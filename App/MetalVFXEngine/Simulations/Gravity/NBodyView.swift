import UIKit
import Metal

/// Mirrors `NBodyParams` in NBody.metal (48 bytes).
private struct NBodyParams {
    var count: UInt32
    var deltaTime: Float
    var softening2: Float
    var gravity: Float
    var attractor: SIMD2<Float>
    var attractorMass: Float
    var pointSize: Float
    var viewScale: SIMD2<Float>
    var brightness: Float
    var galaxySplit: UInt32
}

/// Two colliding galaxies simulated by the original tiled GPU gravity kernel.
final class NBodyView: MetalAnimationView {
    static let countRange: ClosedRange<Float> = 1_024...65_536
    private static let stepTime: Float = 0.0035
    private static let ringSize = 3

    private var bodyCount = 8_192
    private let stepPipeline = MetalEffectContext.shared?.computePipeline(function: "nbody_step")
    private let renderPipeline = MetalEffectContext.shared?.renderPipeline(
        vertex: "nbody_vertex",
        fragment: "nbody_fragment",
        blending: .additive
    )
    /// Shared buffers are seeded with the initial galaxy positions.
    private let ring: [MTLBuffer] = (0..<ringSize).compactMap { _ in
        MetalEffectContext.shared?.device.makeBuffer(
            length: Int(countRange.upperBound) * MemoryLayout<SIMD4<Float>>.stride,
            options: .storageModeShared
        )
    }
    private var current = 0
    private var needsReset = true
    private var lastCommandBuffer: MTLCommandBuffer?
    private var attractor: SIMD2<Float> = .zero
    private var attractorMass: Float = 0

    override var controls: [MetalEffectControl] {
        [
            .slider(
                title: "Тел",
                range: Self.countRange,
                value: Float(bodyCount),
                isLogarithmic: true,
                format: { Self.roundedCount($0).formatted() },
                onChange: { [weak self] value in
                    self?.bodyCount = Self.roundedCount(value)
                    self?.needsReset = true
                }
            ),
            .button(title: "Столкнуть галактики заново") { [weak self] in
                self?.needsReset = true
            },
        ]
    }

    private static func roundedCount(_ value: Float) -> Int {
        max(1, Int((value / 1_024).rounded())) * 1_024
    }

    // MARK: - Simulation

    override func update(_ uniforms: inout EffectUniforms, deltaTime: Double) {
        let viewScale = Self.viewScale(for: uniforms.resolution)
        // Finger → world: a heavy attractor while touching.
        let clip = uniforms.touch / uniforms.resolution * 2 - 1
        attractor = SIMD2(clip.x, -clip.y) / viewScale
        attractorMass = touch.isActive ? 1.5 : 0

        guard ring.count == Self.ringSize else { return }
        if needsReset {
            needsReset = false
            resetGalaxies()
        }
    }

    override func encode(into commandBuffer: MTLCommandBuffer, pass: MTLRenderPassDescriptor, uniforms: inout EffectUniforms) {
        guard ring.count == Self.ringSize, let stepPipeline, let renderPipeline else { return }
        var params = makeParams(resolution: uniforms.resolution)

        if let compute = commandBuffer.makeComputeCommandEncoder() {
            let next = (current + 1) % Self.ringSize
            compute.setBuffer(ring[current], offset: 0, index: 0)
            compute.setBuffer(ring[next], offset: 0, index: 1)
            compute.setBytes(&params, length: MemoryLayout<NBodyParams>.stride, index: 2)
            compute.dispatch(stepPipeline, count: bodyCount)
            compute.endEncoding()
            current = next
        }

        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0.015, alpha: 1)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(renderPipeline)
        encoder.setVertexBuffer(ring[current], offset: 0, index: 0)
        encoder.setVertexBytes(&params, length: MemoryLayout<NBodyParams>.stride, index: 1)
        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: bodyCount)
        encoder.endEncoding()
        lastCommandBuffer = commandBuffer
    }

    private func makeParams(resolution: SIMD2<Float>) -> NBodyParams {
        NBodyParams(
            count: UInt32(bodyCount),
            deltaTime: Self.stepTime,
            softening2: 0.0004,
            gravity: 1,
            attractor: attractor,
            attractorMass: attractorMass,
            pointSize: bodyCount > 16_384 ? 2 : 3,
            viewScale: Self.viewScale(for: resolution),
            brightness: min(max(6_000 / Float(bodyCount), 0.15), 1),
            galaxySplit: UInt32(bodyCount / 2)
        )
    }

    /// Fits a world 2.6 units tall into the view.
    private static func viewScale(for resolution: SIMD2<Float>) -> SIMD2<Float> {
        let y: Float = 2 / 2.6
        return SIMD2(y * resolution.y / max(resolution.x, 1), y)
    }

    private func resetGalaxies() {
        lastCommandBuffer?.waitUntilCompleted()
        let bodies = Self.makeGalaxies(count: bodyCount)
        bodies.withUnsafeBytes { bytes in
            ring[current].contents().copyMemory(from: bytes.baseAddress!, byteCount: bytes.count)
        }
    }

    /// Two rotating disks on a collision course; each body starts on a circular orbit.
    private static func makeGalaxies(count: Int) -> [SIMD4<Float>] {
        var generator = SystemRandomNumberGenerator()
        let half = count / 2
        let radius: Float = 0.35
        let galaxyMass: Float = 0.5    // G × mass of one galaxy (total G × M = 1)
        let centers: [SIMD2<Float>] = [SIMD2(-0.55, -0.35), SIMD2(0.55, 0.35)]
        let drift: [SIMD2<Float>] = [SIMD2(0.12, 0.08), SIMD2(-0.12, -0.08)]
        let spin: [Float] = [1, -1]

        return (0..<count).map { index in
            let galaxy = index < half ? 0 : 1
            // r = R·u puts enclosed mass ∝ r, which gives a flat rotation curve v = √(G·M / R)
            // like real disk galaxies (and keeps the dense core from flinging stars out).
            let r = radius * Float.random(in: 0.03...1, using: &generator)
            let angle = Float.random(in: 0..<(2 * .pi), using: &generator)
            let offset = SIMD2(cos(angle), sin(angle)) * r
            let speed = sqrt(galaxyMass / radius)
            let tangent = SIMD2(-sin(angle), cos(angle)) * speed * spin[galaxy]
            let position = centers[galaxy] + offset
            let velocity = tangent + drift[galaxy]
            return SIMD4(position.x, position.y, velocity.x, velocity.y)
        }
    }
}

