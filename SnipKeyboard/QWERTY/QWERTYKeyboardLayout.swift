//
//  QWERTYKeyboardLayout.swift
//  SnipKeyboard
//
//  Created by Jonathan Taveras Vargas on 2/10/26.
//

import Foundation

// MARK: - Key Action

enum KeyAction: Hashable {
    case character(String)          // A letter, digit, or symbol
    case shift                      // Shift / caps lock
    case backspace                  // Delete backward
    case space                      // Space bar
    case returnKey                  // Return / enter
    case modeChange(KeyboardPage)   // Switch to letters, numbers, or symbols page
    case snippetToggle              // Toggle to snippets list (long-press = switch keyboard)
}

// MARK: - Layout Definitions

struct QWERTYKeyboardLayout {

    // MARK: Letters Page (QWERTY)

    static let lettersRows: [[KeyAction]] = [
        // Row 0: Q W E R T Y U I O P
        "QWERTYUIOP".map { .character(String($0)) },
        // Row 1: A S D F G H J K L
        "ASDFGHJKL".map { .character(String($0)) },
        // Row 2: [Shift] Z X C V B N M [Backspace]
        [.shift] + "ZXCVBNM".map { .character(String($0)) } + [.backspace],
        // Row 3: [123] [Snippets] [Space] [Return]
        [.modeChange(.numbers), .snippetToggle, .space, .returnKey]
    ]

    // MARK: Numbers Page (123)

    static let numbersRows: [[KeyAction]] = [
        // Row 0: 1 2 3 4 5 6 7 8 9 0
        "1234567890".map { .character(String($0)) },
        // Row 1: - / : ; ( ) $ & @ "
        "-/:;()$&@\"".map { .character(String($0)) },
        // Row 2: [#+=] . , ? ! '  [Backspace]
        [.modeChange(.symbols)] + ".,?!'".map { .character(String($0)) } + [.backspace],
        // Row 3: [ABC] [Snippets] [Space] [Return]
        [.modeChange(.letters), .snippetToggle, .space, .returnKey]
    ]

    // MARK: Symbols Page (#+=)

    static let symbolsRows: [[KeyAction]] = [
        // Row 0: [ ] { } # % ^ * + =
        "[]{}#%^*+=".map { .character(String($0)) },
        // Row 1: _ \ | ~ < > € £ ¥ •
        ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"].map { .character($0) },
        // Row 2: [123] . , ? ! ' [Backspace]
        [.modeChange(.numbers)] + ".,?!'".map { .character(String($0)) } + [.backspace],
        // Row 3: [ABC] [Snippets] [Space] [Return]
        [.modeChange(.letters), .snippetToggle, .space, .returnKey]
    ]

    // MARK: - Page Lookup

    static func rows(for page: KeyboardPage) -> [[KeyAction]] {
        switch page {
        case .letters:  return lettersRows
        case .numbers:  return numbersRows
        case .symbols:  return symbolsRows
        }
    }

    // MARK: - Key Role Classification

    /// Whether a key should use the "special" (darker) background style
    static func isSpecialKey(_ action: KeyAction) -> Bool {
        switch action {
        case .character, .space, .returnKey:
            return false
        case .shift, .backspace, .modeChange, .snippetToggle:
            return true
        }
    }

    /// Number of character keys in a given row (for width calculation)
    static func characterCountInRow(_ row: [KeyAction]) -> Int {
        return row.filter {
            if case .character = $0 { return true }
            return false
        }.count
    }
}
