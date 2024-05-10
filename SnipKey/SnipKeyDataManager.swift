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
}
