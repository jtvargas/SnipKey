//
//  KeyboardCalloutView.swift
//  SnipKeyboard
//
//  Single shared callout overlay for the V2 keyboard. One UIView pre-mounted in
//  the keyboard root; every show/hide is a property mutation inside a CATransaction
//  with implicit animations disabled, so there is zero stutter between keys.
//
//  Two modes:
//    .input    — a continuous "tooth"-shaped path that morphs from a wide rounded
//                bubble at the top through a narrowing neck down to the key shape
//                at the bottom (native iOS style, matching the reference screenshot).
//    .actions  — a flat rounded rectangle above the key with the selected accent
//                slot in system-blue (long-press secondary character menu).
//
//  Phase H caches the input-mode bezier path per (keyWidth, keyHeight) tuple so the
//  expensive path construction runs only when the key size changes — typically once
//  per page change, not per keystroke.
//

import UIKit

/// Render modes for the callout overlay.
enum CalloutMode: Equatable {
    case input(character: String, keyFrame: CGRect)
    case actions(chars: [String], keyFrame: CGRect, selectedIndex: Int)
    /// Long-press on the emoji key: a single small bubble with the (rotated) snippets icon
    /// that switches to the snippets view on release.
    case snippetsSwitch(keyFrame: CGRect)
}

final class KeyboardCalloutView: UIView {

    // MARK: - Input-mode geometry

    /// Width of the bubble portion (top, wider than the key).
    private static let inputBubbleWidth: CGFloat = 60
    /// Height of the bubble portion (excluding neck + key area).
    private static let inputBubbleHeight: CGFloat = 46
    /// Vertical distance over which the shape narrows from bubble width down to key width.
    private static let inputNeckHeight: CGFloat = 12
    /// Corner radius of the top of the bubble.
    private static let inputBubbleCornerRadius: CGFloat = 12
    /// Font size of the displayed character.
    private static let inputFontSize: CGFloat = 28

    // MARK: - Action-mode geometry

    /// Width of each accent slot.
    private static let actionSlotWidth: CGFloat = 44
    /// Height of the accent menu bubble.
    private static let actionBubbleHeight: CGFloat = 48
    /// Corner radius of the accent menu bubble.
    private static let actionCornerRadius: CGFloat = 12
    /// Corner radius of the selected slot's highlight inside the bubble (smaller than the bubble itself).
    private static let actionSlotCornerRadius: CGFloat = 8
    /// Vertical gap between the accent menu's bottom and the key's top.
    private static let actionGapAboveKey: CGFloat = 4
    /// Font size of each accent character.
    private static let actionFontSize: CGFloat = 22

    // MARK: - Layers

    /// Single shape layer that draws the entire callout (tooth-path for input mode,
    /// rounded rect for action mode).
    private let bodyShape = CAShapeLayer()
    /// Selected-slot highlight, only used in action mode (system-blue fill).
    private let highlightShape = CAShapeLayer()

    /// Single character label (input mode).
    private let inputLabel: UILabel = {
        let l = UILabel()
        l.textAlignment = .center
        l.adjustsFontSizeToFitWidth = true
        l.minimumScaleFactor = 0.7
        l.baselineAdjustment = .alignCenters
        return l
    }()

    /// Action-mode labels (built dynamically; reused across long-presses).
    private var actionLabels: [UILabel] = []

    /// Rotated snippets icon shown in `.snippetsSwitch` mode (emoji-key long-press).
    private let snippetsIconLayer = CALayer()

    private var currentMode: CalloutMode?

    /// Slot width used for the current action menu. Wider for multi-character entries
    /// (e.g. ".com" domain menu) so they don't clip. Read by `actionIndex(at:)` so drag
    /// hit-testing matches the rendered slots.
    private var currentActionSlotWidth: CGFloat = KeyboardCalloutView.actionSlotWidth

    /// Last appearance mode we were configured with. Read by `updateSelectedActionIndex`
    /// so re-rendering during a long-press drag keeps the correct dark/light styling.
    private var currentIsDark: Bool = false

