//
//  Keyboard.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 4/24/24.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

func pasteFromClipboard() -> String {
    UIPasteboard.general.string ?? ""
}

func isKeyboardExtensionActive() -> Bool {
    guard let bundleID = Bundle.main.bundleIdentifier else {
        return false
    }
    
    let activeInputModes = UITextInputMode.activeInputModes
    
    return activeInputModes.contains { inputMode in
        inputMode.value(forKey: "identifier") as? String == bundleID + ".SnipKeyboard"
    }
}

func isShortcutsKeyboardEnabled() -> Bool {
    guard let appBundleIdentifier = Bundle.main.bundleIdentifier else {
        fatalError("isKeyboardExtensionEnabled(): Cannot retrieve bundle identifier.")
    }
    
    UserDefaults.standard.dictionaryRepresentation()
    
    guard
        let keyboards = UserDefaults.standard.dictionaryRepresentation()["AppleKeyboards"] as? [String]
    else {
        // There is no key `AppleKeyboards` in NSUserDefaults. That happens sometimes.
        return false
    }
    
    print("KEYBOARDS: \(keyboards)")
    let keyboardExtensionBundleIdentifierPrefix = appBundleIdentifier + ".SnipKeyboard"
    
    for keyboard in keyboards {
        if keyboard.hasPrefix(keyboardExtensionBundleIdentifierPrefix) {
            return true
        }
    }
    
    return false
}
