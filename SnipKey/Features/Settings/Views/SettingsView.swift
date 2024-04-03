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
    @Query() private var settings: [SettingsModel]
    let settingsViewModel = SettingsViewModel()
    
    @Binding  var isPresentingSettings: Bool
    
    @State private var action: KeyboardAfterPasteAction = .rtrn
    @State private var currentSettings: SettingsModel = SettingsModel(afterPasteAction: .rtrn)
    
    func changeKeyboardAfterAction(newAction: KeyboardAfterPasteAction ){
        settingsViewModel.changeAfterPasteAction(action: newAction)
    }
    
    var body: some View {
        NavigationStack{
            List {
                Section("Keyboard Settings") {
                    Section(
                        footer:
                        Label {
                            Text("Keyboard action after a snippet is been pasted in your field.")
                                .font(.custom("IBMPlexMono-Medium", size: 14))
                        } icon: {
                            Image(systemName: "doc.badge.arrow.up.fill")
                                .font(.system(size: 16, weight: .light, design: .rounded))
                            
                        }
                            .font(.custom("IBMPlexMono-Medium", size: 12))
                        .foregroundColor(.label)
                    ) {
                        Picker(
                            selection: $currentSettings.afterPasteAction,
                            label:
                                Text("After Paste Action")
                                    .font(.custom("IBMPlexMono-Medium", size: 14))
                        ) {
                            ForEach(KeyboardAfterPasteAction.allCases, id: \.id) { keyboardAction in
                                Text("\(keyboardAction.displayText)").tag(keyboardAction)
                            }
                        }.onChange(of: action) { _, newAction in
                            changeKeyboardAfterAction(newAction: newAction)
                        }
                        
                    }
                }
                
                Section("More") {
                    Button {
                        print("Policy")
                    } label: {
                        Label("Privacy Policy", systemImage: "hand.raised.circle.fill")
                    }
                    Button {
                        print("Feedback")
                    } label: {
                        Label("Give Feedback", systemImage: "square.and.pencil.circle.fill")
                    }
                    
                    
                    Button {
                        print("Reset")
                    } label: {
                        
                        Label("Reset Keyboard Settings", systemImage: "xmark.bin.circle.fill")
                            .foregroundColor(.customError)
                    }

                }
            }
            .toolbar{
                ToolbarItem(placement: .topBarLeading){
                    Button {
                        isPresentingSettings.toggle()
                    } label: {
                        Text("close")
                            .foregroundColor(Color.secondary)
                            .underline()
                            .bold()
                    }
                   
                }
                ToolbarItem(placement: .bottomBar){
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
        
    }
}

#Preview {
    let settingsViewModel = SettingsViewModel()
    let tempSettingsContainer = SnipKeyDataManager().makeSharedContainer()
    @State  var isPresentingSettings: Bool = false
    
    return SettingsView( isPresentingSettings: $isPresentingSettings)
        .onAppear {
            settingsViewModel.modelContext = tempSettingsContainer.mainContext
            settingsViewModel.setupKeyboardSettings()
        }
        .modelContainer(tempSettingsContainer)
}
