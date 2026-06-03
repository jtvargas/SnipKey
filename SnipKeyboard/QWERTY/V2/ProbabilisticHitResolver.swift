//
//  ProbabilisticHitResolver.swift
//  SnipKeyboard
//
//  The Keyboard V2 next-gen touch resolver. Replaces the legacy 1D boundary-shift
//  (`DynamicHitResolver` / `SmartTouchResolver`) with a true 2D Bayesian posterior whose
//  MAP decision boundary is a POWER (Laguerre) Voronoi diagram over key centers:
//
//      choose k = argmin_k [ ‖t' − c_k′‖²  −  w_k ]
//          w_k  = β · clip(log P(k | context),  min: log(1/V))     // language prior, log-space
//          c_k  = key center + offset(row, hand, user)             // offset correction = moving the site
//          t', c_k′ in σ-normalized space (σx, σy)                 // taller vertical touch scatter
//
//  This unifies the three research threads (Bayesian correction, dynamic Voronoi, offset
//  correction) into one engine. See V2_KEYBOARD_NEXTGEN_PLAN.md §6–§8.
//
//  Safety properties:
//   • Anchor zone — a touch inside a key's central strip ALWAYS keeps that key, regardless of
//     the prior (generalizes the old 60% width clamp; Gunawardana 2010 anchored key-targets).
//   • Anti-swallow — if the argmin winner's center is implausibly far from the touch, fall back
//     to the raw (visually-hit) key so a high-probability key can't capture a distant tap.
//   • Strict superset — at β = 0 and zero offsets with isotropic σ, this is exactly
//     nearest-center selection (the DEBUG self-test asserts this).
//
//  Pure and synchronous. Called once per touch-DOWN (never in touchesMoved). ~30-key argmin,
//  ~150 ns. Character keys only; non-character keys (space/return/shift) are resolved upstream
//  by the hit-grid and never reach here.
//

import UIKit

enum ProbabilisticHitResolver {

    /// Tunable parameters. Defaults are conservative starting points; calibrate `beta`,
    /// `sigmaX/Y`, and the anchor fractions on the touch corpus (plan §11, §14).
    struct Config {
        /// Language weight β = 2σ²λ (a single identifiable scalar — do NOT expose σ and λ
        /// separately). 0 ⇒ pure spatial (nearest-center). Higher ⇒ stronger language pull.
        var beta: Float
        /// Touch-scatter normalization. σy > σx encodes the empirical finding that users
        /// scatter more vertically than horizontally; applied as a coordinate pre-transform
        /// so cells stay convex (shared, not per-key).
        var sigmaX: Float
        var sigmaY: Float
        /// Central anchor strip that always wins, as a fraction of the key's width/height.
        /// e.g. 0.5 / 0.6 ⇒ inner 50%×60% of the key is immune to prior pressure.
        var anchorFracW: CGFloat
        var anchorFracH: CGFloat
        /// Anti-swallow guard: max allowed distance (in σ-normalized units, as a multiple of
        /// the mean normalized key diagonal) from the touch to the winner's center. Beyond
        /// this, fall back to the raw key.
        var maxCaptureDiagonals: Float
        /// Vocabulary size for the log-probability floor `log(1/V)`.
        var vocab: Int

        static let `default` = Config(
            beta: 0,                  // ships OFF-equivalent until calibrated; flag-gated anyway
            sigmaX: 1.0,
            sigmaY: 1.2,
            anchorFracW: 0.5,
            anchorFracH: 0.6,
            maxCaptureDiagonals: 1.5,
            vocab: 30
        )
    }

    /// Resolve a touch-down point to the intended character key.
    ///
    /// - Parameters:
    ///   - rawKey: the visually-hit key from the hit grid (already known to be a character key).
    ///   - point: touch location in keys-area coordinates.
    ///   - frames: all resolved key frames (row-major). Only character keys participate.
    ///   - weightFor: P(char | context) for a character string, e.g. `touchContext.weight(for:)`.
    ///   - offsetFor: per-key site offset in points (population/user touch-offset correction).
    ///     Return `.zero` to disable offset correction.
    ///   - config: tunables.
    /// - Returns: the chosen key frame (may equal `rawKey`).
    static func resolve(
        rawKey: KeyFrame,
        point: CGPoint,
        frames: [KeyFrame],
        weightFor: (String) -> Float,
        offsetFor: (KeyFrame) -> CGVector,
        config: Config
    ) -> KeyFrame {
        // Only correct character-key touches. (Caller already gates, but be defensive.)
        guard rawKey.isCharacterKey else { return rawKey }

        // Anchor zone: a touch within the raw key's central strip is a deliberate, unambiguous
        // hit — never override it with the language prior.
        let anchor = rawKey.rect.insetBy(
            dx: rawKey.rect.width * (1 - config.anchorFracW) / 2,
            dy: rawKey.rect.height * (1 - config.anchorFracH) / 2
        )
        if anchor.contains(point) { return rawKey }

        let invSx = config.sigmaX > 0 ? 1 / config.sigmaX : 1
        let invSy = config.sigmaY > 0 ? 1 / config.sigmaY : 1
        let tx = Float(point.x) * invSx
        let ty = Float(point.y) * invSy

        let logFloor = logf(1.0 / Float(max(config.vocab, 2)))

        var bestScore = Float.greatestFiniteMagnitude
        var best: KeyFrame = rawKey
        var bestDist2: Float = .greatestFiniteMagnitude
        var diagSum: Float = 0
        var charCount: Float = 0

        for f in frames where f.isCharacterKey {
            guard case .character(let c) = f.action else { continue }

            let off = offsetFor(f)
            let cx = Float(f.rect.midX + off.dx) * invSx
            let cy = Float(f.rect.midY + off.dy) * invSy
            let dx = tx - cx
            let dy = ty - cy
            let dist2 = dx * dx + dy * dy

            // w_k = β · clip(log P, floor). High P ⇒ w_k near 0 (small penalty, bigger cell);
            // low P ⇒ w_k strongly negative (large penalty). At β = 0, w_k = 0 ⇒ nearest-center.
            let p = weightFor(c)
            let logp = max(logf(max(p, 1e-6)), logFloor)
            let w = config.beta * logp
            let score = dist2 - w

            if score < bestScore {
                bestScore = score
                best = f
                bestDist2 = dist2
            }

            // Mean normalized key diagonal, for the anti-swallow radius.
            let nd = Float(hypot(f.rect.width, f.rect.height)) * 0.5 * (invSx + invSy)
            diagSum += nd
            charCount += 1
        }

        // Anti-swallow: reject an implausibly distant winner.
        if charCount > 0 {
            let meanDiag = diagSum / charCount
            let maxDist = config.maxCaptureDiagonals * meanDiag
            if sqrtf(bestDist2) > maxDist { return rawKey }
        }

        return best
    }
}

