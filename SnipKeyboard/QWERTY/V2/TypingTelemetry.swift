//
//  TypingTelemetry.swift
//  SnipKeyboard
//
//  Shadow-mode telemetry for the Keyboard V2 next-gen rollout. On every eligible character
//  touch-down, the gesture coordinator resolves BOTH the acting resolver and the non-acting
//  ("shadow") resolver, and records how they compared — WITHOUT logging raw coordinates,
//  characters, or any text. This measures the disagreement rate (the rollout gate in
//  V2_KEYBOARD_NEXTGEN_PLAN §12) and gathers a replayable, privacy-safe touch stream for
//  β / offset calibration (§11).
//
//  On-device only — never transmitted. Capped ring buffer; flushed to the App Group
//  container as JSON (read later by the host app's debug screen / replay harness).
//

import UIKit

@MainActor
final class TypingTelemetry {

    static let shared = TypingTelemetry()

    /// One privacy-safe observation. No characters, no raw coordinates, no text — only the
    /// anonymous key grid positions, whether the two resolvers agreed, and where within the
    /// acting key's rect the touch landed (normalized [0,1]).
    struct Event: Codable {
        let layout: Int     // hash of {page, rounded keys-area width} — distinguishes geometries
        let actRow: Int     // acting key's grid row (NOT the character)
        let actCol: Int     // acting key's grid column
        let shdRow: Int     // shadow key's grid row
        let shdCol: Int     // shadow key's grid column
        let agreed: Bool
        let dx: Float        // normalized x within acting key rect [0,1]
        let dy: Float        // normalized y within acting key rect [0,1]
    }

    struct TouchOutcome: Codable {
        let layout: Int
        let rawRow: Int
        let rawCol: Int
        let resolvedRow: Int
        let resolvedCol: Int
        let runnerUpRow: Int?
        let runnerUpCol: Int?
        let resolvedDiffered: Bool
        let dx: Float
        let dy: Float
        let confidence: Float
        let margin: Float?
        /// Composed cadence × fat-touch β multiplier in effect for this tap (nil for
        /// pre-cadence records). Lets analysis bucket outcomes by typing regime.
        let betaMult: Float?
    }

    /// Master switch, mirrored from `AppGroupSettings.Key.shadowLoggingEnabled`.
    var enabled = false

    private var buffer: [Event] = []
    private var outcomes: [TouchOutcome] = []
    private let capacity = 5000
    private(set) var total = 0
    private(set) var disagreements = 0
    private(set) var outcomeTotal = 0
    private(set) var unresolvedTouchDowns = 0
    private(set) var rawResolvedDisagreements = 0

    private init() {}

    var disagreementRate: Double { total > 0 ? Double(disagreements) / Double(total) : 0 }

    /// Record one acting-vs-shadow comparison. No-op when disabled. Hot-path safe: a few
    /// arithmetic ops + one append (amortized; oldest dropped at capacity).
    func record(layout: Int, acting: KeyFrame, shadow: KeyFrame, point: CGPoint) {
        guard enabled else { return }
        let agreed = acting.action == shadow.action
        let w = max(acting.rect.width, 1)
        let h = max(acting.rect.height, 1)
        let dx = Float(min(max((point.x - acting.rect.minX) / w, 0), 1))
        let dy = Float(min(max((point.y - acting.rect.minY) / h, 0), 1))
        let event = Event(
            layout: layout,
            actRow: acting.rowIndex, actCol: acting.columnIndex,
            shdRow: shadow.rowIndex, shdCol: shadow.columnIndex,
            agreed: agreed, dx: dx, dy: dy
        )
        if buffer.count >= capacity { buffer.removeFirst() }
        buffer.append(event)
        total += 1
        if !agreed { disagreements += 1 }
    }

    func recordOutcome(
        layout: Int,
        raw: KeyFrame,
        resolved: KeyFrame,
        runnerUp: KeyFrame?,
        point: CGPoint,
        confidence: Float,
        margin: Float?,
        betaMult: Float? = nil
    ) {
        guard enabled else { return }
        let w = max(raw.rect.width, 1)
        let h = max(raw.rect.height, 1)
        let dx = Float(min(max((point.x - raw.rect.minX) / w, 0), 1))
        let dy = Float(min(max((point.y - raw.rect.minY) / h, 0), 1))
        let differed = raw.action != resolved.action
        let event = TouchOutcome(
            layout: layout,
            rawRow: raw.rowIndex,
            rawCol: raw.columnIndex,
            resolvedRow: resolved.rowIndex,
            resolvedCol: resolved.columnIndex,
            runnerUpRow: runnerUp?.rowIndex,
            runnerUpCol: runnerUp?.columnIndex,
            resolvedDiffered: differed,
            dx: dx,
            dy: dy,
            confidence: confidence,
            margin: margin,
            betaMult: betaMult
        )
        if outcomes.count >= capacity { outcomes.removeFirst() }
        outcomes.append(event)
        outcomeTotal += 1
        if differed { rawResolvedDisagreements += 1 }
    }

    func recordUnresolvedTouchDown(layout: Int) {
        guard enabled else { return }
        unresolvedTouchDowns += 1
    }

