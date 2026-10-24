//
//  SandHourglassView.swift
//  controller
//
//  A loading indicator that turns the Dynamic Island into an hourglass: sand pours out of the island
//  into a basin (any view's frame) and piles up; the heap is the progress. When loading is done the
//  sand glints and vanishes. Simulation: a falling-sand cellular automaton in Shaders/IslandSand.metal.
//

import UIKit
import Metal

/// Mirrors `HourglassUniforms` in IslandSand.metal.
private struct HourglassUniforms {
    var viewport: SIMD2<Float>
    var scale: Float
    var dissolve: Float
    var rect: SIMD4<Float>
    var cell: Float
    var columns: UInt32
    var rows: UInt32
    var step: UInt32
    var emitColumn: Float
    var emitWidth: Float
    var emitRate: Float
    var unused: Float = 0
    var sandDark: SIMD4<Float>
    var sandLight: SIMD4<Float>
}

final class SandHourglassView: VFXMetalView {
    /// Cell (grain) size, points.
    var cellSize: CGFloat = 2.5
    /// Stream width under the island, points.
    var streamWidth: CGFloat = 16
    /// Automaton steps per second: how fast grains fall (cells per second).
    var stepsPerSecond: Double = 420
    var sandDark = UIColor(red: 0.72, green: 0.52, blue: 0.27, alpha: 1)
    var sandLight = UIColor(red: 0.97, green: 0.84, blue: 0.58, alpha: 1)
    /// How full the basin is at progress 1, as a share of its area.
    var fullness: CGFloat = 0.3
    /// Called once the sand has vanished after `finish()`.
    var onFinish: (() -> Void)?

    /// 0…1: how much sand should have poured. The stream runs until the heap catches up.
    var progress: CGFloat = 0 {
        didSet { if progress > oldValue { isPaused = false } }
    }

    private weak var basin: UIView?
    private var rect: CGRect = .zero
    private var gridBasinFrame: CGRect = .null
    private var columns = 0
    private var rows = 0
    private var grids: [MTLTexture] = []
    private var current = 0
    private var stepCounter: UInt32 = 0
    private var stepAccumulator: Double = 0
    private var stepsThisFrame = 0
    private var dissolveStart: CFTimeInterval?
    private var needsClear = true
    private var finished = false
    /// Grains spawned so far, counted on the GPU (shared memory, read a frame or two late).
    private let emittedCounter = VFXGPU.shared?.device.makeBuffer(length: 4, options: .storageModeShared)
    private let haptic = UIImpactFeedbackGenerator(style: .light)
    private var lastHapticCount = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Covers `basin`'s window; sand pours from the island down into `basin`'s frame.
    /// The basin must lie below the island and span its center horizontally.
    func attach(to basin: UIView) {
        guard let window = basin.window else { return }
        self.basin = basin
        dissolveStart = nil
        finished = false
        lastHapticCount = 0
        frame = window.bounds
        window.addSubview(self)
        rebuildGrid()
        isPaused = false
    }

    func detach() {
        removeFromSuperview()
        isPaused = true
    }

    /// Loading done: the stream stops and the sand glints and vanishes.
    func finish() {
        guard dissolveStart == nil else { return }
        progress = 1
        dissolveStart = time
        isPaused = false
    }

    private var emitted: Int {
        emittedCounter.map { Int($0.contents().load(as: UInt32.self)) } ?? 0
    }

    private var capacity: Int {
        guard let basin, let window = basin.window else { return 1 }
        let frame = basin.convert(basin.bounds, to: window)
        return max(1, Int(frame.width * frame.height / (cellSize * cellSize) * fullness))
    }

    private func rebuildGrid() {
        guard let gpu, let basin, let window = basin.window else { return }
        let island = DynamicIslandGeometry.frame(in: window)
        let basinFrame = basin.convert(basin.bounds, to: window)
        gridBasinFrame = basinFrame
        rect = CGRect(x: basinFrame.minX, y: island.maxY - 2, width: basinFrame.width, height: basinFrame.maxY - island.maxY + 2)
        columns = max(2, Int(rect.width / cellSize))
        rows = max(2, Int(rect.height / cellSize))
        rect.size = CGSize(width: CGFloat(columns) * cellSize, height: CGFloat(rows) * cellSize)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Uint, width: columns, height: rows,
                                                                  mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        grids = (0..<2).compactMap { _ in gpu.device.makeTexture(descriptor: descriptor) }
        emittedCounter?.contents().storeBytes(of: UInt32(0), as: UInt32.self)
        needsClear = true
    }

