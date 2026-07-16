//
//  ResolverReplayEngine.swift
//  SnipKeyboard
//
//  Offline replay of captured calibration sessions (plan §11): re-runs every captured tap
//  through the FULL resolver stack — cadence EMA, context/prior rebuild, composedConfig,
//  power-diagram argmin, offset crossfade — under arbitrary parameter variants, without
//  retyping anything. Pure and deterministic: the same session + variant always produces
//  identical decisions, and the baseline variant (the session header's own parameters)
//  must reproduce the live acting decisions bit-exact (the harness gate).
//
//  Labels are resolver-independent, derived purely from the captured stream:
//   • unambiguous taps — clearly nearest one key center (margin ≥ 40% key width) ⇒ label
//     is that key (clean, uncontroversial);
//   • backspace-retype pairs — tap X, backspace, tap Y near the same spot that survives
//     ⇒ the original tap is labeled Y (the adversarial boundary cases that matter most).
//
//  DEBUG-only: compiled into both targets but only reachable from the host app's
//  Calibration Lab and the unit tests.
//

#if DEBUG
import UIKit

enum ResolverReplayEngine {

    // MARK: - Variants

    /// One parameter set to evaluate. `baseline(of:)` reproduces the capture session's
    /// own parameters (the determinism gate).
    struct Variant: Equatable {
        var name: String
        var config: ProbabilisticHitResolver.Config
        var tuning: ResolverTuning
        var contextTuning: ContextTuning
        var populationScale: CGFloat

        static func baseline(of header: CalibrationCapture.SessionHeader) -> Variant {
            Variant(name: "baseline",
                    config: header.config,
                    tuning: header.tuning,
                    contextTuning: header.contextTuning,
                    populationScale: CGFloat(header.populationScale))
        }
    }

    // MARK: - Metrics

    struct Metrics: Equatable {
        var name = ""
        /// Eligible character taps replayed.
        var charTaps = 0
        /// Taps whose replayed decision equals the captured acting decision. For the
        /// baseline variant this must equal `charTaps` (bit-exact reproduction).
        var matchedActing = 0
        var labeled = 0
        var top1Correct = 0
        /// Raw key ≠ label but the variant chose the label — the engine earned its keep.
        var rescues = 0
        /// Raw key == label but the variant overrode it — the number that must never rise.
        var harms = 0
        var anchorHits = 0
        /// Labeled taps split by typing regime (cadence multiplier ≤ 1 = deliberate/slow).
        var slowLabeled = 0
        var slowCorrect = 0
        var fastLabeled = 0
        var fastCorrect = 0

        var accuracy: Double { labeled > 0 ? Double(top1Correct) / Double(labeled) : 0 }
        var harmRate: Double { labeled > 0 ? Double(harms) / Double(labeled) : 0 }
        var rescueRate: Double { labeled > 0 ? Double(rescues) / Double(labeled) : 0 }
        var actingMatchRate: Double { charTaps > 0 ? Double(matchedActing) / Double(charTaps) : 0 }
        var slowAccuracy: Double { slowLabeled > 0 ? Double(slowCorrect) / Double(slowLabeled) : 0 }
    }

    // MARK: - Layout reconstruction

    /// Rebuild the letters-page key frames the session was captured against.
    static func frames(for header: CalibrationCapture.SessionHeader) -> [KeyFrame] {
        let dims = KeyboardDimensions(screenWidth: CGFloat(header.screenWidth))
        let layout = KeyboardLayoutFactory.layout(
            for: .letters,
            profile: profile(named: header.profile),
            dims: dims
        )
        return KeyboardLayoutResolver.resolve(
            layout: layout,
            dims: dims,
            keysAreaSize: CGSize(width: header.keysW, height: header.keysH)
        )
    }

    static func profile(named name: String) -> KeyboardLayoutProfile {
        switch name {
        case "asciiCapable": .asciiCapable
        case "emailAddress": .emailAddress
        case "url": .url
        case "webSearch": .webSearch
        case "twitter": .twitter
        default: .standard
        }
    }

    // MARK: - Labels (resolver-independent, pure)