/// Population-prior touch-offset correction — the systematic per-row vertical bias users
/// exhibit when typing (the registered touch centroid is not the key's geometric center).
/// Offsets move the power-diagram SITE (`c_k = center + offset`), independent of the language
/// weight β, so they improve accuracy even with the language prior disabled.
///
/// Expressed as FRACTIONS of key size so they survive rotation / layout / device changes
/// (plan §8). The SIGN and magnitude are device/study-dependent and MUST be calibrated on the
/// touch corpus (plan §11, §14) — so `scale` ships at 0 (no-op) with the literature-derived
/// fractions captured here for calibration. Online per-user/per-region learning is a later tier.
enum PopulationOffset {

    /// Master scale. 0 ⇒ no offset (ships safe). Set to 1 (and confirm the sign) after the
    /// corpus calibration in plan §11.
    static var scale: CGFloat = 0

    /// Upward vertical bias as a fraction of key height, indexed by row band (top→bottom of
    /// the alpha block). Captured from Azenkot & Zhai 2012 (~2/5/8 px on ~44pt keys ⇒
    /// ~0.045 / 0.11 / 0.18). The last value is reused for any extra rows.
    static let verticalFractionByRow: [CGFloat] = [0.045, 0.11, 0.18]

    /// Per-key site offset in points. `.zero` when disabled or for non-character keys.
    static func offset(for frame: KeyFrame) -> CGVector {
        guard scale != 0, frame.isCharacterKey, frame.rowIndex >= 0 else { return .zero }
        let row = min(frame.rowIndex, verticalFractionByRow.count - 1)
        // Negative dy moves the site UP (screen-y grows downward). Final sign is confirmed
        // during calibration; until then `scale == 0` makes this a no-op regardless.
        let dy = -verticalFractionByRow[row] * frame.rect.height * scale
        return CGVector(dx: 0, dy: dy)
    }
}

#if DEBUG
extension ProbabilisticHitResolver {
    /// One-time invariant check: at β = 0, zero offsets, isotropic σ, the engine must reduce to
    /// nearest-center selection. Logs (does not crash in release) if the property is violated.
    /// Invoked once from the gesture coordinator when the engine is first configured.
    static func runEquivalenceSelfTest() {
        // Synthetic single row of 5 equal keys at y = 50, width 40, height 44, gap 6.
        var frames: [KeyFrame] = []
        let w: CGFloat = 40, h: CGFloat = 44, gap: CGFloat = 6, y: CGFloat = 28
        let letters = ["a", "b", "c", "d", "e"]
        var x: CGFloat = 10
        for (i, ch) in letters.enumerated() {
            let rect = CGRect(x: x, y: y, width: w, height: h)
            frames.append(KeyFrame(action: .character(ch), rect: rect, hitRect: rect,
                                   rowIndex: 0, columnIndex: i, isCharacterKey: true))
            x += w + gap
        }
        var cfg = Config.default
        cfg.beta = 0
        cfg.sigmaX = 1; cfg.sigmaY = 1
        cfg.anchorFracW = 0; cfg.anchorFracH = 0   // disable anchor so we test pure argmin

        // Sample points across the row; expect nearest-center each time.
        var failures = 0
        var sx: CGFloat = 0
        while sx < x {
            let pt = CGPoint(x: sx, y: y + h / 2)
            let got = resolve(rawKey: frames[0], point: pt, frames: frames,
                              weightFor: { _ in 0.5 },         // uniform ⇒ irrelevant at β=0
                              offsetFor: { _ in .zero }, config: cfg)
            let nearest = frames.min(by: {
                let d0 = hypot($0.rect.midX - pt.x, $0.rect.midY - pt.y)
                let d1 = hypot($1.rect.midX - pt.x, $1.rect.midY - pt.y)
                return d0 < d1
            })!
            if got.action != nearest.action { failures += 1 }
            sx += 4
        }
        if failures > 0 {
            NSLog("[ProbabilisticHitResolver] EQUIVALENCE SELF-TEST FAILED: \(failures) mismatches at β=0")
        } else {
            NSLog("[ProbabilisticHitResolver] equivalence self-test passed (β=0 ⇒ nearest-center)")
        }
    }
}
#endif
