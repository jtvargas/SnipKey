//
//  PredictiveTextEngine.swift
//  SnipKeyboard
//
//  Created by Jonathan Taveras Vargas on 2/11/26.
//

import Foundation
import SwiftUI
import UIKit

// MARK: - Predictive Candidates

enum PredictiveCandidateRole: String, Equatable, Sendable {
    case typed
    case correction
    case completion
    case textReplacement
}

enum PredictiveCandidateSource: String, Equatable, Sendable {
    case typed
    case textCheckerCompletion
    case textCheckerGuess
    case lexicon
}

struct PredictiveCandidate: Identifiable, Equatable, Sendable {
    let text: String
    let role: PredictiveCandidateRole
    let source: PredictiveCandidateSource
    let confidence: Float
    let replacementLength: Int
    let autoCommitEligible: Bool

    var id: String {
        "\(role.rawValue):\(text.lowercased())"
    }
}

struct PredictiveCorrectionSnapshot: Equatable, Sendable {
    let original: String
    let replacement: String
}

// MARK: - Predictive Text Tracker (NOT @Observable — no view re-renders)

/// Extracts the current partial word from text context and generates
/// word completions using UITextChecker + UILexicon.
/// Runs on every relevant keystroke but mutates only plain properties —
/// zero SwiftUI re-renders. Only promotes to @Observable state when
/// the candidates actually change.
final class PredictiveTextTracker {
    private let textChecker = UITextChecker()

    /// Cached supplementary lexicon from UIInputViewController.
    /// Contains user contacts, shortcuts (e.g., "omw" → "On my way!").
    /// Set once from viewDidLoad via requestSupplementaryLexicon.
    var lexicon: UILexicon?

    /// Last known candidates — used to avoid redundant @Observable mutations
    private var lastCandidates: [PredictiveCandidate] = []
    /// Last known partial word
    private var lastPartialWord: String = ""

    /// Correction pairs the user rejected during this keyboard session via immediate
    /// backspace. Kept here so future evaluations stop offering the same auto-commit.
    private var rejectedCorrections: Set<String> = []

    /// Evaluate the current text context and generate candidates.
    /// Returns (changed, candidates, partialWord) — only signals change
    /// when candidates actually differ from last evaluation.
    func evaluate(context: String?) -> (changed: Bool, candidates: [PredictiveCandidate], partialWord: String) {
        guard let context = context, !context.isEmpty else {
            let changed = !lastCandidates.isEmpty || !lastPartialWord.isEmpty
            lastCandidates = []
            lastPartialWord = ""
            return (changed, [], "")
        }

        // Extract current partial word by walking backwards from cursor
        let partialWord = extractPartialWord(from: context)

        // Need at least 2 characters to generate useful suggestions
        guard partialWord.count >= 2 else {
            let changed = !lastCandidates.isEmpty || lastPartialWord != partialWord
            lastCandidates = []
            lastPartialWord = partialWord
            return (changed, [], partialWord)
        }

        // Generate candidates
        let candidates = generateCandidates(for: partialWord, in: context)

        // Check if anything changed
        let changed = candidates != lastCandidates || partialWord != lastPartialWord
        lastCandidates = candidates
        lastPartialWord = partialWord

        return (changed, candidates, partialWord)
    }

    /// Reset all cached state (e.g., after suggestion insertion)
    func reset() {
        lastCandidates = []
        lastPartialWord = ""
    }

