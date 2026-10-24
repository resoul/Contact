//
//  ReactionFluid.metal
//  controller
//
//  Stable fluids for chat reactions. Coordinates and velocity use simulation cells,
//  with a top-left origin. The signed-distance field makes message bubbles actual
//  solver boundaries, including during backtracing, rather than a rendering mask.
//

#include <metal_stdlib>
using namespace metal;

// Keep these 16-byte fields in sync with MTReactionFluidView.swift.
struct ReactionUniforms {
    float4 grid;          // width, height, points per cell, dt
    float4 dynamics;      // velocity decay / s, dye decay / s, vorticity, time
    uint4 counts;         // splats, rounded obstacles, sinks, unused
    float4 appearance;   // fade, opacity, unused, unused
};

struct ReactionSplat {
    float4 positionVelocity;  // position.xy, velocity.xy
    float4 colorDensity;      // unpremultiplied RGB, amount of dye
    float4 shape;             // radius, unused, unused, unused
};

struct ReactionObstacle {
    float4 rect;          // origin.xy, size.xy
    float4 corners;       // top-left, top-right, bottom-right, bottom-left
};

struct ReactionSink {
    float4 positionRadius;   // position.xy, radius, suction acceleration
    float4 timing;           // drain progress, absorption / s, unused, unused
};

constexpr sampler reactionSampler(coord::normalized, address::clamp_to_edge, filter::linear);

static uint2 reactionClamp(int2 c, uint2 size) {
    return uint2(clamp(c, int2(0), int2(size) - 1));
}

static bool reactionInside(uint2 gid, constant ReactionUniforms &u) {
    return all(gid < uint2(u.grid.xy));
}

static float reactionDT(constant ReactionUniforms &u) {
    return clamp(u.grid.w, 0.0f, 1.0f / 30.0f);
}

static bool reactionFluid(int2 c, texture2d<float, access::read> mask, uint2 size) {
    if (any(c < int2(0)) || any(c >= int2(size))) { return false; }
    return mask.read(uint2(c)).r > 0.0f;
}

static float reactionDistance(float2 p, texture2d<float, access::read> mask, uint2 size) {
    float2 cell = p - 0.5f;
    int2 base = int2(floor(cell));
    float2 t = fract(cell);
    float a = mask.read(reactionClamp(base, size)).r;
    float b = mask.read(reactionClamp(base + int2(1, 0), size)).r;
    float c = mask.read(reactionClamp(base + int2(0, 1), size)).r;
    float d = mask.read(reactionClamp(base + int2(1, 1), size)).r;
    return mix(mix(a, b, t.x), mix(c, d, t.x), t.y);
}

// A long backtrace must not jump across even a thin bubble. Traverse in subcell
// steps and bisect the first intersection; tracing straight to a clamped endpoint
// would otherwise teleport color from the other side of the obstacle.
static float2 reactionTrace(float2 p, float2 target,
                            texture2d<float, access::read> mask, uint2 size) {
    target = clamp(target, float2(1.5f), float2(size) - 1.5f);
    float2 delta = target - p;
    uint steps = uint(clamp(ceil(length(delta) / 0.6f), 1.0f, 48.0f));
    float2 safe = p;
    for (uint i = 1; i <= steps; ++i) {
        float2 next = p + delta * (float(i) / float(steps));
        if (reactionDistance(next, mask, size) <= 0.12f) {
            float2 blocked = next;
            for (uint j = 0; j < 5; ++j) {
                float2 middle = (safe + blocked) * 0.5f;
                if (reactionDistance(middle, mask, size) > 0.12f) { safe = middle; }
                else { blocked = middle; }
            }
            return safe;
        }
        safe = next;
    }
    return safe;
}

// Bilinear interpolation renormalizes weights over fluid texels only. A hardware
// linear sampler would blend a bubble's zero texels into the surrounding flow.
static float4 reactionSample(float2 p, texture2d<float, access::read> source,
                              texture2d<float, access::read> mask, uint2 size) {
    float2 cell = p - 0.5f;
    int2 base = int2(floor(cell));
    float2 t = fract(cell);
    float4 value = float4(0.0f);
    float weight = 0.0f;
    for (uint y = 0; y < 2; ++y) {
        for (uint x = 0; x < 2; ++x) {
            int2 c = base + int2(x, y);
            if (!reactionFluid(c, mask, size)) { continue; }
            float w = (x == 0 ? 1.0f - t.x : t.x) * (y == 0 ? 1.0f - t.y : t.y);
            value += source.read(uint2(c)) * w;
            weight += w;
        }
    }
    return value / max(weight, 1e-5f);
}

