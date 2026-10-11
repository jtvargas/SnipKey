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
    case englishFrequency
    case englishContext
    /// Runner-up of a swipe decode; accepting replaces the committed word + its space.
    case swipe
}

struct PredictiveCandidate: Identifiable, Equatable, Sendable {
    let text: String
    let role: PredictiveCandidateRole
    let source: PredictiveCandidateSource
    let confidence: Float
    let replacementLength: Int

    var id: String {
        "\(role.rawValue):\(text.lowercased())"
    }
}

// MARK: - Predictive Text Tracker (NOT @Observable — no view re-renders)

/// Preserves the literal typed word and ranks manual English choices from the
/// shared swipe vocabulary, bounded corpus bigrams, and system spelling/shortcuts.
/// Other languages retain the system-checker path. No text is ever inserted here.
// Access is serialized by `PredictiveTextEngineAsync`'s private queue.
final class PredictiveTextTracker: @unchecked Sendable {
    private lazy var textChecker = UITextChecker()
    private lazy var language = preferredLanguage()
    private lazy var englishModel = EnglishSuggestionModel.loadBundled()
    private var supplementaryEntries: [(input: String, text: String)] = []

    /// Cached supplementary lexicon from UIInputViewController.
    /// Contains user contacts, shortcuts (e.g., "omw" → "On my way!").
    /// Set once from `performDeferredSetup` (first viewDidAppear) via requestSupplementaryLexicon.
    var lexicon: UILexicon? {
        didSet {
            supplementaryEntries = lexicon?.entries.map {
                (EnglishSuggestionContext.normalized($0.userInput), $0.documentText)
            } ?? []
        }
    }

