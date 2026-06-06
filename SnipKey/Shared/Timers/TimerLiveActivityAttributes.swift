//
//  TimerLiveActivityAttributes.swift
//  SnipKey + SnipKeyboard + SnipKeyTimerWidget (shared)
//
//  The AlarmKit attributes type for SnipKey timers. AlarmKit's `AlarmAttributes` IS an
//  ActivityKit `ActivityAttributes`, so this exact type must be identical in every target that
//  builds it (app + keyboard) or renders its Live Activity (the widget extension) — otherwise the
//  Dynamic Island / Lock Screen countdown won't bind. See INTEGRATIONS.md / the `/timer` plan.
//

import AlarmKit
import Foundation

/// Empty metadata — we only create timers, no custom per-alarm data. Must be `Sendable`.
nonisolated struct SnipKeyTimerMetadata: AlarmMetadata {
    init() {}
}

/// The concrete attributes type shared across the app, keyboard, and widget extension.
typealias SnipKeyTimerAttributes = AlarmAttributes<SnipKeyTimerMetadata>
