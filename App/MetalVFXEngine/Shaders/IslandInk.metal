//
//  IslandInk.metal
//  controller
//
//  Ink in water, pouring out of the Dynamic Island: a 2D "stable fluids" solver (semi-Lagrangian
//  advection, vorticity confinement for the curls, Jacobi pressure projection) carrying an ink
//  density. A suction toward the island drains the ink back into it.
//  Grid coordinates are in cells, top-left origin; velocities in cells per second.
//

#include <metal_stdlib>
using namespace metal;

// Keep in sync with `InkUniforms` in InkWellOverlay.swift.
struct InkUniforms {
    float2 grid;                // cells
    float  dt;
    float  cell;                // points per cell
    float  velocityDecay;       // per second
    float  dyeDecay;            // per second
    float  vorticity;
    uint   splatCount;
    float2 sink;                // island mouth, cells
    float  suction;             // pull toward the sink, cells / s²
    float  sinkRadius;          // ink inside this radius is swallowed, cells
    float  coverThreshold;      // > 0: remember where ink has been (reveals what is underneath)
    float  time;
    float  gravity;             // ink is heavier than water: it sinks, cells / s² per unit of density
    float  unused;
};

// Keep in sync with `InkSplat` in InkWellOverlay.swift.
struct InkSplat {
    float2 position;            // cells
    float2 velocity;            // cells / s the fluid is pushed toward
    float  radius;              // cells
    float  dye;                 // ink added at the center
    float2 unused;
};

constexpr sampler inkSampler(coord::normalized, address::clamp_to_edge, filter::linear);

static float splatWeight(float2 p, InkSplat s) {
    float2 d = p - s.position;
    return exp(-dot(d, d) / max(s.radius * s.radius, 1e-3));
}

static uint2 inkClamp(int2 c, uint2 size) {
    return uint2(clamp(c, int2(0), int2(size) - 1));
}

kernel void ink_advect_velocity(texture2d<float> velocityIn [[texture(0)]],
                                texture2d<float, access::write> velocityOut [[texture(1)]],
                                texture2d<float, access::read> dye [[texture(2)]],
                                constant InkUniforms &u [[buffer(0)]],
                                constant InkSplat *splats [[buffer(1)]],
                                uint2 gid [[thread_position_in_grid]]) {
    uint2 size = uint2(u.grid);
    if (gid.x >= size.x || gid.y >= size.y) {
        return;
    }
    float2 p = float2(gid) + 0.5;
    float2 v = velocityIn.read(gid).xy;
    float2 back = (p - u.dt * v) / u.grid;
    v = velocityIn.sample(inkSampler, back, level(0.0)).xy * exp(-u.velocityDecay * u.dt);

    for (uint i = 0; i < u.splatCount; ++i) {
        v += (splats[i].velocity - v) * splatWeight(p, splats[i]);
    }
    // Heavy ink sinks and drags the water with it, which breaks it into falling fingers.
    v.y += u.gravity * min(dye.read(gid).r, 1.5) * u.dt;
    if (u.suction > 0.0) {
        float2 to = u.sink - p;
        float d = max(length(to), 1.0);
        v += to / d * u.suction * (0.4 + 25.0 / (d + 8.0)) * u.dt;
    }
    // Walls: the fluid does not flow out of the screen.
    if (gid.x == 0 || gid.y == 0 || gid.x == size.x - 1 || gid.y == size.y - 1) {
        v = float2(0.0);
    }
    velocityOut.write(float4(v, 0.0, 0.0), gid);
}

kernel void ink_curl(texture2d<float, access::read> velocity [[texture(0)]],
                     texture2d<float, access::write> curl [[texture(1)]],
                     constant InkUniforms &u [[buffer(0)]],
                     uint2 gid [[thread_position_in_grid]]) {
    uint2 size = uint2(u.grid);
    if (gid.x >= size.x || gid.y >= size.y) {
        return;
    }
    int2 c = int2(gid);
    float l = velocity.read(inkClamp(c - int2(1, 0), size)).y;
    float r = velocity.read(inkClamp(c + int2(1, 0), size)).y;
    float t = velocity.read(inkClamp(c - int2(0, 1), size)).x;
    float b = velocity.read(inkClamp(c + int2(0, 1), size)).x;
    curl.write(float4(0.5 * ((r - l) - (b - t))), gid);
}

