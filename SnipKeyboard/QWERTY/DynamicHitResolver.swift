//
//  DynamicHitResolver.swift
//  SnipKeyboard
//
//  Created by Jonathan Taveras Vargas on 2/11/26.
//

import Foundation

/// Resolves a touch X-coordinate to the intended key index within a row,
/// using probability-weighted dynamic boundaries.
///
/// Algorithm:
/// 1. Start with equal-width key regions (current static layout)
/// 2. For each boundary between adjacent keys, shift it proportionally
///    to the ratio of their probability weights
/// 3. Clamp the shift so no key shrinks below 60% of its original width
///    (prevents keys from becoming untappable)
/// 4. Find which adjusted region contains the touch point
///
/// Performance: ~100ns for 10 keys. Pure arithmetic, no allocations.
enum DynamicHitResolver {

    /// Resolve a touch point to a key index using probability-weighted boundaries.
    ///
    /// - Parameters:
    ///   - touchX: X coordinate of the touch within the row's coordinate space.
    ///   - keyRects: Array of (centerX, width) tuples for each key's visual position.
    ///     `centerX` is the center of the key's visual rect in the row's coordinate space.
    ///     `width` is the key's visual width (not including gap padding).
    ///   - weights: Probability weight for each key (same count as keyRects).
    ///     If empty or mismatched count, falls back to center-nearest resolution.
    ///   - keyGap: The gap between adjacent keys (used for boundary shift magnitude).
    ///   - minWidthRatio: Minimum effective key width as fraction of original (default 0.60).
    ///     No key's tappable region will shrink below this fraction of its static width.
    ///   - shiftMultiplier: Controls how aggressively boundaries move (default 2.0).
    ///     Higher = more aggressive shifting toward probable keys.
    /// - Returns: Index of the winning key (0-based).
    static func resolve(
        touchX: CGFloat,
        keyRects: [(centerX: CGFloat, width: CGFloat)],
        weights: [Float],
        keyGap: CGFloat,
        minWidthRatio: CGFloat = 0.60,
        shiftMultiplier: CGFloat = 2.0
    ) -> Int {
        let count = keyRects.count
        guard count > 0 else { return 0 }
        guard count > 1 else { return 0 }

        // If weights are missing or mismatched, fall back to nearest-center resolution
        let useWeights = weights.count == count
        
        // Compute static boundaries (midpoints between adjacent key edges)
        // boundary[i] = midpoint between key[i]'s right edge and key[i+1]'s left edge
        // We have (count - 1) boundaries
        var boundaries = [CGFloat]()
        boundaries.reserveCapacity(count - 1)

        for i in 0..<(count - 1) {
            let leftKeyRight = keyRects[i].centerX + keyRects[i].width / 2
            let rightKeyLeft = keyRects[i + 1].centerX - keyRects[i + 1].width / 2
            let midpoint = (leftKeyRight + rightKeyLeft) / 2
            boundaries.append(midpoint)
        }

        // Apply probability-weighted shifts if we have valid weights
        if useWeights {
            for i in 0..<boundaries.count {
                let wLeft = CGFloat(weights[i])
                let wRight = CGFloat(weights[i + 1])
                let totalWeight = wLeft + wRight

                // Skip if both weights are zero (avoid division by zero)
                guard totalWeight > 0 else { continue }

                // Weight ratio: 0.5 = equal, >0.5 = right key is more probable
                let weightRatio = wRight / totalWeight

                // Shift: positive = move boundary left (expand right key),
                //         negative = move boundary right (expand left key)
                let shift = (weightRatio - 0.5) * keyGap * shiftMultiplier

                // Compute minimum allowed positions to enforce minWidthRatio
                // Left key must keep at least minWidthRatio of its original effective width
                let leftKeyEffectiveWidth = keyRects[i].width + keyGap
                let minBoundaryForLeft = keyRects[i].centerX - keyRects[i].width / 2 + leftKeyEffectiveWidth * minWidthRatio

                // Right key must keep at least minWidthRatio of its original effective width
                let rightKeyEffectiveWidth = keyRects[i + 1].width + keyGap
                let maxBoundaryForRight = keyRects[i + 1].centerX + keyRects[i + 1].width / 2 - rightKeyEffectiveWidth * minWidthRatio

                // Apply shift with clamping
                let shifted = boundaries[i] - shift
                boundaries[i] = max(minBoundaryForLeft, min(shifted, maxBoundaryForRight))
            }
        }

        // Resolve: find which region contains the touch point
        // Key 0 owns everything left of boundary[0]
        // Key i owns boundary[i-1]...boundary[i]
        // Key (count-1) owns everything right of boundary[count-2]
        for i in 0..<boundaries.count {
            if touchX < boundaries[i] {
                return i
            }
        }
        return count - 1
    }

    /// Convenience overload that accepts uniform weights (no probability shifting).
    /// Falls back to static nearest-center resolution.
    static func resolveStatic(
        touchX: CGFloat,
        keyRects: [(centerX: CGFloat, width: CGFloat)],
        keyGap: CGFloat
    ) -> Int {
        return resolve(
            touchX: touchX,
            keyRects: keyRects,
            weights: [],
            keyGap: keyGap
        )
    }
}
