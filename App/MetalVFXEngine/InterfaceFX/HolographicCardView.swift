//
//  HolographicCardView.swift
//  controller
//
//  A card with holographic foil: the content is snapshotted once and redrawn every frame with
//  a rainbow, glare and glitter driven by tilt (CoreMotion, or the finger while it is down).
//  The view itself also turns in 3D. Shader: Shaders/HolographicCard.metal.
//

import UIKit
import Metal
import simd
import CoreMotion

/// Mirrors `HoloUniforms` in HolographicCard.metal.
private struct HoloUniforms {
    var size: SIMD2<Float>
    var tilt: SIMD2<Float>
    var time: Float
    var foil: Float
    var glare: Float
    var glitter: Float
}

final class HolographicCardView: VFXMetalView {
    /// The card's artwork. Lay it out like any view; it is rendered offscreen, not added as a subview.
    let contentView = UIView()
    var cornerRadius: CGFloat = 22 {
        didSet { setNeedsContentUpdate() }
    }
    var foil: CGFloat = 0.6
    var glare: CGFloat = 0.8
    var glitter: CGFloat = 0.6
    /// Maximum 3D turn of the card, in radians.
    var maxRotation: CGFloat = 0.32
    /// How strongly tilting the phone moves the light.
    var motionStrength: CGFloat = 2.2

    private var texture: MTLTexture?
    private var needsContentUpdate = true
    private let motion = CMMotionManager()
    private var restGravity: SIMD2<Double>?
    private var fingerTilt: SIMD2<Float>?
    private var tilt = SIMD2<Float>.zero
    private var tiltVelocity = SIMD2<Float>.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 18
        addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
            .configured { $0.minimumPressDuration = 0 })
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Re-snapshot `contentView` on the next frame, after you change it.
    func setNeedsContentUpdate() {
        needsContentUpdate = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if contentView.bounds.size != bounds.size {
            contentView.frame = bounds
            needsContentUpdate = true
        }
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius).cgPath
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

    @objc private func handlePress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            // The touched point dips away from the viewer, as if pressing on the card.
            let p = gesture.location(in: self)
            let x = Float(max(-1, min(1, p.x / max(bounds.width, 1) * 2 - 1)))
            let y = Float(max(-1, min(1, p.y / max(bounds.height, 1) * 2 - 1)))
            fingerTilt = SIMD2(-x, -y)
        default:
            fingerTilt = nil
        }
    }

    override func update(deltaTime: CFTimeInterval) {
        let dt = Float(deltaTime)
        var target = SIMD2<Float>.zero
        if let fingerTilt {
            target = fingerTilt
        } else if let gravity = motion.deviceMotion?.gravity {
            let current = SIMD2(gravity.x, gravity.y)
            // The pose the phone is held in slowly becomes "level", so the card settles.
            let rest = restGravity ?? current
            restGravity = rest + (current - rest) * min(0.4 * deltaTime, 1)
            let delta = current - rest
            target = SIMD2(Float(delta.x), Float(-delta.y)) * Float(motionStrength)
        } else {
            // No sensor (simulator) and no finger: a slow idle sway shows the foil off.
            target = SIMD2(sin(Float(time) * 0.6) * 0.35, cos(Float(time) * 0.45) * 0.25)
        }
        target = simd_clamp(target, SIMD2(repeating: -1), SIMD2(repeating: 1))
        tiltVelocity += (target - tilt) * 90 * dt
        tiltVelocity *= max(0, 1 - 12 * dt)
        tilt += tiltVelocity * dt

        // Turn the view itself: tilt.x > 0 brings the right edge towards the viewer.
        var transform = CATransform3DIdentity
        transform.m34 = -1 / 900
        transform = CATransform3DRotate(transform, CGFloat(tilt.x) * maxRotation, 0, 1, 0)
        transform = CATransform3DRotate(transform, CGFloat(-tilt.y) * maxRotation, 1, 0, 0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = transform
        layer.shadowOffset = CGSize(width: CGFloat(-tilt.x) * 14, height: 14 + CGFloat(-tilt.y) * 10)
        CATransaction.commit()
    }

    override func encode(into commandBuffer: MTLCommandBuffer, target: MTLTexture) {
        if needsContentUpdate {
            refreshTexture()
        }
        guard let gpu, let texture,
              let pipeline = gpu.renderPipeline(vertex: "holo_vertex", fragment: "holo_fragment"),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass(target: target)) else {
            super.encode(into: commandBuffer, target: target)
            return
        }
        var uniforms = HoloUniforms(size: SIMD2(Float(bounds.width), Float(bounds.height)), tilt: tilt,
                                    time: Float(time.truncatingRemainder(dividingBy: 4096)),
                                    foil: Float(foil), glare: Float(glare), glitter: Float(glitter))
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<HoloUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private func refreshTexture() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        needsContentUpdate = false
        contentView.frame = bounds
        contentView.layer.cornerRadius = cornerRadius
        contentView.layer.cornerCurve = .continuous
        contentView.layer.masksToBounds = true
        contentView.layoutIfNeeded()
        texture = gpu?.makeTexture(snapshotting: contentView, scale: contentScaleFactor)
    }
}

extension UIGestureRecognizer {
    /// Inline configuration: `UIPanGestureRecognizer(...).configured { $0.maximumNumberOfTouches = 1 }`.
    func configured(_ configure: (Self) -> Void) -> Self {
        configure(self)
        return self
    }
}
