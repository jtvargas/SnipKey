//
//  SwipeGestureController.swift
//  SnipKeyboard
//
//  Captures one swipe gesture at a time, buffering the first letter before recognition.
//  Distance-based activation preserves short slide-to-correct gestures. Recognition
//  thresholds are SnipKey tuning, not recovered SwiftKey or QuickPath constants.
//
//  Owns no UI and no decoding; the coordinator reacts to the returned `Event`s.
//

import CoreGraphics
import Foundation

@MainActor
final class SwipeGestureController {

    /// Distances scale with the rendered letter-key width.
    enum Thresholds {
        /// Preserve a one-key slide-to-correct; short adjacent-letter words can be tapped
        /// or drawn with a wider curve.
        static let activation: CGFloat = 1.5
        /// Accumulated tremor near the start must not activate word insertion.
        static let minimumExcursion: CGFloat = 0.8
    }

    enum Event {
        /// Sample buffered; the press is still a tap/slide.
        case buffered
        /// The press just became a swipe. `replay` holds every sample since touch-down.
        case activated(replay: [SwipeTracePoint])
        /// Sample appended to an active swipe.
        case sampled(SwipeTracePoint)
        /// Not this controller's touch (another finger, or capture not armed).
        case ignored
    }

    private(set) var ownerTouchID: ObjectIdentifier?
    private(set) var isActive = false
    private var samples: [SwipeTracePoint] = []
    private var pathLength: CGFloat = 0
    private var keyWidth: CGFloat = 1
    private var maximumExcursion: CGFloat = 0
    private static let maximumSamples = 512

    init() {
        samples.reserveCapacity(512)
    }

    // MARK: - Lifecycle

    /// Arm capture for a letter touch-down. Ignored while another finger's swipe is active.
    func arm(touchID: ObjectIdentifier, point: CGPoint, timestamp: TimeInterval, keyWidth: CGFloat) {
        guard !isActive else { return }
        ownerTouchID = touchID
        self.keyWidth = max(keyWidth, 1)
        pathLength = 0
        maximumExcursion = 0
        samples.removeAll(keepingCapacity: true)
        samples.append(SwipeTracePoint(x: point.x, y: point.y, timestamp: timestamp))
    }

    func append(touchID: ObjectIdentifier, point: CGPoint, timestamp: TimeInterval) -> Event {
        guard touchID == ownerTouchID, let last = samples.last, let first = samples.first else { return .ignored }
        let distance = hypot(point.x - last.x, point.y - last.y)
        guard distance >= 1 else { return .buffered }
        let sample = SwipeTracePoint(x: point.x, y: point.y, timestamp: timestamp)
        pathLength += distance
        maximumExcursion = max(maximumExcursion, hypot(point.x - first.x, point.y - first.y))
        if samples.count == Self.maximumSamples {
            // Compact in place, retaining the first point and most recent endpoint.
            var destination = 1
            for source in stride(from: 2, to: samples.count - 1, by: 2) {
                samples[destination] = samples[source]
                destination += 1
            }
            samples[destination] = last
            samples.removeLast(samples.count - destination - 1)
        }
        samples.append(sample)
        if isActive { return .sampled(sample) }
        if pathLength >= Thresholds.activation * keyWidth &&
            maximumExcursion >= Thresholds.minimumExcursion * keyWidth {
            isActive = true
            return .activated(replay: samples)
        }
        return .buffered
    }

    /// Finish the owner's touch. Returns a recognised trace; always disarms.
    func end(touchID: ObjectIdentifier) -> [SwipeTracePoint]? {
        guard touchID == ownerTouchID else { return nil }
        defer { disarm() }
        guard isActive else { return nil }
        return samples
    }

    /// Drop the owner's capture (touch cancelled, press voided, layout changed).
    func cancel(touchID: ObjectIdentifier) {
        guard touchID == ownerTouchID else { return }
        disarm()
    }

    func cancelAll() {
        disarm()
    }

    private func disarm() {
        ownerTouchID = nil
        isActive = false
        pathLength = 0
        maximumExcursion = 0
        samples.removeAll(keepingCapacity: true)
    }
}
