//
//  GravityBlackHoleAnimator.swift
//  controller
//
//  Swallows a view into the Dynamic Island: the view is snapshotted and redrawn by
//  Shaders/BlackHoleWarp.metal in a full-window overlay while the real view disappears.
//

import UIKit
import Metal

/// Mirrors `BlackHoleUniforms` in BlackHoleWarp.metal.
private struct BlackHoleUniforms {
    var viewport: SIMD2<Float>
    var scale: Float
    var progress: Float
    var element: SIMD4<Float>
    var island: SIMD4<Float>
    var swallowRadius: Float
    var spin: Float
    var core: Float
    var unused: Float = 0
}

final class GravityBlackHoleAnimator {
    var duration: TimeInterval = 0.8
    /// Swirl at the core, in radians.
    var spin: CGFloat = 4.5
    /// Size of the gravity core in points; smaller = sharper spaghettification.
    var coreSize: CGFloat = 80

    private var overlays: [BlackHoleOverlay] = []

    /// Plays the swallow from the view's current on-screen position. The view is hidden (alpha 0)
    /// right away; restore it in `completion` if you reuse it.
    func swallow(_ view: UIView, completion: (() -> Void)? = nil) {
        if !playOverlay(for: view, completion: completion) {
            completion?()
        }
        view.alpha = 0
    }

    /// Deletes a row by swallowing its cell. `updates` must remove the item from the data source;
    /// the row is deleted right away so the rows below close the gap while the cell falls in.
    /// The real cell fades out under the overlay rather than being hidden, so a recycled cell
    /// never comes back invisible.
    func deleteRow(at indexPath: IndexPath, in tableView: UITableView, updates: () -> Void) {
        if let cell = tableView.cellForRow(at: indexPath) {
            playOverlay(for: cell, completion: nil)
        }
        updates()
        tableView.deleteRows(at: [indexPath], with: .fade)
    }

    @discardableResult
    private func playOverlay(for view: UIView, completion: (() -> Void)?) -> Bool {
        guard let window = view.window,
              let texture = VFXGPU.shared?.makeTexture(snapshotting: view, scale: window.traitCollection.displayScale)
        else { return false }
        let overlay = BlackHoleOverlay(element: view.convert(view.bounds, to: window),
                                       island: DynamicIslandGeometry.frame(in: window),
                                       texture: texture, duration: duration,
                                       spin: Float(spin), core: Float(coreSize))
        overlay.frame = window.bounds
        overlay.onFinish = { [weak self, weak overlay] in
            overlay?.removeFromSuperview()
            self?.overlays.removeAll { $0 === overlay }
            completion?()
        }
        overlays.append(overlay)
        window.addSubview(overlay)
        return true
    }
}

private final class BlackHoleOverlay: VFXMetalView {
    var onFinish: (() -> Void)?

    private let element: CGRect
    private let island: CGRect
    private let texture: MTLTexture
    private let duration: TimeInterval
    private let spin: Float
    private let core: Float
    private var progress: Float = 0
    private var finished = false
    private var hapticPlayed = false
    private let haptic = UIImpactFeedbackGenerator(style: .soft)

    init(element: CGRect, island: CGRect, texture: MTLTexture, duration: TimeInterval, spin: Float, core: Float) {
        self.element = element
        self.island = island
        self.texture = texture
        self.duration = duration
        self.spin = spin
        self.core = core
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        haptic.prepare()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func update(deltaTime: CFTimeInterval) {
        progress = Float(min(time / max(duration, 0.01), 1))
        if progress > 0.85, !hapticPlayed {
            hapticPlayed = true
            haptic.impactOccurred(intensity: 0.7)
        }
        if progress >= 1, !finished {
            finished = true
            isPaused = true
            DispatchQueue.main.async { [weak self] in self?.onFinish?() }
        }
    }

    override func encode(into commandBuffer: MTLCommandBuffer, target: MTLTexture) {
        guard let gpu, let pipeline = gpu.renderPipeline(vertex: "black_hole_vertex", fragment: "black_hole_fragment"),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass(target: target)) else { return }
        let hole = CGPoint(x: island.midX, y: island.midY)
        let corners = [CGPoint(x: element.minX, y: element.minY), CGPoint(x: element.maxX, y: element.minY),
                       CGPoint(x: element.minX, y: element.maxY), CGPoint(x: element.maxX, y: element.maxY)]
        let reach = corners.map { hypot($0.x - hole.x, $0.y - hole.y) }.max() ?? 0

        var uniforms = BlackHoleUniforms(
            viewport: SIMD2(Float(target.width), Float(target.height)),
            scale: Float(contentScaleFactor),
            progress: progress,
            element: SIMD4(Float(element.minX), Float(element.minY), Float(element.width), Float(element.height)),
            island: SIMD4(Float(island.minX), Float(island.minY), Float(island.width), Float(island.height)),
            swallowRadius: Float(reach), spin: spin, core: core)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<BlackHoleUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}
