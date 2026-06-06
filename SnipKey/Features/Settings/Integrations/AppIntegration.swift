//
//  AppIntegration.swift
//  SnipKey (main app only)
//
//  Lightweight, extensible description of the integrations shown in Settings → Integrations.
//  Deliberately NOT a god-protocol: the only thing that varies between integrations today is
//  list presentation + which detail screen to push. Runtime behavior (EventKit writes, etc.) lives
//  in dedicated services (e.g. `EventKitReminderService`), so this stays a plain value descriptor.
//  Adding a 2nd integration = one new `IntegrationID` case + one `IntegrationDescriptor` + a detail
//  view; the list loop in `IntegrationsView` needs no changes. See INTEGRATIONS.md.
//

import SwiftUI

/// Stable identifier for an integration. Adding one starts here.
enum IntegrationID: String, CaseIterable, Identifiable {
    case reminders
    case timer
    var id: String { rawValue }
}

/// Presentation descriptor for one row in the Integrations list.
struct IntegrationDescriptor: Identifiable {
    let id: IntegrationID
    let title: String
    let subtitle: String
    let iconName: String          // SF Symbol, rendered in the 28×28 badge
    let iconColor: Color
    /// Whether this integration is currently on, derived from settings. Drives the dynamic
    /// "N on" count so it's never hardcoded — a new integration just provides its own flag.
    let isEnabled: (SettingsModel) -> Bool
    /// Builds the detail screen. Type-erased so the registry stays a plain value array.
    let makeDetail: () -> AnyView
}

/// Single source of truth for the Integrations list. Order here = display order.
enum IntegrationRegistry {
    static let all: [IntegrationDescriptor] = [
        IntegrationDescriptor(
            id: .reminders,
            title: "Reminders",
            subtitle: "Create reminders in SnipKey or Apple Reminders",
            iconName: "checklist",
            iconColor: .red,
            isEnabled: { $0.remindersIntegrationEnabled },
            makeDetail: { AnyView(RemindersIntegrationView()) }
        ),
        IntegrationDescriptor(
            id: .timer,
            title: "Timers",
            subtitle: "Start countdown timers from the keyboard",
            iconName: "timer",
            iconColor: .indigo,
            isEnabled: { $0.timerIntegrationEnabled },
            makeDetail: { AnyView(TimerIntegrationView()) }
        )
    ]

    /// How many integrations are currently on (powers the "N on" badge). Extensible: counts
    /// every registered integration's own `isEnabled`, so adding a second needs no changes here.
    static func enabledCount(_ settings: SettingsModel?) -> Int {
        guard let settings else { return 0 }
        return all.filter { $0.isEnabled(settings) }.count
    }
}
