//
//  ParticleChartView.swift
//  controller
//
//  Data charts drawn by ParticleMorphEngine (ParticleModeChart). A chart is a list of segments,
//  each a shape plus a share of the particles; showing a new list morphs the same particles into it.
//  ChartLayout builds the shapes: donut sectors, bars, treemap, waffle, line + area.
//

import UIKit
import ParticleTypes

struct ParticleChartSegment {
    /// Shape in the chart view's coordinates. nil releases the segment's particles: they leave the way
    /// the view's `releaseStyle` says.
    var path: UIBezierPath?
    /// Spread the particles along the stroke of this width instead of over the fill.
    var lineWidth: CGFloat?
    /// Particles in this segment. Segments take consecutive particle indices, so a segment that keeps
    /// its place in the list keeps its particles across charts.
    var count: Int
    /// Color of a particle at a point of the shape; .a is the glow brightness.
    var color: (SIMD2<Float>) -> SIMD4<Float>
    /// Points are sorted by this key before they are handed out, so neighbors stay neighbors in a morph.
    var order: ((SIMD2<Float>) -> Float)?
    /// Particle diameter for fine detail such as small text (default: the view's `pointSize`).
    /// Sizes are given out once, by the first `show`, so keep such a segment at the same particle indices.
    var pointSize: Float?
    /// Multiplies the spring that pulls particles to their places: high for text that must snap into
    /// readable digits (a running counter), 1 for shapes that should flow. Given out once, like `pointSize`.
    var stiffness: Float = 1
    /// Released particles fly here with the `ParticleReleaseHome` style (e.g. the item's legend row).
    var releaseTarget: CGRect?
    /// Whether this shape sets the glow brightness. Off for dense details (text) that tune their own
    /// alpha, so they don't dim everything else when they are all that is left on screen.
    var affectsBrightness = true

    init(
        path: UIBezierPath?,
        lineWidth: CGFloat? = nil,
        count: Int,
        pointSize: Float? = nil,
        color: @escaping (SIMD2<Float>) -> SIMD4<Float>,
        order: ((SIMD2<Float>) -> Float)? = nil
    ) {
        self.path = path
        self.lineWidth = lineWidth
        self.count = count
        self.pointSize = pointSize
        self.color = color
        self.order = order
    }

    init(
        path: UIBezierPath?,
        lineWidth: CGFloat? = nil,
        count: Int,
        pointSize: Float? = nil,
        color: UIColor,
        alpha: Float = 1,
        order: ((SIMD2<Float>) -> Float)? = nil
    ) {
        var simd = color.particleSIMD
        simd.w = alpha
        self.init(path: path, lineWidth: lineWidth, count: count, pointSize: pointSize, color: { _ in simd }, order: order)
    }
}

final class ParticleChartView: UIView {
    /// Fixed by the first `show`: every later chart is drawn by the same particles.
    var particleCount = 24_000
    var pointSize: Float = 2.2
    /// Glow relative to a solid-looking fill of the visible shapes.
    var brightness: Float = 0.5
    /// The finger pushes particles aside.
    var repelsTouches = true
    /// Finger position while touching, nil when it lifts.
    var onTouch: ((CGPoint?) -> Void)?
    var onTap: ((CGPoint) -> Void)?

    let engine: ParticleMorphEngine?
    private var targetIntensity: Float = 1
    private var lastTargets: [SIMD2<Float>] = []
    private var lastColors: [SIMD4<Float>] = []
    private var touchStart: (point: CGPoint, time: CFTimeInterval)?

    override init(frame: CGRect) {
        engine = ParticleMorphEngine(mode: ParticleModeChart)
        super.init(frame: frame)
        guard let engine else { return }
        engine.noiseStrength = 0.5
        engine.touchRadius = 70
        engine.touchPower = 8000
        // Brightness follows the visible area smoothly, so charts never pop when their size changes.
        engine.onFrame = { [weak self] engine, deltaTime in
            guard let self else { return }
            engine.intensity += (self.targetIntensity - engine.intensity) * min(Float(deltaTime) * 4, 1)
        }
        addSubview(engine.view)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        engine?.view.frame = bounds
    }

    /// How released particles leave. Set before the `show` that releases them.
    var releaseStyle: ParticleReleaseStyle {
        get { engine?.releaseStyle ?? ParticleReleaseDust }
        set { engine?.releaseStyle = newValue }
    }

