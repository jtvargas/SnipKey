//
//  KeyLayerRenderer.swift
//  SnipKeyboard
//
//  CALayer-per-key renderer for V2. Each key has a CAShapeLayer background plus glyph
//  layers that are either text (CATextLayer for letters / "123" / "return" / "Go" / etc.)
//  or an image (CALayer.contents = UIImage(systemName:)? for shift / backspace /
//  return-when-not-prominent — matches native iOS visual fidelity).
//
//  Keys are grouped into one `KeySurface` per `KeyboardPage` — a container CALayer that is
//  built once per style (appearance / dims / scale / space subtitle) and geometry. Every
//  later visit to that page is a visibility flip: no layer allocation, no text
//  rasterization. Letter keys carry both case glyphs and the shift key carries all three
//  icons from build time, so shift toggles are `isHidden` flips as well. This mirrors
//  SwiftKey's raster cache keyed by (style, size, shift): page/shift changes are pure blits.
//
//  Every mutation runs inside a CATransaction with implicit animations disabled,
//  so finger-slide between keys is instant.
//

import UIKit
import CoreText

final class KeyLayerRenderer {

    // MARK: - Glyph descriptor

    /// What to render inside a shift-invariant key. Letters and the shift key bypass this
    /// and pre-build every shift variant (see `GlyphLayers`).
    enum KeyGlyph: Equatable {
        /// Plain text label rendered via CATextLayer ("123", "ABC", "Go", "Send", digits).
        case text(String)
        /// SF Symbol rendered into a UIImage and assigned to a plain CALayer's `contents`.
        case symbol(name: String, pointSize: CGFloat, weight: UIImage.SymbolWeight)
    }

    // MARK: - Per-Key Layers

    /// The glyph layer(s) of one key. Variants that depend on shift state pre-build every
    /// alternative so a state change is an `isHidden` flip, never a re-rasterization.
    private enum GlyphLayers {
        /// One layer (text or symbol) that never changes with shift state.
        case single(CALayer)
        /// Letter key: lowercase and uppercase text layers; exactly one is visible.
        case cased(lower: CATextLayer, upper: CATextLayer)
        /// Shift key: one icon per `ShiftState`; exactly one is visible.
        case shift(disabled: CALayer, enabled: CALayer, locked: CALayer)

        /// Glyphs sit above backgrounds (0) and pressed overlays (1).
        private static let zPosition: CGFloat = 2

        func addLayers(to container: CALayer) {
            switch self {
            case .single(let layer):
                layer.zPosition = Self.zPosition
                container.addSublayer(layer)
            case .cased(let lower, let upper):
                lower.zPosition = Self.zPosition
                upper.zPosition = Self.zPosition
                container.addSublayer(lower)
                container.addSublayer(upper)
            case .shift(let disabled, let enabled, let locked):
                disabled.zPosition = Self.zPosition
                enabled.zPosition = Self.zPosition
                locked.zPosition = Self.zPosition
                container.addSublayer(disabled)
                container.addSublayer(enabled)
                container.addSublayer(locked)
            }
        }

        func removeFromSuperlayer() {
            switch self {
            case .single(let layer):
                layer.removeFromSuperlayer()
            case .cased(let lower, let upper):
                lower.removeFromSuperlayer()
                upper.removeFromSuperlayer()
            case .shift(let disabled, let enabled, let locked):
                disabled.removeFromSuperlayer()
                enabled.removeFromSuperlayer()
                locked.removeFromSuperlayer()
            }
        }
    }

    private struct KeyLayers {
        let background: CAShapeLayer
        var glyphs: GlyphLayers
        let keyFrame: KeyFrame
    }

    /// Everything rendered for one keyboard page: a container holding the page's key
    /// backgrounds (z 0) and glyphs (z 2). Per-touch pressed overlays (z 1) are parked in
    /// whichever surface was active when `setPressedKey` ran. Hidden while another page
    /// is showing; reused verbatim on the next visit.
    private final class KeySurface {
        /// The geometry this surface was built from. A render call whose frames differ
        /// (keys-area resize, layout-profile change) invalidates it.
        let frames: [KeyFrame]
        let container = CALayer()
        var keys: [KeyLayers] = []

