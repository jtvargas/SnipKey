//
//  ResolverTuning.swift
//  SnipKeyboard
//
//  Tunables for cadence/fat-touch β modulation and the burst anchor shrink, plus the
//  typing-cadence tracker they drive. Extracted from KeyboardGestureCoordinator (internal,
//  not private) so the calibration replay harness and the unit-test target can sweep and
//  assert these values directly. All modulation composes in the coordinator —
//  `ProbabilisticHitResolver` math is untouched, so the β=0 equivalence self-test keeps
//  holding.
//

import Foundation

/// Grouped so data-driven calibration (shadow telemetry, plan §15) edits one block.
enum ResolverTuning {
    // Typing cadence (EMA over inter-tap intervals, ms).
    static let cadenceAlpha: Double = 0.5          // converges in 2–3 taps — real burst lengths
    static let cadenceMinIntervalMs: Double = 40   // rollover floor: overlap dt ≈ 0 can't max the EMA
    static let cadenceResetGapMs: Double = 800     // a pause longer than this ⇒ cold (deliberate)
    static let cadenceFastKneeMs: Double = 140     // sustained ≤ this ⇒ full fast multiplier
    static let cadenceNeutralKneeMs: Double = 240  // multiplier crosses 1.0 — ordinary typing keeps today's pull
    static let cadenceSlowKneeMs: Double = 450     // ≥ this ⇒ floor (deliberate taps resolve geometrically)
    static let cadenceMultMax: Float = 1.45
    static let cadenceMultMin: Float = 0.35

    // Anchor shrink at full burst: 60%×70% → 50%×60%, linear in the cadence boost above 1.
    // Dead-center taps stay immune (the betaCeiling proof below covers the shrunken floor).
    // Set both to 0 to kill the shrink (static anchor).
    static let anchorShrinkMaxW: CGFloat = 0.10
    static let anchorShrinkMaxH: CGFloat = 0.10

    // Fat touch (UITouch.majorRadius, pt). Uniform σ scaling is argmin-equivalent to a β
    // multiplier (the anchor zone is raw-coords and the anti-swallow ratio is invariant),
    // so it composes as one multiply here instead of touching the resolver. multMax = 1
    // is the kill switch. The simulator reports a constant radius — device-only signal.
    static let fatTouchBaselineRadius: CGFloat = 16
    static let fatTouchMaxRadius: CGFloat = 28
    static let fatTouchMultMax: Float = 1.6

    /// Global clamp on the composed β. Worst-case boundary shift at 0.9 is
    /// βceil·Δlogp/(2d̂) ≈ 0.9·2.7/(2·2.5σ) ≈ 6.2pt — still short of the 8.25pt
    /// half-width protected by the shrunken 50% anchor floor, so even the maximal
    /// multiplier stack can never pull a tap out of the anchor.
    static let betaCeiling: Float = 0.9

    /// 1.0 for fingertip-sized contacts (≤ baseline), linear up to `fatTouchMultMax` at
    /// `fatTouchMaxRadius`. Pure — self-testable.
    static func fatTouchBetaMultiplier(radius: CGFloat) -> Float {
        guard fatTouchMultMax > 1 else { return 1 }  // kill switch
        guard radius > fatTouchBaselineRadius else { return 1 }
        let t = min((radius - fatTouchBaselineRadius) / (fatTouchMaxRadius - fatTouchBaselineRadius), 1)
        return 1 + Float(t) * (fatTouchMultMax - 1)
    }
}

/// Typing-cadence tracker: an EMA over inter-tap intervals. Two stored values, zero
/// allocations, updated once per touch-down from `UITouch.timestamp` (event time on the
/// `CACurrentMediaTime` clock — immune to main-thread delivery jitter).
struct KeyboardCadenceTracker {
    /// Smoothed inter-tap interval in ms. 0 = cold (session start or post-pause): the
    /// next tap is treated as deliberate.
    private(set) var emaMs: Double = 0
    private var lastTimestamp: TimeInterval = 0

    mutating func registerTouchDown(at t: TimeInterval) {
        defer { lastTimestamp = t }
        guard lastTimestamp > 0 else { return }
        let dtMs = (t - lastTimestamp) * 1000
        guard dtMs >= 0 else { return }  // defensive: out-of-order event timestamps
        if dtMs > ResolverTuning.cadenceResetGapMs {
            emaMs = 0
            return
        }
        // Rolling-type overlap delivers near-zero dt between fingers — floor it so a
        // single overlap can't max out the multiplier.
        let clamped = max(dtMs, ResolverTuning.cadenceMinIntervalMs)
        emaMs = emaMs == 0 ? clamped : emaMs + ResolverTuning.cadenceAlpha * (clamped - emaMs)
    }

    /// β multiplier for the current cadence. Piecewise linear, monotone non-increasing:
    /// sustained fast bursts lean harder on the language prior; slow deliberate taps
    /// resolve almost purely geometrically (native feel). Pure — self-testable.
    static func betaMultiplier(forEmaMs ema: Double) -> Float {
        guard ema > 0 else { return ResolverTuning.cadenceMultMin }  // cold ⇒ deliberate
        let fast = ResolverTuning.cadenceFastKneeMs
        let neutral = ResolverTuning.cadenceNeutralKneeMs
        let slow = ResolverTuning.cadenceSlowKneeMs
        if ema <= fast { return ResolverTuning.cadenceMultMax }
        if ema < neutral {
            let t = Float((ema - fast) / (neutral - fast))
            return ResolverTuning.cadenceMultMax + t * (1 - ResolverTuning.cadenceMultMax)
        }
        if ema < slow {
            let t = Float((ema - neutral) / (slow - neutral))
            return 1 + t * (ResolverTuning.cadenceMultMin - 1)
        }
        return ResolverTuning.cadenceMultMin
    }
}

