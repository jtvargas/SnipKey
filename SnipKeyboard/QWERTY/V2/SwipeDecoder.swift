//
//  SwipeDecoder.swift
//  SnipKeyboard
//
//  Turns a swipe trace over the letters page into ranked word candidates. Pure and
//  thread-safe (no UIKit, no main-actor state); decoding is synchronous on the caller.
//
//  Shape/location matching inspired by Kristensson & Zhai's SHARK2 (UIST 2004), with a
//  unigram frequency prior. This is not a reproduction of SHARK2 or a proprietary decoder.
//
//  1. Preprocess: merge trace points closer than `minimumPointSpacing`, measure the path
//     length, resample to `sampleCount` points equidistant by arc length.
//  2. Candidates: the first letter must have its key center within `firstLetterRadius`
//     key widths of the first trace point, the last within `lastLetterRadius` of the last
//     point (lift-off is sloppier than touch-down; the nearest key is always included).
//     Only the lexicon's (first, last) buckets for those sets are enumerated, and a
//     word is skipped when its template path length is outside
//     [minimumLengthRatio, maximumLengthRatio] × trace length.
//  3. Template: the polyline through the word's key centers with consecutive repeated
//     letters collapsed ("hello" → h-e-l-o), resampled like the trace.
//  4. Location channel: mean over samples of max(0, ‖tᵢ − wᵢ‖ − r), r = `locationTolerance`
//     key widths, with the first/last `endSampleCount` samples weighted
//     `endSampleWeight`×.
//  5. Shape channel: both polylines translated to their centroid and scaled by the larger
//     bounding-box side (so a word's shape is compared independent of where and how big
//     it was drawn); mean sample distance.
//  6. cost = endpointWeight·dEnds + locationWeight·dLoc + shapeWeight·dShape
//     − priorWeight·ln P(word). Direct endpoint errors use the same location tolerance.
//     Lowest cost wins; softmax scores are relative, not calibrated correctness probabilities.
//
//  Geometry buffers share one scratch allocation. Candidate scoring allocates no
//  per-word storage and stops when partial location cost cannot beat the current top-K.
//

import CoreGraphics
import Foundation
import simd

final class SwipeDecoder: Sendable {

    struct Config: Sendable {
        /// Samples per resampled trace/template.
        var sampleCount = 48
        /// Trace points closer than this (pt) to the previously kept point are merged.
        var minimumPointSpacing: Float = 1
        /// Half-width (pt) of the box filter applied to the uniformly resampled trace
        /// before its length is measured, reducing jitter at the cost of corner rounding.
        var smoothingRadius: Float = 12
        /// First-letter key centers must lie within this many key widths of the first
        /// trace point. Which neighbouring rows qualify depends on the layout geometry.
        var firstLetterRadius: Float = 1.25
        /// Last-letter radius in key widths; lift-off is sloppier than touch-down.
        var lastLetterRadius: Float = 1.5
        /// Template path length must be within [min, max] × trace length. The lower bound
        /// is waived when the trace is shorter than one key width so 2-letter words pass.
        var minimumLengthRatio: Float = 0.4
        var maximumLengthRatio: Float = 2.2
        /// Location-channel tolerance in key widths: samples within this distance of the
        /// template cost nothing (the finger need not cross key centers).
        var locationTolerance: Float = 0.5
        /// Number of samples at each end given `endSampleWeight` in the location channel.
        var endSampleCount = 4
        var endSampleWeight: Float = 2
        /// Direct endpoint cost, independent of trace length: a frequent neighbour must not
        /// win merely because a clear start/lift mismatch is diluted over all 48 samples.
        var endpointWeight: Float = 0.3
        /// Relative channel weights: location is measured in key widths, shape in
        /// bounding-box-normalized units, and the prior is a natural-log frequency.
        /// Defaults are heuristics, not a measured real-world accuracy guarantee.
        var locationWeight: Float = 1.0
        var shapeWeight: Float = 0.8
        var priorWeight: Float = 0.03
        /// Softmax temperature (cost units) for `SwipeCandidate.confidence`.
        var confidenceTemperature: Float = 0.25
    }

    let lexicon: SwipeLexicon
    let config: Config

    init(lexicon: SwipeLexicon, config: Config = Config()) {
        self.lexicon = lexicon
        self.config = config
    }

