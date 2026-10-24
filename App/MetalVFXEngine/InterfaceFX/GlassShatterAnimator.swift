//
//  GlassShatterAnimator.swift
//  controller
//
//  Shatters a view like a pane of glass from an impact point. The snapshot is cut into Voronoi
//  cells (denser near the impact) on the CPU once; the GPU animates every shard in closed form.
//  Shader: Shaders/GlassShatter.metal.
//

import UIKit
import Metal
import simd

/// Mirrors `ShardVertex` in GlassShatter.metal (stride 48).
private struct ShardVertex {
    var local: SIMD2<Float>
    var uv: SIMD2<Float>
    var bary: SIMD3<Float>
    var shard: UInt32
}

/// Mirrors `Shard` in GlassShatter.metal (stride 48).
private struct Shard {
    var centroid: SIMD2<Float>
    var velocity: SIMD2<Float>
    var axis: SIMD3<Float>
    var spin: Float
    var delay: Float
    var depthVelocity: Float
}

/// Mirrors `ShatterUniforms` in GlassShatter.metal.
private struct ShatterUniforms {
    var viewport: SIMD2<Float>
    var scale: Float
    var time: Float
    var impact: SIMD2<Float>
    var crackTime: Float
    var gravity: Float
}

final class GlassShatterAnimator {
    var shardCount = 64
    var duration: TimeInterval = 1.9
    /// How long the cracked pane holds together before it falls apart.
    var crackTime: TimeInterval = 0.28
    var gravity: CGFloat = 1700

    private var overlays: [ShatterOverlay] = []

    /// Breaks `view` from `impact` (in the view's coordinates; nil = center). The view is hidden
    /// right away (alpha 0); restore it in `completion` if you reuse it.
    func shatter(_ view: UIView, at impact: CGPoint? = nil, completion: (() -> Void)? = nil) {
        guard let window = view.window, let gpu = VFXGPU.shared,
              let texture = gpu.makeTexture(snapshotting: view, scale: window.traitCollection.displayScale) else {
            view.alpha = 0
            completion?()
            return
        }
        let frame = view.convert(view.bounds, to: window)
        let localImpact = impact ?? CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        let hit = view.convert(localImpact, to: window)
        let geometry = makeShards(frame: frame, impact: hit)
        guard let vertexBuffer = geometry.vertices.withUnsafeBytes({
                  gpu.device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }),
              let shardBuffer = geometry.shards.withUnsafeBytes({
                  gpu.device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) })
        else { return }

        let overlay = ShatterOverlay(texture: texture, vertices: vertexBuffer, vertexCount: geometry.vertices.count,
                                     shards: shardBuffer, impact: hit, duration: duration,
                                     crackTime: crackTime, gravity: gravity)
        overlay.frame = window.bounds
        overlay.onFinish = { [weak self, weak overlay] in
            overlay?.removeFromSuperview()
            self?.overlays.removeAll { $0 === overlay }
            completion?()
        }
        overlays.append(overlay)
        window.addSubview(overlay)
        view.alpha = 0
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    // MARK: - Voronoi shards

