#include <metal_stdlib>
using namespace metal;

// Extracted from demo/view/view/Effects.metal's Aurora border (effect == 2).
struct MascotAuroraVertexOut { float4 position [[position]]; float2 uv; };

vertex MascotAuroraVertexOut mascotAuroraVertex(uint id [[vertex_id]]) {
    float2 p = float2((id << 1) & 2, id & 2);
    return { float4(p * float2(2, -2) + float2(-1, 1), 0, 1), p };
}

static float mascotAuroraHash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static float mascotAuroraNoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mascotAuroraHash(i), mascotAuroraHash(i + float2(1, 0)), f.x),
               mix(mascotAuroraHash(i + float2(0, 1)), mascotAuroraHash(i + 1.0), f.x), f.y);
}

fragment float4 mascotAuroraFragment(MascotAuroraVertexOut v [[stage_in]],
                                     constant float4 &u [[buffer(0)]]) {
    float2 size = u.xy;
    float2 p = (v.uv - 0.5) * float2(size.x / size.y, 1.0);
    // Preserve the demo's inset glow, with radius clamped for a button's height.
    float2 halfSize = size * 0.5 - 13.0;
    float radius = min(23.0, min(halfSize.x, halfSize.y));
    float2 q = abs((v.uv - 0.5) * size) - halfSize + radius;
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
    float angle = atan2(p.y, p.x);
    float phase = angle / 6.28318 - u.z * 0.14 + mascotAuroraNoise(p * 3.0 + u.z * 0.2) * 0.3;
    float3 aurora = 0.5 + 0.5 * cos(6.28318 * (phase + float3(0, 0.33, 0.67)));
    aurora = mix(aurora, float3(0.56, 0.41, 1.0), 0.18);
    float3 color = float3(0.025, 0.032, 0.049);
    color += aurora * (exp(-abs(d) * 0.5) * 1.1 + exp(-abs(d) * 0.075) * 0.35) * u.w;
    color += float3(0.08, 0.045, 0.14) * (1.0 - smoothstep(-1.0, 1.0, d));
    return float4(min(color, float3(1)), 1);
}
