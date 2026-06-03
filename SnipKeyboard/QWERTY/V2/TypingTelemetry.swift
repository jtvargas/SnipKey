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

    /// Master switch, mirrored from `AppGroupSettings.Key.shadowLoggingEnabled`.
    var enabled = false

    private var buffer: [Event] = []
    private let capacity = 5000
    private(set) var total = 0
    private(set) var disagreements = 0

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

    /// Persist buffer + summary to the App Group container as JSON. Call OFF the hot path
    /// (e.g. `viewWillDisappear`). No-op when disabled or empty.
    func flush() {
        guard enabled, !buffer.isEmpty else { return }
        guard let dir = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroupSettings.suite
        ) else { return }
        let url = dir.appendingPathComponent("telemetry-shadow.json")
        struct Payload: Codable {
            let total: Int
            let disagreements: Int
            let disagreementRate: Double
            let events: [Event]
        }
        let payload = Payload(
            total: total,
            disagreements: disagreements,
            disagreementRate: disagreementRate,
            events: buffer
        )
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
