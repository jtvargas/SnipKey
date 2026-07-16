//
//  ProbabilisticTouchContext.swift
//  SnipKeyboard
//
//  Created by Jonathan Taveras Vargas on 2/11/26.
//

import Foundation

/// Tunables for the prior pipeline (blend factor + confidence mapping). Internal so the
/// calibration replay harness and unit tests can sweep them; the live keyboard always
/// uses `.current`.
struct ContextTuning {
    /// Prior's share of the blend; the bigram gets the remainder.
    var priorBlendFactor: Float = 0.45
    /// Floor so β is never fully zeroed.
    var minConfidence: Float = 0.25
    /// Peak-weight normalization window: peak ≤ low ⇒ minConfidence, peak ≥ high ⇒ 1.
    var confidencePeakLow: Float = 0.12
    var confidencePeakHigh: Float = 0.35

    static let current = ContextTuning()
}

/// Tracks the last typed character for probabilistic touch resolution.
/// This is a plain class (NOT @Observable) — updates cause zero SwiftUI
/// re-renders. Read by the touch layers on every touch-down.
///
/// Storage is two preallocated 26-slot Float buffers (index = ASCII letter − 'a') plus a
/// tiny overflow map for non-ASCII prior characters. `recordCharacter` runs ON the touch
/// path (synchronously inside `commitCharacter`), so it must not allocate: the bigram row
/// is a fixed-buffer copy from `BigramEngine.table26`, the trigram boost mutates in place,
/// and the blend re-bake is a 26-iteration loop.
final class ProbabilisticTouchContext {

    /// The last character typed (lowercased). nil if last action wasn't a character.
    private(set) var lastCharacter: Character?

    /// Pre-computed weights for the current context, index = letter − 'a'.
    /// Always populated — defaults to word-initial frequencies.
    private var currentWeights26: ContiguousArray<Float>

    /// Pre-baked blend of `predictivePrior` and `currentWeights26`; valid only while
    /// `usingBlended` is true. The touch hot path reads whichever buffer is active — it
    /// never performs blending math.
    private var blended26: ContiguousArray<Float>
    private var usingBlended = false

    /// Blend weights for non-ASCII prior characters (non-English predictive priors only;
    /// nearly always empty). Read after the 26-slot fast path misses.
    private var overflowWeights: [Character: Float] = [:]

    /// Predictive next-character prior derived from the in-progress word's top
    /// completions — P(next char | partial word, dictionary). Produced OFF the
    /// touch path by the coalesced predictive flush (`updatePredictivePrior`);
    /// nil when there is no usable prediction (short prefix, word boundary).
    private(set) var predictivePrior: [Character: Float]?

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

    /// Blend/confidence tunables. `.current` on the live keyboard; the calibration replay
    /// harness constructs contexts with sweep variants.
    let tuning: ContextTuning

    /// The character before `lastCharacter` — gives the 2-char context for trigram boosts.
    private var secondLastCharacter: Character?

    /// How "peaked" the current distribution is, in [minConfidence, 1]. Drives dynamic λ: the
    /// resolver scales β by this so it pulls hard when context is confident (mid-word) and barely
    /// at all when it isn't (first letter of a word). Plan §7.
    private(set) var confidence: Float = 0.35

    init(tuning: ContextTuning = .current) {
        self.tuning = tuning
        self.currentWeights26 = ContiguousArray<Float>(repeating: 0, count: 26)
        self.blended26 = ContiguousArray<Float>(repeating: 0, count: 26)
        BigramEngine.fill26(after: nil, into: &currentWeights26)  // bakes table26 off the touch path
        recomputeConfidence()
    }

