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

    // MARK: - Pop-up Dimensions

    /// Width of the pop-up balloon
    var popupWidth: CGFloat { 52 }

    /// Height of the pop-up body (excluding tail)
    var popupBodyHeight: CGFloat { 48 }

    /// Height of the downward-pointing tail
    var popupTailHeight: CGFloat { 8 }

    /// Vertical gap between key top and popup tail tip
    var popupGap: CGFloat { 0 }

    // MARK: - Key Frame Calculation

    /// Computes the visual frame of a key in the keyboard's coordinate space.
    /// Used to position the pop-up balloon above the pressed key.
    ///
    /// - Parameters:
    ///   - rowIndex: The row (0=top, 3=bottom)
    ///   - columnIndex: The column within that row
    ///   - keyWidth: The visual width of this specific key
    /// - Returns: The CGRect of the key's visual background in keyboard coordinate
    func keyFrame(rowIndex: Int, columnIndex: Int, keyWidth: CGFloat, rowActions: [KeyAction]) -> CGRect {
        // Y position: toolbar + top edge + (row * (keyHeight + rowGap))
        let y = toolbarHeight + topEdge + CGFloat(rowIndex) * (keyHeight + rowGap)

        // X position: walk through columns to accumulate x offset
        var x = sideEdge
        for i in 0..<columnIndex {
            let action = rowActions[i]
            let w = visualKeyWidth(for: action, rowIndex: rowIndex, rowActions: rowActions)
            x += w + keyGap
        }

        return CGRect(x: x, y: y, width: keyWidth, height: keyHeight)
    }

    /// Compute visual width for a key action (mirrors KeyRowView logic).
    /// This duplicates the width logic here so popup positioning doesn't depend on SwiftUI layout.
    private func visualKeyWidth(for action: KeyAction, rowIndex: Int, rowActions: [KeyAction]) -> CGFloat {
        switch action {
        case .character:
            if rowIndex <= 1 {
                return letterKeyWidth
            }
            // Mixed row: compute character key width
            let charCount = QWERTYKeyboardLayout.characterCountInRow(rowActions)
            guard charCount > 0 else { return letterKeyWidth }
            let specialKeys = rowActions.filter {
                if case .character = $0 { return false }
                return true
            }
            let specialWidth = specialKeys.reduce(CGFloat(0)) { total, act in
                switch act {
                case .shift, .backspace, .modeChange:
                    return total + shiftKeyWidth
                default:
                    return total + bottomSpecialKeyWidth
                }
            }
            let totalGaps = keyGap * CGFloat(rowActions.count - 1)
            let totalSideEdges = sideEdge * 2
            let availableWidth = screenWidth - totalSideEdges - specialWidth - totalGaps
            return availableWidth / CGFloat(charCount)

        case .shift, .backspace:
            return shiftKeyWidth
        case .space:
            return spaceKeyWidth
        case .returnKey:
            return returnKeyWidth
        case .modeChange:
            if rowIndex == 3 { return bottomSpecialKeyWidth }
            return shiftKeyWidth
        case .snippetToggle:
            return bottomSpecialKeyWidth
        }
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
