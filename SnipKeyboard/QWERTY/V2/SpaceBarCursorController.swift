//
//  SpaceBarCursorController.swift
//  SnipKeyboard
//
//  Native-iOS-style space-bar cursor drag.
//  Hold space 250ms → engage cursor mode with a haptic; drag horizontally to move the caret.
//  Release without inserting a space.
//

import UIKit

@MainActor
final class SpaceBarCursorController {

    /// Hold duration before cursor mode engages.
    static let engageDelay: Duration = .milliseconds(250)

    /// Points of finger travel per single character of caret movement.
    /// Matches iOS native: ~12pt per character at standard system font scale.
    static let pointsPerChar: CGFloat = 12

    /// Maximum threshold to *also* engage cursor mode early — if the finger drifts
    /// more than this from its start point while still on the space bar, treat it as
    /// a cursor drag without waiting for the timer.
    static let dragEngageThreshold: CGFloat = 14

    private var engageTask: Task<Void, Never>?
    private var startX: CGFloat = 0
    private var lastCommittedX: CGFloat = 0
    private(set) var isActive: Bool = false

    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    /// Called when the finger touches down on the space key.
    func beginPress(at point: CGPoint, onEngage: @escaping @MainActor () -> Void) {
        cancel()
        startX = point.x
        lastCommittedX = point.x
        isActive = false

        haptic.prepare()
        engageTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.engageDelay)
            guard !Task.isCancelled, let self else { return }
            self.engage(onEngage: onEngage)
        }
    }

    /// Called from touchesMoved. Returns the integer caret delta to apply (positive = right).
    /// Engages cursor mode early if drift exceeds threshold.
    @discardableResult
    func updateFinger(at point: CGPoint, onEngage: @escaping @MainActor () -> Void) -> Int {
        if !isActive {
            // Engage early if the user clearly started dragging
            if abs(point.x - startX) >= Self.dragEngageThreshold {
                engage(onEngage: onEngage)
            } else {
                return 0
            }
        }

        let delta = point.x - lastCommittedX
        let charsToMove = Int(delta / Self.pointsPerChar)
        if charsToMove != 0 {
            lastCommittedX += CGFloat(charsToMove) * Self.pointsPerChar
            return charsToMove
        }
        return 0
    }

    /// Returns true if the press should suppress the normal space insertion (cursor mode engaged).
    @discardableResult
    func endPress() -> Bool {
        let wasActive = isActive
        cancel()
        return wasActive
    }

    /// Cancel without committing.
    func cancel() {
        engageTask?.cancel()
        engageTask = nil
        isActive = false
    }

    private func engage(onEngage: @MainActor () -> Void) {
        guard !isActive else { return }
        isActive = true
        engageTask?.cancel()
        engageTask = nil
        haptic.impactOccurred()
        onEngage()
    }
}
