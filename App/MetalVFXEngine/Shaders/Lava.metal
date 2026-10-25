//
//  LavaShader.metal
//  demo
//
//  Procedural boiling lava: domain-warped fBm value noise, bubble rings and a white-hot
//  meniscus, all computed per pixel. No textures are sampled.
//

#include "EffectsCommon.h"

// MARK: - Bubbles

// Expanding, fading rings on a jittered grid; each cell respawns its bubble somewhere new.
static float bubbles(float2 p, float t) {
    float2 cell = floor(p);
    float2 f = fract(p);
    float result = 0.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 g = float2(x, y);
            float2 id = cell + g;
            float2 seed = hash22(id);
            float phase = t * (0.35 + 0.3 * seed.x) + seed.y;
            float life = fract(phase);
            float2 center = g + 0.2 + 0.6 * hash22(id + floor(phase) * 7.31);
            float radius = 0.38 * life;
            float d = length(center - f);
            float ring = 1.0 - smoothstep(0.0, 0.07, abs(d - radius));
            float core = (1.0 - smoothstep(radius - 0.05, radius, d)) * 0.35;
            result = max(result, (ring + core) * (1.0 - life) * smoothstep(0.0, 0.15, life));
        }
    }
    return result;
}

// MARK: - Palette

// Crust -> dark red -> orange -> yellow -> hot white.
static float3 lavaPalette(float h) {
    const float3 crust    = float3(0.12, 0.01, 0.00);
    const float3 darkRed  = float3(0.55, 0.04, 0.00);
    const float3 orange   = float3(1.00, 0.35, 0.00);
    const float3 yellow   = float3(1.00, 0.78, 0.15);
    const float3 hotWhite = float3(1.00, 0.97, 0.88);
    float3 c = mix(crust, darkRed, smoothstep(0.00, 0.30, h));
    c = mix(c, orange, smoothstep(0.30, 0.55, h));
    c = mix(c, yellow, smoothstep(0.55, 0.80, h));
    c = mix(c, hotWhite, smoothstep(0.80, 1.00, h));
    return c;
}

// MARK: - Fragment

fragment float4 lava_fragment(FullscreenVertexOut in [[stage_in]],
                              constant EffectUniforms &u [[buffer(0)]]) {
    float2 uv = in.uv;
    float t = u.time;
    float aspect = u.resolution.x / max(u.resolution.y, 1.0);

    // Bar-height units (y in 0...1, x in 0...aspect) for the meniscus geometry.
    float2 bar = float2(uv.x * aspect, uv.y);
    // Noise lives in pixel space, so the lava keeps its grain size whatever the bar height.
    float2 p = uv * u.resolution / float2(68.0, 50.0);

    // Two levels of domain warping give the slow churning "boil".
    float2 q = float2(fbm(p + float2(-0.30 * t, 0.15 * t)),
                      fbm(p + float2(5.2, 1.3) + float2(-0.25 * t, -0.20 * t)));
    float2 r = float2(fbm(p + 2.5 * q + float2(1.7, 9.2) + 0.30 * t),
                      fbm(p + 2.5 * q + float2(8.3, 2.8) - 0.25 * t));
    float heat = fbm(p + 3.0 * r - float2(0.6 * t, 0.0));

    // Leading edge: a wobbling, convex meniscus. d is the distance from it in bar heights,
    // positive inside the lava. The range is padded so 0 hides it and 1 fills the whole bar.
    float hasLava = smoothstep(0.0, 0.03, u.progress);
    float wobble = (valueNoise(float2(uv.y * 3.0, t * 1.5)) - 0.5) * 0.35 * hasLava;
    float curve = pow(uv.y * 2.0 - 1.0, 2.0) * 0.3;
    float edge = mix(-0.3, aspect + 0.5, u.progress) + wobble - curve;
    float d = edge - bar.x;
    float aa = 1.5 / max(u.resolution.y, 1.0);
    float inside = smoothstep(-aa, aa, d);

    // Heat: noise, cooler near the walls, dark crust plates, bubbles, white-hot meniscus.
    float walls = 1.0 - 0.45 * pow(abs(uv.y * 2.0 - 1.0), 2.5);
    float h = (heat * 1.35 - 0.2) * walls;
    h -= smoothstep(0.55, 0.75, r.x) * 0.35;
    h += bubbles(p * float2(1.2, 1.0) + float2(-0.5 * t, 0.0), t) * 0.45;
    h += exp(-max(d, 0.0) * 5.0) * 0.85;
    float3 lava = lavaPalette(saturate(h));

    // Track: charcoal, lit by the glow spilling ahead of the meniscus.
    float spill = exp(min(d, 0.0) * 6.0) * hasLava;
    float3 track = float3(0.07, 0.05, 0.05) + float3(0.02, 0.01, 0.0) * valueNoise(bar * 8.0);
    track += float3(1.0, 0.32, 0.0) * spill * 0.45;

    return float4(mix(track, lava, inside), 1.0);
}
