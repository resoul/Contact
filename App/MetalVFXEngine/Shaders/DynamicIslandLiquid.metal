//
//  DynamicIslandLiquid.metal
//  controller
//
//  Dynamic Island pull-to-refresh: a liquid drop stretches out of the island (SDF metaballs),
//  tears off, falls (squashed by the vertex shader) and splashes into GPU-simulated particles.
//  All coordinates are in points, top-left origin, matching UIKit window coordinates.
//

#include <metal_stdlib>
using namespace metal;

// MARK: - Shared helpers

static float2 pointsToClip(float2 pt, float2 viewport, float scale) {
    float2 ndc = pt * scale / viewport * 2.0 - 1.0;
    return float2(ndc.x, -ndc.y);
}

static float sdRoundedBox(float2 p, float2 halfSize, float radius) {
    float2 q = abs(p) - halfSize + radius;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

// Polynomial smooth minimum: merges two distance fields within `k` points,
// which is what turns two separate shapes into one viscous blob with a neck.
static float smin(float a, float b, float k) {
    if (k <= 0.0) {
        return min(a, b);
    }
    float h = saturate(0.5 + 0.5 * (b - a) / k);
    return mix(b, a, h) - k * h * (1.0 - h);
}

static float hash11(uint n) {
    n = (n << 13U) ^ n;
    n = n * (n * n * 15731U + 789221U) + 1376312589U;
    return float(n & 0x7fffffffU) / float(0x7fffffff);
}

constant float2 liquidQuadCorners[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };

// MARK: - Phase 1: island + stretching drop (SDF metaballs)

// Keep in sync with `LiquidUniforms` in DynamicIslandRefreshControl.swift.
struct LiquidUniforms {
    float2 viewport;   // px
    float  scale;      // px per point
    float  time;
    float4 island;     // x, y, width, height
    float4 drop;       // center x, center y, radius (0 = none), smin k
    float4 bump;       // center x, center y, radius (0 = none), smin k — recoil after the tear
    float4 color;
};

struct LiquidOut {
    float4 position [[position]];
    float2 uv;
};

vertex LiquidOut island_liquid_vertex(uint vid [[vertex_id]]) {
    float2 pos = float2((vid << 1) & 2, vid & 2);
    LiquidOut out;
    out.position = float4(pos * 2.0 - 1.0, 0.0, 1.0);
    out.uv = float2(pos.x, 1.0 - pos.y);
    return out;
}

fragment float4 island_liquid_fragment(LiquidOut in [[stage_in]],
                                       constant LiquidUniforms &u [[buffer(0)]]) {
    float2 p = in.uv * u.viewport / u.scale;
    float2 halfSize = u.island.zw * 0.5;
    float d = sdRoundedBox(p - (u.island.xy + halfSize), halfSize, halfSize.y);
    if (u.drop.z > 0.0) {
        d = smin(d, length(p - u.drop.xy) - u.drop.z, u.drop.w);
    }
    if (u.bump.z > 0.0) {
        d = smin(d, length(p - u.bump.xy) - u.bump.z, u.bump.w);
    }
    // Antialias over one screen pixel. smin bends the distance field (gradient < 1 in the neck),
    // so a fixed width in points would blur it; fwidth measures the real per-pixel change.
    float aa = max(fwidth(d), 1e-4) * 0.75;
    float alpha = (1.0 - smoothstep(-aa, aa, d)) * u.color.a;
    return float4(u.color.rgb * alpha, alpha);
}

// MARK: - Phase 2: free fall, flattened by air resistance in the vertex shader

// Keep in sync with `DropUniforms` in DynamicIslandRefreshControl.swift.
struct DropUniforms {
    float2 viewport;
    float  scale;
    float  squash;     // 0…~0.3, grows with fall speed
    float4 drop;       // center x, center y, radius, unused
    float4 color;
};

struct DropOut {
    float4 position [[position]];
    float2 local;      // unit-circle space, before squashing
};

vertex DropOut falling_drop_vertex(uint vid [[vertex_id]],
                                   constant DropUniforms &u [[buffer(0)]]) {
    // Flatten along Y and widen along X (volume roughly preserved).
    float2 squash = float2(1.0 + u.squash * 0.6, 1.0 - u.squash);
    float2 corner = liquidQuadCorners[vid] * 1.15;   // padding for antialiasing
    float2 pt = u.drop.xy + corner * u.drop.z * squash;
    DropOut out;
    out.position = float4(pointsToClip(pt, u.viewport, u.scale), 0.0, 1.0);
    out.local = corner;
    return out;
}

fragment float4 falling_drop_fragment(DropOut in [[stage_in]],
                                      constant DropUniforms &u [[buffer(0)]]) {
    float d = length(in.local) - 1.0;
    float aa = fwidth(d);
    float alpha = (1.0 - smoothstep(-aa, aa, d)) * u.color.a;
    return float4(u.color.rgb * alpha, alpha);
}

// MARK: - Phase 3: splash (GPU particle system)

// Keep in sync with `SplashParticle` in DynamicIslandRefreshControl.swift.
struct SplashParticle {
    float2 position;
    float2 velocity;
    float  life;       // seconds left
    float  maxLife;
    float  radius;
    float  seed;
};

struct SplashSpawn {
    float2 origin;
    float  seed;
    uint   count;
};

struct SplashStep {
    float dt;
    float gravity;     // points / s²
    float floorY;
    float drag;
    uint  count;
};

kernel void splash_spawn(device SplashParticle *particles [[buffer(0)]],
                         constant SplashSpawn &s [[buffer(1)]],
                         uint id [[thread_position_in_grid]]) {
    if (id >= s.count) {
        return;
    }
    uint base = id * 5U + uint(s.seed * 1000.0);
    float h1 = hash11(base), h2 = hash11(base + 1U), h3 = hash11(base + 2U);
    float h4 = hash11(base + 3U), h5 = hash11(base + 4U);

    // Impulse: an upward fan (UIKit y grows downward), most droplets slow, a few fast.
    float angle = mix(-M_PI_F + 0.25, -0.25, h1);
    float speed = mix(90.0, 600.0, pow(h2, 1.7));

    SplashParticle p;
    p.position = s.origin + float2((h5 - 0.5) * 14.0, -1.0);
    p.velocity = float2(cos(angle), sin(angle)) * speed;
    p.maxLife = mix(0.45, 1.1, h3);
    p.life = p.maxLife;
    p.radius = mix(1.0, 4.2, h4 * h4);
    p.seed = h5;
    particles[id] = p;
}

kernel void splash_update(device SplashParticle *particles [[buffer(0)]],
                          constant SplashStep &s [[buffer(1)]],
                          uint id [[thread_position_in_grid]]) {
    if (id >= s.count) {
        return;
    }
    SplashParticle p = particles[id];
    if (p.life <= 0.0) {
        return;
    }
    p.velocity.y += s.gravity * s.dt;
    p.velocity *= max(1.0 - s.drag * s.dt, 0.0);
    p.position += p.velocity * s.dt;
    // Droplets that hit the floor bounce once or twice and spread out.
    if (p.position.y > s.floorY - p.radius) {
        p.position.y = s.floorY - p.radius;
        p.velocity.y *= -0.35;
        p.velocity.x *= 0.7;
    }
    p.life -= s.dt;
    particles[id] = p;
}

struct SplashUniforms {
    float2 viewport;
    float  scale;
    float  unused;
    float4 color;
};

struct SplashOut {
    float4 position [[position]];
    float2 local;
    float  alpha;
};

vertex SplashOut splash_particle_vertex(uint vid [[vertex_id]],
                                        uint iid [[instance_id]],
                                        const device SplashParticle *particles [[buffer(0)]],
                                        constant SplashUniforms &u [[buffer(1)]]) {
    SplashParticle p = particles[iid];
    float alpha = p.life > 0.0 ? saturate(p.life / p.maxLife) : 0.0;
    float radius = p.radius * (0.35 + 0.65 * alpha);

    // Stretch each droplet along its velocity: a cheap motion streak.
    float speed = length(p.velocity);
    float2 dir = speed > 1.0 ? p.velocity / speed : float2(0.0, 1.0);
    float2 side = float2(-dir.y, dir.x);
    float stretch = 1.0 + min(speed / 900.0, 1.2);
    float2 corner = liquidQuadCorners[vid] * 1.2;
    float2 pt = p.position + (dir * corner.y * stretch + side * corner.x) * radius;

    SplashOut out;
    out.position = float4(pointsToClip(pt, u.viewport, u.scale), 0.0, 1.0);
    out.local = corner;
    out.alpha = alpha;
    return out;
}

fragment float4 splash_particle_fragment(SplashOut in [[stage_in]],
                                         constant SplashUniforms &u [[buffer(1)]]) {
    float d = length(in.local) - 1.0;
    float aa = fwidth(d);
    float alpha = (1.0 - smoothstep(-aa, aa, d)) * in.alpha * u.color.a;
    return float4(u.color.rgb * alpha, alpha);
}
