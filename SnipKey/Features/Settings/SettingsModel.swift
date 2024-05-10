//
//  SettingsModel.swift
//  SnipKey
//
//  Created by Jonathan Taveras Vargas on 4/1/24.
//

import Foundation
import SwiftData

enum KeyboardAfterPasteAction: String, CaseIterable, Identifiable, Codable {
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

}

@Model
final class SettingsModel {
  var settingsId: String = "SnipKey-Settings"

  var testString: String = "Hello there"

  var afterPasteAction: KeyboardAfterPasteAction = KeyboardAfterPasteAction.space

  init(afterPasteAction: KeyboardAfterPasteAction = .space) {
    self.settingsId = "SnipKey-Settings"
    self.afterPasteAction = afterPasteAction
  }
}
