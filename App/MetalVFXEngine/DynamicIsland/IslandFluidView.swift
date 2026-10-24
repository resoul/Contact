//
//  IslandFluidView.swift
//  controller
//
//  LiquidCanvasView: glossy liquid drawn as one merged field of `shapes` and `spikes`
//  (Shaders/IslandFluid.metal). IslandFluidView: the same liquid growing out of the Dynamic Island,
//  as a full-window, touch-through overlay. Plus the springs the liquid effects move with.
//

import UIKit
import Metal

/// Mirrors `IslandFluidUniforms` in IslandFluid.metal.
private struct IslandFluidUniforms {
    var viewport: SIMD2<Float>
    var scale: Float
    var gloss: Float
    var island: SIMD4<Float>
    var color: SIMD4<Float>
    var bounds: SIMD4<Float>
    var shapeCount: UInt32
    var spikeCount: UInt32
    var rimWidth: Float
    var time: Float
}

/// Mirrors `IslandFluidShape` in IslandFluid.metal. A rounded box; a circle when `cornerRadius`
/// is at least the half size.
struct IslandFluidShape {
    var box: SIMD4<Float>
    var params: SIMD4<Float>

    /// `blend` is the smin radius with the island and the shapes before it: 0 = hard union.
    init(center: CGPoint, halfSize: CGSize, cornerRadius: CGFloat, blend: CGFloat) {
        box = SIMD4(Float(center.x), Float(center.y), Float(max(halfSize.width, 0)), Float(max(halfSize.height, 0)))
        params = SIMD4(Float(cornerRadius), Float(blend), 0, 0)
    }

    static func circle(center: CGPoint, radius: CGFloat, blend: CGFloat) -> IslandFluidShape {
        IslandFluidShape(center: center, halfSize: CGSize(width: radius, height: radius),
                         cornerRadius: radius, blend: blend)
    }

    fileprivate var extent: CGRect {
        CGRect(x: CGFloat(box.x - box.z), y: CGFloat(box.y - box.w), width: CGFloat(box.z * 2), height: CGFloat(box.w * 2))
            .insetBy(dx: -CGFloat(params.y), dy: -CGFloat(params.y))
    }
}

/// Mirrors `IslandFluidSpike` in IslandFluid.metal: a cone tapering from `base` to `tip`.
struct IslandFluidSpike {
    var segment: SIMD4<Float>
    var params: SIMD4<Float>

    init(base: CGPoint, tip: CGPoint, baseRadius: CGFloat, tipRadius: CGFloat, blend: CGFloat) {
        segment = SIMD4(Float(base.x), Float(base.y), Float(tip.x), Float(tip.y))
        params = SIMD4(Float(baseRadius), Float(tipRadius), Float(blend), 0)
    }

    fileprivate var extent: CGRect {
        let r = CGFloat(params.x + params.z)
        return CGRect(x: CGFloat(min(segment.x, segment.z)), y: CGFloat(min(segment.y, segment.w)),
                      width: CGFloat(abs(segment.z - segment.x)), height: CGFloat(abs(segment.w - segment.y)))
            .insetBy(dx: -r, dy: -r)
    }
}

/// Glossy liquid drawn as one smooth field of `shapes` and `spikes` (rounded boxes, circles and
/// tapered cones merged with smooth minimums), in this view's own coordinates. Shaders/IslandFluid.metal.
/// UI controls embed it directly; IslandFluidView adds the Dynamic Island as a pill always merged in.
class LiquidCanvasView: VFXMetalView {
    var liquidColor: UIColor = .black
    /// Strength of the studio reflections: 1 for wet ferrofluid, lower for a calmer UI surface.
    var gloss: CGFloat = 1
    /// How far in from the outline the surface curves, points. Smaller = flatter, sharper rim light.
    var rimWidth: CGFloat = 9
    var shapes: [IslandFluidShape] = []
    var spikes: [IslandFluidSpike] = []