    func rejectCorrection(original: String, replacement: String) {
        rejectedCorrections.insert(Self.rejectionKey(original: original, replacement: replacement))
        reset()
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

    /// Generate up to 3 candidates combining UITextChecker completions,
    /// spell corrections, and UILexicon entries.
    private func generateCandidates(for partialWord: String, in context: String) -> [PredictiveCandidate] {
        var rawCandidates: [PredictiveCandidate] = []
        let language = preferredLanguage()
        let lowerPartial = partialWord.lowercased()

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

        for (index, completion) in completions.prefix(6).enumerated() {
            let confidence = max(0.62, 0.80 - Float(index) * 0.05)
            rawCandidates.append(
                PredictiveCandidate(
                    text: matchCasing(of: completion, to: partialWord),
                    role: .completion,
                    source: .textCheckerCompletion,
                    confidence: confidence,
                    replacementLength: partialWord.count,
                    autoCommitEligible: false
                )
            )
        }

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
            for (index, guess) in guesses.prefix(4).enumerated() {
                let distance = Self.editDistance(lowerPartial, guess.lowercased(), maxDistance: 3)
                let confidence = correctionConfidence(distance: distance, rank: index, partialWord: partialWord)
                let corrected = matchCasing(of: guess, to: partialWord)
                rawCandidates.append(
                    PredictiveCandidate(
                        text: corrected,
                        role: .correction,
                        source: .textCheckerGuess,
                        confidence: confidence,
                        replacementLength: partialWord.count,
                        autoCommitEligible: confidence >= Self.autoCommitThreshold
                            && !isRejected(original: partialWord, replacement: corrected)
                    )
                )
            }
        }

        // 3. UILexicon entries — match against user contacts/shortcuts/text replacements
        if let lexicon = lexicon {
            for entry in lexicon.entries {
                let input = entry.userInput.lowercased()
                let docText = matchCasing(of: entry.documentText, to: partialWord)
                if input == lowerPartial && docText.lowercased() != lowerPartial {
                    rawCandidates.append(
                        PredictiveCandidate(
                            text: docText,
                            role: .textReplacement,
                            source: .lexicon,
                            confidence: 0.98,
                            replacementLength: partialWord.count,
                            autoCommitEligible: !isRejected(original: partialWord, replacement: docText)
                        )
                    )
                } else if input.hasPrefix(lowerPartial) && input != lowerPartial {
                    rawCandidates.append(
                        PredictiveCandidate(
                            text: docText,
                            role: .completion,
                            source: .lexicon,
                            confidence: 0.76,
                            replacementLength: partialWord.count,
                            autoCommitEligible: false
                        )
                    )
                }
            }
        }

        let ranked = deduplicatedRankedCandidates(rawCandidates, typedWord: partialWord)
        guard !ranked.isEmpty else { return [] }

        let typedCandidate = PredictiveCandidate(
            text: partialWord,
            role: .typed,
            source: .typed,
            confidence: 1,
            replacementLength: partialWord.count,
            autoCommitEligible: false
        )

        if let primary = ranked.first, primary.autoCommitEligible {
            return Array(([typedCandidate, primary] + ranked.dropFirst()).prefix(3))
        }

        return Array(ranked.prefix(3))
    }

    private func deduplicatedRankedCandidates(
        _ candidates: [PredictiveCandidate],
        typedWord: String
    ) -> [PredictiveCandidate] {
        let lowerTyped = typedWord.lowercased()
        var bestByText: [String: PredictiveCandidate] = [:]

        for candidate in candidates {
            let key = candidate.text.lowercased()
            if key == lowerTyped || key.isEmpty { continue }
            if let existing = bestByText[key] {
                bestByText[key] = betterCandidate(existing, candidate)
            } else {
                bestByText[key] = candidate
            }
        }

        return bestByText.values.sorted { lhs, rhs in
            let leftScore = rankingScore(lhs, typedWord: typedWord)
            let rightScore = rankingScore(rhs, typedWord: typedWord)
            if leftScore != rightScore { return leftScore > rightScore }
            return lhs.text < rhs.text
        }
    }

    private func betterCandidate(_ lhs: PredictiveCandidate, _ rhs: PredictiveCandidate) -> PredictiveCandidate {
        if lhs.autoCommitEligible != rhs.autoCommitEligible {
            return lhs.autoCommitEligible ? lhs : rhs
        }
        if lhs.confidence != rhs.confidence {
            return lhs.confidence > rhs.confidence ? lhs : rhs
        }
        return rolePriority(lhs.role) >= rolePriority(rhs.role) ? lhs : rhs
    }

    private func rankingScore(_ candidate: PredictiveCandidate, typedWord: String) -> Float {
        var score = candidate.confidence * 100
        score += Float(rolePriority(candidate.role)) * 8
        if candidate.text.lowercased().hasPrefix(typedWord.lowercased()) {
            score += 12
        }
        if candidate.autoCommitEligible {
            score += 18
        }
        return score
    }

    private func rolePriority(_ role: PredictiveCandidateRole) -> Int {
        switch role {
        case .textReplacement: return 4
        case .correction: return 3
        case .completion: return 2
        case .typed: return 1
        }
    }