// Vorticity confinement: pushes energy back into small eddies, which is what makes ink curl.
kernel void ink_vorticity(texture2d<float, access::read> velocityIn [[texture(0)]],
                          texture2d<float, access::read> curl [[texture(1)]],
                          texture2d<float, access::write> velocityOut [[texture(2)]],
                          constant InkUniforms &u [[buffer(0)]],
                          uint2 gid [[thread_position_in_grid]]) {
    uint2 size = uint2(u.grid);
    if (gid.x >= size.x || gid.y >= size.y) {
        return;
    }
    int2 c = int2(gid);
    float l = abs(curl.read(inkClamp(c - int2(1, 0), size)).r);
    float r = abs(curl.read(inkClamp(c + int2(1, 0), size)).r);
    float t = abs(curl.read(inkClamp(c - int2(0, 1), size)).r);
    float b = abs(curl.read(inkClamp(c + int2(0, 1), size)).r);
    float w = curl.read(gid).r;
    float2 n = float2(r - l, b - t);
    n /= length(n) + 1e-4;
    float2 force = u.vorticity * w * float2(n.y, -n.x);
    float2 v = velocityIn.read(gid).xy + force * u.dt;
    velocityOut.write(float4(v, 0.0, 0.0), gid);
}

kernel void ink_divergence(texture2d<float, access::read> velocity [[texture(0)]],
                           texture2d<float, access::write> divergence [[texture(1)]],
                           constant InkUniforms &u [[buffer(0)]],
                           uint2 gid [[thread_position_in_grid]]) {
    uint2 size = uint2(u.grid);
    if (gid.x >= size.x || gid.y >= size.y) {
        return;
    }
    int2 c = int2(gid);
    float l = velocity.read(inkClamp(c - int2(1, 0), size)).x;
    float r = velocity.read(inkClamp(c + int2(1, 0), size)).x;
    float t = velocity.read(inkClamp(c - int2(0, 1), size)).y;
    float b = velocity.read(inkClamp(c + int2(0, 1), size)).y;
    divergence.write(float4(0.5 * ((r - l) + (b - t))), gid);
}

kernel void ink_pressure(texture2d<float, access::read> pressureIn [[texture(0)]],
                         texture2d<float, access::read> divergence [[texture(1)]],
                         texture2d<float, access::write> pressureOut [[texture(2)]],
                         constant InkUniforms &u [[buffer(0)]],
                         uint2 gid [[thread_position_in_grid]]) {
    uint2 size = uint2(u.grid);
    if (gid.x >= size.x || gid.y >= size.y) {
        return;
    }
    int2 c = int2(gid);
    float l = pressureIn.read(inkClamp(c - int2(1, 0), size)).r;
    float r = pressureIn.read(inkClamp(c + int2(1, 0), size)).r;
    float t = pressureIn.read(inkClamp(c - int2(0, 1), size)).r;
    float b = pressureIn.read(inkClamp(c + int2(0, 1), size)).r;
    pressureOut.write(float4((l + r + t + b - divergence.read(gid).r) * 0.25), gid);
}

kernel void ink_project(texture2d<float, access::read> velocityIn [[texture(0)]],
                        texture2d<float, access::read> pressure [[texture(1)]],
                        texture2d<float, access::write> velocityOut [[texture(2)]],
                        constant InkUniforms &u [[buffer(0)]],
                        uint2 gid [[thread_position_in_grid]]) {
    uint2 size = uint2(u.grid);
    if (gid.x >= size.x || gid.y >= size.y) {
        return;
    }
    int2 c = int2(gid);
    float l = pressure.read(inkClamp(c - int2(1, 0), size)).r;
    float r = pressure.read(inkClamp(c + int2(1, 0), size)).r;
    float t = pressure.read(inkClamp(c - int2(0, 1), size)).r;
    float b = pressure.read(inkClamp(c + int2(0, 1), size)).r;
    float2 v = velocityIn.read(gid).xy - 0.5 * float2(r - l, b - t);
    velocityOut.write(float4(v, 0.0, 0.0), gid);
}

