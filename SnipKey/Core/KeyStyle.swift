//
//  KeyStyle.swift
//  SnipKey
//
//  Single source of truth for the V2 keyboard key visual style, so the snippet
//  list can share the EXACT same look as the keys and the keyboard reads as one
//  design system.
//
//  These values MIRROR the V2 renderer (which stays the canonical owner — it is a
//  CALayer/UIColor hot path we deliberately don't refactor):
//    - Backgrounds:  KeyLayerRenderer.backgroundColor(for:isDark:)   (lines 495-506)
//    - Glyphs:       KeyLayerRenderer.glyphColor(for:isDark:)        (lines 521-535)
//    - Space subtitle secondary text:                                (lines 330-351)
//    - Shadow:       KeyLayerRenderer.applyNativeKeyShadow(to:isDark:) (lines 508-519)
//    - Corner radius: KeyboardDimensions.cornerRadius                (lines 48-54)
//  If those change, update here to keep the two surfaces in sync.
//
//  `isDark` is driven by `QWERTYKeyboardState.appearanceMode` (the same signal the
//  keys use), NOT SwiftUI's `colorScheme`, so the snippet list matches the keys even
//  when a text field forces a dark keyboard inside a light-mode app.
//

import SwiftUI
import UIKit

enum KeyStyle {

    // MARK: - Backgrounds

    /// Regular character/space key background.
    static func keyBackground(isDark: Bool) -> Color {
        isDark ? Color(white: 0.40, opacity: 0.55)
               : Color(white: 1.0, opacity: 0.94)
    }

    /// Special/function key background (shift, delete, return, mode, etc.).
    static func specialKeyBackground(isDark: Bool) -> Color {
        isDark ? Color(white: 0.40, opacity: 0.55)
               : Color(red: 0.674, green: 0.704, blue: 0.747, opacity: 0.88)
    }

    /// Background for the small type-icon "well" inside a snippet cell.
    /// In dark mode the regular and special key backgrounds are identical, so the
    /// well needs its own slightly lighter shade to stay visible against the cell.
    static func iconWell(isDark: Bool) -> Color {
        isDark ? Color(white: 0.55, opacity: 0.70)
               : Color(red: 0.674, green: 0.704, blue: 0.747, opacity: 0.88)
    }

    // MARK: - Elevated Surfaces

    /// Fully opaque elevated surface for cards/toasts floating over the keyboard.
    /// Mirrors ReminderToastModifier's pill (QWERTYKeyboardView.swift) — key
    /// backgrounds are translucent by design (they sit on the keyboard blur), so
    /// anything floating OVER content needs its own solid color or the content
    /// bleeds through.
    static func solidSurface(isDark: Bool) -> Color {
        isDark ? Color(red: 0.17, green: 0.17, blue: 0.19) : .white
    }

    /// Primary text on a `solidSurface`.
    static func solidSurfaceText(isDark: Bool) -> Color {
        isDark ? .white : Color(red: 0.10, green: 0.10, blue: 0.12)
    }

    /// Subtle solid button fill that reads on top of `solidSurface`.
    static func solidSurfaceButton(isDark: Bool) -> Color {
        isDark ? Color(white: 0.28) : Color(white: 0.93)
    }

    // MARK: - Glyphs / text

    /// Primary glyph color — explicit black/white like the keys.
    static func glyph(isDark: Bool) -> Color {
        isDark ? .white : .black
    }

    /// Muted secondary text (mirrors the space-bar subtitle color).
    static func secondaryGlyph(isDark: Bool) -> Color {
        isDark ? Color(white: 0.65) : Color(white: 0.45)
    }

    /// Dimmest text — hints and empty-state iconography.
    static func tertiaryGlyph(isDark: Bool) -> Color {
        isDark ? Color(white: 0.50) : Color(white: 0.62)
    }

    // MARK: - Geometry

    /// Dynamic key corner radius (mirrors KeyboardDimensions.cornerRadius).
    static var cornerRadius: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        if screenWidth < 350 { return 6 }
        if screenWidth < 400 { return 7 }
        return 8
    }

    // MARK: - Shadow

    /// The keys' subtle drop shadow — light mode only (no shadow in dark).
    static func keyShadow(isDark: Bool) -> (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
        isDark ? (.clear, 0, 0, 0)
               : (Color.black.opacity(0.24), 0, 0, 1)
    }
}

extension View {
    /// Applies the V2 keys' drop shadow (light mode only).
    func keyShadow(isDark: Bool) -> some View {
        let s = KeyStyle.keyShadow(isDark: isDark)
        return shadow(color: s.color, radius: s.radius, x: s.x, y: s.y)
    }
}
