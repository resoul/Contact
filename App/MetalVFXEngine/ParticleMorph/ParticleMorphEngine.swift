//
//  ParticleMorphEngine.swift
//  controller
//
//  Owns the Metal context for one particle system: an MTKView at 120 Hz, the particle buffer
//  (GPU-resident, simulated by particleComputeKernel), triple-buffered uniforms, and progress tweens.
//  Shaders: ParticleCompute.metal, ParticleRender.metal. Shared types: ParticleStructures.h.
//

import UIKit
import ParticleTypes
import MetalKit

/// Device, queue and pipelines shared by every engine instance (compiled once).
private final class ParticleGPU {
    static let shared = ParticleGPU()

    let device: MTLDevice
    let queue: MTLCommandQueue
    let simulate: MTLComputePipelineState
    let retarget: MTLComputePipelineState
    let glowPipeline: MTLRenderPipelineState
    let solidPipeline: MTLRenderPipelineState
    /// Bound when a mode has no keyframes, so every declared kernel argument has a buffer.
    let emptyBuffer: MTLBuffer
    let pixelFormat: MTLPixelFormat = .bgra8Unorm

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let simulateFunction = library.makeFunction(name: "particleComputeKernel"),
              let retargetFunction = library.makeFunction(name: "particleRetargetKernel"),
              let emptyBuffer = device.makeBuffer(length: 64, options: .storageModeShared) else { return nil }
        do {
            simulate = try device.makeComputePipelineState(function: simulateFunction)
            retarget = try device.makeComputePipelineState(function: retargetFunction)
            glowPipeline = try Self.renderPipeline(device: device, library: library,
                                                   fragment: "particleGlowFragment", additive: true)
            solidPipeline = try Self.renderPipeline(device: device, library: library,
                                                    fragment: "particleSolidFragment", additive: false)
        } catch {
            assertionFailure("ParticleMorphEngine pipelines failed: \(error)")
            return nil
        }
        self.device = device
        self.queue = queue
        self.emptyBuffer = emptyBuffer
    }

    private static func renderPipeline(device: MTLDevice, library: MTLLibrary,
                                       fragment: String, additive: Bool) throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = fragment
        descriptor.vertexFunction = library.makeFunction(name: "particleVertex")
        descriptor.fragmentFunction = library.makeFunction(name: fragment)
        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = .bgra8Unorm
        attachment.isBlendingEnabled = true
        attachment.sourceRGBBlendFactor = .one
        attachment.sourceAlphaBlendFactor = .one
        // Additive: light accumulates (glow). Otherwise: premultiplied "over".
        attachment.destinationRGBBlendFactor = additive ? .one : .oneMinusSourceAlpha
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }
}

final class ParticleMorphEngine: NSObject, MTKViewDelegate {
    enum Style {
        /// Additive neon glow. Looks best over dark backgrounds.
        case glow
        /// Solid squares with normal blending: dust that keeps the source colors.
        case solid
    }

    enum AnimatedValue {
        case progress
        case stage
    }

    enum Timing {
        case linear
        case easeIn
        case easeOut
        case easeInOut

        func apply(_ t: Double) -> Double {
            switch self {
            case .linear: return t
            case .easeIn: return t * t * t
            case .easeOut: return 1 - pow(1 - t, 3)
            case .easeInOut: return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
            }
        }
    }

    /// Number of frames the CPU may run ahead of the GPU.
    static let maxFramesInFlight = 3

    /// Average glow coverage of one sprite, in units of its diameter² (∫ of the glow falloff).
    private static let glowFootprint: Float = 0.11

    let view: MTKView

