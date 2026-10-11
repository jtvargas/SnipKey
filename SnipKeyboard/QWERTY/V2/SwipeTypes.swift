//
//  SwipeTypes.swift
//  SnipKeyboard
//
//  Value types shared by the swipe-typing pipeline (gesture capture → trail → decoder →
//  commit). Everything here is `Sendable` so the decoder can run off the main thread on a
//  copy of the trace while the finger's next gesture is already being captured.
//
//  Coordinates are keys-area local (origin at the top-left of `KeyboardGestureCoordinator`),
//  the same space as `KeyFrame.rect`.
//

import CoreGraphics
import Foundation

/// One sample of a swipe gesture. `timestamp` is in the `UITouch.timestamp` domain.
struct SwipeTracePoint: Equatable, Sendable {
    let x: CGFloat
    let y: CGFloat
    let timestamp: TimeInterval

    var point: CGPoint { CGPoint(x: x, y: y) }
}

/// The letters-page geometry the decoder scores against: one center per lowercase letter
/// a–z plus the key size (for the location tolerance). Built once per layout by the
/// coordinator from the resolved frames; `hash` identifies that layout for caching.
struct SwipeKeyLayout: Equatable, Sendable {
    let centers: [Character: CGPoint]
    let keyWidth: CGFloat
    let keyHeight: CGFloat
    let hash: Int
}

/// A decoded word with a normalized confidence in 0…1 (1 = best). Results are sorted by
/// descending confidence; the first entry is what commits.
struct SwipeCandidate: Equatable, Sendable {
    let word: String
    let confidence: Float
}
