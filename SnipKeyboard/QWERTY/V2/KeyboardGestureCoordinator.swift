//
//  KeyboardGestureCoordinator.swift
//  SnipKeyboard
//
//  Single root-level gesture state machine for the V2 keyboard. Owns:
//    • multi-touch press lifecycles (one ActivePress per UITouch)
//    • finger-slide between keys
//    • the highlight overlay (one CAShapeLayer that follows the most-recent finger)
//    • the input callout (single character bubble — shows the most-recent press)
//    • long-press accent menus (per-press timer)
//    • space-bar cursor drag (one finger owns it)
//    • backspace rapid-delete (per-press timer)
//
//  All state transitions happen synchronously on touch events — no SwiftUI in the hot path.
//
//  Phase G: enabled multi-touch + per-touch press state so rolling-typing (overlap between
//  consecutive fingers) doesn't drop characters. UITouch-keyed dictionary tracks each press
//  independently; the shared visuals (callout + highlight) reflect the most-recent active press.
//

import UIKit

// `ResolverTuning` + `KeyboardCadenceTracker` live in V2/ResolverTuning.swift (internal,
// so the calibration replay harness and unit tests can reach them).

final class KeyboardGestureCoordinator: UIView {

    // MARK: - Dependencies

    private weak var state: QWERTYKeyboardState?
    private var actions: KeyboardActions?
    private let calloutController: CalloutController
    private let spaceCursor = SpaceBarCursorController()

    /// Cached "probabilistic touch enabled" setting. The value lives in App Group
    /// UserDefaults (written by the host app's Settings screen) and cannot change while
    /// the user is typing — flipping it requires leaving the keyboard. So we read it once
    /// per keyboard session in `configure(...)` instead of on every character touch-down,
    /// keeping the smart-touch hot path free of repeated settings lookups.
    private var probabilisticTouchEnabled = KeyboardFeatureFlags.probabilisticTouchEnabled

    /// Staged-enablement flag for the 2D power-diagram resolver (V2 next-gen engine).
    /// Cached once per session like `probabilisticTouchEnabled`. When off, the legacy 1D
    /// `SmartTouchResolver` path runs unchanged. See V2_KEYBOARD_NEXTGEN_PLAN.md.
    private var useProbabilisticHitResolver = KeyboardFeatureFlags.useProbabilisticHitResolver

    /// Shadow-mode telemetry: when on, the non-acting resolver is also computed per eligible
    /// touch-down and the comparison logged (privacy-safe). Cached per session.
    private var shadowLoggingEnabled = KeyboardFeatureFlags.shadowLoggingEnabled

    /// Native commit timing (default ON): letters commit on touch-UP / rollover flush like
    /// the system keyboard, enabling slide-to-correct. OFF = legacy optimistic
    /// commit-on-touch-DOWN (DEBUG A/B kill switch). Cached per session.
    private var nativeCommitTiming = KeyboardFeatureFlags.nativeCommitTiming

    /// Tunables for the power-diagram resolver. β stays 0 until calibrated on the touch
    /// corpus; the flag gates activation independently so the path can be exercised first.
    private var probabilisticConfig = ProbabilisticHitResolver.Config.default

    /// Typing-cadence EMA, fed by every touch-down (space/backspace are part of the typing
    /// rhythm; rapid-delete repeats are a single touch-down so they can't spam it). Modulates
    /// β and the anchor zone per tap in `smartResolvedResult` — see `ResolverTuning`.
    private var cadence = KeyboardCadenceTracker()

    /// Debug overlay that paints the next-gen engine's actual decision cells. Shown only when
    /// the hit-overlay setting AND the next-gen engine are both on; recomputed off the hot path.
    private let voronoiDebugLayer = CALayer()

    #if DEBUG
    private static var didRunResolverSelfTest = false
    #endif

    /// Caret-move callback (only used in cursor mode).
    /// Argument: signed character offset to apply.
    var adjustCaret: ((Int) -> Void)?

    // MARK: - Layout / Frames

    private var dims: KeyboardDimensions = KeyboardDimensions(screenWidth: 393)
    private var resolvedFrames: [KeyFrame] = []
    /// Precomputed grid-Voronoi partition of `resolvedFrames` for O(log n) hit resolution.
    /// Rebuilt alongside `resolvedFrames` in `rebuildLayout`; consumed by `findKey`.
    private var hitGrid: HitGrid?
    /// Row count of the current layout — kept so `findKey` can self-heal (rebuild the
    /// grid) if a touch ever arrives before the first `rebuildLayout`.
    private var currentRowCount = 0
    /// Transparent per-key touch targets that tile the entire keys area (one per `KeyFrame`,
    /// sized to its `hitRect`). They guarantee UIKit's native hit-testing finds a key for
    /// EVERY point — including the visual gaps between keys — and forward the touch to this
    /// coordinator. This is the "Voronoi fills the gaps" model: no dead zones by construction.
    private var keyHitViews: [KeyHitView] = []
    private var currentPage: KeyboardPage = .letters

    /// Signature of the inputs that drove the last full `rebuildLayout()`. If the next
    /// call has an identical signature, we skip the expensive layer rebuild — UIKit
    /// can re-invoke `layoutSubviews()` for trait/keyboard-frame events that don't
    /// actually require re-rendering.
    private struct RenderSignature: Equatable {
        let size: CGSize
        let page: KeyboardPage
        let profile: KeyboardLayoutProfile
        let isDark: Bool
        let dims: KeyboardDimensions
        let spaceSubtitle: String?
    }
    private var lastRenderSignature: RenderSignature?

    // MARK: - Touch State

    /// Lifecycle phase of one press. Native commit timing (default): characters are
    /// PENDING from touch-down and commit at lift or when the next finger lands
    /// (rollover flush) — exactly the system keyboard's semantics, which is what makes
    /// slide-to-correct, slide-off-cancel, shift-slide-capital and 123-slide-symbol work.
    enum PressPhase: Equatable {
        /// Character/shortcut key awaiting lift or rollover flush. Highlight + callout
        /// are already visible; nothing has touched the document yet.
        case pendingCharacter
        /// Space / return / snippet toggle (and mode change under legacy timing) —
        /// commit on lift, as they always have.
        case pendingOnLift
        /// Backspace / shift / (native) mode change: primary effect fired at touch-down.
        case actedOnDown
        /// The long-press accent menu owns this press; insert happens via the menu on lift.
        case accentMenu
        /// Rollover-flushed: the character committed while the finger is still down.
        /// Inert — the highlight clears on lift, nothing else can happen.
        case committed
        /// Legacy (kill-switch) timing: character optimistically committed at touch-down.
        /// Locked against retarget, and the accent menu must undo the commit.
        case committedOnDown
        /// Slid onto a down-acting key or otherwise voided — nothing happens on lift.
        /// A further slide onto a character/space revives the press.
        case cancelled
    }

    /// Initial phase for a fresh press. Pure — self-testable.
    static func initialPhase(for action: KeyAction, nativeCommitTiming: Bool) -> PressPhase {
        switch action {
        case .character, .insertText:
            return nativeCommitTiming ? .pendingCharacter : .committedOnDown
        case .backspace, .shift:
            return .actedOnDown
        case .space, .returnKey, .snippetToggle:
            return .pendingOnLift
        case .modeChange:
            // Native: the plane switches at finger-down (enables 123-slide-to-symbol).
            return nativeCommitTiming ? .actedOnDown : .pendingOnLift
        }
    }

    /// Phase after a slide retargets the press onto `action`. Down-acting keys must never
    /// fire from a slide (a slide onto backspace deleting would be catastrophic), so they
    /// void the press; sliding onward can revive it. Pure — self-testable.
    static func phaseAfterRetarget(to action: KeyAction) -> PressPhase {
        switch action {
        case .character, .insertText:
            return .pendingCharacter
        case .space, .returnKey:
            return .pendingOnLift
        case .backspace, .shift, .modeChange, .snippetToggle:
            return .cancelled
        }
    }

    /// Gold-label plausibility gate: a slide-corrected commit teaches the offset model only
    /// when the touch-down point could plausibly have been an aim error at the final key —
    /// within one row and 1.5 key-widths. A cross-keyboard slide is a changed mind, not an
    /// aim error. Pure — self-testable.
    static func isPlausibleAimError(downPoint: CGPoint, downRow: Int, finalKey: KeyFrame) -> Bool {
        guard abs(finalKey.rowIndex - downRow) <= 1 else { return false }
        return abs(finalKey.rect.midX - downPoint.x) <= finalKey.rect.width * 1.5
    }

