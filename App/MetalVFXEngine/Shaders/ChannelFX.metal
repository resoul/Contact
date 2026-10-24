//
//  ChannelFX.metal
//  controller
//
//  Shaders for the channel feed (MetalVFXEngine/ChannelFeed):
//  - Wallpaper: a four-color gradient whose color points step around a ring on every new post,
//    under a doodle pattern that shifts with the phone's tilt; a ripple can run through it.
//  - Glass: the header and bottom controls as real glass — they refract the feed and the wallpaper
//    beneath them, blur it, and catch a rim light that stays put as the phone tilts.
//  - Dust: a view crumbles into grains that drift off and fade.
//  - Ink spoiler: hidden text under living ink, wiped away with a finger.
//  All coordinates are in points, top-left origin.
//

#include <metal_stdlib>
using namespace metal;

struct ChannelOut {
    float4 position [[position]];
    float2 uv;
};

vertex ChannelOut channel_vertex(uint vid [[vertex_id]]) {
    float2 pos = float2((vid << 1) & 2, vid & 2);
    ChannelOut out;
    out.position = float4(pos * 2.0 - 1.0, 0.0, 1.0);
    out.uv = float2(pos.x, 1.0 - pos.y);
    return out;
}

static float chHash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static float chNoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 w = f * f * (3.0 - 2.0 * f);
    return mix(mix(chHash(i), chHash(i + float2(1, 0)), w.x),
               mix(chHash(i + float2(0, 1)), chHash(i + float2(1, 1)), w.x), w.y);
}

static float chFbm(float2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; ++i) {
        v += a * chNoise(p);
        p = p * 2.03 + 11.7;
        a *= 0.5;
    }
    return v;
}

