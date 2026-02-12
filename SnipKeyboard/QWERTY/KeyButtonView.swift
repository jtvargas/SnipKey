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
    let onTouchDown: () -> Void
    let onTouchUp: () -> Void
    let cornerRadius: CGFloat
    let highlightColor: UIColor

    func makeUIView(context: Context) -> UIControl {
        let control = UIControl()
        control.addTarget(context.coordinator, action: #selector(Coordinator.touchDown(_:)), for: .touchDown)
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
        let onTouchDown: () -> Void
        let onTouchUp: () -> Void
        let highlightColor: UIColor

        init(onTouchDown: @escaping () -> Void, onTouchUp: @escaping () -> Void, highlightColor: UIColor) {
            self.onTouchDown = onTouchDown
            self.onTouchUp = onTouchUp
            self.highlightColor = highlightColor
        }

        @objc func touchDown(_ sender: UIControl) {
            sender.backgroundColor = highlightColor
            onTouchDown()
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
                // Fast path: UIKit touch handler with popup + highlight for character keys
                keyVisual
                    .frame(width: totalWidth, height: dimensions.keyHeight)
                    .contentShape(Rectangle())
                    .overlay(
                        KeyTouchArea(
                            onTouchDown: {
                                handleTap()
                                // Show popup with the displayed character
                                let displayChar = state.shiftState == .disabled ? char.lowercased() : char.uppercased()
                                let frame = dimensions.keyFrame(
                                    rowIndex: rowIndex,
                                    columnIndex: columnIndex,
                                    keyWidth: keyWidth,
                                    rowActions: rowActions
                                )
                                actions.showPopup(displayChar, frame, state.appearanceMode == .dark)
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
                                onTouchDown: {
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

    // MARK: - Tap Handling

    private func handleTap() {
        switch action {
        case .character(let char):
            let textToInsert = state.shiftState == .disabled ? char.lowercased() : char.uppercased()
            actions.insertText(textToInsert)
            state.inputTracking.recordAction(.character)
            state.handleShiftAfterCharacter()
            actions.evaluateSlashCommand()
            actions.evaluatePredictiveText()

        case .shift:
            state.toggleShift()

        case .backspace:
            actions.deleteBackward()
            state.inputTracking.recordAction(.other)
            actions.evaluateSlashCommand()
            actions.evaluatePredictiveText()

        case .space:
            handleSpaceAction()

        case .returnKey:
            actions.insertText("\n")
            state.inputTracking.recordAction(.other)
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
