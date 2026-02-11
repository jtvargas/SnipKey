//
//  KeyboardActions.swift
//  SnipKeyboard
//
//  Created by Jonathan Taveras Vargas on 2/10/26.
//

import SwiftUI

/// Wraps textDocumentProxy operations as closures, passed from
/// KeyboardViewController (UIKit) into the SwiftUI environment.
/// This avoids NotificationCenter overhead for high-frequency key presses.
struct KeyboardActions {
    /// Insert text into the active text field
    let insertText: (String) -> Void

    /// Delete one character backward
    let deleteBackward: () -> Void

    /// Switch to the next keyboard (globe key)
    let advanceToNextInputMode: () -> Void

    /// Read the text before the cursor (for auto-period detection)
    let documentContextBeforeInput: () -> String?

    /// Screen width from UIKit — avoids GeometryReader in the keyboard view
    let screenWidth: CGFloat

    /// Show character pop-up balloon above a key.
    /// Parameters: character (already cased), key's visual frame in keyboard coordinates, isDark
    let showPopup: (_ character: String, _ keyFrame: CGRect, _ isDark: Bool) -> Void

    /// Hide the character pop-up balloon
    let hidePopup: () -> Void

    /// Open the main SnipKey app (for settings access from the keyboard)
    let openApp: () -> Void

    /// No-op instance for previews and default values
    static let noop = KeyboardActions(
        insertText: { _ in },
        deleteBackward: {},
        advanceToNextInputMode: {},
        documentContextBeforeInput: { nil },
        screenWidth: 393,
        showPopup: { _, _, _ in },
        hidePopup: {},
        openApp: {}
    )
}

// MARK: - SwiftUI Environment Key

private struct KeyboardActionsKey: EnvironmentKey {
    static let defaultValue = KeyboardActions.noop
}

extension EnvironmentValues {
    var keyboardActions: KeyboardActions {
        get { self[KeyboardActionsKey.self] }
        set { self[KeyboardActionsKey.self] = newValue }
    }
}
