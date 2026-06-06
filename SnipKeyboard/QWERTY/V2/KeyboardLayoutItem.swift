//
//  KeyboardLayoutItem.swift
//  SnipKeyboard
//
//  V2 layout primitive — flexible width units that let rows balance correctly
//  without role-specific switches scattered throughout the codebase.
//

import UIKit

/// Width sizing modes for a key, modeled after KeyboardKit's `KeyboardLayoutItem.Size`.
enum KeyWidth: Equatable {
    /// Standard character-key width. All `.input` items in a row share the
    /// available width equally after fixed and percentage items are subtracted.
    case input
    /// Width as a fraction of the row's available width (0...1).
    case percentage(CGFloat)
    /// Width in absolute points.
    case points(CGFloat)
    /// Greedy — split whatever is left across all `.available` items in the row.
    case available
}

/// A single keyboard item — what action it triggers and how wide it is.
struct KeyboardLayoutItem {
    let action: KeyAction
    let width: KeyWidth
    /// Touch-slop reduction into the gap on each side. The visible key uses these,
    /// but the gesture coordinator routes touches that fall in the gaps to the nearest key.
    let insets: UIEdgeInsets

    init(action: KeyAction, width: KeyWidth, insets: UIEdgeInsets = .zero) {
        self.action = action
        self.width = width
        self.insets = insets
    }
}

/// A single row of keys with optional leading/trailing padding. Rows 1 and 2 of the
/// letters layout use non-zero insets so their letters stay the same width as row 0
/// (matching native iOS visual alignment), while shift/backspace consume the rest.
struct KeyboardRow {
    let items: [KeyboardLayoutItem]
    let leadingInset: CGFloat
    let trailingInset: CGFloat
    let gapsAfter: [CGFloat]?

    init(items: [KeyboardLayoutItem], leadingInset: CGFloat = 0, trailingInset: CGFloat = 0, gapsAfter: [CGFloat]? = nil) {
        self.items = items
        self.leadingInset = leadingInset
        self.trailingInset = trailingInset
        self.gapsAfter = gapsAfter
    }
}

/// A full keyboard layout — 4 rows of items for a single page (letters/numbers/symbols).
struct KeyboardLayout {
    let rows: [KeyboardRow]
}
