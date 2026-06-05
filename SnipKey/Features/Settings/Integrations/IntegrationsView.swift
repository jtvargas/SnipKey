//
//  IntegrationsView.swift
//  SnipKey (main app only)
//
//  Lists the available integrations (Settings → Integrations). Driven entirely by
//  `IntegrationRegistry`, so new integrations appear here without touching this file.
//  See INTEGRATIONS.md.
//

import SwiftData
import SwiftUI

struct IntegrationsView: View {
    @Query private var settings: [SettingsModel]

    private var remindersEnabled: Bool { settings.first?.remindersIntegrationEnabled ?? false }

    var body: some View {
        List {
            Section {
                ForEach(IntegrationRegistry.all) { integration in
                    NavigationLink {
                        integration.makeDetail()
                    } label: {
                        SettingsRow(
                            icon: integration.iconName,
                            iconColor: integration.iconColor,
                            title: integration.title,
                            subtitle: statusText(for: integration.id),
                            showChevron: false
                        )
                    }
                }
            } header: {
                Text("Available")
            } footer: {
                Text("Connect SnipKey to other apps. More integrations coming soon.")
                    .font(.custom("IBMPlexMono-Regular", size: 12))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Integrations")
    }

    private func statusText(for id: IntegrationID) -> String {
        switch id {
        case .reminders: return remindersEnabled ? "On" : "Off"
        }
    }
}
