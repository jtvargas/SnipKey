//
//  EventKitReminderService.swift
//  SnipKey + SnipKeyboard (shared)
//
//  Single encapsulation point for all EventKit reminder work. Keeping the EKReminder write behind
//  one API means "where the write happens" (keyboard direct vs. main-app hand-off) is a localized
//  decision, not spread across call sites. See INTEGRATIONS.md.
//
//  The SAME code runs in both targets. The authorization gate naturally implements
//  "try direct, then fall back":
//    • Main app — the user granted Reminders access here, so `isAuthorized` is true → writes directly.
//    • Keyboard — iOS TCC is per-process/per-bundle-ID; if the keyboard's process does NOT see the
//      app's grant, `isAuthorized` is false → `create` returns `false` and the caller falls back.
//      (Whether the keyboard's process inherits the app's grant must be confirmed on-device.)
//

import EventKit
import Foundation

enum EventKitReminderService {

    /// Lazily allocated, reused store. NOT touched on the keyboard hot path — only the first time a
    /// reminder is actually created (a rare, explicit user action), so the 48 MB keyboard ceiling
    /// is never pressured during typing.
    private static let store = EKEventStore()

    /// Synchronous, in-process TCC cache read — microseconds, no store allocation needed.
    static func authorizationStatus() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .reminder)
    }

    /// True when this process can write reminders. (iOS 17+ uses `.fullAccess`; both targets are
    /// well above that minimum.)
    static var isAuthorized: Bool {
        authorizationStatus() == .fullAccess
    }

    /// APP ONLY — a keyboard extension cannot present the system permission prompt. Completion is
    /// delivered on the main thread.
    static func requestAccess(completion: @escaping (Bool) -> Void) {
        store.requestFullAccessToReminders { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    /// Attempt to create an `EKReminder` due at `dueDate`, with an alarm so the Reminders app
    /// actually fires an alert. Off-main work; `completion` is delivered on the main thread.
    /// `completion(false)` ⇒ the write didn't happen (not authorized / no calendar / save error)
    /// and the caller MUST fall back so a reminder is never silently lost.
    static func create(title: String, dueDate: Date, completion: @escaping (Bool) -> Void) {
        let finish: (Bool) -> Void = { ok in DispatchQueue.main.async { completion(ok) } }
        guard isAuthorized else { finish(false); return }

        Task.detached(priority: .userInitiated) {
            let reminder = EKReminder(eventStore: store)
            reminder.title = title
            // Default reminders list, else the first writable reminders calendar.
            reminder.calendar = store.defaultCalendarForNewReminders()
                ?? store.calendars(for: .reminder).first(where: { $0.allowsContentModifications })
            // A dated reminder (dueDateComponents) PLUS an alarm — both are needed for it to alert.
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: dueDate)
            reminder.addAlarm(EKAlarm(absoluteDate: dueDate))

            guard reminder.calendar != nil else { finish(false); return }
            do {
                try store.save(reminder, commit: true)
                finish(true)
            } catch {
                print("[EventKit] reminder save failed: \(error)")
                finish(false)
            }
        }
    }
}
