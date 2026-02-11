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
/// - Show/hide is pure CALayer property changes — zero layout passes
/// - Spring animation runs on Core Animation render server, not main thread
/// - Total main-thread cost per show/hide: < 0.1ms
///
/// Visual design:
/// - Rounded rectangle body with a downward-pointing callout tail
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

    private let backgroundShape = CAShapeLayer()

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

        // Background shape layer
        backgroundShape.frame = bounds
        backgroundShape.fillColor = UIColor.white.cgColor
        layer.addSublayer(backgroundShape)

        // Shadow on main layer
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.15
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 4

        // Character label — centered in the body area (excluding tail)
        label.frame = CGRect(
            x: 0,
            y: 0,
            width: Self.bodyWidth,
            height: Self.bodyHeight
        )
        addSubview(label)

        // Build the balloon shape path
        updateShapePath()
    }

    // MARK: - Balloon Shape

    /// Builds a rounded rectangle with a downward-pointing triangular tail centered at the bottom.
    private func updateShapePath() {
        let bodyRect = CGRect(x: 0, y: 0, width: Self.bodyWidth, height: Self.bodyHeight)
        let cr = Self.bodyCornerRadius
        let path = UIBezierPath()

        // Start at top-left corner (after corner radius)
        path.move(to: CGPoint(x: cr, y: 0))

        // Top edge
        path.addLine(to: CGPoint(x: Self.bodyWidth - cr, y: 0))
        // Top-right corner
        path.addArc(
            withCenter: CGPoint(x: Self.bodyWidth - cr, y: cr),
            radius: cr, startAngle: -.pi / 2, endAngle: 0, clockwise: true
        )

        // Right edge
        path.addLine(to: CGPoint(x: Self.bodyWidth, y: Self.bodyHeight - cr))
        // Bottom-right corner
        path.addArc(
            withCenter: CGPoint(x: Self.bodyWidth - cr, y: Self.bodyHeight - cr),
            radius: cr, startAngle: 0, endAngle: .pi / 2, clockwise: true
        )

        // Bottom edge right side → tail
        let tailCenterX = Self.bodyWidth / 2
        let tailHalfWidth = Self.tailWidth / 2
        path.addLine(to: CGPoint(x: tailCenterX + tailHalfWidth, y: Self.bodyHeight))

        // Tail right side → tip
        path.addLine(to: CGPoint(x: tailCenterX, y: Self.bodyHeight + Self.tailHeight))

        // Tail tip → left side
        path.addLine(to: CGPoint(x: tailCenterX - tailHalfWidth, y: Self.bodyHeight))

        // Bottom edge left side
        path.addLine(to: CGPoint(x: cr, y: Self.bodyHeight))
        // Bottom-left corner
        path.addArc(
            withCenter: CGPoint(x: cr, y: Self.bodyHeight - cr),
            radius: cr, startAngle: .pi / 2, endAngle: .pi, clockwise: true
        )

        // Left edge
        path.addLine(to: CGPoint(x: 0, y: cr))
        // Top-left corner
        path.addArc(
            withCenter: CGPoint(x: cr, y: cr),
            radius: cr, startAngle: .pi, endAngle: -.pi / 2, clockwise: true
        )

        path.close()
        backgroundShape.path = path.cgPath

        // Use the path as shadow path for GPU-accelerated shadows
        layer.shadowPath = path.cgPath
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
        if isDark {
            backgroundShape.fillColor = UIColor(white: 0.30, alpha: 1.0).cgColor
            label.textColor = .white
        } else {
            backgroundShape.fillColor = UIColor.white.cgColor
            label.textColor = .black
        }

        // Position: center the tail tip on the key's top-center
        // The tail tip is at (bodyWidth/2, bodyHeight + tailHeight) relative to popup origin
        // We want the tail tip to align with keyFrame's top center
        let keyCenterX = keyFrame.midX
        let keyTopY = keyFrame.minY

        let popupX = keyCenterX - Self.bodyWidth / 2
        let popupY = keyTopY - (Self.bodyHeight + Self.tailHeight)

        // Clamp horizontally to stay within keyboard bounds
        let parentWidth = superview?.bounds.width ?? UIScreen.main.bounds.width
        let clampedX = max(2, min(popupX, parentWidth - Self.bodyWidth - 2))

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
