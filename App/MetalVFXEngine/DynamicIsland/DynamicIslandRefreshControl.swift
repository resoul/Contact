//
//  DynamicIslandRefreshControl.swift
//  controller
//
//  Pull-to-refresh where a liquid drop stretches out of the Dynamic Island, tears off,
//  falls and splashes. Shaders: Shaders/DynamicIslandLiquid.metal.
//

import UIKit
import Metal

/// Where the Dynamic Island is. There is no public API, so the frame is inferred from the safe area
/// using measured sizes: 14 Pro / 15 / 16 (top inset 59 pt) and 16 Pro / 17 (top inset 62 pt).
enum DynamicIslandGeometry {
    static func hasDynamicIsland(in window: UIWindow) -> Bool {
        UIDevice.current.userInterfaceIdiom == .phone
            && window.safeAreaInsets.top >= 59
            && window.bounds.height > window.bounds.width
    }

    /// Island frame in window coordinates. Without an island (older phones, landscape) it returns
    /// where the island would be, so effects still have an anchor at the top center.
    static func frame(in window: UIWindow) -> CGRect {
        let size: CGSize
        let top: CGFloat
        if window.safeAreaInsets.top >= 62 {
            size = CGSize(width: 125.33, height: 36.67)
            top = 14
        } else {
            size = CGSize(width: 126, height: 37.33)
            top = 11.33
        }
        return CGRect(x: window.bounds.midX - size.width / 2, y: top, width: size.width, height: size.height)
    }
}

/// Mirrors `LiquidUniforms` in DynamicIslandLiquid.metal.
private struct LiquidUniforms {
    var viewport: SIMD2<Float>
    var scale: Float
    var time: Float
    var island: SIMD4<Float>
    var drop: SIMD4<Float>
    var bump: SIMD4<Float>
    var color: SIMD4<Float>
}

/// Mirrors `DropUniforms` in DynamicIslandLiquid.metal.
private struct DropUniforms {
    var viewport: SIMD2<Float>
    var scale: Float
    var squash: Float
    var drop: SIMD4<Float>
    var color: SIMD4<Float>
}

/// Mirrors `SplashParticle`, `SplashSpawn`, `SplashStep` and `SplashUniforms` in DynamicIslandLiquid.metal.
private struct SplashParticle {
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var life: Float
    var maxLife: Float
    var radius: Float
    var seed: Float
}

private struct SplashSpawn {
    var origin: SIMD2<Float>
    var seed: Float
    var count: UInt32
}

private struct SplashStep {
    var dt: Float
    var gravity: Float
    var floorY: Float
    var drag: Float
    var count: UInt32
}

private struct SplashUniforms {
    var viewport: SIMD2<Float>
    var scale: Float
    var unused: Float = 0
    var color: SIMD4<Float>
}

/// Attach to a scroll view with `attach(to:)`. The control installs itself as a transparent,
/// touch-through overlay at the top of the scroll view's window, over the Dynamic Island.
final class DynamicIslandRefreshControl: VFXMetalView {
    /// Pull distance (points past the resting position) that tears the drop off and starts a refresh.
    var triggerDistance: CGFloat = 110
    /// Height of the render block below the island; the drop splashes on its bottom edge.
    var renderDepth: CGFloat = 210
    /// Black matches the island, so the liquid looks like it comes out of it.
    var liquidColor: UIColor = .black
    /// Extra top inset kept while refreshing, so the content rests below the island.
    var refreshingInset: CGFloat = 56

    var onRefresh: (() -> Void)?
    private(set) var isRefreshing = false
    /// 0…1, how far the current pull is toward `triggerDistance`.
    private(set) var pullProgress: CGFloat = 0

    private enum Phase {
        case idle
        case breaking(CFTimeInterval)
        case falling
        case splashing(CFTimeInterval)
    }

    private let particleCount = 256
    private let maxStretch: CGFloat = 46
    private let breakDuration: CFTimeInterval = 0.14
    private let gravity: CGFloat = 2600          // points / s²
    private let splashDuration: CFTimeInterval = 1.1

    private weak var scrollView: UIScrollView?
    private var offsetObservation: NSKeyValueObservation?
    private var island: CGRect = .zero
    private var phase = Phase.idle
    private var armed = true
    private var appliedInset: CGFloat = 0

    private var dropCenter = CGPoint.zero
    private var dropRadius: CGFloat = 14
    private var dropVelocity: CGFloat = 0
    private var recoilTime: CFTimeInterval?
    private var pendingSplash: CGPoint?
    private var stepDelta: Float = 0