    override func update(deltaTime: CFTimeInterval) {
        stepAccumulator = min(stepAccumulator + deltaTime * stepsPerSecond, 8)
        stepsThisFrame = Int(stepAccumulator)
        stepAccumulator -= Double(stepsThisFrame)
        // The basin may not be laid out yet when attached, or may move: the grid follows it.
        if let basin, let window = basin.window, basin.convert(basin.bounds, to: window) != gridBasinFrame {
            rebuildGrid()
        }

        // A light patter of haptics as the heap grows.
        let count = emitted
        if dissolveStart == nil, count - lastHapticCount > capacity / 40 {
            lastHapticCount = count
            haptic.impactOccurred(intensity: 0.35)
        }
        if let start = dissolveStart, time - start > 0.9, !finished {
            finished = true
            isPaused = true
            DispatchQueue.main.async { [weak self] in self?.onFinish?() }
        }
    }

    override func encode(into commandBuffer: MTLCommandBuffer, target: MTLTexture) {
        guard let gpu, grids.count == 2, let emittedCounter,
              let stepPipeline = gpu.computePipeline("sand_hourglass_step"),
              let renderPipeline = gpu.renderPipeline(vertex: "sand_hourglass_vertex", fragment: "sand_hourglass_fragment")
        else {
            super.encode(into: commandBuffer, target: target)
            return
        }
        if needsClear {
            needsClear = false
            let zeros = [UInt8](repeating: 0, count: columns * rows)
            for grid in grids {
                grid.replace(region: MTLRegionMake2D(0, 0, columns, rows), mipmapLevel: 0,
                             withBytes: zeros, bytesPerRow: columns)
            }
        }

        let island = window.map { DynamicIslandGeometry.frame(in: $0) } ?? .zero
        let pouring = dissolveStart == nil && CGFloat(emitted) < progress * CGFloat(capacity)
        let dissolve = dissolveStart.map { Float(min(1, (time - $0) / 0.8)) } ?? 0
        var uniforms = HourglassUniforms(
            viewport: SIMD2(Float(target.width), Float(target.height)),
            scale: Float(contentScaleFactor),
            dissolve: dissolve,
            rect: SIMD4(Float(rect.minX), Float(rect.minY), Float(rect.width), Float(rect.height)),
            cell: Float(cellSize), columns: UInt32(columns), rows: UInt32(rows), step: stepCounter,
            emitColumn: Float((island.midX - rect.minX) / cellSize),
            emitWidth: Float(streamWidth / cellSize),
            emitRate: pouring ? 0.85 : 0,
            sandDark: sandDark.vfxSIMD(with: traitCollection),
            sandLight: sandLight.vfxSIMD(with: traitCollection))

        if stepsThisFrame > 0, dissolveStart == nil, let compute = commandBuffer.makeComputeCommandEncoder() {
            compute.setComputePipelineState(stepPipeline)
            compute.setBuffer(emittedCounter, offset: 0, index: 1)
            let blocks = MTLSize(width: columns / 2 + 1, height: rows / 2 + 1, depth: 1)
            let threads = MTLSize(width: 16, height: 16, depth: 1)
            let groups = MTLSize(width: (blocks.width + 15) / 16, height: (blocks.height + 15) / 16, depth: 1)
            for _ in 0..<stepsThisFrame {
                uniforms.step = stepCounter
                compute.setTexture(grids[current], index: 0)
                compute.setTexture(grids[1 - current], index: 1)
                compute.setBytes(&uniforms, length: MemoryLayout<HourglassUniforms>.stride, index: 0)
                compute.dispatchThreadgroups(groups, threadsPerThreadgroup: threads)
                current = 1 - current
                stepCounter &+= 1
            }
            compute.endEncoding()
        }

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass(target: target)) else { return }
        encoder.setRenderPipelineState(renderPipeline)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<HourglassUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<HourglassUniforms>.stride, index: 0)
        encoder.setFragmentTexture(grids[current], index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
    }
}
