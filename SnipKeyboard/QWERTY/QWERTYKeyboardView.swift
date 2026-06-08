//
//  QWERTYKeyboardView.swift
//  SnipKeyboard
//
//  Created by Jonathan Taveras Vargas on 2/10/26.
//

import SwiftUI
import SwiftData

// MARK: - Main QWERTY Keyboard View

struct QWERTYKeyboardView: View {
    @Environment(QWERTYKeyboardState.self) private var state
    @Environment(\.keyboardActions) private var actions

    var body: some View {
        let dimensions = KeyboardDimensions(screenWidth: actions.screenWidth)

        VStack(spacing: 0) {
            KeyboardToolbarView(dimensions: dimensions)

            VStack(spacing: dimensions.rowGap) {
                let rows = QWERTYKeyboardLayout.rows(for: state.currentPage, profile: state.layoutProfile)
                ForEach(Array(rows.enumerated()), id: \.element) { index, row in
                    KeyRowView(
                        actions: row,
                        rowIndex: index,
                        dimensions: dimensions
                    )
                }
            }
            .padding(.top, dimensions.topEdge)
            .padding(.bottom, dimensions.bottomEdge)
        }
        .frame(height: dimensions.totalHeight)
        .reminderToast()
        .timerToast()
    }
}

// MARK: - Keyboard Toolbar

/// Top toolbar with slash command suggestions (left) and settings button (right).
/// When no slash command is active, the suggestions area is empty (Spacer).
/// When a slash command IS active, horizontally scrollable snippet pills appear.
struct KeyboardToolbarView: View {
    let dimensions: KeyboardDimensions
    @Environment(\.keyboardActions) private var actions
    @Environment(\.slashCommandState) private var slashState
    @Environment(\.predictiveTextState) private var predictiveState
    @Environment(\.reminderSuggestionState) private var reminderState
    @Environment(\.timerSuggestionState) private var timerState
    @Environment(\.modelContext) private var modelContext

    /// All snippets from SwiftData — used for slash command matching.
    /// This @Query only triggers re-evaluation when snippet data changes in the DB,
    /// NOT on every keystroke. The matching runs in onChange(of: slashState.query).
    @Query(sort: \SnippetItem.creationDate, order: .reverse) private var allSnippets: [SnippetItem]

    let deviceBiometrics = DeviceBiometrics()

    @Environment(QWERTYKeyboardState.self) private var state

