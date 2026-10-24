//
//  IslandSand.metal
//  controller
//
//  Sand and the Dynamic Island:
//  - Vacuum: a view crumbles into grains (one per cell, colored from its snapshot) that are sucked
//    up into the island in a swirl. The view itself is drawn from the snapshot until its cells let go.
//  - Hourglass: a falling-sand cellular automaton (Margolus neighbourhood, so every 2×2 block is
//    updated by one thread with no write conflicts) fed by a stream pouring out of the island.
//  All coordinates are in points, top-left origin, matching UIKit window coordinates.
//

#include <metal_stdlib>
using namespace metal;

static float sandHash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static float2 sandToClip(float2 pt, float2 viewport, float scale) {
    float2 ndc = pt * scale / viewport * 2.0 - 1.0;
    return float2(ndc.x, -ndc.y);
}

constant float2 sandCorners[4] = { float2(0, 0), float2(1, 0), float2(0, 1), float2(1, 1) };

// =====================================================================
// MARK: - Vacuum
// =====================================================================

// Keep in sync with `SandGrain` in SandVacuumAnimator.swift.
struct SandGrain {
    float2 position;
    float2 velocity;
    float4 color;       // premultiplied
    float  release;     // seconds after the start when this grain lets go
    float  seed;
    float  alive;       // 0 once it reached the island (or was a transparent pixel)
    float  unused;
};

// Keep in sync with `SandVacuumUniforms` in SandVacuumAnimator.swift.
struct SandVacuumUniforms {
    float2 viewport;        // px
    float  scale;
    float  time;            // seconds since the start
    float4 element;         // x, y, width, height
    float4 island;          // x, y, width, height
    float  grain;           // grain size, points
    uint   columns;
    uint   rows;
    float  releaseWindow;   // seconds over which the whole element crumbles
    float  suction;         // pull toward the island, points / s²
    float  swirl;           // sideways pull far from the island, points / s²
    float  dt;
    float  fade;            // 1 → 0 at the very end, for stragglers
};

static float2 vacuumMouth(constant SandVacuumUniforms &u) {
    return float2(u.island.x + u.island.z * 0.5, u.island.y + u.island.w * 0.6);
}

// Cells nearest the island let go first, with a ragged, grainy front.
static float vacuumRelease(uint2 cell, constant SandVacuumUniforms &u) {
    float2 mouth = vacuumMouth(u);
    float2 p = u.element.xy + (float2(cell) + 0.5) * u.grain;
    float2 nearest = clamp(mouth, u.element.xy, u.element.xy + u.element.zw);
    float near = length(nearest - mouth);
    float far = 0.0;
    for (int i = 0; i < 4; ++i) {
        far = max(far, length(u.element.xy + sandCorners[i] * u.element.zw - mouth));
    }
    float t = saturate((length(p - mouth) - near) / max(far - near, 1.0));
    return (t * 0.7 + sandHash(float2(cell) * 1.37) * 0.3) * u.releaseWindow;
}

constexpr sampler sandSampler(coord::normalized, address::clamp_to_edge, filter::linear);

kernel void sand_vacuum_spawn(device SandGrain *grains [[buffer(0)]],
                              constant SandVacuumUniforms &u [[buffer(1)]],
                              texture2d<float> snapshot [[texture(0)]],
                              uint id [[thread_position_in_grid]]) {
    if (id >= u.columns * u.rows) {
        return;
    }
    uint2 cell = uint2(id % u.columns, id / u.columns);
    float2 uv = (float2(cell) + 0.5) * u.grain / u.element.zw;
    SandGrain g;
    g.position = u.element.xy + (float2(cell) + 0.5) * u.grain;
    g.velocity = float2(0.0);
    g.color = snapshot.sample(sandSampler, uv, level(0.0));
    g.release = vacuumRelease(cell, u);
    g.seed = sandHash(float2(cell) + 17.0);
    g.alive = g.color.a > 0.02 ? 1.0 : 0.0;
    g.unused = 0.0;
    grains[id] = g;
}