    /// Ranks lexicon words against `trace` (keys-area coordinates, same space as
    /// `layout.centers`). Returns up to `maxCandidates` distinct output words, best
    /// first, or [] when the trace has fewer than two distinct points or nothing matched.
    func decode(_ trace: [SwipeTracePoint], layout: SwipeKeyLayout, maxCandidates: Int = 3) -> [SwipeCandidate] {
        guard maxCandidates > 0, layout.keyWidth > 0, trace.count >= 2 else { return [] }
        let n = config.sampleCount
        let keyWidth = Float(layout.keyWidth)

        // One block for every buffer the decode touches, carved in order: raw trace, fine
        // uniform trace (×2), resampled trace, shape-normalized trace, collapsed template,
        // resampled template, key centers.
        let fine = Self.fineSampleFactor * n
        let maxTemplatePoints = SwipeLexicon.maxWordLength
        let capacity = trace.count + 2 * fine + 3 * n + maxTemplatePoints + SwipeLexicon.letterCount
        let block = UnsafeMutablePointer<SIMD2<Float>>.allocate(capacity: capacity)
        defer { block.deallocate() }
        var cursor = block
        func carve(_ count: Int) -> UnsafeMutableBufferPointer<SIMD2<Float>> {
            defer { cursor += count }
            return UnsafeMutableBufferPointer(start: cursor, count: count)
        }
        let rawTrace = carve(trace.count)
        let fineTrace = carve(fine)
        let smoothTrace = carve(fine)
        let sampledTrace = carve(n)
        let traceShape = carve(n)
        let template = carve(maxTemplatePoints)
        let sampledTemplate = carve(n)
        let centers = carve(SwipeLexicon.letterCount)

        // 1. Reduce jitter's effect on arc length before resampling for comparison.
        //    Preserve touch-down and lift-off positions through both preprocessing steps.
        let (rawCount, rawLength) = Self.condense(trace, minimumSpacing: config.minimumPointSpacing, into: rawTrace)
        guard rawCount >= 2 else { return [] }
        Self.resample(rawTrace, count: rawCount, length: rawLength, into: fineTrace)
        Self.smooth(fineTrace, spacing: rawLength / Float(fine - 1), radius: config.smoothingRadius, into: smoothTrace)
        let traceLength = Self.polylineLength(smoothTrace)
        Self.resample(smoothTrace, count: fine, length: traceLength, into: sampledTrace)
        Self.normalizeShape(sampledTrace, pathLength: traceLength, into: traceShape)

        // 2. Layout + candidate letter sets.
        let present = Self.loadCenters(layout, into: centers)
        guard present != 0 else { return [] }
        let firstSet = Self.lettersNear(sampledTrace[0], radius: config.firstLetterRadius * keyWidth, centers: centers, present: present)
        let lastSet = Self.lettersNear(sampledTrace[n - 1], radius: config.lastLetterRadius * keyWidth, centers: centers, present: present)
        let minTemplateLength = traceLength < keyWidth ? 0 : config.minimumLengthRatio * traceLength
        let maxTemplateLength = config.maximumLengthRatio * traceLength

        // Keep extra slots so dedup by output word can't leave us short.
        var best = TopK(capacity: maxCandidates * 2)
        let tolerance = config.locationTolerance * keyWidth
        let locationScale = config.locationWeight / (Float(n) * keyWidth)
        let endCount = min(config.endSampleCount, n / 2)

        lexicon.letters.withUnsafeBufferPointer { letters in
            for first in 0..<SwipeLexicon.letterCount where firstSet & (1 << first) != 0 {
                let startError = max(0, simd_distance(sampledTrace[0], centers[first]) - tolerance)
                for last in 0..<SwipeLexicon.letterCount where lastSet & (1 << last) != 0 {
                    let endError = max(0, simd_distance(sampledTrace[n - 1], centers[last]) - tolerance)
                    let endpointCost = config.endpointWeight * (startError + endError) / keyWidth
                    for wordIndex in lexicon.bucket(first: first, last: last) {
                        let wi = Int(wordIndex)
                        let priorCost = endpointCost - config.priorWeight * lexicon.logPrior[wi]
                        if priorCost >= best.threshold { continue }

                        // 3. Template polyline, length-gated.
                        let range = lexicon.letterRange(of: wi)
                        var pointCount = 0
                        var templateLength: Float = 0
                        var previousLetter: UInt8 = .max
                        var complete = true
                        for j in range {
                            let letter = letters[j]
                            if letter == previousLetter { continue }
                            previousLetter = letter
                            if present & (1 << UInt32(letter)) == 0 { complete = false; break }
                            let p = centers[Int(letter)]
                            if pointCount > 0 { templateLength += simd_distance(template[pointCount - 1], p) }
                            template[pointCount] = p
                            pointCount += 1
                        }
                        if !complete || templateLength < minTemplateLength || templateLength > maxTemplateLength { continue }
                        Self.resample(template, count: pointCount, length: templateLength, into: sampledTemplate)

                        // 4. Location channel with branch-and-bound on the running cost.
                        var cost = priorCost
                        var abandoned = false
                        for i in 0..<n {
                            let excess = simd_distance(sampledTrace[i], sampledTemplate[i]) - tolerance
                            if excess > 0 {
                                let weight: Float = (i < endCount || i >= n - endCount) ? config.endSampleWeight : 1
                                cost += weight * excess * locationScale
                                if cost >= best.threshold { abandoned = true; break }
                            }
                        }
                        if abandoned { continue }

                        // 5. Shape channel.
                        cost += config.shapeWeight * Self.shapeDistance(sampledTemplate, pathLength: templateLength, against: traceShape)
                        best.insert(cost: cost, index: wordIndex)
                    }
                }
            }
        }

        // 6. Dedup by output word, softmax the kept costs into confidences.
        var words: [String] = []
        var costs: [Float] = []
        words.reserveCapacity(maxCandidates)
        costs.reserveCapacity(maxCandidates)
        for k in 0..<best.count where words.count < maxCandidates {
            let word = lexicon.outputWord(at: Int(best.indices[k]))
            if words.contains(word) { continue }
            words.append(word)
            costs.append(best.costs[k])
        }
        guard let lowest = costs.first else { return [] }
        let weights = costs.map { exp(-($0 - lowest) / config.confidenceTemperature) }
        let total = weights.reduce(0, +)
        return zip(words, weights).map { SwipeCandidate(word: $0, confidence: $1 / total) }
    }

