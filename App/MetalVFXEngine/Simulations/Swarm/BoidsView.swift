import UIKit
import Metal

/// Mirrors `BoidParams` in Boids.metal (56 bytes).
private struct BoidParams {
    var domain: SIMD2<Float>
    var finger: SIMD2<Float>
    var fingerStrength: Float
    var deltaTime: Float
    var minSpeed: Float
    var maxSpeed: Float
    var count: UInt32
    var flocking: UInt32
    var time: Float
    var boidSize: Float
    var maxNeighbors: UInt32
}

/// A school of fish using the original GPU spatial grid and flocking simulation.
final class BoidsView: MetalAnimationView {
    static let countRange: ClosedRange<Float> = 1_024...131_072
    private static let capacity = Int(countRange.upperBound)
    /// World height in perception radii; the grid cell equals the perception radius.
    private static let worldHeight: Float = 60

    private var count = 16_384
    private var needsReset = true
    private var domain = SIMD2<Float>(33, 60)
    private var current = 0

    private let grid = SpatialGrid(particleCapacity: capacity, cellCapacity: 20_000)
    private lazy var positions = [makeBuffer(), makeBuffer()]
    private lazy var velocities = [makeBuffer(), makeBuffer()]
    private var lastCommandBuffer: MTLCommandBuffer?

    private let updatePipeline = MetalEffectContext.shared?.computePipeline(function: "boids_update")
    private let renderPipeline = MetalEffectContext.shared?.renderPipeline(vertex: "boids_vertex", fragment: "boids_fragment")

    override var controls: [MetalEffectControl] {
        [
            .slider(
                title: "Рыб",
                range: Self.countRange,
                value: Float(count),
                isLogarithmic: true,
                format: { Self.rounded($0).formatted() },
                onChange: { [weak self] value in
                    self?.count = Self.rounded(value)
                    self?.needsReset = true
                }
            ),
            .button(title: "Перемешать") { [weak self] in
                self?.needsReset = true
            },
        ]
    }

    private static func rounded(_ value: Float) -> Int {
        max(1, Int((value / 1_024).rounded())) * 1_024
    }

    private func makeBuffer() -> MTLBuffer? {
        MetalEffectContext.shared?.device.makeBuffer(
            length: Self.capacity * MemoryLayout<SIMD2<Float>>.stride,
            options: .storageModeShared
        )
    }

    override func encode(into commandBuffer: MTLCommandBuffer, pass: MTLRenderPassDescriptor, uniforms: inout EffectUniforms) {
        guard let grid, let updatePipeline, let renderPipeline,
              let positionsA = positions[0], let positionsB = positions[1],
              let velocitiesA = velocities[0], let velocitiesB = velocities[1] else { return }
        let positionBuffers = [positionsA, positionsB]
        let velocityBuffers = [velocitiesA, velocitiesB]

        let aspect = uniforms.resolution.x / max(uniforms.resolution.y, 1)
        domain = SIMD2(Self.worldHeight * aspect, Self.worldHeight)
        if needsReset {
            needsReset = false
            scatter(into: positionBuffers[current], velocities: velocityBuffers[current])
        }

        let unitsPerPixel = domain.y / uniforms.resolution.y
        var params = BoidParams(
            domain: domain,
            finger: uniforms.touch * unitsPerPixel,
            fingerStrength: touch.isActive ? 1 : 0,
            deltaTime: 1.0 / 60,
            minSpeed: 2.5,
            maxSpeed: 6,
            count: UInt32(count),
            flocking: 1,
            time: uniforms.time,
            boidSize: max(0.55 * pow(4_096 / Float(count), 0.3), 0.18),
            maxNeighbors: 32
        )
        var gridParams = GridParams(
            origin: .zero,
            cellSize: 1,
            dims: SIMD2(UInt32(ceil(domain.x)), UInt32(ceil(domain.y))),
            count: UInt32(count)
        )

        if let compute = commandBuffer.makeComputeCommandEncoder() {
            grid.build(with: compute, positions: positionBuffers[current], params: gridParams)
            compute.setBuffer(positionBuffers[current], offset: 0, index: 0)
            compute.setBuffer(velocityBuffers[current], offset: 0, index: 1)
            compute.setBuffer(grid.cellStart, offset: 0, index: 2)
            compute.setBuffer(grid.cellCounts, offset: 0, index: 3)
            compute.setBuffer(grid.sortedIndices, offset: 0, index: 4)
            compute.setBytes(&gridParams, length: MemoryLayout<GridParams>.stride, index: 5)
            compute.setBytes(&params, length: MemoryLayout<BoidParams>.stride, index: 6)
            compute.setBuffer(positionBuffers[1 - current], offset: 0, index: 7)
            compute.setBuffer(velocityBuffers[1 - current], offset: 0, index: 8)
            compute.dispatch(updatePipeline, count: count)
            compute.endEncoding()
            current = 1 - current
        }

        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.01, green: 0.04, blue: 0.08, alpha: 1)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(renderPipeline)
        encoder.setVertexBuffer(positionBuffers[current], offset: 0, index: 0)
        encoder.setVertexBuffer(velocityBuffers[current], offset: 0, index: 1)
        encoder.setVertexBytes(&params, length: MemoryLayout<BoidParams>.stride, index: 2)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3, instanceCount: count)
        encoder.endEncoding()
        lastCommandBuffer = commandBuffer
    }

    private func scatter(into positions: MTLBuffer, velocities: MTLBuffer) {
        lastCommandBuffer?.waitUntilCompleted()
        let points = positions.contents().bindMemory(to: SIMD2<Float>.self, capacity: count)
        let speeds = velocities.contents().bindMemory(to: SIMD2<Float>.self, capacity: count)
        for index in 0..<count {
            points[index] = SIMD2(Float.random(in: 1...(domain.x - 1)), Float.random(in: 1...(domain.y - 1)))
            let angle = Float.random(in: 0..<(2 * .pi))
            speeds[index] = SIMD2(cos(angle), sin(angle)) * 4
        }
    }
}