    private func makeShards(frame: CGRect, impact: CGPoint) -> (vertices: [ShardVertex], shards: [Shard]) {
        var random = SystemRandomNumberGenerator()
        func unit() -> CGFloat { CGFloat.random(in: 0...1, using: &random) }

        // Seeds: most cluster around the impact (small shards there), a few spread evenly.
        let reach = hypot(frame.width, frame.height)
        var seeds: [CGPoint] = []
        while seeds.count < shardCount {
            let point: CGPoint
            if seeds.count < shardCount * 3 / 4 {
                let radius = reach * 0.6 * pow(unit(), 1.8)
                let angle = unit() * 2 * .pi
                point = CGPoint(x: impact.x + cos(angle) * radius, y: impact.y + sin(angle) * radius)
            } else {
                point = CGPoint(x: frame.minX + unit() * frame.width, y: frame.minY + unit() * frame.height)
            }
            if frame.contains(point) { seeds.append(point) }
        }

        var vertices: [ShardVertex] = []
        var shards: [Shard] = []
        let rectangle = [CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY),
                         CGPoint(x: frame.maxX, y: frame.maxY), CGPoint(x: frame.minX, y: frame.maxY)]
        for (index, seed) in seeds.enumerated() {
            // A Voronoi cell is the rectangle clipped by the bisector half-plane of every other seed.
            var cell = rectangle
            for (otherIndex, other) in seeds.enumerated() where otherIndex != index {
                let mid = CGPoint(x: (seed.x + other.x) / 2, y: (seed.y + other.y) / 2)
                let normal = CGPoint(x: other.x - seed.x, y: other.y - seed.y)
                cell = clip(cell, keepingSideOf: mid, normal: normal)
                if cell.count < 3 { break }
            }
            guard cell.count >= 3 else { continue }
            let centroid = CGPoint(x: cell.map(\.x).reduce(0, +) / CGFloat(cell.count),
                                   y: cell.map(\.y).reduce(0, +) / CGFloat(cell.count))

            // Physics: blown away from the impact (harder close to it), kicked up and towards the viewer.
            let away = CGPoint(x: centroid.x - impact.x, y: centroid.y - impact.y)
            let distance = max(hypot(away.x, away.y), 1)
            let closeness = max(0, 1 - distance / reach)
            let speed = 50 + 330 * closeness * closeness + 60 * unit()
            let velocity = SIMD2(Float(away.x / distance * speed), Float(away.y / distance * speed - 150 * unit()))
            let axis = simd_normalize(SIMD3(Float(unit() - 0.5), Float(unit() - 0.5), Float(unit() * 0.4 - 0.2)))
            let shardIndex = UInt32(shards.count)
            shards.append(Shard(centroid: SIMD2(Float(centroid.x), Float(centroid.y)), velocity: velocity,
                                axis: axis, spin: Float(1.5 + 6 * unit()) * (unit() < 0.5 ? -1 : 1),
                                delay: Float(distance / 1800),   // the shock wave travels outwards
                                depthVelocity: Float(60 + 260 * closeness + 40 * unit())))

            // Triangle fan from the centroid; bary.x = 0 marks the outer (crack) edge.
            func vertex(_ p: CGPoint, _ bary: SIMD3<Float>) -> ShardVertex {
                ShardVertex(local: SIMD2(Float(p.x - centroid.x), Float(p.y - centroid.y)),
                            uv: SIMD2(Float((p.x - frame.minX) / frame.width), Float((p.y - frame.minY) / frame.height)),
                            bary: bary, shard: shardIndex)
            }
            for i in 0..<cell.count {
                vertices.append(vertex(centroid, SIMD3(1, 0, 0)))
                vertices.append(vertex(cell[i], SIMD3(0, 1, 0)))
                vertices.append(vertex(cell[(i + 1) % cell.count], SIMD3(0, 0, 1)))
            }
        }
        return (vertices, shards)
    }

    /// Sutherland–Hodgman against one half-plane: keeps points p with (p − point)·normal ≤ 0.
    private func clip(_ polygon: [CGPoint], keepingSideOf point: CGPoint, normal: CGPoint) -> [CGPoint] {
        func side(_ p: CGPoint) -> CGFloat { (p.x - point.x) * normal.x + (p.y - point.y) * normal.y }
        var result: [CGPoint] = []
        for i in 0..<polygon.count {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            let sa = side(a), sb = side(b)
            if sa <= 0 { result.append(a) }
            if (sa <= 0) != (sb <= 0) {
                let t = sa / (sa - sb)
                result.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
        }
        return result
    }
}

private final class ShatterOverlay: VFXMetalView {
    var onFinish: (() -> Void)?

    private let texture: MTLTexture
    private let vertices: MTLBuffer
    private let vertexCount: Int
    private let shards: MTLBuffer
    private let impact: CGPoint
    private let duration: TimeInterval
    private let crackTime: TimeInterval
    private let gravity: CGFloat
    private var finished = false

    init(texture: MTLTexture, vertices: MTLBuffer, vertexCount: Int, shards: MTLBuffer, impact: CGPoint,
         duration: TimeInterval, crackTime: TimeInterval, gravity: CGFloat) {
        self.texture = texture
        self.vertices = vertices
        self.vertexCount = vertexCount
        self.shards = shards
        self.impact = impact
        self.duration = duration
        self.crackTime = crackTime
        self.gravity = gravity
        super.init(frame: .zero)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func update(deltaTime: CFTimeInterval) {
        if time >= duration + crackTime, !finished {
            finished = true
            isPaused = true
            DispatchQueue.main.async { [weak self] in self?.onFinish?() }
        }
    }

    override func encode(into commandBuffer: MTLCommandBuffer, target: MTLTexture) {
        guard let gpu, let pipeline = gpu.renderPipeline(vertex: "shard_vertex", fragment: "shard_fragment"),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass(target: target)) else { return }
        var uniforms = ShatterUniforms(viewport: SIMD2(Float(target.width), Float(target.height)),
                                       scale: Float(contentScaleFactor), time: Float(time),
                                       impact: SIMD2(Float(impact.x), Float(impact.y)),
                                       crackTime: Float(crackTime), gravity: Float(gravity))
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(vertices, offset: 0, index: 0)
        encoder.setVertexBuffer(shards, offset: 0, index: 1)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<ShatterUniforms>.stride, index: 2)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ShatterUniforms>.stride, index: 2)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
        encoder.endEncoding()
    }
}
