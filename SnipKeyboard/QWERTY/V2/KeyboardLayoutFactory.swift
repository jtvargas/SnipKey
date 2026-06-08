//
//  KeyboardLayoutFactory.swift
//  SnipKeyboard
//
//  Produces `KeyboardLayout` values for letters/numbers/symbols. V2-only.
//  The legacy `QWERTYKeyboardLayout.lettersRows` etc. remain in place for the V1 path.
//

import UIKit

enum KeyboardLayoutFactory {

    static func layout(for page: KeyboardPage, profile: KeyboardLayoutProfile = .standard, dims: KeyboardDimensions) -> KeyboardLayout {
        switch page {
        case .letters: return lettersLayout(profile: profile, dims: dims)
        case .numbers: return numbersLayout(profile: profile, dims: dims)
        case .symbols: return symbolsLayout(profile: profile, dims: dims)
        }
    }

    // MARK: - Layout helpers

    /// Inset that centers `letterCount` keys of width `dims.letterKeyWidth` inside the
    /// keyboard's usable row width. Used by rows that have fewer than 10 letters but
    /// need to keep each letter the same visual width as row 0.
    private static func centeredLetterRowInset(letterCount: Int, dims: KeyboardDimensions) -> CGFloat {
        let usableRowWidth = max(dims.screenWidth - dims.sideEdge * 2, 0)
        let lettersWidth = dims.letterKeyWidth * CGFloat(letterCount) + dims.keyGap * CGFloat(max(letterCount - 1, 0))
        return max((usableRowWidth - lettersWidth) / 2, 0)
    }

    private static func letterItem(_ s: String, width: CGFloat) -> KeyboardLayoutItem {
        KeyboardLayoutItem(action: .character(s), width: .points(width))
    }

    private static func shortcutItem(_ label: String, output: String? = nil, width: CGFloat) -> KeyboardLayoutItem {
        KeyboardLayoutItem(action: .insertText(label: label, output: output ?? label), width: .points(width))
    }

    private static func thirdRowSideControlWidth(dims: KeyboardDimensions) -> CGFloat {
        round(dims.screenWidth * 0.115)
    }

    private static func sideControlRow(
        leading: KeyboardLayoutItem,
        center: [KeyboardLayoutItem],
        trailing: KeyboardLayoutItem,
        dims: KeyboardDimensions
    ) -> KeyboardRow {
        let items = [leading] + center + [trailing]
        let usableRowWidth = max(dims.screenWidth - dims.sideEdge * 2, 0)
        let fixedWidth = items.reduce(CGFloat(0)) { total, item in
            switch item.width {
            case .points(let width):
                return total + width
            case .percentage(let fraction):
                return total + usableRowWidth * fraction
            case .input, .available:
                return total
            }
        }
        let centerGapsWidth = dims.keyGap * CGFloat(max(center.count - 1, 0))
        let sideGap = max((usableRowWidth - fixedWidth - centerGapsWidth) / 2, dims.keyGap)
        let gaps = [sideGap] + Array(repeating: dims.keyGap, count: max(center.count - 1, 0)) + [sideGap]
        return KeyboardRow(items: items, gapsAfter: gaps)
    }

    // MARK: - Letters

    private static func lettersLayout(profile: KeyboardLayoutProfile, dims: KeyboardDimensions) -> KeyboardLayout {
        let lw = dims.letterKeyWidth

        // Row 0: 10 letters as `.input` (fills row, naturally giving each `letterKeyWidth`).
        let topRow = KeyboardRow(items: "QWERTYUIOP".map { letterItem(String($0), width: lw) })

        // Row 1: 9 letters at the same width as row 0, centered with equal insets on each side.
        let row1Inset = centeredLetterRowInset(letterCount: 9, dims: dims)
        let middleRow = KeyboardRow(
            items: "ASDFGHJKL".map { letterItem(String($0), width: lw) },
            leadingInset: row1Inset,
            trailingInset: row1Inset
        )

        // Row 2: native side controls are edge-aligned with Q/P, with a larger gap before
        // the centered letter block.
        let row2ControlWidth = thirdRowSideControlWidth(dims: dims)
        let row2 = sideControlRow(
            leading: KeyboardLayoutItem(action: .shift, width: .points(row2ControlWidth)),
            center: "ZXCVBNM".map { letterItem(String($0), width: lw) },
            trailing: KeyboardLayoutItem(action: .backspace, width: .points(row2ControlWidth)),
            dims: dims
        )

        let bottomRow = bottomRow(profile: profile, modeTarget: .numbers, dims: dims)
        return KeyboardLayout(rows: [topRow, middleRow, row2, bottomRow])
    }

    // MARK: - Numbers

    private static func numbersLayout(profile: KeyboardLayoutProfile, dims: KeyboardDimensions) -> KeyboardLayout {
        let lw = dims.letterKeyWidth

        let topRow = KeyboardRow(items: "1234567890".map { letterItem(String($0), width: lw) })
        // Row 1 has 10 chars on numbers page → use `.input` (matches row 0).
        let middleRow = KeyboardRow(items: "-/:;()$&@\"".map { letterItem(String($0), width: lw) })

        // Row 2: native punctuation row with fixed mode/delete controls and wider punctuation keys.
        let row2ControlWidth = thirdRowSideControlWidth(dims: dims)
        let punctuationWidth = round(dims.screenWidth * 0.122)
        let row2 = sideControlRow(
            leading: KeyboardLayoutItem(action: .modeChange(.symbols), width: .points(row2ControlWidth)),
            center: ".,?!'".map { letterItem(String($0), width: punctuationWidth) },
            trailing: KeyboardLayoutItem(action: .backspace, width: .points(row2ControlWidth)),
            dims: dims
        )

        let bottomRow = bottomRow(profile: .standard, modeTarget: .letters, dims: dims)
        return KeyboardLayout(rows: [topRow, middleRow, row2, bottomRow])
    }

