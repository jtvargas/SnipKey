//
//  PredictiveTextEngine.swift
//  SnipKeyboard
//
//  Created by Jonathan Taveras Vargas on 2/11/26.
//

import Foundation
import SwiftUI
import UIKit

// MARK: - Predictive Text Tracker (NOT @Observable — no view re-renders)

/// Extracts the current partial word from text context and generates
/// word completions using UITextChecker + UILexicon.
/// Runs on every relevant keystroke but mutates only plain properties —
/// zero SwiftUI re-renders. Only promotes to @Observable state when
/// the suggestions actually change.
final class PredictiveTextTracker {
    private let textChecker = UITextChecker()

    /// Cached supplementary lexicon from UIInputViewController.
    /// Contains user contacts, shortcuts (e.g., "omw" → "On my way!").
    /// Set once from viewDidLoad via requestSupplementaryLexicon.
    var lexicon: UILexicon?

    /// Last known suggestions — used to avoid redundant @Observable mutations
    private var lastSuggestions: [String] = []
    /// Last known partial word
    private var lastPartialWord: String = ""

    /// Evaluate the current text context and generate suggestions.
    /// Returns (changed, suggestions, partialWord) — only signals change
    /// when suggestions actually differ from last evaluation.
    func evaluate(context: String?) -> (changed: Bool, suggestions: [String], partialWord: String) {
        guard let context = context, !context.isEmpty else {
            let changed = !lastSuggestions.isEmpty || !lastPartialWord.isEmpty
            lastSuggestions = []
            lastPartialWord = ""
            return (changed, [], "")
        }

        // Extract current partial word by walking backwards from cursor
        let partialWord = extractPartialWord(from: context)

        // Need at least 2 characters to generate useful suggestions
        guard partialWord.count >= 2 else {
            let changed = !lastSuggestions.isEmpty || lastPartialWord != partialWord
            lastSuggestions = []
            lastPartialWord = partialWord
            return (changed, [], partialWord)
        }

        // Generate suggestions
        let suggestions = generateSuggestions(for: partialWord, in: context)

        // Check if anything changed
        let changed = suggestions != lastSuggestions || partialWord != lastPartialWord
        lastSuggestions = suggestions
        lastPartialWord = partialWord

        return (changed, suggestions, partialWord)
    }

    /// Reset all cached state (e.g., after suggestion insertion)
    func reset() {
        lastSuggestions = []
        lastPartialWord = ""
    }

    // MARK: - Word Extraction

    /// Walk backwards from the end of context to find the current partial word.
    /// Stops at whitespace, newline, or common punctuation.
    private func extractPartialWord(from context: String) -> String {
        var chars: [Character] = []

        for char in context.reversed() {
            if char.isWhitespace || char.isNewline || char.isPunctuation || char.isSymbol {
                break
            }
            chars.append(char)
        }

        return String(chars.reversed())
    }

    // MARK: - Suggestion Generation

    /// Generate up to 3 suggestions combining UITextChecker completions,
    /// spell corrections, and UILexicon entries.
    private func generateSuggestions(for partialWord: String, in context: String) -> [String] {
        var allSuggestions: [String] = []
        let language = preferredLanguage()

        // 1. UITextChecker completions for the partial word
        let nsContext = context as NSString
        let wordRange = NSRange(
            location: nsContext.length - (partialWord as NSString).length,
            length: (partialWord as NSString).length
        )

        let completions = textChecker.completions(
            forPartialWordRange: wordRange,
            in: context,
            language: language
        ) ?? []

        allSuggestions.append(contentsOf: completions)

        // 2. Spell check — if the partial word is misspelled, add guesses
        let misspelledRange = textChecker.rangeOfMisspelledWord(
            in: partialWord,
            range: NSRange(location: 0, length: (partialWord as NSString).length),
            startingAt: 0,
            wrap: false,
            language: language
        )

        if misspelledRange.location != NSNotFound {
            let guesses = textChecker.guesses(
                forWordRange: misspelledRange,
                in: partialWord,
                language: language
            ) ?? []
            allSuggestions.append(contentsOf: guesses)
        }

        // 3. UILexicon entries — match against user contacts/shortcuts
        if let lexicon = lexicon {
            for entry in lexicon.entries {
                let input = entry.userInput.lowercased()
                let lowerPartial = partialWord.lowercased()
                if input.hasPrefix(lowerPartial) && input != lowerPartial {
                    allSuggestions.append(entry.documentText)
                }
            }
        }

        // Deduplicate (case-insensitive), remove exact matches, cap at 3
        var seen = Set<String>()
        let lowerPartial = partialWord.lowercased()
        var unique: [String] = []

        for suggestion in allSuggestions {
            let lowerSuggestion = suggestion.lowercased()
            // Skip if it's exactly what the user already typed
            if lowerSuggestion == lowerPartial { continue }
            if seen.contains(lowerSuggestion) { continue }
            seen.insert(lowerSuggestion)
            unique.append(suggestion)
            if unique.count >= 3 { break }
        }

        return unique
    }

    // MARK: - Language

    /// Get the preferred language for UITextChecker.
    /// Falls back to "en_US" if the device language is not available.
    private func preferredLanguage() -> String {
        let available = UITextChecker.availableLanguages
        let preferred = Locale.preferredLanguages.first ?? "en_US"
        // UITextChecker uses underscore format (en_US), Locale uses dash (en-US)
        let normalized = preferred.replacingOccurrences(of: "-", with: "_")
        if available.contains(normalized) {
            return normalized
        }
        // Try just the language code (e.g., "en")
        let langCode = String(normalized.prefix(while: { $0 != "_" }))
        if let match = available.first(where: { $0.hasPrefix(langCode) }) {
            return match
        }
        return "en_US"
    }
}

// MARK: - Predictive Text State (@Observable — only view-affecting properties)

/// Holds the current predictive text suggestions for the toolbar.
/// Mutations trigger toolbar re-renders, so all setters use equality guards.
@MainActor
@Observable
class PredictiveTextState {
    /// Current word suggestions to display in the toolbar (max 3)
    var suggestions: [String] = []

    /// The partial word being completed (used to know how many chars to delete on selection)
    var partialWord: String = ""

    /// User-dismissed for the rest of this keyboard session via long-press on the middle
    /// pill. Resets next time the keyboard mounts. While `true`, `updateSuggestions` is a no-op.
    var dismissedForSession: Bool = false

    /// Whether suggestions are available and should be shown
    var isActive: Bool { !suggestions.isEmpty }

    /// Non-isolated initializer so the `@Entry` macro can call it from a non-isolated context.
    /// All stored properties use literal defaults that don't touch main-actor state.
    nonisolated init() {}

    /// Update suggestions from tracker evaluation.
    /// All setters use equality guards to prevent unnecessary re-renders.
    func updateSuggestions(suggestions: [String], partialWord: String) {
        guard !dismissedForSession else { return }
        if self.suggestions != suggestions {
            self.suggestions = suggestions
        }
        if self.partialWord != partialWord {
            self.partialWord = partialWord
        }
    }

    /// Dismiss the bar for the remainder of this keyboard session.
    /// Matches native iOS's "long-press the middle suggestion to silence predictions" gesture.
    func dismissForSession() {
        dismissedForSession = true
        dismiss()
    }

    /// Clear all suggestions
    func dismiss() {
        if !suggestions.isEmpty {
            suggestions = []
        }
        if !partialWord.isEmpty {
            partialWord = ""
        }
    }
}

// MARK: - SwiftUI Environment Key

extension EnvironmentValues {
    @Entry var predictiveTextState: PredictiveTextState = PredictiveTextState()
}
