//
//  TouchOffsetModel.swift
//  SnipKeyboard
//
//  Automatic, invisible per-user touch-offset learning (Keyboard V2 next-gen, plan §8). Users
//  do NOTHING — as they type normally, the keyboard learns where their thumbs actually land
//  relative to each key center and shifts the (invisible) decision sites to match. This is the
//  Gboard approach: don't hardcode an offset sign, learn it per person.
//
//  Robustness:
//   • Clustered (3 row-bands × 2 lateral zones = 6) so it learns fast without overfitting.
//   • Offsets stored as FRACTIONS of key size and keyed by a layout hash, so they survive
//     rotation / device / keyboard-height changes (plan §8, Risk 3).
//   • Confidence-gated: a keystroke is only learned from once it survives a short backspace
//     window. This avoids the self-reinforcing-error loop (plan Risk 1).
//   • Divergence guard: a cluster that drifts beyond half a key resets to neutral.
//   • Trust ramps with sample count, so early taps barely move anything.
//
//  On-device only. Persisted to the App Group container; flushed off the hot path.
//

import UIKit

@MainActor
final class TouchOffsetModel {

    static let shared = TouchOffsetModel()

    /// Mean fractional offset (fraction of key width/height) + sample count for one cluster.
    private struct Cluster: Codable {
        var fx: Float = 0
        var fy: Float = 0
        var n: Int = 0
    }

    private static let clusterCount = 6      // 3 row-bands × 2 lateral zones
    private static let learnThreshold: Float = 30  // samples before the offset is fully trusted
    private static let alpha: Float = 0.06   // EMA rate — slow, stable adaptation
    private static let maxFraction: Float = 0.5    // divergence guard: never exceed half a key

    /// Per-layout clusters, keyed by a stringified layout hash for clean JSON.
    private var clusters: [String: [Cluster]] = [:]
    /// Current layout hash (set by the coordinator each layout pass).
    var currentLayout = 0
    /// Tied to the next-gen engine being enabled.
    var enabled = false

    private struct PendingSample {
        let id: UInt64
        let layoutKey: String
        let cluster: Int
        let fx: Float
        let fy: Float
        let task: Task<Void, Never>
    }

    /// Recently typed keystrokes awaiting the backspace survival window.
    private var pending: [PendingSample] = []
    private var nextPendingID: UInt64 = 0
    private var dirty = false

    private init() { load() }

    // MARK: - Query (hot path)

    /// Site offset for `frame` in points: the learned per-user offset crossfaded with the
    /// population baseline as the cluster earns trust — `user·trust + population·(1−trust)`.
    /// The existing `·trust` ramp was already a crossfade against a zero baseline; the
    /// population offset replaces the zero, so fresh installs and fresh layout hashes start
    /// from the literature bias instead of nothing.
    func offset(for frame: KeyFrame, keyboardWidth: CGFloat, rowCount: Int) -> CGVector {
        guard enabled, frame.isCharacterKey else { return .zero }
        let pop = PopulationOffset.offset(for: frame)
        guard let cs = clusters[key(currentLayout)] else { return pop }  // cold start
        let latFrac = Float(frame.rect.midX / max(keyboardWidth, 1))
        let idx = clusterIndex(row: frame.rowIndex, rowCount: rowCount, lateralFraction: latFrac)
        let c = cs[idx]
        let trust = CGFloat(min(Float(c.n) / Self.learnThreshold, 1))
        // Population dx is 0, so only dy blends.
        return CGVector(dx: CGFloat(c.fx) * trust * frame.rect.width,
                        dy: CGFloat(c.fy) * trust * frame.rect.height + pop.dy * (1 - trust))
    }

    // MARK: - Learning

