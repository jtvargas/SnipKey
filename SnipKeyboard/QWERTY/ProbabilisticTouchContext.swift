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
    /// Always non-nil — defaults to word-initial frequencies.
    private(set) var currentWeights: [Character: Float]

    /// Predictive next-character prior derived from the in-progress word's top
    /// completions — P(next char | partial word, dictionary). Produced OFF the
    /// touch path by the coalesced predictive flush (`updatePredictivePrior`);
    /// nil when there is no usable prediction (short prefix, word boundary).
    private(set) var predictivePrior: [Character: Float]?

    /// Pre-baked blend of `predictivePrior` and `currentWeights`. The touch hot
    /// path reads THIS (via `weightsForRow` / `weight(for:)`) so it never performs
    /// blending math. nil whenever there is no usable predictive prior —
    /// the readers then fall back to the pure-bigram `currentWeights`.
    private(set) var blendedWeights: [Character: Float]?

    /// Whether the current input language is English. The bigram tables
    /// (`BigramEngine`) are English-only, so for non-English contexts the blend
    /// drops the bigram term and uses the (language-correct) prior alone.
    private var isEnglishContext: Bool = true

    /// Whether `predictivePrior` was computed for the CURRENT character context.
    /// `recordCharacter` clears it: at that instant the prior still predicts the
    /// character that was just typed — using it would pull the NEXT tap toward the
    /// PREVIOUS letter. The coalesced predictive flush re-sets it (~40ms later)
    /// with P(next | prefix including the new char). A stale English prior is
    /// excluded from the blend (fresh bigram+trigram only); a stale non-English
    /// prior is kept, because a stale right-language prior still beats a fresh
    /// wrong-language bigram.
    private var priorIsFresh = false

    /// Prior's share of the blend; the bigram gets the remainder. Tunable.
    private static let priorBlendFactor: Float = 0.45

    /// The character before `lastCharacter` — gives the 2-char context for trigram boosts.
    private var secondLastCharacter: Character?

    /// How "peaked" the current distribution is, in [minConfidence, 1]. Drives dynamic λ: the
    /// resolver scales β by this so it pulls hard when context is confident (mid-word) and barely
    /// at all when it isn't (first letter of a word). Plan §7.
    private(set) var confidence: Float = 0.35

    private static let minConfidence: Float = 0.25      // floor so β is never fully zeroed

    init() {
        self.currentWeights = BigramEngine.wordInitialFrequencies
        recomputeConfidence()
    }

    /// Update after a character is typed. Runs ON the touch path (synchronously inside
    /// `commitCharacter` ← `touchesBegan`): one bigram dictionary read, an optional
    /// trigram max-merge, and the stale-aware re-bake — no smoothing loop.
    func recordCharacter(_ char: Character) {
        let lower = Character(char.lowercased())
        // The trigram context advances even when the char repeats ("ll" ⇒ prev2='l',
        // prev1='l') — the old early-out left it stale after double letters.
        secondLastCharacter = (lower == lastCharacter) ? lower : lastCharacter
        lastCharacter = lower
        // Bigram base, then raise the predicted letters for high-confidence trigram prefixes
        // (max-merge: only ever increases a likely letter, never lowers another).
        var base = BigramEngine.weights(after: lower)
        if let boost = TrigramEngine.boost(prev2: secondLastCharacter, prev1: lower) {
            for (ch, b) in boost { base[ch] = max(base[ch] ?? 0, b) }
        }
        currentWeights = base
        // The prior predicted THIS character; for the next tap it is one keystroke stale.
        priorIsFresh = false
        rebakeBlendedWeights()
        recomputeConfidence()
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
        priorIsFresh = false
        blendedWeights = nil
        recomputeConfidence()
    }

    /// Push (or clear) the predictive next-character prior. Produced on `@MainActor`
    /// by the coalesced predictive flush; the touch-path reads (`weightsForRow` /
    /// `weight(for:)`) are also `@MainActor`, so the re-bake here races nothing.
    /// Pass `isEnglish == false` to drop the English bigram term from the blend.
    func updatePredictivePrior(_ prior: [Character: Float]?, isEnglish: Bool) {
        predictivePrior = prior
        isEnglishContext = isEnglish
        priorIsFresh = (prior != nil)
        rebakeBlendedWeights()
        recomputeConfidence()
    }

    /// Recompute `confidence` from the sharp distribution the resolver actually reads.
    /// Flat (word start) → minConfidence; strongly peaked (e.g. after "th") → 1.
    private func recomputeConfidence() {
        let source = blendedWeights ?? currentWeights
        let peak = source.values.max() ?? fallbackPeak
        let normalized = min(max((peak - 0.12) / (0.35 - 0.12), 0), 1)
        confidence = Self.minConfidence + normalized * (1 - Self.minConfidence)
    }

    private var fallbackPeak: Float { 1.0 / 26.0 }

    /// Recompute `blendedWeights` from the current `predictivePrior` + `currentWeights`.
    /// Runs on context change / predictive update, so the hot-path reads always see a
    /// finished result.
    private func rebakeBlendedWeights() {
        guard let prior = predictivePrior else {
            blendedWeights = nil
            return
        }
        // Non-English: bigram tables are English-only, so use the language-correct
        // prior alone rather than polluting it with English bigram mass — even when
        // the prior is one keystroke stale.
        guard isEnglishContext else {
            blendedWeights = prior
            return
        }
        // A stale English prior pulls toward the letter just typed — drop it and let
        // the fresh bigram+trigram carry the next tap until the flush re-supplies it.
        guard priorIsFresh else {
            blendedWeights = nil
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
    /// Reads the pre-baked `blendedWeights` when a fresh predictive prior exists, else
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
        (blendedWeights ?? currentWeights)[Character(char.lowercased())] ?? (1.0 / 26.0)
    }
}

