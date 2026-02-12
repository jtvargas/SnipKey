//
//  ProbabilisticTouchContext.swift
//  SnipKeyboard
//
//  Created by Jonathan Taveras Vargas on 2/11/26.
//

import Foundation

/// Tracks the last typed character for probabilistic touch resolution.
/// This is a plain class (NOT @Observable) — updates cause zero SwiftUI
/// re-renders. Read by KeyButtonView during touch resolution (UIKit path).
///
/// Updated on every keystroke via handleTap() in KeyButtonView,
/// same pattern as QWERTYInputTracking.
final class ProbabilisticTouchContext {

    /// The last character typed (lowercased). nil if last action wasn't a character.
    private(set) var lastCharacter: Character?

    /// Pre-computed weights for the current context.
    /// Recomputed only when lastCharacter changes.
    /// Always non-nil — defaults to word-initial frequencies.
    private(set) var currentWeights: [Character: Float]

    init() {
        self.currentWeights = BigramEngine.wordInitialFrequencies
    }

    /// Update after a character is typed.
    /// Only recomputes weights when the preceding character actually changes.
    /// During rapid typing of different characters, this is one dictionary
    /// lookup per keystroke (~20ns).
    func recordCharacter(_ char: Character) {
        let lower = Character(char.lowercased())
        if lower != lastCharacter {
            lastCharacter = lower
            currentWeights = BigramEngine.weights(after: lower)
        }
    }

    /// Reset context (after space, backspace, return, or non-character action).
    /// Switches to word-initial frequencies since the next character
    /// will be the start of a new word.
    func recordNonCharacter() {
        if lastCharacter != nil {
            lastCharacter = nil
            currentWeights = BigramEngine.wordInitialFrequencies
        }
    }

    /// Extract ordered probability weights for a specific row's characters.
    /// Returns an array of floats in the same order as the input characters.
    ///
    /// - Parameter rowChars: The characters in the row (e.g., ["Q","W","E",...])
    /// - Returns: Array of weights, one per character. Unknown chars get a small default weight.
    func weightsForRow(_ rowChars: [String]) -> [Float] {
        return rowChars.map { charString in
            let lower = Character(charString.lowercased())
            return currentWeights[lower] ?? (1.0 / 26.0)
        }
    }
}