    /// The chart's frame for releases: the black hole and the nova center on it, the sweep turns around it.
    var releaseBounds: CGRect {
        get { engine?.effectBounds ?? .zero }
        set { engine?.effectBounds = newValue }
    }

    /// Morphs the particles into `segments`, whose counts must add up to `particleCount`.
    /// The first chart fades in from random points inside `origin` (default: right where it is drawn).
    /// Particles that become released leave over `releaseDuration` seconds.
    func show(_ segments: [ParticleChartSegment], from origin: CGRect? = nil, releaseDuration: TimeInterval = 1.6) {
        guard let engine else { return }
        engine.view.frame = bounds
        var targets: [SIMD2<Float>] = []
        var colors: [SIMD4<Float>] = []
        var sizes: [Float] = []
        var stiffnesses: [Float] = []
        targets.reserveCapacity(particleCount)
        colors.reserveCapacity(particleCount)
        var brightnessCount = 0
        var brightnessArea: CGFloat = 0

        for (index, segment) in segments.enumerated() where segment.count > 0 {
            sizes += repeatElement(segment.pointSize ?? pointSize, count: segment.count)
            stiffnesses += repeatElement(segment.stiffness, count: segment.count)
            let sampled = sample(segment, seed: UInt64(index + 1))
            targets += sampled.targets
            colors += sampled.colors
            if let area = sampled.area, segment.affectsBrightness {
                brightnessCount += segment.count
                brightnessArea += area
            }
        }
        precondition(targets.count == particleCount, "segment counts must add up to particleCount")
        if brightnessCount > 0 {
            targetIntensity = ParticleMorphEngine.balancedIntensity(count: brightnessCount, area: brightnessArea,
                                                                    pointSize: CGFloat(pointSize)) * brightness
        }
        defer {
            lastTargets = targets
            lastColors = colors
        }

        if engine.particleCount == particleCount {
            // Newly released particles start a release: they hold where they are now until their turn
            // on the `stage` timeline comes.
            let releases = zip(lastColors, colors).contains { $0.w > 0 && $1.w == 0 }
            engine.retarget(targets: targets, colors: colors, colorsAreTargets: true, commitCurrentAsStart: releases)
            if releases {
                engine.releaseDuration = Float(releaseDuration)
                engine.stage = 0
                engine.animate(.stage, to: 1, duration: releaseDuration, timing: .linear)
            }
            return
        }
        var random = SeededRandom(seed: 7)
        let particles = targets.indices.map { i -> Particle in
            var start = targets[i]
            if let origin {
                start = SIMD2(Float(origin.minX + origin.width * CGFloat(random.unit())),
                              Float(origin.minY + origin.height * CGFloat(random.unit())))
            }
            var color = colors[i]
            color.w = 0
            return Particle(currentPosition: start, targetPosition: targets[i], startPosition: start, velocity: .zero,
                            color: color, targetColor: colors[i], size: sizes[i], seed: random.unit(),
                            stiffness: stiffnesses[i])
        }
        engine.load(particles)
        engine.intensity = targetIntensity
    }

    /// Re-draws only the last particles (the segments' counts' worth) and leaves everything else alone:
    /// cheap enough to run many times a second, e.g. for a counter whose digits keep changing.
    func replaceTail(_ segments: [ParticleChartSegment]) {
        guard let engine, engine.particleCount == particleCount, !lastTargets.isEmpty else { return }
        var start = particleCount - segments.reduce(0) { $0 + $1.count }
        precondition(start >= 0, "the tail is longer than the particles")
        for (index, segment) in segments.enumerated() where segment.count > 0 {
            let sampled = sample(segment, seed: UInt64(1000 + index))
            lastTargets.replaceSubrange(start..<(start + segment.count), with: sampled.targets)
            lastColors.replaceSubrange(start..<(start + segment.count), with: sampled.colors)
            start += segment.count
        }
        engine.retarget(targets: lastTargets, colors: lastColors, colorsAreTargets: true)
    }

    /// Targets and colors for one segment, plus the area it covers (nil when it is released).
    private func sample(_ segment: ParticleChartSegment, seed: UInt64)
        -> (targets: [SIMD2<Float>], colors: [SIMD4<Float>], area: CGFloat?) {
        var points: [SIMD2<Float>] = []
        if let path = segment.path {
            points = SVGToParticleConverter.points(from: path, count: segment.count, lineWidth: segment.lineWidth,
                                                   seed: seed)
        }
        guard points.count == segment.count, let path = segment.path else {
            // Released: the kernel only reads the target for the home style.
            var random = SeededRandom(seed: seed)
            let rect = segment.releaseTarget ?? .zero
            let targets = (0..<segment.count).map { _ in
                SIMD2(Float(rect.minX + rect.width * CGFloat(random.unit())),
                      Float(rect.minY + rect.height * CGFloat(random.unit())))
            }
            return (targets, Array(repeating: .zero, count: segment.count), nil)
        }
        if let order = segment.order {
            points = points.map { (order($0), $0) }.sorted { $0.0 < $1.0 }.map(\.1)
        }
        return (points, points.map(segment.color), SVGToParticleConverter.area(of: path, lineWidth: segment.lineWidth))
    }

