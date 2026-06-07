//
//  KeyLayerRenderer.swift
//  SnipKeyboard
//
//  CALayer-per-key renderer for V2. Each key has a CAShapeLayer background plus a glyph
//  layer that's either text (CATextLayer for letters / "123" / "return" / "Go" / etc.)
//  or an image (CALayer.contents = UIImage(systemName:)? for shift / backspace /
//  return-when-not-prominent — matches native iOS visual fidelity).
//
//  Every mutation runs inside a CATransaction with implicit animations disabled,
//  so finger-slide between keys is instant.
//

import UIKit
import CoreText

final class KeyLayerRenderer {

    // MARK: - Glyph descriptor

    /// What to render inside a key. Computed per `KeyAction` + current shift state.
    enum KeyGlyph: Equatable {
        /// Plain text label rendered via CATextLayer (letters, "123", "ABC", "Go", "Send").
        case text(String)
        /// SF Symbol rendered into a UIImage and assigned to a plain CALayer's `contents`.
        case symbol(name: String, pointSize: CGFloat, weight: UIImage.SymbolWeight)
    }

    // MARK: - Per-Key Layers

    private struct KeyLayers {
        let background: CAShapeLayer
        /// Either a `CATextLayer` (for `.text`) or a plain `CALayer` (for `.symbol`).
        let glyph: CALayer
        var keyFrame: KeyFrame
    }

    private weak var hostLayer: CALayer?
    private var keys: [KeyLayers] = []
    private var pressedHighlights: [ObjectIdentifier: CAShapeLayer] = [:]

    /// Render scale used to rasterize CATextLayer glyphs and SF Symbol images. Supplied by
    /// the coordinator on every `render(...)` from its `traitCollection.displayScale` (the
    /// real display scale — correct even in an extension and on external displays). Reused by
    /// the cheap glyph-replacing updaters between full renders. Must equal the device scale
    /// or text rasterizes blurry; the host layer's `contentsScale` is NOT reliable here.
    private var currentScale: CGFloat = 3.0

    /// Shared highlight (shown only on the currently-pressed key).
    /// Fill color is set per appearance mode in `render(...)` so dark mode gets a
    /// slightly lighter tint and light mode a slightly darker one — subtle confirmation
    /// of which key the finger is on, not an obvious overlay.
    let highlight: CAShapeLayer = {
        let l = CAShapeLayer()
        l.isHidden = true
        return l
    }()

    private var currentCornerRadius: CGFloat = 8
    private var currentIsDark: Bool = false
    private var currentShiftUppercase: Bool = false
    private var currentShiftState: ShiftState = .disabled

    /// Optional "EN ES"-style locale subtitle rendered inside the space bar. Set by the
    /// coordinator on each `render(...)` call based on `KeyboardActions.activeInputLocaleCodes()`.
    /// Nil when the user has only one input mode enabled (most users).
    private var spaceBarSubtitle: String?

    // MARK: - Init

    init(hostLayer: CALayer) {
        self.hostLayer = hostLayer
    }

    // MARK: - Rendering

    /// Rebuild all key layers for the given resolved layout. Called when the page changes
    /// or the keyboard is resized.
    func render(frames: [KeyFrame], dims: KeyboardDimensions, isDark: Bool, shiftState: ShiftState, scale: CGFloat, spaceBarSubtitle: String? = nil) {
        guard let hostLayer else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        currentCornerRadius = dims.cornerRadius
        currentIsDark = isDark
        currentShiftState = shiftState
        currentShiftUppercase = shiftState != .disabled
        self.spaceBarSubtitle = spaceBarSubtitle
        if scale > 0 { currentScale = scale }

        // Discard old key layers entirely — frame count and order may have changed.
        for k in keys {
            k.background.removeFromSuperlayer()
            k.glyph.removeFromSuperlayer()
        }
        for layer in pressedHighlights.values {
            layer.removeFromSuperlayer()
        }
        keys.removeAll(keepingCapacity: true)
        pressedHighlights.removeAll(keepingCapacity: true)
        highlight.removeFromSuperlayer()

        let scale = currentScale
        for frame in frames {
            let background = CAShapeLayer()
            background.frame = frame.rect
            background.path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: frame.rect.size), cornerRadius: dims.cornerRadius).cgPath
            background.fillColor = backgroundColor(for: frame.action, isDark: isDark).cgColor
            background.zPosition = 0
            applyNativeKeyShadow(to: background, isDark: isDark)
            hostLayer.addSublayer(background)

            let glyphLayer = makeGlyphLayer(for: frame, scale: scale, isDark: isDark)
            glyphLayer.zPosition = 2
            hostLayer.addSublayer(glyphLayer)