    /// Stage the just-committed character touch for learning after the backspace-survival window.
    func record(keyFrame: KeyFrame, point: CGPoint, keyboardWidth: CGFloat, rowCount: Int) {
        guard enabled, keyFrame.isCharacterKey else { return }
        let w = max(keyFrame.rect.width, 1)
        let h = max(keyFrame.rect.height, 1)
        let fx = Float((point.x - keyFrame.rect.midX) / w)
        let fy = Float((point.y - keyFrame.rect.midY) / h)
        let latFrac = Float(keyFrame.rect.midX / max(keyboardWidth, 1))
        let idx = clusterIndex(row: keyFrame.rowIndex, rowCount: rowCount, lateralFraction: latFrac)
        nextPendingID &+= 1
        let id = nextPendingID
        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.confirmPending(id: id)
        }
        pending.append(PendingSample(id: id, layoutKey: key(currentLayout), cluster: idx, fx: fx, fy: fy, task: task))
        if pending.count > 16 {
            let stale = pending.removeFirst()
            stale.task.cancel()
        }
    }

    /// Compatibility hook for older callers. Confirmation is now time-windowed per sample.
    func confirmPending() {
        guard enabled, let first = pending.first else { return }
        first.task.cancel()
        confirmPending(id: first.id)
    }

    private func confirmPending(id: UInt64) {
        guard enabled, let index = pending.firstIndex(where: { $0.id == id }) else { return }
        let sample = pending.remove(at: index)
        fold(layoutKey: sample.layoutKey, cluster: sample.cluster, fx: sample.fx, fy: sample.fy)
    }

    private func fold(layoutKey: String, cluster: Int, fx: Float, fy: Float) {
        var cs = clusters[layoutKey] ?? Array(repeating: Cluster(), count: Self.clusterCount)
        var c = cs[cluster]
        if c.n == 0 {
            c.fx = fx; c.fy = fy
        } else {
            c.fx = (1 - Self.alpha) * c.fx + Self.alpha * fx
            c.fy = (1 - Self.alpha) * c.fy + Self.alpha * fy
        }
        c.n += 1
        // Divergence guard — a runaway cluster resets to neutral.
        if abs(c.fx) > Self.maxFraction || abs(c.fy) > Self.maxFraction { c = Cluster() }
        #if DEBUG
        // Population-offset sign audit: the moment a cluster becomes fully trusted, its
        // learned vertical sign should agree with the population baseline (+down). A
        // disagreement here is the on-device signal that `PopulationOffset`'s sign is
        // wrong for this user/device profile — review before trusting the cold start.
        if c.n == Int(Self.learnThreshold), c.fy < -0.02 {
            NSLog("[SnipKeyboard] PopulationOffset sign audit: cluster %d learned fy=%.3f (UP) but population baseline is DOWN — review PopulationOffset sign", cluster, c.fy)
        }
        #endif
        cs[cluster] = c
        clusters[layoutKey] = cs
        dirty = true
    }

    /// Drop the most recent pending sample (the keystroke was quickly backspaced — likely an error).
    func discardPending() {
        guard let sample = pending.popLast() else { return }
        sample.task.cancel()
    }

    // MARK: - Clustering

    private func clusterIndex(row: Int, rowCount: Int, lateralFraction: Float) -> Int {
        let band = rowCount <= 1 ? 1 : min(Int(Float(max(row, 0)) / Float(rowCount) * 3), 2)
        let lateral = lateralFraction < 0.5 ? 0 : 1
        return band * 2 + lateral
    }

    private func key(_ layout: Int) -> String { String(layout) }

    // MARK: - Persistence

    private var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroupSettings.suite)?
            .appendingPathComponent("offset-model.json")
    }

    private func load() {
        guard let url = fileURL, let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: [Cluster]].self, from: data)
        else { return }
        clusters = decoded
    }

    /// Persist learned clusters off the hot path (e.g. `viewWillDisappear`). No-op unless dirty.
    func flush() {
        guard dirty, let url = fileURL else { return }
        if let data = try? JSONEncoder().encode(clusters) {
            try? data.write(to: url, options: .atomic)
            dirty = false
        }
    }
}

