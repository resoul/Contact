//
//  NBody.metal
//  demo
//
//  Direct N-body gravity: every body attracts every other body, O(n²) per step. Each threadgroup
//  walks the bodies in tiles staged in threadgroup memory, so a body position is read from device
//  memory once per tile instead of once per interaction.
//

#include <metal_stdlib>
using namespace metal;

// Mirrored by `NBodyParams` in NBodyView.swift (48 bytes).
struct NBodyParams {
    uint count;
    float deltaTime;
    float softening2;       // squared softening length, keeps close encounters finite
    float gravity;          // G × total mass
    float2 attractor;       // finger, world units
    float attractorMass;    // 0 when not touching
    float pointSize;        // pixels
    float2 viewScale;       // world → clip
    float brightness;
    uint galaxySplit;       // bodies below this index belong to the first galaxy
};

// Body: xy position, zw velocity.
kernel void nbody_step(const device float4 *bodiesIn [[buffer(0)]],
                       device float4 *bodiesOut [[buffer(1)]],
                       constant NBodyParams &p [[buffer(2)]],
                       uint id [[thread_position_in_grid]],
                       uint lid [[thread_index_in_threadgroup]],
                       uint groupSize [[threads_per_threadgroup]]) {
    threadgroup float2 tile[256];
    float4 body = id < p.count ? bodiesIn[id] : float4(0.0);
    float2 acceleration = float2(0.0);

    for (uint base = 0; base < p.count; base += groupSize) {
        uint j = base + lid;
        tile[lid] = j < p.count ? bodiesIn[j].xy : body.xy;
        threadgroup_barrier(mem_flags::mem_threadgroup);
        uint n = min(groupSize, p.count - base);
        for (uint k = 0; k < n; k++) {
            float2 d = tile[k] - body.xy;
            float inverse = rsqrt(dot(d, d) + p.softening2);
            acceleration += d * (inverse * inverse * inverse);
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    if (id >= p.count) return;

    acceleration *= p.gravity / float(p.count);
    float2 toFinger = p.attractor - body.xy;
    float inverse = rsqrt(dot(toFinger, toFinger) + p.softening2 * 4.0);
    acceleration += toFinger * (p.attractorMass * inverse * inverse * inverse);

    float2 velocity = body.zw + acceleration * p.deltaTime;
    bodiesOut[id] = float4(body.xy + velocity * p.deltaTime, velocity);
}

struct NBodyVertexOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float3 color;
};

vertex NBodyVertexOut nbody_vertex(const device float4 *bodies [[buffer(0)]],
                                   constant NBodyParams &p [[buffer(1)]],
                                   uint vid [[vertex_id]]) {
    float4 body = bodies[vid];
    float3 base = vid < p.galaxySplit ? float3(0.45, 0.65, 1.0) : float3(1.0, 0.6, 0.3);
    NBodyVertexOut out;
    out.position = float4(body.xy * p.viewScale, 0.0, 1.0);
    out.pointSize = p.pointSize;
    // Fast bodies (falling through the cores) glow white.
    out.color = mix(base, float3(1.0, 0.95, 0.9), saturate(length(body.zw) * 0.35)) * p.brightness;
    return out;
}

fragment float4 nbody_fragment(NBodyVertexOut in [[stage_in]],
                               float2 pointCoord [[point_coord]]) {
    float falloff = saturate(1.0 - length(pointCoord - 0.5) * 2.0);
    return float4(in.color * falloff * falloff, 1.0);
}
