//
//  SyntheticResolverSuiteTests.swift
//  SnipKeyTests
//
//  The plan-§11 synthetic suites, run against the real layout + the full composed
//  resolver: boundary rescue under burst ("the…"), deliberate rare-char immunity
//  ("zxq" at slow cadence), burst-anchor immunity ("asdf" alternation), corner-key
//  guarantees, and non-character ineligibility. These lock the engine's BEHAVIORAL
//  invariants, complementing the equivalence/curve self-tests.
//

import XCTest
@testable import SnipKey

final class SyntheticResolverSuiteTests: XCTestCase {

    private var frames: [KeyFrame] = []

    override func setUp() {
        super.setUp()
        let dims = KeyboardDimensions(screenWidth: 393)
        let layout = KeyboardLayoutFactory.layout(for: .letters, profile: .standard, dims: dims)
        frames = KeyboardLayoutResolver.resolve(
            layout: layout, dims: dims,
            keysAreaSize: CGSize(width: 393, height: dims.keysAreaHeight)
        )
        XCTAssertFalse(frames.isEmpty)
    }

    private func key(_ s: String) -> KeyFrame {
        frames.first { $0.action == .character(s) }!
    }

    private func rawKey(at point: CGPoint) -> KeyFrame {
        frames.first { $0.hitRect.contains(point) } ?? frames[0]
    }

    private func resolve(
        point: CGPoint,
        context: ProbabilisticTouchContext,
        emaMs: Double,
        radius: CGFloat = 0,
        beta: Float? = nil
    ) -> KeyFrame {
        var base = ProbabilisticHitResolver.Config.default
        if let beta { base.beta = beta }
        let raw = rawKey(at: point)
        let cfg = ResolverTuning.current.composedConfig(
            base: base,
            confidence: context.confidence,
            cadenceEmaMs: emaMs,
            touchRadius: radius
        )
        let candidates = frames.filter {
            $0.isCharacterKey && abs($0.rowIndex - raw.rowIndex) <= 1
        }
        return ProbabilisticHitResolver.resolveWithCandidates(
            rawKey: raw,
            point: point,
            frames: candidates,
            weightFor: { context.weight(for: $0.first ?? " ") },
            offsetFor: { _ in .zero },
            config: cfg
        ).winner
    }

    private func legacyContext(_ chars: String...) -> ProbabilisticTouchContext {
        let ctx = ProbabilisticTouchContext(tuning: ContextTuning(useCorpusTrigram: false))
        for s in chars { for c in s { ctx.recordCharacter(c) } }
        return ctx
    }

    /// "the" boundary stress: after "th", a burst tap just barely inside R at the E|R
    /// seam is rescued to E by the prior — and stays R at β = 0 (pure geometry).
    func testBoundaryRescueAfterTH() {
        let ctx = legacyContext("th")
        let e = key("E"), r = key("R")
        let seam = (e.hitRect.maxX + r.hitRect.minX) / 2
        let point = CGPoint(x: seam + 1, y: r.rect.midY)
        XCTAssertEqual(rawKey(at: point).action, .character("R"), "test setup: raw must be R")

        let rescued = resolve(point: point, context: ctx, emaMs: 100)  // burst
        XCTAssertEqual(rescued.action, .character("E"), "prior should rescue a seam-grazing tap after 'th'")

        let geometric = resolve(point: point, context: ctx, emaMs: 100, beta: 0)
        XCTAssertEqual(geometric.action, .character("R"), "β=0 must stay pure geometry")
    }

    /// "zxq" deliberate rare characters: dead-center taps at slow cadence must resolve raw
    /// no matter how unlikely the letter is in context.
    func testDeliberateRareCharsResolveRaw() {
        let ctx = legacyContext("zx")  // q after "zx" is wildly unlikely
        for name in ["Q", "Z", "X"] {
            let k = key(name)
            let center = CGPoint(x: k.rect.midX, y: k.rect.midY)
            let winner = resolve(point: center, context: ctx, emaMs: 600)  // deliberate
            XCTAssertEqual(winner.action, k.action, "dead-center \(name) must never be overridden")
        }
    }

    /// "asdfasdf" burst alternation: even at full burst (shrunken anchor), dead-center
    /// taps stay immune.
    func testBurstAnchorImmunityAtDeadCenter() {
        let ctx = legacyContext("asdfasd")
        for name in ["A", "S", "D", "F"] {
            let k = key(name)
            let center = CGPoint(x: k.rect.midX, y: k.rect.midY)
            let winner = resolve(point: center, context: ctx, emaMs: 80, radius: 28)  // max burst + fat touch
            XCTAssertEqual(winner.action, k.action, "burst anchor shrink must not expose dead-center \(name)")
        }
    }

    /// Corner keys: center taps on the alpha block's corner keys resolve to themselves
    /// under any context.
    func testCornerKeyCenterGuarantee() {
        let ctx = legacyContext("th")  // strong pull toward E
        for name in ["Q", "P", "Z", "M"] {
            let k = key(name)
            let center = CGPoint(x: k.rect.midX, y: k.rect.midY)
            XCTAssertEqual(resolve(point: center, context: ctx, emaMs: 100).action, k.action)
        }
    }

    /// Non-character keys never reach the engine's correction math — the defensive guard
    /// returns them untouched even if a caller slipped one through.
    func testNonCharacterKeysAreIneligible() {
        let space = frames.first { $0.action == .space }!
        let result = ProbabilisticHitResolver.resolveWithCandidates(
            rawKey: space,
            point: CGPoint(x: space.rect.midX, y: space.rect.midY),
            frames: frames,
            weightFor: { _ in 1.0 },
            offsetFor: { _ in .zero },
            config: .default
        )
        XCTAssertEqual(result.winner.action, .space)
        XCTAssertNil(result.runnerUp)
    }

    /// Equivalence re-proof against whatever Config.default currently ships (guards
    /// future calibration edits): β=0 + zero offsets + isotropic σ ⇒ nearest-center.
    func testEquivalenceHoldsForShippingConfig() {
        XCTAssertEqual(
            ProbabilisticHitResolver.equivalenceSelfTestFailures(base: .default), [])
    }
}
