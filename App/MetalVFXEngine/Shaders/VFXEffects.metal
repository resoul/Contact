//
//  VFXEffects.metal
//  controller
//
//  Shaders for MatrixDigitalRainView and FluidMeshGradientView.
//

#include <metal_stdlib>
using namespace metal;

// =====================================================================
// MARK: - Matrix digital rain
// =====================================================================
//
// The screen is a fixed grid of glyph cells drawn as one instanced quad per cell. Each column has
// two falling "heads"; the vertex shader moves them down and wraps them back to the top, the
// fragment shader picks a glyph from the atlas, swaps it randomly over time and shades it from the
// bright head down the fading tail.
// Keep in sync with `MatrixUniforms` in MatrixDigitalRainView.swift.
struct MatrixUniforms {
    float2 viewportSize;    // drawable size, px
    float2 cellSize;        // glyph cell, px
    float2 atlasGrid;       // glyphs per atlas row / number of atlas rows
    uint   columns;
    uint   rows;
    uint   glyphCount;
    float  time;            // seconds
    float  fallSpeed;       // px per second, before the per-column multiplier
    float  fadeSpeed;       // brightness lost per cell behind the head (exponential)
    float  glyphChangeRate; // glyph swaps per second per cell (on average)
    float4 primaryColor;    // head glyph
    float4 trailColor;      // fading tail
};

// Keep in sync with `MatrixColumn` in MatrixDigitalRainView.swift.
struct MatrixColumn {
    float2 speed;   // speed multiplier of each of the two streams
    float2 phase;   // starting offset of each stream, 0…1 of a cycle
};

struct RainVertexOut {
    float4 position [[position]];
    float2 glyphUV;                   // 0…1 inside the cell, top-left origin
    float  headDistance [[flat]];     // cells behind the nearest head (0…1 = head cell)
    float2 cell [[flat]];             // column, row
};

constexpr sampler atlasSampler(coord::normalized, address::clamp_to_edge, filter::linear);

constant float2 quadCorners[4] = { float2(0, 0), float2(1, 0), float2(0, 1), float2(1, 1) };

// Brightness below this is invisible; it also defines how long a trail is.
constant float minBrightness = 0.01;

static float hash12(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static float trailCells(constant MatrixUniforms &u) {
    return 1.0 - log(minBrightness) / max(u.fadeSpeed, 1e-3);
}

vertex RainVertexOut matrix_vertex(uint vid [[vertex_id]],
                                   uint iid [[instance_id]],
                                   constant MatrixUniforms &u [[buffer(0)]],
                                   constant MatrixColumn *columns [[buffer(1)]]) {
    uint col = iid % u.columns;
    uint row = iid / u.columns;
    MatrixColumn column = columns[col];

    // A head travels the screen plus the length of its trail, then wraps back to the top:
    // y = (time * speed + phase) % (screenHeight + trail), so the tail fully leaves before the restart.
    float trail = trailCells(u);
    float cycle = u.viewportSize.y + trail * u.cellSize.y;
    float distance = INFINITY;
    for (int s = 0; s < 2; ++s) {
        float headY = fmod(u.time * u.fallSpeed * column.speed[s] + column.phase[s] * cycle, cycle);
        float behind = headY / u.cellSize.y - float(row);    // < 0: the head hasn't reached this cell
        if (behind >= 0.0) {
            distance = min(distance, behind);
        }
    }

    RainVertexOut out;
    out.headDistance = distance;
    out.cell = float2(col, row);
    out.glyphUV = quadCorners[vid];

    if (distance > trail) {
        // Unlit cell: collapse the quad so it costs no fragment work.
        out.position = float4(-2.0, -2.0, 0.0, 1.0);
        return out;
    }
    float2 pixel = (float2(col, row) + quadCorners[vid]) * u.cellSize;
    float2 ndc = pixel / u.viewportSize * 2.0 - 1.0;
    out.position = float4(ndc.x, -ndc.y, 0.0, 1.0);
    return out;
}

fragment float4 matrix_fragment(RainVertexOut in [[stage_in]],
                                texture2d<float> atlas [[texture(0)]],
                                constant MatrixUniforms &u [[buffer(0)]]) {
    float d = in.headDistance;
    float cellSeed = hash12(in.cell);

    // Random glyph swaps: each cell has its own rhythm; the head churns much faster.
    float rate = u.glyphChangeRate * (0.3 + 1.4 * cellSeed) * (d < 1.0 ? 8.0 : 1.0);
    float epoch = floor(u.time * rate + cellSeed * 17.0);
    uint glyph = min(uint(hash12(in.cell + epoch * float2(1.7, 9.2)) * float(u.glyphCount)), u.glyphCount - 1);
    uint atlasColumns = uint(u.atlasGrid.x);
    float2 atlasCell = float2(glyph % atlasColumns, glyph / atlasColumns);
    float mask = atlas.sample(atlasSampler, (atlasCell + in.glyphUV) / u.atlasGrid).r;

    // Brightness gradient: white-hot head, a short glow just behind it, then an exponential fade.
    float head = 1.0 - smoothstep(0.0, 1.0, d);
    float tail = exp(-u.fadeSpeed * max(d - 1.0, 0.0));
    float glow = exp(-max(d - 1.0, 0.0) * 1.2) * 0.35;
    float flicker = 0.82 + 0.18 * hash12(in.cell + floor(u.time * 14.0));

    float3 color = u.trailColor.rgb * tail * flicker + u.primaryColor.rgb * glow;
    color = mix(color, u.primaryColor.rgb, head);
    float alpha = mask * saturate(max(tail * flicker, head));
    return float4(color * mask, alpha);   // premultiplied
}

// =====================================================================
// MARK: - Fluid mesh gradient
// =====================================================================

// Keep in sync with `FluidUniforms` in FluidMeshGradientView.swift.
struct FluidUniforms {
    float2 viewport;     // px
    float  time;
    float  speed;
    float2 tilt;         // where gravity pulls, screen axes (y down), roughly -1…1
    float2 flow;         // tilt velocity: how hard the liquid is sloshing
    uint   colorCount;
    float  blobSize;     // softness of each color blob, in screen heights
    float  warp;         // strength of the liquid domain warp
    float  grain;        // dither amplitude, in 8-bit steps
};

struct FluidOut {
    float4 position [[position]];
    float2 uv;
};

static float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 w = f * f * (3.0 - 2.0 * f);
    float a = hash12(i), b = hash12(i + float2(1, 0));
    float c = hash12(i + float2(0, 1)), d = hash12(i + float2(1, 1));
    return mix(mix(a, b, w.x), mix(c, d, w.x), w.y) * 2.0 - 1.0;
}