    /// Cached input-mode bezier path keyed by key size. Rebuilt only when the key size
    /// changes (i.e. on layout / page-change). Avoids reconstructing the bezier on every
    /// keystroke for the common case where successive presses share a key size.
    private var cachedInputPath: (keySize: CGSize, neckLeftX: CGFloat, path: CGPath)?

    // MARK: - Init

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        // Visibility is driven by layer.opacity (so hide() can fade), not isHidden.
        // Mounted once, kept un-hidden; opacity 0 = invisible (and isUserInteractionEnabled
        // is false, so a 0-opacity callout never intercepts touches).
        isHidden = false
        layer.opacity = 0
        translatesAutoresizingMaskIntoConstraints = true

        layer.addSublayer(bodyShape)
        bodyShape.shadowColor = UIColor.black.cgColor
        bodyShape.shadowOpacity = 0.15
        bodyShape.shadowOffset = CGSize(width: 0, height: 1)
        bodyShape.shadowRadius = 4

        highlightShape.fillColor = UIColor.systemBlue.cgColor
        highlightShape.isHidden = true
        layer.addSublayer(highlightShape)

        snippetsIconLayer.isHidden = true
        layer.addSublayer(snippetsIconLayer)

        addSubview(inputLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: - Public API

    /// Show or update the callout. Idempotent — call with a new mode to switch instantly.
    /// All CALayer mutations happen inside a single CATransaction with implicit animations
    /// disabled, so transitions between keys do not cross-fade.
    func show(_ mode: CalloutMode, isDark: Bool, in parentWidth: CGFloat, animated: Bool = true) {
        currentIsDark = isDark
        // Captured BEFORE the configure mutates them — used to glide from the old key.
        let previousMode = currentMode
        let oldPosition = layer.position
        let oldPath = bodyShape.path
        let wasVisible = (layer.presentation()?.opacity ?? layer.opacity) >= 0.01

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        switch mode {
        case .input(let character, let keyFrame):
            snippetsIconLayer.isHidden = true
            configureInputMode(character: character, keyFrame: keyFrame, isDark: isDark, parentWidth: parentWidth)
        case .actions(let chars, let keyFrame, let selectedIndex):
            snippetsIconLayer.isHidden = true
            configureActionsMode(chars: chars, keyFrame: keyFrame, selectedIndex: selectedIndex, isDark: isDark, parentWidth: parentWidth)
        case .snippetsSwitch(let keyFrame):
            configureSnippetsSwitchMode(keyFrame: keyFrame, isDark: isDark, parentWidth: parentWidth)
        }

        // Cancel any in-flight fade-out and snap to full opacity so a new key never reuses a
        // half-faded bubble.
        layer.removeAnimation(forKey: "calloutFade")
        layer.opacity = 1
        currentMode = mode

        // GLIDE: a still-visible input bubble moving to the next key animates its position
        // (and tooth path, at clamped edges) so it reads as ONE bubble sliding — native feel —
        // rather than a fresh pop above each key. Explicit animations still run inside the
        // disabled-actions transaction (only implicit ones are suppressed).
        if wasVisible, case .input = mode, case .input = previousMode {
            let newPosition = layer.position
            if oldPosition != newPosition {
                let move = CABasicAnimation(keyPath: "position")
                move.fromValue = NSValue(cgPoint: oldPosition)
                move.toValue = NSValue(cgPoint: newPosition)
                move.duration = 0.08
                move.timingFunction = CAMediaTimingFunction(name: .easeOut)
                layer.add(move, forKey: "calloutGlide")
            }
            if let oldPath, let newPath = bodyShape.path, oldPath != newPath {
                let pathAnim = CABasicAnimation(keyPath: "path")
                pathAnim.fromValue = oldPath
                pathAnim.toValue = newPath
                pathAnim.duration = 0.08
                pathAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
                bodyShape.add(pathAnim, forKey: "calloutPathGlide")
            }
            layer.removeAnimation(forKey: "calloutScale")
            layer.transform = CATransform3DIdentity
            return
        }

        // Already visible but not a glide (e.g. switching to/from an accent menu) → no pop.
        guard !wasVisible else { return }

        // First show: a soft "lift" pop (subtler than a bounce, so it reads as the key
        // rising rather than a separate component appearing). Instant during a fast burst.
        if animated {
            layer.transform = CATransform3DMakeScale(0.88, 0.88, 1.0)
            let spring = CASpringAnimation(keyPath: "transform.scale")
            spring.fromValue = 0.88
            spring.toValue = 1.0
            spring.mass = 1.0
            spring.stiffness = 260
            spring.damping = 26
            spring.duration = spring.settlingDuration
            spring.isRemovedOnCompletion = true
            spring.fillMode = .forwards
            layer.add(spring, forKey: "calloutScale")
            layer.transform = CATransform3DIdentity
        } else {
            layer.removeAnimation(forKey: "calloutScale")
            layer.transform = CATransform3DIdentity
        }
    }

    /// Hide the callout. Fades opacity out over ~110ms for a deliberate single press
    /// (native feel); snaps instantly during a fast-typing burst (`fade: false`), since a
    /// fade on the single shared layer would read as the next character dimming.
    func hide(fade: Bool = true) {
        currentMode = nil
        layer.removeAnimation(forKey: "calloutScale")

        if fade {
            CATransaction.begin()
            CATransaction.setDisableActions(false)
            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue = layer.presentation()?.opacity ?? layer.opacity
            anim.toValue = 0
            anim.duration = 0.11
            anim.timingFunction = CAMediaTimingFunction(name: .easeIn)
            anim.fillMode = .forwards
            anim.isRemovedOnCompletion = false
            layer.add(anim, forKey: "calloutFade")
            layer.opacity = 0
            CATransaction.commit()
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.removeAnimation(forKey: "calloutFade")
            layer.transform = CATransform3DIdentity
            layer.opacity = 0
            CATransaction.commit()
        }
    }

    /// Update the highlighted action slot without rebuilding (long-press drag).
    func updateSelectedActionIndex(_ index: Int) {
        guard case .actions(let chars, let keyFrame, let oldIdx) = currentMode, index != oldIdx else { return }
        let parentWidth = superview?.bounds.width ?? bounds.width
        show(.actions(chars: chars, keyFrame: keyFrame, selectedIndex: index), isDark: currentIsDark, in: parentWidth)
    }

    // MARK: - Input Mode (tooth-shape path)

    private func configureInputMode(character: String, keyFrame: CGRect, isDark: Bool, parentWidth: CGFloat) {
        let bubbleW = Self.inputBubbleWidth
        let bubbleH = Self.inputBubbleHeight
        let neckH = Self.inputNeckHeight
        let keyW = keyFrame.width
        let keyH = keyFrame.height
        let totalH = bubbleH + neckH + keyH

        // Position the callout so the BOTTOM of the path aligns with the bottom of the key.
        let keyCenterX = keyFrame.midX
        let proposedX = keyCenterX - bubbleW / 2
        // Clamp horizontally; the bubble center must follow the key center within the
        // available width, but never extend past the keyboard edges.
        let clampedX = max(2, min(proposedX, parentWidth - bubbleW - 2))
        let originY = max(0, keyFrame.minY - bubbleH - neckH)
        frame = CGRect(x: clampedX, y: originY, width: bubbleW, height: totalH)

        // Where the key sits horizontally WITHIN the bubble's local space. When the bubble is
        // clamped at a screen edge (P, Q, A, L, …) this is no longer the bubble center, so the
        // neck/anchor must shift to keep pointing at the real key instead of empty space.
        let keyCenterXInBubble = keyCenterX - clampedX

        // Path (cached by key size + anchor offset so successive presses reuse it).
        let path = inputModePath(bubbleW: bubbleW, bubbleH: bubbleH, neckH: neckH, keyW: keyW, keyH: keyH, keyCenterXInBubble: keyCenterXInBubble)
        bodyShape.path = path
        bodyShape.shadowPath = path
        bodyShape.frame = CGRect(origin: .zero, size: frame.size)
        bodyShape.fillColor = backgroundColor(isDark: isDark)
        highlightShape.isHidden = true

        // Label fills only the bubble portion (top), not the neck or key overlap area.
        inputLabel.isHidden = false
        for label in actionLabels { label.isHidden = true }
        inputLabel.text = character
        inputLabel.font = UIFont.systemFont(ofSize: Self.inputFontSize, weight: .regular)
        inputLabel.textColor = isDark ? .white : .black
        inputLabel.frame = CGRect(x: 0, y: 0, width: bubbleW, height: bubbleH)
    }

    /// Build (or return cached) tooth-shaped path: a rounded-top rectangle (the bubble),
    /// a smooth tapering neck, and a key-width rectangle with rounded bottom corners (the
    /// key-overlay portion). The bubble has square corners at its BOTTOM so the curves to
    /// the neck start tangent-aligned heading south (no kink at the junction).
    private func inputModePath(bubbleW: CGFloat, bubbleH: CGFloat, neckH: CGFloat, keyW: CGFloat, keyH: CGFloat, keyCenterXInBubble: CGFloat) -> CGPath {
        let keySize = CGSize(width: keyW, height: keyH)

        // Anchor the neck/key-overlay under the real key. Clamp so the key portion stays
        // fully inside the bubble even when the bubble itself is clamped at a screen edge.
        let neckLeftX = max(0, min(keyCenterXInBubble - keyW / 2, bubbleW - keyW))

        if let cached = cachedInputPath, cached.keySize == keySize, cached.neckLeftX == neckLeftX {
            return cached.path
        }

        let br = Self.inputBubbleCornerRadius
        let kr: CGFloat = min(8, keyW / 4, keyH / 4)  // key bottom corner radius
        let neckRightX = neckLeftX + keyW
        let bubbleBottomY = bubbleH
        let neckEndY = bubbleH + neckH
        let keyBottomY = bubbleH + neckH + keyH
        let midNeckY = bubbleBottomY + neckH * 0.5

        let path = UIBezierPath()

        // Start at top-left corner exit point and trace clockwise.
        path.move(to: CGPoint(x: br, y: 0))
        // Top edge
        path.addLine(to: CGPoint(x: bubbleW - br, y: 0))
        // Top-right corner
        path.addArc(
            withCenter: CGPoint(x: bubbleW - br, y: br),
            radius: br, startAngle: -.pi / 2, endAngle: 0, clockwise: true
        )
        // Right side of bubble straight down to the bottom-right (square corner —
        // tangent heads south, no kink before the neck curve).
        path.addLine(to: CGPoint(x: bubbleW, y: bubbleBottomY))
        // Smooth S-curve narrowing from bubble bottom-right to neck top-right.
        // Both control points are vertically at mid-neck — produces a clean inward taper.
        path.addCurve(
            to: CGPoint(x: neckRightX, y: neckEndY),
            controlPoint1: CGPoint(x: bubbleW, y: midNeckY),
            controlPoint2: CGPoint(x: neckRightX, y: midNeckY)
        )
        // Down right side of key area
        path.addLine(to: CGPoint(x: neckRightX, y: keyBottomY - kr))
        // Key bottom-right corner
        path.addArc(
            withCenter: CGPoint(x: neckRightX - kr, y: keyBottomY - kr),
            radius: kr, startAngle: 0, endAngle: .pi / 2, clockwise: true
        )
        // Key bottom edge
        path.addLine(to: CGPoint(x: neckLeftX + kr, y: keyBottomY))
        // Key bottom-left corner
        path.addArc(
            withCenter: CGPoint(x: neckLeftX + kr, y: keyBottomY - kr),
            radius: kr, startAngle: .pi / 2, endAngle: .pi, clockwise: true
        )
        // Up left side of key area
        path.addLine(to: CGPoint(x: neckLeftX, y: neckEndY))
        // Mirror S-curve back up to bubble bottom-left
        path.addCurve(
            to: CGPoint(x: 0, y: bubbleBottomY),
            controlPoint1: CGPoint(x: neckLeftX, y: midNeckY),
            controlPoint2: CGPoint(x: 0, y: midNeckY)
        )
        // Up left side of bubble (square corner at bottom-left)
        path.addLine(to: CGPoint(x: 0, y: br))
        // Top-left corner
        path.addArc(
            withCenter: CGPoint(x: br, y: br),
            radius: br, startAngle: .pi, endAngle: 3 * .pi / 2, clockwise: true
        )
        path.close()

        let cg = path.cgPath
        cachedInputPath = (keySize, neckLeftX, cg)
        return cg
    }

    // MARK: - Action Mode (flat rounded rect)

    private func configureActionsMode(chars: [String], keyFrame: CGRect, selectedIndex: Int, isDark: Bool, parentWidth: CGFloat) {
        let slotCount = max(chars.count, 1)
        // Widen slots (and shrink the font) for multi-character entries like ".com" so they
        // don't clip in the default 44pt accent slot.
        let isMultiChar = chars.contains { $0.count > 1 }
        let slotW: CGFloat = isMultiChar ? 58 : Self.actionSlotWidth
        let fontSz: CGFloat = isMultiChar ? 17 : Self.actionFontSize
        currentActionSlotWidth = slotW
        let bubbleWidth = CGFloat(slotCount) * slotW
        let bubbleHeight = Self.actionBubbleHeight

        // Position above the key with a small gap (native iOS doesn't connect via a tail —
        // the action menu floats cleanly above with ~4pt clearance).
        let keyCenterX = keyFrame.midX
        let popupX = keyCenterX - bubbleWidth / 2
        let clampedX = max(2, min(popupX, parentWidth - bubbleWidth - 2))
        let popupY = max(0, keyFrame.minY - bubbleHeight - Self.actionGapAboveKey)
        frame = CGRect(x: clampedX, y: popupY, width: bubbleWidth, height: bubbleHeight)

        // Body: flat rounded rectangle.
        let bodyRect = CGRect(x: 0, y: 0, width: bubbleWidth, height: bubbleHeight)
        let bodyPath = UIBezierPath(roundedRect: bodyRect, cornerRadius: Self.actionCornerRadius).cgPath
        bodyShape.path = bodyPath
        bodyShape.shadowPath = bodyPath
        bodyShape.frame = bodyRect
        bodyShape.fillColor = backgroundColor(isDark: isDark)

        // Highlight slot (system-blue, slightly inset).
        let safeIndex = max(0, min(selectedIndex, slotCount - 1))
        let slotInset: CGFloat = 4
        let highlightRect = CGRect(
            x: CGFloat(safeIndex) * slotW + slotInset,
            y: slotInset,
            width: slotW - slotInset * 2,
            height: bubbleHeight - slotInset * 2
        )
        highlightShape.path = UIBezierPath(roundedRect: highlightRect, cornerRadius: Self.actionSlotCornerRadius).cgPath
        highlightShape.isHidden = false

        // Labels — reuse across calls; only resize/relabel the ones needed.
        inputLabel.isHidden = true
        while actionLabels.count < slotCount {
            let l = UILabel()
            l.textAlignment = .center
            l.font = UIFont.systemFont(ofSize: Self.actionFontSize, weight: .regular)
            addSubview(l)
            actionLabels.append(l)
        }
        if actionLabels.count > slotCount {
            for label in actionLabels[slotCount...] { label.removeFromSuperview() }
            actionLabels.removeLast(actionLabels.count - slotCount)
        }
        for (i, label) in actionLabels.enumerated() {
            label.isHidden = false
            label.text = chars[i]
            label.font = UIFont.systemFont(ofSize: fontSz, weight: .regular)
            label.frame = CGRect(x: CGFloat(i) * slotW, y: 0, width: slotW, height: bubbleHeight)
            label.textColor = (i == safeIndex) ? .white : (isDark ? .white : .black)
        }
    }

    // MARK: - Snippets-switch Mode (single rotated icon)

    private func configureSnippetsSwitchMode(keyFrame: CGRect, isDark: Bool, parentWidth: CGFloat) {
        let bubbleWidth: CGFloat = 52
        let bubbleHeight = Self.actionBubbleHeight

        let keyCenterX = keyFrame.midX
        let popupX = keyCenterX - bubbleWidth / 2
        let clampedX = max(2, min(popupX, parentWidth - bubbleWidth - 2))
        let popupY = max(0, keyFrame.minY - bubbleHeight - Self.actionGapAboveKey)
        frame = CGRect(x: clampedX, y: popupY, width: bubbleWidth, height: bubbleHeight)

        let bodyRect = CGRect(x: 0, y: 0, width: bubbleWidth, height: bubbleHeight)
        let bodyPath = UIBezierPath(roundedRect: bodyRect, cornerRadius: Self.actionCornerRadius).cgPath
        bodyShape.path = bodyPath
        bodyShape.shadowPath = bodyPath
        bodyShape.frame = bodyRect
        bodyShape.fillColor = backgroundColor(isDark: isDark)
        highlightShape.isHidden = true
        inputLabel.isHidden = true
        for label in actionLabels { label.isHidden = true }

        // The snippets icon, "same icon with a little degree angle rotated".
        let tint: UIColor = isDark ? .white : .black
        let img = Self.snippetsIcon(pointSize: 22, tint: tint)
        snippetsIconLayer.isHidden = false
        snippetsIconLayer.contents = img?.cgImage
        snippetsIconLayer.contentsScale = img?.scale ?? UIScreen.main.scale
        let iw = img?.size.width ?? 22
        let ih = img?.size.height ?? 22
        // Reset transform before resizing so bounds/position apply in the unrotated space.
        snippetsIconLayer.transform = CATransform3DIdentity
        snippetsIconLayer.bounds = CGRect(x: 0, y: 0, width: iw, height: ih)
        snippetsIconLayer.position = CGPoint(x: bubbleWidth / 2, y: bubbleHeight / 2)
        snippetsIconLayer.transform = CATransform3DMakeRotation(-15 * .pi / 180, 0, 0, 1)
    }

    /// Tinted `sparkle` SF Symbol image for the snippets-switch callout. Cached.
    private static var cachedSnippetsIcon: (size: CGFloat, rgba: UInt32, image: UIImage?)?
    private static func snippetsIcon(pointSize: CGFloat, tint: UIColor) -> UIImage? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        tint.getRed(&r, green: &g, blue: &b, alpha: &a)
        let rgba = (UInt32(r * 255) << 24) | (UInt32(g * 255) << 16) | (UInt32(b * 255) << 8) | UInt32(a * 255)
        if let c = cachedSnippetsIcon, c.size == pointSize, c.rgba == rgba { return c.image }
        let cfg = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        let img = UIImage(systemName: "sparkle", withConfiguration: cfg)?
            .withTintColor(tint, renderingMode: .alwaysOriginal)
        cachedSnippetsIcon = (pointSize, rgba, img)
        return img
    }

    // MARK: - Style

    private func backgroundColor(isDark: Bool) -> CGColor {
        if isDark {
            return UIColor(white: 0.30, alpha: 1.0).cgColor
        } else {
            return UIColor.white.cgColor
        }
    }

    // MARK: - Hit Testing for Action Menu

    /// Given a finger position in callout-superview coordinates (root view of the keyboard),
    /// return which action slot the finger is over. Returns nil if not in action mode or
    /// outside the bubble.
    func actionIndex(at fingerPoint: CGPoint) -> Int? {
        guard case .actions(let chars, _, _) = currentMode else { return nil }
        let localX = fingerPoint.x - frame.minX
        let slotCount = chars.count
        let bubbleWidth = CGFloat(slotCount) * currentActionSlotWidth
        guard localX >= 0, localX <= bubbleWidth else { return nil }
        let idx = Int(localX / currentActionSlotWidth)
        return max(0, min(idx, slotCount - 1))
    }
}
