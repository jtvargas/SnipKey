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
    @Environment(\.scenePhase) var scenePhase
    @StateObject private var revenueCatManager = RevenueCatManager.shared
       
    @AppStorage("isOnboarding") var isOnboarding: Bool = true
    
    @AppStorage("showTipDev") var showTipDev: Bool = false
    @AppStorage("showAboutApp") var showAboutApp: Bool = false
    @AppStorage("showWelcomeView") var showWelcomeView: Bool = false
    @AppStorage("isWelcomeAlreadyDisplayed") var isWelcomeAlreadyDisplayed: Bool = false
    
    @AppStorage("isKeyboardShortcutEnabled") var isKeyboardShortcutEnabled: Bool = false
    @AppStorage("appAppearance") var appAppearance: String = AppAppearance.system.rawValue
    
    @State private var showSplashScreen = true
    @State private var isInPaymentScreen = false
    
    private let container = SnipKeyDataManager().makeSharedContainer()
//    private let settingsViewModel = SettingsViewModel()
    private let snippetViewModel = SnippetViewModel()
    @State private var settingsViewModel: SettingsViewModel
    
    init() {
        let modelContext = container.mainContext
        try? Tips.configure()

        // Set the UN delegate before launch finishes so foreground banners present.
        NotificationPresenter.shared.bootstrap()

        let settingsViewModel = SettingsViewModel(modelContext: modelContext)
        _settingsViewModel = State(initialValue: settingsViewModel)
    }
    
    func emptyCallback(){
        print("callback")
    }
    
    
    var body: some Scene {
        WindowGroup {
            Group {
                if showSplashScreen {
                    Splashscreen()
                        .onAppear(){
                            showTipDev = false
                            snippetViewModel.modelContext = container.mainContext
                            DispatchQueue.main
                                .asyncAfter(deadline: .now() +  1.2){
                                    showSplashScreen.toggle()
                                }
                        }
                    
                } else {
                    HomeView2()
                    .sheet(isPresented: $showAboutApp){
                        DevAbout()
                    }.sheet(isPresented: $showWelcomeView){
                        OnboardingStepperView()
                    }
                    .sheet(isPresented: $showTipDev){
                        TipDevView()
                    }
                    .onAppear() {

                        settingsViewModel.setupKeyboardSettings()

                        // Request notification permission once. The keyboard schedules reminders
                        // directly (see LocalNotificationScheduler); the app just owns the prompt.
                        LocalNotificationScheduler.requestAuthorizationIfNeeded()

                        if !isWelcomeAlreadyDisplayed {
                            DispatchQueue.main
                                .asyncAfter(deadline: .now() +  1.0){
                                    showWelcomeView = true
                                    isWelcomeAlreadyDisplayed = true
                                }
                        }
                    }
                    .environmentObject(revenueCatManager)
                    .environment(settingsViewModel)
                    .onChange(of: scenePhase) { oldPhase, newPhase in
                        if newPhase == .active {
                            showAboutApp = false
                            isKeyboardShortcutEnabled = isShortcutsKeyboardEnabled()
                        } else if newPhase == .inactive {
                            print("Inactive")
                        } else if newPhase == .background {
                            print("Background")
                        }
                    }
                }
            }
            .preferredColorScheme(selectedAppearance.colorScheme)
        }
        .modelContainer(container)
    }
    
    private var selectedAppearance: AppAppearance {
        AppAppearance(rawValue: appAppearance) ?? .system
    }
}
