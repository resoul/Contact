//
//  SandVacuumAnimator.swift
//  controller
//
//  Crumbles a view into sand and vacuums it up into the Dynamic Island: the view is snapshotted,
//  every grain takes the color of its cell, and grains let go (closest to the island first) and
//  spiral in. Shaders: Shaders/IslandSand.metal. Same API shape as GravityBlackHoleAnimator.
//

import UIKit
import Metal

/// Mirrors `SandGrain` in IslandSand.metal.
private struct SandGrain {
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var color: SIMD4<Float>
    var release: Float
    var seed: Float
    var alive: Float
    var unused: Float
}

/// Mirrors `SandVacuumUniforms` in IslandSand.metal.
private struct SandVacuumUniforms {
    var viewport: SIMD2<Float>
    var scale: Float
    var time: Float
    var element: SIMD4<Float>
    var island: SIMD4<Float>
    var grain: Float
    var columns: UInt32
    var rows: UInt32
    var releaseWindow: Float
    var suction: Float
    var swirl: Float
    var dt: Float
    var fade: Float
}

final class SandVacuumAnimator {
    /// Grain size in points; grows automatically for big views to cap the grain count.
    var grainSize: CGFloat = 1.5
    /// Seconds over which the whole view crumbles.
    var releaseWindow: TimeInterval = 0.75
    var suction: CGFloat = 3200
    var swirl: CGFloat = 380

    private var overlays: [SandVacuumOverlay] = []

    /// Vacuums `view` into the island. The view is hidden right away; restore it in `completion`.
    func vacuum(_ view: UIView, completion: (() -> Void)? = nil) {
        if !playOverlay(for: view, completion: completion) {
            completion?()
        }
        view.alpha = 0
    }

    /// Deletes a row by vacuuming its cell; `updates` must remove the item from the data source.
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
        let element = view.convert(view.bounds, to: window)
        // Keep it under ~80k grains whatever the view's size.
        let grain = max(grainSize, sqrt(element.width * element.height / 80_000))
        guard let overlay = SandVacuumOverlay(element: element, island: DynamicIslandGeometry.frame(in: window),
                                              texture: texture, grain: grain, animator: self) else { return false }
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

private final class SandVacuumOverlay: VFXMetalView {
    var onFinish: (() -> Void)?

    private let element: CGRect
    private let island: CGRect
    private let texture: MTLTexture
    private let grain: CGFloat
    private let columns: Int
    private let rows: Int
    private let grains: MTLBuffer
    private let releaseWindow: Float
    private let suction: Float
    private let swirl: Float
    private var spawned = false
    private var finished = false
    private var stepDelta: Float = 0
    private var lastTick = -1
    private let haptic = UIImpactFeedbackGenerator(style: .soft)

    /// Total running time: the last grains need a moment to reach the island after letting go.
    private var duration: TimeInterval { TimeInterval(releaseWindow) + 1.1 }

    init?(element: CGRect, island: CGRect, texture: MTLTexture, grain: CGFloat, animator: SandVacuumAnimator) {
        let columns = max(1, Int(ceil(element.width / grain)))
        let rows = max(1, Int(ceil(element.height / grain)))
        guard let buffer = VFXGPU.shared?.device.makeBuffer(length: MemoryLayout<SandGrain>.stride * columns * rows,
                                                            options: .storageModePrivate) else { return nil }
        self.element = element
        self.island = island
        self.texture = texture
        self.grain = grain
        self.columns = columns
        self.rows = rows
        self.grains = buffer
        self.releaseWindow = Float(animator.releaseWindow)
        self.suction = Float(animator.suction)
        self.swirl = Float(animator.swirl)
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        haptic.prepare()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func update(deltaTime: CFTimeInterval) {
        stepDelta = Float(deltaTime)
        // A soft rattle while the sand streams in, like grit going up a vacuum hose.
        let tick = Int(time / 0.07)
        if time > 0.15, time < TimeInterval(releaseWindow) + 0.4, tick != lastTick {
            lastTick = tick
            haptic.impactOccurred(intensity: 0.25 + 0.2 * CGFloat.random(in: 0...1))
        }
        if time >= duration, !finished {
            finished = true
            isPaused = true
            DispatchQueue.main.async { [weak self] in self?.onFinish?() }
        }
    }

    private func uniforms(target: MTLTexture) -> SandVacuumUniforms {
        let fade = 1 - max(0, min(1, (time - (duration - 0.3)) / 0.3))
        return SandVacuumUniforms(
            viewport: SIMD2(Float(target.width), Float(target.height)),
            scale: Float(contentScaleFactor),
            time: Float(time),
            element: SIMD4(Float(element.minX), Float(element.minY), Float(element.width), Float(element.height)),
            island: SIMD4(Float(island.minX), Float(island.minY), Float(island.width), Float(island.height)),
            grain: Float(grain), columns: UInt32(columns), rows: UInt32(rows),
            releaseWindow: releaseWindow, suction: suction, swirl: swirl,
            dt: stepDelta, fade: Float(fade))
    }

    override func encode(into commandBuffer: MTLCommandBuffer, target: MTLTexture) {
        guard let gpu,
              let spawn = gpu.computePipeline("sand_vacuum_spawn"),
              let step = gpu.computePipeline("sand_vacuum_update"),
              let grainPipeline = gpu.renderPipeline(vertex: "sand_grain_vertex", fragment: "sand_grain_fragment"),
              let elementPipeline = gpu.renderPipeline(vertex: "sand_element_vertex", fragment: "sand_element_fragment")
        else {
            super.encode(into: commandBuffer, target: target)
            return
        }
        var params = uniforms(target: target)
        let count = columns * rows

        if let compute = commandBuffer.makeComputeCommandEncoder() {
            let pipeline = spawned ? step : spawn
            compute.setComputePipelineState(pipeline)
            compute.setBuffer(grains, offset: 0, index: 0)
            compute.setBytes(&params, length: MemoryLayout<SandVacuumUniforms>.stride, index: 1)
            if !spawned {
                compute.setTexture(texture, index: 0)
                spawned = true
            }
            let width = pipeline.threadExecutionWidth
            compute.dispatchThreadgroups(MTLSize(width: (count + width - 1) / width, height: 1, depth: 1),
                                         threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1))
            compute.endEncoding()
        }

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass(target: target)) else { return }
        encoder.setRenderPipelineState(elementPipeline)
        encoder.setVertexBytes(&params, length: MemoryLayout<SandVacuumUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&params, length: MemoryLayout<SandVacuumUniforms>.stride, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        encoder.setRenderPipelineState(grainPipeline)
        encoder.setVertexBuffer(grains, offset: 0, index: 0)
        encoder.setVertexBytes(&params, length: MemoryLayout<SandVacuumUniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: count)
        encoder.endEncoding()
    }
}
