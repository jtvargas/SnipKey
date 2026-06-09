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

    /// Learned site offset for `frame` in points. `.zero` until enough samples accumulate.
    func offset(for frame: KeyFrame, keyboardWidth: CGFloat, rowCount: Int) -> CGVector {
        guard enabled, frame.isCharacterKey else { return .zero }
        guard let cs = clusters[key(currentLayout)] else { return .zero }
        let latFrac = Float(frame.rect.midX / max(keyboardWidth, 1))
        let idx = clusterIndex(row: frame.rowIndex, rowCount: rowCount, lateralFraction: latFrac)
        let c = cs[idx]
        let trust = min(Float(c.n) / Self.learnThreshold, 1)
        return CGVector(dx: CGFloat(c.fx * trust) * frame.rect.width,
                        dy: CGFloat(c.fy * trust) * frame.rect.height)
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
