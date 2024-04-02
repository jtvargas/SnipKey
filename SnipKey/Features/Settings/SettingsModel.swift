//
//  SettingsModel.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 4/1/24.
//

import Foundation
import SwiftData

//enum KeyboardAfterPasteAction: Codable {
//    case rtrn
//    case space
//}
enum KeyboardAfterPasteAction: String, CaseIterable, Identifiable, Codable   {
    case rtrn, space, change, changeReturn
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
        }
    }
    
    //    func asciiValue() -> String {
    //          switch self {
    //          case .rtrn:
    //              // Assuming ASCII value for 'Return' is 13 (Carriage Return)
    //              return String(13)
    //          case .changeReturn:
    //              // If you need a combination or a special representation, define it accordingly
    //              return "13+Switch"  // This is just a placeholder, adjust as needed
    //          case .change:
    //              // Assuming a custom ASCII-like value for 'Change'
    //              return String(100)  // Placeholder value
    //          case .space:
    //              // ASCII value for 'Space' is 32
    //              return String(32)
    //          }
    //      }
    
  
}

@Model
final class SettingsModel {
    @Attribute(.unique) var settingsId: String = "SnipKey-Settings"
    
    var testString: String = "Hello there"
    
    var afterPasteAction: KeyboardAfterPasteAction = KeyboardAfterPasteAction.rtrn
    
    init(afterPasteAction: KeyboardAfterPasteAction = .rtrn) {
        self.settingsId = "SnipKey-Settings"
        self.afterPasteAction = afterPasteAction
    }
}
