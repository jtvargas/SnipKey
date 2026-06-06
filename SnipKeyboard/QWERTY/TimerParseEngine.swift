//
//  TimerParseEngine.swift
//  SnipKeyboard
//
//  Natural-language timer parsing for the keyboard. Recognizes `/timer <duration>` and sums every
//  duration token into a total number of seconds (fully on-device, zero latency). Mirrors
//  `ReminderParseEngine` (parser → observable state → suggestion pill), and reuses the same unit
//  synonyms as `ReminderParser`. Unlike the reminder parser (which resolves a single relative
//  offset), this ACCUMULATES tokens ("1h 5m 10s") and defaults a bare number to seconds ("90").
//  See the `/timer` plan + INTEGRATIONS.md.
//

import Foundation
import SwiftUI

// MARK: - Parsed timer

/// A fully-resolved countdown timer extracted from typed text.
struct ParsedTimer: Equatable {
    /// Total countdown length in seconds (clamped to [1s, 24h]).
    let duration: TimeInterval
    /// The exact text typed for the command (from `/timer` to the cursor). Its character count is
    /// how many `deleteBackward()` calls remove the command from the field on accept.
    let triggerText: String

    /// "01:30:00" — HH:MM:SS, shown on the pill ("Create timer · 01:30:00").
    var pillDurationHint: String {
        let total = Int(duration.rounded())
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    /// "1h 30m" / "15s" — compact human form for the confirmation toast.
    var humanReadable: String {
        let total = Int(duration.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h)h") }
        if m > 0 { parts.append("\(m)m") }
        if s > 0 || parts.isEmpty { parts.append("\(s)s") }
        return parts.joined(separator: " ")
    }

    /// "Timer set for 1h 30m" — shown in the confirmation toast.
    var toastMessage: String { "Timer set for \(humanReadable)" }
}

// MARK: - Parser

/// Pure parsing logic. Cheap to call on every keystroke — it early-outs unless the text contains
/// the `/timer` trigger, and the detector is allocated once.
enum TimerParser {
    /// The keyword that activates parsing.
    static let trigger = "/timer"

    /// Clamp bounds: a timer must be at least 1 second; AlarmKit/UN countdowns cap at a day.
    private static let minSeconds = 1
    private static let maxSeconds = 24 * 3600

    /// Matches each `<number><unit?>` token. Unit alternation is longest-first so "min" can't be
    /// clipped to "m" (leaving "in"), and "hour" can't be clipped to "h". A missing unit ⇒ seconds.
    /// Allocated once — `NSRegularExpression` init is comparatively expensive.
    private static let tokenRegex: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: #"(\d+)\s*(hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)?"#,
            options: [.caseInsensitive])
    }()

    /// Parse the text before the cursor into a timer, or nil if it isn't actionable yet
    /// (no `/timer`, or `/timer` with no duration typed).
    static func parse(from context: String?) -> ParsedTimer? {
        guard let context, !context.isEmpty else { return nil }

        // Cheap guard + anchor on the LAST "/timer" so earlier text never interferes.
        let lower = context.lowercased()
        guard let triggerRange = lower.range(of: trigger, options: .backwards) else { return nil }
        let command = String(context[triggerRange.lowerBound...])

        guard let regex = tokenRegex else { return nil }
        // Scan only the part AFTER the trigger word so "/timer" itself can't be misread.
        let scanStart = command.index(command.startIndex, offsetBy: trigger.count)
        let scanned = String(command[scanStart...])
        let ns = NSRange(scanned.startIndex..<scanned.endIndex, in: scanned)

        var totalSeconds = 0
        var matchedAny = false
        for m in regex.matches(in: scanned, options: [], range: ns) {
            guard let numRange = Range(m.range(at: 1), in: scanned),
                  let n = Int(scanned[numRange]) else { continue }
            matchedAny = true
            let unit: String? = Range(m.range(at: 2), in: scanned).map { String(scanned[$0]) }
            totalSeconds += n * secondsPerUnit(unit)
        }

        guard matchedAny, totalSeconds >= minSeconds else { return nil }
        let clamped = min(totalSeconds, maxSeconds)
        return ParsedTimer(duration: TimeInterval(clamped), triggerText: command)
    }

    /// Seconds-per-unit using the same synonym set as `ReminderParser.canonicalUnit`. A nil/empty
    /// unit defaults to **seconds** (so "/timer 15" → 15s).
    private static func secondsPerUnit(_ unit: String?) -> Int {
        switch unit?.lowercased() {
        case "h", "hr", "hrs", "hour", "hours":         return 3600
        case "m", "min", "mins", "minute", "minutes":   return 60
        default:                                         return 1   // s/sec/secs/second/seconds + bare number
        }
    }
}

// MARK: - Observable state (drives the suggestion pill)

/// Promotes parse results into SwiftUI. Mirrors `ReminderSuggestionState`: the controller updates
/// it from the coalesced side-effect flush; the toolbar renders the "Create timer" pill from it.
@MainActor
@Observable
final class TimerSuggestionState {
    /// The current actionable timer, or nil when there's nothing to offer.
    var parsed: ParsedTimer?

    /// Whether the "Create timer" pill should be shown.
    var isActive: Bool { parsed != nil }

    /// One-shot toast payload — `toastToken` bumps each time a timer is created.
    private(set) var toastMessage: String?
    private(set) var toastToken: Int = 0

    nonisolated init() {}

    /// Re-evaluate from a fresh context snapshot. Cheap; `TimerParser.parse` early-outs.
    func update(context: String?) {
        let next = TimerParser.parse(from: context)
        if parsed != next { parsed = next }
    }

    /// Clear the active suggestion (after accept, when the command is gone, or when disabled).
    func clear() {
        if parsed != nil { parsed = nil }
    }

    /// Signal that a timer was created — drives the confirmation toast.
    func signalCreated(_ message: String) {
        toastMessage = message
        toastToken &+= 1
    }
}

// MARK: - SwiftUI Environment Key

extension EnvironmentValues {
    @Entry var timerSuggestionState: TimerSuggestionState = TimerSuggestionState()
}