static float chRoundedBox(float2 p, float2 halfSize, float radius) {
    float2 q = abs(p) - halfSize + radius;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

static float2 chToClip(float2 pt, float2 viewport, float scale) {
    float2 ndc = pt * scale / viewport * 2.0 - 1.0;
    return float2(ndc.x, -ndc.y);
}

constant float2 chCorners[4] = { float2(0, 0), float2(1, 0), float2(0, 1), float2(1, 1) };

// =====================================================================
// MARK: - Wallpaper
// =====================================================================

// Keep in sync with `WallpaperUniforms` in ChannelWallpaperView.swift.
struct WallpaperUniforms {
    float2 viewport;        // px of the target
    float  scale;
    float  patternAlpha;
    float2 size;            // the wallpaper (screen), points
    float2 origin;          // the target's top-left in wallpaper coordinates, points
    float4 colors[4];       // straight srgb
    float4 points01;        // gradient points 0 and 1, normalized
    float4 points23;        // gradient points 2 and 3, normalized
    float2 patternOffset;   // parallax of the doodles, points
    float2 gradientOffset;  // parallax of the gradient (a deeper layer, moves less), points
    float2 rippleOrigin;
    float  rippleRadius;
    float  rippleStrength;
    float  tile;            // pattern tile size, points
    float  time;
    float  night;           // 0 day … 1 night: sunset glow on the way, then stars (chat wallpaper only)
    float  unused;
};

constexpr sampler wallpaperSampler(coord::normalized, address::repeat, filter::linear, mip_filter::linear);

// Telegram-style gradient: every pixel is a weighted mix of four colors by its distance to their
// points, with a gentle swirl around the middle.
static float3 wallpaperGradient(float2 p, constant WallpaperUniforms &u) {
    float2 uv = (p + u.gradientOffset) / u.size;
    float2 c = uv - 0.5;
    float swirl = 0.35 * (1.0 - smoothstep(0.0, 0.7, length(c)));
    float s = sin(swirl), co = cos(swirl);
    uv = float2(c.x * co - c.y * s, c.x * s + c.y * co) + 0.5;
    float2 pts[4] = { u.points01.xy, u.points01.zw, u.points23.xy, u.points23.zw };
    float3 color = float3(0.0);
    float total = 0.0;
    for (int i = 0; i < 4; ++i) {
        float d = max(0.0, 0.9 - distance(uv, pts[i]));
        float w = d * d * d * d;
        color += pow(u.colors[i].rgb, float3(2.2)) * w;
        total += w;
    }
    return pow(color / max(total, 1e-5), float3(1.0 / 2.2));
}

// Wallpaper color at `p` (wallpaper points). `lod` blurs the doodles (for glass).
static float3 wallpaperColor(float2 p, constant WallpaperUniforms &u, texture2d<float> pattern, float lod) {
    // A ripple ring pushes the doodles outward a little and lights them up as it passes.
    float2 fromRipple = p - u.rippleOrigin;
    float rippleDistance = length(fromRipple);
    float ring = exp(-pow((rippleDistance - u.rippleRadius) / 46.0, 2.0)) * u.rippleStrength;
    float2 pushed = p - fromRipple / max(rippleDistance, 1.0) * ring * 9.0;

    float3 color = wallpaperGradient(pushed, u);
    float doodle = pattern.sample(wallpaperSampler, (pushed + u.patternOffset) / u.tile, level(lod)).a;
    color += doodle * u.patternAlpha * (1.0 + ring * 2.5);
    color += ring * 0.05;
    return color;
}

fragment float4 channel_wallpaper_fragment(ChannelOut in [[stage_in]],
                                           constant WallpaperUniforms &u [[buffer(0)]],
                                           texture2d<float> pattern [[texture(0)]]) {
    float2 p = in.position.xy / u.scale + u.origin;
    float3 color = wallpaperColor(p, u, pattern, 0.0);
    if (u.night > 0.001) {
        float2 uv = p / u.size;
        // Dusk: a warm glow rises from the bottom while the palette turns, strongest half way.
        float dusk = sin(saturate(u.night) * 3.14159);
        color += float3(1.0, 0.45, 0.2) * dusk * 0.3 * smoothstep(0.25, 1.0, uv.y);
        // Stars come out one by one, thicker towards the top, and twinkle.
        float cellSize = 26.0;
        float2 cell = floor(p / cellSize);
        float h = chHash(cell + 7.3);
        if (h > 0.88) {
            float2 center = (cell + 0.2 + 0.6 * float2(chHash(cell + 1.1), chHash(cell + 2.7))) * cellSize;
            float d = length(p - center);
            float threshold = 0.25 + 0.65 * chHash(cell + 5.5);
            float shown = smoothstep(threshold, threshold + 0.12, u.night) * (1.0 - uv.y * 0.75);
            float twinkle = 0.55 + 0.45 * sin(u.time * (1.3 + 3.0 * h) + h * 40.0);
            float star = exp(-d * d / 0.8) + exp(-d * d / 9.0) * 0.22;
            color += star * twinkle * shown * float3(1.0, 0.96, 0.88);
        }
    }
    color += (chHash(in.position.xy) - 0.5) / 255.0;   // dither: no banding in the dark gradient
    return float4(saturate(color), 1.0);
}

// =====================================================================
// MARK: - Glass
// =====================================================================

// Keep in sync with `FeedGlassUniforms` in ChannelGlassView.swift.
struct FeedGlassUniforms {
    float2 viewport;        // px
    float  scale;
    uint   count;
    float2 snapshotOrigin;  // the snapshot's top-left in this view, points
    float2 snapshotSize;    // points
    float2 gravity;         // screen-plane gravity: the light sits opposite
    float  refraction;      // how far the rim bends what is behind, points
    float  time;
    float4 tint;            // straight rgb + strength
};

// Keep in sync with `FeedGlassShape` in ChannelGlassView.swift.
struct FeedGlassShape {
    float4 rect;            // x, y, width, height
    float4 params;          // corner radius, opacity, unused, unused
};

constexpr sampler glassBackdropSampler(coord::normalized, address::clamp_to_edge, filter::linear, mip_filter::linear);

static float glassField(float2 p, constant FeedGlassUniforms &g, constant FeedGlassShape *shapes, thread float &opacity) {
    float d = 1e5;
    opacity = 0.0;
    for (uint i = 0; i < g.count; ++i) {
        FeedGlassShape s = shapes[i];
        if (s.params.y <= 0.001) {
            continue;
        }
        float2 halfSize = s.rect.zw * 0.5;
        float di = chRoundedBox(p - s.rect.xy - halfSize, halfSize, min(s.params.x, min(halfSize.x, halfSize.y)));
        if (di < d) {
            d = di;
            opacity = s.params.y;
        }
    }
    return d;
}

fragment float4 channel_glass_fragment(ChannelOut in [[stage_in]],
                                       constant FeedGlassUniforms &g [[buffer(0)]],
                                       constant FeedGlassShape *shapes [[buffer(1)]],
                                       constant WallpaperUniforms &w [[buffer(2)]],
                                       texture2d<float> snapshot [[texture(0)]],
                                       texture2d<float> pattern [[texture(1)]]) {
    float2 p = in.position.xy / g.scale;
    float opacity;
    float d = glassField(p, g, shapes, opacity);
    float pixel = 1.0 / g.scale;
    if (d > 0.0) {
        // A soft contact shadow just under the glass.
        float o;
        float ds = glassField(p - float2(0.0, 3.0), g, shapes, o);
        float shadow = exp(-max(ds, 0.0) * max(ds, 0.0) / 60.0) * 0.28 * o;
        return float4(0.0, 0.0, 0.0, shadow * smoothstep(0.0, 1.5, d));
    }

    const float e = 0.6;
    float o2;
    float2 grad = float2(glassField(p + float2(e, 0), g, shapes, o2) - glassField(p - float2(e, 0), g, shapes, o2),
                         glassField(p + float2(0, e), g, shapes, o2) - glassField(p - float2(0, e), g, shapes, o2));
    float2 n = normalize(grad + 1e-5);

    // A thick slab with rounded edges: flat in the middle, bending hard at the rim.
    float rim = 14.0;
    float inside = saturate(-d / rim);
    float bend = pow(1.0 - inside, 2.4);
    float2 sp = p + n * g.refraction * bend - n * 2.0 * inside;

    // What is behind: the feed (snapshot, blurred via mips) over the wallpaper (drawn right here).
    float2 suv = (sp - g.snapshotOrigin) / g.snapshotSize;
    float2 split = n * g.refraction * bend * 0.25 / g.snapshotSize;
    float lod = 1.6;   // the snapshot is half resolution, so one mip level less
    float4 feedR = snapshot.sample(glassBackdropSampler, suv + split, level(lod));
    float4 feedG = snapshot.sample(glassBackdropSampler, suv, level(lod));
    float4 feedB = snapshot.sample(glassBackdropSampler, suv - split, level(lod));
    float2 wp = sp + w.origin;
    float3 wall = wallpaperColor(wp, w, pattern, 2.5);
    float3 color = float3(feedR.r + wall.r * (1.0 - feedR.a),
                          feedG.g + wall.g * (1.0 - feedG.a),
                          feedB.b + wall.b * (1.0 - feedB.a));

    // Tinted, a little lifted, like frosted glass on a dark theme.
    color = mix(color, g.tint.rgb, g.tint.a) * 1.05 + 0.025;

    // Rim light from the side opposite gravity: tilt the phone and it slides around the edge.
    float2 lightDir = normalize(-g.gravity + float2(-0.25, 0.0));
    float key = saturate(dot(n, lightDir));
    float bounce = saturate(dot(n, -lightDir));
    float rimLight = pow(1.0 - inside, 5.0);
    color += rimLight * (key * 0.55 + bounce * 0.18);
    // A faint sheen across the face, also following the tilt.
    float sheen = exp(-pow(dot(p, normalize(float2(1.0, 0.35))) * 0.02 - g.gravity.x * 3.0 - 2.0, 2.0) * 2.0);
    color += sheen * 0.035 * inside;
    // Hairline edge.
    color += (1.0 - smoothstep(0.0, 1.0, abs(d + 0.6))) * 0.10;

    float aa = (1.0 - smoothstep(-pixel, 0.0, d)) * opacity;
    return float4(saturate(color) * aa, aa);
}

// Keep in sync with `FeedQuadUniforms` in ChannelGlassView.swift.
struct FeedQuadUniforms {
    float2 viewport;    // the target, points
    float2 unused;
    float4 rect;        // where the texture goes: x, y, width, height, points
};

struct FeedQuadOut {
    float4 position [[position]];
    float2 uv;
};

// One cached post snapshot laid out where the post is now (ChannelGlassView's backdrop).
vertex FeedQuadOut channel_quad_vertex(uint vid [[vertex_id]], constant FeedQuadUniforms &u [[buffer(0)]]) {
    FeedQuadOut out;
    out.uv = chCorners[vid];
    float2 pt = u.rect.xy + out.uv * u.rect.zw;
    out.position = float4(chToClip(pt, u.viewport, 1.0), 0.0, 1.0);
    return out;
}

fragment float4 channel_quad_fragment(FeedQuadOut in [[stage_in]], texture2d<float> image [[texture(0)]]) {
    constexpr sampler quadSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    return image.sample(quadSampler, in.uv);
}

// =====================================================================
// MARK: - Dust
// =====================================================================

// Keep in sync with `DustGrain` in DustAnimator.swift.
struct DustGrain {
    float2 position;
    float2 velocity;
    float4 color;       // premultiplied
    float  release;     // seconds after the start when this grain lets go
    float  seed;
    float  alive;
    float  life;        // seconds it lives after letting go
};

// Keep in sync with `DustUniforms` in DustAnimator.swift.
struct DustUniforms {
    float2 viewport;    // px
    float  scale;
    float  time;
    float4 element;     // x, y, width, height
    float  grain;
    uint   columns;
    uint   rows;
    float  releaseWindow;
    float2 wind;        // drift, points / s
    float  gravity;     // points / s², positive = down
    float  dt;
};

constexpr sampler dustSampler(coord::normalized, address::clamp_to_edge, filter::linear);

// Left to right with a grainy front, like the view is blown away from one side.
static float dustRelease(uint2 cell, constant DustUniforms &u) {
    float x = (float(cell.x) + 0.5) / float(u.columns);
    return (x * 0.75 + chHash(float2(cell) * 1.37) * 0.25) * u.releaseWindow;
}

kernel void dust_spawn(device DustGrain *grains [[buffer(0)]],
                       constant DustUniforms &u [[buffer(1)]],
                       texture2d<float> snapshot [[texture(0)]],
                       uint id [[thread_position_in_grid]]) {
    if (id >= u.columns * u.rows) {
        return;
    }
    uint2 cell = uint2(id % u.columns, id / u.columns);
    float2 uv = (float2(cell) + 0.5) * u.grain / u.element.zw;
    DustGrain g;
    g.position = u.element.xy + (float2(cell) + 0.5) * u.grain;
    g.velocity = float2(0.0);
    g.color = snapshot.sample(dustSampler, uv, level(0.0));
    g.release = dustRelease(cell, u);
    g.seed = chHash(float2(cell) + 17.0);
    g.alive = g.color.a > 0.02 ? 1.0 : 0.0;
    g.life = 0.55 + chHash(float2(cell) + 3.1) * 0.6;
    grains[id] = g;
}

kernel void dust_update(device DustGrain *grains [[buffer(0)]],
                        constant DustUniforms &u [[buffer(1)]],
                        uint id [[thread_position_in_grid]]) {
    if (id >= u.columns * u.rows) {
        return;
    }
    DustGrain g = grains[id];
    if (g.alive == 0.0 || u.time < g.release) {
        return;
    }
    float age = u.time - g.release;
    if (all(g.velocity == 0.0)) {
        float angle = (g.seed - 0.5) * 2.4 - 1.2;
        g.velocity = u.wind * (0.4 + g.seed) + float2(cos(angle), sin(angle)) * (30.0 + 50.0 * g.seed);
    }
    // Turbulence: each grain wanders on its own little eddy.
    float2 eddy = float2(sin(age * 7.0 + g.seed * 40.0), cos(age * 5.0 + g.seed * 31.0)) * 140.0;
    g.velocity += (eddy + float2(0.0, u.gravity)) * u.dt;
    g.velocity *= max(1.0 - 1.4 * u.dt, 0.0);
    g.position += g.velocity * u.dt;
    if (age > g.life) {
        g.alive = 0.0;
    }
    grains[id] = g;
}

struct DustGrainOut {
    float4 position [[position]];
    float2 local;
    float4 color;
};

vertex DustGrainOut dust_grain_vertex(uint vid [[vertex_id]],
                                      uint iid [[instance_id]],
                                      const device DustGrain *grains [[buffer(0)]],
                                      constant DustUniforms &u [[buffer(1)]]) {
    DustGrain g = grains[iid];
    DustGrainOut out;
    out.local = chCorners[vid] * 2.0 - 1.0;
    if (g.alive == 0.0 || u.time < g.release) {
        out.position = float4(-2.0, -2.0, 0.0, 1.0);
        out.color = float4(0.0);
        return out;
    }
    float age = saturate((u.time - g.release) / g.life);
    float size = u.grain * mix(1.5, 0.6, age);
    float2 pt = g.position + out.local * size * 0.5;
    out.position = float4(chToClip(pt, u.viewport, u.scale), 0.0, 1.0);
    out.color = g.color * (1.0 - age * age);
    return out;
}

fragment float4 dust_grain_fragment(DustGrainOut in [[stage_in]]) {
    float mask = 1.0 - smoothstep(0.5, 1.0, length(in.local));
    return in.color * mask;
}

struct DustElementOut {
    float4 position [[position]];
    float2 uv;
};

// What has not crumbled yet, drawn straight from the snapshot.
vertex DustElementOut dust_element_vertex(uint vid [[vertex_id]],
                                          constant DustUniforms &u [[buffer(0)]]) {
    DustElementOut out;
    out.uv = chCorners[vid];
    float2 pt = u.element.xy + out.uv * u.element.zw;
    out.position = float4(chToClip(pt, u.viewport, u.scale), 0.0, 1.0);
    return out;
}

fragment float4 dust_element_fragment(DustElementOut in [[stage_in]],
                                      texture2d<float> snapshot [[texture(0)]],
                                      constant DustUniforms &u [[buffer(0)]]) {
    uint2 cell = uint2(in.uv * u.element.zw / u.grain);
    if (cell.x >= u.columns || cell.y >= u.rows || u.time >= dustRelease(cell, u)) {
        return float4(0.0);
    }
    return snapshot.sample(dustSampler, in.uv, level(0.0));
}

// =====================================================================
// MARK: - Ink spoiler
// =====================================================================

// Keep in sync with `SpoilerUniforms` in InkSpoilerView.swift.
struct SpoilerUniforms {
    float2 viewport;    // px
    float  scale;
    float  time;
    uint   rectCount;
    uint   stampCount;
    float  seed;
    float  unused;
    float4 reveal;      // x, y, radius of the tap reveal, unused
    float4 ink;         // straight rgb
};

fragment float4 channel_spoiler_fragment(ChannelOut in [[stage_in]],
                                         constant SpoilerUniforms &u [[buffer(0)]],
                                         constant float4 *rects [[buffer(1)]],
                                         constant float4 *stamps [[buffer(2)]]) {
    float2 p = in.position.xy / u.scale;
    float d = 1e5;
    for (uint i = 0; i < u.rectCount; ++i) {
        float2 halfSize = rects[i].zw * 0.5 + float2(2.0, 1.0);
        d = min(d, chRoundedBox(p - rects[i].xy - rects[i].zw * 0.5, halfSize, 5.0));
    }
    // The ink's outline is a little ragged, and breathes.
    float edgeNoise = (chFbm(p * 0.18 + float2(u.time * 0.4, u.seed)) - 0.5) * 3.0;
    float ink = 1.0 - smoothstep(-1.0, 1.0, d + edgeNoise);
    if (ink <= 0.0) {
        return float4(0.0);
    }

    // Wiped by the finger, and the tap reveal: holes with ragged, soaked edges.
    float holeNoise = (chFbm(p * 0.12 + u.seed * 3.0) - 0.5) * 10.0;
    float erased = 0.0;
    for (uint i = 0; i < u.stampCount; ++i) {
        float r = stamps[i].z;
        erased = max(erased, 1.0 - smoothstep(r - 5.0, r + 1.0, length(p - stamps[i].xy) + holeNoise));
    }
    float rr = u.reveal.z;
    if (rr > 0.0) {
        erased = max(erased, 1.0 - smoothstep(rr - 10.0, rr + 1.0, length(p - u.reveal.xy) + holeNoise * 1.6));
    }
    float alpha = ink * (1.0 - erased);
    if (alpha <= 0.001) {
        return float4(0.0);
    }

    // Slowly churning ink with an oil-slick sheen.
    float2 flow = p * 0.06 + float2(chFbm(p * 0.05 + u.time * 0.15), chFbm(p * 0.05 - u.time * 0.12)) * 2.0;
    float churn = chFbm(flow + u.seed);
    float3 color = u.ink.rgb * (0.75 + 0.6 * churn);
    float3 sheen = 0.5 + 0.5 * cos(6.2831 * (churn * 1.3 + float3(0.0, 0.33, 0.67)) + u.time * 0.6);
    color += sheen * 0.10 * smoothstep(0.45, 0.75, churn);

    // Glinting motes drifting in the ink, like Telegram's spoiler dust.
    float2 q = p + float2(u.time * 5.0, sin(u.time * 0.7 + p.x * 0.05) * 3.0);
    float2 cell = floor(q / 3.2);
    float h = chHash(cell + u.seed);
    float2 dotPos = (cell + 0.25 + 0.5 * float2(chHash(cell + 1.7), chHash(cell + 4.1))) * 3.2;
    float twinkle = smoothstep(0.78, 1.0, h) * (0.5 + 0.5 * sin(u.time * 4.0 + h * 50.0));
    color += exp(-dot(q - dotPos, q - dotPos) * 1.6) * twinkle * 0.9;

    // Pigment pools darker along the edge of a wiped hole.
    float pool = smoothstep(0.0, 0.5, erased) * (1.0 - smoothstep(0.5, 1.0, erased));
    color = mix(color, u.ink.rgb * 0.45, pool * 0.8);

    return float4(saturate(color) * alpha, alpha);
}
