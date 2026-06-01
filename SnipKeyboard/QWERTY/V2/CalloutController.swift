//
//  CalloutController.swift
//  SnipKeyboard
//
//  Thin coordinator between the gesture stream and the shared KeyboardCalloutView.
//  Plain class — zero @Observable churn during the press lifecycle.
//

import UIKit
import QuartzCore

final class CalloutController {

    /// If a new input callout is presented within this window of the last dismiss, skip the
    /// spring "pop" and show it instantly — this is fast successive typing, where re-springing
    /// every key looks bouncy and unlike native iOS.
    private static let burstWindow: CFTimeInterval = 0.15

    /// Timestamp of the last `dismiss()` (mach time). Drives the burst-suppression above.
    private var lastDismissTime: CFTimeInterval = 0

    /// A key-up schedules the hide briefly in the future instead of hiding instantly, so a
    /// quickly-following key keeps the SAME bubble alive — it then glides to the new key
    /// (native feel) instead of popping a fresh component. Cancelled by the next
    /// `presentInput`/`beginActions`. Fires (fades) only when typing actually pauses.
    private var pendingDismiss: DispatchWorkItem?
    private static let dismissDelay: TimeInterval = 0.085

    private func cancelPendingDismiss() {
        pendingDismiss?.cancel()
        pendingDismiss = nil
    }

    /// Modes the controller can be in.
    enum Mode {
        case none
        case input(KeyFrame)
        case actions(base: KeyFrame, items: [String], selectedIndex: Int)
        case snippetsSwitch(base: KeyFrame)
    }

    weak var calloutView: KeyboardCalloutView?
    private(set) var mode: Mode = .none
    private(set) var isDark: Bool = false
    /// Bootstrap default; overwritten by `updateParentWidth(_:)` once the keyboard is laid out.
    private(set) var parentBoundsWidth: CGFloat = 393

    /// Converts a rect from the gesture coordinator's coordinate space to the callout
    /// view's superview coords (the root keyboard view). Set by the gesture coordinator
    /// after both views are in the same window. Identity (returns input unchanged) if
    /// the views don't share a window yet.
    var convertRect: (CGRect) -> CGRect = { $0 }

    /// Converts a point from the callout view's superview coords back to the gesture
    /// coordinator's coords. Used for accent-menu hit testing (the finger position comes
    /// in coordinator-local; the accent slots live in callout-view local).
    var convertPointToCalloutSpace: (CGPoint) -> CGPoint = { $0 }

    init(calloutView: KeyboardCalloutView) {
        self.calloutView = calloutView
    }

    func updateAppearance(isDark: Bool) {
        self.isDark = isDark
    }

    func updateParentWidth(_ width: CGFloat) {
        self.parentBoundsWidth = width
    }

    /// Show the input bubble above a character key.
    func presentInput(for key: KeyFrame, character: String, casedByShift: Bool) {
        guard let view = calloutView, case .character = key.action else {
            dismiss()
            return
        }
        let display = casedByShift ? character.uppercased() : character
        // A new key is coming — keep the current bubble alive so show() glides it.
        cancelPendingDismiss()
        // No-op if already showing this exact key in input mode
        if case .input(let prev) = mode, prev == key {
            return
        }
        mode = .input(key)
        let rectInCalloutSpace = convertRect(key.rect)
        // Spring only on the first key of a burst; instant pop if we just dismissed (fast typing).
        let animated = (CACurrentMediaTime() - lastDismissTime) > Self.burstWindow
        view.show(.input(character: display, keyFrame: rectInCalloutSpace), isDark: isDark, in: parentBoundsWidth, animated: animated)
    }

    /// Begin showing the long-press accent menu.
    func beginActions(for key: KeyFrame, items: [String]) {
        guard let view = calloutView, !items.isEmpty else { return }
        cancelPendingDismiss()
        // Default selection is the base character (index 0)
        mode = .actions(base: key, items: items, selectedIndex: 0)
        let rectInCalloutSpace = convertRect(key.rect)
        view.show(.actions(chars: items, keyFrame: rectInCalloutSpace, selectedIndex: 0), isDark: isDark, in: parentBoundsWidth)
    }

    /// Show the emoji key's long-press "switch to snippets" callout (a single rotated icon).
    func presentSnippetsSwitch(for key: KeyFrame) {
        guard let view = calloutView else { return }
        cancelPendingDismiss()
        mode = .snippetsSwitch(base: key)
        let rectInCalloutSpace = convertRect(key.rect)
        view.show(.snippetsSwitch(keyFrame: rectInCalloutSpace), isDark: isDark, in: parentBoundsWidth)
    }

    /// Update the highlighted slot during accent-menu drag.
    /// `fingerPoint` is in the gesture coordinator's local coordinate space.
    func updateAccentSelection(fingerPoint: CGPoint) {
        guard case .actions(let base, let items, let oldIdx) = mode else { return }
        guard let view = calloutView else { return }
        let pointInCalloutSpace = convertPointToCalloutSpace(fingerPoint)
        let newIdx = view.actionIndex(at: pointInCalloutSpace) ?? oldIdx
        if newIdx != oldIdx {
            mode = .actions(base: base, items: items, selectedIndex: newIdx)
            view.updateSelectedActionIndex(newIdx)
        }
    }

    /// Commit the current action-menu selection, or nil if not in action mode.
    func commitActions() -> String? {
        guard case .actions(_, let items, let idx) = mode else { return nil }
        guard idx >= 0 && idx < items.count else { return nil }
        return items[idx]
    }

    /// Hide the callout and reset state. Fades out for a deliberate single press; snaps
    /// during a fast-typing burst (another dismiss within the burst window) so the shared
    /// callout layer doesn't read as the next character dimming.
    func dismiss() {
        cancelPendingDismiss()
        let now = CACurrentMediaTime()
        let isBurst = (now - lastDismissTime) < Self.burstWindow
        lastDismissTime = now
        guard let view = calloutView else { mode = .none; return }
        view.hide(fade: !isBurst)
        mode = .none
    }

    /// Used on character key-up: defer the hide so a quickly-following key keeps the same
    /// bubble (which then glides). If typing pauses, the bubble fades after `dismissDelay`.
    func dismissInputDeferred() {
        cancelPendingDismiss()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingDismiss = nil
            self?.dismiss()
        }
        pendingDismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.dismissDelay, execute: work)
    }
}
