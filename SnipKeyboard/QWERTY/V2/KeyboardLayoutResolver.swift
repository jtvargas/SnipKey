//
//  KeyboardLayoutResolver.swift
//  SnipKeyboard
//
//  Pure functional resolver: turns a KeyboardLayout into concrete CGRect frames
//  in keyboard-local coordinates. Cached per (page, screenWidth) so that touch
//  routing and rendering both read from the same precomputed table.
//

import UIKit

/// The resolved frame of a single key.
struct KeyFrame: Equatable {
    let action: KeyAction
    /// Visible bounds of the key — used by the renderer.
    let rect: CGRect          // Keyboard-local coordinates (origin at top-left of keys area)
    /// Touch-test bounds — extends to include adjacent half-gaps for middle keys, and
    /// claims the full leading/trailing padding (to the keyboard edge) for row-edge keys.
    /// Native iOS uses an enlarged hit zone like this so edge letters (A, L, Q, P, …) can
    /// be tapped near the keyboard edge without missing. `hitRect ⊇ rect` always.
    let hitRect: CGRect
    let rowIndex: Int
    let columnIndex: Int
    let isCharacterKey: Bool
}

/// Resolves a `KeyboardLayout` to an array of `KeyFrame`s.
enum KeyboardLayoutResolver {

    /// Compute frames for every key in the layout.
    /// - Parameters:
    ///   - layout: The page layout (4 rows of items).
    ///   - dims: Measurement source (key heights, gaps, edges).
    ///   - keysAreaSize: The size of the keys area only (above toolbar).
    /// - Returns: An array of `KeyFrame` in row-major order.
    static func resolve(
        layout: KeyboardLayout,
        dims: KeyboardDimensions,
        keysAreaSize: CGSize
    ) -> [KeyFrame] {
        var frames: [KeyFrame] = []
        frames.reserveCapacity(layout.rows.reduce(0) { $0 + $1.items.count })

        let rowCount = max(layout.rows.count, 1)
        // Available height for keys (excluding top/bottom edges)
        let usableHeight = keysAreaSize.height - dims.topEdge - dims.bottomEdge
        let rowGapTotal = dims.rowGap * CGFloat(rowCount - 1)
        let keyHeight = max((usableHeight - rowGapTotal) / CGFloat(rowCount), 1)

        let usableKeyboardWidth = keysAreaSize.width - dims.sideEdge * 2

        let rowCountForVerticalSlop = layout.rows.count
        for (rowIndex, row) in layout.rows.enumerated() {
            // Per-row width budget accounts for leading/trailing insets (rows 1 and 2 use
            // these so their letters stay the same width as row 0 instead of stretching).
            let usableRowWidth = max(usableKeyboardWidth - row.leadingInset - row.trailingInset, 0)
            let widths = computeWidths(for: row.items, usableRowWidth: usableRowWidth, keyGap: dims.keyGap)

            var x = dims.sideEdge + row.leadingInset
            let y = dims.topEdge + CGFloat(rowIndex) * (keyHeight + dims.rowGap)

            // Vertical slop for this row — half the row gap above and below, clamped at
            // the keys-area top and bottom edges so we don't claim toolbar pixels.
            let halfRowGap = dims.rowGap / 2
            let topSlop = rowIndex == 0 ? min(dims.topEdge, halfRowGap) : halfRowGap
            let bottomSlop = rowIndex == rowCountForVerticalSlop - 1 ? min(dims.bottomEdge, halfRowGap) : halfRowGap

            let itemCount = row.items.count
            for (columnIndex, item) in row.items.enumerated() {
                let w = widths[columnIndex]
                let rect = CGRect(x: x, y: y, width: w, height: keyHeight)
                let isChar: Bool = {
                    if case .character = item.action { return true }
                    return false
                }()

                // Hit-rect horizontal slop:
                // - Leftmost key: claim everything from keyboard-left (x = 0) to its right
                //   neighbor's midpoint (or keyboardWidth if it's also the last in row).
                // - Rightmost key: claim from its left neighbor's midpoint to keyboardWidth.
                // - Middle keys: claim half of each adjacent gap.
                let isFirst = columnIndex == 0
                let isLast = columnIndex == itemCount - 1
                let leftSlop = isFirst ? rect.minX : dims.keyGap / 2
                let rightSlop = isLast ? max(keysAreaSize.width - rect.maxX, 0) : dims.keyGap / 2

                let hitRect = CGRect(
                    x: rect.minX - leftSlop,
                    y: rect.minY - topSlop,
                    width: rect.width + leftSlop + rightSlop,
                    height: rect.height + topSlop + bottomSlop
                )

                frames.append(KeyFrame(
                    action: item.action,
                    rect: rect,
                    hitRect: hitRect,
                    rowIndex: rowIndex,
                    columnIndex: columnIndex,
                    isCharacterKey: isChar
                ))
                x += w + dims.keyGap
            }
        }

        return frames
    }

    /// Two-pass width algorithm:
    /// 1) Sum `.points` and `.percentage` items.
    /// 2) Reserve a baseline minimum for `.input` and `.available` items.
    /// 3) Equally distribute the remainder across `.input` items, then `.available`.
    private static func computeWidths(
        for row: [KeyboardLayoutItem],
        usableRowWidth: CGFloat,
        keyGap: CGFloat
    ) -> [CGFloat] {
        guard !row.isEmpty else { return [] }

        let gapsTotal = keyGap * CGFloat(row.count - 1)
        let widthForKeys = max(usableRowWidth - gapsTotal, 0)

        var inputCount = 0
        var availableCount = 0
        var fixedTotal: CGFloat = 0

        for item in row {
            switch item.width {
            case .input: inputCount += 1
            case .available: availableCount += 1
            case .points(let p): fixedTotal += max(p, 0)
            case .percentage(let pct): fixedTotal += widthForKeys * max(pct, 0)
            }
        }

        let remaining = max(widthForKeys - fixedTotal, 0)

        // If both .input and .available exist, .input gets a fixed slot equal to the
        // smallest sensible character-key width and .available consumes the rest.
        // In practice, rows have one or the other — keep the math simple.
        let inputShare: CGFloat
        let availableShare: CGFloat

        if inputCount > 0 && availableCount > 0 {
            // Give .input items a baseline character-key width (~36pt) so layouts with
            // both kinds (rare) don't starve the input keys.
            let baselineInput: CGFloat = max(remaining * 0.6 / CGFloat(inputCount), 0)
            inputShare = baselineInput
            let usedByInputs = baselineInput * CGFloat(inputCount)
            availableShare = max((remaining - usedByInputs) / CGFloat(availableCount), 0)
        } else if inputCount > 0 {
            inputShare = remaining / CGFloat(inputCount)
            availableShare = 0
        } else if availableCount > 0 {
            inputShare = 0
            availableShare = remaining / CGFloat(availableCount)
        } else {
            inputShare = 0
            availableShare = 0
        }

        return row.map { item in
            switch item.width {
            case .input: return inputShare
            case .available: return availableShare
            case .points(let p): return max(p, 0)
            case .percentage(let pct): return widthForKeys * max(pct, 0)
            }
        }
    }
}
