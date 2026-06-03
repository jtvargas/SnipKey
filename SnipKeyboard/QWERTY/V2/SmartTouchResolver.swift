//
//  SmartTouchResolver.swift
//  SnipKeyboard
//
//  Wraps the existing `DynamicHitResolver` for use by the V2 gesture coordinator.
//  After V2's `findKey(at:)` returns the visually-hit key, this resolver checks
//  whether the previous character makes a neighbor more likely (via bigram weights)
//  and may return that neighbor instead.
//
//  Native iOS's keyboard does similar probabilistic correction implicitly — the
//  user feels their taps land on the "right" key even when they're slightly off.
//
//  Performance: ~200ns per call (filter row + weight lookup + boundary math).
//  Returns the original `rawKey` unchanged whenever:
//    - The action isn't a character key
//    - Smart touch is disabled in Settings
//    - The row only has one character key
//    - The resolver finds no shift large enough to change the winning key
//

import UIKit

@MainActor
enum SmartTouchResolver {

    /// If smart touch is enabled and the touch is on a row of character keys, apply the
    /// bigram-weighted boundary shift to potentially redirect to an adjacent key. Otherwise
    /// returns `rawKey` unchanged.
    static func resolve(
        rawKey: KeyFrame,
        point: CGPoint,
        frames: [KeyFrame],
        touchContext: ProbabilisticTouchContext,
        dims: KeyboardDimensions
    ) -> KeyFrame {
        // Only re-resolve character-key touches. Non-character keys (shift/space/return)
        // are always the visually-hit target.
        guard case .character = rawKey.action else { return rawKey }
        // Settings gate. Default ON as of Phase I.
        guard AppGroupSettings.bool(forKey: AppGroupSettings.Key.probabilisticTouchEnabled, default: true) else {
            return rawKey
        }

        // Collect character keys in the same row as the raw hit, ordered left-to-right.
        // `frames` arrives in row-major order from the resolver, so this filter is
        // already correctly ordered.
        var rowFrames: [KeyFrame] = []
        rowFrames.reserveCapacity(10)
        var rowChars: [String] = []
        rowChars.reserveCapacity(10)
        for f in frames where f.rowIndex == rawKey.rowIndex {
            if case .character(let c) = f.action {
                rowFrames.append(f)
                rowChars.append(c)
            }
        }
        guard rowFrames.count > 1 else { return rawKey }

        // Build (centerX, width) tuples and weights aligned with rowFrames.
        let keyRects: [(centerX: CGFloat, width: CGFloat)] = rowFrames.map {
            ($0.rect.midX, $0.rect.width)
        }
        let weights = touchContext.weightsForRow(rowChars)

        // Run the existing resolver. It accounts for boundary shifts and clamps so no
        // key shrinks below 60% of its width.
        let resolvedIndex = DynamicHitResolver.resolve(
            touchX: point.x,
            keyRects: keyRects,
            weights: weights,
            keyGap: dims.keyGap
        )

        guard resolvedIndex >= 0 && resolvedIndex < rowFrames.count else { return rawKey }
        return rowFrames[resolvedIndex]
    }
}
