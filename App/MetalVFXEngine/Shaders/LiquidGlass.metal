//
//  LiquidGlass.metal
//  controller
//
//  A draggable liquid-glass lens: refraction with a magnifying center and a bending rim,
//  chromatic dispersion, frosted blur from snapshot mipmaps, rim lighting and a soft shadow.
//

#include <metal_stdlib>
using namespace metal;

// Keep in sync with `GlassUniforms` in LiquidGlassLensView.swift.
struct GlassUniforms {
    float2 viewSize;       // lens view size, points
    float2 shapeSize;      // glass shape at rest, points
    float2 axis;           // unit direction of the stretch (drag direction)
    float  stretch;        // 0 = round, 0.4 = strongly pulled along `axis`
    float  pad;
    float2 snapshotOrigin; // lens view's (0, 0) inside the snapshot, points
    float2 snapshotSize;   // snapshot size, points
    float  cornerRadius;
    float  refraction;     // how far the rim bends the background, points
    float  zoom;           // magnification in the middle
    float  blur;           // mip level for the frost
    float  dispersion;     // 0…1 chromatic split at the rim
    float  pressed;        // 0…1, brighter while touched
    float4 tint;           // straight rgb + strength
};

struct GlassOut {
    float4 position [[position]];
    float2 uv;
};

constexpr sampler glassSampler(coord::normalized, address::clamp_to_edge, filter::linear, mip_filter::linear);

static float sdGlass(float2 p, float2 halfSize, float radius) {
    float2 q = abs(p) - halfSize + radius;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

vertex GlassOut glass_vertex(uint vid [[vertex_id]]) {
    float2 pos = float2((vid << 1) & 2, vid & 2);
    GlassOut out;
    out.position = float4(pos * 2.0 - 1.0, 0.0, 1.0);
    out.uv = float2(pos.x, 1.0 - pos.y);
    return out;
}

fragment float4 glass_fragment(GlassOut in [[stage_in]],
                               texture2d<float> backdrop [[texture(0)]],
                               constant GlassUniforms &u [[buffer(0)]]) {
    float2 p = in.uv * u.viewSize;
    float2 rel = p - u.viewSize * 0.5;
    // Liquid stretch: elongate along the drag direction and thin out across it (area roughly kept).
    float2 perp = float2(-u.axis.y, u.axis.x);
    float2 squash = float2(1.0 + u.stretch, 1.0 / (1.0 + u.stretch * 0.6));
    float2 inAxis = float2(dot(rel, u.axis), dot(rel, perp)) / squash;
    float2 q = inAxis.x * u.axis + inAxis.y * perp;
    float2 halfSize = u.shapeSize * 0.5;
    float radius = min(u.cornerRadius, min(halfSize.x, halfSize.y));
    float d = sdGlass(q, halfSize, radius);

    // Outside: a soft contact shadow, offset downwards.
    if (d > 0.0) {
        float2 qs = q - float2(0.0, 6.0);
        float ds = sdGlass(qs, halfSize, radius);
        float shadow = exp(-max(ds, 0.0) * max(ds, 0.0) / 120.0) * 0.22;
        return float4(0.0, 0.0, 0.0, shadow * smoothstep(0.0, 1.0, d));
    }

    // Surface normal from the distance field (points outwards), in view space.
    const float e = 0.75;
    float dx = sdGlass(q + float2(e, 0.0), halfSize, radius) - sdGlass(q - float2(e, 0.0), halfSize, radius);
    float dy = sdGlass(q + float2(0.0, e), halfSize, radius) - sdGlass(q - float2(0.0, e), halfSize, radius);
    float2 n = normalize(float2(dx, dy) + 1e-5);

    // 0 at the rim, 1 a rim-width inside: the glass is a thick slab with rounded edges.
    float rimWidth = min(halfSize.x, halfSize.y) * 0.55;
    float inside = saturate(-d / rimWidth);
    float bend = pow(1.0 - inside, 2.2);

    // Magnify the middle, and let the rounded rim bend in the background from outside the shape.
    float2 sampleRel = rel / u.zoom + n * u.refraction * bend;
    float2 base = (u.viewSize * 0.5 + u.snapshotOrigin + sampleRel) / u.snapshotSize;
    float2 split = n * u.refraction * bend * u.dispersion * 0.35 / u.snapshotSize;
    float lod = u.blur * (0.6 + 0.4 * inside);
    float r = backdrop.sample(glassSampler, base + split, level(lod)).r;
    float g = backdrop.sample(glassSampler, base, level(lod)).g;
    float b = backdrop.sample(glassSampler, base - split, level(lod)).b;
    float3 color = float3(r, g, b);

    // Tint and a touch of brightness, like real glass catching ambient light.
    color = mix(color, u.tint.rgb, u.tint.a) * (1.04 + 0.06 * u.pressed);

    // Rim light: bright on the top-left edge, a softer bounce on the bottom-right.
    float rimLight = pow(1.0 - inside, 7.0);
    float key = saturate(dot(n, normalize(float2(-0.6, -0.8))));
    float bounce = saturate(dot(n, normalize(float2(0.6, 0.8))));
    color += rimLight * (key * 0.85 + bounce * 0.35) * (1.0 + 0.5 * u.pressed);
    // Thin inner edge shadow gives the slab its thickness.
    color *= 1.0 - 0.12 * exp(d * 1.2) * (1.0 - key);

    float aa = 1.0 - smoothstep(-1.0, 0.0, d);
    return float4(saturate(color) * aa, aa);
}
