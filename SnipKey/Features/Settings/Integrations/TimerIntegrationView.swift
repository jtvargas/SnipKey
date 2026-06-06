//
//  TimerIntegrationView.swift
//  SnipKey (main app only)
//
//  Configure the Timer integration. Enabling "Timers" turns on the `/timer` command: typing a
//  duration and tapping the pill schedules a SnipKey notification that fires when the countdown
//  ends — you stay in whatever app you're using. See INTEGRATIONS.md.
//

import SwiftData
import SwiftUI

struct TimerIntegrationView: View {
    @Query private var settings: [SettingsModel]

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

            // MARK: Enable
            Section {
                Toggle(isOn: enableBinding(model)) {
                    badge("timer", .indigo, "Enable Timers")
                }
                .tint(.indigo)
            } footer: {
                Text("Turns on the /timer command. SnipKey notifies you when the timer ends — your timers stay on your device and aren’t shared with any other app or service.")
                    .font(.custom("IBMPlexMono-Regular", size: 12))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Timers")
    }

    private func enableBinding(_ model: SettingsModel) -> Binding<Bool> {
        Binding(
            get: { model.timerIntegrationEnabled },
            set: { enabled in
                model.timerIntegrationEnabled = enabled
                AppGroupSettings.setBool(enabled, forKey: AppGroupSettings.Key.timerIntegrationEnabled)
            }
        )
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
