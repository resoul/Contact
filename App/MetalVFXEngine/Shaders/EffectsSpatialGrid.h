//
//  SpatialGrid.h
//  demo
//
//  Grid parameters and lookup helpers shared by the grid builder and the kernels that query it.
//

#pragma once

#include <metal_stdlib>
using namespace metal;

// Mirrored by `GridParams` in SpatialGrid.swift (32 bytes).
struct GridParams {
    float2 origin;      // world position of cell (0, 0)
    float cellSize;     // world units, at least the interaction radius
    uint2 dims;         // cells in x and y
    uint count;         // particles
};

static inline int2 gridCell(float2 position, constant GridParams &grid) {
    int2 cell = int2(floor((position - grid.origin) / grid.cellSize));
    return clamp(cell, int2(0), int2(grid.dims) - 1);
}

static inline uint gridCellIndex(int2 cell, constant GridParams &grid) {
    return uint(cell.y) * grid.dims.x + uint(cell.x);
}

// Read-only view of a built grid, for neighbour loops:
//   for each of the 3×3 cells around gridCell(p): for k in [start, start + count): j = sorted[k]
struct GridLookup {
    const device uint *cellStart;
    const device uint *cellCounts;
    const device uint *sorted;
};
