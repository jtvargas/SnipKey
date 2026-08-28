//
//  CalibrationCapture.swift
//  SnipKeyboard
//
//  Full-fidelity touch capture for the offline calibration replay harness (plan §11/§15).
//  Unlike `TypingTelemetry` (privacy-safe, deliberately lossy), a calibration session
//  records exact tap geometry, the committed action, and the predictive-prior snapshot —
//  everything `ResolverReplayEngine` needs to re-run the full resolver stack under any
//  Config/ResolverTuning/ContextTuning/PopulationOffset variant, bit-exact.
//
//  DEBUG-only and OFF by default (`calibrationCaptureEnabled`); RELEASE-locked off. It
//  records the developer's own scripted typing on their own device. Offset learning is
//  frozen while capturing so the session-header cluster snapshot stays valid for the
//  whole session.
//

#if DEBUG
import UIKit

@MainActor
final class CalibrationCapture {

    static let shared = CalibrationCapture()
    private init() {}

    /// One captured touch-down. `action` encodes the ACTING commit: "c:x" for character
    /// x, or "space"/"backspace"/"return"/"shift"/"mode"/"other" — enough to replay every
    /// context reset and to derive backspace-retype labels.
    struct TapRecord: Codable {
        let tMs: Double         // UITouch.timestamp × 1000 (event clock, monotonic)
        let x: Double           // keys-area points
        let y: Double
        let radius: Double      // UITouch.majorRadius (constant on simulator)
        let rawRow: Int         // hit-grid key (pre-resolver)
        let rawCol: Int
        let actingRow: Int      // the live resolver's decision (what committed)
        let actingCol: Int
        let action: String
        let confidence: Float   // live context confidence at tap time (cross-check)
        /// Predictive prior snapshot as seen by this tap's resolution (single-char keys).
        let prior: [String: Float]?
        let priorFresh: Bool
        let priorIsEnglish: Bool
    }

    struct SessionHeader: Codable {
        var version = 1
        let capturedAtEpoch: Double
        let screenWidth: Double
        let keysW: Double
        let keysH: Double
        let profile: String          // KeyboardLayoutProfile case name; letters page only
        let layoutHash: Int
        let config: ProbabilisticHitResolver.Config
        let tuning: ResolverTuning
        let contextTuning: ContextTuning
        let populationScale: Double
        /// Learned clusters for `layoutHash` at session start (learning is frozen during
        /// capture, so this stays exact for every tap). nil = unseen layout.
        let clusters: [TouchOffsetModel.Cluster]?
        let nativeCommitTiming: Bool
    }

    struct Session: Codable {
        let header: SessionHeader
        var taps: [TapRecord]
    }

    /// Mirrored from `KeyboardFeatureFlags.calibrationCaptureEnabled` once per session.
    var enabled = false

    private var header: SessionHeader?
    private var taps: [TapRecord] = []
    private let capacity = 20_000

    /// Install the header once per keyboard session (first eligible tap).
    func beginSessionIfNeeded(_ make: () -> SessionHeader) {
        guard enabled, header == nil else { return }
        header = make()
        taps.removeAll(keepingCapacity: true)
    }

    func record(_ tap: TapRecord) {
        guard enabled, header != nil, taps.count < capacity else { return }
        taps.append(tap)
    }

    /// Persist the session to the App Group container. Call OFF the hot path
    /// (`viewWillDisappear`). Sessions with fewer than 10 taps are discarded as noise.
    func flush() {
        guard enabled, let header, taps.count >= 10 else { return }
        guard let dir = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroupSettings.suite
        ) else { return }
        let session = Session(header: header, taps: taps)
        let name = "calibration-session-\(Int(header.capturedAtEpoch)).json"
        if let data = try? JSONEncoder().encode(session) {
            try? data.write(to: dir.appendingPathComponent(name), options: .atomic)
        }
        self.header = nil
        taps.removeAll(keepingCapacity: false)
    }

    /// All captured sessions in the App Group (host-app Replay Lab reads these).
    static func sessionURLs() -> [URL] {
        guard let dir = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroupSettings.suite
        ) else { return [] }
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)) ?? []
        return urls
            .filter { $0.lastPathComponent.hasPrefix("calibration-session-") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    static func loadSession(at url: URL) -> Session? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }
}
#endif