#if DEBUG
extension ProbabilisticTouchContext {
    /// One-time invariant check for the prior pipeline: sharp (un-smoothed) weights,
    /// stale-prior exclusion, double-letter trigram context, and word-boundary snap.
    /// Logs (does not crash) on violation — same pattern as
    /// `ProbabilisticHitResolver.runEquivalenceSelfTest`.
    static func runContextSelfTest() {
        var failures: [String] = []
        let ctx = ProbabilisticTouchContext()

        // 1. Trigram sharpness: after "t","h" the resolver must see the full "th→e"
        //    boost immediately (no EMA dilution).
        ctx.recordCharacter("t")
        ctx.recordCharacter("h")
        if ctx.weight(for: "e") < 0.5 {
            failures.append("th→e boost diluted: weight(e)=\(ctx.weight(for: "e"))")
        }
        let expectedPeak = ctx.currentWeights.values.max() ?? 0
        let expectedNorm = min(max((expectedPeak - 0.12) / (0.35 - 0.12), 0), 1)
        let expectedConfidence = minConfidence + expectedNorm * (1 - minConfidence)
        if abs(ctx.confidence - expectedConfidence) > 0.001 {
            failures.append("confidence lags sharp source: \(ctx.confidence) vs \(expectedConfidence)")
        }

        // 2. Stale English prior is excluded after a keystroke; a fresh one applies
        //    at full strength immediately.
        ctx.updatePredictivePrior(["x": 0.9], isEnglish: true)
        if ctx.blendedWeights == nil {
            failures.append("fresh prior did not produce a blend")
        }
        let blendedX = ctx.weight(for: "x")
        let expectedX = 0.45 * Float(0.9) + 0.55 * (ctx.currentWeights["x"] ?? 1.0 / 26.0)
        if abs(blendedX - expectedX) > 0.001 {
            failures.append("fresh prior under-applied: weight(x)=\(blendedX) expected \(expectedX)")
        }
        ctx.recordCharacter("e")
        if ctx.blendedWeights != nil {
            failures.append("stale English prior still blended after recordCharacter")
        }

        // 3. Stale NON-English prior is kept (right language beats wrong-language bigram).
        ctx.updatePredictivePrior(["ñ": 0.8], isEnglish: false)
        ctx.recordCharacter("a")
        if ctx.weight(for: "ñ") < 0.79 {
            failures.append("stale non-English prior dropped: weight(ñ)=\(ctx.weight(for: "ñ"))")
        }

        // 4. Double-letter trigram context: "t","e","e" ⇒ prev2='e', prev1='e'.
        let ctx2 = ProbabilisticTouchContext()
        ctx2.recordCharacter("t")
        ctx2.recordCharacter("e")
        ctx2.recordCharacter("e")
        if ctx2.lastCharacter != "e" || ctx2.secondLastCharacter != "e" {
            failures.append("double-letter context stale: prev2=\(String(describing: ctx2.secondLastCharacter))")
        }

        // 5. Word boundary snaps to word-initial frequencies and drops the prior.
        ctx2.updatePredictivePrior(["q": 0.9], isEnglish: true)
        ctx2.recordNonCharacter()
        if ctx2.blendedWeights != nil || ctx2.currentWeights != BigramEngine.wordInitialFrequencies {
            failures.append("word boundary did not snap to word-initial")
        }

        if failures.isEmpty {
            NSLog("[SnipKeyboard] ProbabilisticTouchContext self-test passed")
        } else {
            for f in failures { NSLog("[SnipKeyboard] ProbabilisticTouchContext SELF-TEST FAILED: %@", f) }
        }
    }
}
#endif