    var body: some View {
        HStack(spacing: 0) {
            if reminderState.isActive, let parsed = reminderState.parsed {
                // Top precedence: a parsed `/remind … at <time>` offers a Create reminder pill.
                CreateReminderPill(timeHint: parsed.pillTimeHint) {
                    handleCreateReminder()
                }
            } else if timerState.isActive, let parsedTimer = timerState.parsed {
                // A parsed `/timer <duration>` offers a Create timer pill (mutually exclusive with /remind).
                CreateTimerPill(durationHint: parsedTimer.pillDurationHint) {
                    handleCreateTimer()
                }
            } else if slashState.isActive {
                // Slash is active — show suggestions (button hidden)
                if !slashState.matchedSnippets.isEmpty {
                    SlashSuggestionsView(
                        snippets: slashState.matchedSnippets,
                        onSelect: { snippet in
                            handleSnippetSelection(snippet)
                        },
                        onDismiss: {
                            slashState.dismiss()
                        }
                    )
                } else {
                    // Active but no matches yet (still typing query)
                    Spacer()
                }
            } else {
                // Slash trigger button (top-left) + predictive suggestions
                SlashTriggerButton(isDarkMode: state.appearanceMode == .dark) {
                    actions.insertText("/")
                    actions.evaluateSlashCommand()
                }
                if predictiveState.isActive {
                    PredictiveSuggestionsView(
                        candidates: predictiveState.candidates,
                        onSelect: { candidate in
                            handlePredictiveSelection(candidate)
                        },
                        onDismissForSession: {
                            predictiveState.dismissForSession()
                        }
                    )
                } else {
                    Spacer()
                }
            }

//            // Reminder button — schedules a local notification (fires in 2 min; 10s DEBUG).
//            // Matches the suggestion pills' hit area + press feedback. See LOCAL_NOTIFICATIONS.md.
//            Button {
//                actions.requestReminder()
//            } label: {
//                Image(systemName: "bell.badge")
//                    .font(.custom("IBMPlexMono-Medium", size: 16))
//                    .foregroundStyle(Color(.secondaryLabel))
//                    .frame(minWidth: 44, maxHeight: .infinity)   // 44pt-wide, fills toolbar height
//                    .background(Color(white: 0).opacity(0.02))   // keeps the cell hittable
//                    .contentShape(Rectangle())                    // whole frame is the tap target
//                    .debugHitOverlay()
//            }
//            .buttonStyle(SuggestionPillButtonStyle())             // instant pressed highlight, like pills
//            .accessibilityLabel("Remind me in 2 minutes")
        }
        .frame(height: dimensions.toolbarHeight - dimensions.toolbarItemBottomGap)
        .frame(height: dimensions.toolbarHeight, alignment: .top)
        .padding(.horizontal, 12)
        // React to slash command activation and query changes
        .onChange(of: slashState.isActive) { _, isActive in
            if isActive {
                slashState.updateMatches(allSnippets: allSnippets)
            }
        }
        .onChange(of: slashState.query) { _, _ in
            if slashState.isActive {
                slashState.updateMatches(allSnippets: allSnippets)
            }
        }
    }

    // MARK: - Snippet Selection

    private func handleSnippetSelection(_ snippet: SnippetItem) {
        if snippet.isSecure {
            deviceBiometrics.authenticate(
                successHandler: {
                    insertSnippet(snippet)
                },
                unSuccessHandler: { _ in }
            )
        } else {
            insertSnippet(snippet)
        }
    }

    private func insertSnippet(_ snippet: SnippetItem) {
        actions.clearPendingPredictiveCorrection()
        // 1. Delete the slash command text (e.g., "/addr" = 5 chars including the slash)
        let charsToDelete = slashState.query.count + 1 // +1 for the "/" character
        for _ in 0..<charsToDelete {
            actions.deleteBackward()
        }

        // 2. Insert the snippet content
        if let content = snippet.content {
            actions.insertText(content)
        }

        // 3. Track usage
        snippet.lastTimeUsed = Date.now
        snippet.usedCount += 1
        try? modelContext.save()

        // 4. Dismiss slash command mode
        slashState.dismiss()
        // Snippet content is multi-word/arbitrary — never carries a smart space.
        state.inputTracking.pendingSmartSpace = false
    }

    // MARK: - Predictive Text Selection

    private func handlePredictiveSelection(_ candidate: PredictiveCandidate) {
        if candidate.role == .typed {
            predictiveState.dismiss()
            return
        }
        guard (actions.documentContextBeforeInput() ?? "").hasSuffix(predictiveState.partialWord) else {
            predictiveState.dismiss()
            actions.evaluatePredictiveText()
            return
        }

        // Delete the partial word characters
        let charsToDelete = candidate.replacementLength
        for _ in 0..<charsToDelete {
            actions.deleteBackward()
        }

        // Insert the full suggestion + trailing space
        actions.insertText(candidate.text + " ")
        // Mark the trailing space as a "smart space" so the next punctuation attaches to
        // the word (native iOS behavior). Consumed/cleared in the commit pipeline.
        state.inputTracking.pendingSmartSpace = true
        actions.clearPendingPredictiveCorrection()

        // Reset and re-evaluate
        predictiveState.dismiss()
        actions.evaluatePredictiveText()
    }

    // MARK: - Reminder Creation