#if DEBUG
extension KeyboardCadenceTracker {
    /// Invariant check for the cadence/fat-touch β modulation (ResolverTuning): curve
    /// bounds, monotonicity, the neutral crossing, EMA seeding/reset behavior, the
    /// composed worst case vs `betaCeiling`, and the anchor-shrink floor. Returns the
    /// violations so XCTest can assert; the runtime wrapper logs (does not crash) —
    /// same pattern as `ProbabilisticHitResolver.runEquivalenceSelfTest`.
    static func cadenceSelfTestFailures() -> [String] {
        var failures: [String] = []

        // Multiplier curve: clamped to [multMin, multMax] and monotone non-increasing.
        var prev = KeyboardCadenceTracker.betaMultiplier(forEmaMs: 1)
        var ema: Double = 1
        while ema <= 10_000 {
            let m = KeyboardCadenceTracker.betaMultiplier(forEmaMs: ema)
            if m < ResolverTuning.cadenceMultMin - 0.0001 || m > ResolverTuning.cadenceMultMax + 0.0001 {
                failures.append("multiplier out of bounds at \(ema)ms: \(m)")
                break
            }
            if m > prev + 0.0001 {
                failures.append("multiplier not monotone non-increasing at \(ema)ms")
                break
            }
            prev = m
            ema += 5
        }
        if KeyboardCadenceTracker.betaMultiplier(forEmaMs: 0) != ResolverTuning.cadenceMultMin {
            failures.append("cold cadence is not the deliberate floor")
        }
        if abs(KeyboardCadenceTracker.betaMultiplier(forEmaMs: ResolverTuning.cadenceNeutralKneeMs) - 1) > 0.001 {
            failures.append("neutral knee does not cross 1.0")
        }

        // EMA tracker: seeds on second tap, floors rollover dt, resets after a long pause.
        var tracker = KeyboardCadenceTracker()
        tracker.registerTouchDown(at: 10.0)
        tracker.registerTouchDown(at: 10.1)              // dt = 100ms seeds the EMA
        if abs(tracker.emaMs - 100) > 0.001 { failures.append("EMA did not seed at first interval") }
        tracker.registerTouchDown(at: 10.101)            // dt = 1ms → floored to 40ms
        if tracker.emaMs < ResolverTuning.cadenceMinIntervalMs - 0.001 {
            failures.append("rollover overlap drove EMA below the floor")
        }
        tracker.registerTouchDown(at: 20.0)              // pause ≫ reset gap → cold
        if tracker.emaMs != 0 { failures.append("long pause did not reset the EMA") }

        // Fat-touch: neutral at/below baseline, capped at max radius, never above the cap.
        if ResolverTuning.fatTouchBetaMultiplier(radius: 0) != 1 { failures.append("fat mult ≠ 1 at radius 0") }
        if ResolverTuning.fatTouchBetaMultiplier(radius: ResolverTuning.fatTouchBaselineRadius) != 1 {
            failures.append("fat mult ≠ 1 at baseline radius")
        }
        if abs(ResolverTuning.fatTouchBetaMultiplier(radius: ResolverTuning.fatTouchMaxRadius) - ResolverTuning.fatTouchMultMax) > 0.001 {
            failures.append("fat mult cap wrong at max radius")
        }
        if ResolverTuning.fatTouchBetaMultiplier(radius: 100) > ResolverTuning.fatTouchMultMax + 0.0001 {
            failures.append("fat mult exceeds its cap")
        }

        // Composed worst case (confidence 1 × cadence max × fat max) must respect the
        // ceiling without relying on the clamp, and the anchor floor must hold so the
        // betaCeiling shift proof in ResolverTuning stays valid.
        let worst = ProbabilisticHitResolver.Config.default.beta
            * ResolverTuning.cadenceMultMax * ResolverTuning.fatTouchMultMax
        if worst > ResolverTuning.betaCeiling {
            failures.append("composed worst-case β \(worst) exceeds ceiling \(ResolverTuning.betaCeiling)")
        }
        if ProbabilisticHitResolver.Config.default.anchorFracW - ResolverTuning.anchorShrinkMaxW < 0.499 {
            failures.append("anchor width floor below 50%")
        }
        if ProbabilisticHitResolver.Config.default.anchorFracH - ResolverTuning.anchorShrinkMaxH < 0.599 {
            failures.append("anchor height floor below 60%")
        }
        return failures
    }

    /// One-time runtime wrapper — logs instead of crashing, keyboard-extension safe.
    static func runCadenceSelfTest() {
        let failures = cadenceSelfTestFailures()
        if failures.isEmpty {
            NSLog("[SnipKeyboard] cadence/fat-touch self-test passed")
        } else {
            for f in failures { NSLog("[SnipKeyboard] cadence/fat-touch SELF-TEST FAILED: %@", f) }
        }
    }
}
#endif