    /// Persist buffer + summary to the App Group container as JSON. Call OFF the hot path
    /// (e.g. `viewWillDisappear`). No-op when disabled or empty.
    func flush() {
        guard enabled, !buffer.isEmpty || !outcomes.isEmpty || unresolvedTouchDowns > 0 else { return }
        guard let dir = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroupSettings.suite
        ) else { return }
        let url = dir.appendingPathComponent("telemetry-shadow.json")
        struct Payload: Codable {
            let total: Int
            let disagreements: Int
            let disagreementRate: Double
            let events: [Event]
            let outcomeTotal: Int
            let unresolvedTouchDowns: Int
            let rawResolvedDisagreements: Int
            let outcomes: [TouchOutcome]
        }
        let payload = Payload(
            total: total,
            disagreements: disagreements,
            disagreementRate: disagreementRate,
            events: buffer,
            outcomeTotal: outcomeTotal,
            unresolvedTouchDowns: unresolvedTouchDowns,
            rawResolvedDisagreements: rawResolvedDisagreements,
            outcomes: outcomes
        )
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

// MARK: - Responsiveness Telemetry

/// DEBUG-only aggregate timing for perceived keyboard responsiveness. It records durations between
/// the touch lifecycle and visible/host callbacks, never text, characters, or coordinates.
@MainActor
final class KeyboardResponsivenessTelemetry {

    static let shared = KeyboardResponsivenessTelemetry()

    struct Metric: Codable {
        private static let capacity = 5000

        var count: Int = 0
        var totalMs: Double = 0
        var maxMs: Double = 0
        var p50Ms: Double = 0
        var p95Ms: Double = 0
        var p99Ms: Double = 0
        private var samples: [Double] = []

        mutating func add(_ ms: Double) {
            count += 1
            totalMs += ms
            maxMs = max(maxMs, ms)
            if samples.count >= Self.capacity { samples.removeFirst() }
            samples.append(ms)
            updatePercentiles()
        }

        private mutating func updatePercentiles() {
            guard !samples.isEmpty else {
                p50Ms = 0
                p95Ms = 0
                p99Ms = 0
                return
            }
            let sorted = samples.sorted()
            p50Ms = Self.percentile(0.50, sorted: sorted)
            p95Ms = Self.percentile(0.95, sorted: sorted)
            p99Ms = Self.percentile(0.99, sorted: sorted)
        }

        private static func percentile(_ p: Double, sorted: [Double]) -> Double {
            guard !sorted.isEmpty else { return 0 }
            let idx = min(max(Int((Double(sorted.count - 1) * p).rounded()), 0), sorted.count - 1)
            return sorted[idx]
        }
    }

    struct Payload: Codable {
        let touchToHighlight: Metric
        let touchToCallout: Metric
        let touchToInsertReturn: Metric
        let touchToTextDidChange: Metric
        let sideEffectFlushDelay: Metric
    }

    var enabled = false

    private var activeTouches: [ObjectIdentifier: CFTimeInterval] = [:]
    private var mostRecentTouchDown: CFTimeInterval?
    private var pendingSideEffectSchedule: CFTimeInterval?

    private var touchToHighlight = Metric()
    private var touchToCallout = Metric()
    private var touchToInsertReturn = Metric()
    private var touchToTextDidChange = Metric()
    private var sideEffectFlushDelay = Metric()

    private init() {}

    func markTouchDown(_ id: ObjectIdentifier) {
        #if DEBUG
        guard enabled else { return }
        let now = CACurrentMediaTime()
        activeTouches[id] = now
        mostRecentTouchDown = now
        #endif
    }

    func markHighlightApplied(_ id: ObjectIdentifier) {
        #if DEBUG
        guard enabled, let start = activeTouches[id] else { return }
        touchToHighlight.add(Self.ms(from: start))
        #endif
    }

    func markCalloutShown(_ id: ObjectIdentifier) {
        #if DEBUG
        guard enabled, let start = activeTouches[id] else { return }
        touchToCallout.add(Self.ms(from: start))
        #endif
    }

    func markInsertReturned(_ id: ObjectIdentifier) {
        #if DEBUG
        guard enabled, let start = activeTouches[id] else { return }
        touchToInsertReturn.add(Self.ms(from: start))
        #endif
    }

    func markTouchEnded(_ id: ObjectIdentifier) {
        #if DEBUG
        activeTouches.removeValue(forKey: id)
        #endif
    }

    func markTextDidChange() {
        #if DEBUG
        guard enabled, let start = mostRecentTouchDown else { return }
        touchToTextDidChange.add(Self.ms(from: start))
        #endif
    }

    func markSideEffectScheduled() {
        #if DEBUG
        guard enabled else { return }
        pendingSideEffectSchedule = CACurrentMediaTime()
        #endif
    }

    func markSideEffectFlushed() {
        #if DEBUG
        guard enabled, let start = pendingSideEffectSchedule else { return }
        sideEffectFlushDelay.add(Self.ms(from: start))
        pendingSideEffectSchedule = nil
        #endif
    }

    func flush() {
        #if DEBUG
        guard enabled else { return }
        guard let dir = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroupSettings.suite
        ) else { return }
        let payload = Payload(
            touchToHighlight: touchToHighlight,
            touchToCallout: touchToCallout,
            touchToInsertReturn: touchToInsertReturn,
            touchToTextDidChange: touchToTextDidChange,
            sideEffectFlushDelay: sideEffectFlushDelay
        )
        let url = dir.appendingPathComponent("telemetry-responsiveness.json")
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: url, options: .atomic)
        }
        #endif
    }

    private static func ms(from start: CFTimeInterval) -> Double {
        (CACurrentMediaTime() - start) * 1000
    }
}
