//
//  BlackHoleWarp.metal
//  controller
//
//  Gravity well at the Dynamic Island: a snapshot of a UI element is pulled in, swirled
//  (vortex warp), stretched toward the core (spaghettification) and burnt to #000000 as it
//  reaches the island. Coordinates are window points, top-left origin.
//

#include <metal_stdlib>
using namespace metal;

// Keep in sync with `BlackHoleUniforms` in GravityBlackHoleAnimator.swift.
struct BlackHoleUniforms {
    float2 viewport;        // px
    float  scale;           // px per point
    float  progress;        // 0 → 1
    float4 element;         // snapshot frame: x, y, width, height
    float4 island;          // x, y, width, height
    float  swallowRadius;   // farthest element point from the hole, points
    float  spin;            // swirl at the core, radians
    float  core;            // size of the gravity core, points
    float  unused;
};

struct BlackHoleOut {
    float4 position [[position]];
    float2 uv;
};

constexpr sampler blackHoleSampler(coord::normalized, address::clamp_to_zero, filter::linear);

static float sdIslandBox(float2 p, float2 halfSize) {
    float r = halfSize.y;
    float2 q = abs(p) - halfSize + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

static float2 rotate2(float2 v, float a) {
    float s = sin(a), c = cos(a);
    return float2(c * v.x - s * v.y, s * v.x + c * v.y);
}

vertex BlackHoleOut black_hole_vertex(uint vid [[vertex_id]]) {
    float2 pos = float2((vid << 1) & 2, vid & 2);
    BlackHoleOut out;
    out.position = float4(pos * 2.0 - 1.0, 0.0, 1.0);
    out.uv = float2(pos.x, 1.0 - pos.y);
    return out;
}

fragment float4 black_hole_fragment(BlackHoleOut in [[stage_in]],
                                    texture2d<float> element [[texture(0)]],
                                    constant BlackHoleUniforms &u [[buffer(0)]]) {
    float2 P = in.uv * u.viewport / u.scale;
    float2 islandHalf = u.island.zw * 0.5;
    float2 hole = u.island.xy + islandHalf;
    float2 D = P - hole;
    float rd = length(D);
    float2 dir = rd > 1e-3 ? D / rd : float2(0.0, 1.0);

    float p = u.progress;
    float e = p * p;                       // the pull accelerates
    float c = u.core;
    float a = e * (u.swallowRadius + c);   // everything drifts inward; at p = 1 nothing is left outside
    float b = e * 4.0 * c;                 // extra pull close to the core

    // Forward map (source radius → screen radius): r' = r − a − b·c² / (r + c)².
    // Its slope is > 1, so it never folds, and the part of an element nearest the core is pulled
    // much harder than its far side: it stretches radially (spaghettification).
    // Each pixel inverts the map with a few Newton steps.
    float r = rd + a + b;
    for (int i = 0; i < 8; ++i) {
        float rc = r + c;
        float g = c * c / (rc * rc);
        float f = r - a - b * g - rd;
        float df = 1.0 + 2.0 * b * g / rc;
        r -= f / df;
    }

    // Vortex: only points near the core spin; far ones barely turn, so the element spirals in
    // instead of swinging around the island.
    float closeness = c / (r + c);
    float theta = u.spin * p * closeness * closeness;
    float2 source = hole + rotate2(dir, -theta) * r;
    float2 uv = (source - u.element.xy) / u.element.zw;
    if (any(uv < 0.0) || any(uv > 1.0)) {
        return float4(0.0);
    }
    float4 color = element.sample(blackHoleSampler, uv);   // premultiplied

    // Light dies near the event horizon: fade to pure black approaching the island.
    float toIsland = sdIslandBox(D, islandHalf);
    float darkness = (1.0 - smoothstep(0.0, 40.0 + 120.0 * p, toIsland)) * smoothstep(0.0, 0.15, p);
    darkness = max(darkness, smoothstep(0.75, 1.0, p));
    color.rgb *= 1.0 - darkness;
    return color;
}
