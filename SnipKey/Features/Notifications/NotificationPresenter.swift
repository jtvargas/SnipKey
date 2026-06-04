//
//  NotificationPresenter.swift
//  SnipKey (main app only)
//
//  Main-app notification delegate. Its only job is to present banners while SnipKey is in the
//  FOREGROUND at fire time (the system handles delivery on its own when the app is backgrounded
//  or closed). Scheduling lives in `LocalNotificationScheduler` (shared) and is triggered by the
//  keyboard. See LOCAL_NOTIFICATIONS.md.
//

import Foundation
import UserNotifications

final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationPresenter()

    /// Posted when the set of reminders may have changed (e.g. one just fired in-foreground),
    /// so UI like the Snippets bell badge can refresh its pending count.
    static let remindersDidChange = Notification.Name("SnipKey.remindersDidChange")

    private override init() { super.init() }

    /// Set the delegate before launch finishes (call from `SnipKeyApp.init()`), otherwise
    /// `willPresent` won't fire for a notification delivered while the app is foreground.
    func bootstrap() {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // A reminder just fired (moved pending → delivered) — let the badge refresh.
        NotificationCenter.default.post(name: Self.remindersDidChange, object: nil)
        // Present banner + sound even when the app is foreground at fire time.
        completionHandler([.banner, .sound])
    }
}
