//
//  ChatFX.swift
//  controller
//
//  Metal pieces of the Mini-Telegram chat (shaders in MiniTelegramFX.metal):
//  - MessageEffect: the full-screen burst for 🎉 ❤️ 👍 🔥 messages. Particles start on the CPU,
//    then a compute kernel moves them every frame; they draw as the emoji, confetti or HDR sparks.
//  - LiquidWaveView: a voice message's waveform as a band of liquid with a drop on the playhead.
//

import UIKit
import Metal

/// Mirrors `EffectParticle` in MiniTelegramFX.metal.
private struct EffectParticle {
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var color: SIMD4<Float>
    var size: Float
    var rotation: Float
    var spin: Float
    var life: Float
    var maxLife: Float
    var kind: Float
    var delay: Float
    var phase: Float
}

/// Mirrors `EffectStep` in MiniTelegramFX.metal.
private struct EffectStep {
    var dt: Float
    var gravity: Float
    var drag: Float
    var sway: Float
    var time: Float
    var buoyancy: Float
    var unused: SIMD2<Float> = .zero
}

/// Mirrors `EffectRender` in MiniTelegramFX.metal.
private struct EffectRender {
    var viewport: SIMD2<Float>
    var scale: Float
    var boost: Float
}

final class MessageEffect: VFXMetalView {
    /// The emoji that have an effect.
    static let triggers: Set<String> = ["🎉", "❤️", "👍", "🔥"]

    static func effect(for text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return triggers.contains(trimmed) ? trimmed : nil
    }

