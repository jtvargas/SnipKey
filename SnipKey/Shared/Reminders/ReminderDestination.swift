//
//  ReminderDestination.swift
//  SnipKey + SnipKeyboard (shared)
//
//  Where a created reminder is delivered. Exactly ONE destination is active at a time; the
//  selected destination always wins (a reminder is never created in both). Shared by BOTH
//  targets: the main app picks it (Integrations → Reminders); the keyboard routes writes by it.
//  See INTEGRATIONS.md.
//

import SwiftUI

enum ReminderDestination: String, Codable, CaseIterable, Identifiable {
    /// Existing local-notification behavior (`UNUserNotificationCenter`). The default — no extra
    /// permission beyond notifications, works today with zero regression.
    case snipKey
    /// Native iOS Reminders app via EventKit (`EKReminder`). Requires Reminders permission,
    /// granted in the main app's Integrations screen.
    case remindersApp

    var id: String { rawValue }

    /// Default + safe fallback when the stored value is missing/unrecognized.
    static let `default`: ReminderDestination = .snipKey

    var displayName: String {
        switch self {
        case .snipKey:      return "SnipKey"
        case .remindersApp: return "Reminders App"
        }
    }

    /// SF Symbol for the picker / row badge.
    var iconName: String {
        switch self {
        case .snipKey:      return "bell.badge"
        case .remindersApp: return "checklist"
        }
    }

    /// Tolerant decode from the App Group string (keyboard reads this synchronously at launch).
    init(appGroupRawValue: String?) {
        self = appGroupRawValue.flatMap(ReminderDestination.init(rawValue:)) ?? .default
    }
}