    /// Update after a character is typed. Runs ON the touch path (synchronously inside
    /// `commitCharacter` ← `touchesBegan`): one fixed-buffer row copy, an optional
    /// trigram max-merge, and the stale-aware re-bake — no allocations.
    func recordCharacter(_ char: Character) {
        let lower = Character(char.lowercased())
        // The trigram context advances even when the char repeats ("ll" ⇒ prev2='l',
        // prev1='l') — the old early-out left it stale after double letters.
        secondLastCharacter = (lower == lastCharacter) ? lower : lastCharacter
        lastCharacter = lower
        // Bigram base, then raise the predicted letters for high-confidence trigram prefixes
        // (max-merge: only ever increases a likely letter, never lowers another).
        BigramEngine.fill26(after: lower, into: &currentWeights26)
        if let boost = TrigramEngine.boost(prev2: secondLastCharacter, prev1: lower) {
            for (ch, b) in boost {
                if let i = BigramEngine.letterIndex(ch) {
                    currentWeights26[i] = max(currentWeights26[i], b)
                }
            }
        }
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
            BigramEngine.fill26(after: nil, into: &currentWeights26)
        }
        secondLastCharacter = nil
        // Word boundary — the prefix prior no longer applies.
        predictivePrior = nil
        priorIsFresh = false
        usingBlended = false
        if !overflowWeights.isEmpty { overflowWeights.removeAll(keepingCapacity: true) }
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
        var peak: Float = 0
        if usingBlended {
            for v in blended26 where v > peak { peak = v }
            for v in overflowWeights.values where v > peak { peak = v }
        } else {
            for v in currentWeights26 where v > peak { peak = v }
        }
        if peak <= 0 { peak = fallbackPeak }
        let normalized = min(max((peak - tuning.confidencePeakLow)
                                 / (tuning.confidencePeakHigh - tuning.confidencePeakLow), 0), 1)
        confidence = tuning.minConfidence + normalized * (1 - tuning.minConfidence)
    }

    private var fallbackPeak: Float { 1.0 / 26.0 }

    /// Recompute `blended26` from the current `predictivePrior` + `currentWeights26`.
    /// Runs on context change / predictive update (never per touch-down), so the hot-path
    /// reads always see a finished result. Prior keys are lowercased so a capitalized
    /// completion ("I…") still boosts its letter key.
    private func rebakeBlendedWeights() {
        if !overflowWeights.isEmpty { overflowWeights.removeAll(keepingCapacity: true) }
        guard let prior = predictivePrior else {
            usingBlended = false
            return
        }
        let fallback: Float = 1.0 / 26.0
        // Non-English: bigram tables are English-only, so use the language-correct
        // prior alone rather than polluting it with English bigram mass — even when
        // the prior is one keystroke stale. Letters absent from the prior read uniform.
        guard isEnglishContext else {
            for i in 0..<26 { blended26[i] = fallback }
            for (c, p) in prior {
                let lower = Character(String(c).lowercased())
                if let i = BigramEngine.letterIndex(lower) {
                    blended26[i] = p
                } else {
                    overflowWeights[lower] = p
                }
            }
            usingBlended = true
            return
        }
        // A stale English prior pulls toward the letter just typed — drop it and let
        // the fresh bigram+trigram carry the next tap until the flush re-supplies it.
        guard priorIsFresh else {
            usingBlended = false
            return
        }
        let priorFactor = tuning.priorBlendFactor
        let bigramFactor = 1 - priorFactor
        for i in 0..<26 { blended26[i] = bigramFactor * currentWeights26[i] }
        for (c, p) in prior {
            let lower = Character(String(c).lowercased())
            if let i = BigramEngine.letterIndex(lower) {
                blended26[i] += priorFactor * p
            } else {
                overflowWeights[lower] = priorFactor * p + bigramFactor * fallback
            }
        }
        usingBlended = true
    }

    /// Extract ordered probability weights for a specific row's characters.
    /// Returns an array of floats in the same order as the input characters.
    /// Reads the pre-baked active buffer — no blending math on the hot path.
    ///
    /// - Parameter rowChars: The characters in the row (e.g., ["Q","W","E",...])
    /// - Returns: Array of weights, one per character. Unknown chars get a small default weight.
    func weightsForRow(_ rowChars: [String]) -> [Float] {
        rowChars.map { weight(for: $0.first ?? " ") }
    }

    /// Probability weight P(char | context) for a single character, reading the active
    /// pre-baked buffer. Used by the 2D `ProbabilisticHitResolver`, which scores all
    /// character keys per touch-down. A bounds-checked array read — zero allocations.
    func weight(for char: Character) -> Float {
        let lower = Character(char.lowercased())
        if let i = BigramEngine.letterIndex(lower) {
            return usingBlended ? blended26[i] : currentWeights26[i]
        }
        if usingBlended, let v = overflowWeights[lower] { return v }
        return 1.0 / 26.0
    }
}

