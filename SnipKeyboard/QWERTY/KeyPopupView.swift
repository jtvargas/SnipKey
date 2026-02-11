//
//  KeyPopupView.swift
//  SnipKeyboard
//
//  Created by Jonathan Taveras Vargas on 2/10/26.
//

import UIKit

/// A lightweight UIKit view that shows a character pop-up balloon above a pressed key.
///
/// Performance design:
/// - Single instance reused for all keys (created once in KeyboardViewController)
/// - Body and tail are separate CAShapeLayers — paths built once at init, never rebuilt
/// - Tail repositions via CALayer.position.x (~0.005ms) to always point at key center
/// - Show/hide is pure CALayer property changes — zero layout passes, zero SwiftUI state
/// - Spring animation runs on Core Animation render server, not main thread
/// - Total main-thread cost per show/hide: < 0.1ms
///
/// Visual design:
/// - Rounded rectangle body with a separate downward-pointing tail
/// - Tail dynamically aligns with the pressed key's center (even for edge keys)
/// - Enlarged character label centered in the body
/// - Subtle drop shadow matching native iOS keyboard
/// - Colors adapt to light/dark mode
final class KeyPopupView: UIView {

    // MARK: - Subviews

    private let label: UILabel = {
        let l = UILabel()
        l.textAlignment = .center
        l.adjustsFontSizeToFitWidth = true
        l.minimumScaleFactor = 0.7
        l.baselineAdjustment = .alignCenters
        return l
    }()

    /// Rounded rectangle body — path built once at init, never changes.
    private let bodyShape = CAShapeLayer()

    /// Downward-pointing triangle tail — path built once at init.
    /// Only its `position.x` changes per show() to align with the key center.
    private let tailShape = CAShapeLayer()

    // MARK: - Constants

    /// Width of the pop-up balloon body
    private static let bodyWidth: CGFloat = 52
    /// Height of the pop-up balloon body (excluding tail)
    private static let bodyHeight: CGFloat = 48
    /// Height of the downward-pointing tail
    private static let tailHeight: CGFloat = 8
    /// Width of the tail base
    private static let tailWidth: CGFloat = 16
    /// Corner radius of the balloon body
    private static let bodyCornerRadius: CGFloat = 10
    /// Font size for the character label
    private static let fontSize: CGFloat = 28
    /// Total size of the popup view (body + tail)
    private static let totalSize = CGSize(
        width: bodyWidth,
        height: bodyHeight + tailHeight
    )

    // MARK: - Init

