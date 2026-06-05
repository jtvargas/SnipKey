//
//  RemindersIntegrationView.swift
//  SnipKey (main app only)
//
//  Configure the Reminders integration: enable it, grant EventKit permission (this is the ONLY
//  place the system prompt is presented — the keyboard can't prompt), and choose where reminders
//  are created. "Reminders App" is selectable only once permission is granted. Every change is
//  mirrored to the App Group so the keyboard reads it at its next launch. See INTEGRATIONS.md.
//

import EventKit
import SwiftData
import SwiftUI

struct RemindersIntegrationView: View {
    @Query private var settings: [SettingsModel]
    @State private var authStatus: EKAuthorizationStatus = EventKitReminderService.authorizationStatus()
    @State private var requesting = false

    var body: some View {
        if let model = settings.first {
            content(model)
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private func content(_ model: SettingsModel) -> some View {
        @Bindable var model = model
        List {
            // MARK: Enable
            Section {
                Toggle(isOn: $model.remindersIntegrationEnabled) {
                    badge("checklist", .red, "Enable Reminders")
                }
                .tint(.red)
                .onChange(of: model.remindersIntegrationEnabled) { _, enabled in
                    AppGroupSettings.setBool(enabled, forKey: AppGroupSettings.Key.remindersIntegrationEnabled)
                    // Turning the integration off snaps the destination back to SnipKey.
                    if !enabled { setDestination(.snipKey, on: model) }
                }
            } footer: {
                Text("Let SnipKey create reminders in Apple Reminders. Off by default — your existing reminders keep working exactly as before.")
                    .font(.custom("IBMPlexMono-Regular", size: 12))
            }

            if model.remindersIntegrationEnabled {
                // MARK: Permission
                Section {
                    HStack(spacing: 12) {
                        badge("lock.shield", .orange, permissionTitle)
                        Spacer()
                        if isAuthorized {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Button(requesting ? "…" : "Grant") { requestAccess(model) }
                                .font(.custom("IBMPlexMono-Medium", size: 14))
                                .disabled(requesting || authStatus == .denied || authStatus == .restricted)
                        }
                    }
                } footer: {
                    if authStatus == .denied || authStatus == .restricted {
                        Text("Reminders access is off. Enable it in Settings → SnipKey → Reminders, then return here.")
                            .font(.custom("IBMPlexMono-Regular", size: 12))
                    }
                }

                // MARK: Destination
                Section {
                    Picker(selection: $model.reminderDestination) {
                        ForEach(ReminderDestination.allCases) { dest in
                            Text(dest.displayName)
                                .tag(dest)
                                .disabled(dest == .remindersApp && !isAuthorized)
                        }
                    } label: {
                        badge("arrow.triangle.branch", .blue, "Create reminders in")
                    }
                    .onChange(of: model.reminderDestination) { _, dest in
                        // Never persist .remindersApp without permission.
                        let safe: ReminderDestination = (dest == .remindersApp && !isAuthorized) ? .snipKey : dest
                        setDestination(safe, on: model)
                    }
                } footer: {
                    Text("Only one destination is active at a time — a reminder is never created in both. \"Reminders App\" needs the permission above.")
                        .font(.custom("IBMPlexMono-Regular", size: 12))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Reminders")
        .onAppear { authStatus = EventKitReminderService.authorizationStatus() }
    }

    // MARK: - Helpers

    private var isAuthorized: Bool { authStatus == .fullAccess }

    private var permissionTitle: String {
        isAuthorized ? "Reminders access granted" : "Allow Reminders access"
    }

    /// Persist a destination to SwiftData + mirror to the App Group in one place (guards the
    /// `.onChange` re-entrancy when we correct an illegal selection).
    private func setDestination(_ dest: ReminderDestination, on model: SettingsModel) {
        if model.reminderDestination != dest { model.reminderDestination = dest }
        AppGroupSettings.setString(dest.rawValue, forKey: AppGroupSettings.Key.reminderDestination)
    }

    private func requestAccess(_ model: SettingsModel) {
        requesting = true
        EventKitReminderService.requestAccess { _ in
            authStatus = EventKitReminderService.authorizationStatus()
            requesting = false
            // If still not granted, make sure we didn't leave .remindersApp selected.
            if !isAuthorized, model.reminderDestination == .remindersApp {
                setDestination(.snipKey, on: model)
            }
        }
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
