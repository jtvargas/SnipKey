//
//  TimerIntegrationView.swift
//  SnipKey (main app only)
//
//  Configure the Timer integration. Enabling "Timers" turns on the `/timer` command (which, by
//  default, fires a local notification when the timer ends — you stay in your current app).
//  Turning on "Live countdown" auto-requests AlarmKit permission (only here can the system prompt
//  appear) and switches `/timer` to open SnipKey and start a real AlarmKit timer with a live
//  Lock Screen / Dynamic Island countdown. See INTEGRATIONS.md / the `/timer` plan.
//

import AlarmKit
import SwiftData
import SwiftUI
import UIKit

struct TimerIntegrationView: View {
    @Environment(\.openURL) private var openURL
    @Query private var settings: [SettingsModel]
    @State private var authState: AlarmManager.AuthorizationState = AlarmKitTimerService.authorizationState()
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
                Text("Start a countdown right from your keyboard. Type a command like “/timer 1h 30m” (or “/timer 90” for 90 seconds) and tap Create timer.")
                    .font(.custom("IBMPlexMono-Regular", size: 13))
                    .foregroundColor(Color.label)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 2)
            }

            // MARK: Enable (no permission needed — local-notification mode by default)
            Section {
                Toggle(isOn: enableBinding(model)) {
                    badge("timer", .indigo, "Enable Timers")
                }
                .tint(.indigo)
            } footer: {
                Text("Turns on the /timer command. By default, SnipKey notifies you when the timer ends and you stay in whatever app you’re using.")
                    .font(.custom("IBMPlexMono-Regular", size: 12))
            }

            if model.timerIntegrationEnabled {
                // MARK: Live countdown (opt-in; needs AlarmKit permission)
                Section {
                    Toggle(isOn: liveBinding(model)) {
                        badge("bolt.badge.clock", .orange, "Live countdown")
                    }
                    .tint(.orange)
                    .disabled(requesting)
                } footer: {
                    Text("On: tapping Create timer opens SnipKey for a moment to start a live countdown on your Lock Screen and in the Dynamic Island — it keeps running while you use other apps.\n\nOff (default): SnipKey simply sends a notification when the timer ends, and you stay in your current app.\n\nEither way, everything stays on your device.")
                        .font(.custom("IBMPlexMono-Regular", size: 12))
                }

                // MARK: Permission needed (live countdown wanted but AlarmKit denied)
                if showPermissionNeeded {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Timer access is off")
                                .font(.custom("IBMPlexMono-SemiBold", size: 14))
                                .foregroundColor(Color.label)
                            Text("Live countdowns need your permission to start timers. Turn it on in Settings, then switch Live countdown back on here.")
                                .font(.custom("IBMPlexMono-Regular", size: 13))
                                .foregroundColor(Color.secondaryLabel)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Open Settings") { openAppSettings() }
                                .font(.custom("IBMPlexMono-Medium", size: 14))
                                .foregroundColor(.orange)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Timers")
        .onAppear {
            authState = AlarmKitTimerService.authorizationState()
            showPermissionNeeded = model.timerLiveCountdownEnabled && !isAuthorized
        }
    }

    // MARK: - Bindings

    private func enableBinding(_ model: SettingsModel) -> Binding<Bool> {
        Binding(
            get: { model.timerIntegrationEnabled },
            set: { enabled in
                model.timerIntegrationEnabled = enabled
                AppGroupSettings.setBool(enabled, forKey: AppGroupSettings.Key.timerIntegrationEnabled)
                if !enabled { setLive(false, on: model) }   // disabling Timers clears live mode
            }
        )
    }

    private func liveBinding(_ model: SettingsModel) -> Binding<Bool> {
        Binding(
            get: { model.timerLiveCountdownEnabled },
            set: { handleLiveToggle($0, model) }
        )
    }

    // MARK: - Live-countdown permission flow

    private func handleLiveToggle(_ turnOn: Bool, _ model: SettingsModel) {
        guard turnOn else { setLive(false, on: model); return }
        switch AlarmKitTimerService.authorizationState() {
        case .authorized:
            setLive(true, on: model)
        case .notDetermined:
            guard !requesting else { return }
            requesting = true
            AlarmKitTimerService.requestAccess { granted in
                requesting = false
                authState = AlarmKitTimerService.authorizationState()
                if granted { setLive(true, on: model) } else { showPermissionNeeded = true }
            }
        default:                                   // denied / restricted — can't re-prompt
            authState = AlarmKitTimerService.authorizationState()
            showPermissionNeeded = true            // stays off; guide to Settings
        }
    }

    private func setLive(_ on: Bool, on model: SettingsModel) {
        if model.timerLiveCountdownEnabled != on { model.timerLiveCountdownEnabled = on }
        AppGroupSettings.setBool(on, forKey: AppGroupSettings.Key.timerLiveCountdownEnabled)
        if on { showPermissionNeeded = false }
    }

    // MARK: - Helpers

    private var isAuthorized: Bool { authState == .authorized }

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
