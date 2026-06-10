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

    /// Full resolver output. `winner` is the key to commit; `runnerUp` is the next-best
    /// geometric/language candidate for telemetry and future word-level hypothesis ranking.
    struct Result {
        let winner: KeyFrame
        let runnerUp: KeyFrame?
        let margin: Float
    }

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
        /// e.g. 0.6 / 0.7 ⇒ inner 60%×70% of the key is immune to prior pressure.
        var anchorFracW: CGFloat
        var anchorFracH: CGFloat
        /// Anti-swallow guard: max allowed distance (in σ-normalized units, as a multiple of
        /// the mean normalized key diagonal) from the touch to the winner's center. Beyond
        /// this, fall back to the raw key.
        var maxCaptureDiagonals: Float
        /// Vocabulary size for the log-probability floor `log(1/V)`.
        var vocab: Int

        /// Research-backed shipping defaults. σ ≈ real thumb touch scatter (~a third of a key,
        /// taller vertically — Azenkot & Zhai 2012, Bi & Zhai 2013). β gives a MODEST language
        /// pull (a strong bigram shifts a boundary only a few points; the anchor zone still
        /// protects deliberate center taps). Conservative on purpose — per-user offset learning
        /// (TouchOffsetModel) does the heavier personalization over time.
        static let `default` = Config(
            beta: 0.35,
            sigmaX: 13,
            sigmaY: 16,
            anchorFracW: 0.6,
            anchorFracH: 0.7,
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
        resolveWithCandidates(
            rawKey: rawKey,
            point: point,
            frames: frames,
            weightFor: weightFor,
            offsetFor: offsetFor,
            config: config
        ).winner
    }

    /// Resolve a touch-down point and keep the runner-up candidate. This has the same hot-path
    /// cost as `resolve` plus one extra score comparison per candidate.
    static func resolveWithCandidates(
        rawKey: KeyFrame,
        point: CGPoint,
        frames: [KeyFrame],
        weightFor: (String) -> Float,
        offsetFor: (KeyFrame) -> CGVector,
        config: Config
    ) -> Result {
        // Only correct character-key touches. (Caller already gates, but be defensive.)
        guard rawKey.isCharacterKey else { return Result(winner: rawKey, runnerUp: nil, margin: 0) }

        // Anchor zone: a touch within the raw key's central strip is a deliberate, unambiguous
        // hit — never override it with the language prior.
        let anchor = rawKey.rect.insetBy(
            dx: rawKey.rect.width * (1 - config.anchorFracW) / 2,
            dy: rawKey.rect.height * (1 - config.anchorFracH) / 2
        )
        if anchor.contains(point) { return Result(winner: rawKey, runnerUp: nil, margin: .greatestFiniteMagnitude) }

        let invSx = config.sigmaX > 0 ? 1 / config.sigmaX : 1
        let invSy = config.sigmaY > 0 ? 1 / config.sigmaY : 1
        let tx = Float(point.x) * invSx
        let ty = Float(point.y) * invSy

        let logFloor = logf(1.0 / Float(max(config.vocab, 2)))

        var bestScore = Float.greatestFiniteMagnitude
        var best: KeyFrame?
        var bestDist2: Float = .greatestFiniteMagnitude
        var secondScore = Float.greatestFiniteMagnitude
        var second: KeyFrame?
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
                secondScore = bestScore
                second = best
                bestScore = score
                best = f
                bestDist2 = dist2
            } else if score < secondScore {
                if let best, f.action == best.action { continue }
                secondScore = score
                second = f
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
            if sqrtf(bestDist2) > maxDist {
                return Result(winner: rawKey, runnerUp: best, margin: max(0, secondScore - bestScore))
            }
        }

        return Result(winner: best ?? rawKey, runnerUp: second, margin: max(0, secondScore - bestScore))
    }
}

extension ProbabilisticHitResolver {

    /// Pure Σ-normalized power-diagram winner over character keys — no anchor zone, no
    /// anti-swallow fallback. For the debug cell visualization only (shows the raw decision
    /// boundary the engine uses). Returns the winning index into `frames`, or -1.
    static func debugWinningIndex(
        point: CGPoint,
        frames: [KeyFrame],
        weightFor: (String) -> Float,
        offsetFor: (KeyFrame) -> CGVector,
        config: Config
    ) -> Int {
        let invSx = config.sigmaX > 0 ? 1 / config.sigmaX : 1
        let invSy = config.sigmaY > 0 ? 1 / config.sigmaY : 1
        let tx = Float(point.x) * invSx
        let ty = Float(point.y) * invSy
        let logFloor = logf(1.0 / Float(max(config.vocab, 2)))
        var best = -1
        var bestScore = Float.greatestFiniteMagnitude
        for (i, f) in frames.enumerated() where f.isCharacterKey {
            guard case .character(let c) = f.action else { continue }
            let off = offsetFor(f)
            let cx = Float(f.rect.midX + off.dx) * invSx
            let cy = Float(f.rect.midY + off.dy) * invSy
            let dx = tx - cx
            let dy = ty - cy
            let w = config.beta * max(logf(max(weightFor(c), 1e-6)), logFloor)
            let score = dx * dx + dy * dy - w
            if score < bestScore { bestScore = score; best = i }
        }
        return best
    }

