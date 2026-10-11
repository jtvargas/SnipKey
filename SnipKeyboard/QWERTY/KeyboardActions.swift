//
//  KeyboardActions.swift
//  SnipKeyboard
//
//  Created by Jonathan Taveras Vargas on 2/10/26.
//

import SwiftUI
import UIKit

/// Host text-field traits the keyboard reads to drive smart-punctuation, auto-cap, layout
/// profile, return-key label and the space-bar locale subtitle. Each backing
/// `textDocumentProxy` / `UITextInputMode` read crosses to the host process, so the
/// controller snapshots them once per field (off the keystroke path) and the hot path
/// only ever reads this cached value.
struct HostInputTraits {
    let keyboardType: UIKeyboardType
    let keyboardAppearance: UIKeyboardAppearance
    let returnKeyType: UIReturnKeyType
    let autocapitalizationType: UITextAutocapitalizationType
    let autocorrectionType: UITextAutocorrectionType
    let spellCheckingType: UITextSpellCheckingType
    let smartQuotesEnabled: Bool
    let smartDashesEnabled: Bool
    let autoCapitalizationEnabled: Bool
    /// `UIInputViewController.needsInputModeSwitchKey` — whether the globe key is required.
    let needsInputModeSwitchKey: Bool
    /// Uppercased language codes of the enabled input modes ("EN", "ES"…) when more than one
    /// is enabled and the globe key is shown; empty otherwise. Rendered as the space-bar
    /// subtitle. Derived from `UITextInputMode.activeInputModes` at refresh time only.
    let localeCodes: [String]

    /// Sensible defaults used by the `.noop` actions (previews).
    static let defaults = HostInputTraits(
        keyboardType: .default,
        keyboardAppearance: .default,
        returnKeyType: .default,
        autocapitalizationType: .sentences,
        autocorrectionType: .default,
        spellCheckingType: .default,
        smartQuotesEnabled: true,
        smartDashesEnabled: true,
        autoCapitalizationEnabled: true,
        needsInputModeSwitchKey: true,
        localeCodes: []
    )

    /// True if smart-punctuation and auto-cap-I transforms should run for this field.
    /// URL and email fields opt out (lowercase "i" is common in usernames; curly quotes
    /// break literal URLs).
    var allowsSmartTransforms: Bool {
        switch keyboardType {
        case .asciiCapable, .URL, .emailAddress, .numberPad, .phonePad, .decimalPad, .asciiCapableNumberPad:
            return false
        default:
            return true
        }
    }

    var layoutProfile: KeyboardLayoutProfile {
        KeyboardLayoutProfile(keyboardType: keyboardType)
    }

}

/// Wraps textDocumentProxy operations as closures, passed from
/// KeyboardViewController (UIKit) into the SwiftUI environment.
/// This avoids NotificationCenter overhead for high-frequency key presses.
struct KeyboardActions {
    /// Insert text into the active text field. The controller advances the context mirror
    /// and flags the host's synchronous `textDidChange` re-entrancy as our own mutation.
    var insertText: (String) -> Void

    /// Delete one character backward
    var deleteBackward: () -> Void

    /// Switch to the next keyboard (globe key)
    let advanceToNextInputMode: () -> Void

    /// Synchronous cross-process read of the text before the caret. Toolbar-tap paths only
    /// (suggestion accept validation); the keystroke path reads the context mirror instead.
    let documentContextBeforeInput: () -> String?

    /// Screen width from UIKit — avoids GeometryReader in the keyboard view.
    /// Resolved lazily so rotation/Stage Manager size changes don't leave SwiftUI toolbar
    /// dimensions stuck on the width captured when `KeyboardActions` was initialized.
    let screenWidthProvider: () -> CGFloat
    var screenWidth: CGFloat { screenWidthProvider() }

    /// Open the main SnipKey app (for settings access from the keyboard)
    let openApp: () -> Void

    /// Authoritative Full Access check (UIInputViewController.hasFullAccess).
    let hasFullAccess: () -> Bool

    /// Schedule a generic local notification from the keyboard (🔔 quick button). The controller
    /// supplies `hasFullAccess` and the delay. See LOCAL_NOTIFICATIONS.md.
    let requestReminder: () -> Void

    /// Schedule a parsed `/remind … at <time>` reminder at an absolute fire date.
    /// `body` is the notification text, `fireDate` the resolved time. See ReminderParseEngine.
    let createReminder: (_ body: String, _ fireDate: Date) -> Void

