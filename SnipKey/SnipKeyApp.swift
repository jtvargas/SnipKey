//
//  SnipKeyApp.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/25/24.
//

import SwiftUI
import SwiftData

@main
struct SnipKeyApp: App {
    @AppStorage("isOnboarding") var isOnboarding: Bool = true
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            SnippetItem.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    func emptyCallback(){
        print("callback")
    }
    
    var body: some Scene {
        WindowGroup {
            if isOnboarding {
                WelcomeView(skipCallback: emptyCallback)
            } else {
                SnippetView()
            }
            
        }
        .modelContainer(sharedModelContainer)
    }
}