static float2 reactionBoundary(float2 velocity, int2 c,
                                texture2d<float, access::read> mask, uint2 size) {
    if (!all(isfinite(velocity))) { return float2(0.0f); }
    if (!reactionFluid(c, mask, size)) { return float2(0.0f); }
    if (!reactionFluid(c - int2(1, 0), mask, size)) { velocity.x = max(0.0f, velocity.x); }
    if (!reactionFluid(c + int2(1, 0), mask, size)) { velocity.x = min(0.0f, velocity.x); }
    if (!reactionFluid(c - int2(0, 1), mask, size)) { velocity.y = max(0.0f, velocity.y); }
    if (!reactionFluid(c + int2(0, 1), mask, size)) { velocity.y = min(0.0f, velocity.y); }
    if (mask.read(uint2(c)).r < 1.6f) {
        float2 normal = float2(
            mask.read(reactionClamp(c + int2(1, 0), size)).r - mask.read(reactionClamp(c - int2(1, 0), size)).r,
            mask.read(reactionClamp(c + int2(0, 1), size)).r - mask.read(reactionClamp(c - int2(0, 1), size)).r);
        float square = dot(normal, normal);
        if (square > 1e-6f) {
            normal *= rsqrt(square);
            velocity -= normal * min(dot(velocity, normal), 0.0f);
        }
    }
    float speed = length(velocity);
    return velocity * min(1.0f, 240.0f / max(speed, 1e-5f));
}

static float reactionSplatWeight(float2 p, constant ReactionSplat &s) {
    float2 d = p - s.positionVelocity.xy;
    float radius = max(s.shape.x, 0.6f);
    return exp(-dot(d, d) / (radius * radius));
}

kernel void reaction_clear(texture2d<float, access::write> target [[texture(0)]],
                            uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= target.get_width() || gid.y >= target.get_height()) { return; }
    target.write(float4(0.0f), gid);
}

kernel void reaction_obstacles(texture2d<float, access::write> mask [[texture(0)]],
                                constant ReactionUniforms &u [[buffer(0)]],
                                constant ReactionObstacle *obstacles [[buffer(2)]],
                                uint2 gid [[thread_position_in_grid]]) {
    if (!reactionInside(gid, u)) { return; }
    float2 p = float2(gid) + 0.5f;
    float2 wall = min(p - 1.0f, u.grid.xy - 1.0f - p);
    float distance = min(wall.x, wall.y);
    for (uint i = 0; i < u.counts.y; ++i) {
        float2 halfSize = obstacles[i].rect.zw * 0.5f;
        if (any(halfSize <= 0.0f)) { continue; }
        float2 local = p - obstacles[i].rect.xy - halfSize;
        float4 radii = obstacles[i].corners;
        float radius = local.y < 0.0f
            ? (local.x < 0.0f ? radii.x : radii.y)
            : (local.x < 0.0f ? radii.w : radii.z);
        radius = clamp(radius, 0.0f, min(halfSize.x, halfSize.y));
        float2 q = abs(local) - halfSize + radius;
        float d = length(max(q, 0.0f)) + min(max(q.x, q.y), 0.0f) - radius;
        distance = min(distance, d);
    }
    mask.write(float4(distance), gid);
}