    private func correctionConfidence(distance: Int, rank: Int, partialWord: String) -> Float {
        guard distance <= 3 else { return 0.50 }
        var confidence: Float
        switch distance {
        case 0: confidence = 0.60
        case 1: confidence = 0.92
        case 2: confidence = partialWord.count >= 4 ? 0.86 : 0.82
        default: confidence = partialWord.count >= 5 ? 0.80 : 0.64
        }
        confidence -= Float(rank) * 0.06
        return max(0, min(confidence, 0.98))
    }

    private func matchCasing(of candidate: String, to typedWord: String) -> String {
        guard let first = typedWord.first else { return candidate }
        if typedWord.allSatisfy({ $0.isUppercase || !$0.isLetter }) {
            return candidate.uppercased()
        }
        if first.isUppercase {
            return candidate.prefix(1).uppercased() + String(candidate.dropFirst())
        }
        return candidate.lowercased()
    }

    private func isRejected(original: String, replacement: String) -> Bool {
        rejectedCorrections.contains(Self.rejectionKey(original: original, replacement: replacement))
    }

    private static func rejectionKey(original: String, replacement: String) -> String {
        "\(original.lowercased())>\(replacement.lowercased())"
    }

    private static let autoCommitThreshold: Float = 0.84

    static func editDistance(_ lhs: String, _ rhs: String, maxDistance: Int = Int.max) -> Int {
        if lhs == rhs { return 0 }
        let a = Array(lhs)
        let b = Array(rhs)
        if abs(a.count - b.count) > maxDistance { return maxDistance + 1 }
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var previousPrevious: [Int]?
        var previous = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            current[0] = i
            var rowMin = current[0]
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + cost
                )
                if i > 1,
                   j > 1,
                   a[i - 1] == b[j - 2],
                   a[i - 2] == b[j - 1],
                   let previousPrevious {
                    current[j] = min(current[j], previousPrevious[j - 2] + 1)
                }
                rowMin = min(rowMin, current[j])
            }
            if rowMin > maxDistance { return maxDistance + 1 }
            previousPrevious = previous
            swap(&previous, &current)
        }

        return previous[b.count]
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
    /// Current word candidates to display in the toolbar (max 3)
    var candidates: [PredictiveCandidate] = []

    /// The partial word being completed (used to know how many chars to delete on selection)
    var partialWord: String = ""

    /// User-dismissed for the rest of this keyboard session via long-press on the middle
    /// pill. Resets next time the keyboard mounts. While `true`, `updateSuggestions` is a no-op.
    var dismissedForSession: Bool = false

    /// Whether suggestions are available and should be shown
    var isActive: Bool { !candidates.isEmpty }

    var suggestions: [String] { candidates.map(\.text) }

    var autoCommitCandidate: PredictiveCandidate? {
        candidates.first { $0.autoCommitEligible }
    }

    /// Non-isolated initializer so the `@Entry` macro can call it from a non-isolated context.
    /// All stored properties use literal defaults that don't touch main-actor state.
    nonisolated init() {}

    /// Update suggestions from tracker evaluation.
    /// All setters use equality guards to prevent unnecessary re-renders.
    func updateCandidates(_ candidates: [PredictiveCandidate], partialWord: String) {
        guard !dismissedForSession else { return }
        if self.candidates != candidates {
            self.candidates = candidates
        }
        if self.partialWord != partialWord {
            self.partialWord = partialWord
        }
    }

    func updateSuggestions(suggestions: [String], partialWord: String) {
        let candidates = suggestions.map {
            PredictiveCandidate(
                text: $0,
                role: .completion,
                source: .textCheckerCompletion,
                confidence: 0.7,
                replacementLength: partialWord.count,
                autoCommitEligible: false
            )
        }
        updateCandidates(candidates, partialWord: partialWord)
    }

    /// Dismiss the bar for the remainder of this keyboard session.
    /// Matches native iOS's "long-press the middle suggestion to silence predictions" gesture.
    func dismissForSession() {
        dismissedForSession = true
        dismiss()
    }

    /// Clear all suggestions
    func dismiss() {
        if !candidates.isEmpty {
            candidates = []
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
