//
//  KeyboardActions.swift
//  SnipKeyboard
//
//  Created by Jonathan Taveras Vargas on 2/10/26.
//

import SwiftUI
import UIKit

/// Host text-field traits the keyboard reads to drive smart-punctuation, auto-cap, etc.
/// Snapshotted on demand from `textDocumentProxy` — these can change as the user moves
/// between text fields, so we read fresh each time.
struct HostInputTraits {
    let keyboardType: UIKeyboardType
    let autocapitalizationType: UITextAutocapitalizationType
    let smartQuotesEnabled: Bool
    let smartDashesEnabled: Bool

    /// Sensible defaults used by the `.noop` actions (previews / V1 fallback).
    static let defaults = HostInputTraits(
        keyboardType: .default,
        autocapitalizationType: .sentences,
        smartQuotesEnabled: true,
        smartDashesEnabled: true
    )

    /// True if smart-punctuation and auto-cap-I transforms should run for this field.
    /// URL and email fields opt out (lowercase "i" is common in usernames; curly quotes
    /// break literal URLs).
    var allowsSmartTransforms: Bool {
        switch keyboardType {
        case .URL, .emailAddress, .numberPad, .phonePad, .decimalPad, .asciiCapableNumberPad:
            return false
        default:
            return true
        }
    }
}

/// Wraps textDocumentProxy operations as closures, passed from
/// KeyboardViewController (UIKit) into the SwiftUI environment.
/// This avoids NotificationCenter overhead for high-frequency key presses.
struct KeyboardActions {
    /// Insert text into the active text field
    let insertText: (String) -> Void

    /// Insert a single committed character into the active text field.
    /// Identical to `insertText` but marks the host's synchronous `textDidChange`
    /// re-entrancy as "our own character insert" so the controller can skip the
    /// redundant auto-capitalization context read on the hot path (V2 only).
    let insertCharacter: (String) -> Void

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

    /// Schedule a generic local notification from the keyboard (🔔 quick button). The controller
    /// supplies `hasFullAccess` and the delay. See LOCAL_NOTIFICATIONS.md.
    let requestReminder: () -> Void

    /// Schedule a parsed `/remind … at <time>` reminder at an absolute fire date.
    /// `body` is the notification text, `fireDate` the resolved time. See ReminderParseEngine.
    let createReminder: (_ body: String, _ fireDate: Date) -> Void

    /// Start a parsed `/timer <duration>` countdown of `duration` seconds. `label` is the timer's
    /// display title. See TimerParseEngine / AlarmKitTimerService.
    let createTimer: (_ duration: TimeInterval, _ label: String) -> Void

    /// Evaluate the current text context for slash command patterns.
    /// Called after character insertion, deletion, and other key events.
    let evaluateSlashCommand: () -> Void

    /// Evaluate the current text context for predictive text suggestions.
    /// Called after character insertion, deletion, and other key events.
    let evaluatePredictiveText: () -> Void

    /// Coalesced post-commit side-effects for the V2 path. Instead of synchronously
    /// reading `documentContextBeforeInput` and running slash + predictive evaluation
    /// inside `touchesBegan` (which delays the next keypress on the serial main thread),
    /// this schedules a single once-per-runloop flush that reads the context ONCE and
    /// runs both. During a fast burst, many key-downs collapse into one context read
    /// per frame. The flush always reads fresh context, so it is never stale.
    let scheduleSideEffects: () -> Void

    /// Move the text caret by a signed character offset (positive = right).
    /// Used by V2's space-bar cursor drag.
    let adjustCaret: (Int) -> Void

    /// Snapshot of the host text field's input traits — keyboard type, autocap, smart
    /// quotes/dashes. Used by the commit pipeline to gate smart-punctuation and auto-cap
    /// transforms (URL/email fields skip them).
    let inputTraits: () -> HostInputTraits

    /// Localized language codes for the user's active input modes (e.g. ["EN", "ES"]).
    /// Rendered as a subtitle on the space bar when more than one mode is enabled.
    let activeInputLocaleCodes: () -> [String]

    /// Shared V2 callout view, pre-mounted on `KeyboardViewController.view`.
    /// Nil in the V1 path (V1 uses `KeyPopupView` instead) and in previews.
    /// The V2 gesture coordinator presents/dismisses it directly; rect conversion
    /// from coordinator coords to root-view coords happens via the coordinator
    /// converting through window coords (`convert(_:to:nil)` + `convert(_:from:nil)`).
    weak var v2CalloutView: KeyboardCalloutView?

    /// No-op instance for previews and default values
    static let noop = KeyboardActions(
        insertText: { _ in },
        insertCharacter: { _ in },
        deleteBackward: {},
        advanceToNextInputMode: {},
        documentContextBeforeInput: { nil },
        screenWidth: 393,
        showPopup: { _, _, _ in },
        hidePopup: {},
        openApp: {},
        requestReminder: {},
        createReminder: { _, _ in },
        createTimer: { _, _ in },
        evaluateSlashCommand: {},
        evaluatePredictiveText: {},
        scheduleSideEffects: {},
        adjustCaret: { _ in },
        inputTraits: { .defaults },
        activeInputLocaleCodes: { [] },
        v2CalloutView: nil
    )
}

// MARK: - SwiftUI Environment Key

extension EnvironmentValues {
    @Entry var keyboardActions: KeyboardActions = .noop
}
