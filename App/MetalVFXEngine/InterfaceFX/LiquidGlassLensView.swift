//
//  LiquidGlassLensView.swift
//  controller
//
//  A draggable liquid-glass lens over live UI. Every frame the region of `backdropView` under the
//  lens is snapshotted (VFXSnapshotter, mipmapped) and refracted by Shaders/LiquidGlass.metal.
//  The lens stretches along its motion and wobbles back like a drop of liquid.
//

import UIKit
import Metal
import simd

/// Mirrors `GlassUniforms` in LiquidGlass.metal.
private struct GlassUniforms {
    var viewSize: SIMD2<Float>
    var shapeSize: SIMD2<Float>
    var axis: SIMD2<Float>
    var stretch: Float
    var pad: Float = 0
    var snapshotOrigin: SIMD2<Float>
    var snapshotSize: SIMD2<Float>
    var cornerRadius: Float
    var refraction: Float
    var zoom: Float
    var blur: Float
    var dispersion: Float
    var pressed: Float
    var tint: SIMD4<Float>
}

final class LiquidGlassLensView: VFXMetalView {
    /// The view under the lens. Put the lens above it (not inside it) so it never captures itself.
    weak var backdropView: UIView?
    var lensSize = CGSize(width: 190, height: 110) {
        didSet { invalidateIntrinsicContentSize() }
    }
    var cornerRadius: CGFloat = 55
    /// How far the rounded rim bends the background, in points.
    var refraction: CGFloat = 24
    var zoom: CGFloat = 1.2
    /// Frosted blur, as a mip level (0 = clear glass).
    var frost: CGFloat = 0.6
    var dispersion: CGFloat = 0.7
    var glassTint = UIColor(white: 1, alpha: 0.06)
    /// Snapshot resolution cap; the lens refracts and magnifies, so 2× is plenty.
    var maxSnapshotScale: CGFloat = 2

    /// Room around the shape for the shadow and the stretch.
    private let margin: CGFloat = 40
    private let snapshotter = VFXSnapshotter()

    private var stretch: Float = 0
    private var stretchVelocity: Float = 0
    private var axis = SIMD2<Float>(1, 0)
    private var dragVelocity = CGPoint.zero
    private var pressed: Float = 0
    private var isTouching = false
    private var dragOffset = CGPoint.zero
    private var lastDragTime: CFTimeInterval = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(handleDrag(_:)))
            .configured { $0.minimumPressDuration = 0 })
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The lens view is larger than the glass (shadow + stretch room); size it with this.
    override var intrinsicContentSize: CGSize {
        let side = max(lensSize.width, lensSize.height) * 1.45 + margin * 2
        return CGSize(width: side, height: side)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // Only the glass itself is touchable; the transparent margin passes touches through.
        let glass = CGRect(x: bounds.midX - lensSize.width / 2, y: bounds.midY - lensSize.height / 2,
                           width: lensSize.width, height: lensSize.height)
        return glass.insetBy(dx: -8, dy: -8).contains(point)
    }

    @objc private func handleDrag(_ gesture: UILongPressGestureRecognizer) {
        guard let superview else { return }
        let location = gesture.location(in: superview)
        switch gesture.state {
        case .began:
            isTouching = true
            dragOffset = CGPoint(x: center.x - location.x, y: center.y - location.y)
            dragVelocity = .zero
            lastDragTime = CACurrentMediaTime()
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case .changed:
            let next = CGPoint(x: location.x + dragOffset.x, y: location.y + dragOffset.y)
            // Long-press recognizers have no velocity: estimate it from the movement between events.
            let now = CACurrentMediaTime()
            let dt = CGFloat(max(now - lastDragTime, 1.0 / 240))
            lastDragTime = now
            let instant = CGPoint(x: (next.x - center.x) / dt, y: (next.y - center.y) / dt)
            dragVelocity = CGPoint(x: dragVelocity.x * 0.7 + instant.x * 0.3, y: dragVelocity.y * 0.7 + instant.y * 0.3)
            center = next
        default:
            isTouching = false
            dragVelocity = .zero
        }
    }

    override func update(deltaTime: CFTimeInterval) {
        let dt = Float(deltaTime)
        // Stretch towards the drag speed; an underdamped spring makes it wobble back like liquid.
        let speed = Float(hypot(dragVelocity.x, dragVelocity.y))
        if speed > 30 {
            let direction = SIMD2(Float(dragVelocity.x), Float(dragVelocity.y)) / speed
            axis = simd_normalize(axis + (direction - axis) * min(12 * dt, 1))
        }
        let target = min(speed / 2600, 0.38)
        stretchVelocity += (target - stretch) * 260 * dt
        stretchVelocity *= max(0, 1 - 9 * dt)
        stretch += stretchVelocity * dt
        // The movement estimate decays when the finger stops but the gesture does not fire.
        dragVelocity = CGPoint(x: dragVelocity.x * CGFloat(max(0, 1 - 10 * dt)),
                               y: dragVelocity.y * CGFloat(max(0, 1 - 10 * dt)))
        pressed += ((isTouching ? 1 : 0) - pressed) * min(14 * dt, 1)
    }

    override func encode(into commandBuffer: MTLCommandBuffer, target: MTLTexture) {
        guard let gpu, let backdrop = backdropView,
              let pipeline = gpu.renderPipeline(vertex: "glass_vertex", fragment: "glass_fragment") else {
            super.encode(into: commandBuffer, target: target)
            return
        }
        // Region of the backdrop under this view, padded so the rim can bend in what is outside.
        let pad = refraction + 8
        let region = convert(bounds, to: backdrop).insetBy(dx: -pad, dy: -pad)
        // Every frame, so the lens shows live content (scrolling, animations) — mipmapped for the frost.
        guard let snapshot = snapshotter.snapshot(backdrop, region: region,
                                                  scale: min(contentScaleFactor, maxSnapshotScale),
                                                  mipmapped: true, commandBuffer: commandBuffer),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass(target: target)) else {
            super.encode(into: commandBuffer, target: target)
            return
        }
        let tint = glassTint.vfxSIMD(with: traitCollection)
        var uniforms = GlassUniforms(
            viewSize: SIMD2(Float(bounds.width), Float(bounds.height)),
            // The glass swells a little while pressed (drawn bigger, not scaled, so the
            // backdrop mapping stays 1:1).
            shapeSize: SIMD2(Float(lensSize.width), Float(lensSize.height)) * (1 + 0.08 * pressed),
            axis: axis, stretch: max(stretch, -0.15),
            snapshotOrigin: SIMD2(Float(pad), Float(pad)),
            snapshotSize: SIMD2(Float(region.width), Float(region.height)),
            cornerRadius: Float(cornerRadius), refraction: Float(refraction), zoom: Float(zoom),
            blur: Float(frost), dispersion: Float(dispersion), pressed: pressed,
            tint: tint)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(snapshot, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GlassUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}