        init(frames: [KeyFrame]) {
            self.frames = frames
        }
    }

    /// Page-independent inputs that shape every key's appearance. A change invalidates all
    /// surfaces at once; per-page geometry is validated against `KeySurface.frames` instead
    /// (the keys-area size and layout profile are fully determined by the frames).
    private struct SurfaceStyle: Equatable {
        let isDark: Bool
        let dims: KeyboardDimensions
        let scale: CGFloat
        let spaceBarSubtitle: String?
    }

    /// Runtime return-key label pushed in by the host. Nil until the first push: outlined
    /// return symbol on a neutral background.
    private struct ReturnKeyLabel: Equatable {
        let label: String
        let prominent: Bool
    }

    private weak var hostLayer: CALayer?
    private var surfaces: [KeyboardPage: KeySurface] = [:]
    private var activeSurface: KeySurface?
    private var style: SurfaceStyle?
    private var currentShiftState: ShiftState = .disabled
    private var returnKeyLabel: ReturnKeyLabel?

    private var pressedHighlights: [ObjectIdentifier: CAShapeLayer] = [:]

    /// Hot-path caches for the per-touch pressed overlay. The fill color depends only on the
    /// current appearance, and the rounded-rect path only on key size + corner radius — both are
    /// constant between style changes. Caching them avoids a `UIBezierPath`/`UIColor`/`cgColor`
    /// allocation on every touch-down during fast typing. Invalidated when the style changes.
    private var cachedPressedColor: CGColor?
    private var pressedPathCache: [CGSize: CGPath] = [:]

    /// Render scale used to rasterize CATextLayer glyphs and SF Symbol images. Supplied by
    /// the coordinator on every `render(...)` from its `traitCollection.displayScale` (the
    /// real display scale — correct even in an extension and on external displays). Reused by
    /// the cheap glyph-replacing updaters between full renders. Must equal the device scale
    /// or text rasterizes blurry; the host layer's `contentsScale` is NOT reliable here.
    private var currentScale: CGFloat = 3.0

    /// System UI font per point size. A page uses only ~4 distinct sizes, so sharing the
    /// `CTFont` across its text layers turns ~60 `CTFontCreateUIFontForLanguage` calls per
    /// surface build into ~4. Fonts are immutable; dropped only under memory pressure.
    private var fontCache: [CGFloat: CTFont] = [:]

    private var currentIsDark: Bool { style?.isDark ?? false }
    private var currentCornerRadius: CGFloat { style?.dims.cornerRadius ?? 8 }

    // MARK: - Init

    init(hostLayer: CALayer) {
        self.hostLayer = hostLayer
    }

    // MARK: - Rendering

    /// Show `page` with the given resolved layout. Called on page change, resize and
    /// appearance change. After a page's first visit under the current style, re-showing it
    /// is a visibility flip; a style change drops every surface and rebuilds `page` only
    /// (other pages rebuild lazily on their next visit).
    func render(frames: [KeyFrame], page: KeyboardPage, dims: KeyboardDimensions, isDark: Bool, shiftState: ShiftState, scale: CGFloat, spaceBarSubtitle: String? = nil) {
        guard let hostLayer else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        if scale > 0 { currentScale = scale }
        let newStyle = SurfaceStyle(isDark: isDark, dims: dims, scale: currentScale, spaceBarSubtitle: spaceBarSubtitle)
        if newStyle != style {
            style = newStyle
            discardAllSurfaces()
            // Appearance/geometry changed — drop the pressed-overlay color/path caches so
            // the next press rebuilds them once with the current palette and corner radius.
            cachedPressedColor = nil
            pressedPathCache.removeAll(keepingCapacity: true)
        }
        if shiftState != currentShiftState {
            currentShiftState = shiftState
            for surface in surfaces.values {
                applyShiftState(to: surface)
            }
        }

        if let surface = surfaces[page] {
            if surface.frames == frames {
                activate(surface)
                return
            }
            // Same style, different geometry for this page ⇒ the keys area was resized or
            // the layout profile changed. Both invalidate every page, not just this one.
            discardAllSurfaces()
        }

        let surface = buildSurface(frames: frames, style: newStyle)
        surfaces[page] = surface
        hostLayer.addSublayer(surface.container)
        activate(surface)
    }

