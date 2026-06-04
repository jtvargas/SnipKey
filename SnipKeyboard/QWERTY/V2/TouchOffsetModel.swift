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
//   • Confidence-gated: a keystroke is only learned from once it's "confirmed" — i.e. the user
//     typed another character afterwards rather than immediately backspacing it. This avoids the
//     self-reinforcing-error loop (plan Risk 1).
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

    /// The just-typed keystroke awaiting confirmation (folded in only if not backspaced).
    private var pending: (layoutKey: String, cluster: Int, fx: Float, fy: Float)?
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

    /// Stage the just-committed character touch for learning (confirmed on the next character).
    func record(keyFrame: KeyFrame, point: CGPoint, keyboardWidth: CGFloat, rowCount: Int) {
        guard enabled, keyFrame.isCharacterKey else { return }
        let w = max(keyFrame.rect.width, 1)
        let h = max(keyFrame.rect.height, 1)
        let fx = Float((point.x - keyFrame.rect.midX) / w)
        let fy = Float((point.y - keyFrame.rect.midY) / h)
        let latFrac = Float(keyFrame.rect.midX / max(keyboardWidth, 1))
        let idx = clusterIndex(row: keyFrame.rowIndex, rowCount: rowCount, lateralFraction: latFrac)
        pending = (key(currentLayout), idx, fx, fy)
    }

    /// Fold the pending sample into its cluster's running mean (the keystroke survived).
    func confirmPending() {
        guard enabled, let p = pending else { pending = nil; return }
        pending = nil
        var cs = clusters[p.layoutKey] ?? Array(repeating: Cluster(), count: Self.clusterCount)
        var c = cs[p.cluster]
        if c.n == 0 {
            c.fx = p.fx; c.fy = p.fy
        } else {
            c.fx = (1 - Self.alpha) * c.fx + Self.alpha * p.fx
            c.fy = (1 - Self.alpha) * c.fy + Self.alpha * p.fy
        }
        c.n += 1
        // Divergence guard — a runaway cluster resets to neutral.
        if abs(c.fx) > Self.maxFraction || abs(c.fy) > Self.maxFraction { c = Cluster() }
        cs[p.cluster] = c
        clusters[p.layoutKey] = cs
        dirty = true
    }

    /// Drop the pending sample (the keystroke was immediately backspaced — likely an error).
    func discardPending() { pending = nil }

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