    var mode: ParticleMode
    var style: Style = .glow
    var progress: Float = 0
    var stage: Float = 0
    var noiseStrength: Float = 0
    var touchPosition: CGPoint?
    var touchRadius: Float = 90
    var touchPower: Float = 9000
    var audioVolume: Float = 0
    var arcHeight: Float = 0
    /// The scenario's shape in view coordinates: the button, the card, the sphere's box…
    var effectBounds: CGRect = .zero
    var colorA: UIColor = .white
    var colorB: UIColor = .white
    var pointScale: Float = 1
    var intensity: Float = 1
    /// Chart mode: how released particles leave, and the seconds the `stage` timeline of a release spans.
    var releaseStyle = ParticleReleaseDust
    var releaseDuration: Float = 1.6
    /// Chart mode: the ground for the gravity release, in view points.
    var floorY: Float = 0
    /// Chart mode: 0…1, attached particles tremble.
    var charge: Float = 0
    /// Called once per frame before the GPU work is encoded; drive per-frame inputs from here.
    var onFrame: ((ParticleMorphEngine, CFTimeInterval) -> Void)?

    var isPaused: Bool {
        get { view.isPaused }
        set {
            view.isPaused = newValue
            lastTimestamp = nil
        }
    }

    private(set) var particleCount = 0
    private(set) var time: CFTimeInterval = 0
    private var resumeAfterBackground = false
    /// Smoothed frames per second actually delivered.
    private(set) var framesPerSecond: Double = 0

    private let gpu: ParticleGPU
    private var particleBuffer: MTLBuffer?
    private var keyframeBuffer: MTLBuffer?
    private let uniformBuffers: [MTLBuffer]
    private var uniformIndex = 0
    private let inFlight = DispatchSemaphore(value: ParticleMorphEngine.maxFramesInFlight)
    private var pendingRetargets: [(params: ParticleRetarget, targets: MTLBuffer, colors: MTLBuffer)] = []
    private var tweens: [AnimatedValue: Tween] = [:]
    private var lastTimestamp: CFTimeInterval?

    private struct Tween {
        var from: Float
        var to: Float
        var duration: Double
        var elapsed: Double = 0
        var timing: Timing
        var completion: (() -> Void)?
    }

    init?(mode: ParticleMode, frame: CGRect = .zero) {
        guard let gpu = ParticleGPU.shared else { return nil }
        var buffers: [MTLBuffer] = []
        for _ in 0..<Self.maxFramesInFlight {
            guard let buffer = gpu.device.makeBuffer(length: MemoryLayout<ParticleUniforms>.stride,
                                                     options: .storageModeShared) else { return nil }
            buffers.append(buffer)
        }
        self.gpu = gpu
        self.mode = mode
        uniformBuffers = buffers
        view = MTKView(frame: frame, device: gpu.device)
        super.init()

        view.colorPixelFormat = gpu.pixelFormat
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.layer.isOpaque = false
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 120   // ProMotion; needs CADisableMinimumFrameDurationOnPhone
        view.isUserInteractionEnabled = false
        view.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(appWillResign),
                                               name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    @objc private func appWillResign() {
        resumeAfterBackground = !isPaused
        isPaused = true
    }

    @objc private func appDidBecomeActive() {
        if resumeAfterBackground, view.window != nil { isPaused = false }
        resumeAfterBackground = false
    }

    // MARK: - Data

    /// Replaces every particle. The new buffer is a fresh allocation, so frames already in flight
    /// keep reading the old one and nothing has to wait.
    func load(_ particles: [Particle]) {
        particleCount = particles.count
        guard !particles.isEmpty else {
            particleBuffer = nil
            return
        }
        particleBuffer = particles.withUnsafeBytes { bytes in
            gpu.device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: .storageModeShared)
        }
        particleBuffer?.label = "Particles"
    }

