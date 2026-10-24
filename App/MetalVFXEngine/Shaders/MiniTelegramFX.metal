//
//  MiniTelegramFX.metal
//  controller
//
//  Shaders for the Mini-Telegram chat:
//  - Message effects: a full-screen particle burst for 🎉 ❤️ 👍 🔥 messages. Particles are spawned
//    on the CPU once and integrated on the GPU every frame (gravity, drag, sway, buoyancy); they
//    draw as the emoji itself, confetti flakes that flip as they fall, or HDR sparks.
//  - Liquid voice: the voice message's waveform as a band of liquid; while playing, a drop rides
//    the playhead and the band swells and ripples around it.
//  All coordinates are in points, top-left origin.
//

#include <metal_stdlib>
using namespace metal;

static float mtHash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static float mtSmin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// =====================================================================
// MARK: - Message effects
// =====================================================================

// Keep in sync with `MTEffectParticle` in MTChatFX.swift.
struct MTEffectParticle {
    float2 position;    // points
    float2 velocity;    // points / s
    float4 color;       // straight srgb; > 1 is HDR (sparks)
    float  size;        // points
    float  rotation;
    float  spin;
    float  life;        // seconds left
    float  maxLife;
    float  kind;        // 0 emoji, 1 spark, 2 confetti flake
    float  delay;       // seconds before it appears
    float  phase;
};

// Keep in sync with `MTEffectStep` in MTChatFX.swift.
struct MTEffectStep {
    float dt;
    float gravity;      // points / s², + is down
    float drag;         // per second
    float sway;         // sideways wobble, points / s²
    float time;
    float buoyancy;     // emoji float up instead of falling
    float2 unused;
};

kernel void mt_effect_update(device MTEffectParticle *particles [[buffer(0)]],
                             constant MTEffectStep &s [[buffer(1)]],
                             constant uint &count [[buffer(2)]],
                             uint id [[thread_position_in_grid]]) {
    if (id >= count) return;
    MTEffectParticle p = particles[id];
    if (p.delay > 0.0) {
        p.delay -= s.dt;
        particles[id] = p;
        return;
    }
    if (p.life <= 0.0) return;
    float gravity = p.kind == 0.0 ? s.gravity - s.buoyancy : s.gravity;
    if (p.kind == 1.0) gravity *= 0.35;   // sparks are light
    p.velocity.y += gravity * s.dt;
    p.velocity.x += sin(s.time * 3.1 + p.phase) * s.sway * s.dt * (p.kind == 2.0 ? 1.6 : 1.0);
    p.velocity *= exp(-s.drag * s.dt * (p.kind == 2.0 ? 2.2 : 1.0));
    p.position += p.velocity * s.dt;
    p.rotation += p.spin * s.dt;
    p.life -= s.dt;
    particles[id] = p;
}

// Keep in sync with `MTEffectRender` in MTChatFX.swift.
struct MTEffectRender {
    float2 viewport;
    float  scale;
    float  boost;       // HDR multiplier for sparks
};

struct MTEffectOut {
    float4 position [[position]];
    float2 uv;
    float4 color;
    float  kind;
    float  alpha;
    float  flip;
};

constant float2 mtCorners[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };

vertex MTEffectOut mt_effect_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                                    const device MTEffectParticle *particles [[buffer(0)]],
                                    constant MTEffectRender &u [[buffer(1)]]) {
    MTEffectParticle p = particles[iid];
    MTEffectOut out;
    float2 corner = mtCorners[vid];
    bool visible = p.delay <= 0.0 && p.life > 0.0;
    float age = 1.0 - p.life / max(p.maxLife, 1e-3);
    // Pop in, then shrink and fade at the end.
    float grow = smoothstep(0.0, 0.08, age);
    float fade = 1.0 - smoothstep(0.7, 1.0, age);
    float size = p.size * (p.kind == 0.0 ? mix(0.3, 1.0, grow) * mix(1.0, 0.7, smoothstep(0.6, 1.0, age)) : 1.0);
    float flip = p.kind == 2.0 ? cos(p.rotation * 1.7 + p.phase) : 1.0;
    float2 extent = p.kind == 2.0 ? float2(size, size * 0.55) * float2(1.0, max(abs(flip), 0.15)) : float2(size);
    float c = cos(p.rotation), s = sin(p.rotation);
    float2 local = corner * extent * 0.5;
    float2 rotated = float2(local.x * c - local.y * s, local.x * s + local.y * c);
    float2 point = p.position + rotated;
    float2 ndc = point * u.scale / u.viewport * 2.0 - 1.0;
    out.position = visible ? float4(ndc.x, -ndc.y, 0.0, 1.0) : float4(-2, -2, 0, 1);
    out.uv = corner * 0.5 + 0.5;
    out.color = p.color;
    out.kind = p.kind;
    out.alpha = fade * (p.kind == 1.0 ? (1.0 - age) : 1.0);
    out.flip = flip;
    return out;
}