    /// Start a parsed `/timer <duration>` countdown of `duration` seconds. `label` is the timer's
    /// display title. Schedules a local SnipKey notification when it ends. See TimerParseEngine.
    let createTimer: (_ duration: TimeInterval, _ label: String) -> Void

    /// Insert the clipboard's text into the active text field (toolbar paste button).
    /// The controller guards Full Access; the `.string` read here is the one pasteboard
    /// call that can trigger the iOS 16 "Allow Paste" prompt.
    let pasteFromClipboard: () -> Void

    /// Copy a file/image snippet's stored blob to the general pasteboard and return
    /// the true outcome. The externalStorage disk read runs off the main thread; the
    /// pasteboard write happens back on main. Toast messaging is the caller's job.
    let copySnippetFile: @MainActor (SnippetItem) async -> SnippetCopyResult

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

    /// Cached snapshot of the host text field's input traits — keyboard type, autocap,
    /// smart quotes/dashes, return key, locale codes. O(1); refreshed by the controller off
    /// the keystroke path. Used by the commit pipeline to gate smart-punctuation and
    /// auto-cap transforms (URL/email fields skip them).
    let inputTraits: () -> HostInputTraits

    /// `inputTraits().localeCodes` — O(1) cached array, safe to call every layout pass.
    /// Rendered as a subtitle on the space bar when more than one input mode is enabled.
    let activeInputLocaleCodes: () -> [String]

    /// Insert a command prefix through one selection-aware host transaction.
    let insertQuickCommand: (String) -> Void

    /// Validate the current host context before accepting a toolbar candidate.
    let acceptPredictiveCandidate: (PredictiveCandidate) -> Void

    /// Publish the runner-up words of a just-committed swipe to the toolbar so a tap can
    /// replace the committed word (+ its trailing space). `committed` is the word that is
    /// now in the document; `alternatives` are ranked best-first. Call even when there are
    /// no alternatives: publishing invalidates pending predictions and clears the old row.
    let showSwipeAlternatives: (_ committed: String, _ alternatives: [String]) -> Void

    /// Shared V2 callout view, pre-mounted on `KeyboardViewController.view`. Nil in previews.
    /// The V2 gesture coordinator presents/dismisses it directly; rect conversion
    /// from coordinator coords to root-view coords happens via the coordinator
    /// converting through window coords (`convert(_:to:nil)` + `convert(_:from:nil)`).
    weak var v2CalloutView: KeyboardCalloutView?

    /// No-op instance for previews and default values
    static let noop = KeyboardActions(
        insertText: { _ in },
        deleteBackward: {},
        advanceToNextInputMode: {},
        documentContextBeforeInput: { nil },
        screenWidthProvider: { 393 },
        openApp: {},
        hasFullAccess: { false },
        requestReminder: {},
        createReminder: { _, _ in },
        createTimer: { _, _ in },
        pasteFromClipboard: {},
        copySnippetFile: { _ in .noFullAccess },
        evaluateSlashCommand: {},
        evaluatePredictiveText: {},
        scheduleSideEffects: {},
        adjustCaret: { _ in },
        inputTraits: { .defaults },
        activeInputLocaleCodes: { [] },
        insertQuickCommand: { _ in },
        acceptPredictiveCandidate: { _ in },
        showSwipeAlternatives: { _, _ in },
        v2CalloutView: nil
    )
}

// MARK: - SwiftUI Environment Key

extension EnvironmentValues {
    @Entry var keyboardActions: KeyboardActions = .noop
}

// MARK: - Clipboard State

/// Observable clipboard availability — drives the toolbar paste button's visibility.
/// Owned by `KeyboardViewController`, refreshed on `viewWillAppear` and by a 1s poll
/// while the keyboard is visible (UIPasteboard.changedNotification only fires
/// in-process, so the host app's Copy action can only be caught by polling).
@MainActor
@Observable
final class ClipboardState {
    var hasContent: Bool = false

    /// Cached pasteboard generation — lets each poll tick skip the hasStrings/hasURLs
    /// reads (and any observable mutation) when nothing was copied since last tick.
    @ObservationIgnored private var lastChangeCount: Int = -1

    nonisolated init() {}

    /// Metadata-only refresh — changeCount + hasStrings/hasURLs never trigger
    /// the iOS 16 paste prompt. Only content reads (.string) do.
    func refresh() {
        let pb = UIPasteboard.general
        let count = pb.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        let newValue = pb.hasStrings || pb.hasURLs
        if hasContent != newValue { hasContent = newValue }
    }
}

extension EnvironmentValues {
    @Entry var clipboardState: ClipboardState = ClipboardState()
}
