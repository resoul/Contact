//
//  LiquidUI.metal
//  controller
//
//  Shaders for the Liquid UI controls (MetalVFXEngine/LiquidUI): the odometer digits, clay buttons,
//  the liquid heart, ink bleeding out of a text field, the theme reveal, tilt-lit skeletons and
//  kinetic type. All of them draw one full-view triangle; coordinates are points, top-left origin.
//

#include <metal_stdlib>
using namespace metal;

struct LiquidUIOut {
    float4 position [[position]];
    float2 uv;
};

vertex LiquidUIOut liquid_ui_vertex(uint vid [[vertex_id]]) {
    float2 pos = float2((vid << 1) & 2, vid & 2);
    LiquidUIOut out;
    out.position = float4(pos * 2.0 - 1.0, 0.0, 1.0);
    out.uv = float2(pos.x, 1.0 - pos.y);
    return out;
}

static float uiHash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static float uiNoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 w = f * f * (3.0 - 2.0 * f);
    return mix(mix(uiHash(i), uiHash(i + float2(1, 0)), w.x),
               mix(uiHash(i + float2(0, 1)), uiHash(i + float2(1, 1)), w.x), w.y);
}

static float uiFbm(float2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; ++i) {
        v += a * uiNoise(p);
        p = p * 2.03 + 11.7;
        a *= 0.5;
    }
    return v;
}

