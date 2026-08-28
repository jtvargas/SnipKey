//
//  KeyboardDimensions.swift
//  SnipKeyboard
//
//  Created by Jonathan Taveras Vargas on 2/10/26.
//

import Foundation

/// Computes all key measurements dynamically from the available screen width.
/// Based on native iOS keyboard measurements across iPhone models.
struct KeyboardDimensions: Equatable {
    let screenWidth: CGFloat

    // MARK: - Core Measurements

    /// Height of a single key row (scales with screen width)
    var keyHeight: CGFloat {
        // Match native iOS keyboard: ~42pt on 393pt, ~40pt on 375pt, ~46pt on 430pt
        return max(round(screenWidth * 0.107), 38)
    }

    /// Horizontal gap between keys (visual gap — used for padding inside each key)
    var keyGap: CGFloat { 6 }

    /// Vertical gap between rows
    var rowGap: CGFloat {
        // Match native iOS keyboard row spacing (~11pt)
        return 11
    }

    /// Left/right margin from screen edge to first/last key
    var sideEdge: CGFloat {
        return screenWidth < 400 ? 3 : 4
    }

    /// Top padding above the first row
    var topEdge: CGFloat {
        // Match native iOS keyboard top padding (~6pt)
        return 6
    }

    /// Bottom padding below the last row
    var bottomEdge: CGFloat {
        return screenWidth < 400 ? 3 : 4
    }

    /// Corner radius of individual keys. Matches native iOS 26 measurements:
    /// ~6pt on small phones, ~7pt on standard iPhones (393pt wide), ~8pt on Plus/Pro Max (430pt+).
    var cornerRadius: CGFloat {
        if screenWidth < 350 { return 6 }
        if screenWidth < 400 { return 7 }
        return 8
    }

    // MARK: - Key Widths (visual width of the key background, not including gap padding)

    /// Number of keys in the widest row (top row: Q W E R T Y U I O P)
    private var maxKeysPerRow: Int { 10 }

    /// Width of a standard letter key
    var letterKeyWidth: CGFloat {
        let totalGaps = (sideEdge * 2) + (keyGap * CGFloat(maxKeysPerRow - 1))
        return (screenWidth - totalGaps) / CGFloat(maxKeysPerRow)
    }

    /// Width of shift and backspace keys (row 2: fills remaining space after 7 letters)
    var shiftKeyWidth: CGFloat {
        let lettersWidth = letterKeyWidth * 7 + keyGap * 6
        let remaining = screenWidth - lettersWidth - sideEdge * 2 - keyGap * 2
        return remaining / 2
    }

    /// Width of the space bar (fills remaining space on bottom row)
    var spaceKeyWidth: CGFloat {
        // Bottom row: [modeChange] [snippetToggle] [space] [return]
        let fixedKeysWidth = bottomSpecialKeyWidth * 2 + returnKeyWidth
        let gaps = keyGap * 3
        return screenWidth - fixedKeysWidth - gaps - sideEdge * 2
    }

    /// Width of the return key
    var returnKeyWidth: CGFloat {
        return round(screenWidth * 0.23)
    }

    /// Width of bottom row special keys (123, snippet toggle)
    var bottomSpecialKeyWidth: CGFloat {
        return round(screenWidth * 0.12)
    }

    // MARK: - Total Heights

    /// Height of just the 4 key rows + gaps + edges
    var keysAreaHeight: CGFloat {
        let rows: CGFloat = 4
        let gaps: CGFloat = 3
        return keyHeight * rows + rowGap * gaps + topEdge + bottomEdge
    }

    /// Height of the toolbar above the keys (snippet toggle, future suggestion bar)
    /// Matches native iOS prediction/suggestion bar height (~44pt)
    var toolbarHeight: CGFloat { 44 }

    /// Empty gap reserved at the bottom of the toolbar so suggestion/snippet hit cells
    /// don't butt up against the top key row's hit cells. Keeps the toolbar's overall
    /// height (and thus the keys' top anchor) unchanged.
    var toolbarItemBottomGap: CGFloat { 6 }

    /// Total keyboard height (toolbar + keys area)
    var totalHeight: CGFloat {
        return toolbarHeight + keysAreaHeight
    }


    // MARK: - Static Helpers

    /// Compute total height for a given screen width. Used by the controller
    /// to set the height constraint and by the snippet grid for matching height.
    static func totalHeight(forScreenWidth width: CGFloat) -> CGFloat {
        return KeyboardDimensions(screenWidth: width).totalHeight
    }

    /// Estimated total height using the current device's screen width.
    /// Fallback for contexts where UIScreen is not available.
    static var estimatedTotalHeight: CGFloat {
        return KeyboardDimensions(screenWidth: 393).totalHeight
    }
}