    // MARK: - Geometry

    /// Copies `trace` into `out`, dropping points within `minimumSpacing` of the last kept
    /// point, except that the final lift-off position is retained. Returns count and length.
    private static func condense(_ trace: [SwipeTracePoint], minimumSpacing: Float, into out: UnsafeMutableBufferPointer<SIMD2<Float>>) -> (count: Int, length: Float) {
        var count = 0
        var length: Float = 0
        for (index, sample) in trace.enumerated() {
            let p = SIMD2<Float>(Float(sample.x), Float(sample.y))
            if count > 0 {
                let d = simd_distance(out[count - 1], p)
                if d == 0 || (d < minimumSpacing && index != trace.count - 1) { continue }
                length += d
            }
            out[count] = p
            count += 1
        }
        return (count, length)
    }

    /// The trace is first resampled to this many × `sampleCount` points so the smoothing
    /// window is spatial (fixed pt), independent of finger speed and sensor rate.
    private static let fineSampleFactor = 2

    /// Box-filters a uniformly spaced polyline (`spacing` pt between points) with a window
    /// of ±`radius` pt into `out`. The endpoints (touch-down and lift-off) are kept exact;
    /// the window shrinks symmetrically near them.
    private static func smooth(_ points: UnsafeMutableBufferPointer<SIMD2<Float>>, spacing: Float, radius: Float, into out: UnsafeMutableBufferPointer<SIMD2<Float>>) {
        let count = points.count
        let halfWindow = spacing > 0 ? min(Int(radius / spacing), count / 4) : 0
        guard halfWindow > 0 else {
            for i in 0..<count { out[i] = points[i] }
            return
        }
        out[0] = points[0]
        out[count - 1] = points[count - 1]
        for i in 1..<(count - 1) {
            let h = min(halfWindow, i, count - 1 - i)
            var sum = SIMD2<Float>.zero
            for j in (i - h)...(i + h) { sum += points[j] }
            out[i] = sum / Float(2 * h + 1)
        }
    }

    private static func polylineLength(_ points: UnsafeMutableBufferPointer<SIMD2<Float>>) -> Float {
        var length: Float = 0
        for i in 1..<points.count { length += simd_distance(points[i - 1], points[i]) }
        return length
    }

    /// Resamples the polyline `points[0..<count]` of length `length` into `out.count`
    /// points equidistant by arc length; the first and last samples are the polyline's own
    /// endpoints. A single point (or zero length) fills `out` with that point.
    private static func resample(_ points: UnsafeMutableBufferPointer<SIMD2<Float>>, count: Int, length: Float, into out: UnsafeMutableBufferPointer<SIMD2<Float>>) {
        let n = out.count
        let last = points[count - 1]
        guard count >= 2, length > 0 else {
            for i in 0..<n { out[i] = points[0] }
            return
        }
        let interval = length / Float(n - 1)
        out[0] = points[0]
        var produced = 1
        var accumulated: Float = 0
        var previous = points[0]
        var i = 1
        while i < count && produced < n - 1 {
            let current = points[i]
            let segment = simd_distance(previous, current)
            if accumulated + segment >= interval {
                // `segment > interval - accumulated > 0` here, so the division is safe.
                let q = previous + (current - previous) * ((interval - accumulated) / segment)
                out[produced] = q
                produced += 1
                previous = q
                accumulated = 0
            } else {
                accumulated += segment
                previous = current
                i += 1
            }
        }
        // Floating-point drift can leave the walk short by a sample; pin the tail.
        while produced < n {
            out[produced] = last
            produced += 1
        }
    }