#if DEBUG
extension TouchOffsetModel {
    /// One-time invariant check for the population/user offset crossfade: pure population
    /// for unseen layouts and untrusted clusters, pure user at full trust, the exact
    /// midpoint halfway up the ramp, bounded output, and the population sign lock (+down
    /// for every row band). Logs (does not crash) on violation.
    static func runCrossfadeSelfTest() {
        var failures: [String] = []
        let model = TouchOffsetModel()
        model.enabled = true
        model.currentLayout = Int.min   // synthetic layout key — never a real geometry hash

        let w: CGFloat = 40, h: CGFloat = 44
        let rect = CGRect(x: 10, y: 100, width: w, height: h)
        func frame(row: Int) -> KeyFrame {
            KeyFrame(action: .character("a"), rect: rect, hitRect: rect,
                     rowIndex: row, columnIndex: 0, isCharacterKey: true)
        }

        // Sign lock: the population baseline must point DOWN (+) for every row band —
        // it crossfades against the learned model, whose convention is site-toward-landing.
        for row in 0..<3 where PopulationOffset.offset(for: frame(row: row)).dy < 0 {
            failures.append("population dy negative (UP) for row \(row)")
        }

        let f = frame(row: 2)   // 4-row layout ⇒ band 1; midX 30/393 ⇒ lateral 0 ⇒ cluster 2
        let pop = PopulationOffset.offset(for: f)

        // Unseen layout ⇒ pure population (the cold-start fix).
        let cold = model.offset(for: f, keyboardWidth: 393, rowCount: 4)
        if abs(cold.dy - pop.dy) > 0.001 || abs(cold.dx) > 0.001 {
            failures.append("cold start is not pure population: \(cold) vs \(pop)")
        }

        // Synthetic cluster landing ABOVE center (opposite the population sign) so the
        // crossfade direction is unambiguous in the assertions below.
        let userFx: Float = 0.1, userFy: Float = -0.2
        func setCluster(n: Int) {
            var cs = Array(repeating: Cluster(), count: Self.clusterCount)
            cs[2] = Cluster(fx: userFx, fy: userFy, n: n)
            model.clusters[String(model.currentLayout)] = cs
        }

        setCluster(n: 0)        // zero trust ⇒ still pure population
        let untrusted = model.offset(for: f, keyboardWidth: 393, rowCount: 4)
        if abs(untrusted.dy - pop.dy) > 0.001 || abs(untrusted.dx) > 0.001 {
            failures.append("untrusted cluster is not pure population: \(untrusted)")
        }

        setCluster(n: Int(Self.learnThreshold))   // full trust ⇒ pure user
        let trusted = model.offset(for: f, keyboardWidth: 393, rowCount: 4)
        if abs(trusted.dx - CGFloat(userFx) * w) > 0.001 || abs(trusted.dy - CGFloat(userFy) * h) > 0.001 {
            failures.append("fully-trusted cluster is not pure user offset: \(trusted)")
        }

        setCluster(n: Int(Self.learnThreshold) / 2)   // half trust ⇒ exact midpoint
        let mid = model.offset(for: f, keyboardWidth: 393, rowCount: 4)
        let expectedMidDy = CGFloat(userFy) * 0.5 * h + pop.dy * 0.5
        if abs(mid.dx - CGFloat(userFx) * 0.5 * w) > 0.001 || abs(mid.dy - expectedMidDy) > 0.001 {
            failures.append("half-trust crossfade is not the midpoint: \(mid) expected dy \(expectedMidDy)")
        }

        // Bound: |offset| can never exceed the divergence-guard fraction of the key plus
        // the population maximum.
        let bound = CGFloat(Self.maxFraction) * max(w, h) + PopulationOffset.verticalFractionByRow.max()! * h
        for o in [cold, untrusted, trusted, mid] where abs(o.dx) > bound || abs(o.dy) > bound {
            failures.append("offset exceeds bound: \(o)")
        }

        if failures.isEmpty {
            NSLog("[SnipKeyboard] offset-crossfade self-test passed")
        } else {
            for fail in failures { NSLog("[SnipKeyboard] offset-crossfade SELF-TEST FAILED: %@", fail) }
        }
    }
}
#endif
