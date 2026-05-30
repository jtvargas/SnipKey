//
//  SnipKeyDataManager.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/31/24.
//

import Foundation
import SwiftData

class SnipKeyDataManager {
    var sharedContainer: ModelContainer? = nil

    func makeSharedContainer() -> ModelContainer {
        let sharedModelContainer: ModelContainer = {
            let schema = Schema([
                SnippetItem.self,
                SettingsModel.self,
            ])
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, groupContainer: .identifier("group.snipkey"), cloudKitDatabase: .automatic)

            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }()

        self.sharedContainer = sharedModelContainer

        return sharedModelContainer
    }

    /// Build the shared `ModelContainer` off the main thread.
    /// Opening the SQLite store + CloudKit registration is 50–200ms of synchronous work;
    /// performing it here lets `viewDidLoad` complete and the keyboard frame appear before
    /// SwiftData is ready. Callers await this once, then inject the container into SwiftUI.
    static func makeSharedContainerAsync() async throws -> ModelContainer {
        try await Task.detached(priority: .userInitiated) {
            let schema = Schema([
                SnippetItem.self,
                SettingsModel.self,
            ])
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                groupContainer: .identifier("group.snipkey"),
                cloudKitDatabase: .automatic
            )
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        }.value
    }
}
