//
//  ShaderCommon.h
//  demo
//
//  Uniforms, vertex output and noise helpers shared by every effect shader.
//

#pragma once

#include <metal_stdlib>
using namespace metal;

// Mirrored by `EffectUniforms` in MetalAnimationView.swift (144 bytes); keep the layouts identical.
struct EffectUniforms {
    float progress;       // 0...1
    float time;           // seconds
    float2 resolution;    // drawable size in pixels
    float2 touch;         // finger position in pixels, top-left origin
    float touchStrength;  // 0...1, eased
    int blobCount;
    float4 blobs[5];      // metaballs: xy center and z radius, in pixels
    float4 custom[2];     // effect-specific parameters
};

struct FullscreenVertexOut {
    float4 position [[position]];
    float2 uv;            // (0, 0) top-left, (1, 1) bottom-right
};

static inline float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static inline float2 hash22(float2 p) {
    float n = hash21(p);
    return float2(n, hash21(p + n + 17.17));
}

static inline float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Fractal Brownian Motion: 5 octaves, each rotated to hide lattice artifacts. Returns ~0...1.
static inline float fbm(float2 p) {
    const float2x2 rotation = float2x2(0.8, 0.6, -0.6, 0.8);
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 5; i++) {
        value += amplitude * valueNoise(p);
        p = rotation * p * 2.02 + 11.3;
        amplitude *= 0.5;
    }
    return value / 0.96875;
}