    /// index-into-taps → intended character. Backspace-retype labels override
    /// unambiguous-tap labels (they are the adversarial cases).
    static func labels(for session: CalibrationCapture.Session, frames: [KeyFrame]) -> [Int: Character] {
        var result: [Int: Character] = [:]
        let charKeys = frames.filter(\.isCharacterKey)
        guard !charKeys.isEmpty else { return result }
        let taps = session.taps

        func committedChar(_ record: CalibrationCapture.TapRecord) -> Character? {
            guard record.action.hasPrefix("c:") || record.action.hasPrefix("cx:") else { return nil }
            return record.action.last
        }

        // 1. Unambiguous taps: nearest char-key center wins by ≥ 40% of a key width over
        //    the runner-up — no resolver could reasonably disagree; label = nearest key.
        for (i, tap) in taps.enumerated() where committedChar(tap) != nil {
            let p = CGPoint(x: tap.x, y: tap.y)
            var best: (KeyFrame, CGFloat)? = nil
            var second: CGFloat = .greatestFiniteMagnitude
            for f in charKeys {
                let d = hypot(f.rect.midX - p.x, f.rect.midY - p.y)
                if d < (best?.1 ?? .greatestFiniteMagnitude) {
                    second = best?.1 ?? .greatestFiniteMagnitude
                    best = (f, d)
                } else if d < second {
                    second = d
                }
            }
            if let (frame, d) = best, second - d >= frame.rect.width * 0.4,
               case .character(let c) = frame.action, let ch = c.lowercased().first {
                result[i] = ch
            }
        }

        // 2. Backspace-retype pairs: tap i committed X, tap i+1 backspaced it, tap i+2
        //    committed Y near the same spot and survived (i+3 isn't a backspace) ⇒ the
        //    user meant Y at tap i.
        for i in 0..<taps.count {
            guard let _ = committedChar(taps[i]) else { continue }
            guard i + 2 < taps.count, taps[i + 1].action == "backspace",
                  let retyped = committedChar(taps[i + 2]) else { continue }
            if i + 3 < taps.count, taps[i + 3].action == "backspace" { continue }
            let d = hypot(taps[i].x - taps[i + 2].x, taps[i].y - taps[i + 2].y)
            let keyW = charKeys[0].rect.width
            guard d < keyW * 0.9 else { continue }  // same-spot retype, not a rewrite
            result[i] = Character(String(retyped).lowercased())
        }
        return result
    }

    // MARK: - Replay

    static func replay(session: CalibrationCapture.Session, variant: Variant) -> Metrics {
        var metrics = Metrics()
        metrics.name = variant.name

        let frames = Self.frames(for: session.header)
        guard !frames.isEmpty else { return metrics }
        var frameByGrid: [Int: KeyFrame] = [:]
        for f in frames { frameByGrid[f.rowIndex * 100 + f.columnIndex] = f }
        let rowCount = (frames.map(\.rowIndex).max() ?? 0) + 1
        let keyboardWidth = CGFloat(session.header.keysW)
        let labelMap = Self.labels(for: session, frames: frames)

        var cadence = KeyboardCadenceTracker(tuning: variant.tuning)
        let context = ProbabilisticTouchContext(tuning: variant.contextTuning)
        let clusters = session.header.clusters

        func offsetFor(_ frame: KeyFrame) -> CGVector {
            TouchOffsetModel.computeOffset(
                clusters: clusters,
                frame: frame,
                keyboardWidth: keyboardWidth,
                rowCount: rowCount,
                population: PopulationOffset.offset(for: frame, scale: variant.populationScale)
            )
        }

        for (i, tap) in session.taps.enumerated() {
            cadence.registerTouchDown(at: tap.tMs / 1000)

            // Reinstate the predictive-prior state this tap's resolution saw. A stale
            // ENGLISH prior is excluded from the blend (same as live); a non-English
            // prior applies regardless of freshness.
            if let prior = tap.prior, tap.priorFresh || !tap.priorIsEnglish {
                var dict: [Character: Float] = [:]
                for (k, v) in prior where !k.isEmpty { dict[k.first!] = v }
                context.updatePredictivePrior(dict, isEnglish: tap.priorIsEnglish)
            } else {
                context.updatePredictivePrior(nil, isEnglish: true)
            }

            // Resolve eligible character taps ("c:x"); "cx:x" taps commit but were resolved
            // by the legacy path live, so they replay context-only.
            if tap.action.hasPrefix("c:"),
               let rawKey = frameByGrid[tap.rawRow * 100 + tap.rawCol],
               rawKey.isCharacterKey {
                let point = CGPoint(x: tap.x, y: tap.y)
                let cfg = variant.tuning.composedConfig(
                    base: variant.config,
                    confidence: context.confidence,
                    cadenceEmaMs: cadence.emaMs,
                    touchRadius: CGFloat(tap.radius)
                )
                let candidates = frames.filter {
                    $0.isCharacterKey && abs($0.rowIndex - rawKey.rowIndex) <= 1
                }
                let result = ProbabilisticHitResolver.resolveWithCandidates(
                    rawKey: rawKey,
                    point: point,
                    frames: candidates,
                    weightFor: { context.weight(for: $0.first ?? " ") },
                    offsetFor: offsetFor,
                    config: cfg
                )
                metrics.charTaps += 1
                if result.margin == .greatestFiniteMagnitude { metrics.anchorHits += 1 }
                if result.winner.rowIndex == tap.actingRow && result.winner.columnIndex == tap.actingCol {
                    metrics.matchedActing += 1
                }
                if let label = labelMap[i], case .character(let winC) = result.winner.action,
                   case .character(let rawC) = rawKey.action {
                    let win = Character(winC.lowercased())
                    let raw = Character(rawC.lowercased())
                    metrics.labeled += 1
                    let correct = (win == label)
                    if correct { metrics.top1Correct += 1 }
                    if raw != label && correct { metrics.rescues += 1 }
                    if raw == label && !correct { metrics.harms += 1 }
                    let slow = variant.tuning.cadenceBetaMultiplier(forEmaMs: cadence.emaMs) <= 1
                    if slow {
                        metrics.slowLabeled += 1
                        if correct { metrics.slowCorrect += 1 }
                    } else {
                        metrics.fastLabeled += 1
                        if correct { metrics.fastCorrect += 1 }
                    }
                }
            }

            // Advance the context with what actually committed (the acting stream — the
            // document the user produced), mirroring the live pipeline's record calls.
            switch true {
            case tap.action.hasPrefix("c:"), tap.action.hasPrefix("cx:"):
                if let ch = tap.action.last { context.recordCharacter(ch) }
            case tap.action == "space", tap.action == "backspace",
                 tap.action == "return", tap.action == "text":
                context.recordNonCharacter()
            default:
                break  // shift / mode / other — no context effect, same as live
            }
        }
        return metrics
    }

