//
//  SpatialGrid.metal
//  demo
//
//  Uniform grid for neighbour search, rebuilt every frame with a counting sort:
//  count particles per cell, prefix-sum the counts into cell starts, scatter particle indices.
//  Neighbours of a particle are then the particles listed in the surrounding cells.
//

#include "EffectsSpatialGrid.h"

kernel void grid_clear(device uint *cellCounts [[buffer(0)]],
                       constant GridParams &grid [[buffer(1)]],
                       uint id [[thread_position_in_grid]]) {
    if (id < grid.dims.x * grid.dims.y) {
        cellCounts[id] = 0;
    }
}

kernel void grid_count(const device float2 *positions [[buffer(0)]],
                       device atomic_uint *cellCounts [[buffer(1)]],
                       device uint *cellOf [[buffer(2)]],
                       device uint *rankInCell [[buffer(3)]],
                       constant GridParams &grid [[buffer(4)]],
                       uint id [[thread_position_in_grid]]) {
    if (id >= grid.count) return;
    uint cell = gridCellIndex(gridCell(positions[id], grid), grid);
    cellOf[id] = cell;
    rankInCell[id] = atomic_fetch_add_explicit(&cellCounts[cell], 1u, memory_order_relaxed);
}

// Exclusive prefix sum of the cell counts, by a single threadgroup: each thread sums a contiguous
// chunk, the chunk totals are scanned in threadgroup memory, then each thread writes its chunk.
kernel void grid_scan(const device uint *cellCounts [[buffer(0)]],
                      device uint *cellStart [[buffer(1)]],
                      constant GridParams &grid [[buffer(2)]],
                      uint tid [[thread_index_in_threadgroup]],
                      uint threads [[threads_per_threadgroup]]) {
    threadgroup uint partial[1024];
    uint total = grid.dims.x * grid.dims.y;
    uint chunk = (total + threads - 1) / threads;
    uint begin = min(tid * chunk, total);
    uint end = min(begin + chunk, total);

    uint sum = 0;
    for (uint i = begin; i < end; i++) {
        sum += cellCounts[i];
    }
    partial[tid] = sum;
    threadgroup_barrier(mem_flags::mem_threadgroup);

    // Hillis–Steele inclusive scan over the chunk totals.
    for (uint offset = 1; offset < threads; offset <<= 1) {
        uint add = tid >= offset ? partial[tid - offset] : 0;
        threadgroup_barrier(mem_flags::mem_threadgroup);
        partial[tid] += add;
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }

    uint running = partial[tid] - sum;
    for (uint i = begin; i < end; i++) {
        cellStart[i] = running;
        running += cellCounts[i];
    }
}

kernel void grid_scatter(const device uint *cellOf [[buffer(0)]],
                         const device uint *rankInCell [[buffer(1)]],
                         const device uint *cellStart [[buffer(2)]],
                         device uint *sortedIndices [[buffer(3)]],
                         constant GridParams &grid [[buffer(4)]],
                         uint id [[thread_position_in_grid]]) {
    if (id >= grid.count) return;
    sortedIndices[cellStart[cellOf[id]] + rankInCell[id]] = id;
}
