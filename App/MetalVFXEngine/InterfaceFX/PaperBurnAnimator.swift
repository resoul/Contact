//
//  PaperBurnAnimator.swift
//  controller
//
//  Burns a view away like paper from an ignition point: scorch, a glowing ember edge, sparks and
//  heat haze. Shader: Shaders/PaperBurn.metal.
//

import UIKit
import Metal

/// Mirrors `BurnUniforms` in PaperBurn.metal.
private struct BurnUniforms {
    var viewport: SIMD2<Float>
    var scale: Float
    var time: Float
    var element: SIMD4<Float>
    var origin: SIMD2<Float>
    var speed: Float
    var roughness: Float
}

final class PaperBurnAnimator {
    /// Time for the fire to reach the farthest corner.
    var duration: TimeInterval = 1.8
    /// Irregularity of the burn front, in seconds of delay.
    var roughness: CGFloat = 0.45

    private var overlays: [BurnOverlay] = []

    /// Sets `view` on fire at `ignition` (in the view's coordinates; nil = bottom-left corner).
    /// The view is hidden right away (alpha 0); restore it in `completion` if you reuse it.
    func burn(_ view: UIView, from ignition: CGPoint? = nil, completion: (() -> Void)? = nil) {
        guard let window = view.window,
              let texture = VFXGPU.shared?.makeTexture(snapshotting: view, scale: window.traitCollection.displayScale)
        else {
            view.alpha = 0
            completion?()
            return
        }
        let frame = view.convert(view.bounds, to: window)
        let origin = view.convert(ignition ?? CGPoint(x: view.bounds.minX + 12, y: view.bounds.maxY - 12), to: window)
        let corners = [CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY),
                       CGPoint(x: frame.minX, y: frame.maxY), CGPoint(x: frame.maxX, y: frame.maxY)]
        let reach = corners.map { hypot($0.x - origin.x, $0.y - origin.y) }.max() ?? 1
        let speed = reach / max(duration - roughness, 0.3)

        let overlay = BurnOverlay(texture: texture, element: frame, origin: origin, speed: speed,
                                  roughness: roughness, lifetime: duration + 1.0)
        overlay.frame = window.bounds
        overlay.onFinish = { [weak self, weak overlay] in
            overlay?.removeFromSuperview()
            self?.overlays.removeAll { $0 === overlay }
            completion?()
        }
        overlays.append(overlay)
        window.addSubview(overlay)
        view.alpha = 0
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

private final class BurnOverlay: VFXMetalView {
    var onFinish: (() -> Void)?

    private let texture: MTLTexture
    private let element: CGRect
    private let origin: CGPoint
    private let speed: CGFloat
    private let roughness: CGFloat
    private let lifetime: TimeInterval
    private var finished = false

    init(texture: MTLTexture, element: CGRect, origin: CGPoint, speed: CGFloat, roughness: CGFloat,
         lifetime: TimeInterval) {
        self.texture = texture
        self.element = element
        self.origin = origin
        self.speed = speed
        self.roughness = roughness
        self.lifetime = lifetime
        super.init(frame: .zero)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func update(deltaTime: CFTimeInterval) {
        if time >= lifetime, !finished {
            finished = true
            isPaused = true
            DispatchQueue.main.async { [weak self] in self?.onFinish?() }
        }
    }

    override func encode(into commandBuffer: MTLCommandBuffer, target: MTLTexture) {
        guard let gpu, let pipeline = gpu.renderPipeline(vertex: "burn_vertex", fragment: "burn_fragment"),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass(target: target)) else { return }
        var uniforms = BurnUniforms(viewport: SIMD2(Float(target.width), Float(target.height)),
                                    scale: Float(contentScaleFactor), time: Float(time),
                                    element: SIMD4(Float(element.minX), Float(element.minY),
                                                   Float(element.width), Float(element.height)),
                                    origin: SIMD2(Float(origin.x), Float(origin.y)),
                                    speed: Float(speed), roughness: Float(roughness))
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<BurnUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}