    /// Plays `emoji`'s effect over `window`, starting from `origin` (window coordinates).
    static func play(_ emoji: String, in window: UIWindow, from origin: CGPoint) {
        let effect = MessageEffect(emoji: emoji, origin: origin, bounds: window.bounds)
        effect.frame = window.bounds
        window.addSubview(effect)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private let buffer: MTLBuffer?
    private let count: Int
    private let emojiTexture: MTLTexture?
    private var step: EffectStep
    private let duration: CFTimeInterval

    private init(emoji: String, origin: CGPoint, bounds: CGRect) {
        var particles: [EffectParticle] = []
        var physics = EffectStep(dt: 0, gravity: 900, drag: 0.6, sway: 0, time: 0, buoyancy: 0)
        func color(_ r: Float, _ g: Float, _ b: Float) -> SIMD4<Float> { SIMD4(r, g, b, 1) }
        let o = SIMD2(Float(origin.x), Float(origin.y))
        func random(_ range: ClosedRange<Float>) -> Float { Float.random(in: range) }
        func add(kind: Float, at position: SIMD2<Float>, angle: Float, speed: Float, size: Float, life: Float, color: SIMD4<Float>,
                 delay: Float = 0, spin: Float = 0) {
            particles.append(EffectParticle(position: position, velocity: SIMD2(cos(angle), sin(angle)) * speed, color: color,
                                              size: size, rotation: random(-0.4...0.4), spin: spin, life: life, maxLife: life,
                                              kind: kind, delay: delay, phase: random(0...6.28)))
        }
        let up = -Float.pi / 2
        switch emoji {
        case "🎉":
            // Two cannons from the bottom corners plus confetti raining from the top.
            let palette = [color(1, 0.3, 0.4), color(0.3, 0.7, 1), color(1, 0.8, 0.2), color(0.4, 0.9, 0.5), color(0.8, 0.4, 1)]
            let width = Float(bounds.width), height = Float(bounds.height)
            for side in [Float(0), 1] {
                let base = SIMD2(side * width, height)
                let aim = side == 0 ? -1.15 : -Float.pi + 1.15
                for _ in 0..<170 {
                    add(kind: 2, at: base, angle: aim + random(-0.35...0.35), speed: random(900...1700), size: random(9...15),
                        life: random(2.2...3.4), color: palette.randomElement()!, delay: random(0...0.15), spin: random(-9...9))
                }
            }
            for _ in 0..<14 {
                add(kind: 0, at: o, angle: up + random(-1.2...1.2), speed: random(500...900), size: random(34...54), life: 2.4,
                    color: .one, spin: random(-3...3))
            }
            for _ in 0..<80 {
                add(kind: 1, at: o, angle: random(0...6.28), speed: random(150...520), size: random(10...20), life: random(0.6...1.1),
                    color: color(1, 0.8, 0.3))
            }
            physics = EffectStep(dt: 0, gravity: 1100, drag: 0.9, sway: 160, time: 0, buoyancy: 0)
        case "❤️":
            // Hearts float up and sway, pink sparks around them.
            for _ in 0..<46 {
                let start = o + SIMD2(random(-60...60), random(-10...10))
                add(kind: 0, at: start, angle: up + random(-0.9...0.9), speed: random(260...620), size: random(26...62),
                    life: random(2.2...3.2), color: .one, delay: random(0...0.5), spin: random(-1.2...1.2))
            }
            for _ in 0..<140 {
                add(kind: 1, at: o, angle: random(0...6.28), speed: random(120...480), size: random(8...18), life: random(0.7...1.4),
                    color: color(1, 0.35, 0.55), delay: random(0...0.3))
            }
            physics = EffectStep(dt: 0, gravity: 160, drag: 0.7, sway: 120, time: 0, buoyancy: 420)
        case "👍":
            // A burst of thumbs that arc and fall, with a ring of sparks.
            for _ in 0..<36 {
                add(kind: 0, at: o, angle: up + random(-1.4...1.4), speed: random(600...1200), size: random(30...56), life: 2.4,
                    color: .one, spin: random(-5...5))
            }
            for index in 0..<120 {
                add(kind: 1, at: o, angle: Float(index) / 120 * 6.28, speed: random(380...460), size: 14, life: 0.8,
                    color: color(0.4, 0.75, 1))
            }
            physics = EffectStep(dt: 0, gravity: 1500, drag: 0.4, sway: 0, time: 0, buoyancy: 0)
        default:
            // 🔥: flames rise from the bubble as glowing embers, a few fire emoji ride them up.
            for _ in 0..<320 {
                let start = o + SIMD2(random(-90...90), random(-6...6))
                add(kind: 1, at: start, angle: up + random(-0.35...0.35), speed: random(160...520), size: random(10...26),
                    life: random(0.8...1.8), color: [color(1, 0.55, 0.15), color(1, 0.3, 0.08), color(1, 0.8, 0.3)].randomElement()!,
                    delay: random(0...0.9))
            }
            for _ in 0..<12 {
                add(kind: 0, at: o + SIMD2(random(-70...70), 0), angle: up + random(-0.5...0.5), speed: random(300...600),
                    size: random(30...50), life: 2, color: .one, delay: random(0...0.6), spin: random(-1...1))
            }
            physics = EffectStep(dt: 0, gravity: -260, drag: 0.8, sway: 260, time: 0, buoyancy: 0)
        }
        count = particles.count
        step = physics
        duration = Double(particles.map { $0.delay + $0.life }.max() ?? 3) + 0.2
        let device = VFXGPU.shared?.device
        buffer = device?.makeBuffer(bytes: particles, length: MemoryLayout<EffectParticle>.stride * max(count, 1),
                                    options: .storageModeShared)
        emojiTexture = Self.texture(for: emoji)
        super.init(frame: bounds)
        isUserInteractionEnabled = false
        // Extended range: the sparks' cores go brighter than white on HDR displays.
        metalLayer.pixelFormat = .rgba16Float
        metalLayer.wantsExtendedDynamicRangeContent = true
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func texture(for emoji: String) -> MTLTexture? {
        guard let gpu = VFXGPU.shared else { return nil }
        let pixels = 128
        guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: pixels * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                          | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        context.translateBy(x: 0, y: CGFloat(pixels))
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 100)]
        let size = (emoji as NSString).size(withAttributes: attributes)
        (emoji as NSString).draw(at: CGPoint(x: (CGFloat(pixels) - size.width) / 2, y: (CGFloat(pixels) - size.height) / 2),
                                 withAttributes: attributes)
        UIGraphicsPopContext()
        guard let bytes = context.data else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: gpu.pixelFormat, width: pixels, height: pixels,
                                                                  mipmapped: false)
        descriptor.usage = .shaderRead
        let texture = gpu.device.makeTexture(descriptor: descriptor)
        texture?.replace(region: MTLRegionMake2D(0, 0, pixels, pixels), mipmapLevel: 0, withBytes: bytes,
                         bytesPerRow: context.bytesPerRow)
        return texture
    }

    override func update(deltaTime: CFTimeInterval) {
        step.dt = Float(min(deltaTime, 1.0 / 30))
        step.time = Float(time)
        if time > duration {
            isPaused = true
            removeFromSuperview()
        }
    }

    override func encode(into commandBuffer: MTLCommandBuffer, target: MTLTexture) {
        guard let gpu, let buffer, let emojiTexture,
              let kernel = gpu.computePipeline("mt_effect_update"),
              let pipeline = gpu.renderPipeline(vertex: "mt_effect_vertex", fragment: "mt_effect_fragment",
                                                format: metalLayer.pixelFormat) else { return }
        if let compute = commandBuffer.makeComputeCommandEncoder() {
            var total = UInt32(count)
            compute.setComputePipelineState(kernel)
            compute.setBuffer(buffer, offset: 0, index: 0)
            compute.setBytes(&step, length: MemoryLayout<EffectStep>.stride, index: 1)
            compute.setBytes(&total, length: MemoryLayout<UInt32>.stride, index: 2)
            let width = kernel.threadExecutionWidth
            compute.dispatchThreadgroups(MTLSize(width: (count + width - 1) / width, height: 1, depth: 1),
                                         threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1))
            compute.endEncoding()
        }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass(target: target)) else { return }
        var uniforms = EffectRender(viewport: SIMD2(Float(target.width), Float(target.height)),
                                      scale: Float(contentScaleFactor), boost: 2.5)
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<EffectRender>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<EffectRender>.stride, index: 1)
        encoder.setFragmentTexture(emojiTexture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: count)
        encoder.endEncoding()
    }
}