kernel void reaction_advect_velocity(texture2d<float, access::read> velocityIn [[texture(0)]],
                                      texture2d<float, access::write> velocityOut [[texture(1)]],
                                      texture2d<float, access::read> mask [[texture(2)]],
                                      constant ReactionUniforms &u [[buffer(0)]],
                                      constant ReactionSplat *splats [[buffer(1)]],
                                      uint2 gid [[thread_position_in_grid]]) {
    if (!reactionInside(gid, u)) { return; }
    uint2 size = uint2(u.grid.xy);
    int2 c = int2(gid);
    if (!reactionFluid(c, mask, size)) { velocityOut.write(float4(0.0f), gid); return; }
    float dt = reactionDT(u);
    float2 p = float2(gid) + 0.5f;
    float2 v = reactionBoundary(velocityIn.read(gid).xy, c, mask, size);
    float2 back = reactionTrace(p, p - dt * v, mask, size);
    v = reactionSample(back, velocityIn, mask, size).xy * exp(-max(u.dynamics.x, 0.0f) * dt);
    for (uint i = 0; i < u.counts.x; ++i) {
        float weight = reactionSplatWeight(p, splats[i]);
        v += (splats[i].positionVelocity.zw - v) * weight * 0.72f;
        float2 delta = p - splats[i].positionVelocity.xy;
        float rotation = splats[i].colorDensity.r >= splats[i].colorDensity.b ? 1.0f : -1.0f;
        float2 tangent = float2(-delta.y, delta.x) / max(length(delta), 0.8f);
        v += tangent * rotation * min(splats[i].shape.x * 10.0f, 65.0f)
            * weight * clamp(splats[i].colorDensity.a, 0.08f, 1.0f);
    }
    velocityOut.write(float4(reactionBoundary(v, c, mask, size), 0.0f, 0.0f), gid);
}

kernel void reaction_curl(texture2d<float, access::read> velocity [[texture(0)]],
                           texture2d<float, access::write> curl [[texture(1)]],
                           texture2d<float, access::read> mask [[texture(2)]],
                           constant ReactionUniforms &u [[buffer(0)]],
                           uint2 gid [[thread_position_in_grid]]) {
    if (!reactionInside(gid, u)) { return; }
    uint2 size = uint2(u.grid.xy);
    int2 c = int2(gid);
    if (!reactionFluid(c, mask, size)) { curl.write(float4(0.0f), gid); return; }
    float2 v = velocity.read(gid).xy;
    float l = reactionFluid(c - int2(1, 0), mask, size) ? velocity.read(uint2(c - int2(1, 0))).y : v.y;
    float r = reactionFluid(c + int2(1, 0), mask, size) ? velocity.read(uint2(c + int2(1, 0))).y : v.y;
    float t = reactionFluid(c - int2(0, 1), mask, size) ? velocity.read(uint2(c - int2(0, 1))).x : v.x;
    float b = reactionFluid(c + int2(0, 1), mask, size) ? velocity.read(uint2(c + int2(0, 1))).x : v.x;
    curl.write(float4(clamp(0.5f * (r - l - b + t), -240.0f, 240.0f)), gid);
}

kernel void reaction_vorticity(texture2d<float, access::read> velocityIn [[texture(0)]],
                                texture2d<float, access::read> curl [[texture(1)]],
                                texture2d<float, access::write> velocityOut [[texture(2)]],
                                texture2d<float, access::read> mask [[texture(3)]],
                                constant ReactionUniforms &u [[buffer(0)]],
                                uint2 gid [[thread_position_in_grid]]) {
    if (!reactionInside(gid, u)) { return; }
    uint2 size = uint2(u.grid.xy);
    int2 c = int2(gid);
    if (!reactionFluid(c, mask, size)) { velocityOut.write(float4(0.0f), gid); return; }
    float l = abs(curl.read(reactionClamp(c - int2(1, 0), size)).r);
    float r = abs(curl.read(reactionClamp(c + int2(1, 0), size)).r);
    float t = abs(curl.read(reactionClamp(c - int2(0, 1), size)).r);
    float b = abs(curl.read(reactionClamp(c + int2(0, 1), size)).r);
    float2 gradient = float2(r - l, b - t);
    float2 n = gradient / max(length(gradient), 1e-4f);
    float2 force = float2(n.y, -n.x) * curl.read(gid).r * u.dynamics.z;
    float2 v = velocityIn.read(gid).xy + force * reactionDT(u);
    velocityOut.write(float4(reactionBoundary(v, c, mask, size), 0.0f, 0.0f), gid);
}

kernel void reaction_divergence(texture2d<float, access::read> velocity [[texture(0)]],
                                 texture2d<float, access::write> divergence [[texture(1)]],
                                 texture2d<float, access::read> mask [[texture(2)]],
                                 constant ReactionUniforms &u [[buffer(0)]],
                                 uint2 gid [[thread_position_in_grid]]) {
    if (!reactionInside(gid, u)) { return; }
    uint2 size = uint2(u.grid.xy);
    int2 c = int2(gid);
    if (!reactionFluid(c, mask, size)) { divergence.write(float4(0.0f), gid); return; }
    float2 v = velocity.read(gid).xy;
    // Mirror the normal component: the average velocity at a closed face is zero.
    float l = reactionFluid(c - int2(1, 0), mask, size) ? velocity.read(uint2(c - int2(1, 0))).x : -v.x;
    float r = reactionFluid(c + int2(1, 0), mask, size) ? velocity.read(uint2(c + int2(1, 0))).x : -v.x;
    float t = reactionFluid(c - int2(0, 1), mask, size) ? velocity.read(uint2(c - int2(0, 1))).y : -v.y;
    float b = reactionFluid(c + int2(0, 1), mask, size) ? velocity.read(uint2(c + int2(0, 1))).y : -v.y;
    divergence.write(float4(0.5f * (r - l + b - t)), gid);
}

