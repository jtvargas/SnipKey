//
//  IntegrationsView.swift
//  SnipKey (main app only)
//
//  Lists the available integrations (Settings → Integrations) with a friendly intro and the
//  commands they unlock. Driven entirely by `IntegrationRegistry`, so new integrations appear
//  here without touching this file. See INTEGRATIONS.md.
//

import SwiftData
import SwiftUI
import UIKit

struct IntegrationsView: View {
    @Environment(\.openURL) private var openURL
    @Query private var settings: [SettingsModel]

    var body: some View {
        List {
            // MARK: Full Access notice (required for any keyboard integration)
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.orange)
                        Text("Turn on Full Access")
                            .font(.custom("IBMPlexMono-SemiBold", size: 14))
                            .foregroundColor(Color.label)
                    }
                    Text("For integrations to work, turn on “Allow Full Access” for the SnipKey keyboard in Settings → General → Keyboard → Keyboards → SnipKey. This only lets the keyboard work with the app and apps like Apple Reminders — no data is ever sent off your device.")
                        .font(.custom("IBMPlexMono-Regular", size: 12))
                        .foregroundColor(Color.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Settings") { openAppSettings() }
                        .font(.custom("IBMPlexMono-Medium", size: 13))
                        .foregroundColor(.orange)
                }
                .padding(.vertical, 2)
            }

            // MARK: What integrations are
            Section {
                Text("Integrations let SnipKey commands work with other apps on your device. For example, “/remind” can create reminders in Apple Reminders instead of keeping them inside SnipKey.")
                    .font(.custom("IBMPlexMono-Regular", size: 13))
                    .foregroundColor(Color.label)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 2)
            }

            // MARK: Available integrations
            Section {
                ForEach(IntegrationRegistry.all) { integration in
                    NavigationLink {
                        integration.makeDetail()
                    } label: {
                        SettingsRow(
                            icon: integration.iconName,
                            iconColor: integration.iconColor,
                            title: integration.title,
                            subtitle: statusText(for: integration),
                            showChevron: false
                        )
                    }
                }
            } header: {
                Text("Available")
            } footer: {
                Text("More integrations coming soon.")
                    .font(.custom("IBMPlexMono-Regular", size: 12))
            }

            // MARK: Supported commands
            Section {
                commandRow("/remind", "Create reminders using natural language, like “/remind tomorrow at 9am call mom”.")
            } header: {
                Text("Commands")
            } footer: {
                Text("Your reminder data stays on your device. SnipKey doesn’t send it to any other app or service.")
                    .font(.custom("IBMPlexMono-Regular", size: 12))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Integrations")
    }

    private func statusText(for integration: IntegrationDescriptor) -> String {
        guard let model = settings.first else { return "Off" }
        return integration.isEnabled(model) ? "On" : "Off"
    }

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }

    private func commandRow(_ command: String, _ description: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(command)
                .font(.custom("IBMPlexMono-Medium", size: 14))
                .foregroundColor(Color.label)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.secondarySystemBackground)
                )
            Text(description)
                .font(.custom("IBMPlexMono-Regular", size: 12))
                .foregroundColor(Color.secondaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}
