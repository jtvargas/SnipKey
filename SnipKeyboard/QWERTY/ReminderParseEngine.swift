//
//  ReminderParseEngine.swift
//  SnipKeyboard
//
//  Natural-language reminder parsing for the keyboard. Recognizes the explicit
//  `/remind … at <time>` pattern locally with Apple's `NSDataDetector` (C-based, near-zero
//  memory — safe under the extension's 48 MB ceiling, fully on-device, zero latency) and
//  surfaces a "Create reminder" suggestion pill. See LOCAL_NOTIFICATIONS.md.
//

import Foundation
import SwiftUI

// MARK: - Parsed reminder

/// A fully-resolved reminder extracted from typed text.
struct ParsedReminder: Equatable {
    /// The notification body, e.g. "Call the doctor" (capitalized, date/keyword stripped).
    let body: String
    /// Absolute time the reminder should fire (already rolled to tomorrow if the time passed).
    let fireDate: Date
    /// The exact text typed for the command (from `/remind` to the cursor). Its character count
    /// is how many `deleteBackward()` calls remove the command from the field on accept.
    let triggerText: String
    /// True when `fireDate` falls on the current day (drives the toast wording).
    let isToday: Bool

    /// "Create reminder · 3:00 PM" — the short fire-time hint shown on the pill.
    var pillTimeHint: String {
        ParsedReminder.timeFormatter.string(from: fireDate)
    }

    /// "Reminder created for today/tomorrow/Jun 6 at 3:00 PM" — shown in the confirmation toast.
    var toastMessage: String {
        let when: String
        if isToday {
            when = "today"
        } else if Calendar.current.isDateInTomorrow(fireDate) {
            when = "tomorrow"
        } else {
            when = ParsedReminder.dayFormatter.string(from: fireDate)
        }
        return "Reminder created for \(when) at \(ParsedReminder.timeFormatter.string(from: fireDate))"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()
}

// MARK: - Parser

/// Pure parsing logic. Cheap to call on every keystroke — it early-outs unless the text contains
/// the `/remind` trigger, and the detectors are allocated once.
///
/// Intent-aware resolution: rather than trusting `NSDataDetector`'s time (it defaults date-only
/// phrases to noon and misses "noon"/"next week"/bare "at 3"), it separates **which day** from
/// **what time** and decides the time deterministically — explicit clock time → time-of-day phrase
/// → 9 AM default → now + 1 hour. See REMINDER_NLP.md for the full specification.
enum ReminderParser {
    /// The keyword that activates parsing. Kept explicit (no bare "remind me") so the pill never
    /// pops up during normal typing that happens to contain a time.
    static let trigger = "/remind"

    /// Default time for a date with no time of day ("tomorrow", "Friday", "April 15").
    private static let defaultHour = 9

    /// Allocated once — `NSDataDetector` init is comparatively expensive, so never per keystroke.
    private static let detector: NSDataDetector? = {
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
    }()