    /// Per-touch press state. Keyed by `ObjectIdentifier(touch)` so concurrent touches
    /// each get their own key tracking, long-press timer, and rapid-delete timer.
    private struct ActivePress {
        var key: KeyFrame
        /// Hit-grid key at touch-down (pre-resolver) — offset-learning gate input.
        let rawKey: KeyFrame
        /// Action of the down-resolved key, before any slide retarget. Distinguishes
        /// shift-slide / 123-slide commits and keeps mode-slide commits out of the
        /// offset model's gold-label path.
        let originAction: KeyAction
        var startPoint: CGPoint
        var sequence: UInt64
        var phase: PressPhase
        var didSlideOffOriginal: Bool = false
        /// Set when a mid-touch layout swap left `key` referencing the OLD layout's frames
        /// (no action match in the new layout). The next move re-resolves without hysteresis.
        var keyStale: Bool = false
        var longPressTask: Task<Void, Never>? = nil
        var rapidDeleteTask: Task<Void, Never>? = nil
        var rapidDeleteCount: Int = 0
        /// True for the space-bar press that started cursor mode (only one at a time).
        var ownsSpaceCursor: Bool = false
    }

    private var activePresses: [ObjectIdentifier: ActivePress] = [:]
    private var nextPressSequence: UInt64 = 0

    /// The touch most-recently entered into `touchesBegan` (or promoted to most-recent
    /// when a previous most-recent lifted). Drives the shared callout view; pressed
    /// highlights are owned per touch by `KeyLayerRenderer`.
    private var mostRecentTouchID: ObjectIdentifier?

    private let lightImpactHaptic = UIImpactFeedbackGenerator(style: .light)

    // MARK: - Init

