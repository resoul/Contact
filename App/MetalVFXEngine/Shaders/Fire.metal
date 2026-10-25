//
//  FireShader.metal
//  demo
//
//  Procedural fire: upward-scrolling turbulence noise with a vertical falloff mapped to a
//  temperature gradient, heat-haze distortion, smoke above the flames and drifting sparks.
//

#include "EffectsCommon.h"

// Turbulence: fBm of |noise| gives sharp creases, which read as flame tongues.
static float turbulence(float2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 5; i++) {
        value += amplitude * abs(valueNoise(p) * 2.0 - 1.0);
        p = p * 2.03 + float2(7.7, 3.1);
        amplitude *= 0.5;
    }
    return value;
}

// Black -> deep red -> orange -> yellow -> white.
static float3 fireColor(float heat) {
    float3 c = mix(float3(0.0), float3(0.45, 0.02, 0.0), smoothstep(0.00, 0.25, heat));
    c = mix(c, float3(1.00, 0.35, 0.00), smoothstep(0.25, 0.50, heat));
    c = mix(c, float3(1.00, 0.80, 0.20), smoothstep(0.50, 0.78, heat));
    c = mix(c, float3(1.00, 0.97, 0.90), smoothstep(0.78, 1.00, heat));
    return c;
}

fragment float4 fire_fragment(FullscreenVertexOut in [[stage_in]],
                              constant EffectUniforms &u [[buffer(0)]]) {
    float2 px = in.uv * u.resolution;
    float unit = min(u.resolution.x, u.resolution.y);
    float t = u.time;
    float2 p = float2(px.x, u.resolution.y - px.y) / unit;    // y grows upwards from the bottom
    float height = (0.25 + 0.75 * u.progress) * u.resolution.y / unit;
    float yn = p.y / height;                                  // 0 at the base, 1 at the flame tip

    // The flames lean towards the finger, more at the top.
    float lean = (u.touch.x - 0.5 * u.resolution.x) / unit * u.touchStrength * 0.6;
    // Heat haze: a wavy horizontal shift that grows with height.
    float haze = (valueNoise(float2(p.y * 6.0 - t * 4.0, p.x * 2.0 + t)) - 0.5) * 0.08 * saturate(yn);
    float2 q = float2(p.x - lean * yn * yn + haze, p.y);

    float turb = turbulence(float2(q.x * 3.0, q.y * 2.0 - t * 2.6));
    float heat = saturate((1.0 - yn) * 1.3 - turb * (0.55 + 0.6 * yn));
    float3 flame = fireColor(heat);

    // Smoke rising above the flames.
    float smokeNoise = fbm(float2(q.x * 2.0, q.y * 1.4 - t * 0.7));
    float smoke = smoothstep(0.7, 1.2, yn) * (1.0 - smoothstep(1.4, 2.8, yn))
                * smoothstep(0.45, 0.8, smokeNoise) * 0.4;
    float3 background = mix(float3(0.03, 0.025, 0.03), float3(0.07, 0.03, 0.02), saturate(1.0 - yn));
    float3 color = mix(background, float3(0.28, 0.26, 0.26), smoke) + flame;

    // Sparks: sparse points on a grid scrolling upwards, wobbling sideways and twinkling.
    float2 sp = float2(q.x * 7.0, p.y * 4.0 - t * 2.2);
    float2 cell = floor(sp);
    float2 seed = hash22(cell);
    float2 center = float2(0.5 + 0.35 * sin(t * 3.0 + seed.y * 6.28), 0.2 + 0.6 * seed.x);
    float d = length((fract(sp) - center) * float2(1.0, 0.6));
    float spark = (1.0 - smoothstep(0.0, 0.08, d)) * step(0.8, hash21(cell + 5.3));
    float sparkFade = smoothstep(0.1 * height, 0.4 * height, p.y) * (1.0 - smoothstep(0.4 * height, 1.8 * height, p.y));
    float twinkle = 0.6 + 0.4 * sin(t * 10.0 + seed.y * 20.0);
    color += float3(1.0, 0.55, 0.15) * spark * sparkFade * twinkle * (0.5 + 0.5 * u.progress);

    return float4(saturate(color), 1.0);
}