kernel void reaction_pressure(texture2d<float, access::read> pressureIn [[texture(0)]],
                               texture2d<float, access::read> divergence [[texture(1)]],
                               texture2d<float, access::write> pressureOut [[texture(2)]],
                               texture2d<float, access::read> mask [[texture(3)]],
                               constant ReactionUniforms &u [[buffer(0)]],
                               uint2 gid [[thread_position_in_grid]]) {
    if (!reactionInside(gid, u)) { return; }
    uint2 size = uint2(u.grid.xy);
    int2 c = int2(gid);
    if (!reactionFluid(c, mask, size)) { pressureOut.write(float4(0.0f), gid); return; }
    const int2 offsets[4] = {int2(-1, 0), int2(1, 0), int2(0, -1), int2(0, 1)};
    float sum = 0.0f;
    float count = 0.0f;
    for (uint i = 0; i < 4; ++i) {
        int2 neighbor = c + offsets[i];
        if (!reactionFluid(neighbor, mask, size)) { continue; }
        sum += pressureIn.read(uint2(neighbor)).r;
        count += 1.0f;
    }
    float p = count > 0.0f ? (sum - divergence.read(gid).r) / count : 0.0f;
    pressureOut.write(float4(clamp(p, -6000.0f, 6000.0f)), gid);
}

kernel void reaction_project(texture2d<float, access::read> velocityIn [[texture(0)]],
                              texture2d<float, access::read> pressure [[texture(1)]],
                              texture2d<float, access::write> velocityOut [[texture(2)]],
                              texture2d<float, access::read> mask [[texture(3)]],
                              constant ReactionUniforms &u [[buffer(0)]],
                              constant ReactionSink *sinks [[buffer(3)]],
                              uint2 gid [[thread_position_in_grid]]) {
    if (!reactionInside(gid, u)) { return; }
    uint2 size = uint2(u.grid.xy);
    int2 c = int2(gid);
    if (!reactionFluid(c, mask, size)) { velocityOut.write(float4(0.0f), gid); return; }
    float p = pressure.read(gid).r;
    float l = reactionFluid(c - int2(1, 0), mask, size) ? pressure.read(uint2(c - int2(1, 0))).r : p;
    float r = reactionFluid(c + int2(1, 0), mask, size) ? pressure.read(uint2(c + int2(1, 0))).r : p;
    float t = reactionFluid(c - int2(0, 1), mask, size) ? pressure.read(uint2(c - int2(0, 1))).r : p;
    float b = reactionFluid(c + int2(0, 1), mask, size) ? pressure.read(uint2(c + int2(0, 1))).r : p;
    float2 v = velocityIn.read(gid).xy - 0.5f * float2(r - l, b - t);
    float2 position = float2(gid) + 0.5f;
    // Absorption creates a local volume sink. Add its converging flow after the
    // incompressible projection, which would otherwise cancel a radial suction.
    for (uint i = 0; i < u.counts.z; ++i) {
        float progress = saturate(sinks[i].timing.x);
        float acceleration = max(sinks[i].positionRadius.w, 0.0f);
        if (progress <= 0.0f || acceleration <= 0.0f) { continue; }
        float2 to = sinks[i].positionRadius.xy - position;
        float distance = length(to);
        float radius = max(sinks[i].positionRadius.z, 1.0f);
        float speed = min(sqrt(2.0f * acceleration * distance), 260.0f);
        float influence = min(1.0f, radius * 5.0f / max(distance + radius, 1.0f));
        float2 pull = to / max(distance, 1.0f) * speed * influence * progress;
        v += pull;
    }
    velocityOut.write(float4(reactionBoundary(v, c, mask, size), 0.0f, 0.0f), gid);
}

