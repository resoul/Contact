//
//  Boids.metal
//  demo
//
//  Reynolds boids: separation, alignment and cohesion with the neighbours found through the
//  spatial grid, plus wall avoidance and fleeing from the finger.
//  Perception radius = 1 world unit = grid cell size.
//

#include "EffectsCommon.h"
#include "EffectsSpatialGrid.h"

// Mirrored by `BoidParams` in BoidsView.swift (56 bytes).
struct BoidParams {
    float2 domain;
    float2 finger;
    float fingerStrength;   // 0 when not touching
    float deltaTime;
    float minSpeed;
    float maxSpeed;
    uint count;
    uint flocking;          // 0 = independent particles
    float time;
    float boidSize;         // world units
    uint maxNeighbors;
};

kernel void boids_update(device const float2 *positionsIn [[buffer(0)]],
                         device const float2 *velocitiesIn [[buffer(1)]],
                         device const uint *cellStart [[buffer(2)]],
                         device const uint *cellCounts [[buffer(3)]],
                         device const uint *sorted [[buffer(4)]],
                         constant GridParams &grid [[buffer(5)]],
                         constant BoidParams &p [[buffer(6)]],
                         device float2 *positionsOut [[buffer(7)]],
                         device float2 *velocitiesOut [[buffer(8)]],
                         uint id [[thread_position_in_grid]]) {
    if (id >= p.count) return;
    float2 position = positionsIn[id];
    float2 velocity = velocitiesIn[id];
    float2 steer = float2(0.0);

    if (p.flocking != 0) {
        float2 separation = float2(0.0);
        float2 alignment = float2(0.0);
        float2 center = float2(0.0);
        uint neighbours = 0;
        int2 cell = gridCell(position, grid);
        for (int dy = -1; dy <= 1 && neighbours < p.maxNeighbors; dy++) {
            for (int dx = -1; dx <= 1 && neighbours < p.maxNeighbors; dx++) {
                int2 c = cell + int2(dx, dy);
                if (any(c < 0) || any(c >= int2(grid.dims))) continue;
                uint index = gridCellIndex(c, grid);
                uint end = cellStart[index] + cellCounts[index];
                for (uint k = cellStart[index]; k < end && neighbours < p.maxNeighbors; k++) {
                    uint j = sorted[k];
                    if (j == id) continue;
                    float2 d = positionsIn[j] - position;
                    float r2 = dot(d, d);
                    if (r2 >= 1.0) continue;
                    neighbours++;
                    alignment += velocitiesIn[j];
                    center += positionsIn[j];
                    if (r2 < 0.12) {
                        separation -= d / max(r2, 0.01);
                    }
                }
            }
        }
        if (neighbours > 0) {
            float n = float(neighbours);
            steer += separation * 0.35;
            steer += (alignment / n - velocity) * 1.2;
            steer += (center / n - position) * 1.0;
        }
    }

    // Wander: a slowly turning random heading per fish.
    float seed = hash21(float2(id % 4096, id / 4096));
    float angle = seed * 6.2831 + p.time * (0.4 + seed);
    steer += float2(cos(angle), sin(angle)) * (p.flocking != 0 ? 0.6 : 2.0);

    // Turn away from the walls.
    const float margin = 3.0;
    float2 low = saturate((margin - position) / margin);
    float2 high = saturate((position - (p.domain - margin)) / margin);
    steer += (low - high) * 12.0;

    // Flee the finger.
    if (p.fingerStrength > 0.0) {
        float2 away = position - p.finger;
        float distance = length(away) + 1e-3;
        float radius = 10.0;
        steer += away / distance * saturate(1.0 - distance / radius) * 60.0 * p.fingerStrength;
    }

    velocity += steer * p.deltaTime * 3.0;
    float speed = length(velocity);
    velocity *= clamp(speed, p.minSpeed, p.maxSpeed) / max(speed, 1e-4);
    position = clamp(position + velocity * p.deltaTime, float2(0.1), p.domain - 0.1);

    positionsOut[id] = position;
    velocitiesOut[id] = velocity;


}

struct BoidVertexOut {
    float4 position [[position]];
    float3 color;
};

// One triangle per fish, pointing along its velocity.
vertex BoidVertexOut boids_vertex(device const float2 *positions [[buffer(0)]],
                                  device const float2 *velocities [[buffer(1)]],
                                  constant BoidParams &p [[buffer(2)]],
                                  uint vid [[vertex_id]],
                                  uint iid [[instance_id]]) {
    float2 velocity = velocities[iid];
    float2 forward = velocity / max(length(velocity), 1e-4);
    float2 side = float2(-forward.y, forward.x);
    const float2 shape[3] = { float2(1.0, 0.0), float2(-0.7, 0.45), float2(-0.7, -0.45) };
    float2 local = shape[vid] * p.boidSize;
    float2 world = positions[iid] + forward * local.x + side * local.y;
    float2 clip = world / p.domain * 2.0 - 1.0;

    // Color by heading, so schools of fish swimming together share a color.
    float heading = atan2(forward.y, forward.x) / 6.2831 + 0.5;
    float3 color = 0.55 + 0.45 * cos(6.2831 * (heading + float3(0.0, 0.33, 0.67)));

    BoidVertexOut out;
    out.position = float4(clip.x, -clip.y, 0.0, 1.0);
    out.color = color * (vid == 0 ? 1.0 : 0.65);
    return out;
}

fragment float4 boids_fragment(BoidVertexOut in [[stage_in]]) {
    return float4(in.color, 1.0);
}
