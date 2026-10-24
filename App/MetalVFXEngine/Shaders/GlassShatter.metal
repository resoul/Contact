//
//  GlassShatter.metal
//  controller
//
//  A view shatters like glass: Voronoi shards (built on the CPU) crack open, then tumble in 3D
//  under gravity. Motion is closed-form in the vertex shader, so there is no per-frame CPU work.
//

#include <metal_stdlib>
using namespace metal;

// Keep in sync with `ShardVertex` / `Shard` / `ShatterUniforms` in GlassShatterAnimator.swift.
struct ShardVertex {
    float2 local;      // offset from the shard's centroid, points
    float2 uv;         // into the snapshot
    float3 bary;       // (1,0,0) at the centroid; the far edge has bary.x = 0
    uint   shard;
};

struct Shard {
    float2 centroid;   // window points
    float2 velocity;   // points / s
    float3 axis;       // rotation axis (unit)
    float  spin;       // radians / s
    float  delay;      // shock wave arrival, s
    float  depthVelocity;   // towards the viewer, points / s
};

struct ShatterUniforms {
    float2 viewport;   // px
    float  scale;      // px per point
    float  time;       // s since impact
    float2 impact;     // window points
    float  crackTime;  // s the cracked glass holds together
    float  gravity;    // points / s²
};

struct ShardOut {
    float4 position [[position]];
    float2 uv;
    float3 bary;
    float3 normal;
    float  age;
};

constexpr sampler shardSampler(coord::normalized, address::clamp_to_zero, filter::linear);

static float3 rotateAround(float3 v, float3 axis, float angle) {
    float c = cos(angle), s = sin(angle);
    return v * c + cross(axis, v) * s + axis * dot(axis, v) * (1.0 - c);
}

vertex ShardOut shard_vertex(uint vid [[vertex_id]],
                             const device ShardVertex *vertices [[buffer(0)]],
                             const device Shard *shards [[buffer(1)]],
                             constant ShatterUniforms &u [[buffer(2)]]) {
    ShardVertex v = vertices[vid];
    Shard s = shards[v.shard];
    float age = max(u.time - u.crackTime - s.delay, 0.0);

    // While cracking, shards only creep apart a little along the shock direction.
    float2 away = s.centroid - u.impact;
    float2 open = normalize(away + 1e-3) * min(u.time / max(u.crackTime, 1e-3), 1.0) * 1.2;

    float angle = s.spin * age;
    float3 local = rotateAround(float3(v.local, 0.0), s.axis, angle);
    float3 center = float3(s.centroid + open + s.velocity * age + float2(0.0, 0.5 * u.gravity * age * age),
                           s.depthVelocity * age);
    float3 world = center + local;

    // Perspective around the screen center, camera 1000 pt away.
    float2 screenCenter = u.viewport / u.scale * 0.5;
    float perspective = 1000.0 / max(1000.0 - world.z, 100.0);
    float2 screen = screenCenter + (world.xy - screenCenter) * perspective;

    float2 ndc = screen * u.scale / u.viewport * 2.0 - 1.0;
    ShardOut out;
    out.position = float4(ndc.x, -ndc.y, 0.0, 1.0);
    out.uv = v.uv;
    out.bary = v.bary;
    out.normal = rotateAround(float3(0.0, 0.0, 1.0), s.axis, angle);
    out.age = age;
    return out;
}

fragment float4 shard_fragment(ShardOut in [[stage_in]],
                               texture2d<float> snapshot [[texture(0)]],
                               constant ShatterUniforms &u [[buffer(2)]]) {
    float4 color = snapshot.sample(shardSampler, in.uv);
    float3 n = normalize(in.normal);

    // Facing away dims the shard; a glint flashes when its face catches the key light.
    float facing = abs(n.z);
    float glint = pow(saturate(dot(n, normalize(float3(-0.5, -0.6, 0.62)))), 24.0);
    color.rgb *= 0.55 + 0.45 * facing;

    // Bright crack lines along each shard's outer edge (bary.x → 0), one pixel wide.
    float edgeWidth = fwidth(in.bary.x) * 1.6;
    float edge = 1.0 - smoothstep(0.0, edgeWidth, in.bary.x);
    float crackGlow = mix(0.9, 0.45, saturate(in.age * 2.0));
    color.rgb += (edge * crackGlow + glint * 0.8) * color.a;

    // Shards fade as they fall away.
    float fade = 1.0 - smoothstep(0.9, 1.5, in.age);
    return saturate(color) * fade;
}