// Ink density in .r; .g remembers the most ink a cell has ever held (the reveal mask).
kernel void ink_advect_dye(texture2d<float> dyeIn [[texture(0)]],
                           texture2d<float, access::read> velocity [[texture(1)]],
                           texture2d<float, access::write> dyeOut [[texture(2)]],
                           constant InkUniforms &u [[buffer(0)]],
                           constant InkSplat *splats [[buffer(1)]],
                           uint2 gid [[thread_position_in_grid]]) {
    uint2 size = uint2(u.grid);
    if (gid.x >= size.x || gid.y >= size.y) {
        return;
    }
    float2 p = float2(gid) + 0.5;
    float2 back = (p - u.dt * velocity.read(gid).xy) / u.grid;
    float density = dyeIn.sample(inkSampler, back, level(0.0)).r * exp(-u.dyeDecay * u.dt);
    for (uint i = 0; i < u.splatCount; ++i) {
        density += splats[i].dye * splatWeight(p, splats[i]);
    }
    if (u.suction > 0.0) {
        float d = length(p - u.sink);
        density *= 1.0 - saturate(u.dt * 10.0 * (1.0 - smoothstep(u.sinkRadius * 0.5, u.sinkRadius, d)));
    }
    density = min(density, 3.0);
    float cover = 0.0;
    if (u.coverThreshold > 0.0) {
        cover = max(dyeIn.read(gid).g, smoothstep(u.coverThreshold * 0.4, u.coverThreshold, density));
    }
    dyeOut.write(float4(density, cover, 0.0, 0.0), gid);
}

// MARK: - Rendering

// Keep in sync with `InkRenderUniforms` in InkWellOverlay.swift.
struct InkRenderUniforms {
    float4 inkColor;        // dense ink
    float4 edgeColor;       // thin, diluted ink
    float2 texel;           // 1 / grid size
    float  fade;            // ink opacity, 1 → 0 at the end
    float  underFade;       // snapshot opacity where ink never reached
    uint   hasSnapshot;
    float  unused;
    float2 unused2;
};

struct InkOut {
    float4 position [[position]];
    float2 uv;
};

vertex InkOut ink_vertex(uint vid [[vertex_id]]) {
    float2 pos = float2((vid << 1) & 2, vid & 2);
    InkOut out;
    out.position = float4(pos * 2.0 - 1.0, 0.0, 1.0);
    out.uv = float2(pos.x, 1.0 - pos.y);
    return out;
}

fragment float4 ink_fragment(InkOut in [[stage_in]],
                             texture2d<float> dye [[texture(0)]],
                             texture2d<float> snapshot [[texture(1)]],
                             constant InkRenderUniforms &u [[buffer(0)]]) {
    float2 ink = dye.sample(inkSampler, in.uv).rg;
    float density = ink.r;
    float inkAlpha = (1.0 - exp(-density * 3.2)) * u.fade;

    // A faint wet sheen from the density slope, so the ink has body instead of being a flat stain.
    float dl = dye.sample(inkSampler, in.uv - float2(u.texel.x, 0.0)).r;
    float dr = dye.sample(inkSampler, in.uv + float2(u.texel.x, 0.0)).r;
    float dt = dye.sample(inkSampler, in.uv - float2(0.0, u.texel.y)).r;
    float db = dye.sample(inkSampler, in.uv + float2(0.0, u.texel.y)).r;
    float3 n = normalize(float3(-(dr - dl) * 2.5, -(db - dt) * 2.5, 1.0));
    float sheen = pow(saturate(dot(n, normalize(float3(-0.4, -0.6, 0.7)))), 24.0) * 0.18;

    float3 inkRGB = mix(u.edgeColor.rgb, u.inkColor.rgb, smoothstep(0.1, 1.3, density)) + sheen;

    float4 under = float4(0.0);
    if (u.hasSnapshot != 0) {
        under = snapshot.sample(inkSampler, in.uv) * (1.0 - ink.g) * u.underFade;
    }
    float3 rgb = inkRGB * inkAlpha + under.rgb * (1.0 - inkAlpha);
    float alpha = inkAlpha + under.a * (1.0 - inkAlpha);
    return float4(rgb, alpha);
}
