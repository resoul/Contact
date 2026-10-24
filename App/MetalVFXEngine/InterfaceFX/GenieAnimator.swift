//
//  GenieAnimator.swift
//  controller
//
//  macOS-style genie: a view is sucked into a target (a dock icon, a button) through a curved
//  tube, and can be poured back out. Shader: Shaders/Genie.metal.
//

import UIKit
import Metal

/// Mirrors `GenieUniforms` in Genie.metal.
private struct GenieUniforms {
    var viewport: SIMD2<Float>
    var scale: Float
    var progress: Float
    var source: SIMD4<Float>
    var target: SIMD4<Float>
    var rows: UInt32
    var flip: Float
}

final class GenieAnimator {
    var duration: TimeInterval = 0.6
    /// Horizontal slices of the mesh; more = smoother curve.
    var rows = 96

    private var overlays: [GenieOverlay] = []
    private let snapshots = NSMapTable<UIView, AnyObject>.weakToStrongObjects()

    /// Sucks `view` into `target`. The view is hidden right away (alpha 0) and stays hidden.
    func minimize(_ view: UIView, into target: UIView, completion: (() -> Void)? = nil) {
        play(view, target: target, from: 0, to: 1) {
            completion?()
        }
        view.alpha = 0
    }

    /// Pours `view` back out of `target`. The view becomes visible (alpha 1) when it lands.
    func restore(_ view: UIView, from target: UIView, completion: (() -> Void)? = nil) {
        view.alpha = 0
        play(view, target: target, from: 1, to: 0) {
            view.alpha = 1
            completion?()
        }
    }

    private func play(_ view: UIView, target: UIView, from: Float, to: Float, completion: @escaping () -> Void) {
        guard let window = view.window ?? target.window, let gpu = VFXGPU.shared else {
            completion()
            return
        }
        // Restoring a hidden view: reuse the picture taken when it was minimized (a hidden view
        // has nothing on screen to snapshot).
        let texture: MTLTexture?
        if view.alpha > 0 {
            texture = gpu.makeTexture(snapshotting: view, scale: window.traitCollection.displayScale)
            if let texture { snapshots.setObject(texture, forKey: view) }
        } else {
            texture = snapshots.object(forKey: view) as? MTLTexture
        }
        guard let texture else {
            completion()
            return
        }
        let overlay = GenieOverlay(texture: texture, source: view.convert(view.bounds, to: window),
                                   target: target.convert(target.bounds, to: window),
                                   from: from, to: to, duration: duration, rows: rows)
        overlay.frame = window.bounds
        overlay.onFinish = { [weak self, weak overlay] in
            overlay?.removeFromSuperview()
            self?.overlays.removeAll { $0 === overlay }
            completion()
        }
        overlays.append(overlay)
        window.addSubview(overlay)
    }
}

private final class GenieOverlay: VFXMetalView {
    var onFinish: (() -> Void)?

    private let texture: MTLTexture
    private let source: CGRect
    private let target: CGRect
    private let from: Float
    private let to: Float
    private let duration: TimeInterval
    private let rows: Int
    private var progress: Float
    private var finished = false

    init(texture: MTLTexture, source: CGRect, target: CGRect, from: Float, to: Float,
         duration: TimeInterval, rows: Int) {
        self.texture = texture
        self.source = source
        self.target = target
        self.from = from
        self.to = to
        self.duration = duration
        self.rows = rows
        progress = from
        super.init(frame: .zero)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func update(deltaTime: CFTimeInterval) {
        let t = Float(min(time / max(duration, 0.01), 1))
        let eased = t * t * (3 - 2 * t)
        progress = from + (to - from) * eased
        if t >= 1, !finished {
            finished = true
            isPaused = true
            DispatchQueue.main.async { [weak self] in self?.onFinish?() }
        }
    }

    override func encode(into commandBuffer: MTLCommandBuffer, target drawable: MTLTexture) {
        guard let gpu, let pipeline = gpu.renderPipeline(vertex: "genie_vertex", fragment: "genie_fragment"),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass(target: drawable)) else { return }
        // The shader works "downwards"; for a target above the source, mirror y (and back in the shader).
        let flip = target.midY < source.midY
        func downSpace(_ r: CGRect) -> SIMD4<Float> {
            let y = flip ? -r.maxY : r.minY
            return SIMD4(Float(r.minX), Float(y), Float(r.width), Float(r.height))
        }
        var uniforms = GenieUniforms(viewport: SIMD2(Float(drawable.width), Float(drawable.height)),
                                     scale: Float(contentScaleFactor), progress: progress,
                                     source: downSpace(source), target: downSpace(target),
                                     rows: UInt32(rows), flip: flip ? 1 : 0)
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<GenieUniforms>.stride, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GenieUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: (rows + 1) * 2)
        encoder.endEncoding()
    }
}