    /// Make `surface` the visible one. Exactly one surface is visible at any time.
    private func activate(_ surface: KeySurface) {
        guard surface !== activeSurface else { return }
        activeSurface?.container.isHidden = true
        surface.container.isHidden = false
        activeSurface = surface
    }

    private func discardAllSurfaces() {
        for surface in surfaces.values {
            surface.container.removeFromSuperlayer()
        }
        surfaces.removeAll(keepingCapacity: true)
        activeSurface = nil
        // The pressed overlays went down with their containers. Detach them so the next
        // `setPressedKey` (the coordinator re-applies in-flight presses right after a
        // rebuild) re-parents them into the new active surface instead of allocating.
        for layer in pressedHighlights.values {
            layer.removeFromSuperlayer()
        }
    }

    /// Build every layer of one page into a hidden container. This is the only place that
    /// allocates key layers or rasterizes text.
    private func buildSurface(frames: [KeyFrame], style: SurfaceStyle) -> KeySurface {
        let surface = KeySurface(frames: frames)
        surface.container.isHidden = true
        if let hostLayer {
            surface.container.frame = hostLayer.bounds
        }
        surface.keys.reserveCapacity(frames.count)

        for frame in frames {
            let background = CAShapeLayer()
            background.frame = frame.rect
            background.path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: frame.rect.size), cornerRadius: style.dims.cornerRadius).cgPath
            background.fillColor = backgroundColor(for: frame.action, isDark: style.isDark).cgColor
            background.zPosition = 0
            applyNativeKeyShadow(to: background, isDark: style.isDark)
            surface.container.addSublayer(background)

            let glyphs = makeGlyphLayers(for: frame, scale: style.scale, isDark: style.isDark)
            glyphs.addLayers(to: surface.container)

