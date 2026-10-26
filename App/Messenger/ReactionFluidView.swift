import UIKit
import Metal

/// A message's visible silhouette, in the fluid overlay's local points.
struct ReactionFluidObstacle {
    let rect: CGRect
    /// Corner radii in points, ordered top-left, top-right, bottom-right, bottom-left.
    let corners: SIMD4<Float>

    init(rect: CGRect, corners: SIMD4<Float>) {
        self.rect = rect
        self.corners = corners
    }

    init(rect: CGRect, cornerRadius: CGFloat) {
        self.init(rect: rect, corners: SIMD4(repeating: Float(cornerRadius)))
    }
}

// Every field is a 16-byte vector. Keep the layout in sync with ReactionFluid.metal.
private struct ReactionFluidUniforms {
    var grid: SIMD4<Float>
    var dynamics: SIMD4<Float>
    var counts: SIMD4<UInt32>
    var appearance: SIMD4<Float>
}

private struct FluidSplat {
    var positionVelocity: SIMD4<Float>
    var colorDensity: SIMD4<Float>
    var shape: SIMD4<Float>
}

private struct FluidObstacle {
    var rect: SIMD4<Float>
    var corners: SIMD4<Float>
}

private struct FluidSink {
    var positionRadius: SIMD4<Float>
    var timing: SIMD4<Float>
}

/// A small RGB fluid simulation shared by concurrent message reactions. UIKit remains interactive
/// underneath it; the chat supplies message geometry without taking per-frame snapshots.
final class ReactionFluidView: VFXMetalView {
    var geometryProvider: (() -> [ReactionFluidObstacle])?
    private(set) var isActive = false

    private struct Reaction {
        let startedAt: CFTimeInterval
        var source: CGRect
        var origin: CGPoint
        let color: SIMD3<Float>
        let target: () -> CGPoint?
        let completion: () -> Void
        let spin: CGFloat
        var lastTarget: CGPoint
    }

    private struct Pipelines {
        let clear: MTLComputePipelineState
        let obstacles: MTLComputePipelineState
        let advectVelocity: MTLComputePipelineState
        let curl: MTLComputePipelineState
        let vorticity: MTLComputePipelineState
        let divergence: MTLComputePipelineState
        let pressure: MTLComputePipelineState
        let project: MTLComputePipelineState
        let advectDye: MTLComputePipelineState
        let render: MTLRenderPipelineState
    }

