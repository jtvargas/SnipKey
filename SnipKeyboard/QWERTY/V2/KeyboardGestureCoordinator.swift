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

final class KeyboardGestureCoordinator: UIView {

    // MARK: - Dependencies

    private weak var state: QWERTYKeyboardState?
    private var actions: KeyboardActions?
    private let calloutController: CalloutController
    private let spaceCursor = SpaceBarCursorController()

    /// Caret-move callback (only used in cursor mode).
    /// Argument: signed character offset to apply.
    var adjustCaret: ((Int) -> Void)?

    // MARK: - Layout / Frames

    private var dims: KeyboardDimensions = KeyboardDimensions(screenWidth: 393)
    private var resolvedFrames: [KeyFrame] = []
    /// Precomputed grid-Voronoi partition of `resolvedFrames` for O(log n) hit resolution.
    /// Rebuilt alongside `resolvedFrames` in `rebuildLayout`; consumed by `findKey`.
    private var hitGrid: HitGrid?
    private var currentPage: KeyboardPage = .letters

    /// Signature of the inputs that drove the last full `rebuildLayout()`. If the next
    /// call has an identical signature, we skip the expensive layer rebuild — UIKit
    /// can re-invoke `layoutSubviews()` for trait/keyboard-frame events that don't
    /// actually require re-rendering.
    private struct RenderSignature: Equatable {
        let size: CGSize
        let page: KeyboardPage
        let isDark: Bool
        let dims: KeyboardDimensions
        let spaceSubtitle: String?
    }
    private var lastRenderSignature: RenderSignature?

    // MARK: - Touch State

    /// Per-touch press state. Keyed by `ObjectIdentifier(touch)` so concurrent touches
    /// each get their own key tracking, long-press timer, and rapid-delete timer.
    private struct ActivePress {
        var key: KeyFrame
        var startPoint: CGPoint
        var didSlideOffOriginal: Bool = false
        var longPressTask: Task<Void, Never>? = nil
        var rapidDeleteTask: Task<Void, Never>? = nil
        var rapidDeleteCount: Int = 0
        /// True for the space-bar press that started cursor mode (only one at a time).
        var ownsSpaceCursor: Bool = false
    }

    private var activePresses: [ObjectIdentifier: ActivePress] = [:]

