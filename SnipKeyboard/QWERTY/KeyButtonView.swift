//
//  KeyButtonView.swift
//  SnipKeyboard
//
//  Created by Jonathan Taveras Vargas on 2/10/26.
//

import SwiftUI
import UIKit

// MARK: - Deletion Counter (non-observable, avoids @State re-renders)

/// Reference-type counter for rapid deletion acceleration.
/// Using a class instead of @State Int avoids scheduling SwiftUI body
/// re-evaluations 10x/second during backspace long-press.
final class DeletionCounter {
    var count: Int = 0
}

// MARK: - Haptic Feedback Manager

/// Lightweight haptic feedback for key presses.
/// Uses UIImpactFeedbackGenerator which works without Full Access.
/// Re-prepares after each call for consistent low-latency response.
enum KeyboardHaptics {
    private static let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private static let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)

    static func prepare() {
        lightGenerator.prepare()
        mediumGenerator.prepare()
    }

    static func keyPress() {
        lightGenerator.impactOccurred()
        lightGenerator.prepare() // Re-arm for next press
    }

    static func specialKey() {
        mediumGenerator.impactOccurred()
        mediumGenerator.prepare() // Re-arm for next press
    }
}

// MARK: - UIKit Touch Handler

/// A lightweight UIKit-based touch target with full touch lifecycle.
/// Fires `onTouchDown` immediately on finger contact (for character insertion + popup),
/// and `onTouchUp` on finger lift (for popup dismiss + highlight removal).
///
/// Also applies a subtle background highlight while the finger is down,
/// entirely via CALayer — zero SwiftUI state changes.
struct KeyTouchArea: UIViewRepresentable {
    /// Called on touch down with:
    /// - touchX: X position relative to this control's bounds (for probabilistic resolution)
    /// - keyFrame: the control's actual frame in keyboard root coordinates (for popup positioning)
    let onTouchDown: (_ touchX: CGFloat, _ keyFrame: CGRect) -> Void
    let onTouchUp: () -> Void
    let cornerRadius: CGFloat
    let highlightColor: UIColor