// MARK: - Liquid waveform

/// Mirrors `WaveUniforms` in MiniTelegramFX.metal.
private struct WaveUniforms {
    var viewport: SIMD2<Float>
    var scale: Float
    var progress: Float
    var played: SIMD4<Float>
    var rest: SIMD4<Float>
    var time: Float
    var playing: Float
    var count: Float
    var unused: Float = 0
}

final class LiquidWaveView: VFXMetalView {
    var playedColor: UIColor = Palette.accent
    var restColor: UIColor = Palette.accent.withAlphaComponent(0.35)
    var onFinish: (() -> Void)?
    private(set) var isPlaying = false

    private let amplitudes: [Float]
    private var progress: Double = 0
    private var duration: Double = 1
    private var playing = Spring1D(0, stiffness: 10, dampingRatio: 1)

    init(amplitudes: [CGFloat]) {
        self.amplitudes = amplitudes.map(Float.init)
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        preferredFramesPerSecond = 60
        isPaused = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        renderFrame()
    }

    func play(duration: Double) {
        self.duration = duration
        progress = 0
        isPlaying = true
        isPaused = false
    }

    func stop() {
        isPlaying = false
    }

    override func update(deltaTime: CFTimeInterval) {
        if isPlaying {
            progress += deltaTime / duration
            if progress >= 1 {
                progress = 1
                isPlaying = false
                onFinish?()
            }
        } else if progress >= 1, playing.value < 0.05 {
            progress = 0
        }
        playing.step(toward: isPlaying ? 1 : 0, deltaTime: deltaTime)
        if !isPlaying, playing.isSettled(at: 0, tolerance: 0.002) {
            playing.value = 0
            renderFrame()
            isPaused = true
        }
    }

    override func encode(into commandBuffer: MTLCommandBuffer, target: MTLTexture) {
        guard let gpu, let pipeline = gpu.renderPipeline(vertex: "mt_fullscreen_vertex", fragment: "mt_wave_fragment"),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass(target: target)) else { return }
        var uniforms = WaveUniforms(viewport: SIMD2(Float(target.width), Float(target.height)), scale: Float(contentScaleFactor),
                                      progress: Float(progress), played: playedColor.vfxSIMD(with: traitCollection),
                                      rest: restColor.vfxSIMD(with: traitCollection), time: Float(time),
                                      playing: Float(min(max(playing.value, 0), 1)), count: Float(amplitudes.count))
        var amps = amplitudes
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<WaveUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&amps, length: MemoryLayout<Float>.stride * amps.count, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}
