//
//  InkWellOverlay.swift
//  controller
//
//  The Dynamic Island as an inkwell. Two uses:
//  - `InkWellOverlay.transition(in:changes:)`: ink pours out of the island over the current screen;
//    wherever it has been, the new screen shows through once the ink is sucked back into the island.
//  - `attach(to:)`: draw with ink over live UI; after a pause the island drinks it back.
//  Fluid solver: Shaders/IslandInk.metal.
//

import UIKit
import Metal

/// Mirrors `InkUniforms` in IslandInk.metal.
private struct InkUniforms {
    var grid: SIMD2<Float>
    var dt: Float
    var cell: Float
    var velocityDecay: Float
    var dyeDecay: Float
    var vorticity: Float
    var splatCount: UInt32
    var sink: SIMD2<Float>
    var suction: Float
    var sinkRadius: Float
    var coverThreshold: Float
    var time: Float
    var gravity: Float
    var unused: Float = 0
}

/// Mirrors `InkSplat` in IslandInk.metal.
private struct InkSplat {
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var radius: Float
    var dye: Float
    var unused: SIMD2<Float> = .zero
}

/// Mirrors `InkRenderUniforms` in IslandInk.metal.
private struct InkRenderUniforms {
    var inkColor: SIMD4<Float>
    var edgeColor: SIMD4<Float>
    var texel: SIMD2<Float>
    var fade: Float
    var underFade: Float
    var hasSnapshot: UInt32
    var unused: Float = 0
    var unused2: SIMD2<Float> = .zero
}

final class InkWellOverlay: VFXMetalView {
    private enum Mode {
        case transition
        case drawing
    }

    /// Covers `window` with a snapshot of it, runs `changes` (e.g. a push without animation) under
    /// the cover, then pours ink from the island; the new screen appears wherever the ink has been.
    static func transition(in window: UIWindow, changes: () -> Void, completion: (() -> Void)? = nil) {
        guard let snapshot = VFXGPU.shared?.makeTexture(snapshotting: window, scale: window.traitCollection.displayScale)
        else {
            changes()
            completion?()
            return
        }
        let overlay = InkWellOverlay(mode: .transition)
        overlay.snapshot = snapshot
        overlay.frame = window.bounds
        overlay.isUserInteractionEnabled = true   // swallow taps until the new screen is revealed
        overlay.onFinish = { [weak overlay] in
            overlay?.removeFromSuperview()
            completion?()
        }
        window.addSubview(overlay)
        overlay.sink = DynamicIslandGeometry.frame(in: window)
        changes()
        window.bringSubviewToFront(overlay)
    }

    /// Ink as dark as the island, with a deep blue where it thins out.
    var inkColor = UIColor(red: 0.02, green: 0.02, blue: 0.05, alpha: 1)
    var edgeColor = UIColor(red: 0.12, green: 0.16, blue: 0.48, alpha: 1)
    /// Simulation cell size, points: smaller = finer swirls, more GPU work.
    var cellSize: CGFloat = 4
    /// Drawing mode: how long after the last touch the island starts drinking the ink back.
    var calmDelay: TimeInterval = 1.4

    private let mode: Mode
    private var onFinish: (() -> Void)?
    private var snapshot: MTLTexture?
    private var sink: CGRect = .zero
    private weak var hostView: UIView?
    private let observer = TouchObserverGestureRecognizer()

    private var velocity: [MTLTexture] = []
    private var dye: [MTLTexture] = []
    private var pressure: [MTLTexture] = []
    private var divergence: MTLTexture?
    private var curl: MTLTexture?
    private var grid = SIMD2<Float>(1, 1)
    private var needsClear = true

    private var splats: [InkSplat] = []
    private var stepAccumulator: Double = 0
    private var stepsThisFrame = 0
    private let stepRate: Double = 120
    private var lastTouchTime: CFTimeInterval = -.infinity
    private var lastTouch: (point: CGPoint, time: CFTimeInterval)?
    private var finished = false
    private let haptic = UIImpactFeedbackGenerator(style: .soft)

