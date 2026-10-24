//
//  FluidMeshGradientView.swift
//  controller
//
//  Liquid mesh gradient: soft color blobs drift, warp and flow toward the low side when the
//  phone tilts (CoreMotion gravity → spring → Metal uniforms). Shader: Shaders/VFXEffects.metal.
//

import UIKit
import Metal
import CoreMotion

/// Mirrors `FluidUniforms` in VFXEffects.metal.
private struct FluidUniforms {
    var viewport: SIMD2<Float>
    var time: Float
    var speed: Float
    var tilt: SIMD2<Float>
    var flow: SIMD2<Float>
    var colorCount: UInt32
    var blobSize: Float
    var warp: Float
    var grain: Float
}

final class FluidMeshGradientView: VFXMetalView {
    /// Up to 8 colors, blended in linear light.
    var colors: [UIColor] = [
        UIColor(red: 0.98, green: 0.36, blue: 0.55, alpha: 1),
        UIColor(red: 0.45, green: 0.32, blue: 0.98, alpha: 1),
        UIColor(red: 0.15, green: 0.78, blue: 0.95, alpha: 1),
        UIColor(red: 1.00, green: 0.72, blue: 0.30, alpha: 1),
        UIColor(red: 0.20, green: 0.90, blue: 0.62, alpha: 1),
    ]
    /// Speed of the idle drift.
    var speed: CGFloat = 1
    /// Softness of each blob, in screen heights.
    var blobSize: CGFloat = 0.24
    /// Strength of the liquid distortion.
    var warp: CGFloat = 0.4
    /// How far tilting the phone drags the colors.
    var motionStrength: CGFloat = 1.2
    /// Tilt (−1…1 per axis) used when there is no motion hardware, e.g. in the simulator.
    /// Without motion, a pan gesture drives this automatically.
    var manualTilt: CGPoint?

    private let motion = CMMotionManager()
    private var restGravity: SIMD2<Double>?
    private var tilt = SIMD2<Float>.zero
    private var tiltVelocity = SIMD2<Float>.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        isOpaque = true
        metalLayer.isOpaque = true
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        if !motion.isDeviceMotionAvailable {
            addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:))))
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive {
            restGravity = nil
            motion.deviceMotionUpdateInterval = 1.0 / 120
            motion.startDeviceMotionUpdates()
        } else if window == nil {
            motion.stopDeviceMotionUpdates()
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            let translation = gesture.translation(in: self)
            manualTilt = CGPoint(x: max(-1, min(1, translation.x / (bounds.width / 2))),
                                 y: max(-1, min(1, translation.y / (bounds.height / 2))))
        default:
            manualTilt = nil   // let go: the liquid sloshes back
        }
    }

    override func update(deltaTime: CFTimeInterval) {
        let dt = Float(deltaTime)
        var target = SIMD2<Float>.zero
        if let gravity = motion.deviceMotion?.gravity {
            let current = SIMD2(gravity.x, gravity.y)
            // The pose the phone is held in slowly becomes the new "level", so the liquid settles.
            let rest = restGravity ?? current
            restGravity = rest + (current - rest) * min(0.3 * deltaTime, 1)
            let delta = current - rest
            // Device y points to the top of the phone; screen y points down.
            target = SIMD2(Float(delta.x), Float(-delta.y)) * Float(motionStrength)
        } else if let manualTilt {
            target = SIMD2(Float(manualTilt.x), Float(manualTilt.y)) * Float(motionStrength)
        }
        // Damped spring toward the target: the colors overshoot and settle like a liquid.
        tiltVelocity += (target - tilt) * 40 * dt
        tiltVelocity *= max(0, 1 - 7 * dt)
        tilt += tiltVelocity * dt
    }

    override func encode(into commandBuffer: MTLCommandBuffer, target: MTLTexture) {
        let palette = colors.prefix(8).map { color -> SIMD4<Float> in
            let c = color.vfxSIMD(with: traitCollection)
            return SIMD4(pow(c.x, 2.2), pow(c.y, 2.2), pow(c.z, 2.2), c.w)   // blend in linear light
        }
        guard let gpu, !palette.isEmpty,
              let pipeline = gpu.renderPipeline(vertex: "fluid_gradient_vertex", fragment: "fluid_gradient_fragment"),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass(target: target)) else {
            super.encode(into: commandBuffer, target: target)
            return
        }
        var uniforms = FluidUniforms(
            viewport: SIMD2(Float(target.width), Float(target.height)),
            time: Float(time.truncatingRemainder(dividingBy: 4096)),
            speed: Float(speed),
            tilt: tilt,
            flow: tiltVelocity,
            colorCount: UInt32(palette.count),
            blobSize: Float(max(blobSize, 0.05)),
            warp: Float(warp),
            grain: 1.5)
        var paletteBytes = palette
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FluidUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&paletteBytes, length: MemoryLayout<SIMD4<Float>>.stride * paletteBytes.count, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}