    private let cellSize: CGFloat = 3
    private let stepRate: Double = 120
    private let duration: Double = 2.4
    private let maxSplats = 48
    private var pipelines: Pipelines?
    private var reactions: [Reaction] = []
    private var obstacles: [ReactionFluidObstacle] = []
    private var splats: [FluidSplat] = []
    private var velocity: [MTLTexture] = []
    private var dye: [MTLTexture] = []
    private var pressure: [MTLTexture] = []
    private var divergence: MTLTexture?
    private var curl: MTLTexture?
    private var obstacleMask: MTLTexture?
    private var grid = SIMD2<Float>(1, 1)
    private var needsClear = true
    private var accumulator: Double = 0
    private var stepsThisFrame = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        preferredFramesPerSecond = 60
        isPaused = true
        isHidden = true
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stop() }
    }

    /// Returns false when the caller should use its standard UIKit reaction animation.
    /// Once accepted, the completion runs exactly once, asynchronously on the main queue, even
    /// when stopped, resized, or displaced by a fifth reaction. The caller owns chip visibility.
    @discardableResult
    func play(
        emoji: String,
        from point: CGPoint,
        around source: CGRect,
        target: @escaping () -> CGPoint?,
        completion: @escaping () -> Void
    ) -> Bool {
        guard !UIAccessibility.isReduceMotionEnabled, gpu != nil, window != nil,
              bounds.width > 0, bounds.height > 0, loadPipelines() else { return false }
        layoutIfNeeded()
        if velocity.count != 2 { allocateTextures() }
        guard texturesReady else { return false }

        // Retiring a reaction cannot leave its caller's reaction chip hidden.
        if reactions.count == 4 {
            finish([reactions.removeFirst()])
        }
        if !isActive {
            needsClear = true
            accumulator = 0
            splats.removeAll(keepingCapacity: true)
        }
        obstacles = Array((geometryProvider?() ?? []).prefix(64))
        let origin = fluidPoint(point, outside: source)
        reactions.append(Reaction(startedAt: time, source: source, origin: origin,
                                  color: reactionColor(emoji), target: target, completion: completion,
                                  spin: reactions.count.isMultiple(of: 2) ? 1 : -1,
                                  lastTarget: target() ?? CGPoint(x: source.midX, y: source.maxY + 18)))
        isActive = true
        isHidden = false
        isPaused = false
        return true
    }

    /// Touches observed by the chat stir existing dye; this view never intercepts gestures.
    func stir(at point: CGPoint, velocity touchVelocity: CGVector) {
        guard isActive, !UIAccessibility.isReduceMotionEnabled else { return }
        let position = fluidPoint(point)
        appendSplat(at: position,
                    velocity: CGVector(dx: touchVelocity.dx * 0.42, dy: touchVelocity.dy * 0.42),
                    radius: 18, color: .zero, density: 0)
    }

    func stop() {
        let finished = reactions
        reactions.removeAll(keepingCapacity: true)
        splats.removeAll(keepingCapacity: true)
        isActive = false
        isPaused = true
        isHidden = true
        accumulator = 0
        stepsThisFrame = 0
        needsClear = true
        finish(finished)
    }

    private func finish(_ finished: [Reaction]) {
        guard !finished.isEmpty else { return }
        DispatchQueue.main.async {
            for reaction in finished { reaction.completion() }
        }
    }

    override func drawableSizeDidChange(_ size: CGSize) {
        // A rotated/resized chat has different obstacle and target coordinates. End the old
        // simulation instead of stretching a stale mask across the new message layout.
        if isActive { stop() }
        allocateTextures()
    }

    private var texturesReady: Bool {
        velocity.count == 2 && dye.count == 2 && pressure.count == 2 &&
        divergence != nil && curl != nil && obstacleMask != nil
    }

    private func allocateTextures() {
        guard let gpu, bounds.width > 0, bounds.height > 0 else { return }
        let width = max(2, Int(ceil(bounds.width / cellSize)))
        let height = max(2, Int(ceil(bounds.height / cellSize)))
        grid = SIMD2(Float(width), Float(height))
        func texture(_ format: MTLPixelFormat, _ label: String) -> MTLTexture? {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format,
                                                                      width: width, height: height,
                                                                      mipmapped: false)
            descriptor.storageMode = .private
            descriptor.usage = [.shaderRead, .shaderWrite]
            let texture = gpu.device.makeTexture(descriptor: descriptor)
            texture?.label = "Reaction fluid: \(label)"
            return texture
        }
        velocity = (0..<2).compactMap { texture(.rg16Float, "velocity \($0)") }
        dye = (0..<2).compactMap { texture(.rgba16Float, "RGB dye \($0)") }
        pressure = (0..<2).compactMap { texture(.r16Float, "pressure \($0)") }
        divergence = texture(.r16Float, "divergence")
        curl = texture(.r16Float, "curl")
        obstacleMask = texture(.r16Float, "message distance field")
        needsClear = true
    }

    private func loadPipelines() -> Bool {
        if pipelines != nil { return true }
        guard let gpu else { return false }
        // VFXGPU asserts on a missing function in debug. Missing shader support is a normal
        // fallback here, so inspect the library before requesting its cached pipeline states.
        let names = ["reaction_clear", "reaction_obstacles", "reaction_advect_velocity",
                     "reaction_curl", "reaction_vorticity", "reaction_divergence",
                     "reaction_pressure", "reaction_project", "reaction_advect_dye",
                     "reaction_vertex", "reaction_fragment"]
        guard names.allSatisfy({ gpu.library.makeFunction(name: $0) != nil }),
              let clear = gpu.computePipeline("reaction_clear"),
              let obstacles = gpu.computePipeline("reaction_obstacles"),
              let advectVelocity = gpu.computePipeline("reaction_advect_velocity"),
              let curl = gpu.computePipeline("reaction_curl"),
              let vorticity = gpu.computePipeline("reaction_vorticity"),
              let divergence = gpu.computePipeline("reaction_divergence"),
              let pressure = gpu.computePipeline("reaction_pressure"),
              let project = gpu.computePipeline("reaction_project"),
              let advectDye = gpu.computePipeline("reaction_advect_dye"),
              let render = gpu.renderPipeline(vertex: "reaction_vertex", fragment: "reaction_fragment")
        else { return false }
        pipelines = Pipelines(clear: clear, obstacles: obstacles, advectVelocity: advectVelocity,
                              curl: curl, vorticity: vorticity, divergence: divergence,
                              pressure: pressure, project: project, advectDye: advectDye, render: render)
        return true
    }

    override func update(deltaTime: CFTimeInterval) {
        guard isActive else { return }
        if UIAccessibility.isReduceMotionEnabled {
            stop()
            return
        }
        let expired = reactions.filter { time - $0.startedAt >= duration }
        reactions.removeAll { time - $0.startedAt >= duration }
        finish(expired)
        guard !reactions.isEmpty else {
            stop()
            return
        }
        obstacles = Array((geometryProvider?() ?? []).prefix(64))
        var missingTargets: [Reaction] = []
        reactions = reactions.compactMap { reaction in
            guard let current = reaction.target() else {
                missingTargets.append(reaction)
                return nil
            }
            // During the brief emission stage the source follows the same scroll/layout delta
            // as its chip. Existing dye stays in screen space and meets the live obstacle mask.
            var updated = reaction
            let dx = current.x - reaction.lastTarget.x
            let dy = current.y - reaction.lastTarget.y
            updated.source = reaction.source.offsetBy(dx: dx, dy: dy)
            updated.origin = CGPoint(x: reaction.origin.x + dx, y: reaction.origin.y + dy)
            updated.lastTarget = current
            return updated
        }
        finish(missingTargets)
        guard !reactions.isEmpty else {
            stop()
            return
        }
        accumulator = min(accumulator + deltaTime * stepRate, 3)
        stepsThisFrame = Int(accumulator)
        accumulator -= Double(stepsThisFrame)
        if stepsThisFrame > 0 {
            for reaction in reactions where time - reaction.startedAt < 0.42 {
                emit(reaction, deltaTime: deltaTime)
            }
        }
    }

    private func emit(_ reaction: Reaction, deltaTime: Double) {
        let age = CGFloat(time - reaction.startedAt)
        let rect = reaction.source
        let outward: CGFloat = 8
        let wobble = sin(age * 27) * 0.08
        let speed: CGFloat = 360 + 150 * sin(min(1, age / 0.42) * .pi)
        let density = Float(min(deltaTime * 60, 2)) * 0.16
        let spin = reaction.spin
        // Multiple tangential jets are deliberately outside the solid message. They create
        // visible wraparound at both long edges and turn into eddies at the rounded corners.
        let jets: [(CGPoint, CGVector)] = [
            (CGPoint(x: rect.minX + rect.width * (0.25 + wobble), y: rect.minY - outward),
             CGVector(dx: speed * spin, dy: -speed * 0.13)),
            (CGPoint(x: rect.minX + rect.width * (0.72 - wobble), y: rect.minY - outward),
             CGVector(dx: speed * spin, dy: -speed * 0.16)),
            (CGPoint(x: rect.maxX + outward, y: rect.midY),
             CGVector(dx: speed * 0.1, dy: speed * spin)),
            (CGPoint(x: rect.minX + rect.width * 0.72, y: rect.maxY + outward),
             CGVector(dx: -speed * spin, dy: speed * 0.14)),
            (CGPoint(x: rect.minX + rect.width * 0.28, y: rect.maxY + outward),
             CGVector(dx: -speed * spin, dy: speed * 0.12)),
            (CGPoint(x: rect.minX - outward, y: rect.midY),
             CGVector(dx: -speed * 0.1, dy: -speed * spin)),
        ]
        for (position, velocity) in jets where bounds.insetBy(dx: 3, dy: 3).contains(position) {
            appendSplat(at: fluidPoint(position), velocity: velocity, radius: 13,
                        color: reaction.color, density: density)
        }
        // The selected edge gets a broader pulse so each reaction has a clear point of origin.
        appendSplat(at: fluidPoint(reaction.origin),
                    velocity: CGVector(dx: speed * 0.5 * spin, dy: -speed * 0.45),
                    radius: 16, color: reaction.color, density: density * 1.25)
    }

    private func appendSplat(
        at point: CGPoint,
        velocity: CGVector,
        radius: CGFloat,
        color: SIMD3<Float>,
        density: Float
    ) {
        guard splats.count < maxSplats else { return }
        let speed = hypot(velocity.dx, velocity.dy)
        let scale: CGFloat = speed > 1100 ? 1100 / speed : 1
        splats.append(FluidSplat(
            positionVelocity: SIMD4(Float(point.x / cellSize), Float(point.y / cellSize),
                                    Float(velocity.dx * scale / cellSize), Float(velocity.dy * scale / cellSize)),
            colorDensity: SIMD4(color.x, color.y, color.z, density),
            shape: SIMD4(Float(radius / cellSize), 0, 0, 0)))
    }

    /// Move an emitter out of a bubble instead of injecting all its dye into a solid texel.
    private func fluidPoint(_ point: CGPoint, outside source: CGRect? = nil) -> CGPoint {
        let safe = bounds.insetBy(dx: 4, dy: 4)
        var result = CGPoint(x: min(max(point.x, safe.minX), safe.maxX),
                             y: min(max(point.y, safe.minY), safe.maxY))
        let solids = (source.map { [$0] } ?? []) + obstacles.map(\.rect)
        for _ in 0..<3 {
            var moved = false
            for rect in solids where rect.contains(result) {
                let options = [CGPoint(x: rect.minX - 6, y: result.y),
                               CGPoint(x: rect.maxX + 6, y: result.y),
                               CGPoint(x: result.x, y: rect.minY - 6),
                               CGPoint(x: result.x, y: rect.maxY + 6)]
                if let closest = options.filter({ safe.contains($0) }).min(by: {
                    hypot($0.x - result.x, $0.y - result.y) < hypot($1.x - result.x, $1.y - result.y)
                }) {
                    result = closest
                    moved = true
                }
            }
            if !moved { break }
        }
        return result
    }

    private func reactionColor(_ emoji: String) -> SIMD3<Float> {
        switch emoji {
        case Reactions.gas: return SIMD3(0.35, 0.78, 1)
        case "❤️", "❤", "💗", "💖", "😍": return SIMD3(1, 0.1, 0.38)
        case "🔥", "🎉", "⚡", "🤣", "😂": return SIMD3(1, 0.48, 0.06)
        case "👍", "👏", "⭐", "🌟": return SIMD3(0.18, 0.65, 1)
        case "💚", "✅": return SIMD3(0.14, 0.95, 0.57)
        default: return SIMD3(0.64, 0.28, 1)
        }
    }

    private func currentSinks() -> [FluidSink] {
        reactions.map { reaction in
            let age = Float(time - reaction.startedAt)
            let progress = max(0, min(1, (age - 1.1) / 0.65))
            let point = fluidPoint(reaction.lastTarget)
            return FluidSink(positionRadius: SIMD4(Float(point.x / cellSize), Float(point.y / cellSize),
                                                     Float(18 / cellSize), progress * 1500),
                               timing: SIMD4(progress, 24, 0, 0))
        }
    }

    private func uniforms(splatCount: Int, sinkCount: Int) -> ReactionFluidUniforms {
        // A short final fade catches isolated drops that cannot reach a chip through a narrow gap.
        let youngest = reactions.map { time - $0.startedAt }.min() ?? duration
        let fade = Float(max(0, min(1, (duration - youngest) / 0.3)))
        return ReactionFluidUniforms(grid: SIMD4(grid.x, grid.y, Float(cellSize), Float(1 / stepRate)),
                               dynamics: SIMD4(0.65, 0.28, 24, Float(time)),
                               counts: SIMD4(UInt32(splatCount), UInt32(obstacles.count), UInt32(sinkCount), 0),
                               appearance: SIMD4(fade, 0.9, 0, 0))
    }

    override func encode(into commandBuffer: MTLCommandBuffer, target: MTLTexture) {
        guard isActive, texturesReady, let p = pipelines, let divergence, let curl, let mask = obstacleMask else {
            super.encode(into: commandBuffer, target: target)
            return
        }
        let sinks = currentSinks()
        let gpuObstacles = obstacles.map { obstacle in
            FluidObstacle(rect: SIMD4(Float(obstacle.rect.minX / cellSize), Float(obstacle.rect.minY / cellSize),
                                        Float(obstacle.rect.width / cellSize), Float(obstacle.rect.height / cellSize)),
                            corners: obstacle.corners / Float(cellSize))
        }
        var renderUniforms = uniforms(splatCount: 0, sinkCount: sinks.count)
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.label = "Reaction fluid simulation"
        let threads = MTLSize(width: 16, height: 16, depth: 1)
        let groups = MTLSize(width: (Int(grid.x) + 15) / 16, height: (Int(grid.y) + 15) / 16, depth: 1)

        func run(
            _ pipeline: MTLComputePipelineState,
            _ textures: [MTLTexture],
            _ uniforms: inout ReactionFluidUniforms,
            batch: [FluidSplat] = []
        ) {
            encoder.setComputePipelineState(pipeline)
            for (index, texture) in textures.enumerated() { encoder.setTexture(texture, index: index) }
            encoder.setBytes(&uniforms, length: MemoryLayout<ReactionFluidUniforms>.stride, index: 0)
            // Metal requires a valid buffer binding even for a zero-count array. setBytes copies
            // the values into this command buffer, so CPU changes cannot race an in-flight frame.
            let splatData = batch.isEmpty ? [FluidSplat(positionVelocity: .zero, colorDensity: .zero, shape: .zero)] : batch
            let obstacleData = gpuObstacles.isEmpty ? [FluidObstacle(rect: .zero, corners: .zero)] : gpuObstacles
            let sinkData = sinks.isEmpty ? [FluidSink(positionRadius: .zero, timing: .zero)] : sinks
            encoder.setBytes(splatData, length: MemoryLayout<FluidSplat>.stride * splatData.count, index: 1)
            encoder.setBytes(obstacleData, length: MemoryLayout<FluidObstacle>.stride * obstacleData.count, index: 2)
            encoder.setBytes(sinkData, length: MemoryLayout<FluidSink>.stride * sinkData.count, index: 3)
            encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threads)
        }

        if needsClear {
            needsClear = false
            for texture in velocity + dye + pressure + [divergence, curl, mask] {
                run(p.clear, [texture], &renderUniforms)
            }
        }
        // Rebuild the small signed-distance field from current UIKit rectangles while scrolling.
        run(p.obstacles, [mask], &renderUniforms)
        if stepsThisFrame > 0 {
            // A warm pressure field from a previous message layout can kick the fluid on scroll.
            for texture in pressure { run(p.clear, [texture], &renderUniforms) }
            for step in 0..<stepsThisFrame {
                let batch = step == 0 ? splats : []
                var u = uniforms(splatCount: batch.count, sinkCount: sinks.count)
                run(p.advectVelocity, [velocity[0], velocity[1], mask], &u, batch: batch)
                run(p.curl, [velocity[1], curl, mask], &u)
                run(p.vorticity, [velocity[1], curl, velocity[0], mask], &u)
                run(p.divergence, [velocity[0], divergence, mask], &u)
                for _ in 0..<18 {
                    run(p.pressure, [pressure[0], divergence, pressure[1], mask], &u)
                    pressure.swapAt(0, 1)
                }
                run(p.project, [velocity[0], pressure[0], velocity[1], mask], &u)
                velocity.swapAt(0, 1)
                run(p.advectDye, [dye[0], velocity[0], dye[1], mask], &u, batch: batch)
                dye.swapAt(0, 1)
            }
            splats.removeAll(keepingCapacity: true)
        }
        encoder.endEncoding()

        guard let render = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass(target: target)) else { return }
        render.label = "Reaction fluid transparent composite"
        render.setRenderPipelineState(p.render)
        render.setFragmentTexture(dye[0], index: 0)
        render.setFragmentTexture(mask, index: 1)
        render.setFragmentBytes(&renderUniforms, length: MemoryLayout<ReactionFluidUniforms>.stride, index: 0)
        render.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        render.endEncoding()
    }
}
