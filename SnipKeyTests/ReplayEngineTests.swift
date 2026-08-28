//
//  ReplayEngineTests.swift
//  SnipKeyTests
//
//  The calibration replay harness must be deterministic (same session + variant ⇒
//  identical decisions) and its resolver-independent labeling must behave as specified
//  before any parameter sweep can be trusted.
//

import XCTest
@testable import SnipKey

@MainActor
final class ReplayEngineTests: XCTestCase {

    private func makeHeader() -> CalibrationCapture.SessionHeader {
        let dims = KeyboardDimensions(screenWidth: 393)
        return CalibrationCapture.SessionHeader(
            capturedAtEpoch: 0,
            screenWidth: 393,
            keysW: 393,
            keysH: Double(dims.keysAreaHeight),
            profile: "standard",
            layoutHash: 1,
            config: .default,
            tuning: .current,
            contextTuning: .current,
            populationScale: 1,
            clusters: nil,
            nativeCommitTiming: true
        )
    }

    private func makeSession() -> CalibrationCapture.Session {
        let header = makeHeader()
        let frames = ResolverReplayEngine.frames(for: header)
        XCTAssertFalse(frames.isEmpty, "layout reconstruction produced no frames")

        func key(_ ch: String) -> KeyFrame {
            frames.first { $0.action == .character(ch) }!
        }

        var taps: [CalibrationCapture.TapRecord] = []
        var t = 1000.0
        func record(_ frame: KeyFrame, action: String, dx: Double = 0, dy: Double = 0) {
            taps.append(CalibrationCapture.TapRecord(
                tMs: t,
                x: Double(frame.rect.midX) + dx,
                y: Double(frame.rect.midY) + dy,
                radius: 16,
                rawRow: frame.rowIndex, rawCol: frame.columnIndex,
                actingRow: frame.rowIndex, actingCol: frame.columnIndex,
                action: action,
                confidence: 0.35,
                prior: nil, priorFresh: false, priorIsEnglish: true
            ))
            t += 200
        }

        // Clean center taps: "the" — unambiguous labels.
        record(key("T"), action: "c:t")
        record(key("H"), action: "c:h")
        record(key("E"), action: "c:e")
        // Boundary mis-tap: acting "r", backspaced, retyped near the same spot as "t".
        // The retype gives tap #3 the adversarial label "t".
        let r = key("R")
        record(r, action: "c:r", dx: Double(r.rect.width) * 0.45)
        let bsp = frames.first { $0.action == .backspace }!
        record(bsp, action: "backspace")
        let tKey = key("T")
        record(tKey, action: "c:t", dx: -Double(tKey.rect.width) * 0.45)
        // Survivor tap after the retype (not a backspace) so the label sticks.
        let space = frames.first { $0.action == .space }!
        record(space, action: "space")

        return CalibrationCapture.Session(header: header, taps: taps)
    }

    func testLabelsFromGeometryAndBackspaceRetype() {
        let session = makeSession()
        let frames = ResolverReplayEngine.frames(for: session.header)
        let labels = ResolverReplayEngine.labels(for: session, frames: frames)

        // Center taps label themselves.
        XCTAssertEqual(labels[0], "t")
        XCTAssertEqual(labels[1], "h")
        XCTAssertEqual(labels[2], "e")
        // The backspaced-and-retyped boundary tap is labeled with the retyped char.
        XCTAssertEqual(labels[3], "t")
        // The retype tap itself may carry an unambiguous label but never a retype label.
        XCTAssertNil(labels[4], "backspace taps are never labeled")
    }

    func testReplayIsDeterministic() {
        let session = makeSession()
        let baseline = ResolverReplayEngine.Variant.baseline(of: session.header)
        let a = ResolverReplayEngine.replay(session: session, variant: baseline)
        let b = ResolverReplayEngine.replay(session: session, variant: baseline)
        XCTAssertEqual(a, b, "same session + variant must produce identical metrics")
        XCTAssertEqual(a.charTaps, 5)
        XCTAssertGreaterThanOrEqual(a.labeled, 4)
        // Dead-center taps must resolve to their own key under any sane config.
        XCTAssertGreaterThanOrEqual(a.top1Correct, 3)
    }

    func testSweepIncludesBaselineAndSignVariants() {
        let session = makeSession()
        let base = ResolverReplayEngine.Variant.baseline(of: session.header)
        let variants = ResolverReplayEngine.standardSweep(around: base)
        XCTAssertTrue(variants.contains { $0.name == "baseline" })
        XCTAssertTrue(variants.contains { $0.name == "popScale=0" })
        XCTAssertTrue(variants.contains { $0.name == "popScale=-1" })
        let metrics = ResolverReplayEngine.sweep(sessions: [session], variants: variants)
        XCTAssertEqual(metrics.count, variants.count)
    }
}
