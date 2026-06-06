//
//  AlarmKitTimerService.swift
//  SnipKey + SnipKeyboard (shared)
//
//  Single encapsulation point for AlarmKit timer creation — mirrors `EventKitReminderService`.
//  The SAME code runs in both targets; the authorization gate implements "try direct, then fall
//  back": the main app (which owns the permission prompt) is authorized and schedules a real
//  AlarmKit countdown (Dynamic Island + Lock Screen Live Activity); the keyboard *attempts* the
//  same and, if its process can't schedule, returns false so the caller falls back to a
//  local-notification countdown. See the `/timer` plan + INTEGRATIONS.md.
//

import AlarmKit
import Foundation
import SwiftUI

enum AlarmKitTimerService {

    static func authorizationState() -> AlarmManager.AuthorizationState {
        AlarmManager.shared.authorizationState
    }

    /// True when this process can schedule AlarmKit alarms.
    static var isAuthorized: Bool {
        authorizationState() == .authorized
    }

    /// APP ONLY — a keyboard extension cannot present the system permission prompt. Completion on main.
    static func requestAccess(completion: @escaping (Bool) -> Void) {
        Task {
            let granted = (try? await AlarmManager.shared.requestAuthorization()) == .authorized
            await MainActor.run { completion(granted) }
        }
    }

    /// Attempt to schedule a one-shot countdown timer of `duration` seconds. `completion(false)`
    /// ⇒ the caller MUST fall back (not authorized / scheduling failed) so a timer is never lost.
    static func createTimer(duration: TimeInterval, label: String, completion: @escaping (Bool) -> Void) {
        let finish: (Bool) -> Void = { ok in DispatchQueue.main.async { completion(ok) } }
        guard isAuthorized else { finish(false); return }

        Task.detached(priority: .userInitiated) {
            do {
                let title = LocalizedStringResource(stringLiteral: label)
                let presentation = AlarmPresentation(
                    alert: AlarmPresentation.Alert(
                        title: title,
                        stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.circle")),
                    countdown: AlarmPresentation.Countdown(
                        title: title,
                        pauseButton: AlarmButton(text: "Pause", textColor: .white, systemImageName: "pause.circle")),
                    paused: AlarmPresentation.Paused(
                        title: "Paused",
                        resumeButton: AlarmButton(text: "Resume", textColor: .white, systemImageName: "play.circle")))

                let attributes = SnipKeyTimerAttributes(
                    presentation: presentation,
                    metadata: SnipKeyTimerMetadata(),
                    tintColor: Color.red)

                let configuration = AlarmManager.AlarmConfiguration.timer(
                    duration: duration,
                    attributes: attributes)

                _ = try await AlarmManager.shared.schedule(id: UUID(), configuration: configuration)
                finish(true)
            } catch {
                print("[AlarmKit] timer schedule failed: \(error)")
                finish(false)
            }
        }
    }
}
