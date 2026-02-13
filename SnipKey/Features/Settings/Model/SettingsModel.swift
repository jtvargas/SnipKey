//
//  SettingsModel.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 4/1/24.
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - App Appearance
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Keyboard After Paste Action
enum KeyboardAfterPasteAction: String, CaseIterable, Identifiable, Codable {
    case rtrn, space, change, changeReturn, nothing
    var id: String { return self.rawValue }
    var displayText: String {
        switch self {
        case .rtrn:
            return "Return"
        case .changeReturn:
            return "Return + Switch"
        case .change:
            return "Switch"
        case .space:
            return "Space"
        case .nothing:
            return "Nothing"
        }
    }
    
}

@Model
final class SettingsModel {
    var settingsId: String = "SnipKey-Settings"
    
    var testString: String = "Hello there"
    
    var afterPasteAction: KeyboardAfterPasteAction = KeyboardAfterPasteAction.space
    
    /// When true, the keyboard extension opens to the QWERTY keyboard instead of the snippet list.
    /// This is an experimental feature — disabled by default.
    var isQWERTYKeyboardEnabled: Bool = false
    
    init(afterPasteAction: KeyboardAfterPasteAction = .space, isQWERTYKeyboardEnabled: Bool = false) {
        self.settingsId = "SnipKey-Settings"
        self.afterPasteAction = afterPasteAction
        self.isQWERTYKeyboardEnabled = isQWERTYKeyboardEnabled
    }
}