kernel void sand_vacuum_update(device SandGrain *grains [[buffer(0)]],
                               constant SandVacuumUniforms &u [[buffer(1)]],
                               uint id [[thread_position_in_grid]]) {
    if (id >= u.columns * u.rows) {
        return;
    }
    SandGrain g = grains[id];
    if (g.alive == 0.0 || u.time < g.release) {
        return;
    }
    if (all(g.velocity == 0.0)) {
        // The moment it lets go: a little hop, as if the grain was knocked loose.
        g.velocity = float2((g.seed - 0.5) * 160.0, -40.0 - g.seed * 90.0);
    }
    float2 to = vacuumMouth(u) - g.position;
    float dist = max(length(to), 1.0);
    float2 dir = to / dist;
    float2 tangent = float2(-dir.y, dir.x);
    // Suction gets much stronger close to the island; the swirl only acts far away, so grains
    // spiral in instead of orbiting forever.
    float2 accel = dir * u.suction * (0.35 + 90.0 / (dist + 25.0))
                 + tangent * u.swirl * smoothstep(30.0, 220.0, dist) * (0.6 + 0.8 * g.seed);
    g.velocity += accel * u.dt;
    // Extra drag close to the island so grains slow down and go in instead of shooting past.
    float drag = 1.6 + 7.0 * (1.0 - smoothstep(10.0, 140.0, dist));
    g.velocity *= max(1.0 - drag * u.dt, 0.0);
    g.position += g.velocity * u.dt;

    float2 islandCenter = u.island.xy + u.island.zw * 0.5;
    float2 inside = abs(g.position - islandCenter) - u.island.zw * float2(0.5, 0.5);
    if (all(inside < 0.0) || g.position.y < u.island.y + u.island.w * 0.5) {
        g.alive = 0.0;
    }
    grains[id] = g;
}

struct SandGrainOut {
    float4 position [[position]];
    float2 local;
    float4 color;
};

vertex SandGrainOut sand_grain_vertex(uint vid [[vertex_id]],
                                      uint iid [[instance_id]],
                                      const device SandGrain *grains [[buffer(0)]],
                                      constant SandVacuumUniforms &u [[buffer(1)]]) {
    SandGrain g = grains[iid];
    SandGrainOut out;
    out.local = sandCorners[vid] * 2.0 - 1.0;
    if (g.alive == 0.0 || u.time < g.release) {
        out.position = float4(-2.0, -2.0, 0.0, 1.0);
        out.color = float4(0.0);
        return out;
    }
    float dist = length(vacuumMouth(u) - g.position);
    // Grains shrink and blacken as they disappear into the island.
    float near = 1.0 - smoothstep(15.0, 170.0, dist);
    float size = u.grain * mix(1.25, 0.45, near);
    float2 pt = g.position + out.local * size * 0.5;
    out.position = float4(sandToClip(pt, u.viewport, u.scale), 0.0, 1.0);
    out.color = float4(g.color.rgb * (1.0 - 0.85 * near), g.color.a) * u.fade;
    return out;
}

fragment float4 sand_grain_fragment(SandGrainOut in [[stage_in]]) {
    float mask = 1.0 - smoothstep(0.55, 1.0, length(in.local));
    return in.color * mask;
}

struct SandElementOut {
    float4 position [[position]];
    float2 uv;
};

// The part of the element that has not crumbled yet, drawn straight from the snapshot.
vertex SandElementOut sand_element_vertex(uint vid [[vertex_id]],
                                          constant SandVacuumUniforms &u [[buffer(0)]]) {
    SandElementOut out;
    out.uv = sandCorners[vid];
    float2 pt = u.element.xy + out.uv * u.element.zw;
    out.position = float4(sandToClip(pt, u.viewport, u.scale), 0.0, 1.0);
    return out;
}

fragment float4 sand_element_fragment(SandElementOut in [[stage_in]],
                                      texture2d<float> snapshot [[texture(0)]],
                                      constant SandVacuumUniforms &u [[buffer(0)]]) {
    uint2 cell = uint2(in.uv * u.element.zw / u.grain);
    if (cell.x >= u.columns || cell.y >= u.rows || u.time >= vacuumRelease(cell, u)) {
        return float4(0.0);
    }
    return snapshot.sample(sandSampler, in.uv, level(0.0));
}

// =====================================================================
// MARK: - Hourglass
// =====================================================================

// Keep in sync with `HourglassUniforms` in SandHourglassView.swift.
struct HourglassUniforms {
    float2 viewport;    // px
    float  scale;
    float  dissolve;    // 0…1: grains vanish at random when the loading is done
    float4 rect;        // simulated area: x, y, width, height, points
    float  cell;        // cell size, points
    uint   columns;
    uint   rows;
    uint   step;        // simulation step counter: Margolus offset and randomness
    float  emitColumn;  // stream center, in cells
    float  emitWidth;   // stream width, in cells
    float  emitRate;    // chance per stream cell per step to spawn a grain
    float  unused;
    float4 sandDark;
    float4 sandLight;
};

// Cell values: 0 = empty, 1…255 = a grain (the value picks its shade). Outside the grid = wall.
constant int sandWall = -1;