    func makeUIView(context: Context) -> UIControl {
        let control = UIControl()
        control.addTarget(context.coordinator, action: #selector(Coordinator.touchDown(_:event:)), for: .touchDown)
        control.addTarget(context.coordinator, action: #selector(Coordinator.touchUp(_:)), for: .touchUpInside)
        control.addTarget(context.coordinator, action: #selector(Coordinator.touchUp(_:)), for: .touchUpOutside)
        control.addTarget(context.coordinator, action: #selector(Coordinator.touchUp(_:)), for: .touchCancel)
        control.backgroundColor = .clear
        control.layer.cornerRadius = cornerRadius
        control.clipsToBounds = true
        return control
    }

    func updateUIView(_ uiView: UIControl, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onTouchDown: onTouchDown, onTouchUp: onTouchUp, highlightColor: highlightColor)
    }

    final class Coordinator: NSObject {
        let onTouchDown: (_ touchX: CGFloat, _ keyFrame: CGRect) -> Void
        let onTouchUp: () -> Void
        let highlightColor: UIColor

        init(onTouchDown: @escaping (_ touchX: CGFloat, _ keyFrame: CGRect) -> Void, onTouchUp: @escaping () -> Void, highlightColor: UIColor) {
            self.onTouchDown = onTouchDown
            self.onTouchUp = onTouchUp
            self.highlightColor = highlightColor
        }

        @objc func touchDown(_ sender: UIControl, event: UIEvent) {
            sender.backgroundColor = highlightColor
            let touchX = event.allTouches?.first?.location(in: sender).x ?? sender.bounds.midX
            // Actual frame in keyboard root coordinates — single affine transform, ~0ns.
            // In keyboard extensions, convert(to: nil) yields window coords which match
            // the KeyboardViewController.view coordinate space (popup's superview).
            let keyFrame = sender.convert(sender.bounds, to: nil)
            onTouchDown(touchX, keyFrame)
        }

        @objc func touchUp(_ sender: UIControl) {
            sender.backgroundColor = .clear
            onTouchUp()
        }
    }
}

// MARK: - Character Key Label (isolated shift observation)

/// Lightweight sub-view that observes shift state for character casing.
/// By isolating the `state.shiftState` read here, shift changes only re-render
/// the text label — NOT the entire key (background, frame, shadow, touch handler).
struct CharacterKeyLabel: View {
    let char: String
    let fontSize: CGFloat

    @Environment(QWERTYKeyboardState.self) private var state

    var body: some View {
        let display = state.shiftState == .disabled ? char.lowercased() : char.uppercased()
        Text(display)
            .font(.system(size: fontSize, weight: .regular))
            .foregroundStyle(Color(.label))
    }
}

// MARK: - Key Button View

/// A single keyboard key.
///
/// Layout strategy for hit slop:
/// - `keyWidth` is the visual width of the rounded-rect background.
/// - `leadingPad` / `trailingPad` extend the tappable frame into the gap
///   between keys (or to the screen edge for first/last keys).
/// - The visual background is drawn only on the inner `keyWidth x keyHeight` area.
/// - Character keys use a UIKit `UIControl` for direct touch handling (no SwiftUI delay).
/// - Special keys (shift, backspace, etc.) use SwiftUI Button since they need gesture support.
struct KeyButtonView: View {
    let action: KeyAction
    let dimensions: KeyboardDimensions
    let keyWidth: CGFloat
    let leadingPad: CGFloat
    let trailingPad: CGFloat
    let rowIndex: Int
    let columnIndex: Int
    let rowActions: [KeyAction]

    // MARK: - Probabilistic Touch Data (letters page character keys only)
    // These are nil on numbers/symbols pages. Precomputed by KeyRowView once per layout,
    // NOT per keystroke. Zero-cost when nil (fast path).

    /// (centerX, width) rects for each character key in this row, in row coordinate space.
    var rowKeyRects: [(centerX: CGFloat, width: CGFloat)]?

    /// Character strings in row order (e.g., ["Q","W","E",...]).
    var rowCharacters: [String]?

    /// This key's index within the character keys (not the full row actions).
    var characterIndex: Int?

    /// X offset of this key's tappable left edge in the row's coordinate space.
    var keyOffsetInRow: CGFloat = 0

    @Environment(\.keyboardActions) private var actions
    @Environment(QWERTYKeyboardState.self) private var state

    // Long-press state (delete + snippet toggle globe)
    @State private var isLongPressing = false
    @State private var deleteTimer: Timer?
    // NOTE: deletionCount is NOT @State — it's only used inside the Timer closure
    // and stopRapidDeletion(). Making it @State would schedule unnecessary SwiftUI
    // body re-evaluations 10x/second during long-press delete.
    @State private var deletionCounter = DeletionCounter()

    /// Total tappable width including padding into gaps
    private var totalWidth: CGFloat {
        leadingPad + keyWidth + trailingPad
    }

    var body: some View {
        // Visual key background with label
        let keyVisual = keyLabel
            .frame(width: keyWidth, height: dimensions.keyHeight)
            .background(backgroundStyle)
            .clipShape(RoundedRectangle(cornerRadius: dimensions.cornerRadius))
            .shadow(color: keyShadowColor, radius: 0, x: 0, y: keyShadowY)

        // Choose touch handler based on key type
        Group {
            switch action {
            case .character(let char):
                // UIKit touch handler with probabilistic resolution + popup + highlight.
                // On touch-down, localTouchX is used to resolve which character key was
                // actually intended (may redirect to a neighbor based on bigram probabilities).
                // When rowKeyRects is nil (numbers/symbols pages), falls through to own char.
                keyVisual
                    .frame(width: totalWidth, height: dimensions.keyHeight)
                    .contentShape(Rectangle())
                    .overlay(
                        KeyTouchArea(
                            onTouchDown: { localTouchX, keyFrame in
                                let resolved = resolveCharacter(localTouchX: localTouchX, ownChar: char)
                                // Capture display char BEFORE handleCharacterTap changes shift state
                                let displayChar = state.shiftState == .disabled ? resolved.lowercased() : resolved.uppercased()
                                handleCharacterTap(resolved)
                                // Popup at actual UIKit-computed position (not duplicated arithmetic).
                                // keyFrame is the full tappable area; visual key is inset by leadingPad.
                                let visualKeyFrame = CGRect(
                                    x: keyFrame.minX + leadingPad,
                                    y: keyFrame.minY,
                                    width: keyWidth,
                                    height: dimensions.keyHeight
                                )
                                actions.showPopup(displayChar, visualKeyFrame, state.appearanceMode == .dark)
                            },
                            onTouchUp: {
                                actions.hidePopup()
                            },
                            cornerRadius: dimensions.cornerRadius,
                            highlightColor: UIColor.label.withAlphaComponent(0.08)
                        )
                    )

            case .backspace:
                // Needs long-press for rapid deletion
                Button(action: handleTap) { keyVisual }
                    .buttonStyle(.plain)
                    .frame(width: totalWidth, height: dimensions.keyHeight)
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.4)
                            .onEnded { _ in
                                isLongPressing = true
                                deletionCounter.count = 0
                                startRapidDeletion()
                            }
                    )
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { _ in
                                if isLongPressing { stopRapidDeletion() }
                            }
                    )

            case .snippetToggle:
                // Tap = snippets, long-press = switch keyboard (globe)
                Button(action: handleTap) { keyVisual }
                    .buttonStyle(.plain)
                    .frame(width: totalWidth, height: dimensions.keyHeight)
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.5)
                            .onEnded { _ in
                                actions.advanceToNextInputMode()
                            }
                    )

            default:
                // Standard keys: shift, space, return, modeChange
                // Use UIKit touch for space (high frequency), Button for the rest
                if action == .space {
                    keyVisual
                        .frame(width: totalWidth, height: dimensions.keyHeight)
                        .contentShape(Rectangle())
                        .overlay(
                            KeyTouchArea(
                                onTouchDown: { _, _ in
                                    handleTap()
                                    actions.hidePopup() // Dismiss any active popup from previous key
                                },
                                onTouchUp: {},
                                cornerRadius: dimensions.cornerRadius,
                                highlightColor: UIColor.label.withAlphaComponent(0.06)
                            )
                        )
                } else {
                    Button(action: handleTap) { keyVisual }
                        .buttonStyle(.plain)
                        .frame(width: totalWidth, height: dimensions.keyHeight)
                        .contentShape(Rectangle())
                }
            }
        }
    }

    // MARK: - Key Label

    @ViewBuilder
    private var keyLabel: some View {
        switch action {
        case .character(let char):
            CharacterKeyLabel(char: char, fontSize: characterFontSize)

        case .shift:
            shiftIcon

        case .backspace:
            Image(systemName: "delete.backward")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(keyForegroundColor)

        case .space:
            Text("space")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(keyForegroundColor)

        case .returnKey:
            Text(state.returnKeyLabel)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(returnForegroundColor)

        case .modeChange(let page):
            Text(modeLabelText(for: page))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(keyForegroundColor)

        case .snippetToggle:
            Image(systemName: "text.badge.star")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(keyForegroundColor)
        }
    }

    @ViewBuilder
    private var shiftIcon: some View {
        let iconName: String = switch state.shiftState {
        case .disabled: "shift"
        case .enabled:  "shift.fill"
        case .locked:   "capslock.fill"
        }

        Image(systemName: iconName)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(shiftForegroundColor)
    }

    private func modeLabelText(for page: KeyboardPage) -> String {
        switch page {
        case .letters: return "ABC"
        case .numbers: return "123"
        case .symbols: return "#+="
        }
    }

    // MARK: - Styling

    private var isDarkMode: Bool {
        state.appearanceMode == .dark
    }

    private var backgroundStyle: Color {
        switch action {
        case .returnKey where state.returnKeyIsProminent:
            return .blue
        case .character, .space:
            return isDarkMode ? Color(white: 0.35).opacity(0.55) : Color(UIColor.systemGray6).opacity(0.6)
        default:
            return isDarkMode ? Color(white: 0.25).opacity(0.6) : Color(UIColor.systemGray4).opacity(0.7)
        }
    }

    /// Letter and space keys: no shadow. Special keys: subtle bottom edge.
    private var keyShadowColor: Color {
        switch action {
        case .character, .space:
            return .clear
        default:
            return .black.opacity(0.06)
        }
    }

    private var keyShadowY: CGFloat {
        switch action {
        case .character, .space:
            return 0
        default:
            return 0.5
        }
    }

    private var keyForegroundColor: Color {
        Color(.label)
    }

    private var returnForegroundColor: Color {
        state.returnKeyIsProminent ? .white : keyForegroundColor
    }

    private var shiftForegroundColor: Color {
        switch state.shiftState {
        case .disabled:
            return keyForegroundColor
        case .enabled:
            return isDarkMode ? .white : .white
        case .locked:
            return .white
        }
    }

    private var characterFontSize: CGFloat {
        if case .character(let char) = action, char.first?.isLetter == true {
            return 20
        }
        return 18
    }

    // MARK: - Probabilistic Touch Resolution

    /// Resolve which character the user intended, given the touch X position
    /// within this key's tappable area. On the letters page, uses bigram-weighted
    /// dynamic boundaries to potentially redirect to an adjacent key.
    /// On numbers/symbols pages (rowKeyRects == nil), returns ownChar immediately (~0ns).
    ///
    /// Performance: ~100ns when active (dictionary lookup + arithmetic). Zero allocations
    /// beyond a small [Float] weights array (10 elements, 40 bytes).
    private func resolveCharacter(localTouchX: CGFloat, ownChar: String) -> String {
        // Fast path: no probabilistic data → return own character
        guard let rects = rowKeyRects,
              let chars = rowCharacters,
              let _ = characterIndex else {
            return ownChar
        }

        // Convert local touch X (within this key's tappable area) to row-space X
        let rowX = localTouchX + keyOffsetInRow

        // Get weights from touch context (pre-computed when last character changed)
        let weights = state.inputTracking.touchContext.weightsForRow(chars)

        // Resolve using DynamicHitResolver — pure arithmetic, ~100ns
        let resolvedIndex = DynamicHitResolver.resolve(
            touchX: rowX,
            keyRects: rects,
            weights: weights,
            keyGap: dimensions.keyGap
        )

        guard resolvedIndex >= 0 && resolvedIndex < chars.count else { return ownChar }
        return chars[resolvedIndex]
    }

    /// Handle a character key tap with the resolved character (may differ from the
    /// visually tapped key due to probabilistic resolution).
    /// Inserts text, records context, updates shift, and triggers slash/predictive evaluation.
    private func handleCharacterTap(_ char: String) {
        let textToInsert = state.shiftState == .disabled ? char.lowercased() : char.uppercased()
        actions.insertText(textToInsert)
        state.inputTracking.recordAction(.character)
        state.inputTracking.touchContext.recordCharacter(Character(char))
        state.handleShiftAfterCharacter()
        actions.evaluateSlashCommand()
        actions.evaluatePredictiveText()
    }

    // MARK: - Tap Handling

    private func handleTap() {
        switch action {
        case .character(let char):
            // Character keys are handled by handleCharacterTap() via the
            // KeyTouchArea onTouchDown closure (with probabilistic resolution).
            // This path is only reached if a character key uses a SwiftUI Button
            // instead of KeyTouchArea (currently none do).
            handleCharacterTap(char)

        case .shift:
            state.toggleShift()

        case .backspace:
            actions.deleteBackward()
            state.inputTracking.recordAction(.other)
            state.inputTracking.touchContext.recordNonCharacter()
            actions.evaluateSlashCommand()
            actions.evaluatePredictiveText()

        case .space:
            handleSpaceAction()

        case .returnKey:
            actions.insertText("\n")
            state.inputTracking.recordAction(.other)
            state.inputTracking.touchContext.recordNonCharacter()
            actions.evaluateSlashCommand()
            actions.evaluatePredictiveText()

        case .modeChange(let page):
            state.currentPage = page
            state.inputTracking.recordAction(.other)

        case .snippetToggle:
            state.showingSnippets = true
        }
    }

    // MARK: - Space / Auto-Period

    private func handleSpaceAction() {
        // Check auto-return condition BEFORE recording the space action,
        // because recordAction overwrites lastAction.
        // Native iOS behavior: pressing space after a character in numbers/symbols
        // mode auto-switches back to the letters page.
        let shouldAutoReturn = state.currentPage != .letters
            && state.inputTracking.lastAction == .character

        if state.inputTracking.shouldInsertAutoPeriod() {
            actions.deleteBackward()
            actions.insertText(". ")
            state.inputTracking.resetAutoPeriodTracking()
        } else {
            actions.insertText(" ")
            state.inputTracking.recordAction(.space)
        }

        // Update probabilistic touch context — space starts a new word
        state.inputTracking.touchContext.recordNonCharacter()

        // Auto-return to letters after space following a character in numbers/symbols
        if shouldAutoReturn {
            state.currentPage = .letters
        }

        actions.evaluateSlashCommand()
        actions.evaluatePredictiveText()
    }

    // MARK: - Rapid Deletion

    private func startRapidDeletion() {
        deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            deletionCounter.count += 1
            let charsToDelete = min(deletionCounter.count, 10)
            for _ in 0..<charsToDelete {
                actions.deleteBackward()
            }
        }
    }

    private func stopRapidDeletion() {
        isLongPressing = false
        deletionCounter.count = 0
        deleteTimer?.invalidate()
        deleteTimer = nil
    }
}
