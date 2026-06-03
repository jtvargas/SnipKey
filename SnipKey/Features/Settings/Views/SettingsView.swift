//
//  SettingsView.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 4/1/24.
//

import SwiftData
import SwiftUI

// MARK: - Settings Row Component
struct SettingsRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    var subtitle: String? = nil
    var showChevron: Bool = true
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(iconColor)
                .cornerRadius(6)
            
            Text(title)
                .font(.custom("IBMPlexMono-Medium", size: 15))
                .foregroundColor(.label)
            
            Spacer()
            
            if let subtitle {
                Text(subtitle)
                    .foregroundColor(.secondary)
                    .font(.custom("IBMPlexMono-Regular", size: 14))
            }
            
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.tertiaryLabel)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @AppStorage("showWelcomeView") var showWelcomeView: Bool = false
    @AppStorage("showAboutApp") var showAboutApp: Bool = false
    @AppStorage("showTipDev") var showTipDev: Bool = false
    @AppStorage("appAppearance") var appAppearance: String = AppAppearance.system.rawValue
    
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.modelContext) var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(SettingsViewModel.self) private var settingsViewModel
    
    @Query() private var settings: [SettingsModel]
    @Query() private var tags: [SnipTag]
    
    let snippetViewModel = SnippetViewModel()
    
    @Binding var isPresentingSettings: Bool
    
    @State private var showingAlert = false
    @State private var currentSettings: SettingsModel = SettingsModel(afterPasteAction: .rtrn)
    @State private var isPresentedGuide: Bool = false
    
    private var selectedAppearance: AppAppearance {
        AppAppearance(rawValue: appAppearance) ?? .system
    }
    
    var body: some View {
        NavigationStack {
            List {
                // MARK: - General Section
                Section {
                    Picker(selection: $appAppearance) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.displayName).tag(appearance.rawValue)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "circle.lefthalf.filled")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.purple)
                                .cornerRadius(6)
                            
                            Text("Appearance")
                                .font(.custom("IBMPlexMono-Medium", size: 15))
                        }
                    }
                } header: {
                    Text("General")
                }
                
                // MARK: - Snippets Section
                Section {
                    NavigationLink {
                        TagsView()
                    } label: {
                        SettingsRow(
                            icon: "tag.fill",
                            iconColor: .blue,
                            title: "Tags",
                            subtitle: "\(tags.count)",
                            showChevron: false
                        )
                    }
                } header: {
                    Text("Snippets")
                }
                
                // MARK: - Keyboard Section
                Section {
                    Picker(selection: $currentSettings.afterPasteAction) {
                        ForEach(KeyboardAfterPasteAction.allCases, id: \.id) { action in
                            Text(action.displayText).tag(action)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "keyboard.fill")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.gray)
                                .cornerRadius(6)
                            
                            Text("Paste Action")
                                .font(.custom("IBMPlexMono-Medium", size: 15))
                        }
                    }
                } header: {
                    Text("Keyboard")
                } footer: {
                    Text("Customize what happens after pasting a snippet from the keyboard extension.")
                        .font(.custom("IBMPlexMono-Regular", size: 12))
                }
                
                // MARK: - Experimental Section
                Section {
                    Toggle(isOn: $currentSettings.isQWERTYKeyboardEnabled) {
                        HStack(spacing: 12) {
                            Image(systemName: "keyboard.fill")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.orange)
                                .cornerRadius(6)

                            Text("QWERTY Keyboard")
                                .font(.custom("IBMPlexMono-Medium", size: 15))
                        }
                    }
                    .tint(.orange)

                    Toggle(isOn: $currentSettings.useNativeKeyboardV2) {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.indigo)
                                .cornerRadius(6)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Native Keyboard V2 (Beta)")
                                    .font(.custom("IBMPlexMono-Medium", size: 15))
                                Text("KeyboardKit-style with finger-slide & accents")
                                    .font(.custom("IBMPlexMono-Regular", size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .tint(.indigo)
                    .onChange(of: currentSettings.useNativeKeyboardV2) { _, newValue in
                        AppGroupSettings.setBool(newValue, forKey: AppGroupSettings.Key.useNativeKeyboardV2)
                    }

                    Toggle(isOn: $currentSettings.probabilisticTouchEnabled) {
                        HStack(spacing: 12) {
                            Image(systemName: "target")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.teal)
                                .cornerRadius(6)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Smart Touch Targeting")
                                    .font(.custom("IBMPlexMono-Medium", size: 15))
                                Text("Improves accuracy when typing fast")
                                    .font(.custom("IBMPlexMono-Regular", size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .tint(.teal)
                    .onChange(of: currentSettings.probabilisticTouchEnabled) { _, newValue in
                        AppGroupSettings.setBool(newValue, forKey: AppGroupSettings.Key.probabilisticTouchEnabled)
                    }

                    Toggle(isOn: $currentSettings.autoCapitalizationEnabled) {
                        HStack(spacing: 12) {
                            Image(systemName: "textformat")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.green)
                                .cornerRadius(6)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Auto-Capitalization")
                                    .font(.custom("IBMPlexMono-Medium", size: 15))
                                Text("Capitalize sentence starts and lone \"i\"")
                                    .font(.custom("IBMPlexMono-Regular", size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .tint(.green)
                    .onChange(of: currentSettings.autoCapitalizationEnabled) { _, newValue in
                        AppGroupSettings.setBool(newValue, forKey: AppGroupSettings.Key.autoCapitalizationEnabled)
                    }

                    Toggle(isOn: $currentSettings.debugHitOverlayEnabled) {
                        HStack(spacing: 12) {
                            Image(systemName: "square.grid.3x3")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.red)
                                .cornerRadius(6)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Show Hit-Test Overlay")
                                    .font(.custom("IBMPlexMono-Medium", size: 15))
                                Text("Debug: outline each key's touch cell (reopen keyboard to apply)")
                                    .font(.custom("IBMPlexMono-Regular", size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .tint(.red)
                    .onChange(of: currentSettings.debugHitOverlayEnabled) { _, newValue in
                        AppGroupSettings.setBool(newValue, forKey: AppGroupSettings.Key.debugHitOverlayEnabled)
                    }
                } header: {
                    Text("Experimental")
                } footer: {
                    Text("Experimental features may contain bugs and are not fully stable. Enable at your own discretion and consider sharing feedback.")
                        .font(.custom("IBMPlexMono-Regular", size: 12))
                }
                
                // MARK: - Help & Support Section
                Section {
                    Button {
                        isPresentedGuide.toggle()
                    } label: {
                        SettingsRow(
                            icon: "gear",
                            iconColor: .gray,
                            title: "Set Up Keyboard"
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        isPresentingSettings = false
                        showWelcomeView.toggle()
                    } label: {
                        SettingsRow(
                            icon: "hand.wave.fill",
                            iconColor: .orange,
                            title: "Show Welcome Message"
                        )
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Help & Support")
                }
                
                // MARK: - About Section
                Section {
                    Button {
                        isPresentingSettings = false
                        showTipDev.toggle()
                    } label: {
                        SettingsRow(
                            icon: "heart.fill",
                            iconColor: .pink,
                            title: "Support Development"
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        isPresentingSettings = false
                        showAboutApp.toggle()
                    } label: {
                        SettingsRow(
                            icon: "info.circle.fill",
                            iconColor: .blue,
                            title: "About the App"
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        if let url = URL(string: "https://snipkey.jrtv.online") {
                            openURL(url)
                        }
                    } label: {
                        SettingsRow(
                            icon: "globe",
                            iconColor: .teal,
                            title: "SnipKey Website"
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        if let url = URL(string: "https://github.com/jtvargas/SnipKey") {
                            openURL(url)
                        }
                    } label: {
                        SettingsRow(
                            icon: "chevron.left.forwardslash.chevron.right",
                            iconColor: .purple,
                            title: "Source Code (GitHub)"
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        if let url = URL(string: "https://snipkey.jrtv.online/privacy-policy") {
                            openURL(url)
                        }
                    } label: {
                        SettingsRow(
                            icon: "hand.raised.fill",
                            iconColor: .green,
                            title: "Privacy Policy"
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        let urlString = "https://snipkey.jrtv.online/feedback-login?companyID=6611dc80cc35d4304dff22cd&redirect=https%3A%2F%2Fsnipkey.canny.io"
                        if let url = URL(string: urlString) {
                            openURL(url)
                        }
                    } label: {
                        SettingsRow(
                            icon: "lightbulb.fill",
                            iconColor: .yellow,
                            title: "Suggest Feature"
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        if let url = URL(string: "https://snipkey.jrtv.online/contact-us") {
                            openURL(url)
                        }
                    } label: {
                        SettingsRow(
                            icon: "envelope.fill",
                            iconColor: .blue,
                            title: "Contact Us"
                        )
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("About")
                }
                
                // MARK: - Reset Section
                Section {
                    Button {
                        showingAlert.toggle()
                    } label: {
                        SettingsRow(
                            icon: "arrow.counterclockwise",
                            iconColor: .red,
                            title: "Reset Keyboard Settings",
                            showChevron: false
                        )
                    }
                    .buttonStyle(.plain)
                } footer: {
                    Text("Reset keyboard settings to their default values.")
                        .font(.custom("IBMPlexMono-Regular", size: 12))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .onAppear {
                settingsViewModel.modelContext = modelContext
                if let myCurrentSettings = settings.first {
                    currentSettings = myCurrentSettings
                    // Mirror SwiftData settings to the App Group so the keyboard extension
                    // can read them synchronously at launch.
                    AppGroupSettings.setBool(
                        myCurrentSettings.useNativeKeyboardV2,
                        forKey: AppGroupSettings.Key.useNativeKeyboardV2
                    )
                    AppGroupSettings.setBool(
                        myCurrentSettings.probabilisticTouchEnabled,
                        forKey: AppGroupSettings.Key.probabilisticTouchEnabled
                    )
                    AppGroupSettings.setBool(
                        myCurrentSettings.autoCapitalizationEnabled,
                        forKey: AppGroupSettings.Key.autoCapitalizationEnabled
                    )
                    AppGroupSettings.setBool(
                        myCurrentSettings.debugHitOverlayEnabled,
                        forKey: AppGroupSettings.Key.debugHitOverlayEnabled
                    )
                }
            }
        }
        .sheet(isPresented: $isPresentedGuide) {
            KeyboardHelpGuideView(isPresented: $isPresentedGuide)
        }
        .alert("Reset Keyboard Settings?", isPresented: $showingAlert) {
            Button("Reset", role: .destructive) {
                resetKeyboardSettings()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will reset the paste action to its default value.")
        }
    }
    
    private func resetKeyboardSettings() {
        currentSettings.afterPasteAction = .space
        currentSettings.isQWERTYKeyboardEnabled = false
        currentSettings.useNativeKeyboardV2 = true
        currentSettings.probabilisticTouchEnabled = true
        currentSettings.autoCapitalizationEnabled = true
        currentSettings.debugHitOverlayEnabled = false
        AppGroupSettings.setBool(true, forKey: AppGroupSettings.Key.useNativeKeyboardV2)
        AppGroupSettings.setBool(true, forKey: AppGroupSettings.Key.probabilisticTouchEnabled)
        AppGroupSettings.setBool(true, forKey: AppGroupSettings.Key.autoCapitalizationEnabled)
        AppGroupSettings.setBool(false, forKey: AppGroupSettings.Key.debugHitOverlayEnabled)
    }
}

#Preview {
    @Previewable @State var isPresentingSettings: Bool = false
    let tempSettingsContainer = SnipKeyDataManager().makeSharedContainer()
    let settingsViewModel = SettingsViewModel(modelContext: tempSettingsContainer.mainContext)
   
    
    SettingsView(isPresentingSettings: $isPresentingSettings)
        .onAppear {
            settingsViewModel.modelContext = tempSettingsContainer.mainContext
            settingsViewModel.setupKeyboardSettings()
        }
        .modelContainer(tempSettingsContainer)
        .environment(settingsViewModel)
}
