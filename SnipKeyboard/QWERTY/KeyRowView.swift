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
///
/// Probabilistic touch targeting:
/// - On the letters page, rows 0-2 (which contain character keys) pass pre-computed
///   row geometry to each KeyButtonView. On touch-down, each character key runs
///   DynamicHitResolver inline to decide if the touch should redirect to a neighbor.
/// - On numbers/symbols pages, KeyButtonView receives nil probabilistic data
///   and uses static per-key touch handling (zero overhead).
struct KeyRowView: View {
    let actions: [KeyAction]
    let rowIndex: Int
    let dimensions: KeyboardDimensions

    @Environment(QWERTYKeyboardState.self) private var state

    var body: some View {
        // Pre-compute probabilistic data once for the entire row.
        // nil on numbers/symbols pages or row 3 (bottom row — no character keys).
        // This is computed during SwiftUI layout, NOT per keystroke.
        let probData = probabilisticRowData()

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
                    rowActions: actions,
                    // Probabilistic data — nil for non-character keys or non-letters pages
                    rowKeyRects: probData?.keyRects,
                    rowCharacters: probData?.characters,
                    characterIndex: probData?.characterIndex(forColumnIndex: index),
                    keyOffsetInRow: probData?.keyOffset(forColumnIndex: index) ?? 0
                )
            }
        }
    }

    // MARK: - Probabilistic Row Data

    /// Pre-computed geometry for probabilistic touch resolution.
    /// Computed once per row per SwiftUI layout pass (when page changes or dimensions change).
    /// Contains everything a character KeyButtonView needs to run DynamicHitResolver inline.
    private struct ProbabilisticRowData {
        /// (centerX, width) for each character key in row coordinate space.
        /// Used directly by DynamicHitResolver.resolve().
        let keyRects: [(centerX: CGFloat, width: CGFloat)]

        /// Character strings in row order (e.g., ["Q","W","E",...]).
        let characters: [String]

        /// X offset of each key's tappable left edge in row coordinate space.
        /// Indexed by column index in the full actions array (not character index).
        let keyOffsets: [Int: CGFloat]

        /// Map from column index (in full actions array) to character index.
        let columnToCharIndex: [Int: Int]

        /// Returns the character index for a given column index, or nil for non-character keys.
        func characterIndex(forColumnIndex col: Int) -> Int? {
            columnToCharIndex[col]
        }

        /// Returns the X offset of a key's tappable left edge for a given column index.
        /// Non-character keys return 0 (they don't use this value).
        func keyOffset(forColumnIndex col: Int) -> CGFloat {
            keyOffsets[col] ?? 0
        }
    }

    /// Compute probabilistic row data for the letters page, rows 0-2.
    /// Returns nil when probabilistic targeting is not applicable.
    ///
    /// Performance: Pure arithmetic over the row's actions array (~200ns for 10 keys).
    /// Computed during SwiftUI layout, NOT on the touch hot path.
    private func probabilisticRowData() -> ProbabilisticRowData? {
        guard state.currentPage == .letters else { return nil }
        guard rowIndex <= 2 else { return nil }

        // Extract character keys and build column-to-character-index mapping
        var characters: [String] = []
        var columnToCharIndex: [Int: Int] = [:]

        for (i, action) in actions.enumerated() {
            if case .character(let c) = action {
                columnToCharIndex[i] = characters.count
                characters.append(c)
            }
        }

        guard !characters.isEmpty else { return nil }

        // Compute key rects (centerX, width) in row coordinate space.
        // Walk through ALL actions to accumulate X positions.
        let charKeyWidth = visualKeyWidth(for: .character("A")) // All char keys same width in a row
        var keyRects: [(centerX: CGFloat, width: CGFloat)] = []
        keyRects.reserveCapacity(characters.count)

        var keyOffsets: [Int: CGFloat] = [:]
        var x: CGFloat = 0 // Tracks the left edge of each key's tappable area

        for (i, action) in actions.enumerated() {
            let w = visualKeyWidth(for: action)
            let leading: CGFloat = (i == 0) ? dimensions.sideEdge : dimensions.keyGap / 2
            let trailing: CGFloat = (i == actions.count - 1) ? dimensions.sideEdge : dimensions.keyGap / 2

            if case .character = action {
                // Store the tappable left edge offset for this character key
                keyOffsets[i] = x

                // Key rect: center of the visual key within row coordinate space
                // The visual key starts at x + leading, so center is at x + leading + w/2
                let centerX = x + leading + w / 2
                keyRects.append((centerX: centerX, width: w))
            }

            x += leading + w + trailing
        }

        return ProbabilisticRowData(
            keyRects: keyRects,
            characters: characters,
            keyOffsets: keyOffsets,
            columnToCharIndex: columnToCharIndex
        )
    }

    // MARK: - Visual Key Width Calculation

    /// The visual width of the key background (not including gap padding).
    func visualKeyWidth(for action: KeyAction) -> CGFloat {
        switch action {
        case .character:
            if isTopOrMiddleRow {
                return dimensions.letterKeyWidth
            }
            return characterKeyWidthInMixedRow

        case .insertText(let label, _):
            if label.count > 1 {
                return round(dimensions.screenWidth * 0.18)
            }
            return round(dimensions.screenWidth * 0.11)

        case .shift, .backspace:
            return dimensions.shiftKeyWidth

        case .space:
            if isBottomRow {
                return bottomRowSpaceWidth
            }
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

    private var bottomRowSpaceWidth: CGFloat {
        let fixedWidth = actions.reduce(CGFloat(0)) { total, action in
            switch action {
            case .space:
                return total
            case .modeChange, .snippetToggle:
                return total + dimensions.bottomSpecialKeyWidth
            case .returnKey:
                return total + dimensions.returnKeyWidth
            case .insertText(let label, _):
                let width = label.count > 1
                    ? round(dimensions.screenWidth * 0.18)
                    : round(dimensions.screenWidth * 0.11)
                return total + width
            case .character:
                return total + dimensions.bottomSpecialKeyWidth
            case .shift, .backspace:
                return total + dimensions.shiftKeyWidth
            }
        }
        let totalGaps = dimensions.keyGap * CGFloat(max(actions.count - 1, 0))
        let totalSideEdges = dimensions.sideEdge * 2
        let availableWidth = dimensions.screenWidth - totalSideEdges - fixedWidth - totalGaps
        return max(availableWidth, 52)
    }
}
