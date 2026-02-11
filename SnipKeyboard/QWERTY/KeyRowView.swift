//
//  KeyRowView.swift
//  SnipKeyboard
//
//  Created by Jonathan Taveras Vargas on 2/10/26.
//

import SwiftUI

/// Renders a single horizontal row of keyboard keys.
///
/// Layout strategy:
/// - Uses `HStack(spacing: 0)` — no inter-key spacing at the HStack level.
/// - Each key handles its own horizontal padding (half the keyGap on each side,
///   sideEdge on the outer edges). This means the tappable area extends into
///   the visual gap between keys, eliminating dead zones.
/// - The visual key background is inset within the tappable frame.
struct KeyRowView: View {
    let actions: [KeyAction]
    let rowIndex: Int
    let dimensions: KeyboardDimensions

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(actions.enumerated()), id: \.element) { index, action in
                let isFirst = index == 0
                let isLast = index == actions.count - 1

                KeyButtonView(
                    action: action,
                    dimensions: dimensions,
                    keyWidth: visualKeyWidth(for: action),
                    leadingPad: isFirst ? dimensions.sideEdge : dimensions.keyGap / 2,
                    trailingPad: isLast ? dimensions.sideEdge : dimensions.keyGap / 2,
                    rowIndex: rowIndex,
                    columnIndex: index,
                    rowActions: actions
                )
            }
        }
    }

    // MARK: - Visual Key Width Calculation

    /// The visual width of the key background (not including gap padding).
    private func visualKeyWidth(for action: KeyAction) -> CGFloat {
        switch action {
        case .character:
            if isTopOrMiddleRow {
                return dimensions.letterKeyWidth
            }
            return characterKeyWidthInMixedRow

        case .shift, .backspace:
            return dimensions.shiftKeyWidth

        case .space:
            return dimensions.spaceKeyWidth

        case .returnKey:
            return dimensions.returnKeyWidth

        case .modeChange:
            if isBottomRow {
                return dimensions.bottomSpecialKeyWidth
            }
            // Mode change in row 2 (e.g., "#+=" or "123" on numbers/symbols pages)
            return dimensions.shiftKeyWidth

        case .snippetToggle:
            return dimensions.bottomSpecialKeyWidth
        }
    }

    /// Whether this is the top row (row 0) or middle row (row 1) — rows with only letter keys
    private var isTopOrMiddleRow: Bool {
        return rowIndex <= 1
    }

    /// Whether this is the bottom row (row 3)
    private var isBottomRow: Bool {
        return rowIndex == 3
    }

    /// Width for character keys in mixed rows (row 2: shift + letters + backspace).
    private var characterKeyWidthInMixedRow: CGFloat {
        let charCount = QWERTYKeyboardLayout.characterCountInRow(actions)
        guard charCount > 0 else { return dimensions.letterKeyWidth }

        let specialKeys = actions.filter {
            if case .character = $0 { return false }
            return true
        }
        let specialWidth = specialKeys.reduce(CGFloat(0)) { total, action in
            switch action {
            case .shift, .backspace, .modeChange:
                return total + dimensions.shiftKeyWidth
            default:
                return total + dimensions.bottomSpecialKeyWidth
            }
        }

        let totalGaps = dimensions.keyGap * CGFloat(actions.count - 1)
        let totalSideEdges = dimensions.sideEdge * 2
        let availableWidth = dimensions.screenWidth - totalSideEdges - specialWidth - totalGaps

        return availableWidth / CGFloat(charCount)
    }
}