constexpr sampler mtEmojiSampler(coord::normalized, address::clamp_to_edge, filter::linear);

fragment float4 mt_effect_fragment(MTEffectOut in [[stage_in]],
                                   constant MTEffectRender &u [[buffer(1)]],
                                   texture2d<float> emoji [[texture(0)]]) {
    if (in.kind == 0.0) {
        float4 texel = emoji.sample(mtEmojiSampler, in.uv);   // premultiplied
        return texel * in.alpha;
    }
    if (in.kind == 1.0) {
        // A soft glowing spark; the core goes past white on HDR displays.
        float d = length(in.uv - 0.5) * 2.0;
        float glow = exp(-d * d * 4.0);
        float core = exp(-d * d * 30.0);
        float3 color = in.color.rgb * glow + core * u.boost;
        float a = saturate(glow) * in.alpha;
        return float4(color * in.alpha, a * 0.85);
    }
    // Confetti: a flake, darker on its back side as it flips.
    float2 q = abs(in.uv - 0.5) * 2.0;
    float edge = 1.0 - smoothstep(0.85, 1.0, max(q.x, q.y));
    float shade = mix(0.55, 1.0, abs(in.flip)) * (in.flip < 0.0 ? 0.8 : 1.0);
    float a = edge * in.alpha;
    return float4(in.color.rgb * shade * a, a);
}

// =====================================================================
// MARK: - Liquid voice waveform
// =====================================================================

// Keep in sync with `MTWaveUniforms` in MTChatFX.swift.
struct MTWaveUniforms {
    float2 viewport;
    float  scale;
    float  progress;    // 0…1 played
    float4 played;      // straight srgb
    float4 rest;
    float  time;
    float  playing;     // 0…1, eases in and out
    float  count;       // number of amplitudes
    float  unused;
};

static float waveAmplitude(constant float *amps, float count, float x) {
    // Catmull-Rom through the bars, so the band is smooth like a liquid surface.
    float f = clamp(x, 0.0, 1.0) * (count - 1.0);
    int i = int(floor(f));
    float t = f - float(i);
    int n = int(count);
    float a = amps[max(i - 1, 0)], b = amps[i], c = amps[min(i + 1, n - 1)], d = amps[min(i + 2, n - 1)];
    return 0.5 * ((2.0 * b) + (-a + c) * t + (2.0 * a - 5.0 * b + 4.0 * c - d) * t * t + (-a + 3.0 * b - 3.0 * c + d) * t * t * t);
}

fragment float4 mt_wave_fragment(float4 position [[position]],
                                 constant MTWaveUniforms &u [[buffer(0)]],
                                 constant float *amps [[buffer(1)]]) {
    float2 size = u.viewport / u.scale;
    float2 p = position.xy / u.scale;
    float margin = 4.0;
    float x = (p.x - margin) / (size.x - margin * 2.0);
    float mid = size.y * 0.5;
    float head = margin + u.progress * (size.x - margin * 2.0);

    float amp = max(waveAmplitude(amps, u.count, x), 0.12);
    // Around the playhead the surface swells and ripples, as if the drop pushes the liquid.
    float near = exp(-pow((p.x - head) / 16.0, 2.0)) * u.playing;
    float ripple = sin((p.x - head) * 0.55 - u.time * 14.0) * exp(-abs(p.x - head) / 26.0) * u.playing;
    float half_h = amp * (size.y * 0.42) * (1.0 + near * 0.35) + ripple * 1.6;
    half_h = max(half_h, 1.4);
    float band = abs(p.y - mid) - half_h;
    // Rounded ends.
    float ends = max(margin - p.x, p.x - (size.x - margin));
    band = max(band, ends);
    // The drop on the playhead, merged into the band.
    float dropRadius = (3.5 + 1.2 * sin(u.time * 9.0)) * u.playing;
    float drop = length(p - float2(head, mid - half_h * 0.2)) - dropRadius;
    float d = u.playing > 0.01 ? mtSmin(band, drop, 6.0) : band;

    float coverage = saturate(0.5 - d * u.scale / 1.5);
    if (coverage <= 0.0) return float4(0.0);
    float playedMix = smoothstep(head + 1.5, head - 1.5, p.x);
    float3 color = mix(u.rest.rgb, u.played.rgb, playedMix);
    float alpha = mix(u.rest.a, u.played.a, playedMix);
    // A wet highlight along the upper edge.
    float rim = exp(-pow((d + 1.4) / 1.2, 2.0)) * step(p.y, mid);
    color = mix(color, float3(1.0), rim * 0.35);
    float a = coverage * alpha;
    return float4(color * a, a);
}

vertex float4 mt_fullscreen_vertex(uint vid [[vertex_id]]) {
    float2 pos = float2((vid << 1) & 2, vid & 2);
    return float4(pos * 2.0 - 1.0, 0.0, 1.0);
}
