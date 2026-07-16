//
//  ResolverSelfTests.swift
//  SnipKeyTests
//
//  XCTest ports of the four DEBUG runtime self-tests that guard the V2 touch engine.
//  Each self-test exposes a `...Failures() -> [String]` variant; the extension still
//  runs the logging wrappers once per session, so the invariants are enforced both in
//  CI (here, hard assert) and on-device (log-only).
//

import XCTest
@testable import SnipKey

final class ResolverSelfTests: XCTestCase {

    /// At β = 0, zero offsets, isotropic σ, the power-diagram resolver must reduce to
    /// exact nearest-center selection.
    func testEquivalenceAtBetaZero() {
        XCTAssertEqual(ProbabilisticHitResolver.equivalenceSelfTestFailures(), [])
    }

    /// Prior pipeline invariants: sharp weights, stale-prior exclusion, double-letter
    /// trigram context, word-boundary snap.
    func testTouchContextInvariants() {
        XCTAssertEqual(ProbabilisticTouchContext.contextSelfTestFailures(), [])
    }

    /// Cadence/fat-touch β modulation: curve bounds, monotonicity, neutral crossing,
    /// EMA seeding/reset, composed worst case vs betaCeiling, anchor-shrink floor.
    func testCadenceAndFatTouchCurves() {
        XCTAssertEqual(KeyboardCadenceTracker.cadenceSelfTestFailures(), [])
    }

    /// Population/user offset crossfade: pure population cold start, pure user at full
    /// trust, exact midpoint at half trust, bounded output, population sign lock.
    @MainActor
    func testOffsetCrossfade() {
        XCTAssertEqual(TouchOffsetModel.crossfadeSelfTestFailures(), [])
    }

    /// Press-phase state machine: initial phase per action under native + legacy commit
    /// timing, slide-retarget mapping, gold-label plausibility gate.
    @MainActor
    func testCommitPhaseTables() {
        XCTAssertEqual(KeyboardGestureCoordinator.commitPhaseSelfTestFailures(), [])
    }

    /// Word-tier backspace chunk math (whitespace run + word, grapheme-safe, clamped).
    @MainActor
    func testWordDeletionChunk() {
        XCTAssertEqual(KeyboardCommitPipeline.wordDeleteSelfTestFailures(), [])
    }
}