            surface.keys.append(KeyLayers(background: background, glyphs: glyphs, keyFrame: frame))
        }
        return surface
    }

    // MARK: - Updates (cheap, no rebuild)

    /// Update the shift state — flips character casing AND the shift key's icon on every
    /// built surface, so a hidden page never shows stale casing when it comes back.
    func updateShiftState(_ shiftState: ShiftState) {
        guard shiftState != currentShiftState else { return }
        currentShiftState = shiftState

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        for surface in surfaces.values {
            applyShiftState(to: surface)
        }
    }

    /// Pure `isHidden` flips over the pre-built case/icon variants of one surface.
    private func applyShiftState(to surface: KeySurface) {
        let uppercase = currentShiftState != .disabled
        for k in surface.keys {
            switch k.glyphs {
            case .cased(let lower, let upper):
                lower.isHidden = uppercase
                upper.isHidden = !uppercase
            case .shift(let disabled, let enabled, let locked):
                disabled.isHidden = currentShiftState != .disabled
                enabled.isHidden = currentShiftState != .enabled
                locked.isHidden = currentShiftState != .locked
            case .single:
                break
            }
        }
    }

    /// Press a key for a specific touch. Multiple touches can be active at once; each gets a
    /// separate layer below glyphs so rolling typing no longer makes one shared overlay jump.
    /// The overlay lives in the active surface; if the page switched mid-press (123 swaps the
    /// plane at touch-down) the same layer is moved over rather than re-created.
    func setPressedKey(_ frame: KeyFrame, for id: ObjectIdentifier) {
        guard let container = activeSurface?.container else { return }

        let layer: CAShapeLayer
        if let existing = pressedHighlights[id] {
            layer = existing
        } else {
            layer = CAShapeLayer()
            pressedHighlights[id] = layer
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAllAnimations()
        layer.frame = frame.rect
        layer.path = pressedPath(for: frame.rect.size)
        layer.fillColor = pressedColorCGColor()
        layer.opacity = 1
        layer.zPosition = 1
        if layer.superlayer !== container {
            layer.removeFromSuperlayer()
            container.addSublayer(layer)
        }
        CATransaction.commit()
    }

    /// Release one touch's pressed layer. The fade is short and isolated to that key, so a new
    /// press elsewhere never dims the next key's feedback.
    func clearPressedKey(for id: ObjectIdentifier) {
        guard let layer = pressedHighlights.removeValue(forKey: id) else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(false)
        // Remove the layer when the fade finishes via the transaction completion block, so fast
        // typing doesn't stack a delayed `asyncAfter` closure on the main thread per release.
        CATransaction.setCompletionBlock { [weak layer] in
            layer?.removeFromSuperlayer()
        }
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = layer.presentation()?.opacity ?? layer.opacity
        anim.toValue = 0
        anim.duration = 0.085
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false
        layer.add(anim, forKey: "pressedFade")
        layer.opacity = 0
        CATransaction.commit()
    }

    func clearAllPressedKeys() {
        for id in Array(pressedHighlights.keys) {
            clearPressedKey(for: id)
        }
    }

    private func pressedColor() -> UIColor {
        currentIsDark
            ? UIColor(white: 0.62, alpha: 0.72)
            : UIColor(white: 0.78, alpha: 1.0)
    }

    /// Appearance-constant pressed fill, resolved to a `CGColor` once per style change.
    private func pressedColorCGColor() -> CGColor {
        if let cached = cachedPressedColor { return cached }
        let color = pressedColor().cgColor
        cachedPressedColor = color
        return color
    }

    /// Rounded-rect path for a pressed overlay of the given key size, cached per size. Most keys
    /// share a size, so after the first few presses this is a dictionary hit, not an allocation.
    private func pressedPath(for size: CGSize) -> CGPath {
        if let cached = pressedPathCache[size] { return cached }
        let path = UIBezierPath(
            roundedRect: CGRect(origin: .zero, size: size),
            cornerRadius: currentCornerRadius
        ).cgPath
        pressedPathCache[size] = path
        return path
    }

    /// Update the return key's label/style on every built surface. Replaces the glyph layer
    /// because text↔symbol may switch. A no-op when the label is unchanged — the coordinator
    /// re-pushes it after every `render`, and surfaces are built with the stored label, so
    /// the per-render call costs nothing.
    func updateReturnKeyLabel(_ label: String, prominent: Bool, isDark: Bool) {
        let newLabel = ReturnKeyLabel(label: label, prominent: prominent)
        guard newLabel != returnKeyLabel else { return }
        returnKeyLabel = newLabel
        guard !surfaces.isEmpty else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let fill = backgroundColor(for: .returnKey, isDark: isDark).cgColor
        for surface in surfaces.values {
            for index in surface.keys.indices where surface.keys[index].keyFrame.action == .returnKey {
                let k = surface.keys[index]
                k.glyphs.removeFromSuperlayer()
                let glyphs = makeGlyphLayers(for: k.keyFrame, scale: currentScale, isDark: isDark)
                glyphs.addLayers(to: surface.container)
                k.background.fillColor = fill
                surface.keys[index].glyphs = glyphs
            }
        }
    }

    // MARK: - Memory pressure

    /// Keep only the visible surface (an in-flight press may be parked in it) and drop every
    /// cache that rebuilds lazily. Other pages rebuild on their next visit exactly as a
    /// first visit would.
    func handleMemoryPressure() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        for surface in surfaces.values where surface !== activeSurface {
            surface.container.removeFromSuperlayer()
        }
        surfaces = surfaces.filter { $0.value === activeSurface }
        Self.glyphCache.removeAll()
        pressedPathCache.removeAll()
        fontCache.removeAll()
    }

    // MARK: - Glyph factory

    /// Build the glyph layer(s) for a key. Letters get both cases and the shift key all
    /// three icons, each pre-set to the current shift state; everything else is one layer.
    private func makeGlyphLayers(for frame: KeyFrame, scale: CGFloat, isDark: Bool) -> GlyphLayers {
        switch frame.action {
        case .character(let c):
            let lower = c.lowercased()
            let upper = c.uppercased()
            if lower == upper {
                return .single(makeTextLayer(lower, for: frame, scale: scale, isDark: isDark))
            }
            let lowerLayer = makeTextLayer(lower, for: frame, scale: scale, isDark: isDark)
            let upperLayer = makeTextLayer(upper, for: frame, scale: scale, isDark: isDark)
            let uppercase = currentShiftState != .disabled
            lowerLayer.isHidden = uppercase
            upperLayer.isHidden = !uppercase
            return .cased(lower: lowerLayer, upper: upperLayer)
        case .shift:
            let disabled = makeSymbolLayer(name: Self.shiftSymbolName(for: .disabled), pointSize: Self.shiftSymbolPointSize, weight: .regular, for: frame, scale: scale, isDark: isDark)
            let enabled = makeSymbolLayer(name: Self.shiftSymbolName(for: .enabled), pointSize: Self.shiftSymbolPointSize, weight: .regular, for: frame, scale: scale, isDark: isDark)
            let locked = makeSymbolLayer(name: Self.shiftSymbolName(for: .locked), pointSize: Self.shiftSymbolPointSize, weight: .regular, for: frame, scale: scale, isDark: isDark)
            disabled.isHidden = currentShiftState != .disabled
            enabled.isHidden = currentShiftState != .enabled
            locked.isHidden = currentShiftState != .locked
            return .shift(disabled: disabled, enabled: enabled, locked: locked)
        default:
            return .single(makeGlyphLayer(for: frame, scale: scale, isDark: isDark))
        }
    }

    /// Build the single glyph layer for a shift-invariant key.
    private func makeGlyphLayer(for frame: KeyFrame, scale: CGFloat, isDark: Bool) -> CALayer {
        // Space bar with a locale subtitle: a parent CALayer holds the subtitle CATextLayer
        // positioned bottom-right (matches native iOS's "EN ES" placement).
        if case .space = frame.action, let subtitle = style?.spaceBarSubtitle, !subtitle.isEmpty {
            let container = CALayer()
            container.frame = frame.rect
            let subtitleFont: CGFloat = 11
            let subtitleLayer = CATextLayer()
            subtitleLayer.contentsScale = scale
            subtitleLayer.alignmentMode = .right
            subtitleLayer.string = subtitle
            subtitleLayer.fontSize = subtitleFont
            subtitleLayer.font = uiFont(ofSize: subtitleFont)
            // Dimmer than the main glyph — matches native's secondary-text treatment.
            let secondary = isDark ? UIColor(white: 0.65, alpha: 1.0) : UIColor(white: 0.45, alpha: 1.0)
            subtitleLayer.foregroundColor = secondary.cgColor
            let padding: CGFloat = 8
            subtitleLayer.frame = CGRect(
                x: 0,
                y: frame.rect.height - subtitleFont - padding,
                width: frame.rect.width - padding,
                height: subtitleFont + 2
            )
            container.addSublayer(subtitleLayer)
            return container
        }

        switch glyph(for: frame.action) {
        case .text(let string):
            return makeTextLayer(string, for: frame, scale: scale, isDark: isDark)
        case .symbol(let name, let pointSize, let weight):
            return makeSymbolLayer(name: name, pointSize: pointSize, weight: weight, for: frame, scale: scale, isDark: isDark)
        }
    }

    private func makeTextLayer(_ string: String, for frame: KeyFrame, scale: CGFloat, isDark: Bool) -> CATextLayer {
        let textLayer = CATextLayer()
        textLayer.contentsScale = scale
        textLayer.alignmentMode = .center
        let fontSize = textFontSize(for: frame.action, keyHeight: frame.rect.height)
        // Vertically center the text within the key, with a small upward bias to match
        // native iOS (Apple's glyphs sit slightly above mathematical center).
        let inset = max((frame.rect.height - fontSize - 4) / 2, 0)
        textLayer.frame = frame.rect.insetBy(dx: 0, dy: inset).offsetBy(dx: 0, dy: -1)
        textLayer.string = string
        textLayer.fontSize = fontSize
        textLayer.font = uiFont(ofSize: fontSize)
        textLayer.foregroundColor = glyphColor(for: frame.action, isDark: isDark).cgColor
        return textLayer
    }

    private func makeSymbolLayer(name: String, pointSize: CGFloat, weight: UIImage.SymbolWeight, for frame: KeyFrame, scale: CGFloat, isDark: Bool) -> CALayer {
        let imageLayer = CALayer()
        imageLayer.contentsScale = scale
        imageLayer.contentsGravity = .resizeAspect
        let image = symbolImage(name: name, pointSize: pointSize, weight: weight, tint: glyphColor(for: frame.action, isDark: isDark))
        imageLayer.contents = image?.cgImage
        // Size the layer to the rendered image's pixel-perfect size, centered in the key.
        if let image {
            let w = image.size.width
            let h = image.size.height
            let originX = frame.rect.midX - w / 2
            let originY = frame.rect.midY - h / 2
            imageLayer.frame = CGRect(x: originX, y: originY, width: w, height: h)
        } else {
            imageLayer.frame = frame.rect
        }
        return imageLayer
    }

    private static let shiftSymbolPointSize: CGFloat = 17

    /// Match native: outline arrow when disabled, filled when enabled, capslock.fill when locked.
    private static func shiftSymbolName(for state: ShiftState) -> String {
        switch state {
        case .disabled: return "shift"
        case .enabled:  return "shift.fill"
        case .locked:   return "capslock.fill"
        }
    }

    /// Decide whether a key should render text or an SF Symbol image. Letters and the shift
    /// key are built by `makeGlyphLayers` with every variant; here they yield the variant
    /// for the current shift state.
    private func glyph(for action: KeyAction) -> KeyGlyph {
        switch action {
        case .character(let c):
            return .text(currentShiftState != .disabled ? c.uppercased() : c.lowercased())
        case .insertText(let label, _):
            return .text(label)
        case .shift:
            return .symbol(name: Self.shiftSymbolName(for: currentShiftState), pointSize: Self.shiftSymbolPointSize, weight: .regular)
        case .backspace:
            return .symbol(name: "delete.left", pointSize: 19, weight: .regular)
        case .space:
            return .text("")
        case .returnKey:
            if let returnKeyLabel, returnKeyLabel.prominent {
                return .text(returnKeyLabel.label)
            }
            // Default before any label is pushed in (and whenever not prominent): outlined return symbol.
            return .symbol(name: "return", pointSize: 20, weight: .regular)
        case .modeChange(let page):
            switch page {
            case .letters: return .text("ABC")
            case .numbers: return .text("123")
            case .symbols: return .text("#+=")
            }
        case .snippetToggle:
            return .symbol(name: "sparkle", pointSize: 16, weight: .regular)
        }
    }

    private func textFontSize(for action: KeyAction, keyHeight: CGFloat) -> CGFloat {
        if case .character(let c) = action {
            let ch = c.first
            if ch?.isLetter == true || ch?.isNumber == true { return round(keyHeight * 0.50) }
            return round(keyHeight * 0.43)
        }
        if case .insertText(let label, _) = action {
            return label.count > 1 ? round(keyHeight * 0.34) : round(keyHeight * 0.43)
        }
        if case .returnKey = action { return round(keyHeight * 0.36) }
        if case .modeChange = action { return round(keyHeight * 0.36) }
        return round(keyHeight * 0.43)
    }

    private func uiFont(ofSize size: CGFloat) -> CTFont? {
        if let cached = fontCache[size] { return cached }
        guard let font = CTFontCreateUIFontForLanguage(.system, size, nil) else { return nil }
        fontCache[size] = font
        return font
    }

    /// Render an SF Symbol to a `UIImage` of pixel-perfect size at the current screen scale,
    /// tinted to the requested color.
    ///
    /// Results are memoized in a static cache keyed by (name, pointSize, weight, tint).
    /// The distinct set of symbols rendered by V2 is tiny (≤ 8 icons × 2 tints), so the
    /// cache stays well-bounded without eviction; `handleMemoryPressure` empties it.
    /// Eliminates `UIGraphicsImageRenderer` work on every surface build and return-label change.
    private struct GlyphCacheKey: Hashable {
        let name: String
        let pointSize: CGFloat
        let weightRaw: Int
        let tintRGBA: UInt32
    }
    private static var glyphCache: [GlyphCacheKey: UIImage] = [:]

    private static func packRGBA(_ color: UIColor) -> UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func q(_ v: CGFloat) -> UInt32 { UInt32(max(0, min(255, Int(v * 255)))) }
        return (q(r) << 24) | (q(g) << 16) | (q(b) << 8) | q(a)
    }

    private func symbolImage(name: String, pointSize: CGFloat, weight: UIImage.SymbolWeight, tint: UIColor) -> UIImage? {
        let key = GlyphCacheKey(
            name: name,
            pointSize: pointSize,
            weightRaw: weight.rawValue,
            tintRGBA: Self.packRGBA(tint)
        )
        if let cached = Self.glyphCache[key] { return cached }

        let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        guard let raw = UIImage(systemName: name, withConfiguration: configuration) else { return nil }
        let size = raw.size
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            raw.withTintColor(tint, renderingMode: .alwaysOriginal).draw(in: CGRect(origin: .zero, size: size))
        }
        Self.glyphCache[key] = image
        return image
    }

    // MARK: - Style

    private func backgroundColor(for action: KeyAction, isDark: Bool) -> UIColor {
        switch action {
        case .character, .insertText, .space:
            return isDark
                ? UIColor(white: 0.40, alpha: 0.55)
                : UIColor(white: 1.0, alpha: 0.94)
        case .returnKey where returnKeyLabel?.prominent == true:
            return .systemBlue
        case .returnKey, .shift, .backspace, .modeChange, .snippetToggle:
            return isDark
                ? UIColor(white: 0.40, alpha: 0.55)
                : UIColor(red: 0.674, green: 0.704, blue: 0.747, alpha: 0.88)
        }
    }

    private func applyNativeKeyShadow(to layer: CAShapeLayer, isDark: Bool) {
        if isDark {
            layer.shadowOpacity = 0
            return
        }

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 0
        layer.shadowOpacity = 0.24
        layer.shadowPath = layer.path
    }

    private func glyphColor(for action: KeyAction, isDark: Bool) -> UIColor {
        if case .returnKey = action {
            let prominent = returnKeyLabel?.prominent ?? false
            if !prominent {
                return isDark ? UIColor(white: 0.48, alpha: 1.0) : UIColor(white: 0.82, alpha: 1.0)
            }
        }
        // Explicit black/white — `UIColor.label` is a dynamic color whose `.cgColor`
        // resolves through the current trait collection at access time. CATextLayer has
        // no trait collection of its own, so `.label.cgColor` would fall back to whatever
        // `UITraitCollection.current` is on the calling thread — frequently dark inside
        // a keyboard extension. Using explicit black/white based on our own `isDark`
        // signal guarantees correct rendering regardless of UIKit's global trait state.
        return isDark ? UIColor.white : UIColor.black
    }
}
