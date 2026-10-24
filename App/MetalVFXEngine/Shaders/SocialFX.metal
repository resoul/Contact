//
//  SocialFX.metal
//  controller
//
//  Shaders for the social demos (MetalVFXEngine/Social):
//  - Story rings: one pass draws every ring of the stories row — a living gradient that flows
//    around the avatar and wobbles; watched stories get a thin grey ring.
//  - Character ring: the composer's counter as a ring-shaped tube that fills with liquid; past the
//    limit it overflows and drips.
//  - Filter wave: a new photo filter washing over the old one as a wavy, refracting front.
//  All coordinates are in points, top-left origin.
//

#include <metal_stdlib>
using namespace metal;

struct SocialOut {
    float4 position [[position]];
    float2 uv;
};

vertex SocialOut social_vertex(uint vid [[vertex_id]]) {
    float2 pos = float2((vid << 1) & 2, vid & 2);
    SocialOut out;
    out.position = float4(pos * 2.0 - 1.0, 0.0, 1.0);
    out.uv = float2(pos.x, 1.0 - pos.y);
    return out;
}

static float socialSmin(float a, float b, float k) {
    float h = saturate(0.5 + 0.5 * (b - a) / k);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// =====================================================================
// MARK: - Story rings
// =====================================================================

// Keep in sync with `StoryRingUniforms` in StoryRingsView.swift.
struct StoryRingUniforms {
    float2 viewport;    // px
    float  scale;
    float  time;
    uint   count;
    float  width;       // ring thickness, points
    float2 unused;
};

// Keep in sync with `StoryRing` in StoryRingsView.swift.
struct StoryRing {
    float4 ring;        // center x, center y, radius (middle of the ring), seen (0…1)
    float4 extra;       // press (0…1), seed, unused, unused
};

// The warm-to-violet sweep of story rings, as a loop.
static float3 storyGradient(float t) {
    const float3 c0 = float3(1.00, 0.85, 0.36);
    const float3 c1 = float3(0.98, 0.49, 0.12);
    const float3 c2 = float3(0.84, 0.16, 0.46);
    const float3 c3 = float3(0.59, 0.18, 0.75);
    const float3 c4 = float3(0.31, 0.36, 0.84);
    t = fract(t) * 5.0;
    if (t < 1.0) return mix(c0, c1, t);
    if (t < 2.0) return mix(c1, c2, t - 1.0);
    if (t < 3.0) return mix(c2, c3, t - 2.0);
    if (t < 4.0) return mix(c3, c4, t - 3.0);
    return mix(c4, c0, t - 4.0);
}

fragment float4 story_rings_fragment(SocialOut in [[stage_in]],
                                     constant StoryRingUniforms &u [[buffer(0)]],
                                     constant StoryRing *rings [[buffer(1)]]) {
    float2 p = in.position.xy / u.scale;
    float pixel = 1.0 / u.scale;
    float4 result = float4(0.0);
    for (uint i = 0; i < u.count; ++i) {
        StoryRing r = rings[i];
        float2 d = p - r.ring.xy;
        float dist = length(d);
        if (abs(dist - r.ring.z) > u.width * 2.0 + 4.0) {
            continue;
        }
        float angle = atan2(d.x, -d.y) / (2.0 * M_PI_F);   // 0 at the top, clockwise
        float seen = r.ring.w;
        float press = r.extra.x;
        // Unseen rings breathe: their thickness ripples around the circle like a liquid band.
        float wobble = (sin(angle * 6.2831 * 3.0 + u.time * 2.2 + r.extra.y) * 0.22
                      + sin(angle * 6.2831 * 5.0 - u.time * 3.1 + r.extra.y * 2.0) * 0.12) * (1.0 - seen);
        float halfWidth = mix(u.width * 0.5 * (1.0 + wobble) * (1.0 + 0.4 * press), 0.6, seen);
        float ringD = abs(dist - r.ring.z) - halfWidth;
        float alpha = 1.0 - smoothstep(-pixel, pixel, ringD);
        if (alpha <= 0.0) {
            continue;
        }
        // The gradient flows around the ring; a soft highlight slides along with it.
        float3 color = storyGradient(angle * 0.9 - u.time * 0.12 + r.extra.y);
        float shine = pow(saturate(cos((angle - u.time * 0.18) * 6.2831)), 12.0) * 0.35;
        color = mix(color + shine, float3(0.45), seen);
        result = float4(color * alpha, alpha) + result * (1.0 - alpha);
    }
    return result;
}

// =====================================================================
// MARK: - Character ring
// =====================================================================

// Keep in sync with `CharacterRingUniforms` in CharacterRingView.swift.
struct CharacterRingUniforms {
    float2 viewport;    // px
    float  scale;
    float  time;
    float2 center;
    float  radius;      // middle of the tube, points
    float  width;       // tube thickness, points
    float  fill;        // 0…1 around the ring; ≥ 1 full (overflowing)
    float  slosh;       // how hard the front sloshes
    uint   dripCount;
    float  unused;
    float4 liquid;      // straight rgb
    float4 track;       // straight rgb + alpha
};

fragment float4 character_ring_fragment(SocialOut in [[stage_in]],
                                        constant CharacterRingUniforms &u [[buffer(0)]],
                                        constant float4 *drips [[buffer(1)]]) {
    float2 p = in.position.xy / u.scale;
    float pixel = 1.0 / u.scale;
    float2 d = p - u.center;
    float dist = length(d);
    float channel = abs(dist - u.radius) - u.width * 0.5;

    // Liquid: the channel up to the front, which ripples while it moves.
    float angle = fract(atan2(d.x, -d.y) / (2.0 * M_PI_F));
    float front = u.fill + (sin(u.time * 11.0 + (dist - u.radius) * 1.3) * 0.012 + sin(u.time * 5.0) * 0.006)
                * min(abs(u.slosh) * 4.0 + 0.3, 1.5) * step(u.fill, 0.999);
    float liquid = u.fill >= 0.999 ? channel : max(channel, (angle - front) * 6.2831 * u.radius);
    // Overflow: drips run off the bottom of the ring, joined to it by gooey necks.
    for (uint i = 0; i < u.dripCount; ++i) {
        float4 drip = drips[i];
        liquid = socialSmin(liquid, length(p - drip.xy) - drip.z, 3.5);
    }

    float liquidA = 1.0 - smoothstep(-pixel, pixel, liquid);
    float trackA = (1.0 - smoothstep(-pixel, pixel, channel)) * u.track.a;
    // A highlight along the inner edge gives the tube some roundness.
    float inner = saturate(1.0 - abs(dist - (u.radius - u.width * 0.2)) / (u.width * 0.4));
    float3 color = u.liquid.rgb * (0.9 + 0.25 * inner);
    float3 rgb = color * liquidA + u.track.rgb * trackA * (1.0 - liquidA);
    float a = liquidA + trackA * (1.0 - liquidA);
    return float4(rgb, a);
}

// =====================================================================
// MARK: - Filter wave
// =====================================================================

// Keep in sync with `FilterWaveUniforms` in FilterWaveView.swift.
struct FilterWaveUniforms {
    float2 viewport;    // px
    float  progress;    // 0 → 1 as the new filter washes over
    float  direction;   // 1 left to right, -1 right to left
    float  time;
    float  radius;      // corner radius, points
    float  scale;
    float  unused;
};

constexpr sampler waveSampler(coord::normalized, address::clamp_to_edge, filter::linear);

fragment float4 filter_wave_fragment(SocialOut in [[stage_in]],
                                     texture2d<float> oldImage [[texture(0)]],
                                     texture2d<float> newImage [[texture(1)]],
                                     constant FilterWaveUniforms &u [[buffer(0)]]) {
    float2 uv = in.uv;
    float x = u.direction > 0.0 ? uv.x : 1.0 - uv.x;
    // A wavy front, fast ripples riding on a slow swell.
    float wave = sin(uv.y * 9.0 + u.time * 5.0) * 0.035 + sin(uv.y * 23.0 - u.time * 8.0) * 0.012;
    float front = u.progress * 1.3 - 0.15 + wave;
    float behind = x - front;                       // < 0: already washed with the new filter
    float band = exp(-behind * behind / 0.0016);    // the crest of the wave
    // Near the crest the image is bent, like looking through the water's edge.
    float2 bend = float2(u.direction * band * 0.025, sin(uv.y * 40.0 + u.time * 7.0) * band * 0.004);
    float3 oldC = oldImage.sample(waveSampler, uv + bend).rgb;
    float3 newC = newImage.sample(waveSampler, uv + bend).rgb;
    float mixT = smoothstep(0.01, -0.01, behind);
    float3 color = mix(oldC, newC, mixT);
    color += band * 0.22;   // foam on the crest

    // Rounded corners, like the photo under it.
    float2 size = u.viewport / u.scale;
    float2 p = uv * size;
    float2 q = abs(p - size * 0.5) - size * 0.5 + u.radius;
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - u.radius;
    float alpha = 1.0 - smoothstep(-1.0 / u.scale, 1.0 / u.scale, d);
    return float4(saturate(color) * alpha, alpha);
}
