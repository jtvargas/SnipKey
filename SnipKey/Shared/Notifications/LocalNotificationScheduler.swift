//
//  LocalNotificationScheduler.swift
//  SnipKey + SnipKeyboard (shared)
//
//  Shared local-notification scheduling, usable from BOTH the keyboard extension and the
//  main app. See LOCAL_NOTIFICATIONS.md.
//

import Foundation
import UserNotifications

/// Actions the reminder system supports. Add a case here (and an arm in
/// `LocalNotificationScheduler.schedule`) to extend without touching call sites.
enum ReminderAction {
    case scheduleReminder
}

/// A request to schedule a local notification. Built by whoever triggers it (keyboard or app).
struct ReminderRequest {
    let action: ReminderAction
    /// Seconds from now to fire. 120 = 2 minutes (the product requirement).
    let fireDelay: TimeInterval
    /// Optional user-facing message used as the notification body.
    let message: String?

    init(action: ReminderAction = .scheduleReminder,
         fireDelay: TimeInterval = 120,
         message: String? = nil) {
        self.action = action
        self.fireDelay = fireDelay
        self.message = message
    }
}

/// Schedules local notifications from either target.
///
/// WHY the keyboard schedules directly: when SnipKey is backgrounded, iOS *suspends* it — a
/// suspended app runs no code, so it cannot schedule on the keyboard's behalf. The keyboard IS
/// running at tap time, so it schedules itself. Once `add` succeeds, the SYSTEM owns the timer and
/// delivers the notification regardless of the app's state (suspended, backgrounded, or closed).
///
/// Authorization stays owned by the MAIN APP — an app extension can't present the system prompt —
/// so the keyboard relies on the app having been granted permission once. The notification is
/// delivered under SnipKey's identity using SnipKey's authorization.
enum LocalNotificationScheduler {

    /// Prefix for every reminder's notification identifier. Lets the in-app list
    /// (`RemindersView`) filter pending/delivered notifications down to ours.
    static let identifierPrefix = "reminder."

    /// Prompts for permission only when undetermined. Call from the MAIN APP.
    static func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    /// Schedules a local notification. Safe to call from the keyboard extension or the app.
    /// No-ops (with a diagnostic) if notifications aren't authorized.
    static func schedule(_ request: ReminderRequest) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional else {
                print("[Reminder] notifications not authorized; nothing scheduled")
                return
            }

            switch request.action {
            case .scheduleReminder:
                let delay = max(request.fireDelay, 1) // UN requires > 0
                let createdAt = Date()
                let fireDate = createdAt.addingTimeInterval(delay)

                let timeFormatter = DateFormatter()
                timeFormatter.dateFormat = "h:mm:ss a"

                let content = UNMutableNotificationContent()
                content.title = "SnipKey"
                content.body = request.message ?? "Reminder from your keyboard."
                // Distinct per reminder so two never look identical (avoids visual coalescing) and
                // the in-app list reads clearly.
                content.subtitle = "Fires at \(timeFormatter.string(from: fireDate))"
                content.sound = .default
                content.userInfo = ["createdAt": createdAt.timeIntervalSince1970]

                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
                // Unique identifier per tap → each tap schedules its own independent notification.
                let identifier = "\(identifierPrefix)\(UUID().uuidString)"
                let req = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                center.add(req) { error in
                    if let error {
                        print("[Reminder] schedule failed: \(error)")
                    } else {
                        print("[Reminder] scheduled \(identifier), fires in \(Int(delay))s")
                    }
                }
            }
        }
    }
}