    // MARK: - Symbols

    private static func symbolsLayout(profile: KeyboardLayoutProfile, dims: KeyboardDimensions) -> KeyboardLayout {
        let lw = dims.letterKeyWidth

        let topRow = KeyboardRow(items: "[]{}#%^*+=".map { letterItem(String($0), width: lw) })
        let middleChars: [String] = profile == .asciiCapable
            ? ["_", "\\", "|", "~", "<", ">", "`", "^", "{", "}"]
            : ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"]
        let middleRow = KeyboardRow(items: middleChars.map { letterItem($0, width: lw) })

        // Row 2: native punctuation row with fixed mode/delete controls and wider punctuation keys.
        let row2ControlWidth = thirdRowSideControlWidth(dims: dims)
        let punctuationWidth = round(dims.screenWidth * 0.122)
        let row2 = sideControlRow(
            leading: KeyboardLayoutItem(action: .modeChange(.numbers), width: .points(row2ControlWidth)),
            center: ".,?!'".map { letterItem(String($0), width: punctuationWidth) },
            trailing: KeyboardLayoutItem(action: .backspace, width: .points(row2ControlWidth)),
            dims: dims
        )

        let bottomRow = bottomRow(profile: .standard, modeTarget: .letters, dims: dims)
        return KeyboardLayout(rows: [topRow, middleRow, row2, bottomRow])
    }

    // MARK: - Bottom Row

    /// Bottom row used on every page: [modeChange] [snippetToggle] [space] [returnKey].
    /// Fixed-width special keys + greedy space.
    private static func bottomRow(profile: KeyboardLayoutProfile, modeTarget: KeyboardPage, dims: KeyboardDimensions) -> KeyboardRow {
        let specialWidth: CGFloat = dims.bottomSpecialKeyWidth
        let returnWidth: CGFloat = dims.returnKeyWidth
        let shortcutWidth: CGFloat = round(dims.screenWidth * 0.11)
        let domainWidth: CGFloat = round(dims.screenWidth * 0.18)

        let items: [KeyboardLayoutItem]
        switch profile {
        case .emailAddress:
            items = [
                KeyboardLayoutItem(action: .modeChange(modeTarget), width: .points(specialWidth)),
                KeyboardLayoutItem(action: .snippetToggle, width: .points(specialWidth)),
                shortcutItem("@", width: shortcutWidth),
                KeyboardLayoutItem(action: .space, width: .available),
                shortcutItem(".", width: shortcutWidth),
                KeyboardLayoutItem(action: .returnKey, width: .points(returnWidth)),
            ]
        case .url:
            items = [
                KeyboardLayoutItem(action: .modeChange(modeTarget), width: .points(specialWidth)),
                KeyboardLayoutItem(action: .snippetToggle, width: .points(specialWidth)),
                shortcutItem("/", width: shortcutWidth),
                shortcutItem(".", width: shortcutWidth),
                shortcutItem(".com", width: domainWidth),
                KeyboardLayoutItem(action: .returnKey, width: .points(returnWidth)),
            ]
        case .webSearch:
            items = [
                KeyboardLayoutItem(action: .modeChange(modeTarget), width: .points(specialWidth)),
                KeyboardLayoutItem(action: .snippetToggle, width: .points(specialWidth)),
                KeyboardLayoutItem(action: .space, width: .available),
                shortcutItem(".", width: shortcutWidth),
                KeyboardLayoutItem(action: .returnKey, width: .points(returnWidth)),
            ]
        case .twitter:
            items = [
                KeyboardLayoutItem(action: .modeChange(modeTarget), width: .points(specialWidth)),
                KeyboardLayoutItem(action: .snippetToggle, width: .points(specialWidth)),
                shortcutItem("@", width: shortcutWidth),
                KeyboardLayoutItem(action: .space, width: .available),
                shortcutItem("#", width: shortcutWidth),
                KeyboardLayoutItem(action: .returnKey, width: .points(returnWidth)),
            ]
        case .standard, .asciiCapable:
            items = [
                KeyboardLayoutItem(action: .modeChange(modeTarget), width: .points(specialWidth)),
                KeyboardLayoutItem(action: .snippetToggle, width: .points(specialWidth)),
                KeyboardLayoutItem(action: .space, width: .available),
                KeyboardLayoutItem(action: .returnKey, width: .points(returnWidth)),
            ]
        }
        return KeyboardRow(items: items)
    }

    private static func standardBottomRow(modeTarget: KeyboardPage, dims: KeyboardDimensions) -> KeyboardRow {
        let specialWidth: CGFloat = dims.bottomSpecialKeyWidth
        let returnWidth: CGFloat = dims.returnKeyWidth
        return KeyboardRow(items: [
            KeyboardLayoutItem(action: .modeChange(modeTarget), width: .points(specialWidth)),
            KeyboardLayoutItem(action: .snippetToggle, width: .points(specialWidth)),
            KeyboardLayoutItem(action: .space, width: .available),
            KeyboardLayoutItem(action: .returnKey, width: .points(returnWidth)),
        ])
    }
}