static int sandRead(texture2d<uint, access::read> grid, int2 c, constant HourglassUniforms &u) {
    if (c.x < 0 || c.y < 0 || c.x >= int(u.columns) || c.y >= int(u.rows)) {
        return sandWall;
    }
    return int(grid.read(uint2(c)).r);
}

kernel void sand_hourglass_step(texture2d<uint, access::read> src [[texture(0)]],
                                texture2d<uint, access::write> dst [[texture(1)]],
                                constant HourglassUniforms &u [[buffer(0)]],
                                device atomic_uint *emitted [[buffer(1)]],
                                uint2 gid [[thread_position_in_grid]]) {
    int offset = int(u.step & 1u);
    int2 origin = int2(gid) * 2 - offset;
    int2 cells[4] = { origin, origin + int2(1, 0), origin + int2(0, 1), origin + int2(1, 1) };
    int v[4];
    for (int i = 0; i < 4; ++i) {
        v[i] = sandRead(src, cells[i], u);
    }
    float rnd = sandHash(float2(origin) + float(u.step % 977u) * float2(3.17, 1.93));

    // The stream: new grains appear in the top row under the island.
    for (int i = 0; i < 4; ++i) {
        int2 c = cells[i];
        if (c.y == 0 && v[i] == 0 && abs(float(c.x) + 0.5 - u.emitColumn) < u.emitWidth * 0.5) {
            float chance = sandHash(float2(c) + float(u.step % 613u) * 7.1);
            if (chance < u.emitRate) {
                v[i] = 1 + int(sandHash(float2(c) * 3.3 + float(u.step % 331u)) * 254.0);
                atomic_fetch_add_explicit(emitted, 1u, memory_order_relaxed);
            }
        }
    }

    // 0 1     Falling first, then sliding diagonally into an empty lower cell. Randomly mirrored
    // 2 3     so piles grow symmetrically; sometimes sliding is skipped, which steepens the heap.
    bool mirror = rnd < 0.5;
    int a = mirror ? 1 : 0, b = mirror ? 0 : 1, c = mirror ? 3 : 2, d = mirror ? 2 : 3;
    if (v[a] > 0 && v[c] == 0) { v[c] = v[a]; v[a] = 0; }
    if (v[b] > 0 && v[d] == 0) { v[d] = v[b]; v[b] = 0; }
    bool slide = fract(rnd * 7.31) < 0.9;
    if (slide && v[a] > 0 && v[c] != 0 && v[d] == 0) { v[d] = v[a]; v[a] = 0; }
    else if (slide && v[b] > 0 && v[d] != 0 && v[c] == 0) { v[c] = v[b]; v[b] = 0; }

    for (int i = 0; i < 4; ++i) {
        int2 cc = cells[i];
        if (cc.x >= 0 && cc.y >= 0 && cc.x < int(u.columns) && cc.y < int(u.rows)) {
            dst.write(uint4(uint(max(v[i], 0))), uint2(cc));
        }
    }
}

struct HourglassOut {
    float4 position [[position]];
    float2 uv;
};

vertex HourglassOut sand_hourglass_vertex(uint vid [[vertex_id]],
                                          constant HourglassUniforms &u [[buffer(0)]]) {
    HourglassOut out;
    out.uv = sandCorners[vid];
    float2 pt = u.rect.xy + out.uv * u.rect.zw;
    out.position = float4(sandToClip(pt, u.viewport, u.scale), 0.0, 1.0);
    return out;
}

fragment float4 sand_hourglass_fragment(HourglassOut in [[stage_in]],
                                        texture2d<uint, access::read> grid [[texture(0)]],
                                        constant HourglassUniforms &u [[buffer(0)]]) {
    float2 local = in.uv * u.rect.zw / u.cell;
    int2 cell = int2(local);
    int value = sandRead(grid, cell, u);
    if (value <= 0) {
        return float4(0.0);
    }
    float noise = sandHash(float2(cell) * 0.91);
    if (noise < u.dissolve) {
        return float4(0.0);
    }
    float shade = float(value) / 255.0;
    float3 color = mix(u.sandDark.rgb, u.sandLight.rgb, shade);
    // Grains on the surface of the heap catch the light.
    if (sandRead(grid, cell - int2(0, 1), u) == 0) {
        color *= 1.18;
    }
    // A hint of a round grain inside every cell.
    float2 f = fract(local) - 0.5;
    color *= 1.0 - 0.3 * smoothstep(0.25, 0.7, length(f));
    // Grains about to vanish glow briefly.
    float glow = u.dissolve > 0.0 ? smoothstep(0.12, 0.0, noise - u.dissolve) : 0.0;
    color = mix(color, float3(1.0, 0.95, 0.8), glow * 0.8);
    return float4(saturate(color), 1.0);
}