    /// Translates `points` to their centroid and scales by the larger bounding-box side
    /// (falling back to `pathLength`, then to 1, for a single-point polyline).
    private static func normalizeShape(_ points: UnsafeMutableBufferPointer<SIMD2<Float>>, pathLength: Float, into out: UnsafeMutableBufferPointer<SIMD2<Float>>) {
        let (centroid, scale) = shapeFrame(points, pathLength: pathLength)
        for i in 0..<points.count { out[i] = (points[i] - centroid) / scale }
    }

    /// Mean distance between the shape-normalized `points` and an already-normalized
    /// `reference`, without materializing the normalized `points`.
    private static func shapeDistance(_ points: UnsafeMutableBufferPointer<SIMD2<Float>>, pathLength: Float, against reference: UnsafeMutableBufferPointer<SIMD2<Float>>) -> Float {
        let (centroid, scale) = shapeFrame(points, pathLength: pathLength)
        var sum: Float = 0
        for i in 0..<points.count {
            sum += simd_distance((points[i] - centroid) / scale, reference[i])
        }
        return sum / Float(points.count)
    }

    private static let degenerateScale: Float = 1e-3

    private static func shapeFrame(_ points: UnsafeMutableBufferPointer<SIMD2<Float>>, pathLength: Float) -> (centroid: SIMD2<Float>, scale: Float) {
        var sum = SIMD2<Float>.zero
        var low = points[0]
        var high = points[0]
        for i in 0..<points.count {
            let p = points[i]
            sum += p
            low = pointwiseMin(low, p)
            high = pointwiseMax(high, p)
        }
        var scale = (high - low).max()
        if scale < degenerateScale { scale = pathLength }
        if scale < degenerateScale { scale = 1 }
        return (sum / Float(points.count), scale)
    }

    // MARK: - Layout

    /// Fills `centers[0..<26]` from the layout and returns a bitmask of the letters present.
    private static func loadCenters(_ layout: SwipeKeyLayout, into centers: UnsafeMutableBufferPointer<SIMD2<Float>>) -> UInt32 {
        var present: UInt32 = 0
        for i in 0..<centers.count { centers[i] = .zero }
        for (character, point) in layout.centers {
            guard let ascii = character.asciiValue, ascii >= UInt8(ascii: "a"), ascii <= UInt8(ascii: "z") else { continue }
            let index = Int(ascii - UInt8(ascii: "a"))
            centers[index] = SIMD2<Float>(Float(point.x), Float(point.y))
            present |= 1 << UInt32(index)
        }
        return present
    }

    /// Bitmask of letters whose center is within `radius` of `point`; the nearest letter
    /// is always included.
    private static func lettersNear(_ point: SIMD2<Float>, radius: Float, centers: UnsafeMutableBufferPointer<SIMD2<Float>>, present: UInt32) -> UInt32 {
        var set: UInt32 = 0
        var nearest = -1
        var nearestDistance = Float.infinity
        for i in 0..<centers.count where present & (1 << UInt32(i)) != 0 {
            let d = simd_distance(point, centers[i])
            if d <= radius { set |= 1 << UInt32(i) }
            if d < nearestDistance { nearestDistance = d; nearest = i }
        }
        if nearest >= 0 { set |= 1 << UInt32(nearest) }
        return set
    }

    // MARK: - Top-K

    /// Fixed-capacity ascending list of the best (cost, lexicon index) pairs seen so far.
    /// `threshold` is the cost a new entry must beat once the list is full.
    private struct TopK {
        private(set) var costs: [Float]
        private(set) var indices: [Int32]
        private(set) var count = 0
        private let capacity: Int

        init(capacity: Int) {
            self.capacity = capacity
            costs = [Float](repeating: .infinity, count: capacity)
            indices = [Int32](repeating: -1, count: capacity)
        }

        var threshold: Float { count < capacity ? .infinity : costs[capacity - 1] }

        mutating func insert(cost: Float, index: Int32) {
            guard cost < threshold else { return }
            var slot = min(count, capacity - 1)
            while slot > 0 && costs[slot - 1] > cost {
                costs[slot] = costs[slot - 1]
                indices[slot] = indices[slot - 1]
                slot -= 1
            }
            costs[slot] = cost
            indices[slot] = index
            if count < capacity { count += 1 }
        }
    }
}