    /// Splits `total` in proportion to `weights` so the parts add up exactly (largest remainder).
    static func split(_ total: Int, weights: [Double]) -> [Int] {
        let sum = weights.reduce(0) { $0 + max($1, 0) }
        guard sum > 0 else { return weights.indices.map { $0 == 0 ? total : 0 } }
        let exact = weights.map { Double(total) * max($0, 0) / sum }
        var parts = exact.map { Int($0) }
        let byRemainder = exact.indices.sorted { exact[$0] - Double(parts[$0]) > exact[$1] - Double(parts[$1]) }
        for i in byRemainder.prefix(total - parts.reduce(0, +)) {
            parts[i] += 1
        }
        return parts
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        touchStart = (point, CACurrentMediaTime())
        setTouch(point)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        setTouch(touches.first?.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let start = touchStart, let point = touches.first?.location(in: self),
           hypot(point.x - start.point.x, point.y - start.point.y) < 12,
           CACurrentMediaTime() - start.time < 0.35 {
            onTap?(point)
        }
        touchStart = nil
        setTouch(nil)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchStart = nil
        setTouch(nil)
    }

    private func setTouch(_ point: CGPoint?) {
        if repelsTouches {
            engine?.touchPosition = point
        }
        onTouch?(point)
    }
}

// MARK: - Layouts

enum ChartLayout {
    /// Annular sectors clockwise from 12 o'clock, one per share (nil for a zero share).
    /// `pop` pushes a sector outwards along its middle angle, in points.
    static func donut(
        center: CGPoint,
        innerRadius: CGFloat,
        outerRadius: CGFloat,
        shares: [Double],
        gap: CGFloat = 3,
        pop: [CGFloat] = []
    ) -> [UIBezierPath?] {
        let total = shares.reduce(0) { $0 + max($1, 0) }
        let visible = shares.filter { $0 > 0 }.count
        let gapAngle = visible > 1 ? gap / outerRadius : 0
        var angle = -CGFloat.pi / 2
        return shares.enumerated().map { index, share in
            guard share > 0, total > 0 else { return nil }
            let sweep = CGFloat(share / total) * 2 * .pi
            defer { angle += sweep }
            let a0 = angle + gapAngle / 2
            let a1 = max(angle + sweep - gapAngle / 2, a0 + 0.01)
            let offset = index < pop.count ? pop[index] : 0
            let mid = (a0 + a1) / 2
            let c = CGPoint(x: center.x + cos(mid) * offset, y: center.y + sin(mid) * offset)
            let path = UIBezierPath(arcCenter: c, radius: outerRadius, startAngle: a0, endAngle: a1, clockwise: true)
            path.addArc(withCenter: c, radius: innerRadius, startAngle: a1, endAngle: a0, clockwise: false)
            path.close()
            return path
        }
    }

    /// Angle from 12 o'clock, clockwise, 0…2π: the order of particles around a donut.
    static func clockAngle(_ point: SIMD2<Float>, center: CGPoint) -> Float {
        let angle = atan2(point.y - Float(center.y), point.x - Float(center.x)) + .pi / 2
        return angle < 0 ? angle + 2 * .pi : angle
    }

    /// Bars standing on the bottom of `rect`, heights relative to `maxValue`.
    static func bars(in rect: CGRect, values: [Double], maxValue: Double, spacing: CGFloat) -> [CGRect] {
        guard !values.isEmpty else { return [] }
        let width = (rect.width - spacing * CGFloat(values.count - 1)) / CGFloat(values.count)
        return values.enumerated().map { index, value in
            let height = rect.height * CGFloat(max(value, 0) / max(maxValue, 1e-9))
            return CGRect(x: rect.minX + CGFloat(index) * (width + spacing), y: rect.maxY - height,
                          width: width, height: height)
        }
    }

