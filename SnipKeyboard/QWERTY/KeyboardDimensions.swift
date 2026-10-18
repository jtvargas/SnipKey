//
//  KeyboardDimensions.swift
//  SnipKeyboard
//
//  Created by Jonathan Taveras Vargas on 2/10/26.
//

import Foundation

/// Computes all key measurements dynamically from the available screen width.
///
/// Single source of truth for keyboard geometry. The native reference values
/// (iPhone portrait, iOS 17+, measured) live in the `Native reference` section
/// below; everything else — row pitch, side-control widths, punctuation widths,
/// hit slop — is derived from them so no other file carries a `W * 0.xxx` ratio.
///
/// Reference table (W = screen width; all values in points):
///
///   | W   | keyHeight | rowGap | keyGap | sideEdge | letter | sideControl | sideControlGap | return | punctuation |
///   |-----|-----------|--------|--------|----------|--------|-------------|----------------|--------|-------------|
///   | 375 | 42        | 12     | 6      | 3        | 31.5   | 42          | 14.25          | 88     | 46.5        |
///   | 393 | 42        | 12     | 6      | 3        | 33.3   | 44          | 14.95          | 92     | 49.02       |
///   | 430 | 46        | 12     | 6      | 3        | 37     | 49          | 15.5           | 101    | 54.2        |
///
///   `sideControl` is shift / delete / 123 / ✦; `sideControlGap` is the space between
///   shift and Z (and M and delete); `punctuation` is `. , ? ! '` on the numbers/symbols page.
struct KeyboardDimensions: Equatable {
    let screenWidth: CGFloat

    // MARK: - Native reference (iPhone portrait, iOS 17+, measured)

    /// Native key height as a fraction of screen width — 42pt @393, 46pt @430.
    private static let keyHeightRatio: CGFloat = 0.107

    /// Native key height floor. 375pt-wide phones measure 42pt, the same as 393pt,
    /// so the ratio alone would under-size them (40pt); the floor pins both to native.
    private static let minimumKeyHeight: CGFloat = 42

    /// Native shift / delete / 123 / globe width relative to a letter key (42 / 31.5 @375).
    private static let sideControlToLetterRatio: CGFloat = 4.0 / 3.0

    /// Native return key width as a fraction of screen width (88pt @375).
    private static let returnKeyWidthRatio: CGFloat = 88.0 / 375.0

    /// Number of keys in the widest row (top row: Q W E R T Y U I O P).
    private static let maxKeysPerRow = 10

    /// Number of letters in the centered block of the third row (Z X C V B N M).
    /// The numbers/symbols punctuation block is sized to span exactly this block.
    private static let thirdRowLetterCount = 7

    /// Number of punctuation keys in the third row of the numbers/symbols page (`. , ? ! '`).
    private static let punctuationKeyCount = 5

    // MARK: - Core Measurements

    /// Height of a single key row. Native: 42pt on 375/393pt phones, scaling up on
    /// wider devices (46pt @430).
    var keyHeight: CGFloat {
        max(round(screenWidth * Self.keyHeightRatio), Self.minimumKeyHeight)
    }

    /// Horizontal gap between keys. Native: 6pt on every iPhone width.
    var keyGap: CGFloat { 6 }

    /// Vertical gap between rows. Native: 12pt (row pitch 54pt = 42 key + 12 gap).
    var rowGap: CGFloat { 12 }

    /// Left/right margin from screen edge to first/last key. Native: 3pt on every width.
    var sideEdge: CGFloat { 3 }

    /// Top padding above the first row. Native: 6pt.
    var topEdge: CGFloat { 6 }

    /// Bottom padding below the last row. Tuned per device class to sit above the
    /// home indicator safe area; intentionally not a native-table value.
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

    // MARK: - Hit Testing

    /// Fraction of the inter-row gap claimed by the LOWER key's hit rect; the upper key
    /// gets the remainder, so adjacent rows still tile exactly. Thumbs land low on the
    /// key they aim at — SwiftKey's theme gives the lower key 10 of the 12 gap points
    /// (0.83); 0.7 is a milder bias that keeps the upper key reachable on short rows.
    /// The first/last rows claim the full `topEdge` / `bottomEdge` instead of a gap share.
    var verticalHitBias: CGFloat { 0.7 }

    // MARK: - Key Widths (visual width of the key background, not including gap padding)

    /// Row width available to keys once the side edges are removed.
    var usableRowWidth: CGFloat {
        max(screenWidth - sideEdge * 2, 0)
    }

    /// Width of a standard letter key: the top row's 10 keys share the usable width
    /// after 9 gaps. 31.5 @375, 33.3 @393.
    var letterKeyWidth: CGFloat {
        let gaps = keyGap * CGFloat(Self.maxKeysPerRow - 1)
        return (usableRowWidth - gaps) / CGFloat(Self.maxKeysPerRow)
    }

    /// Width spanned by `count` letter keys and the gaps between them.
    func letterBlockWidth(count: Int) -> CGFloat {
        letterKeyWidth * CGFloat(count) + keyGap * CGFloat(max(count - 1, 0))
    }

    /// Width of shift, delete, 123 and the snippet toggle (native 123/globe):
    /// 4/3 of a letter key, rounded. 42 @375, 44 @393.
    var sideControlKeyWidth: CGFloat {
        round(letterKeyWidth * Self.sideControlToLetterRatio)
    }

    /// Gap between a third-row side control and the centered 7-key block (shift↔Z,
    /// M↔delete): whatever the row has left, split equally. 14.25 @375.
    /// The numbers/symbols punctuation block spans the same width as the letter
    /// block, so this gap is shared by every page's third row.
    var sideControlGap: CGFloat {
        let remaining = usableRowWidth - sideControlKeyWidth * 2 - letterBlockWidth(count: Self.thirdRowLetterCount)
        return max(remaining / 2, keyGap)
    }

    /// Width of each `. , ? ! '` key on the numbers/symbols page. The 5 keys plus
    /// their 4 gaps occupy exactly the span of the letters page's 7-key block, so
    /// mode/delete sit in the same place on every page. 46.5 @375.
    var punctuationKeyWidth: CGFloat {
        let gaps = keyGap * CGFloat(Self.punctuationKeyCount - 1)
        return (letterBlockWidth(count: Self.thirdRowLetterCount) - gaps) / CGFloat(Self.punctuationKeyCount)
    }

    /// Width of the return key. 88 @375, 92 @393.
    var returnKeyWidth: CGFloat {
        round(screenWidth * Self.returnKeyWidthRatio)
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
