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
        max((dims.usableRowWidth - dims.letterBlockWidth(count: letterCount)) / 2, 0)
    }

    private static func letterItem(_ s: String, width: CGFloat) -> KeyboardLayoutItem {
        KeyboardLayoutItem(action: .character(s), width: .points(width))
    }

    private static func shortcutItem(_ label: String, output: String? = nil, width: CGFloat) -> KeyboardLayoutItem {
        KeyboardLayoutItem(action: .insertText(label: label, output: output ?? label), width: .points(width))
    }

    /// Third row on every page: a `sideControlKeyWidth` control on each edge (aligned
    /// with Q/P), `dims.sideControlGap` on both sides of a centered block whose keys are
    /// `keyGap` apart. `center` must span `dims.letterBlockWidth(count: 7)` — true for
    /// the 7 letters and, by construction of `punctuationKeyWidth`, for the 5 punctuation keys.
    private static func sideControlRow(
        leading: KeyAction,
        center: [KeyboardLayoutItem],
        trailing: KeyAction,
        dims: KeyboardDimensions
    ) -> KeyboardRow {
        let controlWidth = dims.sideControlKeyWidth
        let items = [KeyboardLayoutItem(action: leading, width: .points(controlWidth))]
            + center
            + [KeyboardLayoutItem(action: trailing, width: .points(controlWidth))]
        let gaps = [dims.sideControlGap]
            + Array(repeating: dims.keyGap, count: max(center.count - 1, 0))
            + [dims.sideControlGap]
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
        let row2 = sideControlRow(
            leading: .shift,
            center: "ZXCVBNM".map { letterItem(String($0), width: lw) },
            trailing: .backspace,
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

        // Row 2: native punctuation row — 5 wider keys spanning the letters page's 7-key block.
        let row2 = sideControlRow(
            leading: .modeChange(.symbols),
            center: ".,?!'".map { letterItem(String($0), width: dims.punctuationKeyWidth) },
            trailing: .backspace,
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

        // Row 2: native punctuation row — 5 wider keys spanning the letters page's 7-key block.
        let row2 = sideControlRow(
            leading: .modeChange(.numbers),
            center: ".,?!'".map { letterItem(String($0), width: dims.punctuationKeyWidth) },
            trailing: .backspace,
            dims: dims
        )

        let bottomRow = bottomRow(profile: .standard, modeTarget: .letters, dims: dims)
        return KeyboardLayout(rows: [topRow, middleRow, row2, bottomRow])
    }

    // MARK: - Bottom Row

    /// Bottom row used on every page: [modeChange] [emojiToggle] [space] [returnKey].
    /// 123 and Emoji are `sideControlKeyWidth`, return is `returnKeyWidth`,
    /// space is greedy. Profile rows add shortcut keys at the side-control width; the URL
    /// profile has no space bar, so its `.com` key takes the greedy slot instead (as native).
    private static func bottomRow(profile: KeyboardLayoutProfile, modeTarget: KeyboardPage, dims: KeyboardDimensions) -> KeyboardRow {
        let specialWidth: CGFloat = dims.sideControlKeyWidth
        let returnWidth: CGFloat = dims.returnKeyWidth
        let shortcutWidth: CGFloat = dims.sideControlKeyWidth

        let items: [KeyboardLayoutItem]
        switch profile {
        case .emailAddress:
            items = [
                KeyboardLayoutItem(action: .modeChange(modeTarget), width: .points(specialWidth)),
                KeyboardLayoutItem(action: .emojiToggle, width: .points(specialWidth)),
                shortcutItem("@", width: shortcutWidth),
                KeyboardLayoutItem(action: .space, width: .available),
                shortcutItem(".", width: shortcutWidth),
                KeyboardLayoutItem(action: .returnKey, width: .points(returnWidth)),
            ]
        case .url:
            items = [
                KeyboardLayoutItem(action: .modeChange(modeTarget), width: .points(specialWidth)),
                KeyboardLayoutItem(action: .emojiToggle, width: .points(specialWidth)),
                shortcutItem("/", width: shortcutWidth),
                shortcutItem(".", width: shortcutWidth),
                KeyboardLayoutItem(action: .insertText(label: ".com", output: ".com"), width: .available),
                KeyboardLayoutItem(action: .returnKey, width: .points(returnWidth)),
            ]
        case .webSearch:
            items = [
                KeyboardLayoutItem(action: .modeChange(modeTarget), width: .points(specialWidth)),
                KeyboardLayoutItem(action: .emojiToggle, width: .points(specialWidth)),
                KeyboardLayoutItem(action: .space, width: .available),
                shortcutItem(".", width: shortcutWidth),
                KeyboardLayoutItem(action: .returnKey, width: .points(returnWidth)),
            ]
        case .twitter:
            items = [
                KeyboardLayoutItem(action: .modeChange(modeTarget), width: .points(specialWidth)),
                KeyboardLayoutItem(action: .emojiToggle, width: .points(specialWidth)),
                shortcutItem("@", width: shortcutWidth),
                KeyboardLayoutItem(action: .space, width: .available),
                shortcutItem("#", width: shortcutWidth),
                KeyboardLayoutItem(action: .returnKey, width: .points(returnWidth)),
            ]
        case .standard, .asciiCapable:
            items = [
                KeyboardLayoutItem(action: .modeChange(modeTarget), width: .points(specialWidth)),
                KeyboardLayoutItem(action: .emojiToggle, width: .points(specialWidth)),
                KeyboardLayoutItem(action: .space, width: .available),
                KeyboardLayoutItem(action: .returnKey, width: .points(returnWidth)),
            ]
        }
        return KeyboardRow(items: items)
    }
}