    /// Rasterize the decision cells over `bounds` into a coarse CGImage (one color per winning
    /// key index). Off the hot path — called only on layout/weight change when the debug
    /// overlay is on. `stepPoints` trades crispness for cost (~6pt ⇒ a few hundred samples).
    static func debugCellImage(
        frames: [KeyFrame],
        bounds: CGRect,
        stepPoints: CGFloat,
        weightFor: (String) -> Float,
        offsetFor: (KeyFrame) -> CGVector,
        config: Config
    ) -> CGImage? {
        let cols = max(Int(bounds.width / stepPoints), 1)
        let rows = max(Int(bounds.height / stepPoints), 1)
        guard let ctx = CGContext(
            data: nil, width: cols, height: rows, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        for ry in 0..<rows {
            for rx in 0..<cols {
                let pt = CGPoint(x: (CGFloat(rx) + 0.5) * stepPoints,
                                 y: (CGFloat(ry) + 0.5) * stepPoints)
                let idx = debugWinningIndex(point: pt, frames: frames,
                                            weightFor: weightFor, offsetFor: offsetFor, config: config)
                guard idx >= 0 else { continue }
                let (r, g, b) = cellColor(idx)
                ctx.setFillColor(red: r, green: g, blue: b, alpha: 0.28)
                // CGContext origin is bottom-left; place view-row `ry` at the top.
                ctx.fill(CGRect(x: rx, y: rows - 1 - ry, width: 1, height: 1))
            }
        }
        return ctx.makeImage()
    }

    /// Distinct, stable per-index color via the golden-ratio hue sequence.
    private static func cellColor(_ index: Int) -> (CGFloat, CGFloat, CGFloat) {
        let hue = (CGFloat(index) * 0.61803398875).truncatingRemainder(dividingBy: 1.0)
        return UIColor(hue: hue, saturation: 0.9, brightness: 1.0, alpha: 1).rgbComponents()
    }
}

private extension UIColor {
    func rgbComponents() -> (CGFloat, CGFloat, CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b)
    }
}

/// Population-prior touch-offset correction — the systematic per-row vertical bias users
/// exhibit when typing (the registered touch centroid is not the key's geometric center).
/// Offsets move the power-diagram SITE (`c_k = center + offset`), independent of the language
/// weight β, so they improve accuracy even with the language prior disabled.
///
/// Expressed as FRACTIONS of key size so they survive rotation / layout / device changes
/// (plan §8). Serves as the COLD-START baseline: `TouchOffsetModel` crossfades it out as the
/// per-user clusters earn trust (`user·trust + population·(1−trust)`), so a fresh install or
/// fresh layout hash starts from the literature bias instead of zero. The DEBUG sign audit in
/// `TouchOffsetModel.fold` validates the sign against fully-trusted learned clusters on-device.
enum PopulationOffset {

    /// Master scale. 1 = literature fractions; 0 = kill switch (no-op).
    static var scale: CGFloat = 1

    /// Downward vertical bias as a fraction of key height, indexed by row band (top→bottom of
    /// the alpha block). Captured from Azenkot & Zhai 2012 (~2/5/8 px on ~44pt keys ⇒
    /// ~0.045 / 0.11 / 0.18). The last value is reused for any extra rows.
    static let verticalFractionByRow: [CGFloat] = [0.045, 0.11, 0.18]

    /// Per-key site offset in points. `.zero` when disabled or for non-character keys.
    static func offset(for frame: KeyFrame) -> CGVector {
        guard scale != 0, frame.isCharacterKey, frame.rowIndex >= 0 else { return .zero }
        let row = min(frame.rowIndex, verticalFractionByRow.count - 1)
        // POSITIVE dy moves the site DOWN (screen-y grows downward) — toward where touch
        // centroids actually land: below the visually-aimed keycap (finger occlusion),
        // increasingly so on lower rows. This matches the learned model's convention —
        // `TouchOffsetModel` folds fy = (point.y − midY)/h (positive = below center) and
        // applies +fy·h, so the baseline it crossfades against must share the sign.
        let dy = verticalFractionByRow[row] * frame.rect.height * scale
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
