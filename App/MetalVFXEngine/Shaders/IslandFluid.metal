//
//  IslandFluid.metal
//  controller
//
//  One signed distance field for everything that grows out of the Dynamic Island: the island pill,
//  any number of liquid shapes (rounded boxes, circles) and tapered spikes, merged with smooth
//  minimums and shaded as glossy black liquid lit by a studio environment.
//  Used by IslandFluidView and its subclasses (FerrofluidIslandView, LiquidIslandToast).
//  All coordinates are in points, top-left origin, matching UIKit window coordinates.
//

#include <metal_stdlib>
using namespace metal;

// Keep in sync with `IslandFluidUniforms` in IslandFluidView.swift.
struct IslandFluidUniforms {
    float2 viewport;    // px
    float  scale;       // px per point
    float  gloss;       // 0 = flat color, 1 = full ferrofluid reflections
    float4 island;      // x, y, width, height
    float4 color;       // straight rgb + alpha
    float4 bounds;      // minX, minY, maxX, maxY: nothing is drawn outside
    uint   shapeCount;
    uint   spikeCount;
    float  rimWidth;    // how far in from the edge the surface is curved, points
    float  time;
};

// Keep in sync with `IslandFluidShape` in IslandFluidView.swift.
struct IslandFluidShape {
    float4 box;         // center x, center y, half width, half height
    float4 params;      // corner radius, smin k with everything before it, unused, unused
};

// Keep in sync with `IslandFluidSpike` in IslandFluidView.swift.
struct IslandFluidSpike {
    float4 segment;     // base x, base y, tip x, tip y
    float4 params;      // base radius, tip radius, smin k, unused
};

struct IslandFluidOut {
    float4 position [[position]];
    float2 uv;
};