    /// Treemap: the biggest items are split into two groups of nearly equal sum along the longer
    /// side, recursively. Areas are proportional to the values.
    static func treemap(_ values: [Double], in rect: CGRect) -> [CGRect] {
        var result = Array(repeating: CGRect.zero, count: values.count)
        func place(_ indices: [Int], in rect: CGRect) {
            guard indices.count > 1 else {
                if let index = indices.first { result[index] = rect }
                return
            }
            let total = indices.reduce(0) { $0 + values[$1] }
            var cut = 1, bestDifference = Double.infinity, running = 0.0
            for k in 1..<indices.count {
                running += values[indices[k - 1]]
                let difference = abs(running - total / 2)
                if difference < bestDifference {
                    bestDifference = difference
                    cut = k
                }
            }
            let first = Array(indices[..<cut]), second = Array(indices[cut...])
            let fraction = CGFloat(total > 0 ? first.reduce(0) { $0 + values[$1] } / total : 0.5)
            let (a, b) = rect.width >= rect.height
                ? rect.divided(atDistance: rect.width * fraction, from: .minXEdge)
                : rect.divided(atDistance: rect.height * fraction, from: .minYEdge)
            place(first, in: a)
            place(second, in: b)
        }
        place(values.indices.sorted { values[$0] > values[$1] }, in: rect)
        return result
    }

    /// A columns × rows grid of cells handed out in proportion to `weights`, filled from the bottom row up.
    static func waffle(
        in rect: CGRect,
        columns: Int,
        rows: Int,
        weights: [Double],
        spacing: CGFloat = 4
    ) -> [UIBezierPath?] {
        let cells = ParticleChartView.split(columns * rows, weights: weights)
        let side = min((rect.width - spacing * CGFloat(columns - 1)) / CGFloat(columns),
                       (rect.height - spacing * CGFloat(rows - 1)) / CGFloat(rows))
        let origin = CGPoint(x: rect.midX - (side * CGFloat(columns) + spacing * CGFloat(columns - 1)) / 2,
                             y: rect.midY + (side * CGFloat(rows) + spacing * CGFloat(rows - 1)) / 2)
        var next = 0
        return cells.map { count in
            guard count > 0 else { return nil }
            let path = UIBezierPath()
            for cell in next..<(next + count) {
                let x = origin.x + CGFloat(cell % columns) * (side + spacing)
                let y = origin.y - CGFloat(cell / columns + 1) * side - CGFloat(cell / columns) * spacing
                path.append(UIBezierPath(roundedRect: CGRect(x: x, y: y, width: side, height: side),
                                         cornerRadius: side * 0.22))
            }
            next += count
            return path
        }
    }

    struct Line {
        let points: [CGPoint]
        let stroke: UIBezierPath
        /// The area between the curve and the bottom of the rect.
        let area: UIBezierPath

        /// The curve's height at `x` (linear between data points).
        func y(at x: CGFloat) -> CGFloat {
            guard let first = points.first, let last = points.last else { return 0 }
            if x <= first.x { return first.y }
            if x >= last.x { return last.y }
            let index = points.firstIndex { $0.x >= x } ?? points.count - 1
            let a = points[max(index - 1, 0)], b = points[index]
            return a.y + (b.y - a.y) * (x - a.x) / max(b.x - a.x, 1e-6)
        }
    }

    /// A smooth (Catmull-Rom) line through `values`, scaled so their range fills `rect` with some headroom.
    static func line(_ values: [Double], in rect: CGRect) -> Line {
        let low = values.min() ?? 0, high = values.max() ?? 1
        let padding = max(high - low, 1e-9) * 0.12
        let points = values.enumerated().map { index, value in
            CGPoint(x: rect.minX + rect.width * CGFloat(index) / CGFloat(max(values.count - 1, 1)),
                    y: rect.maxY - rect.height * CGFloat((value - low + padding) / (high - low + 2 * padding)))
        }
        let stroke = UIBezierPath()
        stroke.move(to: points[0])
        for i in 1..<points.count {
            let p0 = points[max(i - 2, 0)], p1 = points[i - 1], p2 = points[i], p3 = points[min(i + 1, points.count - 1)]
            stroke.addCurve(to: p2,
                            controlPoint1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                            controlPoint2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        let area = stroke.copy() as! UIBezierPath
        area.addLine(to: CGPoint(x: points[points.count - 1].x, y: rect.maxY))
        area.addLine(to: CGPoint(x: points[0].x, y: rect.maxY))
        area.close()
        return Line(points: points, stroke: stroke, area: area)
    }
}