    init(state: QWERTYKeyboardState, calloutView: KeyboardCalloutView) {
        self.state = state
        self.calloutController = CalloutController(calloutView: calloutView)
        super.init(frame: .zero)
        backgroundColor = .clear
        // Multi-touch enabled so rolling-type (overlapping fingers) doesn't drop keys.
        isMultipleTouchEnabled = true
        lightImpactHaptic.prepare()

        // Debug Voronoi overlay sits above the key layers. Hidden unless the debug overlay +
        // next-gen engine are on.
        voronoiDebugLayer.isHidden = true
        voronoiDebugLayer.magnificationFilter = .nearest
        voronoiDebugLayer.zPosition = 50
        layer.addSublayer(voronoiDebugLayer)

        // Coord conversions: callout lives on the keyboard's root view, so its
        // `keyFrame:` rect must be in root-view coords (callout's superview).
        // The accent hit-test also uses root-view coords.
        calloutController.convertRect = { [weak self, weak calloutView] rect in
            guard let self, let target = calloutView?.superview else { return rect }
            return self.convert(rect, to: target)
        }
        calloutController.convertPointToCalloutSpace = { [weak self, weak calloutView] point in
            guard let self, let target = calloutView?.superview else { return point }
            return self.convert(point, to: target)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    deinit {
        // Defensive cleanup — if the view is deallocated while presses are still active
        // (e.g., keyboard dismissed mid-typing), cancel all outstanding Tasks so they
        // can't leak past our lifetime. The dictionary itself goes away with `self`.
        for press in activePresses.values {
            press.longPressTask?.cancel()
            press.rapidDeleteTask?.cancel()
        }
        rendererRef.clearAllPressedKeys()
    }

    // MARK: - External Configuration

    func configure(actions: KeyboardActions, dims: KeyboardDimensions) {
        self.actions = actions
        self.dims = dims
        // Refresh cached settings once per keyboard session (this is the cold-start seam).
        probabilisticTouchEnabled = KeyboardFeatureFlags.probabilisticTouchEnabled
        useProbabilisticHitResolver = KeyboardFeatureFlags.useProbabilisticHitResolver
        shadowLoggingEnabled = KeyboardFeatureFlags.shadowLoggingEnabled
        nativeCommitTiming = KeyboardFeatureFlags.nativeCommitTiming
        TypingTelemetry.shared.enabled = shadowLoggingEnabled
        KeyboardResponsivenessTelemetry.shared.enabled = shadowLoggingEnabled
        #if DEBUG
        KeyboardSignposts.enabled = shadowLoggingEnabled
        #endif
        // Per-user offset learning is part of the next-gen engine — on when it is.
        TouchOffsetModel.shared.enabled = useProbabilisticHitResolver
        calloutController.updateParentWidth(bounds.width)

        #if DEBUG
        if !Self.didRunResolverSelfTest {
            Self.didRunResolverSelfTest = true
            ProbabilisticHitResolver.runEquivalenceSelfTest()
            ProbabilisticTouchContext.runContextSelfTest()
            KeyboardCadenceTracker.runCadenceSelfTest()
            TouchOffsetModel.runCrossfadeSelfTest()
            Self.runCommitPhaseSelfTest()
            KeyboardCommitPipeline.runWordDeleteSelfTest()
        }
        #endif
    }

    /// Provide the layout for the current page and rerender.
    func setPage(_ page: KeyboardPage) {
        currentPage = page
        rebuildLayout()
    }

    /// Notify of an appearance change. Re-renders all key backgrounds and updates callout dark mode.
    func setAppearance(isDark: Bool) {
        calloutController.updateAppearance(isDark: isDark)
        rebuildLayout()
    }

    /// Notify of shift state change. Refreshes character casing AND the shift glyph icon.
    /// Does not rebuild the full layout.
    func setShiftState(_ shiftState: ShiftState) {
        rendererRef.updateShiftState(shiftState)
    }

    /// Notify of return-key label change.
    func setReturnKey(label: String, prominent: Bool) {
        let isDark = state?.appearanceMode == .dark
        rendererRef.updateReturnKeyLabel(label, prominent: prominent, isDark: isDark)
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        // Recompute dims for the current width and rebuild layout if size changed
        let newDims = KeyboardDimensions(screenWidth: max(bounds.width, 1))
        if newDims != dims {
            dims = newDims
        }
        rebuildLayout()
        calloutController.updateParentWidth(bounds.width)
    }

    /// Display scale to rasterize glyphs at. `traitCollection.displayScale` is the real
    /// device scale (3.0 on most iPhones) and is correct even inside a keyboard extension —
    /// unlike the host layer's `contentsScale`, which can report 1.0/2.0 and produce blurry
    /// text. Falls back to the window scene's screen scale, then a sensible default.
    private func renderScale() -> CGFloat {
        let s = traitCollection.displayScale
        if s > 0 { return s }
        if let s2 = window?.windowScene?.screen.scale, s2 > 0 { return s2 }
        return 3.0
    }

    private func rebuildLayout() {
        KeyboardSignposts.interval("rebuildLayout") { performRebuildLayout() }
    }

    private func performRebuildLayout() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let isDark = state?.appearanceMode == .dark
        let shiftState = state?.shiftState ?? .disabled
        // Show the "EN ES" locale subtitle only when the user has multiple input modes
        // enabled; otherwise the space bar stays clean. Computed fresh from the host's
        // `UITextInputMode.activeInputModes` each layout pass.
        let codes = actions?.activeInputLocaleCodes() ?? []
        let subtitle: String? = codes.count >= 2 ? codes.joined(separator: " ") : nil

        // Short-circuit if nothing visible has changed since the last rebuild.
        // The cheap updaters (updateShiftState / updateReturnKeyLabel / setPressedKey)
        // already cover diffs that are allowed to bypass a full rebuild.
        let signature = RenderSignature(
            size: bounds.size,
            page: currentPage,
            profile: state?.layoutProfile ?? .standard,
            isDark: isDark,
            dims: dims,
            spaceSubtitle: subtitle
        )
        if signature == lastRenderSignature {
            return
        }
        let sizeChanged = lastRenderSignature.map { $0.size != signature.size } ?? false
        lastRenderSignature = signature

        let layout = KeyboardLayoutFactory.layout(
            for: currentPage,
            profile: state?.layoutProfile ?? .standard,
            dims: dims
        )
        resolvedFrames = KeyboardLayoutResolver.resolve(
            layout: layout,
            dims: dims,
            keysAreaSize: bounds.size
        )
        // Rebuild the hit grid in lockstep with the frames so the two never diverge.
        currentRowCount = layout.rows.count
        hitGrid = Self.buildHitGrid(from: resolvedFrames, rowCount: currentRowCount)

        rendererRef.render(
            frames: resolvedFrames,
            dims: dims,
            isDark: isDark,
            shiftState: shiftState,
            scale: renderScale(),
            spaceBarSubtitle: subtitle
        )

        if let label = state?.returnKeyLabel, let prominent = state?.returnKeyIsProminent {
            rendererRef.updateReturnKeyLabel(label, prominent: prominent, isDark: isDark)
        }

        TouchOffsetModel.shared.currentLayout = currentLayoutHash
        rebuildAccessibilityElements()
        rebuildHitViews()
        updateVoronoiDebugOverlay()

        // Mid-gesture layout changes: a SIZE change (rotation / host height) invalidates
        // every in-flight press geometry — cancel them, exactly as UIKit cancels touches on
        // rotation. A same-size change (page swap, appearance) keeps presses alive: remap
        // their key frames into the new layout and re-apply the per-touch highlights that
        // `render()` just destroyed.
        if sizeChanged {
            cancelAllActivePresses()
        } else {
            remapActivePressesAfterLayoutChange()
        }
    }

    /// Re-anchor in-flight presses after a same-size layout rebuild (page/appearance swap).
    /// Presses whose action exists in the new layout keep tracking seamlessly; the rest are
    /// marked stale so the next move re-resolves without hysteresis.
    private func remapActivePressesAfterLayoutChange() {
        guard !activePresses.isEmpty else { return }
        for (id, press) in activePresses {
            var p = press
            if let match = resolvedFrames.first(where: { $0.action == p.key.action }) {
                p.key = match
                rendererRef.setPressedKey(match, for: id)
            } else {
                p.keyStale = true
                rendererRef.clearPressedKey(for: id)
            }
            activePresses[id] = p
        }
    }

    /// Cancel every in-flight press without committing anything (rotation / teardown).
    private func cancelAllActivePresses() {
        guard !activePresses.isEmpty else { return }
        for (id, press) in activePresses {
            press.longPressTask?.cancel()
            press.rapidDeleteTask?.cancel()
            if press.ownsSpaceCursor { _ = spaceCursor.endPress() }
            rendererRef.clearPressedKey(for: id)
            KeyboardResponsivenessTelemetry.shared.markTouchEnded(id)
        }
        activePresses.removeAll()
        calloutController.dismiss()
        mostRecentTouchID = nil
    }

    /// Paint the next-gen engine's decision cells when both the debug hit-overlay setting and
    /// the engine are enabled. Off the hot path (layout changes only). Hidden otherwise.
    private func updateVoronoiDebugOverlay() {
        let on = useProbabilisticHitResolver && KeyboardFeatureFlags.debugHitOverlayEnabled
        guard on, let state, bounds.width > 1, bounds.height > 1, !resolvedFrames.isEmpty else {
            voronoiDebugLayer.isHidden = true
            voronoiDebugLayer.contents = nil
            return
        }
        let tc = state.inputTracking.touchContext
        // Cadence-neutral boundary: the overlay uses the static config (confidence-scaled
        // only), so it shows the baseline cells — per-tap cadence/fat-touch modulation
        // (ResolverTuning) shifts the live boundary around what's painted here.
        var cfg = probabilisticConfig
        cfg.beta *= tc.confidence
        let image = ProbabilisticHitResolver.debugCellImage(
            frames: resolvedFrames,
            bounds: bounds,
            stepPoints: 6,
            weightFor: { tc.weight(for: $0.first ?? " ") },
            offsetFor: { [weak self] in self?.siteOffset(for: $0) ?? .zero },
            config: cfg
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        voronoiDebugLayer.frame = bounds
        voronoiDebugLayer.contents = image
        voronoiDebugLayer.isHidden = (image == nil)
        CATransaction.commit()
    }

    /// Rebuild the tiling `KeyHitView` touch targets in lockstep with `resolvedFrames`.
    /// Each covers its key's `hitRect`; together they tile the whole keys area with no gaps,
    /// so a touch anywhere, including between keys, lands on a real interactive subview that
    /// forwards to this coordinator. The debug overlay flag only changes their visual styling.
    private func rebuildHitViews() {
        KeyboardSignposts.interval("rebuildHitViews") {
            // Reframe in place when the key count is unchanged (appearance/subtitle/rotation
            // rebuilds): UIView reuse keeps mid-gesture touches flowing to live views and
            // avoids ~35 view alloc/deallocs. Count changes (page switch) rebuild fully.
            if keyHitViews.count == resolvedFrames.count, !keyHitViews.isEmpty {
                for (hv, frame) in zip(keyHitViews, resolvedFrames) {
                    hv.frame = frame.hitRect
                }
                return
            }
            for v in keyHitViews { v.removeFromSuperview() }
            keyHitViews.removeAll(keepingCapacity: true)
            for frame in resolvedFrames {
                let hv = KeyHitView(frame: frame.hitRect)
                hv.coordinator = self
                addSubview(hv)
                keyHitViews.append(hv)
            }
        }
    }

    // MARK: - Accessibility

    /// Rebuild VoiceOver elements so each key is its own focusable, labelled element.
    /// Without this, the entire coordinator reads as one anonymous rectangle.
    private func rebuildAccessibilityElements() {
        let elements: [UIAccessibilityElement] = resolvedFrames.map { frame in
            let element = KeyboardKeyAccessibilityElement(
                container: self,
                key: frame,
                onActivate: { [weak self] in self?.activateKey(frame) }
            )
            element.accessibilityFrameInContainerSpace = frame.rect
            element.accessibilityLabel = accessibilityLabel(for: frame.action)
            element.accessibilityHint = accessibilityHint(for: frame.action)
            element.accessibilityTraits = [.keyboardKey]
            return element
        }
        accessibilityElements = elements
    }

    private func accessibilityLabel(for action: KeyAction) -> String {
        switch action {
        case .character(let c):
            // Use the cased character so VoiceOver reads e.g. "uppercase A".
            let cased = (state?.shiftState ?? .disabled) != .disabled ? c.uppercased() : c.lowercased()
            return cased
        case .insertText(let label, _):
            return label
        case .shift:
            switch state?.shiftState ?? .disabled {
            case .disabled: return "shift"
            case .enabled:  return "shift, enabled"
            case .locked:   return "caps lock"
            }
        case .backspace:        return "delete"
        case .space:            return "space"
        case .returnKey:        return state?.returnKeyLabel ?? "return"
        case .modeChange(let p):
            switch p {
            case .letters: return "letters"
            case .numbers: return "numbers"
            case .symbols: return "symbols"
            }
        case .snippetToggle:    return "snippets"
        }
    }

    private func accessibilityHint(for action: KeyAction) -> String? {
        switch action {
        case .shift:        "Double tap for caps lock"
        case .space:        "Hold and drag to move the cursor"
        case .snippetToggle: "Switch to snippet list"
        default:            nil
        }
    }

    /// Invoked by VoiceOver's "activate" gesture (a double-tap on a key element).
    /// Routes through the same commit pipeline as a normal touch.
    private func activateKey(_ frame: KeyFrame) {
        guard let state = state, let actions = actions else { return }
        switch frame.action {
        case .character(let c):
            KeyboardCommitPipeline.commitCharacter(c, state: state, actions: actions)
        case .insertText(_, let output):
            KeyboardCommitPipeline.commitText(output, state: state, actions: actions)
        case .backspace:
            KeyboardCommitPipeline.commitBackspace(state: state, actions: actions)
        case .space:
            KeyboardCommitPipeline.commitSpace(state: state, actions: actions)
        case .returnKey:
            KeyboardCommitPipeline.commitReturn(state: state, actions: actions)
        case .modeChange(let page):
            KeyboardCommitPipeline.commitModeChange(to: page, state: state, actions: actions)
        case .snippetToggle:
            state.showingSnippets = true
        case .shift:
            state.toggleShift()
            rendererRef.updateShiftState(state.shiftState)
        }
    }

    // MARK: - Touch Routing (multi-touch aware)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            KeyboardSignposts.interval("touchDown") {
                processTouchBegan(touch)
            }
        }
    }

    private func processTouchBegan(_ touch: UITouch) {
        let id = ObjectIdentifier(touch)
        KeyboardResponsivenessTelemetry.shared.markTouchDown(id)
        cadence.registerTouchDown(at: touch.timestamp)
        // Rollover flush (native): a new finger landing commits the previous pending
        // character FIRST — so fast typing loses zero throughput to lift-commit timing,
        // and the bigram/trigram context is exactly as fresh as under commit-on-down
        // when the new touch resolves below.
        flushPendingCharacterPresses()
        let point = touch.location(in: self)
        guard ensureLayoutReadyForTouch(), let rawKey = findKey(at: point) else {
            TypingTelemetry.shared.recordUnresolvedTouchDown(layout: currentLayoutHash)
            return
        }
        let resolved = KeyboardSignposts.interval("resolve") {
            smartResolvedResult(rawKey: rawKey, at: point, radius: touch.majorRadius)
        }
        let key = resolved.key
        TypingTelemetry.shared.recordOutcome(
            layout: currentLayoutHash,
            raw: rawKey,
            resolved: key,
            runnerUp: resolved.runnerUp,
            point: point,
            confidence: state?.inputTracking.touchContext.confidence ?? 0,
            margin: resolved.margin,
            betaMult: KeyboardCadenceTracker.betaMultiplier(forEmaMs: cadence.emaMs)
                * ResolverTuning.fatTouchBetaMultiplier(radius: touch.majorRadius)
        )
        beginPress(touch: touch, key: key, rawKey: rawKey, at: point)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            guard let press = activePresses[id] else { continue }
            // Forward every coalesced sample for presses that can retarget (slide-to-correct
            // tracks the true finger path at 120 Hz on ProMotion) and for the space-cursor
            // owner (sub-frame caret drag). Locked presses keep the single-sample path —
            // they only run slop checks.
            let wantsCoalesced: Bool
            if press.ownsSpaceCursor {
                wantsCoalesced = true
            } else {
                switch press.phase {
                case .pendingCharacter, .pendingOnLift, .cancelled:
                    wantsCoalesced = true
                case .actedOnDown:
                    if case .backspace = press.originAction { wantsCoalesced = false } else { wantsCoalesced = true }
                case .committed, .committedOnDown, .accentMenu:
                    wantsCoalesced = false
                }
            }
            if wantsCoalesced, let coalesced = event?.coalescedTouches(for: touch), !coalesced.isEmpty {
                for sample in coalesced {
                    handleMovedPress(touchID: id, point: sample.location(in: self))
                }
            } else {
                handleMovedPress(touchID: id, point: touch.location(in: self))
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            endPress(touchID: ObjectIdentifier(touch), committed: true)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            endPress(touchID: ObjectIdentifier(touch), committed: false)
        }
    }

    // MARK: - Press Lifecycle (per-touch)

    private func beginPress(touch: UITouch, key: KeyFrame, rawKey: KeyFrame, at point: CGPoint) {
        let id = ObjectIdentifier(touch)
        nextPressSequence &+= 1
        var press = ActivePress(
            key: key,
            rawKey: rawKey,
            originAction: key.action,
            startPoint: point,
            sequence: nextPressSequence,
            phase: Self.initialPhase(for: key.action, nativeCommitTiming: nativeCommitTiming)
        )
        // Make this the most-recent press — drives the shared callout.
        mostRecentTouchID = id

        rendererRef.setPressedKey(key, for: id)
        KeyboardResponsivenessTelemetry.shared.markHighlightApplied(id)
        // No per-press haptic (Phase F). Discrete event haptics (accent-menu, space-cursor)
        // are preserved further below.

        switch key.action {
        case .character(let c):
            // Perceived feedback (highlight above + callout here) fires at touch-down in
            // BOTH timings — that is what defines responsiveness. Under native timing the
            // document insert waits for lift or rollover flush (commitPendingPress).
            let cased = (state?.shiftState ?? .disabled) != .disabled ? c.uppercased() : c.lowercased()
            calloutController.presentInput(for: key, character: cased, casedByShift: false)
            KeyboardResponsivenessTelemetry.shared.markCalloutShown(id)
            if press.phase == .committedOnDown {
                // Legacy kill-switch timing: optimistic commit at finger-down.
                if let state, let actions {
                    KeyboardCommitPipeline.commitCharacter(c, state: state, actions: actions)
                    KeyboardResponsivenessTelemetry.shared.markInsertReturned(id)
                }
                if useProbabilisticHitResolver, currentPage == .letters,
                   shouldLearnTouchOffset(rawKey: rawKey, resolvedKey: key, point: point) {
                    TouchOffsetModel.shared.record(keyFrame: key, point: point,
                                                   keyboardWidth: bounds.width, rowCount: currentRowCount)
                }
            }
            press.longPressTask = scheduleLongPress(touchID: id, key: key)
        case .insertText(_, let output):
            calloutController.dismiss()
            if press.phase == .committedOnDown, let state, let actions {
                KeyboardCommitPipeline.commitText(output, state: state, actions: actions)
                KeyboardResponsivenessTelemetry.shared.markInsertReturned(id)
            }
        case .backspace:
            // Immediate delete on touch-down feels native. Long-press starts rapid-delete.
            commitBackspace()
            // The just-typed character is being deleted — likely an error; don't learn from it.
            TouchOffsetModel.shared.discardPending()
            press.rapidDeleteTask = scheduleRapidDelete(touchID: id)
        case .space:
            // Only one touch can own space-cursor at a time. If another touch is already
            // driving it, leave it alone — this press becomes a normal space tap on lift.
            if !spaceCursor.isActive {
                press.ownsSpaceCursor = true
                spaceCursor.beginPress(at: point, onEngage: { [weak self] in
                    self?.calloutController.dismiss()
                })
            }
        case .shift:
            // Shift triggers on press for snappier feel; double-tap detection happens in state.
            state?.toggleShift()
            rendererRef.updateShiftState(state?.shiftState ?? .disabled)
        case .modeChange(let page):
            if press.phase == .actedOnDown, let state {
                // Native: the plane switches at finger-down so press-slide-release can pick
                // a key from the new page (123-slide-to-symbol). The synchronous setPage
                // skips the withObservationTracking runloop hop; the observation sync that
                // follows is a no-op via the RenderSignature short-circuit.
                KeyboardCommitPipeline.commitModeChange(to: page, state: state)
                setPage(page)
                // The press's key frame belongs to the OLD page. Re-anchor it to whatever
                // now sits under the finger (usually the swapped mode key) so slide
                // hysteresis measures against live geometry.
                if let under = findKey(at: point) {
                    press.key = under
                    rendererRef.setPressedKey(under, for: id)
                }
            }
        case .returnKey, .snippetToggle:
            break  // commit on release for these
        }

        activePresses[id] = press
    }

    /// Commit every press still in `.pendingCharacter`, oldest first (at most one in
    /// practice). Called from `processTouchBegan` BEFORE the new touch resolves, so
    /// context-sensitive resolution sees the freshest character stream.
    private func flushPendingCharacterPresses() {
        guard !activePresses.isEmpty else { return }
        for (id, press) in activePresses.sorted(by: { $0.value.sequence < $1.value.sequence })
        where press.phase == .pendingCharacter {
            var p = press
            p.longPressTask?.cancel()
            p.longPressTask = nil
            commitPendingPress(&p, touchID: id)
            p.phase = .committed
            activePresses[id] = p
        }
    }

    /// The single deferred-commit block, shared by the rollover flush and `endPress`.
    private func commitPendingPress(_ press: inout ActivePress, touchID id: ObjectIdentifier) {
        guard let state, let actions else { return }
        let commitStart = CACurrentMediaTime()
        switch press.key.action {
        case .character(let c):
            KeyboardCommitPipeline.commitCharacter(c, state: state, actions: actions)
            KeyboardResponsivenessTelemetry.shared.markInsertReturned(id)
            KeyboardResponsivenessTelemetry.shared.recordCommitDispatch(startedAt: commitStart)
            learnOffsetIfEligible(for: press)
        case .insertText(_, let output):
            KeyboardCommitPipeline.commitText(output, state: state, actions: actions)
            KeyboardResponsivenessTelemetry.shared.markInsertReturned(id)
            KeyboardResponsivenessTelemetry.shared.recordCommitDispatch(startedAt: commitStart)
        default:
            break
        }
    }

    /// Offset learning at commit time. Non-slid presses go through the standard
    /// anchor/confidence gate with their touch-DOWN geometry. A slid press that committed a
    /// DIFFERENT character key than it resolved at down is a gold label — the user showed us
    /// exactly which key the down-point was aiming at — and bypasses those gates behind the
    /// plausible-aim-error check instead. Mode/shift-origin slides teach nothing (the down
    /// point aimed at the mode/shift key, not the slid-to character).
    private func learnOffsetIfEligible(for press: ActivePress) {
        guard useProbabilisticHitResolver, currentPage == .letters else { return }
        if !press.didSlideOffOriginal {
            if shouldLearnTouchOffset(rawKey: press.rawKey, resolvedKey: press.key, point: press.startPoint) {
                TouchOffsetModel.shared.record(keyFrame: press.key, point: press.startPoint,
                                               keyboardWidth: bounds.width, rowCount: currentRowCount)
            }
        } else if case .character = press.originAction,
                  press.key.isCharacterKey,
                  press.key.action != press.originAction,
                  Self.isPlausibleAimError(downPoint: press.startPoint,
                                           downRow: press.rawKey.rowIndex,
                                           finalKey: press.key) {
            TouchOffsetModel.shared.recordCorrected(keyFrame: press.key, point: press.startPoint,
                                                    keyboardWidth: bounds.width, rowCount: currentRowCount)
            TypingTelemetry.shared.recordSlideCorrection()
        }
    }

    private func handleMovedPress(touchID id: ObjectIdentifier, point: CGPoint) {
        guard var press = activePresses[id] else { return }

        // Off-keyboard drag: dismiss this press's visual state if its finger left the keys
        // area entirely. Other concurrent presses keep working.
        let offKeyboardSlop: CGFloat = 8
        if point.y > bounds.maxY + offKeyboardSlop {
            press.longPressTask?.cancel()
            press.rapidDeleteTask?.cancel()
            if id == mostRecentTouchID {
                calloutController.dismiss()
            }
            rendererRef.clearPressedKey(for: id)
            KeyboardResponsivenessTelemetry.shared.markTouchEnded(id)
            activePresses.removeValue(forKey: id)
            promoteNewMostRecentIfNeeded(removedID: id)
            return
        }

        // Space cursor mode? — purely directional caret adjustment for the owning touch.
        if press.ownsSpaceCursor && spaceCursor.isActive {
            let delta = spaceCursor.updateFinger(at: point, onEngage: { [weak self] in
                self?.calloutController.dismiss()
            })
            if delta != 0 { adjustCaret?(delta) }
            return
        } else if press.ownsSpaceCursor {
            // Still on space, not yet engaged — see if the drag should engage cursor mode.
            _ = spaceCursor.updateFinger(at: point, onEngage: { [weak self] in
                self?.calloutController.dismiss()
                if var p = self?.activePresses[id] {
                    p.longPressTask?.cancel()
                    p.longPressTask = nil
                    self?.activePresses[id] = p
                }
            })
            return
        }

        // Action menu drag (only when THIS touch is in actions mode — i.e. it was the
        // most-recent press when the long-press timer fired). The callout view is shared,
        // so accent selection is gated on the most-recent press driving it.
        if id == mostRecentTouchID, case .actions = calloutController.mode {
            calloutController.updateAccentSelection(fingerPoint: point)
            return
        }

        // Locked phases: rollover-flushed, legacy commit-on-down, accent-menu-owned, and
        // backspace-origin presses never retarget. Movement may cancel held timers
        // (accent menu scheduling / rapid delete), nothing else.
        let locked: Bool
        switch press.phase {
        case .committed, .committedOnDown, .accentMenu:
            locked = true
        case .actedOnDown:
            // Shift/mode-origin presses stay live so press-slide-release works
            // (shift-slide-capital, 123-slide-symbol); backspace stays locked.
            if case .backspace = press.originAction { locked = true } else { locked = false }
        case .pendingCharacter, .pendingOnLift, .cancelled:
            locked = false
        }
        if locked {
            let cancelSlop: CGFloat = 8
            if !press.key.hitRect.insetBy(dx: -cancelSlop, dy: -cancelSlop).contains(point) {
                press.longPressTask?.cancel()
                press.longPressTask = nil
                press.rapidDeleteTask?.cancel()
                press.rapidDeleteTask = nil
            }
            activePresses[id] = press
            return
        }

        // Finger-slide retarget. RAW geometry on purpose: a slide is visually targeted —
        // the user is looking at the key — so the language prior must not fight the finger
        // (native retargeting is geometric too).
        guard let rawNewKey = findKey(at: point) else { return }
        let newKey = rawNewKey
        if press.keyStale {
            // Mid-touch layout swap left `key` on the old layout — re-anchor without
            // hysteresis (the old rect can't be compared against live geometry).
            press.keyStale = false
            if newKey == press.key {
                activePresses[id] = press
                return
            }
        } else {
            guard newKey != press.key else { return }

            // Touch hysteresis: require the finger to move at least 12pt past the boundary
            // into the new key's rect before swapping. Prevents callout flicker / wrong-key
            // commits when a finger wobbles around a key boundary during a fast slide —
            // matches native iOS "sticky" feel.
            let hysteresisDistance: CGFloat = 12
            let oldRect = press.key.rect
            let newRect = newKey.rect
            let pastBoundary: CGFloat
            if newRect.midX > oldRect.midX {
                // Sliding right: boundary is between oldRect.maxX and newRect.minX.
                pastBoundary = point.x - max(oldRect.maxX, newRect.minX)
            } else if newRect.midX < oldRect.midX {
                // Sliding left.
                pastBoundary = min(oldRect.minX, newRect.maxX) - point.x
            } else {
                // Vertical slide (different row) — don't apply horizontal hysteresis.
                pastBoundary = hysteresisDistance
            }
            if pastBoundary < hysteresisDistance { return }
        }

        press.longPressTask?.cancel()
        press.longPressTask = nil
        press.rapidDeleteTask?.cancel()
        press.rapidDeleteTask = nil
        press.key = newKey
        press.didSlideOffOriginal = true
        press.phase = Self.phaseAfterRetarget(to: newKey.action)

        // Refresh shared visuals only if this touch is the current most-recent — keeps the
        // highlight/callout from flickering when a less-recent finger slides.
        rendererRef.setPressedKey(newKey, for: id)
        if id == mostRecentTouchID {
            switch newKey.action {
            case .character(let c):
                let cased = (state?.shiftState ?? .disabled) != .disabled ? c.uppercased() : c.lowercased()
                calloutController.presentInput(for: newKey, character: cased, casedByShift: false, slide: true)
            default:
                calloutController.dismiss()
            }
        }

        // Long-press timer only relevant for character keys (accent menu).
        if case .character = newKey.action {
            press.longPressTask = scheduleLongPress(touchID: id, key: newKey)
        }
        activePresses[id] = press
    }

    private func endPress(touchID id: ObjectIdentifier, committed: Bool) {
        guard var press = activePresses.removeValue(forKey: id) else { return }
        press.longPressTask?.cancel()
        press.rapidDeleteTask?.cancel()
        rendererRef.clearPressedKey(for: id)

        // Space-cursor mode: if this press owned it, end cursor mode and suppress space.
        var spaceCursorWasEngaged = false
        if press.ownsSpaceCursor {
            spaceCursorWasEngaged = spaceCursor.endPress()
        }

        // Accent-menu commit: only relevant when THIS touch was driving the most-recent
        // accent menu (callout view is shared). Commit the selected accent on lift.
        var accentInserted = false
        if id == mostRecentTouchID, case .actions(_, _, _) = calloutController.mode {
            if committed, let selected = calloutController.commitActions(), let state = state, let actions = actions {
                actions.insertCharacter(selected)
                state.inputTracking.recordAction(.character)
                if selected.count == 1, let scalar = selected.first, scalar.isLetter {
                    state.inputTracking.touchContext.recordCharacter(scalar)
                } else {
                    state.inputTracking.touchContext.recordNonCharacter()
                }
                state.handleShiftAfterCharacter()
                actions.scheduleSideEffects()
                accentInserted = true
            }
        }

        // Touch-up commit, by phase. A system cancel (`committed == false`) drops a pending
        // character silently — native-identical semantics.
        if committed && !accentInserted, let state = state, let actions = actions {
            switch press.phase {
            case .pendingCharacter:
                commitPendingPress(&press, touchID: id)
                // 123-slide-release: after committing the slid-to key, snap back to letters
                // (native plane-peek). A plain mode tap (no slide) stays on the new page.
                if case .modeChange = press.originAction, press.didSlideOffOriginal,
                   state.currentPage != .letters {
                    KeyboardCommitPipeline.commitModeChange(to: .letters, state: state)
                    setPage(.letters)
                }
            case .pendingOnLift:
                switch press.key.action {
                case .space:
                    // If this press owned cursor mode and cursor engaged, suppress the space.
                    if !spaceCursorWasEngaged {
                        KeyboardCommitPipeline.commitSpace(state: state, actions: actions)
                    }
                case .returnKey:
                    KeyboardCommitPipeline.commitReturn(state: state, actions: actions)
                case .modeChange(let page):
                    // Legacy timing only — native switches the plane at touch-down.
                    KeyboardCommitPipeline.commitModeChange(to: page, state: state, actions: actions)
                case .snippetToggle:
                    state.showingSnippets = true
                default:
                    break
                }
            case .actedOnDown, .committed, .committedOnDown, .accentMenu, .cancelled:
                break
            }
        }

        KeyboardResponsivenessTelemetry.shared.markTouchEnded(id)

        // Visual cleanup: only dismiss the shared callout/highlight when no other press
        // remains. Otherwise promote the next-most-recent press to drive the visuals.
        if id == mostRecentTouchID {
            calloutController.dismiss()
            promoteNewMostRecentIfNeeded(removedID: id)
        }
    }

    /// When a press is removed, choose the newest remaining touch and refresh the shared callout
    /// to reflect it. Per-key pressed highlights remain owned by each active touch. Only a press
    /// still awaiting its character (`.pendingCharacter`) may resurrect the balloon — a
    /// rollover-flushed or cancelled press must not — and never while the accent menu owns it.
    private func promoteNewMostRecentIfNeeded(removedID: ObjectIdentifier) {
        if let next = activePresses.max(by: { $0.value.sequence < $1.value.sequence }) {
            let nextID = next.key
            let nextPress = next.value
            mostRecentTouchID = nextID
            if case .actions = calloutController.mode { return }
            let showsCallout = nextPress.phase == .pendingCharacter || nextPress.phase == .committedOnDown
            if showsCallout, case .character(let c) = nextPress.key.action {
                let cased = (state?.shiftState ?? .disabled) != .disabled ? c.uppercased() : c.lowercased()
                calloutController.presentInput(for: nextPress.key, character: cased, casedByShift: false)
            }
        } else {
            mostRecentTouchID = nil
        }
    }

    // MARK: - Hit Testing

    /// Guarantee every in-bounds point lands on a tiling `KeyHitView` (which forwards the
    /// touch to this coordinator), even if the default traversal drops the transparent cells
    /// in the keyboard-extension hit-test context. Zero visual change.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if let hit, hit !== self { return hit }           // a debug hit cell or other subview caught it
        guard bounds.contains(point) else { return hit }  // outside the keys area → leave as-is
        if keyHitViews.isEmpty { return self }
        for hv in keyHitViews where hv.frame.contains(point) { return hv }
        return self
    }

    /// Stable hash of the current geometry {page, profile, rounded keys-area width}. Distinguishes
    /// portrait/landscape/host-height layouts so learned offsets and telemetry don't mix.
    private var currentLayoutHash: Int {
        let profile = state?.layoutProfile ?? .standard
        return (currentPage.hashValue &* 31 &+ profile.hashValue) &* 31 &+ Int(bounds.width.rounded())
    }

    /// Combined per-key site offset: the learned per-user model crossfaded with the population
    /// cold-start baseline (see `TouchOffsetModel.offset`). Used by both the live resolver and
    /// the debug overlay so they never diverge.
    private func siteOffset(for frame: KeyFrame) -> CGVector {
        TouchOffsetModel.shared.offset(for: frame, keyboardWidth: bounds.width, rowCount: currentRowCount)
    }

    /// Make the first real touch after mount/profile/page changes self-heal if UIKit delivers it
    /// before `layoutSubviews` has produced frames. This should be rare, but a dropped first press
    /// feels exactly like a missed native-keyboard key.
    private func ensureLayoutReadyForTouch() -> Bool {
        if !resolvedFrames.isEmpty, hitGrid != nil { return true }
        rebuildLayout()
        return !resolvedFrames.isEmpty
    }

    private func shouldLearnTouchOffset(rawKey: KeyFrame, resolvedKey: KeyFrame, point: CGPoint) -> Bool {
        guard rawKey.isCharacterKey, resolvedKey.isCharacterKey else { return false }
        guard rawKey.rowIndex == resolvedKey.rowIndex else { return false }
        guard (state?.inputTracking.touchContext.confidence ?? 0) >= 0.35 else { return false }
        if rawKey.action == resolvedKey.action { return true }
        // Deliberately the STATIC config — offset learning must never get more permissive
        // when the burst anchor-shrink is active (ResolverTuning), or sloppy-burst taps
        // would feed the offset model.
        let cfg = probabilisticConfig
        let anchor = rawKey.rect.insetBy(
            dx: rawKey.rect.width * (1 - cfg.anchorFracW) / 2,
            dy: rawKey.rect.height * (1 - cfg.anchorFracH) / 2
        )
        return anchor.contains(point)
    }

    private struct SmartResolvedResult {
        let key: KeyFrame
        let runnerUp: KeyFrame?
        let margin: Float?
    }

    private func smartResolvedResult(rawKey: KeyFrame, at point: CGPoint, radius: CGFloat = 0) -> SmartResolvedResult {
        guard let state else { return SmartResolvedResult(key: rawKey, runnerUp: nil, margin: nil) }
        guard probabilisticTouchEnabled else {
            return SmartResolvedResult(key: rawKey, runnerUp: nil, margin: nil)
        }

        // 2D power-diagram engine (V2 next-gen), gated to the letters page and fields that
        // allow smart transforms (excludes URL/email/number pads). Non-letters pages and
        // opted-out fields fall through to the legacy 1D path, which itself no-ops for
        // non-character keys. Symbols/number keys carry no meaningful English language prior.
        let touchContext = state.inputTracking.touchContext
        let allowsTransforms = actions?.inputTraits().allowsSmartTransforms ?? true
        // Eligible = a character key on the letters page in a smart-transform field. Only
        // these get the language-prior engine (symbols/number keys carry no English prior).
        let eligible = rawKey.isCharacterKey && currentPage == .letters && allowsTransforms

        func newEngine() -> ProbabilisticHitResolver.Result {
            // Dynamic λ: scale the language pull by how confident the context is (word-start
            // taps lean on geometry, mid-word taps get the full prior) AND by typing cadence
            // (sustained fast bursts lean harder on the prior; slow deliberate taps resolve
            // almost purely geometrically — native feel). Composed and clamped here; the
            // resolver math itself is untouched.
            var cfg = probabilisticConfig
            let cadenceMult = KeyboardCadenceTracker.betaMultiplier(forEmaMs: cadence.emaMs)
            // Fat touch: a large contact patch means the centroid is less trustworthy —
            // lean a bit harder on the prior (σ-scaling expressed as a β multiplier).
            let fatMult = ResolverTuning.fatTouchBetaMultiplier(radius: radius)
            cfg.beta = min(cfg.beta * touchContext.confidence * cadenceMult * fatMult,
                           ResolverTuning.betaCeiling)
            // During sustained bursts, shrink the prior-immune anchor zone (60%×70% →
            // 50%×60% at full burst) so the prior can rescue sloppier taps. Dead-center
            // taps stay immune; slow taps keep the full anchor (shrink only when mult > 1).
            let shrinkT = CGFloat(max(0, min(1, (cadenceMult - 1) / (ResolverTuning.cadenceMultMax - 1))))
            cfg.anchorFracW -= ResolverTuning.anchorShrinkMaxW * shrinkT
            cfg.anchorFracH -= ResolverTuning.anchorShrinkMaxH * shrinkT
            return ProbabilisticHitResolver.resolveWithCandidates(
                rawKey: rawKey,
                point: point,
                frames: probabilisticCandidateFrames(for: rawKey),
                weightFor: { str in touchContext.weight(for: str.first ?? " ") },
                offsetFor: { [weak self] in self?.siteOffset(for: $0) ?? .zero },
                config: cfg
            )
        }
        func legacy() -> KeyFrame {
            SmartTouchResolver.resolve(
                rawKey: rawKey,
                point: point,
                enabled: probabilisticTouchEnabled,
                frames: resolvedFrames,
                touchContext: touchContext,
                dims: dims
            )
        }

        // Acting resolver — what actually commits. New engine only when its flag is on AND
        // the touch is eligible; otherwise the legacy 1D path (unchanged).
        let actingResult: SmartResolvedResult
        if useProbabilisticHitResolver && eligible {
            let result = newEngine()
            actingResult = SmartResolvedResult(
                key: result.winner,
                runnerUp: result.runnerUp,
                margin: result.runnerUp == nil ? nil : result.margin
            )
        } else {
            actingResult = SmartResolvedResult(key: legacy(), runnerUp: nil, margin: nil)
        }

        // Shadow mode: compute the OTHER resolver too (only when eligible) and log the
        // comparison without affecting what commits. The shadow cost is paid only when
        // shadow logging is on.
        if shadowLoggingEnabled, eligible {
            let shadow: KeyFrame = useProbabilisticHitResolver ? legacy() : newEngine().winner
            TypingTelemetry.shared.record(layout: currentLayoutHash, acting: actingResult.key, shadow: shadow, point: point)
        }

        return actingResult
    }

    /// The 2D engine is allowed to correct vertical near-misses, so it scores the raw row plus
    /// adjacent letter rows. Non-letter pages still use the legacy same-row path.
    private func probabilisticCandidateFrames(for rawKey: KeyFrame) -> [KeyFrame] {
        resolvedFrames.filter {
            $0.isCharacterKey && abs($0.rowIndex - rawKey.rowIndex) <= 1
        }
    }

    private func findKey(at point: CGPoint) -> KeyFrame? {
        guard !resolvedFrames.isEmpty else { return nil }
        // A delivered touch is by definition inside the view, so it must always resolve
        // to a key — there are no dead dividers between keys. Resolve via the precomputed
        // hit-cell partition ("owning hit cell wins" — the same tiling the user sees).
        // Self-heal: a touch can arrive before the first layout pass built the grid.
        if hitGrid == nil {
            hitGrid = Self.buildHitGrid(from: resolvedFrames, rowCount: max(currentRowCount, 1))
        }
        if let grid = hitGrid {
            let idx = grid.frameIndex(for: point)
            if idx >= 0 && idx < resolvedFrames.count { return resolvedFrames[idx] }
        }
        // Defensive fallback, only if the grid is somehow unavailable. Prefer the hit cell
        // that contains the point (consistent with the grid's hitRect tiling); otherwise
        // fall back to the nearest key center by squared distance so a delivered touch
        // never resolves to nothing. Off-keyboard drag is handled earlier in
        // handleMovedPress (point.y > bounds.maxY + 8), before findKey is ever reached.
        if let owner = resolvedFrames.first(where: { $0.hitRect.contains(point) }) { return owner }
        var bestSq = CGFloat.greatestFiniteMagnitude
        var best: KeyFrame?
        for f in resolvedFrames {
            let dx = point.x - f.rect.midX
            let dy = point.y - f.rect.midY
            let d = dx * dx + dy * dy
            if d < bestSq { bestSq = d; best = f }
        }
        return best
    }

    /// Build the hit-cell partition from row-major `frames`. Boundaries are the seams of the
    /// per-key `hitRect`s — the exact tiling the user sees (debug overlay) and that the
    /// `KeyHitView` touch targets cover — so a touch resolves to whichever key's hit cell
    /// owns the point. Keys form clean rows with monotonic-x hit cells that tile with no
    /// gaps, so the partition is a rectangular grid: row bands at the seam between
    /// vertically-adjacent rows, per-row column boundaries at the seam between adjacent keys.
    /// Using `hitRect` seams (not key centers) is what lets a wide space next to a narrow
    /// return split at the visual gap instead of deep inside the space bar. O(n), off the
    /// touch path (layout changes only).
    private static func buildHitGrid(from frames: [KeyFrame], rowCount: Int) -> HitGrid {
        guard rowCount > 0, !frames.isEmpty else {
            return HitGrid(rowYBoundaries: [], rowFrameIndices: [[]], rowXBoundaries: [[]])
        }
        var rowFrameIndices = Array(repeating: [Int](), count: rowCount)
        for (i, f) in frames.enumerated() where f.rowIndex >= 0 && f.rowIndex < rowCount {
            rowFrameIndices[f.rowIndex].append(i)   // frames are row-major → already L→R
        }
        // Row Y boundaries: seam between vertically-adjacent rows' hit cells.
        let rowYBoundaries: [CGFloat] = rowCount > 1
            ? (1..<rowCount).map { r -> CGFloat in
                let upper = rowFrameIndices[r - 1].first.map { frames[$0].hitRect.maxY } ?? 0
                let lower = rowFrameIndices[r].first.map { frames[$0].hitRect.minY } ?? 0
                return (upper + lower) / 2
              }
            : []
        // Per-row column boundaries: seam between horizontally-adjacent keys' hit cells.
        let rowXBoundaries: [[CGFloat]] = (0..<rowCount).map { r in
            let idxs = rowFrameIndices[r]
            guard idxs.count > 1 else { return [] }
            return (1..<idxs.count).map {
                (frames[idxs[$0 - 1]].hitRect.maxX + frames[idxs[$0]].hitRect.minX) / 2
            }
        }
        return HitGrid(rowYBoundaries: rowYBoundaries, rowFrameIndices: rowFrameIndices, rowXBoundaries: rowXBoundaries)
    }

    /// Precomputed grid-Voronoi partition of the keys area for O(log n) hit resolution.
    /// Tiles the whole plane → every tap resolves to a key (no dead dividers); edge cells
    /// extend outward so edge keys claim the margins. Never mutated on the touch path.
    private struct HitGrid {
        let rowYBoundaries: [CGFloat]     // ascending; count = rowCount - 1
        let rowFrameIndices: [[Int]]      // per row, indices into resolvedFrames, left→right
        let rowXBoundaries: [[CGFloat]]   // per row, ascending; count = keysInRow - 1

        /// `resolvedFrames` index owning `point`. Never out of range — clamps at the extremes.
        func frameIndex(for point: CGPoint) -> Int {
            let row = min(Self.bucket(point.y, rowYBoundaries), rowFrameIndices.count - 1)
            let cols = rowFrameIndices[row]
            guard !cols.isEmpty else { return 0 }
            let col = min(Self.bucket(point.x, rowXBoundaries[row]), cols.count - 1)
            return cols[col]
        }

        /// Band index for `v` given ascending interior boundaries (binary search, clamped).
        static func bucket(_ v: CGFloat, _ boundaries: [CGFloat]) -> Int {
            var lo = 0, hi = boundaries.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if v < boundaries[mid] { hi = mid } else { lo = mid + 1 }
            }
            return lo
        }
    }

    // MARK: - Long-Press (per-touch)

    /// Create a task that opens the accent menu after 400ms iff the press is still on `key`.
    /// Returns the task so it can be stored on the `ActivePress` and cancelled if needed.
    private func scheduleLongPress(touchID id: ObjectIdentifier, key: KeyFrame) -> Task<Void, Never>? {
        guard case .character(let c) = key.action else { return nil }
        // In URL / email fields, long-pressing "." offers domain TLDs (.com, .net, …),
        // matching native iOS. Everywhere else, "." shows its normal accent menu (ellipsis).
        let menu: [String]?
        if c == ".", let kt = actions?.inputTraits().keyboardType, kt == .URL || kt == .emailAddress {
            menu = AccentMap.domainMenu()
        } else {
            menu = AccentMap.menu(for: c, uppercased: (state?.shiftState ?? .disabled) != .disabled)
        }
        guard let menu else { return nil }
        return Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            // Make sure this press is still alive, still on the same key, and still able to
            // own the menu. A rollover-flushed press (.committed) can't — its character is
            // final, exactly like native.
            guard var press = self.activePresses[id], press.key == key,
                  press.phase == .pendingCharacter || press.phase == .committedOnDown else { return }
            if press.phase == .committedOnDown {
                // Legacy timing only: the character was optimistically committed at
                // touch-down — undo it so the accent insertion replaces it cleanly. Under
                // native timing nothing has been committed, so there is nothing to undo
                // (no ghost character flicker in the host field).
                self.actions?.deleteBackward()
                TouchOffsetModel.shared.discardPending()
                self.state?.inputTracking.recordAction(.other)
            }
            press.phase = .accentMenu
            self.activePresses[id] = press
            // Accent menu becomes the visual focus — promote this touch to most-recent.
            self.mostRecentTouchID = id
            self.calloutController.beginActions(for: key, items: menu)
            self.lightImpactHaptic.impactOccurred(intensity: 0.8)
        }
    }

    // MARK: - Backspace Rapid Delete (per-touch)

    private func scheduleRapidDelete(touchID id: ObjectIdentifier) -> Task<Void, Never>? {
        let native = nativeCommitTiming
        return Task { @MainActor [weak self] in
            // The first delete already fired on touch-down (instant). Native pacing:
            // ~500ms initial delay, then ~100ms per character for ~1.5s, then whole-WORD
            // chunks at ~350ms — the escalation every native user's muscle memory expects.
            // Legacy (kill switch): the old accelerating 1→2→3-char burst ramp.
            try? await Task.sleep(for: .milliseconds(native ? 500 : 350))
            while !Task.isCancelled {
                guard let self, var press = self.activePresses[id] else { return }
                press.rapidDeleteCount += 1
                let count = press.rapidDeleteCount
                if native {
                    if count <= 15 {
                        self.commitBackspace()
                        self.activePresses[id] = press
                        try? await Task.sleep(for: .milliseconds(100))
                    } else {
                        let deleted = self.commitWordBackspace()
                        self.activePresses[id] = press
                        // A single-char fallback tick (empty/unavailable context) keeps the
                        // fast cadence so held-backspace never crawls or stalls.
                        try? await Task.sleep(for: .milliseconds(deleted > 1 ? 350 : 100))
                    }
                } else {
                    // Delete more per tick the longer you hold (1 → 2 → 3 chars).
                    let burst = count < 6 ? 1 : (count < 16 ? 2 : 3)
                    for _ in 0..<burst { self.commitBackspace() }
                    self.activePresses[id] = press
                    // Interval ramps from ~110ms down to ~45ms as the hold continues.
                    let interval = max(45, 110 - count * 6)
                    try? await Task.sleep(for: .milliseconds(interval))
                }
            }
        }
    }

    private func commitBackspace() {
        guard let state = state, let actions = actions else { return }
        KeyboardCommitPipeline.commitBackspace(state: state, actions: actions)
    }

    /// One word-tier backspace tick. Returns how many deletions were performed.
    private func commitWordBackspace() -> Int {
        guard let state = state, let actions = actions else { return 0 }
        return KeyboardCommitPipeline.commitWordBackspace(state: state, actions: actions)
    }

    // MARK: - Renderer

    /// CALayer renderer pinned to this view's own layer. Built lazily on first access so
    /// `self.layer` is available — UIView's `layer` cannot be read during super.init.
    private lazy var rendererRef: KeyLayerRenderer = KeyLayerRenderer(hostLayer: layer)
}