    private func handleCreateReminder() {
        guard let parsed = reminderState.parsed else { return }
        actions.clearPendingPredictiveCorrection()

        // 1. Delete the typed `/remind … at <time>` command (reuses the snippet delete pattern).
        for _ in 0..<parsed.triggerText.count {
            actions.deleteBackward()
        }

        // 2. Schedule the reminder at the parsed absolute time (controller checks Full Access).
        actions.createReminder(parsed.body, parsed.fireDate)

        // 3. Confirmation toast + reset.
        reminderState.signalCreated(parsed.toastMessage)
        reminderState.clear()
        state.inputTracking.pendingSmartSpace = false
    }

    // MARK: - Timer Creation

    private func handleCreateTimer() {
        guard let parsed = timerState.parsed else { return }
        actions.clearPendingPredictiveCorrection()

        // 1. Delete the typed `/timer <duration>` command.
        for _ in 0..<parsed.triggerText.count {
            actions.deleteBackward()
        }

        // 2. Start the timer (controller checks Full Access, then schedules a local notification).
        actions.createTimer(parsed.duration, "Timer")

        // 3. Confirmation toast + reset.
        timerState.signalCreated(parsed.toastMessage)
        timerState.clear()
        state.inputTracking.pendingSmartSpace = false
    }
}

// MARK: - Slash Suggestions View

/// Horizontally scrollable row of snippet suggestion pills.
/// Mimics the native iOS autocomplete suggestion bar appearance.
// MARK: - Slash Trigger Button

/// Compact button that inserts `/` to start a slash command.
/// Styled to match the native iOS keyboard key appearance.
/// Hidden when slash commands are active (suggestions take its place).
struct SlashTriggerButton: View {
    let isDarkMode: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(.secondaryLabel))
                .frame(width: 34, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isDarkMode
                            ? Color(white: 0.35).opacity(0.55)
                            : Color(UIColor.systemGray6).opacity(0.6)
                        )
                        .shadow(color: .black.opacity(0.06), radius: 0, x: 0, y: 0.5)
                )
                .debugHitOverlay()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Reminder Confirmation Toast

/// Shows a confirmation banner ("Reminder created for today/tomorrow at 3:00 PM") whenever a
/// reminder is created from the keyboard. Reads the shared `ReminderSuggestionState` from the
/// environment so it works on both the V1 and V2 keyboard roots (the toolbar is shared by both).
/// Driven by `toastToken` so repeat creations re-fire the banner.
///
/// Hand-rolled rather than `AlertToast`: that library composites see-through over the keyboard's
/// translucent input view. This draws a fully-opaque pill we control completely.
private struct ReminderToastModifier: ViewModifier {
    @Environment(\.reminderSuggestionState) private var reminderState
    @Environment(QWERTYKeyboardState.self) private var keyboardState
    @State private var show = false
    @State private var message = ""
    /// Identifies the latest toast so a stale auto-dismiss can't hide a newer one.
    @State private var activeToken = 0

    private var isDark: Bool { keyboardState.appearanceMode == .dark }
    /// Opaque pill that adapts to the keyboard's light/dark appearance (like a native toast):
    /// a near-white surface on a light keyboard, a dark surface on a dark one.
    private var pillFill: Color { isDark ? Color(red: 0.17, green: 0.17, blue: 0.19) : .white }
    private var textColor: Color { isDark ? .white : Color(red: 0.10, green: 0.10, blue: 0.12) }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if show {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color(red: 0.15, green: 0.78, blue: 0.41)) // success green
                        Text(message)
                            .font(.custom("IBMPlexMono-Medium", size: 14))
                            .foregroundStyle(textColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        Capsule(style: .continuous)
                            .fill(pillFill)
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
                            )
                    )
                    .shadow(color: .black.opacity(isDark ? 0.45 : 0.18), radius: 10, y: 4)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: show)
            .onChange(of: reminderState.toastToken) { _, newToken in
                guard let m = reminderState.toastMessage else { return }
                message = m
                activeToken = newToken
                show = true
                // Auto-dismiss after a few seconds, unless a newer toast has since appeared.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                    if activeToken == newToken { show = false }
                }
            }
    }
}

