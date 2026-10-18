//
//  TimerParseEngine.swift
//  SnipKeyboard
//
//  Natural-language timer parsing for the keyboard. Recognizes `/timer <duration>` and sums every
//  duration token into a total number of seconds (fully on-device, zero latency). Mirrors
//  `ReminderParseEngine` (parser → observable state → suggestion pill), and reuses the same unit
//  synonyms as `ReminderParser`. It accumulates numeric or number-word duration tokens
//  ("one hour and five minutes") and defaults a bare number to seconds ("90").
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

    /// Clamp bounds: a timer must be at least 1 second and at most a day.
    private static let minSeconds = 1
    private static let maxSeconds = 24 * 3600

    /// Duration parsing is shared with reminders; timers permit only hours/minutes/seconds.

    /// Parse the text before the cursor into a timer, or nil if it isn't actionable yet
    /// (no `/timer`, or `/timer` with no duration typed).
    static func parse(from context: String?) -> ParsedTimer? {
        guard let context, !context.isEmpty else { return nil }

        guard let command = CommandSource.suffix(in: context, trigger: trigger) else { return nil }
        var scanned = String(command.dropFirst(trigger.count)).trimmingCharacters(in: .whitespaces)
        if scanned.lowercased().hasPrefix("for ") {
            scanned = String(scanned.dropFirst(4))
        }
        let totalSeconds: Double
        if let tokens = DurationExpression.parse(scanned),
           tokens.allSatisfy({ $0.unit == .second || $0.unit == .minute || $0.unit == .hour }) {
            totalSeconds = tokens.reduce(0) { total, token in
                total + Double(token.amount) * (token.unit == .hour ? 3600 : token.unit == .minute ? 60 : 1)
            }
        } else if !scanned.isEmpty, scanned.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let bare = Double(scanned), bare.isFinite {
            totalSeconds = bare
        } else {
            return nil
        }
        guard totalSeconds >= Double(minSeconds) else { return nil }
        return ParsedTimer(duration: min(totalSeconds, Double(maxSeconds)), triggerText: command)
    }

}

/// Bounded English duration grammar. It validates the entire expression instead of harvesting
/// unrelated digits; original text is never rewritten, so accepted commands retain exact spans.
enum DurationExpression {
    struct Token {
        let amount: Int
        let unit: Calendar.Component
    }

    private static let small: [String: Int] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11,
        "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19,
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60,
        "seventy": 70, "eighty": 80, "ninety": 90
    ]
    private static let ones = "one|two|three|four|five|six|seven|eight|nine"
    private static let amountPattern = #"(?:[0-9]+|(?:twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety)(?:[ -](?:"# + ones + #"))?|seventeen|eighteen|nineteen|thirteen|fourteen|fifteen|sixteen|eleven|twelve|ten|"# + ones + "|an|a)"
    static let tokenPattern = "(" + amountPattern + #")(?:(?<=[0-9])(hours?|minutes?|seconds?|days?|weeks?|months?|hrs?|mins?|secs?|wks?|[smhdw])|\s+(hours?|minutes?|seconds?|days?|weeks?|months?|hrs?|mins?|secs?|wks?))(?![\p{L}_])"#
    static let separatorPattern = #"(?:\s*(?:,|and)\s*|\s*)"#
    private static let regex = try? NSRegularExpression(pattern: tokenPattern, options: [.caseInsensitive])
    private static let separator = try? NSRegularExpression(pattern: "\\A" + separatorPattern + "\\z", options: [.caseInsensitive])

    static func parse(_ expression: String) -> [Token]? {
        guard let regex else { return nil }
        let ns = expression as NSString
        let matches = regex.matches(in: expression, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return nil }
        var end = 0
        var tokens: [Token] = []
        for match in matches {
            let gap = ns.substring(with: NSRange(location: end, length: match.range.location - end))
            if end == 0 {
                guard gap.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            } else {
                guard separator?.firstMatch(in: gap, range: NSRange(location: 0, length: (gap as NSString).length)) != nil else { return nil }
            }
            let number = ns.substring(with: match.range(at: 1)).lowercased()
            guard let amount = numberValue(number) else { return nil }
            let unitRange = match.range(at: match.range(at: 2).location != NSNotFound ? 2 : 3)
            guard let unit = canonicalUnit(ns.substring(with: unitRange)) else { return nil }
            tokens.append(Token(amount: amount, unit: unit))
            end = NSMaxRange(match.range)
        }
        guard ns.substring(from: end).trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return tokens
    }

    private static func numberValue(_ value: String) -> Int? {
        if let numeric = Int(value) { return numeric }
        if let word = small[value] { return word }
        let words = value.split(whereSeparator: { $0 == " " || $0 == "-" })
        guard words.count == 2, let tens = small[String(words[0])],
              let ones = small[String(words[1])], tens >= 20, ones < 10 else { return nil }
        return tens + ones
    }

    private static func canonicalUnit(_ value: String) -> Calendar.Component? {
        switch value.lowercased() {
        case "s", "sec", "secs", "second", "seconds": return .second
        case "m", "min", "mins", "minute", "minutes": return .minute
        case "h", "hr", "hrs", "hour", "hours": return .hour
        case "d", "day", "days": return .day
        case "w", "wk", "wks", "week", "weeks": return .weekOfYear
        case "month", "months": return .month
        default: return nil
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