static float uiRoundedBox(float2 p, float2 halfSize, float radius) {
    float2 q = abs(p) - halfSize + radius;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

// =====================================================================
// MARK: - Odometer
// =====================================================================

// Keep in sync with `OdometerUniforms` in OdometerStepper.swift.
struct OdometerUniforms {
    float2 viewport;    // px
    float  scale;
    uint   digitCount;
    float4 color;       // straight rgb + alpha
    float2 cell;        // one digit, points
    float2 origin;      // top-left of the rightmost-aligned digit row, points
};

// Keep in sync with `OdometerDigit` in OdometerStepper.swift.
struct OdometerDigit {
    float position;     // continuous 0…10 (wraps), which digit is showing
    float blur;         // motion blur, in digits
    float alpha;
    float unused;
};

constexpr sampler odometerSampler(coord::normalized, address::repeat, filter::linear);

fragment float4 odometer_fragment(LiquidUIOut in [[stage_in]],
                                  texture2d<float> atlas [[texture(0)]],
                                  constant OdometerUniforms &u [[buffer(0)]],
                                  constant OdometerDigit *digits [[buffer(1)]]) {
    float2 p = in.position.xy / u.scale - u.origin;
    if (p.x < 0.0 || p.y < 0.0 || p.y > u.cell.y) {
        return float4(0.0);
    }
    uint index = uint(p.x / u.cell.x);
    if (index >= u.digitCount) {
        return float4(0.0);
    }
    OdometerDigit d = digits[index];
    float2 local = float2(p.x / u.cell.x - float(index), p.y / u.cell.y);
    // The atlas is a vertical strip 0…9; repeat addressing wraps 9 → 0 seamlessly.
    float alpha = 0.0;
    const int taps = 9;
    for (int k = 0; k < taps; ++k) {
        float offset = (float(k) / float(taps - 1) - 0.5) * d.blur;
        float v = (d.position + local.y + offset) / 10.0;
        alpha += atlas.sample(odometerSampler, float2(local.x, v)).a;
    }
    alpha /= float(taps);
    // Digits roll out of view through soft top and bottom edges.
    float edges = smoothstep(0.0, 0.2, local.y) * smoothstep(1.0, 0.8, local.y);
    alpha *= edges * d.alpha * u.color.a;
    return float4(u.color.rgb * alpha, alpha);
}

// =====================================================================
// MARK: - Clay button
// =====================================================================

// Keep in sync with `ClayUniforms` in ClayButton.swift.
struct ClayUniforms {
    float2 viewport;    // px
    float  scale;
    float  depth;       // 0 rest, 1 pressed in, < 0 bulging out on the rebound
    float4 rect;        // button: x, y, width, height, points
    float4 color;       // straight rgb
    float2 press;       // where the finger is, points
    float2 light;       // toward the light, screen space (y down)
    float  radius;      // corner radius
    float  bevel;       // how far in the rounded edge reaches
    float  pressRadius; // size of the dent
    float  time;
};

// A soft slab: a quarter-round dome along the edge, minus a gaussian dent under the finger.
static float clayHeight(float2 p, constant ClayUniforms &u) {
    float2 halfSize = u.rect.zw * 0.5;
    float d = uiRoundedBox(p - (u.rect.xy + halfSize), halfSize, u.radius);
    float s = saturate(-d / u.bevel);
    float dome = sqrt(max(1.0 - (1.0 - s) * (1.0 - s), 0.0)) * u.bevel * 0.55;
    float2 toPress = p - u.press;
    float dent = u.depth * 6.0 * exp(-dot(toPress, toPress) / (u.pressRadius * u.pressRadius));
    return dome - dent;
}

fragment float4 clay_fragment(LiquidUIOut in [[stage_in]],
                              constant ClayUniforms &u [[buffer(0)]]) {
    float2 p = in.position.xy / u.scale;
    float2 halfSize = u.rect.zw * 0.5;
    float2 center = u.rect.xy + halfSize;
    float d = uiRoundedBox(p - center, halfSize, u.radius);
    float pixel = 1.0 / u.scale;
    float2 lightDir = normalize(u.light);

    // Contact shadow, cast away from the light; it tightens as the button is pushed in.
    float2 shadowOffset = -lightDir * (6.0 - 3.5 * max(u.depth, 0.0)) + float2(0.0, 2.0);
    float ds = uiRoundedBox(p - center - shadowOffset, halfSize, u.radius);
    float blur = 8.0 - 3.0 * max(u.depth, 0.0);
    float shadow = 0.22 * exp(-max(ds, 0.0) * max(ds, 0.0) / (2.0 * blur * blur));

    float alpha = 1.0 - smoothstep(-0.75 * pixel, 0.75 * pixel, d);
    if (alpha <= 0.0) {
        return float4(0.0, 0.0, 0.0, shadow);
    }

    const float e = 0.6;
    float hx = clayHeight(p + float2(e, 0.0), u) - clayHeight(p - float2(e, 0.0), u);
    float hy = clayHeight(p + float2(0.0, e), u) - clayHeight(p - float2(0.0, e), u);
    float3 n = normalize(float3(-hx / (2.0 * e), -hy / (2.0 * e), 1.0));
    float3 l = normalize(float3(lightDir, 0.9));
    float diffuse = 0.5 + 0.5 * dot(n, l);
    float spec = pow(saturate(dot(n, normalize(l + float3(0.0, 0.0, 1.0)))), 36.0) * 0.32;
    // The dent collects a little shade at its bottom.
    float2 toPress = p - u.press;
    float occlusion = 1.0 - 0.22 * max(u.depth, 0.0) * exp(-dot(toPress, toPress) / (u.pressRadius * u.pressRadius * 0.5));
    float3 color = u.color.rgb * (0.62 + 0.55 * diffuse) * occlusion + spec;
    float4 button = float4(saturate(color) * alpha, alpha);
    return button + float4(0.0, 0.0, 0.0, shadow) * (1.0 - alpha);
}

// =====================================================================
// MARK: - Liquid heart
// =====================================================================

// Keep in sync with `HeartUniforms` in LikeButton.swift.
struct HeartUniforms {
    float2 viewport;    // px
    float  scale;
    float  level;       // 0 empty … 1 full
    float2 center;      // points
    float  size;        // heart height, points
    float  slosh;       // how hard the liquid moves
    float4 color;       // straight rgb
    float  time;
    float  stroke;      // outline width, points
    float2 unused;
};

// Inigo Quilez's heart: tip at the origin, lobes up to y ≈ 1.
static float sdHeart(float2 p) {
    p.x = abs(p.x);
    if (p.y + p.x > 1.0) {
        return length(p - float2(0.25, 0.75)) - sqrt(2.0) / 4.0;
    }
    float2 a = p - float2(0.0, 1.0);
    float2 b = p - 0.5 * max(p.x + p.y, 0.0);
    return sqrt(min(dot(a, a), dot(b, b))) * sign(p.x - p.y);
}

fragment float4 heart_fragment(LiquidUIOut in [[stage_in]],
                               constant HeartUniforms &u [[buffer(0)]]) {
    float2 p = in.position.xy / u.scale;
    // Heart space: y up, the tip at the bottom.
    float2 q = float2(p.x - u.center.x, u.center.y + u.size * 0.5 - p.y) / u.size + float2(0.0, 0.05);
    float d = sdHeart(q) * u.size;   // back to points
    float pixel = 1.0 / u.scale;
    float inside = 1.0 - smoothstep(-0.75 * pixel, 0.75 * pixel, d);
    float outline = (1.0 - smoothstep(u.stroke * 0.5 - pixel, u.stroke * 0.5 + pixel, abs(d + u.stroke * 0.5))) ;

    // The liquid surface sloshes; the level is measured from the tip (q.y = 0) to the top (≈1.05).
    float wave = (sin(q.x * 13.0 + u.time * 7.0) * 0.02 + sin(q.x * 7.0 - u.time * 4.3) * 0.015) * (0.4 + min(abs(u.slosh), 2.0));
    float surface = u.level * 1.08 - 0.02 + wave * smoothstep(0.0, 0.08, u.level) * smoothstep(1.0, 0.92, u.level);
    float wet = (1.0 - smoothstep(surface - 0.006, surface + 0.006, q.y)) * inside;

    // Liquid shading: darker toward the bottom, a glossy highlight on the upper left lobe.
    float3 liquid = u.color.rgb * mix(0.8, 1.12, saturate(q.y));
    float highlight = smoothstep(0.16, 0.0, length(q - float2(-0.27, 0.8))) * 0.45;
    float rim = smoothstep(0.03, 0.0, abs(q.y - surface)) * 0.25 * wet;
    liquid += highlight + rim;

    float3 color = mix(u.color.rgb, liquid, wet);
    float alpha = max(wet, max(outline, inside * 0.08));
    return float4(saturate(color) * alpha, alpha);
}

// =====================================================================
// MARK: - Ink bleeding out of a field / success ripple
// =====================================================================

// Keep in sync with `InkBleedUniforms` in InkPasswordField.swift.
struct InkBleedUniforms {
    float2 viewport;    // px
    float  scale;
    float  progress;    // 0 → 1 over the effect
    float4 rect;        // the field: x, y, width, height, points
    float4 color;       // straight rgb
    float  radius;      // field corner radius
    uint   mode;        // 0 ink, 1 ripple
    float  seed;
    float  unused;
};

fragment float4 ink_bleed_fragment(LiquidUIOut in [[stage_in]],
                                   constant InkBleedUniforms &u [[buffer(0)]]) {
    float2 p = in.position.xy / u.scale;
    float2 halfSize = u.rect.zw * 0.5;
    float d = uiRoundedBox(p - (u.rect.xy + halfSize), halfSize, u.radius);
    float t = u.progress;
    float alpha = 0.0;
    if (u.mode == 0u) {
        if (d < -1.0) {
            return float4(0.0);
        }
        // A ragged ink front soaking outward from the field's edge, with tendrils.
        float spread = (1.0 - pow(1.0 - saturate(t / 0.55), 3.0)) * 34.0;
        float n = uiFbm(p * 0.07 + u.seed) - 0.5;
        float tendrils = (uiFbm(p * 0.25 + u.seed * 3.1) - 0.5) * 10.0;
        float front = spread * (1.0 + n * 1.4) + tendrils * saturate(t * 3.0);
        alpha = 1.0 - smoothstep(front - 6.0, front, d);
        // Pigment pools at the front as it dries, like real ink.
        alpha *= 0.45 + 0.55 * smoothstep(front - 14.0, front - 1.0, d);
        alpha *= 1.0 - smoothstep(0.55, 1.0, t);
        alpha *= 0.85;
    } else {
        // Two soft rings racing out from the field.
        for (int i = 0; i < 2; ++i) {
            float r = t * 56.0 - float(i) * 16.0;
            float ring = exp(-(d - r) * (d - r) / (2.0 * 3.0 * 3.0));
            alpha += ring * step(0.0, d) * (1.0 - t) * (r > 0.0 ? 1.0 : 0.0);
        }
        alpha = saturate(alpha) * 0.8;
    }
    return float4(u.color.rgb * alpha, alpha);
}

static float uiSmin(float a, float b, float k) {
    float h = saturate(0.5 + 0.5 * (b - a) / k);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// =====================================================================
// MARK: - Theme reveal
// =====================================================================

// Keep in sync with `ThemeRevealUniforms` in LiquidThemeReveal.swift.
struct ThemeRevealUniforms {
    float2 viewport;    // px
    float  scale;
    float  radius;      // how far the new theme has spread, points
    float2 origin;      // where it started, points
    float  time;
    float  seed;
};

constexpr sampler revealSampler(coord::normalized, address::clamp_to_edge, filter::linear);

// The old screen, with a liquid hole growing in it: a wobbling front plus droplets thrown ahead,
// merged with a smooth minimum. Just outside the front the old screen bends and catches the light.
fragment float4 theme_reveal_fragment(LiquidUIOut in [[stage_in]],
                                      texture2d<float> oldScreen [[texture(0)]],
                                      constant ThemeRevealUniforms &u [[buffer(0)]]) {
    float2 size = u.viewport / u.scale;
    float2 p = in.position.xy / u.scale;
    float2 v = p - u.origin;
    float dist = length(v);
    float angle = atan2(v.y, v.x);
    float wobble = (uiFbm(float2(angle * 2.4 + u.seed, u.time * 0.9)) - 0.5) * (22.0 + u.radius * 0.07);
    float edge = dist - (u.radius + wobble);
    for (int k = 0; k < 12; ++k) {
        float h1 = uiHash(float2(float(k), u.seed)), h2 = uiHash(float2(u.seed, float(k) * 1.7));
        float a = h1 * 6.2831;
        float ahead = 18.0 + 40.0 * h2;
        float2 c = u.origin + float2(cos(a), sin(a)) * (u.radius + ahead);
        float r = (4.0 + 11.0 * h2) * smoothstep(0.0, 60.0, u.radius);
        edge = uiSmin(edge, length(p - c) - r, 12.0);
    }
    float pixel = 1.0 / u.scale;
    float alpha = smoothstep(-pixel, pixel, edge);
    if (alpha <= 0.0) {
        return float4(0.0);
    }
    float2 outward = dist > 0.001 ? v / dist : float2(0.0);
    float rim = exp(-max(edge, 0.0) / 6.0);
    float2 uv = (p - outward * rim * 7.0) / size;
    float4 color = oldScreen.sample(revealSampler, uv);
    // A glossy meniscus right at the edge, and a soft shade just behind it.
    color.rgb = color.rgb * (1.0 - 0.18 * exp(-(edge - 10.0) * (edge - 10.0) / 40.0)) + rim * 0.22;
    return float4(saturate(color.rgb) * alpha, alpha);
}

// =====================================================================
// MARK: - Tilt-lit skeletons
// =====================================================================

// Keep in sync with `SkeletonUniforms` in SkeletonShimmerView.swift.
struct SkeletonUniforms {
    float2 viewport;    // px
    float  scale;
    uint   count;
    float4 base;        // placeholder color
    float4 sheen;       // highlight color
    float2 gravity;     // screen-space gravity, (0, 1) upright
    float  time;
    float  unused;
};

// Keep in sync with `SkeletonBlock` in SkeletonShimmerView.swift.
struct SkeletonBlock {
    float4 rect;        // x, y, width, height
    float4 params;      // corner radius, unused…
};

// Placeholders lit like glass: a broad highlight band whose angle and position follow the tilt,
// so it slides over the blocks as the phone moves, plus a thin rim on the edges facing the light.
fragment float4 skeleton_fragment(LiquidUIOut in [[stage_in]],
                                  constant SkeletonUniforms &u [[buffer(0)]],
                                  constant SkeletonBlock *blocks [[buffer(1)]]) {
    float2 p = in.position.xy / u.scale;
    float d = 1e5;
    for (uint i = 0; i < u.count; ++i) {
        float2 halfSize = blocks[i].rect.zw * 0.5;
        d = min(d, uiRoundedBox(p - (blocks[i].rect.xy + halfSize), halfSize, blocks[i].params.x));
    }
    float pixel = 1.0 / u.scale;
    float alpha = 1.0 - smoothstep(-0.75 * pixel, 0.75 * pixel, d);
    if (alpha <= 0.0) {
        return float4(0.0);
    }
    float2 size = u.viewport / u.scale;
    float2 light = normalize(float2(-u.gravity.x, -max(u.gravity.y, 0.2)) + float2(0.35, 0.0));
    float2 across = float2(-light.y, light.x);
    // The band's position comes from the tilt, not from time.
    float along = dot(p - size * 0.5, across);
    float center = u.gravity.x * size.x * 1.1;
    float band = exp(-(along - center) * (along - center) / (2.0 * 70.0 * 70.0));
    float rim = smoothstep(-3.0, 0.0, d) * 0.25;
    float3 color = mix(u.base.rgb, u.sheen.rgb, saturate(band * 0.75 + rim));
    return float4(color * alpha, alpha);
}

// =====================================================================
// MARK: - Kinetic type
// =====================================================================

// Keep in sync with `KineticUniforms` in KineticTextView.swift.
struct KineticUniforms {
    float2 viewport;    // px
    float  scale;
    float  reveal;      // 0 → 1: the new text fills with liquid from the bottom
    float4 color;       // straight rgb
    float  dissolve;    // 0 → 1: the old text crumbles away
    float  time;
    float2 unused;
};

constexpr sampler textSampler(coord::normalized, address::clamp_to_zero, filter::linear);

fragment float4 kinetic_text_fragment(LiquidUIOut in [[stage_in]],
                                      texture2d<float> newText [[texture(0)]],
                                      texture2d<float> oldText [[texture(1)]],
                                      constant KineticUniforms &u [[buffer(0)]]) {
    float2 uv = in.uv;
    float height = 1.0 - uv.y;   // 0 at the bottom

    // New text: liquid rising inside the letters, with a sloshing surface and a bright wet line.
    float glyph = newText.sample(textSampler, uv).a;
    float wave = sin(uv.x * 28.0 + u.time * 6.0) * 0.03 + sin(uv.x * 11.0 - u.time * 3.7) * 0.025;
    float level = u.reveal * 1.25 - 0.12 + wave * (1.0 - smoothstep(0.85, 1.0, u.reveal));
    float filled = smoothstep(level + 0.012, level - 0.012, height);
    float line = exp(-(height - level) * (height - level) / 0.0006) * (1.0 - smoothstep(0.9, 1.0, u.reveal));
    float ghost = 0.07 * (1.0 - u.reveal);
    float newAlpha = glyph * max(filled, ghost);
    float3 newColor = u.color.rgb + line * 0.6;

    // Old text: crumbles in little cells, left to right, each drifting up as it goes, glinting.
    float2 cell = floor(in.position.xy / (3.0 * u.scale / 2.0));
    float n = uiHash(cell);
    float q = saturate((u.dissolve * 1.4 - (n * 0.6 + uv.x * 0.4)) / 0.3);
    float2 drift = float2((n - 0.5) * 0.04, 0.06) * q * q;
    float oldGlyph = oldText.sample(textSampler, uv + drift).a;
    float oldAlpha = oldGlyph * (1.0 - q) * step(u.dissolve, 0.999);
    float glint = oldGlyph * smoothstep(0.0, 0.15, q) * smoothstep(0.5, 0.2, q) * 0.8;

    float alpha = saturate(newAlpha + oldAlpha);
    float3 rgb = newColor * newAlpha + u.color.rgb * oldAlpha + glint;
    return float4(rgb, max(alpha, glint * 0.5));
}
