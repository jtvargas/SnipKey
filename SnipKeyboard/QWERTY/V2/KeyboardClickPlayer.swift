//
//  KeyboardClickPlayer.swift
//  SnipKeyboard
//
//  Audible key click for the V2 keyboard — the one feedback channel a third-party keyboard
//  can give at touch-DOWN without Full Access. Mirrors the system keyboard: one generic
//  click per key press (every key, including shift/delete/123) and one per rapid-delete
//  repeat; honours Settings → Sounds & Haptics → Keyboard Clicks automatically because
//  `UIDevice.playInputClick()` is gated by that preference.
//
//  UIKit only routes the click when a view in the input-view hierarchy that conforms to
//  `UIInputViewAudioFeedback` reports `enableInputClicksWhenVisible == true`. The
//  `UIInputViewController`'s root `view` is a `UIInputView`, so the retroactive conformance
//  below covers every keyboard view we host. Haptics are deliberately NOT part of this type.
//

import UIKit

/// Plays the native keyboard click. Stateless — a namespace, not an object, so the touch path
/// pays one static call and no retain/release.
enum KeyboardClickPlayer {

    /// Play one key click. Safe to call at any rate; UIKit coalesces overlapping clicks.
    @inline(__always)
    static func play() {
        UIDevice.current.playInputClick()
    }
}

extension UIInputView: @retroactive UIInputViewAudioFeedback {
    public var enableInputClicksWhenVisible: Bool { true }
}