// MARK: - Accessibility Element

/// VoiceOver-focusable element representing a single keyboard key.
/// Routes the "activate" gesture (double-tap in VoiceOver) back into the commit pipeline.
private final class KeyboardKeyAccessibilityElement: UIAccessibilityElement {
    let key: KeyFrame
    private let onActivate: () -> Void

    init(container: Any, key: KeyFrame, onActivate: @escaping () -> Void) {
        self.key = key
        self.onActivate = onActivate
        super.init(accessibilityContainer: container)
    }

    override func accessibilityActivate() -> Bool {
        onActivate()
        return true
    }
}

/// Transparent, tiling touch target placed over each key's `hitRect`. It has no logic of its
/// own — it exists so UIKit's native hit-testing always finds a real interactive view for
/// every point in the keys area (gaps included), then forwards the touch to the gesture
/// coordinator, which resolves and commits it exactly as if it had received the touch directly.
#if DEBUG
extension KeyboardGestureCoordinator {
    /// Invariant check for the press-phase state machine tables: initial phase per action
    /// under both commit timings, retarget mapping, and the gold-label plausibility gate.
    /// Returns violations so XCTest can assert; the runtime wrapper logs (does not crash).
    static func commitPhaseSelfTestFailures() -> [String] {
        var failures: [String] = []

        // Initial phase — native timing.
        let nativeExpectations: [(KeyAction, PressPhase)] = [
            (.character("a"), .pendingCharacter),
            (.insertText(label: "@", output: "@"), .pendingCharacter),
            (.backspace, .actedOnDown),
            (.shift, .actedOnDown),
            (.space, .pendingOnLift),
            (.returnKey, .pendingOnLift),
            (.snippetToggle, .pendingOnLift),
            (.modeChange(.numbers), .actedOnDown),
        ]
        for (action, expected) in nativeExpectations
        where initialPhase(for: action, nativeCommitTiming: true) != expected {
            failures.append("native initialPhase(\(action)) != \(expected)")
        }

        // Initial phase — legacy timing: characters commit on down; mode changes on lift.
        let legacyExpectations: [(KeyAction, PressPhase)] = [
            (.character("a"), .committedOnDown),
            (.insertText(label: "@", output: "@"), .committedOnDown),
            (.backspace, .actedOnDown),
            (.shift, .actedOnDown),
            (.space, .pendingOnLift),
            (.returnKey, .pendingOnLift),
            (.snippetToggle, .pendingOnLift),
            (.modeChange(.numbers), .pendingOnLift),
        ]
        for (action, expected) in legacyExpectations
        where initialPhase(for: action, nativeCommitTiming: false) != expected {
            failures.append("legacy initialPhase(\(action)) != \(expected)")
        }

        // Retarget mapping: characters revive, space/return defer, down-acting keys void.
        let retargetExpectations: [(KeyAction, PressPhase)] = [
            (.character("a"), .pendingCharacter),
            (.insertText(label: ".com", output: ".com"), .pendingCharacter),
            (.space, .pendingOnLift),
            (.returnKey, .pendingOnLift),
            (.backspace, .cancelled),
            (.shift, .cancelled),
            (.modeChange(.symbols), .cancelled),
            (.snippetToggle, .cancelled),
        ]
        for (action, expected) in retargetExpectations
        where phaseAfterRetarget(to: action) != expected {
            failures.append("phaseAfterRetarget(\(action)) != \(expected)")
        }
        // A retarget must never fabricate a down-acting or terminal phase.
        for action: KeyAction in [.character("z"), .space, .backspace, .shift,
                                  .modeChange(.letters), .snippetToggle, .returnKey] {
            let p = phaseAfterRetarget(to: action)
            if p == .actedOnDown || p == .committed || p == .committedOnDown || p == .accentMenu {
                failures.append("phaseAfterRetarget(\(action)) produced illegal phase \(p)")
            }
        }

        // Gold-label plausibility gate.
        let keyRect = CGRect(x: 100, y: 50, width: 40, height: 44)
        let finalKey = KeyFrame(action: .character("k"), rect: keyRect, hitRect: keyRect,
                                rowIndex: 1, columnIndex: 5, isCharacterKey: true)
        // Adjacent-key mis-tap (one key width away, same row) — plausible.
        if !isPlausibleAimError(downPoint: CGPoint(x: 160, y: 72), downRow: 1, finalKey: finalKey) {
            failures.append("adjacent mis-tap rejected by gold-label gate")
        }
        // Cross-keyboard slide (far away) — a changed mind, not an aim error.
        if isPlausibleAimError(downPoint: CGPoint(x: 300, y: 72), downRow: 1, finalKey: finalKey) {
            failures.append("cross-keyboard slide accepted by gold-label gate")
        }
        // Two rows away — rejected.
        if isPlausibleAimError(downPoint: CGPoint(x: 120, y: 72), downRow: 3, finalKey: finalKey) {
            failures.append("two-row slide accepted by gold-label gate")
        }
        return failures
    }