kernel void reaction_advect_dye(texture2d<float, access::read> dyeIn [[texture(0)]],
                                 texture2d<float, access::read> velocity [[texture(1)]],
                                 texture2d<float, access::write> dyeOut [[texture(2)]],
                                 texture2d<float, access::read> mask [[texture(3)]],
                                 constant ReactionUniforms &u [[buffer(0)]],
                                 constant ReactionSplat *splats [[buffer(1)]],
                                 constant ReactionSink *sinks [[buffer(3)]],
                                 uint2 gid [[thread_position_in_grid]]) {
    if (!reactionInside(gid, u)) { return; }
    uint2 size = uint2(u.grid.xy);
    if (!reactionFluid(int2(gid), mask, size)) { dyeOut.write(float4(0.0f), gid); return; }
    float dt = reactionDT(u);
    float2 p = float2(gid) + 0.5f;
    float2 back = reactionTrace(p, p - dt * velocity.read(gid).xy, mask, size);
    float4 dye = reactionSample(back, dyeIn, mask, size) * exp(-max(u.dynamics.y, 0.0f) * dt);
    for (uint i = 0; i < u.counts.x; ++i) {
        float amount = max(splats[i].colorDensity.a, 0.0f) * reactionSplatWeight(p, splats[i]);
        dye += float4(saturate(splats[i].colorDensity.rgb) * amount, amount);
    }
    for (uint i = 0; i < u.counts.z; ++i) {
        float radius = max(sinks[i].positionRadius.z, 1.0f);
        float distance = length(p - sinks[i].positionRadius.xy);
        float swallow = 1.0f - smoothstep(radius * 0.35f, radius * 1.4f, distance);
        float absorption = max(sinks[i].timing.y, 0.0f) * saturate(sinks[i].timing.x);
        dye *= exp(-dt * absorption * swallow);
    }
    if (!all(isfinite(dye))) { dye = float4(0.0f); }
    dye = max(dye, 0.0f);
    // Preserve color ratios when limiting density; RGB stores color * density.
    dye *= min(1.0f, 5.0f / max(dye.a, 1e-5f));
    dye.rgb = min(dye.rgb, float3(dye.a));
    dyeOut.write(dye, gid);
}

struct ReactionVertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex ReactionVertexOut reaction_vertex(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);
    ReactionVertexOut out;
    out.position = float4(p * 2.0f - 1.0f, 0.0f, 1.0f);
    out.uv = float2(p.x, 1.0f - p.y);
    return out;
}

fragment float4 reaction_fragment(ReactionVertexOut in [[stage_in]],
                                   texture2d<float> dye [[texture(0)]],
                                   texture2d<float> mask [[texture(1)]],
                                   constant ReactionUniforms &u [[buffer(0)]]) {
    float distance = mask.sample(reactionSampler, in.uv).r;
    if (distance <= 0.0f) { return float4(0.0f); }
    float4 ink = dye.sample(reactionSampler, in.uv);
    float density = max(ink.a, 0.0f);
    if (density < 0.001f) { return float4(0.0f); }
    float2 texel = 1.0f / max(u.grid.xy, 1.0f);
    float l = dye.sample(reactionSampler, in.uv - float2(texel.x, 0.0f)).a;
    float r = dye.sample(reactionSampler, in.uv + float2(texel.x, 0.0f)).a;
    float t = dye.sample(reactionSampler, in.uv - float2(0.0f, texel.y)).a;
    float b = dye.sample(reactionSampler, in.uv + float2(0.0f, texel.y)).a;
    float3 normal = normalize(float3(-(r - l) * 1.6f, -(b - t) * 1.6f, 1.0f));
    float diffuse = 0.88f + 0.12f * saturate(dot(normal, normalize(float3(-0.4f, -0.6f, 0.8f))));
    float specular = pow(saturate(dot(normal, normalize(float3(-0.35f, -0.5f, 0.9f)))), 26.0f);
    float3 color = saturate(ink.rgb / max(density, 1e-4f));
    color = mix(color, color * 0.82f, smoothstep(0.6f, 3.5f, density));
    color = saturate(color * diffuse + specular * 0.11f);
    float alpha = (1.0f - exp(-density * 1.8f)) * saturate(u.appearance.x)
        * saturate(u.appearance.y) * smoothstep(0.0f, 0.7f, distance);
    return float4(color * alpha, alpha);
}