extension View {
    /// Attach the reminder-created confirmation banner. Apply to a keyboard root view.
    func reminderToast() -> some View { modifier(ReminderToastModifier()) }
}

// MARK: - Timer Confirmation Toast

/// Confirmation banner ("Timer set for 1h 30m") shown when a timer is created from the keyboard.
/// Same opaque-pill treatment as the reminder toast; reads the shared `TimerSuggestionState`.
private struct TimerToastModifier: ViewModifier {
    @Environment(\.timerSuggestionState) private var timerState
    @Environment(QWERTYKeyboardState.self) private var keyboardState
    @State private var show = false
    @State private var message = ""
    @State private var activeToken = 0

    private var isDark: Bool { keyboardState.appearanceMode == .dark }
    private var pillFill: Color { isDark ? Color(red: 0.17, green: 0.17, blue: 0.19) : .white }
    private var textColor: Color { isDark ? .white : Color(red: 0.10, green: 0.10, blue: 0.12) }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if show {
                    HStack(spacing: 8) {
                        Image(systemName: "timer")
                            .foregroundStyle(Color(red: 0.15, green: 0.78, blue: 0.41))
                        Text(message)
                            .font(.custom("IBMPlexMono-Medium", size: 14))
                            .foregroundStyle(textColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        Capsule(style: .continuous)
                            .fill(pillFill)
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
                            )
                    )
                    .shadow(color: .black.opacity(isDark ? 0.45 : 0.18), radius: 10, y: 4)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: show)
            .onChange(of: timerState.toastToken) { _, newToken in
                guard let m = timerState.toastMessage else { return }
                message = m
                activeToken = newToken
                show = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                    if activeToken == newToken { show = false }
                }
            }
    }
}

extension View {
    /// Attach the timer-created confirmation banner. Apply to a keyboard root view.
    func timerToast() -> some View { modifier(TimerToastModifier()) }
}

// MARK: - Create Reminder Pill

/// Single suggestion pill shown when the user types a `/remind … at <time>` command.
/// Tapping it removes the command and schedules the reminder. Styled like the other pills.
struct CreateReminderPill: View {
    let timeHint: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "bell.badge")
                Text("Create reminder")
                Text("· \(timeHint)")
                    .foregroundStyle(Color(.secondaryLabel))
            }
            .font(.custom("IBMPlexMono-Medium", size: 16))
            .foregroundStyle(Color(.label))
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(white: 0).opacity(0.02))
            .contentShape(Rectangle())
            .debugHitOverlay()
        }
        .buttonStyle(SuggestionPillButtonStyle())
        .accessibilityLabel("Create reminder for \(timeHint)")
    }
}

// MARK: - Create Timer Pill

/// Single suggestion pill shown when the user types a `/timer <duration>` command.
/// Tapping it removes the command and starts the timer. Styled like the other pills.
struct CreateTimerPill: View {
    let durationHint: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "timer")
                Text("Create timer")
                Text("· \(durationHint)")
                    .foregroundStyle(Color(.secondaryLabel))
            }
            .font(.custom("IBMPlexMono-Medium", size: 16))
            .foregroundStyle(Color(.label))
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(white: 0).opacity(0.02))
            .contentShape(Rectangle())
            .debugHitOverlay()
        }
        .buttonStyle(SuggestionPillButtonStyle())
        .accessibilityLabel("Create timer for \(durationHint)")
    }
}

// MARK: - Predictive Text Suggestions View

/// Horizontally arranged row of up to 3 word completion/correction pills.
/// Mimics the native iOS QuickType suggestion bar appearance.
/// Native suggestion-bar press feedback: a rounded gray highlight fills the pill's cell
/// while it's pressed (no bounce/scale, no animation — appears/clears instantly with the
/// press so it feels immediate, matching the iOS predictive bar).
struct SuggestionPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(.systemFill))
                    .padding(.vertical, 5)
                    .padding(.horizontal, 2)
                    .opacity(configuration.isPressed ? 1 : 0)
            )
    }
}

