//
//  HolographicCard.metal
//  controller
//
//  Holographic foil over a card snapshot: a diffraction rainbow that slides with tilt,
//  a moving glare, and glitter that twinkles as the light angle changes.
//

#include <metal_stdlib>
using namespace metal;

// Keep in sync with `HoloUniforms` in HolographicCardView.swift.
struct HoloUniforms {
    float2 size;       // card size, points
    float2 tilt;       // −1…1; x = right edge towards the viewer, y = bottom edge towards the viewer
    float  time;
    float  foil;       // rainbow strength, 0…1
    float  glare;      // glare strength, 0…1
    float  glitter;    // glitter strength, 0…1
};

struct HoloOut {
    float4 position [[position]];
    float2 uv;
};

constexpr sampler holoSampler(coord::normalized, address::clamp_to_zero, filter::linear);

static float holoHash(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float3 rainbow(float t) {
    return 0.5 + 0.5 * cos(2.0 * M_PI_F * (t + float3(0.0, 0.33, 0.67)));
}

vertex HoloOut holo_vertex(uint vid [[vertex_id]]) {
    float2 pos = float2((vid << 1) & 2, vid & 2);
    HoloOut out;
    out.position = float4(pos * 2.0 - 1.0, 0.0, 1.0);
    out.uv = float2(pos.x, 1.0 - pos.y);
    return out;
}

fragment float4 holo_fragment(HoloOut in [[stage_in]],
                              texture2d<float> card [[texture(0)]],
                              constant HoloUniforms &u [[buffer(0)]]) {
    float4 base = card.sample(holoSampler, in.uv);   // premultiplied
    if (base.a <= 0.0) {
        return 0.0;
    }
    float3 color = base.rgb / base.a;
    float2 p = in.uv * u.size;
    float2 centered = in.uv - 0.5;
    float lum = dot(color, float3(0.299, 0.587, 0.114));

    // Diffraction grating: diagonal hue bands whose phase depends on the viewing angle,
    // so the colors sweep across the card as it tilts.
    float phase = dot(centered, float2(0.85, 0.55)) * 1.8 + u.tilt.x * 1.1 + u.tilt.y * 0.7;
    float3 holo = rainbow(phase);
    // Foil texture: fine etched lines plus a soft wave pattern; stronger on darker artwork.
    float lines = 0.6 + 0.4 * sin((p.x * 0.8 + p.y * 1.3) + u.tilt.x * 6.0);
    float waves = 0.5 + 0.5 * sin(length(centered * float2(1.0, 1.6)) * 26.0 - u.tilt.y * 5.0);
    float foilMask = u.foil * lines * mix(0.55, 1.0, waves) * mix(1.0, 0.45, lum);
    // Screen blend: brightens without washing out to grey.
    color = 1.0 - (1.0 - color) * (1.0 - holo * foilMask * 0.75);

    // Glare: a light spot that moves opposite to the tilt, like a reflection of the room.
    float2 light = float2(0.5, 0.5) - u.tilt * 0.65;
    float2 toLight = (in.uv - light) * float2(u.size.x / u.size.y, 1.0);
    float spot = exp(-dot(toLight, toLight) * 7.0);
    color += u.glare * (spot * 0.55 + pow(spot, 6.0) * 0.6);

    // Glitter: tiny cells that flash only at their own light angle.
    float2 cell = floor(p / 3.0);
    float h = holoHash(cell);
    float angle = h * 40.0 + u.tilt.x * 9.0 - u.tilt.y * 7.0;
    float2 inCell = fract(p / 3.0) - (0.3 + 0.4 * float2(holoHash(cell + 1.7), holoHash(cell + 5.3)));
    float sparkle = exp(-dot(inCell, inCell) * 40.0);   // a round point, not the whole cell
    float flash = pow(saturate(sin(angle)), 40.0) * step(0.55, h) * sparkle;
    color += u.glitter * flash * rainbow(h * 3.0 + phase) * 1.4;

    // Fresnel-like rim: edges catch more light when tilted.
    float2 edge = min(in.uv, 1.0 - in.uv) * u.size;
    float rim = exp(-min(edge.x, edge.y) / 6.0) * length(u.tilt) * 0.35;
    color += rim;

    return float4(saturate(color) * base.a, base.a);
}