    /// Relative durations `NSDataDetector` won't parse — both compact shorthand ("10s", "2hr",
    /// "1d", "2w") and spaced words ("15 min", "3 days", "2 weeks"), with an optional leading "in".
    /// Group 1 = amount; group 2 = an **attached** unit (compact — single letters allowed);
    /// group 3 = a **spaced** unit (multi-char only — a bare spaced "m"/"s" is intentionally NOT a
    /// unit, so "2 m&ms" can't read as minutes). The optional "in " is inside the match so it's
    /// stripped from the body cleanly.
    private static let relativeRegex: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: #"\b(?:in\s+)?(\d+)(?:(secs?|mins?|hrs?|wks?|s|m|h|d|w)|\s+(seconds?|minutes?|hours?|days?|weeks?|months?|secs?|mins?|hrs?|wks?))\b"#,
            options: [.caseInsensitive])
    }()

    /// A bare "at <hour>" with no am/pm/colon ("at 3") — `NSDataDetector` ignores these.
    private static let bareHourRegex: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: #"\bat\s+(\d{1,2})\b(?!\s*(?:[ap]m|:|\d))"#,
            options: [.caseInsensitive])
    }()

    /// Deterministic time-of-day phrases → (hour, minute). Ordered so substrings can't shadow a
    /// more specific phrase ("afternoon" must be checked before "noon").
    private static let timeOfDayPhrases: [(phrase: String, hour: Int, minute: Int)] = [
        ("before bed", 21, 0),
        ("lunchtime", 12, 0),
        ("midnight", 0, 0),
        ("afternoon", 15, 0),
        ("morning", 9, 0),
        ("evening", 18, 0),
        ("tonight", 19, 0),
        ("noon", 12, 0),
    ]

    /// Connector/filler words dropped from the start of the task ("/remind me to call" → "call").
    private static let leadConnectors: Set<String> = ["me", "to", "please", "that"]
    /// Connector words left dangling at the END after a time is removed ("… the doctor at").
    private static let trailingConnectors: Set<String> = ["at", "on", "by", "around", "@"]

    /// Parse the text before the cursor into a reminder, or nil if it isn't actionable yet
    /// (no `/remind`, or `/remind` with neither a task nor a time).
    static func parse(from context: String?) -> ParsedReminder? {
        guard let context, !context.isEmpty else { return nil }

        // Cheap guard + anchor on the LAST "/remind" so earlier text never interferes.
        let lower = context.lowercased()
        guard let triggerRange = lower.range(of: trigger, options: .backwards) else { return nil }
        let command = String(context[triggerRange.lowerBound...])

        let now = Date()
        let cal = Calendar.current
        var phrases: [String] = []   // temporal substrings to strip from the task body
        var fire: Date?
        var hadTemporal = false       // did we detect any time/date (vs. the bare now+1h fallback)?

        if let rel = matchRelative(in: command, now: now, cal: cal) {
            phrases.append(rel.phrase); fire = rel.date; hadTemporal = true
        } else if let special = matchSpecialDate(in: command, now: now, cal: cal) {
            phrases.append(special.phrase); fire = special.date; hadTemporal = true
        } else {
            let tod = matchTimeOfDay(in: command)
            if let tod { phrases.append(tod.phrase) }
            let det = matchDetector(in: command)
            if let det { phrases.append(det.phrase) }

            if let det {
                let day = cal.startOfDay(for: det.date)
                if det.hasClockTime {
                    fire = det.date                                   // exact time honored
                } else if let tod {
                    fire = at(tod.hour, tod.minute, on: day, cal: cal) // day + mapped phrase time
                } else {
                    // Date only: a vague "today" has no actionable time (9 AM is likely past) →
                    // now + 1 hour; a future day → 9 AM.
                    fire = cal.isDateInToday(det.date)
                        ? now.addingTimeInterval(3600)
                        : at(defaultHour, 0, on: day, cal: cal)
                }
                hadTemporal = true
            } else if let tod {
                fire = at(tod.hour, tod.minute, on: cal.startOfDay(for: now), cal: cal)
                hadTemporal = true
            } else if let bare = matchBareHour(in: command) {
                phrases.append(bare.phrase)
                fire = at(bare.hour, 0, on: cal.startOfDay(for: now), cal: cal)
                hadTemporal = true
            } else {
                fire = now.addingTimeInterval(3600)                   // nothing temporal → soon
                hadTemporal = false
            }
        }

        guard var resolved = fire else { return nil }
        // Roll a today-resolved time that already passed forward to tomorrow ("at 3pm" at 5pm,
        // "this afternoon" once 3pm passed). Future days are untouched.
        if resolved <= now && cal.isDateInToday(resolved) {
            resolved = cal.date(byAdding: .day, value: 1, to: resolved) ?? resolved
        }

        let body = extractBody(from: command, removing: phrases)
        // Show the pill only when there's a real task OR an explicit time — never for "/remind"
        // alone with nothing entered yet.
        guard body != "Reminder" || hadTemporal else { return nil }

        return ParsedReminder(body: body, fireDate: resolved, triggerText: command,
                              isToday: cal.isDateInToday(resolved))
    }

    // MARK: Time resolution

    /// Build a date at a specific hour/minute on the given day.
    private static func at(_ hour: Int, _ minute: Int, on day: Date, cal: Calendar) -> Date {
        cal.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    /// Map a bare hour to a 24h hour, assuming PM (users rarely mean 3 AM): 3 → 15, 11 → 23, 12 → 12.
    private static func mapBareHour(_ h: Int) -> Int {
        if h == 0 || h == 12 { return h }
        return h < 12 ? h + 12 : h
    }

    /// Resolve a relative duration ("10s", "5m", "2hr", "1d", "2 weeks", "in 45m") to an exact
    /// offset from now — same wall-clock time, never snapped to 9 AM (durations are unambiguous).
    /// Returns the resolved date and the matched substring (incl. any leading "in").
    private static func matchRelative(in command: String, now: Date, cal: Calendar) -> (date: Date, phrase: String)? {
        guard let regex = relativeRegex else { return nil }
        let ns = NSRange(command.startIndex..<command.endIndex, in: command)
        guard let m = regex.firstMatch(in: command, options: [], range: ns),
              let full = Range(m.range, in: command),
              let countRange = Range(m.range(at: 1), in: command),
              let n = Int(command[countRange]) else {
            return nil
        }
        // Unit comes from the attached (group 2) or spaced (group 3) branch, whichever matched.
        let unitText: String
        if let r = Range(m.range(at: 2), in: command) { unitText = String(command[r]) }
        else if let r = Range(m.range(at: 3), in: command) { unitText = String(command[r]) }
        else { return nil }

        guard let unit = canonicalUnit(unitText) else { return nil }
        let phrase = String(command[full])
        let resolved: Date
        switch unit {
        case .second: resolved = now.addingTimeInterval(Double(n))
        case .minute: resolved = now.addingTimeInterval(Double(n * 60))
        case .hour:   resolved = now.addingTimeInterval(Double(n * 3600))
        case .day:    resolved = cal.date(byAdding: .day, value: n, to: now) ?? now
        case .week:   resolved = cal.date(byAdding: .day, value: n * 7, to: now) ?? now
        case .month:  resolved = cal.date(byAdding: .month, value: n, to: now) ?? now
        }
        // UN requires a positive interval; guards "0m" and any clamp edge.
        return (max(resolved, now.addingTimeInterval(1)), phrase)
    }

    private enum DurationUnit { case second, minute, hour, day, week, month }

    /// Normalize every accepted synonym to a canonical unit.
    private static func canonicalUnit(_ text: String) -> DurationUnit? {
        switch text.lowercased() {
        case "s", "sec", "secs", "second", "seconds":  return .second
        case "m", "min", "mins", "minute", "minutes":  return .minute
        case "h", "hr", "hrs", "hour", "hours":        return .hour
        case "d", "day", "days":                        return .day
        case "w", "wk", "wks", "week", "weeks":        return .week
        case "month", "months":                         return .month
        default:                                        return nil
        }
    }

    /// "next week" → next Monday 9 AM; "next month" → first day of next month 9 AM. `NSDataDetector`
    /// doesn't resolve these.
    private static func matchSpecialDate(in command: String, now: Date, cal: Calendar) -> (date: Date, phrase: String)? {
        let lower = command.lowercased()
        if lower.contains("next week") {
            var comp = DateComponents(); comp.weekday = 2 // Monday (Gregorian: Sunday = 1)
            let monday = cal.nextDate(after: now, matching: comp, matchingPolicy: .nextTime) ?? now
            return (at(defaultHour, 0, on: cal.startOfDay(for: monday), cal: cal), "next week")
        }
        if lower.contains("next month") {
            let startOfThisMonth = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
            let firstOfNext = cal.date(byAdding: .month, value: 1, to: startOfThisMonth) ?? now
            return (at(defaultHour, 0, on: firstOfNext, cal: cal), "next month")
        }
        return nil
    }

    /// First matching deterministic time-of-day phrase (e.g. "this afternoon" → 3 PM).
    private static func matchTimeOfDay(in command: String) -> (hour: Int, minute: Int, phrase: String)? {
        let lower = command.lowercased()
        for entry in timeOfDayPhrases where lower.range(of: entry.phrase) != nil {
            return (entry.hour, entry.minute, entry.phrase)
        }
        return nil
    }

    /// `NSDataDetector`'s date plus whether the matched phrase carried an explicit *clock* time.
    private static func matchDetector(in command: String) -> (date: Date, hasClockTime: Bool, phrase: String)? {
        guard let detector else { return nil }
        let ns = NSRange(command.startIndex..<command.endIndex, in: command)
        guard let match = detector.matches(in: command, options: [], range: ns).first,
              let date = match.date,
              let range = Range(match.range, in: command) else {
            return nil
        }
        return (date, hasClockTime(command[range]), String(command[range]))
    }

    /// A clock time = "3:30", "3pm"/"3 pm". (Time-of-day *words* are handled separately and are NOT
    /// clock times — "this afternoon" keeps the day but takes the mapped 3 PM.)
    private static func hasClockTime(_ phrase: Substring) -> Bool {
        let lower = phrase.lowercased()
        if lower.contains(":") { return true }
        return lower.range(of: #"\d\s?[ap]m\b"#, options: .regularExpression) != nil
    }

    /// Bare "at <hour>" → (PM-assumed 24h hour, matched substring).
    private static func matchBareHour(in command: String) -> (hour: Int, phrase: String)? {
        guard let regex = bareHourRegex else { return nil }
        let ns = NSRange(command.startIndex..<command.endIndex, in: command)
        guard let m = regex.firstMatch(in: command, options: [], range: ns),
              let full = Range(m.range, in: command),
              let hourRange = Range(m.range(at: 1), in: command),
              let h = Int(command[hourRange]) else {
            return nil
        }
        return (mapBareHour(h), String(command[full]))
    }

    // MARK: Body

    /// Remove the matched temporal substrings, the "/remind" trigger and leading connectors, any
    /// dangling trailing connector and punctuation, then capitalize. "Reminder" when empty.
    private static func extractBody(from command: String, removing phrases: [String]) -> String {
        var task = command
        // Longest first so a shorter phrase can't partially clip a longer overlapping one.
        for phrase in phrases.sorted(by: { $0.count > $1.count }) where !phrase.isEmpty {
            if let r = task.range(of: phrase, options: [.caseInsensitive]) { task.removeSubrange(r) }
        }
        task = task.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                   .trimmingCharacters(in: .whitespacesAndNewlines)
        if task.lowercased().hasPrefix(trigger) { task = String(task.dropFirst(trigger.count)) }

        var words = task.split(separator: " ").map(String.init)
        while let first = words.first, leadConnectors.contains(first.lowercased()) { words.removeFirst() }
        while let last = words.last, trailingConnectors.contains(last.lowercased()) { words.removeLast() }
        task = words.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:-"))

        guard !task.isEmpty else { return "Reminder" }
        return task.prefix(1).uppercased() + task.dropFirst()
    }
}

// MARK: - Observable state (drives the suggestion pill)

/// Promotes parse results into SwiftUI. Mirrors `SlashCommandState` / `PredictiveTextState`:
/// the controller updates it from the coalesced side-effect flush; the toolbar renders from it.
@MainActor
@Observable
final class ReminderSuggestionState {
    /// The current actionable reminder, or nil when there's nothing to offer.
    var parsed: ParsedReminder?

    /// Whether the "Create reminder" pill should be shown.
    var isActive: Bool { parsed != nil }

    /// One-shot toast payload — `toastToken` bumps each time a reminder is created so the host
    /// view can present a banner via `.onChange`.
    private(set) var toastMessage: String?
    private(set) var toastToken: Int = 0

    nonisolated init() {}

    /// Re-evaluate from a fresh context snapshot. Cheap; `ReminderParser.parse` early-outs.
    func update(context: String?) {
        let next = ReminderParser.parse(from: context)
        if parsed != next { parsed = next }
    }

    /// Clear the active suggestion (after accept, or when the command is no longer present).
    func clear() {
        if parsed != nil { parsed = nil }
    }

    /// Signal that a reminder was created — drives the confirmation toast.
    func signalCreated(_ message: String) {
        toastMessage = message
        toastToken &+= 1
    }
}

// MARK: - SwiftUI Environment Key

extension EnvironmentValues {
    @Entry var reminderSuggestionState: ReminderSuggestionState = ReminderSuggestionState()
}
