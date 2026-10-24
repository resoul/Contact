//
//  IslandConfetti.swift
//  controller
//
//  The Dynamic Island spits out a celebration: its mouth bulges, then confetti and sparks burst out
//  of it (GPU particles, Shaders/IslandConfetti.metal). The layer is extended dynamic range, so on
//  an HDR display the sparks glow brighter than the white UI around them.
//

import UIKit
import Metal

/// Mirrors `ConfettiParticle` in IslandConfetti.metal.
private struct ConfettiParticle {
    var motion: SIMD4<Float>
    var color: SIMD4<Float>
    var spin: SIMD4<Float>
    var shape: SIMD4<Float>
}

/// Mirrors `ConfettiStep` in IslandConfetti.metal.
private struct ConfettiStep {
    var origin: SIMD2<Float>
    var dt: Float
    var time: Float
    var count: UInt32
    var gravity: Float
    var seed: Float
    var sparkShare: Float
    var sparkColor: SIMD4<Float>
    var direction: Float
    var spread: Float
    var speedScale: Float
    var unused: Float = 0
}

/// Mirrors `ConfettiRender` in IslandConfetti.metal.
private struct ConfettiRender {
    var viewport: SIMD2<Float>
    var scale: Float
    var sparkBoost: Float
}

final class IslandConfetti: IslandFluidView {
    /// Bursts a celebration out of the island in `window`. The overlay removes itself afterwards.
    @discardableResult
    static func burst(in window: UIWindow, particles: Int = 700) -> IslandConfetti {
        let confetti = IslandConfetti(count: particles)
        confetti.install(in: window)
        confetti.isPaused = false
        return confetti
    }

    /// Bursts from any point of the window instead (window coordinates), without the island's spit:
    /// a fan around `direction` (radians, y down; -π/2 is up) `spread` radians wide.
    @discardableResult
    static func burst(in window: UIWindow, from origin: CGPoint, direction: CGFloat = -.pi / 2, spread: CGFloat = 2.2,
                      particles: Int = 500, sparkShare: CGFloat = 0.32, sparkColor: UIColor? = nil,
                      speedScale: CGFloat = 0.8) -> IslandConfetti {
        let confetti = IslandConfetti(count: particles)
        confetti.origin = origin
        confetti.direction = Float(direction)
        confetti.spread = Float(spread)
        confetti.sparkShare = Float(sparkShare)
        confetti.speedScale = Float(speedScale)
        if let sparkColor {
            confetti.sparkColor = sparkColor.vfxSIMD()
        }
        confetti.install(in: window)
        confetti.isPaused = false
        return confetti
    }

    /// How far past SDR white the sparks go (1 = white). Only visible on HDR displays.
    var sparkBoost: Float = 3.5

    private let count: Int
    /// nil: out of the island, with its spit.
    private var origin: CGPoint?
    private var direction: Float = .pi / 2
    private var spread: Float = 2.6
    private var sparkShare: Float = 0.32
    private var sparkColor = SIMD4<Float>(1.0, 0.72, 0.18, 1)
    private var speedScale: Float = 1
    private let particles: MTLBuffer?
    private var spawned = false
    private var stepDelta: Float = 0
    private let duration: CFTimeInterval = 3.6
    private let burstDelay: CFTimeInterval = 0.12
    private let spitHaptic = UIImpactFeedbackGenerator(style: .rigid)
    private let success = UINotificationFeedbackGenerator()

    private init(count: Int) {
        self.count = count
        particles = VFXGPU.shared?.device.makeBuffer(length: MemoryLayout<ConfettiParticle>.stride * count,
                                                     options: .storageModePrivate)
        super.init(frame: .zero)
        gloss = 0.35
        // Extended range: values above 1.0 are brighter than white on EDR displays.
        metalLayer.pixelFormat = .rgba16Float
        metalLayer.wantsExtendedDynamicRangeContent = true
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        spitHaptic.prepare()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func update(deltaTime: CFTimeInterval) {
        stepDelta = Float(deltaTime)
        let mouth = islandMouth
        if origin != nil {
            if !spawned {
                spitHaptic.impactOccurred(intensity: 0.8)
            }
            shapes = []
        } else if time < burstDelay {
            // The mouth bulges as it winds up.
            let windUp = CGFloat(time / burstDelay)
            shapes = [.circle(center: CGPoint(x: mouth.x, y: mouth.y - 4 + windUp * 8), radius: 7 + windUp * 5, blend: 12)]
        } else {
            if !spawned, time >= burstDelay {
                spitHaptic.impactOccurred()
                success.notificationOccurred(.success)
            }
            shapes = time - burstDelay < 1 ? [recoilBump(time - burstDelay, amplitude: 14)] : []
        }
        if time > duration {
            isPaused = true
            removeFromSuperview()
        }
    }

    override func encode(into commandBuffer: MTLCommandBuffer, target: MTLTexture) {
        super.encode(into: commandBuffer, target: target)
        guard time >= burstDelay || origin != nil, let gpu, let particles,
              let spawn = gpu.computePipeline("confetti_spawn"),
              let step = gpu.computePipeline("confetti_update"),
              let render = gpu.renderPipeline(vertex: "confetti_vertex", fragment: "confetti_fragment",
                                              format: metalLayer.pixelFormat)
        else { return }

        if let compute = commandBuffer.makeComputeCommandEncoder() {
            let pipeline = spawned ? step : spawn
            let from = origin ?? CGPoint(x: islandMouth.x, y: islandMouth.y + 2)
            var params = ConfettiStep(origin: SIMD2(Float(from.x), Float(from.y)),
                                      dt: stepDelta, time: Float(time), count: UInt32(count),
                                      gravity: 1000, seed: Float.random(in: 0...1), sparkShare: sparkShare,
                                      sparkColor: sparkColor, direction: direction, spread: spread,
                                      speedScale: speedScale)
            compute.setComputePipelineState(pipeline)
            compute.setBuffer(particles, offset: 0, index: 0)
            compute.setBytes(&params, length: MemoryLayout<ConfettiStep>.stride, index: 1)
            let width = pipeline.threadExecutionWidth
            compute.dispatchThreadgroups(MTLSize(width: (count + width - 1) / width, height: 1, depth: 1),
                                         threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1))
            compute.endEncoding()
            spawned = true
        }

        let pass = renderPass(target: target)
        pass.colorAttachments[0].loadAction = .load
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        var uniforms = ConfettiRender(viewport: SIMD2(Float(target.width), Float(target.height)),
                                      scale: Float(contentScaleFactor), sparkBoost: sparkBoost)
        encoder.setRenderPipelineState(render)
        encoder.setVertexBuffer(particles, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<ConfettiRender>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ConfettiRender>.stride, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: count)
        encoder.endEncoding()
    }
}
