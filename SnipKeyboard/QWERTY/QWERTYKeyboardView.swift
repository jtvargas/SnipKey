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
                let rows = QWERTYKeyboardLayout.rows(for: state.currentPage)
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
    @Environment(\.modelContext) private var modelContext

    /// All snippets from SwiftData — used for slash command matching.
    /// This @Query only triggers re-evaluation when snippet data changes in the DB,
    /// NOT on every keystroke. The matching runs in onChange(of: slashState.query).
    @Query(sort: \SnippetItem.creationDate, order: .reverse) private var allSnippets: [SnippetItem]

    let deviceBiometrics = DeviceBiometrics()

    @Environment(QWERTYKeyboardState.self) private var state

    var body: some View {
        HStack(spacing: 0) {
            if slashState.isActive {
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
                        suggestions: predictiveState.suggestions,
                        onSelect: { suggestion in
                            handlePredictiveSelection(suggestion)
                        },
                        onDismissForSession: {
                            predictiveState.dismissForSession()
                        }
                    )
                } else {
                    Spacer()
                }
            }

//            // Settings button — opens main SnipKey app
//            Button {
//                actions.openApp()
//            } label: {
//                Image(systemName: "gearshape")
//                    .font(.system(size: 16, weight: .medium))
//                    .foregroundStyle(Color(.secondaryLabel))
//                    .padding(6)
//            }
//            .buttonStyle(.plain)
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

    private func handlePredictiveSelection(_ suggestion: String) {
        // Delete the partial word characters
        let charsToDelete = predictiveState.partialWord.count
        for _ in 0..<charsToDelete {
            actions.deleteBackward()
        }

        // Insert the full suggestion + trailing space
        actions.insertText(suggestion + " ")
        // Mark the trailing space as a "smart space" so the next punctuation attaches to
        // the word (native iOS behavior). Consumed/cleared in the commit pipeline.
        state.inputTracking.pendingSmartSpace = true

        // Reset and re-evaluate
        predictiveState.dismiss()
        actions.evaluatePredictiveText()
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
        if AppGroupSettings.bool(forKey: AppGroupSettings.Key.debugHitOverlayEnabled, default: false) {
            self
                .background(Color(.systemRed).opacity(0.08))
                .overlay(Rectangle().stroke(Color(.systemRed).opacity(0.9), lineWidth: 1))
        } else {
            self
        }
    }
}

struct PredictiveSuggestionsView: View {
    let suggestions: [String]
    let onSelect: (String) -> Void
    /// Called when the user long-presses the middle pill — matches native iOS, which
    /// long-presses the user's literal typed word to dismiss predictions for the session.
    var onDismissForSession: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                if index > 0 {
                    // Thin vertical divider between pills (native iOS style)
                    Rectangle()
                        .fill(Color(.separator).opacity(0.4))
                        .frame(width: 0.5)
                        .padding(.vertical, 8)
                }

                let isMiddle = (suggestions.count >= 2 && index == suggestions.count / 2)
                Button {
                    onSelect(suggestion)
                } label: {
                    Text(suggestion)
                        .font(.custom("IBMPlexMono-Medium", size: 16))
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
