//
//  IslandConfetti.metal
//  controller
//
//  A celebration spat out of the Dynamic Island: confetti that tumbles and flutters down, and sparks
//  that glow brighter than white. The target is extended-range (rgba16Float, extended linear sRGB),
//  so spark values above 1.0 light up past SDR white on HDR displays.
//  Spark cores are added on top of a partly covering halo (premultiplied "over" with low alpha).
//

#include <metal_stdlib>
using namespace metal;

// Keep in sync with `ConfettiParticle` in IslandConfetti.swift.
struct ConfettiParticle {
    float4 motion;      // position xy, velocity zw (points, points / s)
    float4 color;       // linear rgb
    float4 spin;        // angle, angular speed, life left, max life
    float4 shape;       // size, kind (0 confetti, 1 spark), seed, unused
};

// Keep in sync with `ConfettiStep` in IslandConfetti.swift.
struct ConfettiStep {
    float2 origin;
    float  dt;
    float  time;
    uint   count;
    float  gravity;
    float  seed;
    float  sparkShare;  // 0…1 of the particles that are sparks rather than paper
    float4 sparkColor;  // srgb
    float  direction;   // center of the fan, radians (screen space, y down)
    float  spread;      // width of the fan, radians
    float  speedScale;
    float  unused;
};

// Keep in sync with `ConfettiRender` in IslandConfetti.swift.
struct ConfettiRender {
    float2 viewport;    // px
    float  scale;
    float  sparkBoost;  // how far past white the sparks go
};

static float confettiHash(uint n) {
    n = (n << 13U) ^ n;
    n = n * (n * n * 15731U + 789221U) + 1376312589U;
    return float(n & 0x7fffffffU) / float(0x7fffffff);
}

constant float3 confettiPalette[6] = {
    float3(1.00, 0.24, 0.47), float3(1.00, 0.80, 0.18), float3(0.22, 0.85, 0.95),
    float3(0.55, 0.40, 1.00), float3(0.30, 0.90, 0.45), float3(1.00, 0.55, 0.20),
};

kernel void confetti_spawn(device ConfettiParticle *particles [[buffer(0)]],
                           constant ConfettiStep &s [[buffer(1)]],
                           uint id [[thread_position_in_grid]]) {
    if (id >= s.count) {
        return;
    }
    uint base = id * 7U + uint(s.seed * 7919.0);
    float h0 = confettiHash(base), h1 = confettiHash(base + 1U), h2 = confettiHash(base + 2U);
    float h3 = confettiHash(base + 3U), h4 = confettiHash(base + 4U), h5 = confettiHash(base + 5U);
    bool spark = h0 < s.sparkShare;

    // A fan around `direction` (down out of the island by default).
    float angle = s.direction + (h1 - 0.5) * s.spread;
    float speed = (spark ? mix(500.0, 1500.0, pow(h2, 0.7)) : mix(320.0, 1050.0, h2)) * s.speedScale;
    ConfettiParticle p;
    p.motion = float4(s.origin + float2((h3 - 0.5) * 30.0, 0.0), float2(cos(angle), sin(angle)) * speed);
    float3 srgb = spark ? s.sparkColor.rgb : confettiPalette[uint(h4 * 5.999)];
    p.color = float4(pow(srgb, float3(2.2)), 1.0);   // linear, for the extended linear color space
    float life = spark ? mix(0.45, 1.1, h5) : mix(2.2, 3.4, h5);
    p.spin = float4(h3 * 6.28, (h4 - 0.5) * 24.0, life, life);
    p.shape = float4(spark ? mix(2.6, 4.4, h2) : mix(5.0, 8.0, h3), spark ? 1.0 : 0.0, h5, 0.0);
    particles[id] = p;
}