    /// Evaluate off-main. The view-facing state owns equality guards; suppressing an
    /// unchanged worker result could lose the newest validated document snapshot.
    func evaluate(context: String?) -> (candidates: [PredictiveCandidate], partialWord: String) {
        guard let context = context, !context.isEmpty else {
            return ([], "")
        }

        let english = language == "en" || language.hasPrefix("en_")
        let parsed = EnglishSuggestionContext(context)
        let partialWord = english ? parsed.partialWord : extractPartialWord(from: context)
        let candidates: [PredictiveCandidate]
        if english {
            candidates = generateEnglishCandidates(parsed, in: context)
        } else {
            candidates = partialWord.count >= 2 ? generateCandidates(for: partialWord, in: context) : []
        }

        return (candidates, partialWord)
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

    /// Slot 0 always preserves a nonempty partial verbatim; slots 1 and 2 are the
    /// best distinct manual choices. At a whitespace boundary all three are next words.
    private func generateEnglishCandidates(
        _ parsed: EnglishSuggestionContext,
        in context: String
    ) -> [PredictiveCandidate] {
        let partial = parsed.partialWord
        guard !partial.isEmpty || parsed.allowsNextWord else { return [] }
        let replacementLength = partial.count
        let normalizedTyped = EnglishSuggestionContext.normalized(partial)
        var ranked: [(candidate: PredictiveCandidate, score: Float)] = []
        ranked.reserveCapacity(20)

        func offer(_ text: String, role: PredictiveCandidateRole, source: PredictiveCandidateSource,
                   score: Float, confidence: Float) {
            let cased = parsed.matchCasing(text)
            let key = EnglishSuggestionContext.normalized(cased)
            guard !key.isEmpty, key != normalizedTyped else { return }
            let candidate = PredictiveCandidate(text: cased, role: role, source: source,
                                                confidence: confidence, replacementLength: replacementLength)
            if let index = ranked.firstIndex(where: {
                EnglishSuggestionContext.normalized($0.candidate.text) == key
            }) {
                if score > ranked[index].score { ranked[index] = (candidate, score) }
            } else {
                ranked.append((candidate, score))
            }
        }

        if let englishModel {
            for suggestion in englishModel.suggestions(for: parsed) {
                offer(suggestion.text, role: suggestion.isCorrection ? .correction : .completion,
                      source: suggestion.usesContext ? .englishContext : .englishFrequency,
                      score: suggestion.score, confidence: 0.8)
            }
        }
        if !partial.isEmpty {
            // The system is a fallback/supplement, not the first source of English prefixes.
            if ranked.count < 2 {
                let range = NSRange(location: (context as NSString).length - (partial as NSString).length,
                                    length: (partial as NSString).length)
                let completions = textChecker.completions(forPartialWordRange: range, in: context,
                                                          language: language) ?? []
                for (index, completion) in completions.prefix(6).enumerated() {
                    let prior = englishModel?.languageScore(completion, previousWord: parsed.previousWord) ?? -8
                    offer(completion, role: .completion, source: .textCheckerCompletion,
                          score: prior + 1.5 - Float(index) * 0.15, confidence: 0.7)
                }
            }
            if partial.count >= 3 && englishModel?.contains(partial) != true {
                let misspelling = textChecker.rangeOfMisspelledWord(
                    in: partial, range: NSRange(location: 0, length: (partial as NSString).length),
                    startingAt: 0, wrap: false, language: language)
                if misspelling.location != NSNotFound {
                    let guesses = textChecker.guesses(forWordRange: misspelling, in: partial,
                                                      language: language) ?? []
                    for (index, guess) in guesses.prefix(6).enumerated() {
                        let distance = Self.editDistance(normalizedTyped,
                            EnglishSuggestionContext.normalized(guess), maxDistance: 2)
                        guard distance <= 2 else { continue }
                        let prior = englishModel?.languageScore(guess, previousWord: parsed.previousWord) ?? -8
                        offer(guess, role: .correction, source: .textCheckerGuess,
                              score: prior - Float(distance) * 2.3 - Float(index) * 0.15,
                              confidence: correctionConfidence(distance: distance, rank: index, partialWord: partial))
                    }
                }
            }
            for entry in supplementaryEntries {
                if entry.input == normalizedTyped {
                    offer(entry.text, role: .textReplacement, source: .lexicon, score: 100, confidence: 0.98)
                } else if entry.input.hasPrefix(normalizedTyped) {
                    offer(entry.text, role: .completion, source: .lexicon,
                          score: -5.5 - Float(min(8, entry.input.count - partial.count)) * 0.2, confidence: 0.76)
                }
            }
        }
        ranked.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.candidate.text < $1.candidate.text
        }
        var result: [PredictiveCandidate] = []
        result.reserveCapacity(3)
        if !partial.isEmpty {
            result.append(PredictiveCandidate(text: partial, role: .typed, source: .typed,
                                              confidence: 1, replacementLength: replacementLength))
        }
        for entry in ranked.prefix(3 - result.count) { result.append(entry.candidate) }
        return result
    }

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
                    replacementLength: partialWord.count
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
                        replacementLength: partialWord.count
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
                            replacementLength: partialWord.count
                        )
                    )
                } else if input.hasPrefix(lowerPartial) && input != lowerPartial {
                    rawCandidates.append(
                        PredictiveCandidate(
                            text: docText,
                            role: .completion,
                            source: .lexicon,
                            confidence: 0.76,
                            replacementLength: partialWord.count
                        )
                    )
                }
            }
        }

        let ranked = deduplicatedRankedCandidates(rawCandidates, typedWord: partialWord)
        guard !ranked.isEmpty else { return [] }

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

    /// Exact suffix validated before replacement: a typed partial word, or a committed
    /// swipe word plus its trailing space. Candidates carry the matching deletion length.
    var partialWord: String = ""

    /// User-dismissed for the rest of this keyboard session via long-press on the middle
    /// pill. Resets next time the keyboard mounts. While `true`, `updateSuggestions` is a no-op.
    var dismissedForSession: Bool = false

    /// Whether suggestions are available and should be shown
    var isActive: Bool { !candidates.isEmpty }

    var suggestions: [String] { candidates.map(\.text) }

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
                replacementLength: partialWord.count
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
