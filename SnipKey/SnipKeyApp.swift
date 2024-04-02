//
//  SnipKeyApp.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/25/24.
//

import SwiftUI
import SwiftData


//var sharedModelContainer: ModelContainer = {
//    let schema = Schema([
//        SnippetItem.self,
//    ])
//    let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
//    
//    do {
//        return try ModelContainer(for: schema, configurations: [modelConfiguration])
//    } catch {
//        fatalError("Could not create ModelContainer: \(error)")
//    }
//}()

@main
struct SnipKeyApp: App {
    @AppStorage("isOnboarding") var isOnboarding: Bool = true
    @State private var showSplashScreen = true
    private let container = SnipKeyDataManager().makeSharedContainer()
    let settingsViewModel = SettingsViewModel()
    
    
    func emptyCallback(){
        print("callback")
    }

    
    var body: some Scene {
        WindowGroup {
            if showSplashScreen {
                Splashscreen()
                    .onAppear(){
                        settingsViewModel.modelContext = container.mainContext
                        settingsViewModel.setupKeyboardSettings()
                        DispatchQueue.main
                            .asyncAfter(deadline: .now() + (isOnboarding ? 2.2 : 1.4)){
                                showSplashScreen.toggle()
                            }
                    }
                
            } else if isOnboarding {
                WelcomeView(skipCallback: emptyCallback)
            } else {
                SnippetView()
            }
        }
        .modelContainer(container)
    }
}