static float islandRoundedBox(float2 p, float2 halfSize, float radius) {
    float2 q = abs(p) - halfSize + radius;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

// Polynomial smooth minimum, same as the pull-to-refresh liquid.
static float islandSmin(float a, float b, float k) {
    if (k <= 0.0) {
        return min(a, b);
    }
    float h = saturate(0.5 + 0.5 * (b - a) / k);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// Cone with rounded ends from `a` (radius ra) to `b` (radius rb): Inigo Quilez's uneven capsule,
// evaluated in the segment's own frame.
static float islandSpike(float2 p, float2 a, float2 b, float ra, float rb) {
    float2 axis = b - a;
    float h = length(axis);
    if (h < 1e-3) {
        return length(p - a) - ra;
    }
    float2 dir = axis / h;
    float2 q = float2(abs(dot(p - a, float2(-dir.y, dir.x))), dot(p - a, dir));
    float slope = clamp((ra - rb) / h, -0.999, 0.999);
    float c = sqrt(1.0 - slope * slope);
    float k = dot(q, float2(-slope, c));
    if (k < 0.0) {
        return length(q) - ra;
    }
    if (k > c * h) {
        return length(q - float2(0.0, h)) - rb;
    }
    return dot(q, float2(c, slope)) - ra;
}

static float islandField(float2 p, constant IslandFluidUniforms &u,
                         constant IslandFluidShape *shapes, constant IslandFluidSpike *spikes) {
    float2 halfSize = u.island.zw * 0.5;
    float d = islandRoundedBox(p - (u.island.xy + halfSize), halfSize, halfSize.y);
    for (uint i = 0; i < u.shapeCount; ++i) {
        IslandFluidShape s = shapes[i];
        float radius = min(s.params.x, min(s.box.z, s.box.w));
        d = islandSmin(d, islandRoundedBox(p - s.box.xy, s.box.zw, radius), s.params.y);
    }
    for (uint i = 0; i < u.spikeCount; ++i) {
        IslandFluidSpike s = spikes[i];
        d = islandSmin(d, islandSpike(p, s.segment.xy, s.segment.zw, s.params.x, s.params.y), s.params.z);
    }
    return d;
}

// A photo studio around the liquid: a big softbox up-left, a strip light low-right and a dim
// ceiling. Black liquid shows nothing but these reflections, which is what sells it as wet.
static float3 islandStudio(float3 r, float time) {
    float3 key = normalize(float3(-0.45, -0.75, 0.55));
    float3 strip = normalize(float3(0.75, 0.35, 0.55));
    float keyLight = smoothstep(0.86, 0.93, dot(r, key));
    float stripLight = smoothstep(0.93, 0.97, dot(r, strip)) * 0.55;
    // A slow sweep across the ceiling keeps the highlights alive even when nothing moves.
    float3 sweepDir = normalize(float3(sin(time * 0.6) * 0.5, -0.6, 0.6));
    float sweep = smoothstep(0.96, 0.99, dot(r, sweepDir)) * 0.35;
    float ceiling = pow(saturate(-r.y * 0.5 + 0.5), 4.0) * 0.10;
    return float3(0.92, 0.96, 1.0) * (keyLight + sweep + ceiling) + float3(1.0, 0.93, 0.86) * stripLight;
}

vertex IslandFluidOut island_fluid_vertex(uint vid [[vertex_id]]) {
    float2 pos = float2((vid << 1) & 2, vid & 2);
    IslandFluidOut out;
    out.position = float4(pos * 2.0 - 1.0, 0.0, 1.0);
    out.uv = float2(pos.x, 1.0 - pos.y);
    return out;
}

fragment float4 island_fluid_fragment(IslandFluidOut in [[stage_in]],
                                      constant IslandFluidUniforms &u [[buffer(0)]],
                                      constant IslandFluidShape *shapes [[buffer(1)]],
                                      constant IslandFluidSpike *spikes [[buffer(2)]]) {
    float2 p = in.position.xy / u.scale;
    if (any(p < u.bounds.xy) || any(p > u.bounds.zw)) {
        return float4(0.0);
    }
    float d = islandField(p, u, shapes, spikes);
    float pixel = 1.0 / u.scale;
    if (d > 2.0 * pixel) {
        return float4(0.0);
    }

    // Central differences: smin bends the field, so its real gradient is needed both for the
    // normal and to turn d into a true distance for antialiasing.
    const float e = 0.35;
    float2 grad = float2(islandField(p + float2(e, 0.0), u, shapes, spikes) - islandField(p - float2(e, 0.0), u, shapes, spikes),
                         islandField(p + float2(0.0, e), u, shapes, spikes) - islandField(p - float2(0.0, e), u, shapes, spikes)) / (2.0 * e);
    float slope = max(length(grad), 0.05);
    float distance = d / slope;
    float alpha = (1.0 - smoothstep(-0.75 * pixel, 0.75 * pixel, distance)) * u.color.a;
    if (alpha <= 0.0) {
        return float4(0.0);
    }

    // Treat the shape as a liquid slab whose edge is a quarter circle `rimWidth` wide:
    // flat (facing the viewer) in the middle, vertical at the outline.
    float s = saturate(-distance / u.rimWidth);
    float height = sqrt(max(2.0 * s - s * s, 1e-4));
    float dhds = (1.0 - s) / height;
    float2 outward = grad / slope;
    float3 n = normalize(float3(outward * dhds, 1.0));
    float3 r = float3(2.0 * n.z * n.xy, 2.0 * n.z * n.z - 1.0);   // reflect(view, n), view = (0, 0, -1)
    float fresnel = 0.04 + 0.96 * pow(1.0 - n.z, 5.0);

    // No reflections on the island itself: on screen it hides under the cutout, but screen
    // recordings capture those pixels, and the real island is flat black.
    float2 islandHalf = u.island.zw * 0.5;
    float onIsland = islandRoundedBox(p - (u.island.xy + islandHalf), islandHalf, islandHalf.y);
    float gloss = u.gloss * smoothstep(-2.0, 3.0, onIsland);
    float3 color = u.color.rgb + islandStudio(r, u.time) * (0.35 + 0.65 * fresnel) * gloss;
    return float4(saturate(color) * alpha, alpha);
}

// MARK: - Liquid progress tube (IslandLiveProgress)

// Keep in sync with `IslandTubeUniforms` in IslandLiveProgress.swift.
struct IslandTubeUniforms {
    float2 viewport;    // px
    float  scale;
    float  time;
    float4 rect;        // tube: x, y, width, height, points
    float  fill;        // 0…1
    float  slosh;       // how hard the liquid is sloshing (fill velocity)
    float2 unused;
    float4 liquid;      // straight rgb + alpha
    float4 track;       // straight rgb + alpha
};

fragment float4 island_tube_fragment(IslandFluidOut in [[stage_in]],
                                     constant IslandTubeUniforms &u [[buffer(0)]]) {
    float2 p = in.position.xy / u.scale - u.rect.xy;
    float2 halfSize = u.rect.zw * 0.5;
    float d = islandRoundedBox(p - halfSize, halfSize, halfSize.y);
    float pixel = 1.0 / u.scale;
    float alpha = 1.0 - smoothstep(-0.75 * pixel, 0.75 * pixel, d);
    if (alpha <= 0.0) {
        return float4(0.0);
    }
    // The liquid front is a meniscus that ripples, harder while the level is still catching up.
    float wave = sin(p.y * 0.9 + u.time * 9.0) * (0.6 + 3.0 * min(abs(u.slosh), 1.5))
               + sin(u.time * 4.3 + p.y * 0.4) * 0.6;
    float front = u.fill * u.rect.z + wave * smoothstep(0.0, 0.05, u.fill);
    float liquid = 1.0 - smoothstep(front - 0.8, front + 0.8, p.x);
    // A highlight along the top of the tube and a darker bottom give it volume.
    float shade = mix(1.25, 0.8, p.y / u.rect.w);
    float3 liquidRGB = saturate(u.liquid.rgb * shade);
    float4 color = mix(float4(u.track.rgb * u.track.a, u.track.a), float4(liquidRGB * u.liquid.a, u.liquid.a), liquid);
    return color * alpha;
}
