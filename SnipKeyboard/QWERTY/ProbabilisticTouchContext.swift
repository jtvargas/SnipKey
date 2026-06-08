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

    /// Predictive next-character prior derived from the in-progress word's top
    /// completions — P(next char | partial word, dictionary). Produced OFF the
    /// touch path by the coalesced predictive flush (`updatePredictivePrior`);
    /// nil when there is no usable prediction (short prefix, word boundary).
    private(set) var predictivePrior: [Character: Float]?

    /// Pre-baked blend of `predictivePrior` and `currentWeights`. The touch hot
    /// path reads THIS (via `weightsForRow`) so it never performs blending math.
    /// nil whenever there is no predictive prior — `weightsForRow` then falls
    /// back to the pure-bigram `currentWeights`, preserving legacy behavior.
    private(set) var blendedWeights: [Character: Float]?

    /// Whether the current input language is English. The bigram tables
    /// (`BigramEngine`) are English-only, so for non-English contexts the blend
    /// drops the bigram term and uses the (language-correct) prior alone.
    private var isEnglishContext: Bool = true

    /// Prior's share of the blend; the bigram gets the remainder. Tunable.
    private static let priorBlendFactor: Float = 0.45

    /// The character before `lastCharacter` — gives the 2-char context for trigram boosts.
    private var secondLastCharacter: Character?

    /// Temporally-smoothed weights the next-gen resolver reads (via `weight(for:)`). EMA of the
    /// raw source so the catch-zones rebalance gradually between keystrokes instead of snapping
    /// (plan §6 anti-jitter). Snapped (not eased) at word boundaries to avoid cross-word lag.
    private(set) var smoothedWeights: [Character: Float]

    /// How "peaked" the current distribution is, in [minConfidence, 1]. Drives dynamic λ: the
    /// resolver scales β by this so it pulls hard when context is confident (mid-word) and barely
    /// at all when it isn't (first letter of a word). Plan §7.
    private(set) var confidence: Float = 0.35

    private static let smoothingAlpha: Float = 0.4      // EMA rate for smoothedWeights
    private static let smoothingDeadband: Float = 0.01  // skip a tiny update
    private static let minConfidence: Float = 0.25      // floor so β is never fully zeroed

    init() {
        self.currentWeights = BigramEngine.wordInitialFrequencies
        self.smoothedWeights = BigramEngine.wordInitialFrequencies
    }

    /// Update after a character is typed.
    /// Only recomputes weights when the preceding character actually changes.
    /// During rapid typing of different characters, this is one dictionary
    /// lookup per keystroke (~20ns).
    func recordCharacter(_ char: Character) {
        let lower = Character(char.lowercased())
        if lower != lastCharacter {
            secondLastCharacter = lastCharacter
            lastCharacter = lower
            // Bigram base, then raise the predicted letters for high-confidence trigram prefixes
            // (max-merge: only ever increases a likely letter, never lowers another).
            var base = BigramEngine.weights(after: lower)
            if let boost = TrigramEngine.boost(prev2: secondLastCharacter, prev1: lower) {
                for (ch, b) in boost { base[ch] = max(base[ch] ?? 0, b) }
            }
            currentWeights = base
            // Keep the blend consistent with the new local context within a word.
            // Off the touch-commit critical span (same call site as today).
            rebakeBlendedWeights()
            updateSmoothingAndConfidence(reset: false)
        }
    }

    /// Reset context (after space, backspace, return, or non-character action).
    /// Switches to word-initial frequencies since the next character
    /// will be the start of a new word, and drops the (now-stale) prefix prior.
    func recordNonCharacter() {
        if lastCharacter != nil {
            lastCharacter = nil
            currentWeights = BigramEngine.wordInitialFrequencies
        }
        secondLastCharacter = nil
        // Word boundary — the prefix prior no longer applies.
        predictivePrior = nil
        blendedWeights = nil
        // Snap (don't ease) at the word boundary so the previous word's context doesn't bleed
        // into the first keystrokes of the next one.
        updateSmoothingAndConfidence(reset: true)
    }

    /// Push (or clear) the predictive next-character prior. Produced on `@MainActor`
    /// by the coalesced predictive flush; the touch-path read (`weightsForRow` via
    /// `SmartTouchResolver`) is also `@MainActor`, so the re-bake here races nothing.
    /// Pass `isEnglish == false` to drop the English bigram term from the blend.
    func updatePredictivePrior(_ prior: [Character: Float]?, isEnglish: Bool) {
        predictivePrior = prior
        isEnglishContext = isEnglish
        rebakeBlendedWeights()
        updateSmoothingAndConfidence(reset: prior == nil)
    }

    /// Ease `smoothedWeights` toward the current raw source and recompute `confidence`. Runs only
    /// off the touch path (context change / predictive update). `reset` snaps instantly.
    private func updateSmoothingAndConfidence(reset: Bool) {
        let target = blendedWeights ?? currentWeights
        if reset || smoothedWeights.isEmpty {
            smoothedWeights = target
        } else {
            let a = Self.smoothingAlpha
            let fallback: Float = 1.0 / 26.0
            var next = smoothedWeights
            var maxDelta: Float = 0
            for k in Set(smoothedWeights.keys).union(target.keys) {
                let old = smoothedWeights[k] ?? fallback
                let nv = old + a * ((target[k] ?? fallback) - old)
                next[k] = nv
                maxDelta = max(maxDelta, abs(nv - old))
            }
            if maxDelta >= Self.smoothingDeadband { smoothedWeights = next }
        }
        // Confidence = how peaked the distribution is. Flat (word start) → minConfidence;
        // strongly peaked (e.g. after "th") → 1.
        let peak = smoothedWeights.values.max() ?? fallbackPeak
        let normalized = min(max((peak - 0.12) / (0.35 - 0.12), 0), 1)
        confidence = Self.minConfidence + normalized * (1 - Self.minConfidence)
    }

    private var fallbackPeak: Float { 1.0 / 26.0 }

    /// Recompute `blendedWeights` from the current `predictivePrior` + `currentWeights`.
    /// Runs only off the touch path (predictive completion / char record), so the
    /// hot path always reads a finished result.
    private func rebakeBlendedWeights() {
        guard let prior = predictivePrior else {
            blendedWeights = nil
            return
        }
        // Non-English: bigram tables are English-only, so use the language-correct
        // prior alone rather than polluting it with English bigram mass.
        guard isEnglishContext else {
            blendedWeights = prior
            return
        }
        let priorFactor = Self.priorBlendFactor
        let bigramFactor = 1 - priorFactor
        let fallback: Float = 1.0 / 26.0
        var blended: [Character: Float] = [:]
        blended.reserveCapacity(currentWeights.count + prior.count)
        for c in Set(currentWeights.keys).union(prior.keys) {
            let p = prior[c] ?? 0
            let b = currentWeights[c] ?? fallback
            blended[c] = priorFactor * p + bigramFactor * b
        }
        blendedWeights = blended
    }

    /// Extract ordered probability weights for a specific row's characters.
    /// Returns an array of floats in the same order as the input characters.
    /// Reads the pre-baked `blendedWeights` when a predictive prior exists, else
    /// the pure-bigram `currentWeights` — a single optional-dictionary read swap,
    /// no blending math on the hot path.
    ///
    /// - Parameter rowChars: The characters in the row (e.g., ["Q","W","E",...])
    /// - Returns: Array of weights, one per character. Unknown chars get a small default weight.
    func weightsForRow(_ rowChars: [String]) -> [Float] {
        let source = blendedWeights ?? currentWeights
        return rowChars.map { charString in
            let lower = Character(charString.lowercased())
            return source[lower] ?? (1.0 / 26.0)
        }
    }

    /// Probability weight P(char | context) for a single character, reading the same
    /// pre-baked source as `weightsForRow`. Used by the 2D `ProbabilisticHitResolver`,
    /// which scores all character keys (not just one row) per touch-down. Unknown chars
    /// get the uniform fallback. No blending math on the hot path.
    func weight(for char: Character) -> Float {
        smoothedWeights[Character(char.lowercased())] ?? (1.0 / 26.0)
    }
}