    // MARK: - Sweep

    /// Coordinate-wise sweep around a base variant: each parameter varied independently,
    /// plus the sign-question PopulationOffset variants. Small enough to run on-device in
    /// well under a second for a few thousand taps.
    static func standardSweep(around base: Variant) -> [Variant] {
        var variants: [Variant] = [base]

        for beta: Float in [0, 0.2, 0.5, 0.7] where beta != base.config.beta {
            var v = base; v.config.beta = beta; v.name = "β=\(beta)"; variants.append(v)
        }
        for sy: Float in [13, 20] where sy != base.config.sigmaY {
            var v = base; v.config.sigmaY = sy; v.name = "σy=\(sy)"; variants.append(v)
        }
        for sx: Float in [10, 16] where sx != base.config.sigmaX {
            var v = base; v.config.sigmaX = sx; v.name = "σx=\(sx)"; variants.append(v)
        }
        for (aw, ah): (CGFloat, CGFloat) in [(0.5, 0.6), (0.7, 0.8)]
        where aw != base.config.anchorFracW {
            var v = base
            v.config.anchorFracW = aw; v.config.anchorFracH = ah
            v.name = "anchor=\(aw)×\(ah)"; variants.append(v)
        }
        for blend: Float in [0.30, 0.60] where blend != base.contextTuning.priorBlendFactor {
            var v = base; v.contextTuning.priorBlendFactor = blend
            v.name = "blend=\(blend)"; variants.append(v)
        }
        for scale: CGFloat in [-1, 0, 1] where scale != base.populationScale {
            var v = base; v.populationScale = scale
            v.name = "popScale=\(scale > 0 ? "+1" : scale == 0 ? "0" : "-1")"; variants.append(v)
        }
        for mult: Float in [1.0, 1.3] where mult != base.tuning.fatTouchMultMax {
            var v = base; v.tuning.fatTouchMultMax = mult
            v.name = "fatMax=\(mult)"; variants.append(v)
        }
        // Cadence knees ±30%.
        for factor in [0.7, 1.3] {
            var v = base
            v.tuning.cadenceFastKneeMs = base.tuning.cadenceFastKneeMs * factor
            v.tuning.cadenceNeutralKneeMs = base.tuning.cadenceNeutralKneeMs * factor
            v.tuning.cadenceSlowKneeMs = base.tuning.cadenceSlowKneeMs * factor
            v.name = "knees×\(factor)"; variants.append(v)
        }
        return variants
    }

    /// Replay every variant over every session and merge per-variant metrics.
    static func sweep(sessions: [CalibrationCapture.Session], variants: [Variant]) -> [Metrics] {
        variants.map { variant in
            var merged = Metrics()
            merged.name = variant.name
            for session in sessions {
                let m = replay(session: session, variant: variant)
                merged.charTaps += m.charTaps
                merged.matchedActing += m.matchedActing
                merged.labeled += m.labeled
                merged.top1Correct += m.top1Correct
                merged.rescues += m.rescues
                merged.harms += m.harms
                merged.anchorHits += m.anchorHits
                merged.slowLabeled += m.slowLabeled
                merged.slowCorrect += m.slowCorrect
                merged.fastLabeled += m.fastLabeled
                merged.fastCorrect += m.fastCorrect
            }
            return merged
        }
    }
}
#endif
