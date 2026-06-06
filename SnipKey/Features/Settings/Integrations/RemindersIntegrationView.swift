//
//  RemindersIntegrationView.swift
//  SnipKey (main app only)
//
//  Configure the Reminders integration. Flipping the toggle on automatically asks for Reminders
//  permission (this is the only place the system prompt can appear — the keyboard can't prompt);
//  on grant the integration turns on and the destination switches to Apple Reminders. On denial it
//  stays off and explains how to fix it. Every change is mirrored to the App Group so the keyboard
//  reads it at its next launch. See INTEGRATIONS.md.
//

import EventKit
import SwiftData
import SwiftUI
import UIKit

struct RemindersIntegrationView: View {
    @Environment(\.openURL) private var openURL
    @Query private var settings: [SettingsModel]
    @State private var authStatus: EKAuthorizationStatus = EventKitReminderService.authorizationStatus()
    @State private var requesting = false
    @State private var showPermissionNeeded = false

    var body: some View {
        if let model = settings.first {
            content(model)
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private func content(_ model: SettingsModel) -> some View {
        List {
            // MARK: What this does
            Section {
                Text("Create reminders straight from your keyboard. When this is on, typing a command like “/remind tomorrow at 9am call mom” adds it to Apple Reminders instead of keeping it inside SnipKey.")
                    .font(.custom("IBMPlexMono-Regular", size: 13))
                    .foregroundColor(Color.label)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 2)
            }

            // MARK: Enable (auto-requests permission)
            Section {
                Toggle(isOn: enableBinding(model)) {
                    badge("checklist", .red, "Enable Reminders")
                }
                .tint(.red)
                .disabled(requesting)
            } footer: {
                Text("Reminders are created on your device — kept in SnipKey, or sent straight to Apple Reminders when you choose it as the destination. SnipKey doesn’t track or collect your reminders, and never sends them to any third-party or external service.")
                    .font(.custom("IBMPlexMono-Regular", size: 12))
            }

            // MARK: Permission needed (denied / restricted / turned off later)
            if showPermissionNeeded {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reminders access is off")
                            .font(.custom("IBMPlexMono-SemiBold", size: 14))
                            .foregroundColor(Color.label)
                        Text("SnipKey needs your permission to add reminders to Apple Reminders. Turn it on in Settings to use this integration.")
                            .font(.custom("IBMPlexMono-Regular", size: 13))
                            .foregroundColor(Color.secondaryLabel)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Open Settings") { openAppSettings() }
                            .font(.custom("IBMPlexMono-Medium", size: 14))
                            .foregroundColor(.red)
                    }
                    .padding(.vertical, 2)
                }
            }

            // MARK: Destination (only once enabled + allowed)
            if model.remindersIntegrationEnabled, isAuthorized {
                Section {
                    Picker(selection: destinationBinding(model)) {
                        ForEach(ReminderDestination.allCases) { dest in
                            Text(dest.displayName).tag(dest)
                        }
                    } label: {
                        badge("arrow.triangle.branch", .blue, "Create reminders in")
                    }
                } footer: {
                    Text("Choose where “/remind” creates reminders. Only one is ever used — a reminder is never created in two places.")
                        .font(.custom("IBMPlexMono-Regular", size: 12))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Reminders")
        .onAppear {
            authStatus = EventKitReminderService.authorizationStatus()
            // Surface the fix-it message if the integration is on but access was later revoked.
            showPermissionNeeded = model.remindersIntegrationEnabled && !isAuthorized
        }
    }

    // MARK: - Toggle / destination bindings

    /// Intercepts the toggle so enabling runs the permission flow before the model flips on.
    private func enableBinding(_ model: SettingsModel) -> Binding<Bool> {
        Binding(
            get: { model.remindersIntegrationEnabled },
            set: { handleToggle($0, model) }
        )
    }

    private func destinationBinding(_ model: SettingsModel) -> Binding<ReminderDestination> {
        Binding(
            get: { model.reminderDestination },
            set: { setDestination($0, on: model) }
        )
    }

    // MARK: - Permission flow

    private func handleToggle(_ turnOn: Bool, _ model: SettingsModel) {
        guard turnOn else { disable(model); return }
        switch EventKitReminderService.authorizationStatus() {
        case .fullAccess:
            enable(model)                          // already allowed — no prompt needed
        case .notDetermined:
            guard !requesting else { return }
            requesting = true
            EventKitReminderService.requestAccess { granted in
                requesting = false
                authStatus = EventKitReminderService.authorizationStatus()
                if granted {
                    enable(model)
                } else {
                    showPermissionNeeded = true    // declined → stays off
                }
            }
        default:                                   // denied / restricted — can't re-prompt
            authStatus = EventKitReminderService.authorizationStatus()
            showPermissionNeeded = true            // guide the user to Settings; stays off
        }
    }

    private func enable(_ model: SettingsModel) {
        model.remindersIntegrationEnabled = true
        AppGroupSettings.setBool(true, forKey: AppGroupSettings.Key.remindersIntegrationEnabled)
        authStatus = EventKitReminderService.authorizationStatus()
        showPermissionNeeded = false
        // Automatically route reminders to Apple Reminders once it's enabled + allowed.
        setDestination(.remindersApp, on: model)
    }

    private func disable(_ model: SettingsModel) {
        model.remindersIntegrationEnabled = false
        AppGroupSettings.setBool(false, forKey: AppGroupSettings.Key.remindersIntegrationEnabled)
        showPermissionNeeded = false
        setDestination(.snipKey, on: model)
    }

    private func setDestination(_ dest: ReminderDestination, on model: SettingsModel) {
        if model.reminderDestination != dest { model.reminderDestination = dest }
        AppGroupSettings.setString(dest.rawValue, forKey: AppGroupSettings.Key.reminderDestination)
    }

    // MARK: - Helpers

    private var isAuthorized: Bool { authStatus == .fullAccess }

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }

    private func badge(_ icon: String, _ color: Color, _ title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(color)
                .cornerRadius(6)
            Text(title)
                .font(.custom("IBMPlexMono-Medium", size: 15))
        }
    }
}