    /// The touch most-recently entered into `touchesBegan` (or promoted to most-recent
    /// when a previous most-recent lifted). Drives the shared highlight overlay and
    /// callout view — both of which only show one key at a time.
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
    }

    // MARK: - External Configuration

    func configure(actions: KeyboardActions, dims: KeyboardDimensions) {
        self.actions = actions
        self.dims = dims
        calloutController.updateParentWidth(bounds.width)
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
        guard bounds.width > 0, bounds.height > 0 else { return }
        let layout = KeyboardLayoutFactory.layout(for: currentPage, dims: dims)
        resolvedFrames = KeyboardLayoutResolver.resolve(
            layout: layout,
            dims: dims,
            keysAreaSize: bounds.size
        )
        // Rebuild the hit grid in lockstep with the frames so the two never diverge.
        // `resolvedFrames` is recomputed on every rebuildLayout (before the render
        // short-circuit), so the grid must be too.
        hitGrid = Self.buildHitGrid(from: resolvedFrames, rowCount: layout.rows.count)

        let isDark = state?.appearanceMode == .dark
        let shiftState = state?.shiftState ?? .disabled
        // Show the "EN ES" locale subtitle only when the user has multiple input modes
        // enabled; otherwise the space bar stays clean. Computed fresh from the host's
        // `UITextInputMode.activeInputModes` each layout pass.
        let codes = actions?.activeInputLocaleCodes() ?? []
        let subtitle: String? = codes.count >= 2 ? codes.joined(separator: " ") : nil

        // Short-circuit if nothing visible has changed since the last rebuild.
        // The cheap updaters (updateShiftState / updateReturnKeyLabel / setHighlightedKey)
        // already cover diffs that are allowed to bypass a full rebuild.
        let signature = RenderSignature(
            size: bounds.size,
            page: currentPage,
            isDark: isDark,
            dims: dims,
            spaceSubtitle: subtitle
        )
        if signature == lastRenderSignature {
            return
        }
        lastRenderSignature = signature

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

        rebuildAccessibilityElements()
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
        case .backspace:
            KeyboardCommitPipeline.commitBackspace(state: state, actions: actions)
        case .space:
            KeyboardCommitPipeline.commitSpace(state: state, actions: actions)
        case .returnKey:
            KeyboardCommitPipeline.commitReturn(state: state, actions: actions)
        case .modeChange(let page):
            KeyboardCommitPipeline.commitModeChange(to: page, state: state)
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
            let point = touch.location(in: self)
            guard let rawKey = findKey(at: point) else { continue }
            let key = smartResolved(rawKey: rawKey, at: point)
            beginPress(touch: touch, key: key, at: point)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            guard let press = activePresses[id] else { continue }
            // For the space-cursor owner, forward every coalesced sample so caret-drag
            // is sub-frame smooth on 120 Hz ProMotion displays. Other presses keep the
            // single-sample path (character keys don't benefit and we want fewer hit-tests).
            if press.ownsSpaceCursor, let coalesced = event?.coalescedTouches(for: touch), !coalesced.isEmpty {
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

    private func beginPress(touch: UITouch, key: KeyFrame, at point: CGPoint) {
        let id = ObjectIdentifier(touch)
        var press = ActivePress(key: key, startPoint: point)
        // Make this the most-recent press — drives shared callout/highlight.
        mostRecentTouchID = id

        rendererRef.setHighlightedKey(key)
        // No per-press haptic (Phase F). Discrete event haptics (accent-menu, space-cursor)
        // are preserved further below.

        switch key.action {
        case .character(let c):
            let cased = (state?.shiftState ?? .disabled) != .disabled ? c.uppercased() : c.lowercased()
            calloutController.presentInput(for: key, character: cased, casedByShift: false)
            // Commit immediately on touch-down (Phase D). Matches native iOS: the character
            // lands in the document at the instant of finger-down, not on release.
            if let state, let actions {
                KeyboardCommitPipeline.commitCharacter(c, state: state, actions: actions)
            }
            press.longPressTask = scheduleLongPress(touchID: id, key: key)
        case .backspace:
            // Immediate delete on touch-down feels native. Long-press starts rapid-delete.
            commitBackspace()
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
        case .returnKey, .modeChange, .snippetToggle:
            break  // commit on release for these
        }

        activePresses[id] = press
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
                rendererRef.setHighlightedKey(nil)
            }
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

        // Finger-slide: are we still on the same key? Apply smart-touch resolution so
        // a sideways drag that lands near a boundary still picks the contextually correct
        // character (same logic as initial touch-down).
        guard let rawNewKey = findKey(at: point) else { return }
        let newKey = smartResolved(rawKey: rawNewKey, at: point)
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

        press.longPressTask?.cancel()
        press.longPressTask = nil
        press.rapidDeleteTask?.cancel()
        press.rapidDeleteTask = nil
        press.key = newKey
        press.didSlideOffOriginal = true

        // Refresh shared visuals only if this touch is the current most-recent — keeps the
        // highlight/callout from flickering when a less-recent finger slides.
        if id == mostRecentTouchID {
            rendererRef.setHighlightedKey(newKey)
            switch newKey.action {
            case .character(let c):
                let cased = (state?.shiftState ?? .disabled) != .disabled ? c.uppercased() : c.lowercased()
                calloutController.presentInput(for: newKey, character: cased, casedByShift: false)
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
        guard let press = activePresses.removeValue(forKey: id) else { return }
        press.longPressTask?.cancel()
        press.rapidDeleteTask?.cancel()

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
                if let scalar = selected.first { state.inputTracking.touchContext.recordCharacter(scalar) }
                state.handleShiftAfterCharacter()
                actions.scheduleSideEffects()
                accentInserted = true
            }
        }

        // Touch-up commit for keys that don't insert on touch-down.
        if committed && !accentInserted, let state = state, let actions = actions {
            switch press.key.action {
            case .character, .backspace, .shift:
                // Already committed on touch-down (or shift toggled). Nothing more to do.
                break
            case .space:
                // If this press owned cursor mode and cursor engaged, suppress the space.
                if !spaceCursorWasEngaged {
                    KeyboardCommitPipeline.commitSpace(state: state, actions: actions)
                }
            case .returnKey:
                KeyboardCommitPipeline.commitReturn(state: state, actions: actions)
            case .modeChange(let page):
                KeyboardCommitPipeline.commitModeChange(to: page, state: state)
            case .snippetToggle:
                state.showingSnippets = true
            }
        }

        // Visual cleanup: only dismiss the shared callout/highlight when no other press
        // remains. Otherwise promote the next-most-recent press to drive the visuals.
        if id == mostRecentTouchID {
            calloutController.dismiss()
            rendererRef.setHighlightedKey(nil)
            promoteNewMostRecentIfNeeded(removedID: id)
        }
    }

    /// When a press is removed, choose a new most-recent (arbitrary remaining touch) and
    /// refresh the shared callout/highlight to reflect it. If no presses remain, leave
    /// the visuals cleared.
    private func promoteNewMostRecentIfNeeded(removedID: ObjectIdentifier) {
        if let nextID = activePresses.keys.first, let nextPress = activePresses[nextID] {
            mostRecentTouchID = nextID
            rendererRef.setHighlightedKey(nextPress.key)
            if case .character(let c) = nextPress.key.action {
                let cased = (state?.shiftState ?? .disabled) != .disabled ? c.uppercased() : c.lowercased()
                calloutController.presentInput(for: nextPress.key, character: cased, casedByShift: false)
            }
        } else {
            mostRecentTouchID = nil
        }
    }

    // MARK: - Hit Testing

    /// Apply bigram-weighted smart-touch correction to the raw `findKey` result.
    /// Non-character keys, and presses while smart touch is disabled, pass through unchanged.
    private func smartResolved(rawKey: KeyFrame, at point: CGPoint) -> KeyFrame {
        guard let state else { return rawKey }
        return SmartTouchResolver.resolve(
            rawKey: rawKey,
            point: point,
            frames: resolvedFrames,
            touchContext: state.inputTracking.touchContext,
            dims: dims
        )
    }

    private func findKey(at point: CGPoint) -> KeyFrame? {
        guard let grid = hitGrid, !resolvedFrames.isEmpty else { return nil }
        // Resolve any tap inside the keys area (plus a small outward margin) to its owning
        // Voronoi cell — "closest letter wins", so there are no dead dividers between keys.
        // Only taps clearly outside the keyboard return nil; off-keyboard drag is already
        // handled earlier in handleMovedPress (point.y > bounds.maxY + 8).
        let margin = max(dims.keyGap * 2, 12)
        guard bounds.insetBy(dx: -margin, dy: -margin).contains(point) else { return nil }
        let idx = grid.frameIndex(for: point)
        guard idx >= 0 && idx < resolvedFrames.count else { return nil }
        return resolvedFrames[idx]
    }

    /// Build the grid-Voronoi partition from row-major `frames`. Keys form clean rows with
    /// monotonic-x centers, so the Voronoi diagram of the key centers is a rectangular grid:
    /// row bands at the midpoints between row centers, and per-row column boundaries at the
    /// midpoints between adjacent key centers. O(n), off the touch path (layout changes only).
    private static func buildHitGrid(from frames: [KeyFrame], rowCount: Int) -> HitGrid {
        guard rowCount > 0, !frames.isEmpty else {
            return HitGrid(rowYBoundaries: [], rowFrameIndices: [[]], rowXBoundaries: [[]])
        }
        var rowFrameIndices = Array(repeating: [Int](), count: rowCount)
        for (i, f) in frames.enumerated() where f.rowIndex >= 0 && f.rowIndex < rowCount {
            rowFrameIndices[f.rowIndex].append(i)   // frames are row-major → already L→R
        }
        // Row centers (any key's rect.midY per row) → interior row boundaries at midpoints.
        let rowCenters: [CGFloat] = (0..<rowCount).map { r in
            rowFrameIndices[r].first.map { frames[$0].rect.midY } ?? 0
        }
        let rowYBoundaries = rowCount > 1
            ? (1..<rowCount).map { (rowCenters[$0 - 1] + rowCenters[$0]) / 2 }
            : []
        // Per-row column boundaries at midpoints between adjacent key centers.
        let rowXBoundaries: [[CGFloat]] = (0..<rowCount).map { r in
            let idxs = rowFrameIndices[r]
            guard idxs.count > 1 else { return [] }
            return (1..<idxs.count).map { (frames[idxs[$0 - 1]].rect.midX + frames[idxs[$0]].rect.midX) / 2 }
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
            // Make sure this press is still alive and still on the same key.
            guard let press = self.activePresses[id], press.key == key else { return }
            // The character was already committed on touch-down (Phase D). Undo that commit
            // so the eventual accent insertion replaces it cleanly.
            self.actions?.deleteBackward()
            self.state?.inputTracking.recordAction(.other)
            // Accent menu becomes the visual focus — promote this touch to most-recent.
            self.mostRecentTouchID = id
            self.calloutController.beginActions(for: key, items: menu)
            self.lightImpactHaptic.impactOccurred(intensity: 0.8)
        }
    }

    // MARK: - Backspace Rapid Delete (per-touch)

    private func scheduleRapidDelete(touchID id: ObjectIdentifier) -> Task<Void, Never>? {
        return Task { @MainActor [weak self] in
            // The first delete already fired on touch-down (instant). Hold engages an
            // accelerating repeat after a short pause — matches native iOS, which starts
            // char-by-char and speeds up the longer the key is held.
            try? await Task.sleep(for: .milliseconds(350))
            while !Task.isCancelled {
                guard let self, var press = self.activePresses[id] else { return }
                press.rapidDeleteCount += 1
                let count = press.rapidDeleteCount
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

    private func commitBackspace() {
        guard let state = state, let actions = actions else { return }
        KeyboardCommitPipeline.commitBackspace(state: state, actions: actions)
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