    /// Changes targets and/or colors on the GPU at the start of the next frame, keeping each
    /// particle's current position and velocity. `commitCurrentAsStart` freezes where every particle
    /// is right now as its new `startPosition` (for analytic modes that interpolate start → target).
    /// `colorsAreTargets`: write `colors` to `targetColor` (the chart mode fades towards it) instead of `color`.
    func retarget(targets: [SIMD2<Float>]? = nil, colors: [SIMD4<Float>]? = nil, colorsAreTargets: Bool = false,
                  commitCurrentAsStart: Bool = false, stopVelocity: Bool = false) {
        guard particleCount > 0 else { return }
        var flags: UInt32 = 0
        if commitCurrentAsStart { flags |= ParticleRetargetCommitStart.rawValue }
        if stopVelocity { flags |= ParticleRetargetStopVelocity.rawValue }
        var targetBuffer = gpu.emptyBuffer
        var colorBuffer = gpu.emptyBuffer
        if let targets {
            precondition(targets.count == particleCount, "retarget needs one target per particle")
            flags |= ParticleRetargetTargets.rawValue
            targetBuffer = makeBuffer(targets) ?? gpu.emptyBuffer
        }
        if let colors {
            precondition(colors.count == particleCount, "retarget needs one color per particle")
            flags |= colorsAreTargets ? ParticleRetargetTargetColors.rawValue : ParticleRetargetColors.rawValue
            colorBuffer = makeBuffer(colors) ?? gpu.emptyBuffer
        }
        pendingRetargets.append((ParticleRetarget(count: UInt32(particleCount), flags: flags), targetBuffer, colorBuffer))
    }

    /// Point sets the loader morphs through, each with exactly `particleCount` points:
    /// Buffer_0, Buffer_50, Buffer_100 and the final card.
    func setKeyframes(_ frames: [[SIMD2<Float>]]) {
        precondition(frames.allSatisfy { $0.count == particleCount }, "every keyframe needs one point per particle")
        keyframeBuffer = makeBuffer(frames.flatMap { $0 })
    }

    private func makeBuffer<T>(_ values: [T]) -> MTLBuffer? {
        values.withUnsafeBytes { bytes in
            gpu.device.makeBuffer(bytes: bytes.baseAddress!, length: max(bytes.count, 16), options: .storageModeShared)
        }
    }

    /// Brightness that makes `count` glowing sprites of `pointSize` over `area` pt² read as a solid
    /// fill (≈ 1 coverage). Denser shapes then bloom towards white, sparser ones become sparks.
    static func balancedIntensity(count: Int, area: CGFloat, pointSize: CGFloat) -> Float {
        let density = Float(count) / Float(max(area, 1))
        return 1 / max(density * Float(pointSize * pointSize) * glowFootprint, 1e-3)
    }

    // MARK: - Animation

    func animate(_ value: AnimatedValue, to target: Float, duration: TimeInterval,
                 timing: Timing = .easeInOut, completion: (() -> Void)? = nil) {
        let from = value == .progress ? progress : stage
        tweens[value] = Tween(from: from, to: target, duration: max(duration, 1e-3), timing: timing, completion: completion)
        isPaused = false
    }

    func cancelAnimations() {
        tweens.removeAll()
    }

