//
//  SnipKeyApp.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 3/25/24.
//

import SwiftUI
import SwiftData
import TipKit

@main
struct SnipKeyApp: App {
    @AppStorage("isOnboarding") var isOnboarding: Bool = true
    @State private var showSplashScreen = true
    private let container = SnipKeyDataManager().makeSharedContainer()
//    private let settingsViewModel = SettingsViewModel()
    private let snippetViewModel = SnippetViewModel()
    @State private var settingsViewModel: SettingsViewModel
    
    init() {
        let modelContext = container.mainContext
        try? Tips.configure()
        
        let settingsViewModel = SettingsViewModel(modelContext: modelContext)
        _settingsViewModel = State(initialValue: settingsViewModel)
    }
    
    func emptyCallback(){
        print("callback")
    }
    
    
    var body: some Scene {
        WindowGroup {
            if showSplashScreen {
                Splashscreen()
                    .onAppear(){
                        snippetViewModel.modelContext = container.mainContext
                        DispatchQueue.main
                            .asyncAfter(deadline: .now() + (isOnboarding ? 2.2 : 1.4)){
                                showSplashScreen.toggle()
                            }
                    }
                
            } else if isOnboarding {
                WelcomeView(skipCallback: emptyCallback)
            } else {
                SnippetHomeView()
                    .onAppear() {
                        settingsViewModel.setupKeyboardSettings()
                    }
                    .environment(settingsViewModel)
                
            }
        }
        .modelContainer(container)
    }
}
