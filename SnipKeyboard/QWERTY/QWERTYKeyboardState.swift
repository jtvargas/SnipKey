//
//  QWERTYKeyboardState.swift
//  SnipKeyboard
//
//  Created by Jonathan Taveras Vargas on 2/10/26.
//

import Foundation
import SwiftUI
import UIKit

// MARK: - Enums

enum KeyboardPage: Hashable {
    case letters
    case numbers
    case symbols
}

enum ShiftState: Hashable {
    case disabled   // Lowercase
    case enabled    // Next character uppercase, then auto-disable
    case locked     // All uppercase until toggled off (caps lock)
}

enum KeyboardAppearanceMode: Equatable {
    case light
    case dark
}

enum KeyboardLayoutProfile: Hashable {
    case standard
    case asciiCapable
    /// Local emoji query editor: no surface switch, wide mode/Done keys.
    case emojiSearch
    case emailAddress
    case url
    case webSearch
    case twitter

    init(keyboardType: UIKeyboardType) {
        switch keyboardType {
        case .asciiCapable:
            self = .asciiCapable
        case .emailAddress:
            self = .emailAddress
        case .URL:
            self = .url
        case .webSearch:
            self = .webSearch
        case .twitter:
            self = .twitter
        default:
            self = .standard
        }
    }

    var fallbackReturnKey: (label: String, prominent: Bool)? {
        switch self {
        case .url:
            return ("Go", true)
        case .webSearch:
            return ("Search", true)
        case .emojiSearch:
            return ("Done", true)
        default:
            return nil
        }
    }
}

// MARK: - Input Tracking (NOT @Observable — no view re-renders)

/// Internal tracking state that no view reads directly.
/// Mutations here do NOT trigger SwiftUI view invalidation.
/// This is the key performance optimization — recordAction() and auto-period
/// checks cause zero re-renders since they only touch this object.
final class QWERTYInputTracking {
    enum KeyActionType {
        case space
        case character
        case other
    }

    /// Tracks the last two key actions to detect double-space for auto-period
    var lastAction: KeyActionType = .other
    var secondLastAction: KeyActionType = .other

    /// True when the last insertion was a predictive-suggestion completion, which added a
    /// trailing "smart space". If the next character is punctuation, that space is consumed
    /// so the punctuation attaches to the word ("word ." → "word."). Matches native iOS,
    /// which only eats a space IT inserted — never an arbitrary user-typed space. Cleared
    /// aggressively on any other commit, caret move, or snippet insertion.
    var pendingSmartSpace: Bool = false

    /// Touch-stream time of the last shift tap (`UITouch.timestamp` / `systemUptime`
    /// domain), for caps-lock double-tap detection. Nil until the first tap.
    var lastShiftTapTime: TimeInterval? = nil

    /// Probabilistic touch context — updated per keystroke, read by touch layers.
    /// Plain class (not @Observable) — mutations cause zero SwiftUI re-renders.
    let touchContext = ProbabilisticTouchContext()

    /// Keyboard-side mirror of the text before the caret, advanced in lockstep with every
    /// proxy mutation we make and re-synced from one real read off the keystroke path.
    /// Auto-cap, smart punctuation and word-tier backspace read it instead of the host.
    let contextMirror = TypingContextMirror()

    /// Record a key action for auto-period detection
    func recordAction(_ action: KeyActionType) {
        secondLastAction = lastAction
        lastAction = action
    }

    /// Check if double-space was detected (for auto-period: ". ")
    func shouldInsertAutoPeriod() -> Bool {
        return secondLastAction == .character && lastAction == .space
    }

    /// Reset auto-period tracking (after auto-period is inserted)
    func resetAutoPeriodTracking() {
        lastAction = .other
        secondLastAction = .other
    }
}

// MARK: - Keyboard Render State (@Observable — only view-affecting properties)

/// Exactly one keyboard surface owns touch routing at a time.
enum KeyboardSurface: Equatable {
    case typing
    case emoji
    case snippets
}

/// Only contains properties that SwiftUI views actually read.
/// Mutations here DO trigger view invalidation, but only when something
/// the user can see actually changes (shift icon, page layout, etc.).
@MainActor
@Observable
class QWERTYKeyboardState {
    // MARK: Surface
    /// Hydrated from the QWERTY setting when the shared data container is ready.
    var surface: KeyboardSurface = .snippets

    // MARK: QWERTY State
    /// Current keyboard page (letters, numbers, symbols)
    var currentPage: KeyboardPage = .letters

    /// Host-input layout profile derived from `textDocumentProxy.keyboardType`.
    var layoutProfile: KeyboardLayoutProfile = .standard

    /// Current shift state (views read this for key label casing and shift icon)
    var shiftState: ShiftState = .disabled

    // MARK: Text Input Context (updated by KeyboardViewController)
    /// True only when the controller has confirmed that the entire host field is empty.
    var isDocumentEmpty: Bool = false

    /// Display label for the return key (e.g., "return", "Send", "Go", "Search")
    var returnKeyLabel: String = "return"

    /// Whether the return key should use the prominent (blue) style
    var returnKeyIsProminent: Bool = false

    /// The host app's keyboard appearance preference
    var appearanceMode: KeyboardAppearanceMode = .light

    /// Whether the globe/input mode switch key should be shown
    var needsInputModeSwitchKey: Bool = true

    // MARK: Internal Tracking (non-observable, no re-renders)
    /// Internal tracking for auto-period, shift double-tap, etc.
    /// This is a plain class — mutations here don't trigger view updates.
    let inputTracking = QWERTYInputTracking()

    // MARK: - Shift Methods

    /// Two shift taps within this window engage caps lock. Compared on the touch-stream
    /// clock (`UITouch.timestamp`, seconds since boot) rather than wall-clock `Date()`, so a
    /// clock change or a stalled frame can neither fake nor miss a double-tap.
    static let capsLockDoubleTapWindow: TimeInterval = 0.3

    /// Handle a single shift tap at `timestamp` (the touch's own timestamp, or
    /// `ProcessInfo.processInfo.systemUptime` for non-touch callers).
    func toggleShift(at timestamp: TimeInterval) {
        let isDoubleTap: Bool
        if let lastTap = inputTracking.lastShiftTapTime {
            isDoubleTap = timestamp - lastTap < Self.capsLockDoubleTapWindow
        } else {
            isDoubleTap = false
        }
        inputTracking.lastShiftTapTime = timestamp

        if isDoubleTap {
            shiftState = .locked
        } else {
            switch shiftState {
            case .disabled:
                shiftState = .enabled
            case .enabled:
                shiftState = .disabled
            case .locked:
                shiftState = .disabled
            }
        }
    }

    /// Called after typing a character. If shift was .enabled (single shift),
    /// auto-disable it. Caps lock (.locked) stays on.
    func handleShiftAfterCharacter() {
        if shiftState == .enabled {
            shiftState = .disabled
        }
        // If shift was NOT enabled, this does nothing — no @Observable mutation,
        // no view re-render. This is intentional.
    }

    /// Apply auto-capitalization if the text context suggests it.
    /// Called from the controller after textDidChange.
    func applyAutoCapitalization(shouldCapitalize: Bool) {
        if shouldCapitalize && shiftState == .disabled {
            shiftState = .enabled
        }
    }
}
