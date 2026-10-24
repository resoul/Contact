//
//  DustAnimator.swift
//  controller
//
//  Blows a view away as dust (dust_* in ChannelFX.metal): the view is snapshotted, crumbles from
//  left to right into grains colored from the snapshot, and the grains drift off on little eddies
//  and fade. The overlay covers the window, touch-through, and removes itself.
//

import UIKit
import Metal

/// Mirrors `DustGrain` in ChannelFX.metal.
private struct DustGrain {
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var color: SIMD4<Float>
    var release: Float
    var seed: Float
    var alive: Float
    var life: Float
}

/// Mirrors `DustUniforms` in ChannelFX.metal.
private struct DustUniforms {
    var viewport: SIMD2<Float>
    var scale: Float
    var time: Float
    var element: SIMD4<Float>
    var grain: Float
    var columns: UInt32
    var rows: UInt32
    var releaseWindow: Float
    var wind: SIMD2<Float>
    var gravity: Float
    var dt: Float
}

enum DustAnimator {
    /// Crumbles `view` into dust. The view is hidden right away (alpha 0); `completion` runs at the end.
    /// `wind` is the drift in points/s, `gravity` pulls down (negative floats up).
    static func blowAway(_ view: UIView, wind: CGVector = CGVector(dx: 70, dy: -50), gravity: CGFloat = -30,
                         grain: CGFloat = 1.2, releaseWindow: TimeInterval = 0.5, completion: (() -> Void)? = nil) {
        guard let window = view.window,
              let texture = VFXGPU.shared?.makeTexture(snapshotting: view, scale: window.traitCollection.displayScale) else {
            view.alpha = 0
            completion?()
            return
        }
        let element = view.convert(view.bounds, to: window)
        let size = max(grain, sqrt(element.width * element.height / 40_000))
        guard let overlay = DustOverlay(element: element, texture: texture, grain: size, wind: wind, gravity: gravity,
                                        releaseWindow: releaseWindow) else {
            view.alpha = 0
            completion?()
            return
        }
        overlay.frame = window.bounds
        overlay.onFinish = { [weak overlay] in
            overlay?.removeFromSuperview()
            completion?()
        }
        window.addSubview(overlay)
        view.alpha = 0
    }
}

private final class DustOverlay: VFXMetalView {
    var onFinish: (() -> Void)?

    private let element: CGRect
    private let texture: MTLTexture
    private let grain: CGFloat
    private let columns: Int
    private let rows: Int
    private let grains: MTLBuffer
    private let wind: CGVector
    private let gravity: CGFloat
    private let releaseWindow: TimeInterval
    private var spawned = false
    private var finished = false
    private var stepDelta: Float = 0

    init?(element: CGRect, texture: MTLTexture, grain: CGFloat, wind: CGVector, gravity: CGFloat, releaseWindow: TimeInterval) {
        let columns = max(1, Int(ceil(element.width / grain)))
        let rows = max(1, Int(ceil(element.height / grain)))
        guard let buffer = VFXGPU.shared?.device.makeBuffer(length: MemoryLayout<DustGrain>.stride * columns * rows,
                                                            options: .storageModePrivate) else { return nil }
        self.element = element
        self.texture = texture
        self.grain = grain
        self.columns = columns
        self.rows = rows
        self.grains = buffer
        self.wind = wind
        self.gravity = gravity
        self.releaseWindow = releaseWindow
        super.init(frame: .zero)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func update(deltaTime: CFTimeInterval) {
        stepDelta = Float(deltaTime)
        if time > releaseWindow + 1.3, !finished {
            finished = true
            isPaused = true
            DispatchQueue.main.async { [weak self] in self?.onFinish?() }
        }
    }

    override func encode(into commandBuffer: MTLCommandBuffer, target: MTLTexture) {
        guard let gpu,
              let spawn = gpu.computePipeline("dust_spawn"),
              let step = gpu.computePipeline("dust_update"),
              let grainPipeline = gpu.renderPipeline(vertex: "dust_grain_vertex", fragment: "dust_grain_fragment"),
              let elementPipeline = gpu.renderPipeline(vertex: "dust_element_vertex", fragment: "dust_element_fragment")
        else {
            super.encode(into: commandBuffer, target: target)
            return
        }
        var params = DustUniforms(
            viewport: SIMD2(Float(target.width), Float(target.height)), scale: Float(contentScaleFactor), time: Float(time),
            element: SIMD4(Float(element.minX), Float(element.minY), Float(element.width), Float(element.height)),
            grain: Float(grain), columns: UInt32(columns), rows: UInt32(rows), releaseWindow: Float(releaseWindow),
            wind: SIMD2(Float(wind.dx), Float(wind.dy)), gravity: Float(gravity), dt: stepDelta)
        let count = columns * rows

        if let compute = commandBuffer.makeComputeCommandEncoder() {
            let pipeline = spawned ? step : spawn
            compute.setComputePipelineState(pipeline)
            compute.setBuffer(grains, offset: 0, index: 0)
            compute.setBytes(&params, length: MemoryLayout<DustUniforms>.stride, index: 1)
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
        encoder.setVertexBytes(&params, length: MemoryLayout<DustUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&params, length: MemoryLayout<DustUniforms>.stride, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        encoder.setRenderPipelineState(grainPipeline)
        encoder.setVertexBuffer(grains, offset: 0, index: 0)
        encoder.setVertexBytes(&params, length: MemoryLayout<DustUniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: count)
        encoder.endEncoding()
    }
}
