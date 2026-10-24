//
//  SocialRoomFX.metal
//  controller
//
//  Shaders for the voice room, the bubble cluster and the ambient feed (MetalVFXEngine/SocialRoom):
//  - Voice rims: a liquid rim around every speaker's tile, thickening and rippling with their voice,
//    with a glow that blooms while they talk. One pass for all tiles.
//  - Glass column: frosted glass over a photo — refracts and blurs the photo under it (sampled from
//    the photo itself, so it costs no snapshot), with a rim light and a soft shadow.
//  All coordinates are in points, top-left origin.
//

#include <metal_stdlib>
using namespace metal;

struct RoomOut {
    float4 position [[position]];
    float2 uv;
};

vertex RoomOut room_vertex(uint vid [[vertex_id]]) {
    float2 pos = float2((vid << 1) & 2, vid & 2);
    RoomOut out;
    out.position = float4(pos * 2.0 - 1.0, 0.0, 1.0);
    out.uv = float2(pos.x, 1.0 - pos.y);
    return out;
}

static float roomRoundedBox(float2 p, float2 halfSize, float radius) {
    float2 q = abs(p) - halfSize + radius;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

// =====================================================================
// MARK: - Voice rims
// =====================================================================

// Keep in sync with `VoiceRimUniforms` in VoiceRimsView.swift.
struct VoiceRimUniforms {
    float2 viewport;    // px
    float  scale;
    float  time;
    uint   count;
    float  unused0;
    float  unused1;
    float  unused2;
    float4 colorA;      // straight rgb
    float4 colorB;
};

// Keep in sync with `VoiceRim` in VoiceRimsView.swift.
struct VoiceRim {
    float4 rect;        // x, y, width, height
    float4 params;      // corner radius, level 0…1, seed, unused
};

fragment float4 voice_rims_fragment(RoomOut in [[stage_in]],
                                    constant VoiceRimUniforms &u [[buffer(0)]],
                                    constant VoiceRim *rims [[buffer(1)]]) {
    float2 p = in.position.xy / u.scale;
    float pixel = 1.0 / u.scale;
    float4 result = float4(0.0);
    for (uint i = 0; i < u.count; ++i) {
        VoiceRim r = rims[i];
        float level = r.params.y;
        float2 halfSize = r.rect.zw * 0.5;
        float2 local = p - r.rect.xy - halfSize;
        float d = roomRoundedBox(local, halfSize, r.params.x);
        if (d < -2.0 || d > 34.0) {
            continue;
        }
        // Around the tile: 0…1 along its outline, for the ripples and the flowing gradient.
        float around = atan2(local.y, local.x) / (2.0 * M_PI_F) + 0.5;
        float ripple = sin(around * 6.2831 * 4.0 + u.time * 7.0 + r.params.z) * 0.6
                     + sin(around * 6.2831 * 9.0 - u.time * 11.0 + r.params.z * 2.0) * 0.4;
        float thickness = 2.0 + level * (5.0 + 3.0 * ripple);
        float rim = 1.0 - smoothstep(thickness - pixel, thickness + pixel, d);
        rim *= smoothstep(-pixel, pixel, d + 0.5);
        float glow = exp(-max(d - thickness, 0.0) / (4.0 + 10.0 * level)) * level * 0.55 * step(thickness, d)
                   * (1.0 - smoothstep(18.0, 33.0, d));   // fades out before the cutoff
        float t = fract(around - u.time * 0.15);
        float3 color = mix(u.colorA.rgb, u.colorB.rgb, 0.5 + 0.5 * sin(t * 6.2831));
        float alpha = max(rim * (0.35 + 0.65 * smoothstep(0.02, 0.2, level)), glow);
        result = float4(color * alpha, alpha) + result * (1.0 - alpha);
    }
    return result;
}

// =====================================================================
// MARK: - Glass column over a photo
// =====================================================================

// Keep in sync with `GlassColumnUniforms` in GlassColumnView.swift.
struct GlassColumnUniforms {
    float2 viewport;    // px
    float  scale;
    float  radius;      // corner radius of the glass, points
    float4 glass;       // the glass pill in this view: x, y, width, height
    float4 image;       // where the photo lies in this view (aspect-filled): x, y, width, height
    float4 tint;        // straight rgb + strength
    float  refraction;
    float  blur;        // mip level
    float2 light;       // direction the light comes from (screen space)
};

constexpr sampler columnSampler(coord::normalized, address::clamp_to_edge, filter::linear, mip_filter::linear);

fragment float4 glass_column_fragment(RoomOut in [[stage_in]],
                                      constant GlassColumnUniforms &u [[buffer(0)]],
                                      texture2d<float> photo [[texture(0)]]) {
    float2 p = in.position.xy / u.scale;
    float2 halfSize = u.glass.zw * 0.5;
    float2 local = p - u.glass.xy - halfSize;
    float radius = min(u.radius, min(halfSize.x, halfSize.y));
    float d = roomRoundedBox(local, halfSize, radius);
    if (d > 0.0) {
        float ds = roomRoundedBox(local - float2(0.0, 4.0), halfSize, radius);
        float shadow = exp(-max(ds, 0.0) * max(ds, 0.0) / 90.0) * 0.25;
        return float4(0.0, 0.0, 0.0, shadow * smoothstep(0.0, 1.0, d));
    }
    const float e = 0.6;
    float2 grad = float2(roomRoundedBox(local + float2(e, 0), halfSize, radius) - roomRoundedBox(local - float2(e, 0), halfSize, radius),
                         roomRoundedBox(local + float2(0, e), halfSize, radius) - roomRoundedBox(local - float2(0, e), halfSize, radius));
    float2 n = normalize(grad + 1e-5);
    float inside = saturate(-d / 12.0);
    float bend = pow(1.0 - inside, 2.4);
    float2 sp = p + n * u.refraction * bend;
    float2 uv = (sp - u.image.xy) / u.image.zw;
    float2 split = n * u.refraction * bend * 0.3 / u.image.zw;
    float3 color = float3(photo.sample(columnSampler, uv + split, level(u.blur)).r,
                          photo.sample(columnSampler, uv, level(u.blur)).g,
                          photo.sample(columnSampler, uv - split, level(u.blur)).b);
    color = mix(color, u.tint.rgb, u.tint.a) * 1.08 + 0.03;
    float2 lightDir = normalize(u.light);
    float key = saturate(dot(n, lightDir));
    float rimLight = pow(1.0 - inside, 5.0);
    color += rimLight * (key * 0.6 + 0.12);
    color += (1.0 - smoothstep(0.0, 1.0, abs(d + 0.6))) * 0.12;
    float aa = 1.0 - smoothstep(-1.0 / u.scale, 0.0, d);
    return float4(saturate(color) * aa, aa);
}