    private init(mode: Mode) {
        self.mode = mode
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        observer.onTouch = { [weak self] point, phase in self?.handleTouch(at: point, phase: phase) }
    }

    convenience init() {
        self.init(mode: .drawing)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Drawing mode

    /// Lays the ink over `host` (as a sibling right above it) and draws with its touches.
    func attach(to host: UIView) {
        guard let container = host.superview else { return }
        detach()
        hostView = host
        // Pinned rather than copying host.frame: the host may not be laid out yet.
        translatesAutoresizingMaskIntoConstraints = false
        container.insertSubview(self, aboveSubview: host)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: host.topAnchor),
            bottomAnchor.constraint(equalTo: host.bottomAnchor),
            leadingAnchor.constraint(equalTo: host.leadingAnchor),
            trailingAnchor.constraint(equalTo: host.trailingAnchor),
        ])
        host.addGestureRecognizer(observer)
        isHidden = true
        isPaused = true
    }

    func detach() {
        hostView?.removeGestureRecognizer(observer)
        hostView = nil
        removeFromSuperview()
    }

    private func handleTouch(at hostPoint: CGPoint, phase: UITouch.Phase) {
        guard let host = hostView else { return }
        let point = host.convert(hostPoint, to: self)
        if isHidden {
            isHidden = false
            needsClear = true
            haptic.prepare()
        }
        if let window {
            sink = window.convert(DynamicIslandGeometry.frame(in: window), to: self)
        }
        isPaused = false
        lastTouchTime = time
        switch phase {
        case .began:
            // A blot where the pen lands.
            addSplat(at: point, velocity: .zero, radius: 18, dye: 1.6)
            lastTouch = (point, time)
        case .moved:
            if let last = lastTouch {
                let dt = max(time - last.time, 1.0 / 240)
                let v = CGVector(dx: (point.x - last.point.x) / dt, dy: (point.y - last.point.y) / dt)
                // A few splats along the segment, so fast strokes stay continuous.
                let steps = max(1, Int(point.distance(to: last.point) / 6))
                for i in 1...steps {
                    let t = CGFloat(i) / CGFloat(steps)
                    let p = CGPoint(x: last.point.x + (point.x - last.point.x) * t, y: last.point.y + (point.y - last.point.y) * t)
                    // The pen drags the water only gently, so strokes stay strokes instead of smoke.
                    addSplat(at: p, velocity: CGVector(dx: v.dx * 0.3, dy: v.dy * 0.3), radius: 9, dye: 1.1)
                }
            }
            lastTouch = (point, time)
        default:
            lastTouch = nil
        }
    }

    // MARK: Simulation

    /// `velocity` in points per second, `radius` in points.
    private func addSplat(at point: CGPoint, velocity: CGVector, radius: CGFloat, dye: CGFloat) {
        let speedLimit: CGFloat = 2400
        let speed = hypot(velocity.dx, velocity.dy)
        let clamp = speed > speedLimit ? speedLimit / speed : 1
        splats.append(InkSplat(position: SIMD2(Float(point.x / cellSize), Float(point.y / cellSize)),
                               velocity: SIMD2(Float(velocity.dx * clamp / cellSize), Float(velocity.dy * clamp / cellSize)),
                               radius: Float(radius / cellSize), dye: Float(dye)))
    }

    override func drawableSizeDidChange(_ size: CGSize) {
        guard let gpu, bounds.width > 0 else { return }
        let width = Int(ceil(bounds.width / cellSize)), height = Int(ceil(bounds.height / cellSize))
        grid = SIMD2(Float(width), Float(height))
        func make(_ format: MTLPixelFormat) -> MTLTexture? {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width,
                                                                      height: height, mipmapped: false)
            descriptor.usage = [.shaderRead, .shaderWrite]
            descriptor.storageMode = .shared
            return gpu.device.makeTexture(descriptor: descriptor)
        }
        velocity = (0..<2).compactMap { _ in make(.rg16Float) }
        dye = (0..<2).compactMap { _ in make(.rg16Float) }
        pressure = (0..<2).compactMap { _ in make(.r16Float) }
        divergence = make(.r16Float)
        curl = make(.r16Float)
        needsClear = true
    }

    /// Where the ink pours from / drains into, in cells.
    private var sinkCell: SIMD2<Float> {
        SIMD2(Float(sink.midX / cellSize), Float((sink.maxY - 4) / cellSize))
    }

    override func update(deltaTime: CFTimeInterval) {
        stepAccumulator = min(stepAccumulator + deltaTime * stepRate, 3)
        stepsThisFrame = Int(stepAccumulator)
        stepAccumulator -= Double(stepsThisFrame)

        switch mode {
        case .transition:
            pourFromIsland()
            if time > transitionDuration, !finished {
                finished = true
                isPaused = true
                DispatchQueue.main.async { [weak self] in self?.onFinish?() }
            }
        case .drawing:
            if time - lastTouchTime > calmDelay + 3.5 {
                isHidden = true
                isPaused = true
            }
        }
    }

    private let pourDuration: TimeInterval = 0.8
    private let transitionDuration: TimeInterval = 2.1

    /// The jet: a wobbling stream straight down from the island, plus side jets that fan the ink out.
    private func pourFromIsland() {
        guard time < pourDuration else { return }
        let mouth = CGPoint(x: sink.midX, y: sink.maxY + 4)
        let wobble = sin(time * 23) * 0.35
        let speed: CGFloat = 1900
        if time < 0.03 {
            haptic.impactOccurred(intensity: 0.8)
        }
        addSplat(at: mouth, velocity: CGVector(dx: speed * wobble, dy: speed),
                 radius: 14 + 10 * CGFloat(time / pourDuration), dye: 1.4)
        // Side jets alternate left and right, aimed lower over time so the ink sweeps the screen.
        let side: CGFloat = Int(time * 14) % 2 == 0 ? 1 : -1
        let angle = (0.35 + 0.55 * CGFloat(time / pourDuration)) * .pi / 2
        addSplat(at: CGPoint(x: mouth.x + side * 10, y: mouth.y + 6),
                 velocity: CGVector(dx: side * speed * sin(angle), dy: speed * cos(angle)),
                 radius: 12, dye: 0.9)
    }

    private func simulationUniforms(splatCount: Int) -> InkUniforms {
        var suction: Float = 0
        var dyeDecay: Float = 0.12
        var coverThreshold: Float = 0
        var gravity: Float = 0
        switch mode {
        case .transition:
            coverThreshold = 0.35
            let drain = max(0, min(1, (time - 0.9) / 0.4))
            suction = Float(drain) * 1300
            dyeDecay = 0.1 + Float(drain) * 2.4
            gravity = 900 * (1 - Float(drain))
        case .drawing:
            let calm = time - lastTouchTime - calmDelay
            let drain = max(0, min(1, calm / 0.6))
            suction = Float(drain) * 1100
            dyeDecay = 0.15 + Float(max(0, min(1, (calm - 1) / 1.5))) * 1.4
            gravity = 120 * (1 - Float(drain))
        }
        return InkUniforms(grid: grid, dt: Float(1 / stepRate), cell: Float(cellSize),
                           velocityDecay: 0.4, dyeDecay: dyeDecay, vorticity: 28,
                           splatCount: UInt32(splatCount), sink: sinkCell, suction: suction,
                           sinkRadius: Float(26 / cellSize), coverThreshold: coverThreshold, time: Float(time),
                           gravity: gravity)
    }

    override func encode(into commandBuffer: MTLCommandBuffer, target: MTLTexture) {
        guard let gpu, velocity.count == 2, dye.count == 2, pressure.count == 2, let divergence, let curl,
              let advectVelocity = gpu.computePipeline("ink_advect_velocity"),
              let curlPipeline = gpu.computePipeline("ink_curl"),
              let vorticityPipeline = gpu.computePipeline("ink_vorticity"),
              let divergencePipeline = gpu.computePipeline("ink_divergence"),
              let pressurePipeline = gpu.computePipeline("ink_pressure"),
              let projectPipeline = gpu.computePipeline("ink_project"),
              let advectDye = gpu.computePipeline("ink_advect_dye"),
              let renderPipeline = gpu.renderPipeline(vertex: "ink_vertex", fragment: "ink_fragment")
        else {
            super.encode(into: commandBuffer, target: target)
            return
        }
        if needsClear {
            needsClear = false
            for texture in velocity + dye + pressure + [divergence, curl] {
                let bytes = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
                texture.replace(region: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0,
                                withBytes: bytes, bytesPerRow: texture.width * (texture.pixelFormat == .rg16Float ? 4 : 2))
            }
        }

        if stepsThisFrame > 0, let encoder = commandBuffer.makeComputeCommandEncoder() {
            let threads = MTLSize(width: 16, height: 16, depth: 1)
            let groups = MTLSize(width: (Int(grid.x) + 15) / 16, height: (Int(grid.y) + 15) / 16, depth: 1)
            func run(_ pipeline: MTLComputePipelineState, _ textures: [MTLTexture], _ uniforms: inout InkUniforms,
                     splats: [InkSplat] = []) {
                encoder.setComputePipelineState(pipeline)
                for (index, texture) in textures.enumerated() {
                    encoder.setTexture(texture, index: index)
                }
                encoder.setBytes(&uniforms, length: MemoryLayout<InkUniforms>.stride, index: 0)
                let data = splats.isEmpty ? [InkSplat(position: .zero, velocity: .zero, radius: 0, dye: 0)] : splats
                encoder.setBytes(data, length: MemoryLayout<InkSplat>.stride * data.count, index: 1)
                encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threads)
            }
            for step in 0..<stepsThisFrame {
                // Splats go into the first step only; at most 64 per frame (the rest wait a frame).
                let batch = step == 0 ? Array(splats.prefix(64)) : []
                var u = simulationUniforms(splatCount: batch.count)
                run(advectVelocity, [velocity[0], velocity[1], dye[0]], &u, splats: batch)
                run(curlPipeline, [velocity[1], curl], &u)
                run(vorticityPipeline, [velocity[1], curl, velocity[0]], &u)
                run(divergencePipeline, [velocity[0], divergence], &u)
                for _ in 0..<20 {
                    run(pressurePipeline, [pressure[0], divergence, pressure[1]], &u)
                    pressure.swapAt(0, 1)
                }
                run(projectPipeline, [velocity[0], pressure[0], velocity[1]], &u)
                velocity.swapAt(0, 1)
                run(advectDye, [dye[0], velocity[0], dye[1]], &u, splats: batch)
                dye.swapAt(0, 1)
                if step == 0 {
                    splats.removeFirst(batch.count)
                }
            }
            encoder.endEncoding()
        }

        let fade: Float
        let underFade: Float
        switch mode {
        case .transition:
            underFade = 1 - Float(max(0, min(1, (time - 1.15) / 0.4)))
            fade = 1 - Float(max(0, min(1, (time - (transitionDuration - 0.45)) / 0.45)))
        case .drawing:
            underFade = 0
            fade = 1
        }
        var render = InkRenderUniforms(inkColor: inkColor.vfxSIMD(with: traitCollection),
                                       edgeColor: edgeColor.vfxSIMD(with: traitCollection),
                                       texel: SIMD2(1 / grid.x, 1 / grid.y), fade: fade, underFade: underFade,
                                       hasSnapshot: snapshot == nil ? 0 : 1)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass(target: target)) else { return }
        encoder.setRenderPipelineState(renderPipeline)
        encoder.setFragmentTexture(dye[0], index: 0)
        encoder.setFragmentTexture(snapshot ?? dye[0], index: 1)
        encoder.setFragmentBytes(&render, length: MemoryLayout<InkRenderUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}