            keys.append(KeyLayers(background: background, glyph: glyphLayer, keyFrame: frame))
        }

        // Highlight goes on top of backgrounds; uses translucent fill so glyphs stay readable.
        // Tint adapts to appearance — slightly lighter than character keys in dark mode,
        // slightly darker than character keys in light mode.
        highlight.fillColor = isDark
            ? UIColor(white: 0.55, alpha: 0.55).cgColor
            : UIColor(white: 0.85, alpha: 0.9).cgColor
        highlight.zPosition = 1
        // Visibility is driven by opacity (so the highlight can fade out on release).
        // The layer is recreated each full render, so re-establish the hidden-via-opacity state.
        highlight.isHidden = false
        highlight.opacity = 0
        hostLayer.addSublayer(highlight)
    }

    // MARK: - Updates (cheap, no rebuild)

    /// Update the shift state — refreshes character casing AND the shift key's glyph icon.
    func updateShiftState(_ shiftState: ShiftState) {
        let newUppercase = shiftState != .disabled
        let stateChanged = shiftState != currentShiftState
        guard stateChanged else { return }
        currentShiftState = shiftState
        currentShiftUppercase = newUppercase

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        for (index, k) in keys.enumerated() {
            switch k.keyFrame.action {
            case .character:
                // Re-string the text layer (we know it's CATextLayer for character keys).
                if let textLayer = k.glyph as? CATextLayer {
                    textLayer.string = characterText(for: k.keyFrame.action, uppercase: newUppercase)
                }
            case .shift:
                // Shift glyph swaps between three icons. The glyph layer's type may need
                // to change if we go from .symbol → .symbol (still a CALayer). Re-render
                // by replacing the layer entirely.
                let scale = currentScale
                let newLayer = makeGlyphLayer(for: k.keyFrame, scale: scale, isDark: currentIsDark)
                newLayer.zPosition = 2
                k.glyph.removeFromSuperlayer()
                hostLayer?.insertSublayer(newLayer, above: k.background)
                keys[index] = KeyLayers(background: k.background, glyph: newLayer, keyFrame: k.keyFrame)
            default:
                break
            }
        }
    }

    /// Legacy single-key highlight path. V2 uses per-touch `setPressedKey(_:for:)` so rolling
    /// typing cannot make one shared overlay jump between fingers.
    /// Appearance is INSTANT on press (native); on clear (frame == nil) the highlight fades
    /// its opacity out over ~120ms. A new press cancels any in-flight fade and snaps to full
    /// opacity — so promotion to another finger / a fast new press never flickers.
    func setHighlightedKey(_ frame: KeyFrame?) {
        guard let frame else {
            // Fade out on release. Needs implicit/explicit animation, so DON'T disable actions.
            CATransaction.begin()
            CATransaction.setDisableActions(false)
            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue = highlight.presentation()?.opacity ?? highlight.opacity
            anim.toValue = 0
            anim.duration = 0.12
            anim.timingFunction = CAMediaTimingFunction(name: .easeIn)
            anim.fillMode = .forwards
            anim.isRemovedOnCompletion = false
            highlight.add(anim, forKey: "highlightFade")
            highlight.opacity = 0
            CATransaction.commit()
            return
        }
        // Instant show — move to the key and snap to full opacity, cancelling any fade.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        highlight.removeAnimation(forKey: "highlightFade")
        highlight.frame = frame.rect
        highlight.path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: frame.rect.size), cornerRadius: currentCornerRadius).cgPath
        highlight.isHidden = false
        highlight.opacity = 1
        CATransaction.commit()
    }

    /// Press a key for a specific touch. Multiple touches can be active at once; each gets a
    /// separate layer below glyphs so rolling typing no longer makes one shared overlay jump.
    func setPressedKey(_ frame: KeyFrame, for id: ObjectIdentifier) {
        guard let hostLayer else { return }

        let layer = pressedHighlights[id] ?? CAShapeLayer()
        pressedHighlights[id] = layer

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAllAnimations()
        layer.frame = frame.rect
        layer.path = UIBezierPath(
            roundedRect: CGRect(origin: .zero, size: frame.rect.size),
            cornerRadius: currentCornerRadius
        ).cgPath
        layer.fillColor = pressedColor().cgColor
        layer.opacity = 1
        layer.zPosition = 1
        if layer.superlayer == nil {
            hostLayer.addSublayer(layer)
        }
        CATransaction.commit()
    }

    /// Release one touch's pressed layer. The fade is short and isolated to that key, so a new
    /// press elsewhere never dims the next key's feedback.
    func clearPressedKey(for id: ObjectIdentifier) {
        guard let layer = pressedHighlights.removeValue(forKey: id) else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(false)
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

        DispatchQueue.main.asyncAfter(deadline: .now() + anim.duration) { [weak layer] in
            layer?.removeFromSuperlayer()
        }
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

    /// Update an individual key's text/style (used for return-key label changes).
    /// Replaces the glyph layer because text↔symbol may switch.
    func updateReturnKeyLabel(_ label: String, prominent: Bool, isDark: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        for (index, k) in keys.enumerated() where k.keyFrame.action == .returnKey {
            let scale = currentScale
            // Override the glyph factory's default by stashing the label override.
            self.returnKeyOverride = (label: label, prominent: prominent)
            let newGlyph = makeGlyphLayer(for: k.keyFrame, scale: scale, isDark: isDark)
            newGlyph.zPosition = 2
            self.returnKeyOverride = nil

            if prominent {
                k.background.fillColor = UIColor.systemBlue.cgColor
            } else {
                k.background.fillColor = backgroundColor(for: .returnKey, isDark: isDark).cgColor
            }
            k.glyph.removeFromSuperlayer()
            hostLayer?.insertSublayer(newGlyph, above: k.background)
            keys[index] = KeyLayers(background: k.background, glyph: newGlyph, keyFrame: k.keyFrame)
        }
    }

    // MARK: - Glyph factory

    /// Transient state read by `glyph(for:)` when re-rendering the return key with a runtime label.
    private var returnKeyOverride: (label: String, prominent: Bool)?

    /// Build the appropriate glyph layer for a given key.
    private func makeGlyphLayer(for frame: KeyFrame, scale: CGFloat, isDark: Bool) -> CALayer {
        // Space bar with a locale subtitle: a parent CALayer holds the subtitle CATextLayer
        // positioned bottom-right (matches native iOS's "EN ES" placement).
        if case .space = frame.action, let subtitle = spaceBarSubtitle, !subtitle.isEmpty {
            let container = CALayer()
            container.frame = frame.rect
            let subtitleFont: CGFloat = 11
            let subtitleLayer = CATextLayer()
            subtitleLayer.contentsScale = scale
            subtitleLayer.alignmentMode = .right
            subtitleLayer.string = subtitle
            subtitleLayer.fontSize = subtitleFont
            subtitleLayer.font = CTFontCreateUIFontForLanguage(.system, subtitleFont, nil)
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

        let glyph = self.glyph(for: frame.action)
        switch glyph {
        case .text(let string):
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
            textLayer.font = CTFontCreateUIFontForLanguage(.system, fontSize, nil)
            textLayer.foregroundColor = glyphColor(for: frame.action, isDark: isDark).cgColor
            return textLayer
        case .symbol(let name, let pointSize, let weight):
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
    }

    /// Decide whether a key should render text or an SF Symbol image.
    private func glyph(for action: KeyAction) -> KeyGlyph {
        switch action {
        case .character(let c):
            return .text(currentShiftUppercase ? c.uppercased() : c.lowercased())
        case .shift:
            // Match native: outline arrow when disabled, filled when enabled, capslock.fill when locked.
            switch currentShiftState {
            case .disabled: return .symbol(name: "shift", pointSize: 17, weight: .regular)
            case .enabled:  return .symbol(name: "shift.fill", pointSize: 17, weight: .regular)
            case .locked:   return .symbol(name: "capslock.fill", pointSize: 17, weight: .regular)
            }
        case .backspace:
            return .symbol(name: "delete.left", pointSize: 19, weight: .regular)
        case .space:
            return .text("")
        case .returnKey:
            if let override = returnKeyOverride {
                return override.prominent
                    ? .text(override.label)
                    : .symbol(name: "return", pointSize: 20, weight: .regular)
            }
            // Default before any label is pushed in: outlined return symbol.
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

    private func characterText(for action: KeyAction, uppercase: Bool) -> String {
        if case .character(let c) = action {
            return uppercase ? c.uppercased() : c.lowercased()
        }
        return ""
    }

    private func textFontSize(for action: KeyAction, keyHeight: CGFloat) -> CGFloat {
        if case .character(let c) = action {
            let ch = c.first
            if ch?.isLetter == true || ch?.isNumber == true { return round(keyHeight * 0.50) }
            return round(keyHeight * 0.43)
        }
        if case .returnKey = action { return round(keyHeight * 0.36) }
        if case .modeChange = action { return round(keyHeight * 0.36) }
        return round(keyHeight * 0.43)
    }

    /// Render an SF Symbol to a `UIImage` of pixel-perfect size at the current screen scale,
    /// tinted to the requested color.
    ///
    /// Results are memoized in a static cache keyed by (name, pointSize, weight, tint).
    /// The distinct set of symbols rendered by V2 is tiny (≤ 8 icons × 2 tints), so the
    /// cache stays well-bounded without eviction. Eliminates `UIGraphicsImageRenderer`
    /// work on every full render, shift toggle, and return-label change.
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
        case .character, .space:
            return isDark
                ? UIColor(white: 0.40, alpha: 0.55)
                : UIColor(white: 1.0, alpha: 0.94)
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
            let prominent = returnKeyOverride?.prominent ?? false
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
