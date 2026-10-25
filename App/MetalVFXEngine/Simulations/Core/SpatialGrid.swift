import Metal

/// Mirrors `GridParams` in EffectsSpatialGrid.h (32 bytes).
struct GridParams {
    var origin: SIMD2<Float>
    var cellSize: Float
    var dims: SIMD2<UInt32>
    var count: UInt32
}

/// GPU neighbour-search grid (counting sort into cells), shared by the fluid and the boids.
/// Kernels that query it bind `cellStart`, `cellCounts` and `sortedIndices`.
final class SpatialGrid {
    private(set) var cellStart: MTLBuffer
    private(set) var cellCounts: MTLBuffer
    private(set) var sortedIndices: MTLBuffer
    private var cellOf: MTLBuffer
    private var rankInCell: MTLBuffer

    private let clearPipeline: MTLComputePipelineState
    private let countPipeline: MTLComputePipelineState
    private let scanPipeline: MTLComputePipelineState
    private let scatterPipeline: MTLComputePipelineState

    init?(particleCapacity: Int, cellCapacity: Int) {
        guard let context = MetalEffectContext.shared,
              let clear = context.computePipeline(function: "grid_clear"),
              let count = context.computePipeline(function: "grid_count"),
              let scan = context.computePipeline(function: "grid_scan"),
              let scatter = context.computePipeline(function: "grid_scatter") else { return nil }
        let device = context.device
        let uint = MemoryLayout<UInt32>.stride
        guard let cellStart = device.makeBuffer(length: cellCapacity * uint, options: .storageModePrivate),
              let cellCounts = device.makeBuffer(length: cellCapacity * uint, options: .storageModePrivate),
              let sorted = device.makeBuffer(length: particleCapacity * uint, options: .storageModePrivate),
              let cellOf = device.makeBuffer(length: particleCapacity * uint, options: .storageModePrivate),
              let rank = device.makeBuffer(length: particleCapacity * uint, options: .storageModePrivate) else { return nil }
        self.cellStart = cellStart
        self.cellCounts = cellCounts
        self.sortedIndices = sorted
        self.cellOf = cellOf
        self.rankInCell = rank
        clearPipeline = clear
        countPipeline = count
        scanPipeline = scan
        scatterPipeline = scatter
    }

    /// Rebuilds the grid for `positions` (packed float2). Four dispatches, no CPU work per particle.
    func build(with encoder: MTLComputeCommandEncoder, positions: MTLBuffer, params: GridParams) {
        var params = params
        let cells = Int(params.dims.x * params.dims.y)
        let size = MemoryLayout<GridParams>.stride

        encoder.setBuffer(cellCounts, offset: 0, index: 0)
        encoder.setBytes(&params, length: size, index: 1)
        encoder.dispatch(clearPipeline, count: cells)

        encoder.setBuffer(positions, offset: 0, index: 0)
        encoder.setBuffer(cellCounts, offset: 0, index: 1)
        encoder.setBuffer(cellOf, offset: 0, index: 2)
        encoder.setBuffer(rankInCell, offset: 0, index: 3)
        encoder.setBytes(&params, length: size, index: 4)
        encoder.dispatch(countPipeline, count: Int(params.count))

        encoder.setBuffer(cellCounts, offset: 0, index: 0)
        encoder.setBuffer(cellStart, offset: 0, index: 1)
        encoder.setBytes(&params, length: size, index: 2)
        encoder.setComputePipelineState(scanPipeline)
        let threads = min(scanPipeline.maxTotalThreadsPerThreadgroup, 1024)
        encoder.dispatchThreadgroups(
            MTLSize(width: 1, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: threads, height: 1, depth: 1)
        )

        encoder.setBuffer(cellOf, offset: 0, index: 0)
        encoder.setBuffer(rankInCell, offset: 0, index: 1)
        encoder.setBuffer(cellStart, offset: 0, index: 2)
        encoder.setBuffer(sortedIndices, offset: 0, index: 3)
        encoder.setBytes(&params, length: size, index: 4)
        encoder.dispatch(scatterPipeline, count: Int(params.count))
    }
}