kernel void confetti_update(device ConfettiParticle *particles [[buffer(0)]],
                            constant ConfettiStep &s [[buffer(1)]],
                            uint id [[thread_position_in_grid]]) {
    if (id >= s.count) {
        return;
    }
    ConfettiParticle p = particles[id];
    if (p.spin.z <= 0.0) {
        return;
    }
    float2 velocity = p.motion.zw;
    if (p.shape.y < 0.5) {
        // Paper: heavy drag gives a slow terminal speed, and it flutters side to side as it falls.
        velocity.y += s.gravity * 0.55 * s.dt;
        velocity.x += sin(s.time * 7.0 + p.shape.z * 40.0) * 90.0 * s.dt;
        velocity *= max(1.0 - 2.3 * s.dt, 0.0);
    } else {
        velocity.y += s.gravity * 0.35 * s.dt;
        velocity *= max(1.0 - 3.0 * s.dt, 0.0);
    }
    p.motion = float4(p.motion.xy + velocity * s.dt, velocity);
    p.spin.x += p.spin.y * s.dt;
    p.spin.z -= s.dt;
    particles[id] = p;
}

struct ConfettiOut {
    float4 position [[position]];
    float2 local;
    float4 color;
    float  kind [[flat]];
    float  shade;
};

constant float2 confettiCorners[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };

vertex ConfettiOut confetti_vertex(uint vid [[vertex_id]],
                                   uint iid [[instance_id]],
                                   const device ConfettiParticle *particles [[buffer(0)]],
                                   constant ConfettiRender &u [[buffer(1)]]) {
    ConfettiParticle p = particles[iid];
    ConfettiOut out;
    float2 corner = confettiCorners[vid];
    out.local = corner;
    out.kind = p.shape.y;
    if (p.spin.z <= 0.0) {
        out.position = float4(-2.0, -2.0, 0.0, 1.0);
        out.color = float4(0.0);
        out.shade = 0.0;
        return out;
    }
    float lifeFraction = p.spin.z / p.spin.w;
    float2 offset;
    if (p.shape.y < 0.5) {
        // A strip of paper tumbling in 3D: its width flips through zero as it turns.
        float flip = cos(p.spin.x * 1.7 + p.shape.z * 6.0);
        float2 extent = float2(p.shape.x * 0.5 * max(abs(flip), 0.15), p.shape.x);
        float c = cos(p.spin.x), s = sin(p.spin.x);
        float2 q = corner * extent;
        offset = float2(c * q.x - s * q.y, s * q.x + c * q.y);
        out.shade = 0.65 + 0.35 * abs(flip);
        out.color = float4(p.color.rgb, saturate(p.spin.z / 0.5));
    } else {
        // A spark: a short streak along its velocity.
        float2 v = p.motion.zw;
        float speed = length(v);
        float2 dir = speed > 1.0 ? v / speed : float2(0.0, 1.0);
        float2 side = float2(-dir.y, dir.x);
        float streak = p.shape.x * (1.5 + speed * 0.012);
        offset = dir * corner.y * streak + side * corner.x * p.shape.x;
        out.shade = 1.0;
        out.color = float4(p.color.rgb, lifeFraction);
    }
    float2 pt = p.motion.xy + offset;
    float2 ndc = pt * u.scale / u.viewport * 2.0 - 1.0;
    out.position = float4(ndc.x, -ndc.y, 0.0, 1.0);
    return out;
}

fragment float4 confetti_fragment(ConfettiOut in [[stage_in]],
                                  constant ConfettiRender &u [[buffer(1)]]) {
    if (in.kind < 0.5) {
        float alpha = in.color.a;
        return float4(in.color.rgb * in.shade * alpha, alpha);
    }
    // Sparks: a golden halo that also shows on a white background (it covers a little of what is
    // behind it), plus a hot core added on top that goes well past white on HDR screens.
    float d = length(in.local);
    float glow = exp(-d * d * 2.5);
    float core = exp(-d * d * 12.0);
    float life = in.color.a;
    float halo = glow * 0.85 * life;
    float3 rgb = in.color.rgb * halo + float3(1.0, 0.95, 0.85) * core * u.sparkBoost * life;
    return float4(rgb, halo);
}
