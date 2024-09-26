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

func copyImageToClipboard(snippet: SnippetItem) -> Bool? {
    guard
        let newImage = UIImage(data: (snippet.file?.fileData)!)
    else { return nil }
    
    var imageData: Data?
    
    if snippet.file?.fileFormatType == "image/png"{
        imageData = newImage.pngData()
    }
    
    if snippet.file?.fileFormatType == "image/jpeg"{
        imageData = newImage.jpegData(compressionQuality: 0.5)
    }
    
    
    let clipboard = UIPasteboard.general
    clipboard.setValue(imageData!, forPasteboardType: UTType.png.identifier)
    
    return true
}


func isKeyboardExtensionFullAccessGranted() -> Bool {
    let tempKey = "KeyboardExtensionFullAccessCheck"
    let tempValue = "TemporaryValue"
    
    // Store the original value if it exists
    let originalValue = UIPasteboard.general.string
    
    // Try to set a value in the pasteboard
    UIPasteboard.general.setValue(tempValue, forPasteboardType: tempKey)
    
    // Try to retrieve the value
    let retrievedValue = UIPasteboard.general.value(forPasteboardType: tempKey) as? String
    
    // Clean up by restoring the original value or removing our temp value
    if let original = originalValue {
        UIPasteboard.general.string = original
    } else {
        UIPasteboard.general.items = UIPasteboard.general.items.filter { item in
            !item.keys.contains(where: { $0 == tempKey })
        }
    }
    
    // If we could set and retrieve the value, full access is granted
    return retrievedValue == tempValue
}


func checkFullAccess() -> Bool
{
    var hasFullAccess = false
    if #available(iOSApplicationExtension 10.0, *) {
        let pasty = UIPasteboard.general
        if pasty.hasURLs || pasty.hasColors || pasty.hasStrings || pasty.hasImages || pasty.value(forPasteboardType: UTType.pdf.identifier) != nil {
            hasFullAccess = true
        }
    } else {
        // Fallback on earlier versions
        var clippy : UIPasteboard?
        clippy = UIPasteboard.general
        if clippy != nil {
            hasFullAccess = true
        }
    }
    return hasFullAccess
    
//   return isKeyboardExtensionFullAccessGranted()
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
