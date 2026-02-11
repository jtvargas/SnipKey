//
//  QWERTYKeyboardState.swift
//  SnipKeyboard
//
//  Created by Jonathan Taveras Vargas on 2/10/26.
//

import Foundation
import SwiftUI

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

    /// Timestamp of the last shift tap, for detecting double-tap (caps lock)
    var lastShiftTapTime: Date? = nil

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

/// Only contains properties that SwiftUI views actually read.
/// Mutations here DO trigger view invalidation, but only when something
/// the user can see actually changes (shift icon, page layout, etc.).
@Observable
class QWERTYKeyboardState {
    // MARK: Mode Toggle
    /// When true, shows the snippet grid instead of the QWERTY keyboard
    var showingSnippets: Bool = false

    // MARK: QWERTY State
    /// Current keyboard page (letters, numbers, symbols)
    var currentPage: KeyboardPage = .letters

    /// Current shift state (views read this for key label casing and shift icon)
    var shiftState: ShiftState = .disabled

    // MARK: Text Input Context (updated by KeyboardViewController)
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

    /// Handle a single shift tap
    func toggleShift() {
        let now = Date()
        let isDoubleTap: Bool
        if let lastTap = inputTracking.lastShiftTapTime {
            isDoubleTap = now.timeIntervalSince(lastTap) < 0.3
        } else {
            isDoubleTap = false
        }
        inputTracking.lastShiftTapTime = now

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