static float fluidFbm(float2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 4; ++i) {
        value += amplitude * valueNoise(p);
        p = p * 2.01 + 7.3;
        amplitude *= 0.5;
    }
    return value;
}

vertex FluidOut fluid_gradient_vertex(uint vid [[vertex_id]]) {
    float2 pos = float2((vid << 1) & 2, vid & 2);
    FluidOut out;
    out.position = float4(pos * 2.0 - 1.0, 0.0, 1.0);
    out.uv = float2(pos.x, 1.0 - pos.y);
    return out;
}

fragment float4 fluid_gradient_fragment(FluidOut in [[stage_in]],
                                        constant FluidUniforms &u [[buffer(0)]],
                                        constant float4 *colors [[buffer(1)]]) {
    float aspect = u.viewport.x / u.viewport.y;
    float2 p = (in.uv - 0.5) * float2(aspect, 1.0);
    float t = u.time * u.speed;

    // Liquid look: warp the sample position with slowly drifting noise; sloshing adds turbulence.
    float turbulence = u.warp * (1.0 + 2.0 * min(length(u.flow), 1.5));
    float2 q = p + turbulence * float2(fluidFbm(p * 1.4 + float2(t * 0.11, -t * 0.07)),
                                       fluidFbm(p * 1.4 + float2(5.2 - t * 0.09, 1.3 + t * 0.05)));

    // Each blob orbits on its own Lissajous path and slides toward gravity; later (heavier)
    // blobs slide further, so tilting the phone makes the colors flow past each other.
    float logits[8];
    float maxLogit = -1e9;
    uint count = min(u.colorCount, 8u);
    for (uint i = 0; i < count; ++i) {
        float fi = float(i);
        float2 center = float2(sin(t * (0.31 + 0.07 * fi) + fi * 2.39) * 0.42 * aspect,
                               cos(t * (0.27 + 0.05 * fi) + fi * 1.71) * 0.38);
        center += u.tilt * (0.25 + 0.1 * fi);
        float2 d = q - center;
        logits[i] = -dot(d, d) / (u.blobSize * u.blobSize);
        maxLogit = max(maxLogit, logits[i]);
    }
    // Softmax in log space: smooth everywhere, never underflows to black far from every blob.
    float3 color = float3(0.0);
    float total = 0.0;
    for (uint i = 0; i < count; ++i) {
        float w = exp(logits[i] - maxLogit);
        color += colors[i].rgb * w;
        total += w;
    }
    color = pow(color / max(total, 1e-5), float3(1.0 / 2.2));   // blended in linear light

    color += (hash12(in.position.xy) - 0.5) * u.grain / 255.0;  // dither: no banding
    return float4(color, 1.0);
}