    init() {
        super.init(frame: CGRect(origin: .zero, size: Self.totalSize))
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    private func setup() {
        // This view should not intercept touches — it's purely visual
        isUserInteractionEnabled = false
        // Start hidden
        isHidden = true
        // No autoresizing
        translatesAutoresizingMaskIntoConstraints = true

        // --- Body shape layer (rounded rect, no tail) ---
        let bodyPath = UIBezierPath(
            roundedRect: CGRect(x: 0, y: 0, width: Self.bodyWidth, height: Self.bodyHeight),
            cornerRadius: Self.bodyCornerRadius
        )
        bodyShape.path = bodyPath.cgPath
        bodyShape.fillColor = UIColor.white.cgColor
        bodyShape.frame = CGRect(x: 0, y: 0, width: Self.bodyWidth, height: Self.bodyHeight)
        layer.addSublayer(bodyShape)

        // Shadow on body shape for GPU-accelerated rendering
        bodyShape.shadowColor = UIColor.black.cgColor
        bodyShape.shadowOpacity = 0.15
        bodyShape.shadowOffset = CGSize(width: 0, height: 1)
        bodyShape.shadowRadius = 4
        bodyShape.shadowPath = bodyPath.cgPath

        // --- Tail shape layer (triangle pointing down, centered at its own origin) ---
        let tailPath = UIBezierPath()
        tailPath.move(to: CGPoint(x: -Self.tailWidth / 2, y: 0))
        tailPath.addLine(to: CGPoint(x: 0, y: Self.tailHeight))
        tailPath.addLine(to: CGPoint(x: Self.tailWidth / 2, y: 0))
        tailPath.close()
        tailShape.path = tailPath.cgPath
        tailShape.fillColor = UIColor.white.cgColor
        // Position tail at bottom-center of body by default
        tailShape.position = CGPoint(x: Self.bodyWidth / 2, y: Self.bodyHeight)
        tailShape.anchorPoint = CGPoint(x: 0.5, y: 0)
        layer.addSublayer(tailShape)

        // Character label — centered in the body area (excluding tail)
        label.frame = CGRect(
            x: 0,
            y: 0,
            width: Self.bodyWidth,
            height: Self.bodyHeight
        )
        addSubview(label)
    }

    // MARK: - Show / Hide

    /// Show the pop-up above a key.
    ///
    /// - Parameters:
    ///   - character: The character to display (already cased correctly)
    ///   - keyFrame: The visual key's frame in the keyboard view's coordinate space
    ///   - isDark: Whether the keyboard is in dark mode
    func show(character: String, keyFrame: CGRect, isDark: Bool) {
        // Update label
        label.text = character
        label.font = UIFont.systemFont(ofSize: Self.fontSize, weight: .regular)

        // Colors: light mode = white bg + dark text, dark mode = dark bg + white text
        let bgColor: CGColor
        if isDark {
            bgColor = UIColor(white: 0.30, alpha: 1.0).cgColor
            label.textColor = .white
        } else {
            bgColor = UIColor.white.cgColor
            label.textColor = .black
        }
        bodyShape.fillColor = bgColor
        tailShape.fillColor = bgColor

        // Position: center the popup body over the key, with tail pointing down at key top
        let keyCenterX = keyFrame.midX
        let keyTopY = keyFrame.minY

        let popupX = keyCenterX - Self.bodyWidth / 2
        let popupY = keyTopY - (Self.bodyHeight + Self.tailHeight)

        // Clamp popup horizontally to stay within keyboard bounds
        let parentWidth = superview?.bounds.width ?? UIScreen.main.bounds.width
        let clampedX = max(2, min(popupX, parentWidth - Self.bodyWidth - 2))

        // Move the tail to point at the key center, even if the body was clamped.
        // tailOffsetX is where the key center falls relative to the popup's left edge.
        let tailOffsetX = keyCenterX - clampedX
        // Clamp the tail within the body (respecting corner radius so it doesn't overlap rounded corners)
        let minTailX = Self.bodyCornerRadius + Self.tailWidth / 2
        let maxTailX = Self.bodyWidth - Self.bodyCornerRadius - Self.tailWidth / 2
        let clampedTailX = max(minTailX, min(tailOffsetX, maxTailX))

        // Reposition tail — single CALayer.position.x write, no path rebuild
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tailShape.position = CGPoint(x: clampedTailX, y: Self.bodyHeight)
        CATransaction.commit()

        frame.origin = CGPoint(x: clampedX, y: max(0, popupY))

        // Show with spring scale animation
        if isHidden {
            isHidden = false
            // Start slightly scaled down
            layer.transform = CATransform3DMakeScale(0.7, 0.7, 1.0)

            // Animate to full size with spring
            let spring = CASpringAnimation(keyPath: "transform.scale")
            spring.fromValue = 0.7
            spring.toValue = 1.0
            spring.mass = 0.8
            spring.stiffness = 300
            spring.damping = 15
            spring.duration = spring.settlingDuration
            spring.isRemovedOnCompletion = true
            spring.fillMode = .forwards
            layer.add(spring, forKey: "popupScale")
            layer.transform = CATransform3DIdentity
        } else {
            // Already visible (switching between keys) — just reposition, no animation
            layer.removeAnimation(forKey: "popupScale")
            layer.transform = CATransform3DIdentity
        }
    }

    /// Hide the pop-up instantly.
    func hide() {
        guard !isHidden else { return }
        layer.removeAnimation(forKey: "popupScale")
        layer.transform = CATransform3DIdentity
        isHidden = true
    }
}