    private func stepTweens(_ deltaTime: CFTimeInterval) {
        var finished: [() -> Void] = []
        for (key, var tween) in tweens {
            tween.elapsed += deltaTime
            let t = min(tween.elapsed / tween.duration, 1)
            let value = tween.from + (tween.to - tween.from) * Float(tween.timing.apply(t))
            if key == .progress { progress = value } else { stage = value }
            if t >= 1 {
                tweens[key] = nil
                if let completion = tween.completion { finished.append(completion) }
            } else {
                tweens[key] = tween
            }
        }
        finished.forEach { $0() }
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        // Clamp long frames (first frame, app resume) so physics never takes a huge step.
        let deltaTime = lastTimestamp.map { min(max(now - $0, 1.0 / 240), 1.0 / 30) } ?? 1.0 / 120
        if let lastTimestamp {
            let instant = 1 / max(now - lastTimestamp, 1e-4)
            framesPerSecond = framesPerSecond == 0 ? instant : framesPerSecond * 0.95 + instant * 0.05
        }
        lastTimestamp = now
        time += deltaTime
        stepTweens(deltaTime)
        onFrame?(self, deltaTime)

        // Triple buffering: wait until one of the three uniform buffers is free again.
        inFlight.wait()
        let uniformBuffer = uniformBuffers[uniformIndex]
        uniformIndex = (uniformIndex + 1) % Self.maxFramesInFlight
        uniformBuffer.contents().assumingMemoryBound(to: ParticleUniforms.self).pointee = makeUniforms(deltaTime: deltaTime)

        guard let commandBuffer = gpu.queue.makeCommandBuffer() else {
            inFlight.signal()
            return
        }
        let semaphore = inFlight
        commandBuffer.addCompletedHandler { @Sendable _ in semaphore.signal() }

        if let particles = particleBuffer, particleCount > 0 {
            encodeCompute(into: commandBuffer, particles: particles, uniforms: uniformBuffer)
        }
        if let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
           let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) {
            if let particles = particleBuffer, particleCount > 0 {
                encoder.setRenderPipelineState(style == .glow ? gpu.glowPipeline : gpu.solidPipeline)
                encoder.setVertexBuffer(particles, offset: 0, index: Int(ParticleBufferIndexParticles.rawValue))
                encoder.setVertexBuffer(uniformBuffer, offset: 0, index: Int(ParticleBufferIndexUniforms.rawValue))
                encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: Int(ParticleBufferIndexUniforms.rawValue))
                encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: particleCount)
            }
            encoder.endEncoding()
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
    }

    private func encodeCompute(into commandBuffer: MTLCommandBuffer, particles: MTLBuffer, uniforms: MTLBuffer) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        let width = gpu.simulate.threadExecutionWidth
        let groups = MTLSize(width: (particleCount + width - 1) / width, height: 1, depth: 1)
        let threads = MTLSize(width: width, height: 1, depth: 1)

        // Retargets go first, in the same encoder; Metal orders dispatches that touch the same buffer.
        for var pending in pendingRetargets {
            encoder.setComputePipelineState(gpu.retarget)
            encoder.setBuffer(particles, offset: 0, index: 0)
            encoder.setBuffer(pending.targets, offset: 0, index: 1)
            encoder.setBuffer(pending.colors, offset: 0, index: 2)
            encoder.setBytes(&pending.params, length: MemoryLayout<ParticleRetarget>.stride, index: 3)
            encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threads)
        }
        pendingRetargets.removeAll()

        encoder.setComputePipelineState(gpu.simulate)
        encoder.setBuffer(particles, offset: 0, index: Int(ParticleBufferIndexParticles.rawValue))
        encoder.setBuffer(uniforms, offset: 0, index: Int(ParticleBufferIndexUniforms.rawValue))
        encoder.setBuffer(keyframeBuffer ?? gpu.emptyBuffer, offset: 0, index: Int(ParticleBufferIndexKeyframes.rawValue))
        encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threads)
        encoder.endEncoding()
    }

    private func makeUniforms(deltaTime: CFTimeInterval) -> ParticleUniforms {
        let size = view.bounds.size
        var u = ParticleUniforms()
        u.progress = progress
        u.time = Float(time.truncatingRemainder(dividingBy: 4096))
        u.touchPos = SIMD2(Float(touchPosition?.x ?? -10_000), Float(touchPosition?.y ?? -10_000))
        u.touchRadius = touchRadius
        u.noiseStrength = noiseStrength
        u.deltaTime = Float(deltaTime)
        u.mode = mode.rawValue
        u.viewSize = SIMD2(Float(max(size.width, 1)), Float(max(size.height, 1)))
        u.bounds = SIMD4(Float(effectBounds.minX), Float(effectBounds.minY),
                         Float(effectBounds.width), Float(effectBounds.height))
        u.colorA = colorA.particleSIMD
        u.colorB = colorB.particleSIMD
        u.scale = Float(size.width > 0 ? view.drawableSize.width / size.width : view.contentScaleFactor)
        u.touchActive = touchPosition == nil ? 0 : 1
        u.touchPower = touchPower
        u.audioVolume = audioVolume
        u.arcHeight = arcHeight
        u.stage = stage
        u.pointScale = pointScale
        u.intensity = intensity
        u.particleCount = UInt32(particleCount)
        u.releaseStyle = releaseStyle.rawValue
        u.releaseDuration = releaseDuration
        u.floorY = floorY
        u.charge = charge
        return u
    }
}

extension UIColor {
    /// Straight (not premultiplied) sRGB components.
    var particleSIMD: SIMD4<Float> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD4(Float(r), Float(g), Float(b), Float(a))
    }
}