#if DEBUG
extension ProbabilisticTouchContext {
    /// Test-only reconstructions of the old dictionary views (never on the hot path).
    var debugCurrentWeights: [Character: Float] {
        var d: [Character: Float] = [:]
        for i in 0..<26 {
            d[Character(UnicodeScalar(UInt8(97 + i)))] = currentWeights26[i]
        }
        return d
    }

    var debugHasBlend: Bool { usingBlended }

    /// Invariant check for the prior pipeline: sharp (un-smoothed) weights, stale-prior
    /// exclusion, double-letter trigram context, and word-boundary snap. Returns the
    /// violations so XCTest can assert; the runtime wrapper logs (does not crash) —
    /// same pattern as `ProbabilisticHitResolver.runEquivalenceSelfTest`.
    static func contextSelfTestFailures() -> [String] {
        var failures: [String] = []
        let ctx = ProbabilisticTouchContext()
        let tuning = ctx.tuning

        // 1. Trigram sharpness: after "t","h" the resolver must see the full "th→e"
        //    boost immediately (no EMA dilution).
        ctx.recordCharacter("t")
        ctx.recordCharacter("h")
        if ctx.weight(for: "e") < 0.5 {
            failures.append("th→e boost diluted: weight(e)=\(ctx.weight(for: "e"))")
        }
        let expectedPeak = ctx.debugCurrentWeights.values.max() ?? 0
        let expectedNorm = min(max((expectedPeak - tuning.confidencePeakLow)
                                   / (tuning.confidencePeakHigh - tuning.confidencePeakLow), 0), 1)
        let expectedConfidence = tuning.minConfidence + expectedNorm * (1 - tuning.minConfidence)
        if abs(ctx.confidence - expectedConfidence) > 0.001 {
            failures.append("confidence lags sharp source: \(ctx.confidence) vs \(expectedConfidence)")
        }

        // 2. Stale English prior is excluded after a keystroke; a fresh one applies
        //    at full strength immediately.
        ctx.updatePredictivePrior(["x": 0.9], isEnglish: true)
        if !ctx.debugHasBlend {
            failures.append("fresh prior did not produce a blend")
        }
        let blendedX = ctx.weight(for: "x")
        let expectedX = tuning.priorBlendFactor * Float(0.9)
            + (1 - tuning.priorBlendFactor) * (ctx.debugCurrentWeights["x"] ?? 1.0 / 26.0)
        if abs(blendedX - expectedX) > 0.001 {
            failures.append("fresh prior under-applied: weight(x)=\(blendedX) expected \(expectedX)")
        }
        ctx.recordCharacter("e")
        if ctx.debugHasBlend {
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
        if ctx2.debugHasBlend || ctx2.debugCurrentWeights != BigramEngine.wordInitialFrequencies {
            failures.append("word boundary did not snap to word-initial")
        }
        return failures
    }

    /// One-time runtime wrapper — logs instead of crashing, keyboard-extension safe.
    static func runContextSelfTest() {
        let failures = contextSelfTestFailures()
        if failures.isEmpty {
            NSLog("[SnipKeyboard] ProbabilisticTouchContext self-test passed")
        } else {
            for f in failures { NSLog("[SnipKeyboard] ProbabilisticTouchContext SELF-TEST FAILED: %@", f) }
        }
    }
}
#endif