    /// One-time runtime wrapper — logs instead of crashing, keyboard-extension safe.
    static func runCommitPhaseSelfTest() {
        let failures = commitPhaseSelfTestFailures()
        if failures.isEmpty {
            NSLog("[SnipKeyboard] commit-phase self-test passed")
        } else {
            for f in failures { NSLog("[SnipKeyboard] commit-phase SELF-TEST FAILED: %@", f) }
        }
    }
}
#endif

final class KeyHitView: UIView {
    weak var coordinator: KeyboardGestureCoordinator?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        // NOT `.clear`: a fully transparent view is skipped by hit-testing in the keyboard
        // extension's rendering context (verified — gap/edge presses only registered once the
        // debug overlay gave the cells a visible fill). A ~2% neutral fill is imperceptible on
        // both light and dark keyboards but keeps the cell hit-testable.
        backgroundColor = UIColor(white: 0, alpha: 0.02)
        // VoiceOver still navigates via the coordinator's accessibility elements.
        isAccessibilityElement = false

        // DEBUG overlay (off by default): visualize the tiling touch cells (each = one key's
        // hitRect) so the per-key "Voronoi" coverage of the gaps can be inspected. Toggled
        // from the app: SnipKey Settings → Experimental → "Show Hit-Test Overlay".
        if KeyboardFeatureFlags.debugHitOverlayEnabled {
            layer.borderColor = UIColor.systemRed.withAlphaComponent(0.9).cgColor
            layer.borderWidth = 1
            backgroundColor = UIColor.systemRed.withAlphaComponent(0.08)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        coordinator?.touchesBegan(touches, with: event)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        coordinator?.touchesMoved(touches, with: event)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        coordinator?.touchesEnded(touches, with: event)
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        coordinator?.touchesCancelled(touches, with: event)
    }
}