    private let particles: MTLBuffer?
    private let rigidHaptic = UIImpactFeedbackGenerator(style: .rigid)
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)

    init() {
        particles = VFXGPU.shared?.device.makeBuffer(length: MemoryLayout<SplashParticle>.stride * particleCount,
                                                     options: .storageModePrivate)
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isPaused = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Public API

    func attach(to scrollView: UIScrollView) {
        detach()
        self.scrollView = scrollView
        offsetObservation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.scrollViewDidScroll() }
        }
        updateGeometry()
    }

    func detach() {
        offsetObservation = nil
        scrollView = nil
        removeFromSuperview()
    }

    func endRefreshing() {
        guard isRefreshing else { return }
        isRefreshing = false
        wake()
        guard let scrollView, appliedInset > 0 else { return }
        let inset = appliedInset
        appliedInset = 0
        UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            scrollView.contentInset.top -= inset
            let restingY = -scrollView.adjustedContentInset.top
            if scrollView.contentOffset.y < restingY {
                scrollView.contentOffset.y = restingY
            }
        }
    }

    // MARK: Scroll tracking

    private func scrollViewDidScroll() {
        guard let scrollView else { return }
        updateGeometry()
        // Measured from the resting position, so it works with nav bars and safe-area insets.
        let pull = -(scrollView.contentOffset.y + scrollView.adjustedContentInset.top)
        pullProgress = max(0, min(1, pull / triggerDistance))

        if case .idle = phase {
            if pullProgress == 0, !isRefreshing {
                armed = true
            }
            if pullProgress > 0, armed {
                rigidHaptic.prepare()
            }
            if pullProgress >= 1, armed, scrollView.isTracking, !isRefreshing {
                beginTear()
            }
        }
        if pullProgress > 0 {
            wake()
        }
    }

    private func updateGeometry() {
        guard let window = scrollView?.window else { return }
        if superview !== window {
            window.addSubview(self)
        }
        // Slightly smaller than the real island, so any misalignment stays hidden under it.
        island = DynamicIslandGeometry.frame(in: window).insetBy(dx: 1.5, dy: 1.5)
        let newFrame = CGRect(x: 0, y: 0, width: window.bounds.width, height: island.maxY + renderDepth)
        if frame != newFrame {
            frame = newFrame
        }
    }

    private func wake() {
        if superview != nil {
            isPaused = false
        }
    }

    private func beginTear() {
        armed = false
        phase = .breaking(0)
        isRefreshing = true
        if let scrollView, refreshingInset > 0 {
            appliedInset = refreshingInset
            scrollView.contentInset.top += refreshingInset
        }
        onRefresh?()
    }

    // MARK: Simulation

    /// Attached drop for a given stretch: center, radius and the smin blend radius `k`.
    /// Between the island and the drop the merged field is ≈ gap/2 − k/4, so the liquid neck is
    /// about k/2 − gap wide: thick early in the pull, ~5 pt at full stretch, gone once k < 2·gap.
    private func attachedDrop(progress p: CGFloat, breaking b: CGFloat = 0) -> (center: CGPoint, radius: CGFloat, k: CGFloat) {
        let radius = 5 + 10 * p
        let gap = max(p * maxStretch - radius, 0)   // island bottom → drop top, before tearing
        // While tearing, k stays at its full-stretch value and the drop keeps moving away,
        // so the neck thins over a few frames and snaps.
        let k = 2 * gap + 10 + 14 * (1 - p)
        let centerY = island.maxY + p * maxStretch + b * 14
        return (CGPoint(x: island.midX, y: centerY), radius, k)
    }

    private var squash: CGFloat {
        min(dropVelocity / 2400, 0.32)
    }

    private var needsAnimation: Bool {
        if case .idle = phase {
            return (armed && pullProgress > 0) || recoilTime != nil || isRefreshing
        }
        return true
    }

    override func update(deltaTime: CFTimeInterval) {
        stepDelta = Float(deltaTime)
        switch phase {
        case .idle:
            if !isRefreshing, pullProgress == 0 {
                armed = true
            }
        case .breaking(let elapsed):
            let t = elapsed + deltaTime
            let b = CGFloat(min(t / breakDuration, 1))
            let drop = attachedDrop(progress: 1, breaking: b)
            let gap = drop.center.y - drop.radius - island.maxY
            if drop.k <= 2 * gap || b >= 1 {
                tear(at: drop.center, radius: drop.radius)   // the frame the liquid bridge breaks
            } else {
                phase = .breaking(t)
            }
        case .falling:
            dropVelocity += gravity * CGFloat(deltaTime)
            dropCenter.y += dropVelocity * CGFloat(deltaTime)
            if dropCenter.y + dropRadius * (1 - squash) >= bounds.height - 2 {
                splash()
            }
        case .splashing(let elapsed):
            let t = elapsed + deltaTime
            phase = t >= splashDuration ? .idle : .splashing(t)
        }
        if let recoil = recoilTime {
            recoilTime = recoil > 1.2 ? nil : recoil + deltaTime
        }
    }

    private func tear(at center: CGPoint, radius: CGFloat) {
        rigidHaptic.impactOccurred()
        lightHaptic.prepare()
        dropCenter = center
        dropRadius = radius
        dropVelocity = 220
        recoilTime = 0
        phase = .falling
    }

    private func splash() {
        lightHaptic.impactOccurred()
        pendingSplash = CGPoint(x: dropCenter.x, y: bounds.height - 2)
        phase = .splashing(0)
    }

    // MARK: Rendering

    override func encode(into commandBuffer: MTLCommandBuffer, target: MTLTexture) {
        guard let gpu, needsAnimation else {
            super.encode(into: commandBuffer, target: target)   // one clear frame, then sleep
            if !needsAnimation {
                isPaused = true
            }
            return
        }
        let viewport = SIMD2(Float(target.width), Float(target.height))
        let scale = Float(contentScaleFactor)
        let color = liquidColor.vfxSIMD(with: traitCollection)

        var splashing = false
        if case .splashing = phase {
            splashing = true
            encodeParticleSimulation(commandBuffer, gpu: gpu)
        }

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass(target: target)) else { return }

        // Island, attached drop and the recoiling/breathing bump: one SDF pass.
        if let pipeline = gpu.renderPipeline(vertex: "island_liquid_vertex", fragment: "island_liquid_fragment") {
            var drop = SIMD4<Float>.zero
            if case .breaking(let elapsed) = phase {
                let d = attachedDrop(progress: 1, breaking: CGFloat(min(elapsed / breakDuration, 1)))
                drop = SIMD4(Float(d.center.x), Float(d.center.y), Float(d.radius), Float(d.k))
            } else if case .idle = phase, armed, pullProgress > 0 {
                let d = attachedDrop(progress: pullProgress)
                drop = SIMD4(Float(d.center.x), Float(d.center.y), Float(d.radius), Float(d.k))
            }
            var uniforms = LiquidUniforms(
                viewport: viewport, scale: scale, time: Float(time),
                island: SIMD4(Float(island.minX), Float(island.minY), Float(island.width), Float(island.height)),
                drop: drop, bump: bumpShape(), color: color)
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<LiquidUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }

        if case .falling = phase,
           let pipeline = gpu.renderPipeline(vertex: "falling_drop_vertex", fragment: "falling_drop_fragment") {
            var uniforms = DropUniforms(viewport: viewport, scale: scale, squash: Float(squash),
                                        drop: SIMD4(Float(dropCenter.x), Float(dropCenter.y), Float(dropRadius), 0),
                                        color: color)
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<DropUniforms>.stride, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<DropUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        if splashing, let particles,
           let pipeline = gpu.renderPipeline(vertex: "splash_particle_vertex", fragment: "splash_particle_fragment") {
            var uniforms = SplashUniforms(viewport: viewport, scale: scale, color: color)
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBuffer(particles, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<SplashUniforms>.stride, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SplashUniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: particleCount)
        }
        encoder.endEncoding()
    }

    /// The torn neck springs back into the island; while refreshing, the island "breathes".
    private func bumpShape() -> SIMD4<Float> {
        if let t = recoilTime {
            let extent = 14 * exp(-7 * t) * cos(18 * t)
            return SIMD4(Float(island.midX), Float(island.maxY - 7 + max(extent, -4)), 7, 10)
        }
        if isRefreshing {
            let breath = 0.5 + 0.5 * sin(time * 5)
            return SIMD4(Float(island.midX), Float(island.maxY - 5 + 6 * breath), 6, 10)
        }
        return .zero
    }

    private func encodeParticleSimulation(_ commandBuffer: MTLCommandBuffer, gpu: VFXGPU) {
        guard let particles, let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        let count = UInt32(particleCount)

        func dispatch(_ pipeline: MTLComputePipelineState) {
            let width = pipeline.threadExecutionWidth
            encoder.dispatchThreadgroups(MTLSize(width: (particleCount + width - 1) / width, height: 1, depth: 1),
                                         threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1))
        }

        if let origin = pendingSplash, let spawn = gpu.computePipeline("splash_spawn") {
            var params = SplashSpawn(origin: SIMD2(Float(origin.x), Float(origin.y)),
                                     seed: Float.random(in: 0...1), count: count)
            encoder.setComputePipelineState(spawn)
            encoder.setBuffer(particles, offset: 0, index: 0)
            encoder.setBytes(&params, length: MemoryLayout<SplashSpawn>.stride, index: 1)
            dispatch(spawn)
            pendingSplash = nil
        } else if let step = gpu.computePipeline("splash_update") {
            var params = SplashStep(dt: stepDelta, gravity: Float(gravity * 0.75), floorY: Float(bounds.height - 1),
                                    drag: 1.2, count: count)
            encoder.setComputePipelineState(step)
            encoder.setBuffer(particles, offset: 0, index: 0)
            encoder.setBytes(&params, length: MemoryLayout<SplashStep>.stride, index: 1)
            dispatch(step)
        }
        encoder.endEncoding()
    }
}
