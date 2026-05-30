//
//  KeyboardLayoutFactory.swift
//  SnipKeyboard
//
//  Produces `KeyboardLayout` values for letters/numbers/symbols. V2-only.
//  The legacy `QWERTYKeyboardLayout.lettersRows` etc. remain in place for the V1 path.
//

import UIKit

enum KeyboardLayoutFactory {

    static func layout(for page: KeyboardPage, dims: KeyboardDimensions) -> KeyboardLayout {
        switch page {
        case .letters: return lettersLayout(dims: dims)
        case .numbers: return numbersLayout(dims: dims)
        case .symbols: return symbolsLayout(dims: dims)
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

    // MARK: - Letters

    private static func lettersLayout(dims: KeyboardDimensions) -> KeyboardLayout {
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

        // Row 2: shift + 7 letters (same width as row 0) + backspace. Shift and backspace
        // fill the natural padding around the centered letter block.
        let row2 = KeyboardRow(items:
            [KeyboardLayoutItem(action: .shift, width: .available)] +
            "ZXCVBNM".map { letterItem(String($0), width: lw) } +
            [KeyboardLayoutItem(action: .backspace, width: .available)]
        )

        let bottomRow = standardBottomRow(modeTarget: .numbers, dims: dims)
        return KeyboardLayout(rows: [topRow, middleRow, row2, bottomRow])
    }

    // MARK: - Numbers

    private static func numbersLayout(dims: KeyboardDimensions) -> KeyboardLayout {
        let lw = dims.letterKeyWidth

        let topRow = KeyboardRow(items: "1234567890".map { letterItem(String($0), width: lw) })
        // Row 1 has 10 chars on numbers page → use `.input` (matches row 0).
        let middleRow = KeyboardRow(items: "-/:;()$&@\"".map { letterItem(String($0), width: lw) })

        // Row 2: mode-change + 5 chars + backspace. 5 chars at letterKeyWidth match row 0 alignment.
        let row2 = KeyboardRow(items:
            [KeyboardLayoutItem(action: .modeChange(.symbols), width: .available)] +
            ".,?!'".map { letterItem(String($0), width: lw) } +
            [KeyboardLayoutItem(action: .backspace, width: .available)]
        )

        let bottomRow = standardBottomRow(modeTarget: .letters, dims: dims)
        return KeyboardLayout(rows: [topRow, middleRow, row2, bottomRow])
    }

    // MARK: - Symbols

    private static func symbolsLayout(dims: KeyboardDimensions) -> KeyboardLayout {
        let lw = dims.letterKeyWidth

        let topRow = KeyboardRow(items: "[]{}#%^*+=".map { letterItem(String($0), width: lw) })
        let middleChars: [String] = ["_", "\\", "|", "~", "<", ">", ".", ",", "?", "!"]
        let middleRow = KeyboardRow(items: middleChars.map { letterItem($0, width: lw) })

        // Row 2: mode-change + 6 chars + backspace.
        let row2 = KeyboardRow(items:
            [KeyboardLayoutItem(action: .modeChange(.numbers), width: .available)] +
            "-/:;()".map { letterItem(String($0), width: lw) } +
            [KeyboardLayoutItem(action: .backspace, width: .available)]
        )

        let bottomRow = standardBottomRow(modeTarget: .letters, dims: dims)
        return KeyboardLayout(rows: [topRow, middleRow, row2, bottomRow])
    }

    // MARK: - Bottom Row

    /// Bottom row used on every page: [modeChange] [snippetToggle] [space] [returnKey].
    /// Fixed-width special keys + greedy space.
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