    /// A pill that is always part of the liquid (the Dynamic Island); none for a plain canvas.
    var anchorPill: CGRect? {
        nil
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Per-frame hook for controls that drive an embedded canvas instead of subclassing it.
    var onUpdate: ((CFTimeInterval) -> Void)?

    override func update(deltaTime: CFTimeInterval) {
        onUpdate?(deltaTime)
    }

    /// Draws one last frame and stops the display link until the next wake-up.
    func settle() {
        shapes = []
        spikes = []
        renderFrame()
        isPaused = true
    }

    override func encode(into commandBuffer: MTLCommandBuffer, target: MTLTexture) {
        guard let gpu, let pipeline = gpu.renderPipeline(vertex: "island_fluid_vertex", fragment: "island_fluid_fragment",
                                                         format: metalLayer.pixelFormat),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass(target: target)) else { return }

        var extent = anchorPill ?? .null
        shapes.forEach { extent = extent.union($0.extent) }
        spikes.forEach { extent = extent.union($0.extent) }
        guard !extent.isNull else {
            encoder.endEncoding()
            return
        }
        extent = extent.insetBy(dx: -3, dy: -3)

        // Only the pixels around the liquid run the fragment shader.
        let scale = contentScaleFactor
        let pixels = CGRect(x: extent.minX * scale, y: extent.minY * scale,
                            width: extent.width * scale, height: extent.height * scale)
            .integral
            .intersection(CGRect(x: 0, y: 0, width: target.width, height: target.height))
        guard !pixels.isNull, pixels.width > 0, pixels.height > 0 else {
            encoder.endEncoding()
            return
        }
        encoder.setScissorRect(MTLScissorRect(x: Int(pixels.minX), y: Int(pixels.minY),
                                              width: Int(pixels.width), height: Int(pixels.height)))

        // Without an anchor the pill is parked far off screen, where it never touches the liquid.
        let pill = anchorPill ?? CGRect(x: -10_000, y: -10_000, width: 0, height: 0)
        var uniforms = IslandFluidUniforms(
            viewport: SIMD2(Float(target.width), Float(target.height)),
            scale: Float(scale),
            gloss: Float(gloss),
            island: SIMD4(Float(pill.minX), Float(pill.minY), Float(pill.width), Float(pill.height)),
            color: liquidColor.vfxSIMD(with: traitCollection),
            bounds: SIMD4(Float(extent.minX), Float(extent.minY), Float(extent.maxX), Float(extent.maxY)),
            shapeCount: UInt32(shapes.count),
            spikeCount: UInt32(spikes.count),
            rimWidth: Float(rimWidth),
            time: Float(time))
        // Every declared buffer must be bound, even when its count is 0.
        let shapeData = shapes.isEmpty ? [IslandFluidShape.circle(center: .zero, radius: 0, blend: 0)] : shapes
        let spikeData = spikes.isEmpty
            ? [IslandFluidSpike(base: .zero, tip: .zero, baseRadius: 0, tipRadius: 0, blend: 0)] : spikes
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<IslandFluidUniforms>.stride, index: 0)
        encoder.setFragmentBytes(shapeData, length: MemoryLayout<IslandFluidShape>.stride * shapeData.count, index: 1)
        encoder.setFragmentBytes(spikeData, length: MemoryLayout<IslandFluidSpike>.stride * spikeData.count, index: 2)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}

/// Liquid that grows out of the Dynamic Island: a full-window, touch-through overlay whose liquid is
/// always merged with the island pill. Subclasses move the shapes in `update(deltaTime:)`.
class IslandFluidView: LiquidCanvasView {
    /// Island frame in window coordinates, slightly inset so a misaligned edge hides under the real one.
    private(set) var island: CGRect = .zero

    override var anchorPill: CGRect? {
        island
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        liquidColor = .black   // island black, so the liquid looks like part of the island
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Covers `window` and anchors the liquid to its Dynamic Island.
    func install(in window: UIWindow) {
        if superview !== window {
            window.addSubview(self)
        }
        frame = window.bounds
        island = DynamicIslandGeometry.frame(in: window).insetBy(dx: 1.5, dy: 1.5)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let window {
            island = DynamicIslandGeometry.frame(in: window).insetBy(dx: 1.5, dy: 1.5)
        }
    }

    /// Bottom center of the island: where liquid comes out.
    var islandMouth: CGPoint {
        CGPoint(x: island.midX, y: island.maxY)
    }

    /// The bump left under the island after liquid tears off or is swallowed, `t` seconds later:
    /// it springs out and wobbles back in over about a second.
    func recoilBump(_ t: CFTimeInterval, amplitude: CGFloat = 12) -> IslandFluidShape {
        let extent = amplitude * exp(-7 * t) * cos(18 * t)
        return .circle(center: CGPoint(x: islandMouth.x, y: islandMouth.y - 7 + max(extent, -4)), radius: 7, blend: 10)
    }
}

// MARK: - Springs

/// Damped spring on a point, integrated in small fixed steps so it stays stable at any frame rate.
struct IslandSpring {
    var position: CGPoint
    var velocity: CGVector = .zero
    /// Angular frequency, 1/s: higher = snappier.
    var stiffness: CGFloat
    /// 1 = critically damped, < 1 wobbles like jelly.
    var dampingRatio: CGFloat

    init(_ position: CGPoint, stiffness: CGFloat, dampingRatio: CGFloat) {
        self.position = position
        self.stiffness = stiffness
        self.dampingRatio = dampingRatio
    }

    mutating func step(toward target: CGPoint, deltaTime: CFTimeInterval) {
        let steps = max(1, Int(ceil(deltaTime / (1.0 / 480))))
        let dt = CGFloat(deltaTime) / CGFloat(steps)
        let k = stiffness * stiffness
        let c = 2 * dampingRatio * stiffness
        for _ in 0..<steps {
            velocity.dx += (k * (target.x - position.x) - c * velocity.dx) * dt
            velocity.dy += (k * (target.y - position.y) - c * velocity.dy) * dt
            position.x += velocity.dx * dt
            position.y += velocity.dy * dt
        }
    }

    var speed: CGFloat {
        hypot(velocity.dx, velocity.dy)
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}

/// Hermite step from 0 at `edge0` to 1 at `edge1`, like the shading language's smoothstep.
func islandSmoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
    let t = max(0, min(1, (x - edge0) / (edge1 - edge0)))
    return t * t * (3 - 2 * t)
}
