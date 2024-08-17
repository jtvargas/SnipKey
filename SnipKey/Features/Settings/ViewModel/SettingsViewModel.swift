//
//  SettingsViewModel.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 4/1/24.
//

import SwiftData
import SwiftUI

@Observable
class SettingsViewModel {
  var modelContext: ModelContext? = nil
    
    
    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

  func setupKeyboardSettings() {

    let fetchDescriptor = FetchDescriptor<SettingsModel>()

    do {
      let settings = try modelContext?.fetch(fetchDescriptor)

      if settings!.isEmpty {
        print("SETUP NEW KEYBOARD SETTINGS MODEL!")
        self.modelContext?.insert(SettingsModel())
      } else {
        print("KEYBOARD MODEL ALREADY SETUP!")
      }

    } catch {
      print("FAILED TO SETUP KEYBOARD SETTINGS MODEL")
    }

  }

  func changeAfterPasteAction(action: KeyboardAfterPasteAction) {
    let newSettingsModel = SettingsModel(afterPasteAction: action)

    print("NEW ACTION: \(newSettingsModel.afterPasteAction)")
    print("KEYBOARD ID: \(newSettingsModel.settingsId)")

    self.modelContext?.insert(newSettingsModel)
  }
}
