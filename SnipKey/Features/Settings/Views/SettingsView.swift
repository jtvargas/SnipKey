//
//  SettingsView.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 4/1/24.
//

import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) var modelContext
    @Environment(\.openURL) private var openURL
    
    @Query() private var settings: [SettingsModel]
    let settingsViewModel = SettingsViewModel()
    let snippetViewModel = SnippetViewModel()
    
    @Binding var isPresentingSettings: Bool
    
    @State private var showingAlert = false
    @State private var action: KeyboardAfterPasteAction = .rtrn
    @State private var currentSettings: SettingsModel = SettingsModel(afterPasteAction: .rtrn)
    
    @State private var keyboardValueTest: String = ""
    
    var body: some View {
        NavigationStack {
            List {
                Section("Keyboard Settings") {
                    Section(
                        footer:
                            Group{
                                Label {
                                    Text("Customize what happens after pasting a snippet.")
                                        .font(.custom("IBMPlexMono-Medium", size: 14))
                                } icon: {
                                    Image(systemName: "doc.badge.arrow.up.fill")
                                        .font(.system(size: 16, weight: .light, design: .rounded))
                                    
                                }
                            }
                            .font(.custom("IBMPlexMono-Medium", size: 12))
                            .foregroundColor(.label)
                    ) {
                        Picker(
                            selection: $currentSettings.afterPasteAction,
                            label:
                                Text("Paste Action")
                                .font(.custom("IBMPlexMono-Medium", size: 14))
                        ) {
                            ForEach(KeyboardAfterPasteAction.allCases, id: \.id) { keyboardAction in
                                Text("\(keyboardAction.displayText)").tag(keyboardAction)
                            }
                        }
                        
                    }
                }
                
                Section("About") {
                    Button {
                        if let url = URL(string: "https://snipkey.jrtv.online") {
                            openURL(url)
                        }
                    } label: {
                        
                        Label("SnipKey Website", systemImage: "network")
                    }
                    Button {
                        if let url = URL(string: "https://snipkey.jrtv.online/privacy-policy") {
                            openURL(url)
                        }
                    } label: {
                        
                        Label("Privacy Policy", systemImage: "hand.raised.circle.fill")
                    }
                    Button {
                        let urlString = "https://snipkey.jrtv.online/feedback-login?companyID=6611dc80cc35d4304dff22cd&redirect=https%3A%2F%2Fsnipkey.canny.io"
                        print("url: \(urlString)")
                        if let url = URL(string: urlString) {
                            openURL(url)
                        }
                    } label: {
                        Label("Suggest Feature", systemImage: "square.and.pencil.circle.fill")
                    }
                }
                
                Section(footer: Text("Reset to default settings")) {
                    Button {
                        showingAlert.toggle()
                    } label: {
                        
                        Label("Reset Keyboard Settings", systemImage: "xmark.bin.circle.fill")
                            .foregroundColor(.customError)
                    }

                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isPresentingSettings.toggle()
                    } label: {
                        Text("close")
                            .foregroundColor(Color.secondary)
                            .underline()
                            .bold()
                    }
                    
                }
                ToolbarItem(placement: .bottomBar) {
                    Text("SnipKey")
                        .foregroundColor(Color.secondary)
                }
            }
            .navigationTitle("Settings")
            .font(.custom("IBMPlexMono-Bold", size: 16))
            .onAppear {
                settingsViewModel.modelContext = modelContext
                if let myCurrentSettings = settings.first {
                    currentSettings = myCurrentSettings
                    action = myCurrentSettings.afterPasteAction
                }
            }
        }
        .alert("Are you sure you want to reset the keyboard settings?", isPresented: $showingAlert) {
            Button("Reset Settings", role: .destructive) {
                resetKeyboardSettings()
            }
            Button("Cancel", role: .cancel) { }
        }
        
        
    }
    
    func resetKeyboardSettings(){
        currentSettings.afterPasteAction = .space
    }
}

#Preview {
    let settingsViewModel = SettingsViewModel()
    let tempSettingsContainer = SnipKeyDataManager().makeSharedContainer()
    @State var isPresentingSettings: Bool = false
    
    return SettingsView(isPresentingSettings: $isPresentingSettings)
        .onAppear {
            settingsViewModel.modelContext = tempSettingsContainer.mainContext
            settingsViewModel.setupKeyboardSettings()
        }
        .modelContainer(tempSettingsContainer)
}