// MARK: - Debug Hit-Area Overlay

extension View {
    /// DEBUG (off by default): outline this view's hit area with the same red border/fill
    /// used for the keys' touch cells, so the suggestion/snippet press regions can be
    /// inspected. Gated by Settings → "Show Hit-Test Overlay"
    /// (`AppGroupSettings.Key.debugHitOverlayEnabled`). Read at render time — reopen the
    /// keyboard to apply, matching the keys overlay. No layout/behavior change when off.
    @ViewBuilder
    func debugHitOverlay() -> some View {
        if KeyboardFeatureFlags.debugHitOverlayEnabled {
            self
                .background(Color(.systemRed).opacity(0.08))
                .overlay(Rectangle().stroke(Color(.systemRed).opacity(0.9), lineWidth: 1))
        } else {
            self
        }
    }
}

struct PredictiveSuggestionsView: View {
    let candidates: [PredictiveCandidate]
    let onSelect: (PredictiveCandidate) -> Void
    /// Called when the user long-presses the middle pill — matches native iOS, which
    /// long-presses the user's literal typed word to dismiss predictions for the session.
    var onDismissForSession: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                if index > 0 {
                    // Thin vertical divider between pills (native iOS style)
                    Rectangle()
                        .fill(Color(.separator).opacity(0.4))
                        .frame(width: 0.5)
                        .padding(.vertical, 8)
                }

                let isMiddle = (candidates.count >= 2 && index == candidates.count / 2)
                Button {
                    onSelect(candidate)
                } label: {
                    Text(label(for: candidate))
                        .font(.custom(fontName(for: candidate), size: 16))
                        .foregroundStyle(Color(.label))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(white: 0).opacity(0.02))   // keeps the cell hittable when overlay is off
                        .contentShape(Rectangle())
                        .debugHitOverlay()
                }
                .buttonStyle(SuggestionPillButtonStyle())
                .simultaneousGesture(
                    isMiddle
                        ? LongPressGesture(minimumDuration: 0.4)
                            .onEnded { _ in onDismissForSession?() }
                        : nil
                )
            }
        }
    }

    private func label(for candidate: PredictiveCandidate) -> String {
        candidate.role == .typed ? "\"\(candidate.text)\"" : candidate.text
    }

    private func fontName(for candidate: PredictiveCandidate) -> String {
        candidate.autoCommitEligible ? "IBMPlexMono-SemiBold" : "IBMPlexMono-Medium"
    }
}

// MARK: - Slash Suggestions View

struct SlashSuggestionsView: View {
    let snippets: [SnippetItem]
    let onSelect: (SnippetItem) -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(snippets.enumerated()), id: \.element.id) { index, snippet in
                        if index > 0 {
                            // Thin vertical divider between pills (native iOS style)
                            Rectangle()
                                .fill(Color(.separator).opacity(0.4))
                                .frame(width: 0.5)
                                .padding(.vertical, 8)
                        }

                        Button {
                            onSelect(snippet)
                        } label: {
                            HStack(spacing: 4) {
                                if snippet.isSecure {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(Color(.tertiaryLabel))
                                }
                                Text(snippet.title ?? "Untitled")
                                    .font(.custom("IBMPlexMono-Medium", size: 16))
                                    .foregroundStyle(Color(.label))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 14)
                            .frame(maxHeight: .infinity)
                            .background(Color(white: 0).opacity(0.02))   // keeps the cell hittable when overlay is off
                            .contentShape(Rectangle())
                            .debugHitOverlay()
                        }
                        .buttonStyle(SuggestionPillButtonStyle())
                    }
                }
            }

            // Dismiss button
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
                    .frame(width: 28, height: 28)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(Circle())
                    .debugHitOverlay()
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
        }
    }
}
