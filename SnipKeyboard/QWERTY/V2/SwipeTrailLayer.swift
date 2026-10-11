//
//  SwipeTrailLayer.swift
//  SnipKeyboard
//
//  A short age-limited Catmull-Rom trail, independently implemented from the trail
//  architecture suggested by SwiftKey's exported symbols. A CADisplayLink runs only
//  during a swipe, so a paused finger still sees the tail shrink.
//
//  Pure presentation: no gesture logic, no decoding. Lives on the coordinator's layer above
//  the key surfaces.
//

import UIKit

final class SwipeTrailLayer: CAShapeLayer {

    /// A translucent stroke keeps key labels visible.
    enum Style {
        static let lineWidth: CGFloat = 9
        /// Age after which a sample leaves the trail (seconds). Short enough that a fast
        /// swipe reads as motion, long enough that direction changes stay legible.
        static let sampleLifetime: TimeInterval = 0.32
        static let fadeOutDuration: TimeInterval = 0.18
        static func color(isDark: Bool) -> CGColor {
            (isDark ? UIColor(white: 0.92, alpha: 0.55) : UIColor(white: 0.30, alpha: 0.50)).cgColor
        }
    }

    private var samples: [SwipeTracePoint] = []
    private var displayLink: CADisplayLink?
    private var generation: UInt64 = 0
    private var needsRedraw = false

    override init() {
        super.init()
        samples.reserveCapacity(256)
        actions = ["opacity": NSNull(), "hidden": NSNull(), "path": NSNull()]
        fillColor = nil
        lineWidth = Style.lineWidth
        lineCap = .round
        lineJoin = .round
        strokeColor = Style.color(isDark: false)
        zPosition = 40
        isHidden = true
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    func updateAppearance(isDark: Bool) {
        strokeColor = Style.color(isDark: isDark)
    }

    // MARK: - Lifecycle

    /// Start a trail from the samples captured before the swipe was recognised.
    func begin(with initial: [SwipeTracePoint]) {
        generation &+= 1
        removeAllAnimations()
        samples.removeAll(keepingCapacity: true)
        samples.append(contentsOf: initial)
        needsRedraw = true
        opacity = 1
        isHidden = false
        redraw(now: initial.last?.timestamp ?? ProcessInfo.processInfo.systemUptime)
        if displayLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    func append(_ sample: SwipeTracePoint) {
        samples.append(sample)
        needsRedraw = true
        // Coalesced touch samples are painted together on the next display frame.
    }

    /// Finish: the remaining comet fades out, then the layer hides and releases its link.
    func end() {
        let endingGeneration = generation
        redraw(now: ProcessInfo.processInfo.systemUptime)
        displayLink?.invalidate()
        displayLink = nil
        CATransaction.begin()
        CATransaction.setDisableActions(false)
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.generation == endingGeneration, self.displayLink == nil else { return }
            self.isHidden = true
            self.samples.removeAll(keepingCapacity: true)
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = Style.fadeOutDuration
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        add(fade, forKey: "trailFade")
        opacity = 0
        CATransaction.commit()
    }

    func cancel() {
        generation &+= 1
        displayLink?.invalidate()
        displayLink = nil
        removeAllAnimations()
        isHidden = true
        samples.removeAll(keepingCapacity: true)
    }

    // MARK: - Drawing

    @objc private func tick() {
        redraw(now: ProcessInfo.processInfo.systemUptime)
    }

    /// Rebuild the path from the samples still alive at `now`, Catmull-Rom smoothed.
    private func redraw(now: TimeInterval) {
        let cutoff = now - Style.sampleLifetime
        // Keep only the short visible tail.
        var firstAlive = 0
        while firstAlive < samples.count - 1, samples[firstAlive].timestamp < cutoff {
            firstAlive += 1
        }
        guard needsRedraw || firstAlive > 0 else { return }
        needsRedraw = false
        if firstAlive > 0 { samples.removeFirst(firstAlive) }

        let path = CGMutablePath()
        let n = samples.count
        if n >= 2 {
            path.move(to: samples[0].point)
            for i in 0..<(n - 1) {
                let p0 = samples[max(i - 1, 0)].point
                let p1 = samples[i].point
                let p2 = samples[i + 1].point
                let p3 = samples[min(i + 2, n - 1)].point
                // Catmull-Rom → cubic Bézier control points (tension 0.5).
                let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
                let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
                path.addCurve(to: p2, control1: c1, control2: c2)
            }
        } else if n == 1 {
            path.move(to: samples[0].point)
            path.addLine(to: samples[0].point)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.path = path
        CATransaction.commit()
    }
}
