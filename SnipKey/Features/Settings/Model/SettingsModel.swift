//
//  SettingsModel.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 4/1/24.
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - App Appearance
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Keyboard After Paste Action
enum KeyboardAfterPasteAction: String, CaseIterable, Identifiable, Codable {
    case rtrn, space, change, changeReturn, nothing
    var id: String { return self.rawValue }
    var displayText: String {
        switch self {
        case .rtrn:
            return "Return"
        case .changeReturn:
            return "Return + Switch"
        case .change:
            return "Switch"
        case .space:
            return "Space"
        case .nothing:
            return "Nothing"
        }
    }
    
}

@Model
final class SettingsModel {
    var settingsId: String = "SnipKey-Settings"

    var testString: String = "Hello there"

    var afterPasteAction: KeyboardAfterPasteAction = KeyboardAfterPasteAction.space

    /// When true, the keyboard extension opens to the QWERTY keyboard instead of the snippet list.
    /// This is an experimental feature — disabled by default.
    var isQWERTYKeyboardEnabled: Bool = false

    /// When true, the keyboard uses the V2 (KeyboardKit-inspired) implementation with a single
    /// root-gesture coordinator, finger-slide tracking, long-press accent menus, and a shared
    /// callout overlay. **Default ON** as of Phase D — V2 is now the recommended keyboard.
    var useNativeKeyboardV2: Bool = true

    /// When true, character-key hit testing shifts boundaries based on English bigram weights
    /// (e.g. after typing "t", the "h" key's hit area expands toward "g"). Matches native
    /// iOS's always-on bigram-aware touch resolver. **Default ON** as of Phase I.
    var probabilisticTouchEnabled: Bool = true

    /// When true, the keyboard auto-capitalizes at sentence starts and replaces lone "i"
    /// with "I" (matches the iOS system Auto-Capitalization setting). When false, the
    /// keyboard always starts lowercase and never auto-caps — the user must tap shift
    /// to capitalize. Default ON to match iOS defaults.
    var autoCapitalizationEnabled: Bool = true

    /// DEBUG only: overlays each key's tiling touch cell (its `hitRect`) with a visible
    /// red border/fill in the V2 keyboard, so the per-key hit coverage ("Voronoi" tiling)
    /// can be inspected. **Default OFF.**
    var debugHitOverlayEnabled: Bool = false

    /// Route letters-page character touches through the V2 next-gen 2D power-diagram resolver
    /// (research-backed defaults + automatic per-user offset learning). **Default ON.**
    /// See V2_KEYBOARD_NEXTGEN_PLAN.
    var useProbabilisticHitResolver: Bool = true

    /// EXPERIMENTAL: shadow-mode telemetry — run the non-acting resolver in parallel and log
    /// how often it disagrees (privacy-safe, on-device only). **Default OFF.** Used to measure
    /// the rollout gate and gather a calibration corpus.
    var shadowLoggingEnabled: Bool = false

    // MARK: - Integrations

    /// Master switch for the Reminders integration (Integrations → Reminders). **Default OFF** so
    /// existing users see no behavior change until they opt in. When OFF, the reminder destination
    /// is forced to `.snipKey` at routing time regardless of the stored picker value.
    var remindersIntegrationEnabled: Bool = false

    /// Where `/remind` (and the 🔔 quick button) deliver. **Default `.snipKey`** = existing
    /// local-notification behavior. Persisted like `afterPasteAction` (a `Codable` enum).
    /// NB: `@Model` requires a fully-qualified default (`ReminderDestination.snipKey`, not `.snipKey`).
    var reminderDestination: ReminderDestination = ReminderDestination.snipKey

    init(
        afterPasteAction: KeyboardAfterPasteAction = .space,
        isQWERTYKeyboardEnabled: Bool = false,
        useNativeKeyboardV2: Bool = true,
        probabilisticTouchEnabled: Bool = true,
        autoCapitalizationEnabled: Bool = true,
        debugHitOverlayEnabled: Bool = false,
        useProbabilisticHitResolver: Bool = true,
        shadowLoggingEnabled: Bool = false,
        remindersIntegrationEnabled: Bool = false,
        reminderDestination: ReminderDestination = .snipKey
    ) {
        self.settingsId = "SnipKey-Settings"
        self.afterPasteAction = afterPasteAction
        self.isQWERTYKeyboardEnabled = isQWERTYKeyboardEnabled
        self.useNativeKeyboardV2 = useNativeKeyboardV2
        self.probabilisticTouchEnabled = probabilisticTouchEnabled
        self.autoCapitalizationEnabled = autoCapitalizationEnabled
        self.debugHitOverlayEnabled = debugHitOverlayEnabled
        self.useProbabilisticHitResolver = useProbabilisticHitResolver
        self.shadowLoggingEnabled = shadowLoggingEnabled
        self.remindersIntegrationEnabled = remindersIntegrationEnabled
        self.reminderDestination = reminderDestination
    }
}

// MARK: - App Group Settings Bridge

/// Synchronous read/write of experimental settings via shared App Group UserDefaults.
/// The keyboard extension needs synchronous reads at launch (SwiftData fetch is async).
/// The main app's SettingsViewModel mirrors writes here every time the SwiftData settings change.
enum AppGroupSettings {
    static let suite = "group.snipkey"

    enum Key {
        static let useNativeKeyboardV2 = "useNativeKeyboardV2"
        static let probabilisticTouchEnabled = "probabilisticTouchEnabled"
        static let autoCapitalizationEnabled = "autoCapitalizationEnabled"
        static let debugHitOverlayEnabled = "debugHitOverlayEnabled"
        /// Staged-enablement flag for the 2D power-diagram hit resolver (Keyboard V2
        /// next-gen engine). Default OFF — gated rollout per V2_KEYBOARD_NEXTGEN_PLAN.
        /// When off, the legacy 1D `SmartTouchResolver` path is used unchanged.
        static let useProbabilisticHitResolver = "useProbabilisticHitResolver"
        /// Shadow-mode telemetry: run the non-acting resolver in parallel and log how often
        /// it disagrees with the acting one (privacy-safe aggregates). Default OFF. Drives
        /// the rollout gate + β/offset calibration in V2_KEYBOARD_NEXTGEN_PLAN §11–§12.
        static let shadowLoggingEnabled = "shadowLoggingEnabled"
        /// Master enable for the Reminders integration. When false, the keyboard behaves exactly
        /// as today (SnipKey local notifications only). Bool.
        static let remindersIntegrationEnabled = "remindersIntegrationEnabled"
        /// Active reminder destination — `ReminderDestination.rawValue` ("snipKey"/"remindersApp").
        /// The keyboard reads this synchronously once per session to route reminder creation. String.
        static let reminderDestination = "reminderDestination"
    }

    static func bool(forKey key: String, default defaultValue: Bool = false) -> Bool {
        UserDefaults(suiteName: suite)?.object(forKey: key) as? Bool ?? defaultValue
    }

    static func setBool(_ value: Bool, forKey key: String) {
        UserDefaults(suiteName: suite)?.set(value, forKey: key)
    }

    static func string(forKey key: String, default defaultValue: String) -> String {
        UserDefaults(suiteName: suite)?.string(forKey: key) ?? defaultValue
    }

    static func setString(_ value: String, forKey key: String) {
        UserDefaults(suiteName: suite)?.set(value, forKey: key)
    }
}
