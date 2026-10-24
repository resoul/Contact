//
//  PaperBurn.metal
//  controller
//
//  A view burns away like paper: a noisy burn front spreads from the ignition point,
//  scorching ahead of it, leaving a glowing ember edge, rising sparks and heat haze.
//

#include <metal_stdlib>
using namespace metal;

// Keep in sync with `BurnUniforms` in PaperBurnAnimator.swift.
struct BurnUniforms {
    float2 viewport;   // px
    float  scale;      // px per point
    float  time;       // s since ignition
    float4 element;    // snapshot frame in overlay points: x, y, w, h
    float2 origin;     // ignition point, overlay points
    float  speed;      // front speed, points / s
    float  roughness;  // seconds of noise added to the arrival time
};

struct BurnOut {
    float4 position [[position]];
    float2 uv;
};

constexpr sampler burnSampler(coord::normalized, address::clamp_to_zero, filter::linear);

static float burnHash(float2 p) {
    p = fract(p * float2(127.1, 311.7));
    p += dot(p, p + 19.19);
    return fract(p.x * p.y);
}

static float valueNoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 w = f * f * (3.0 - 2.0 * f);
    float a = burnHash(i), b = burnHash(i + float2(1, 0)), c = burnHash(i + float2(0, 1)), d = burnHash(i + float2(1, 1));
    return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
}

static float fbm(float2 p) {
    float sum = 0.0, amplitude = 0.5;
    for (int i = 0; i < 5; ++i) {
        sum += amplitude * valueNoise(p);
        p = p * 2.03 + 17.0;
        amplitude *= 0.5;
    }
    return sum;
}

/// Seconds since the front passed `p` (negative: not burning yet).
static float burnAge(float2 p, constant BurnUniforms &u) {
    float arrival = length(p - u.origin) / u.speed + fbm(p * 0.03) * u.roughness;
    return u.time - arrival;
}

vertex BurnOut burn_vertex(uint vid [[vertex_id]]) {
    float2 pos = float2((vid << 1) & 2, vid & 2);
    BurnOut out;
    out.position = float4(pos * 2.0 - 1.0, 0.0, 1.0);
    out.uv = float2(pos.x, 1.0 - pos.y);
    return out;
}

fragment float4 burn_fragment(BurnOut in [[stage_in]],
                              texture2d<float> paper [[texture(0)]],
                              constant BurnUniforms &u [[buffer(0)]]) {
    float2 p = in.uv * u.viewport / u.scale;
    float age = burnAge(p, u);

    // Heat haze just ahead of the front.
    float haze = smoothstep(-0.15, -0.02, age) * (1.0 - smoothstep(-0.02, 0.0, age));
    float2 wobble = float2(sin(p.y * 0.45 + u.time * 19.0), cos(p.x * 0.4 + u.time * 16.0)) * 1.2 * haze;
    float2 uv = (p + wobble - u.element.xy) / u.element.zw;
    float4 sheet = paper.sample(burnSampler, uv);   // premultiplied
    float3 color = sheet.a > 0.0 ? sheet.rgb / sheet.a : float3(0.0);

    // Scorch: browning ahead of the front, charring right at it.
    float scorch = smoothstep(-0.3, -0.01, age);
    color = mix(color, color * float3(0.55, 0.36, 0.18), scorch * 0.8);
    float charred = smoothstep(-0.06, 0.0, age);
    color = mix(color, float3(0.05, 0.03, 0.02), charred);

    // Burnt away behind the front, with a thin flickering ember line.
    float alpha = sheet.a * (1.0 - smoothstep(0.0, 0.05, age));
    float flicker = 0.75 + 0.25 * valueNoise(p * 0.2 + u.time * 6.0);
    float ember = sheet.a * exp(-max(age, 0.0) * 22.0) * step(-0.01, age);
    float emberEdge = ember * flicker;
    float3 emberColor = mix(float3(1.0, 0.3, 0.05), float3(1.0, 0.85, 0.4), saturate(ember * 1.5 - 0.5));

    // Sparks: sparse cells drifting upwards over the freshly burnt band.
    float2 drift = float2(sin(p.y * 0.05 + u.time) * 6.0, u.time * 55.0);
    float2 cellPos = (p + drift) / 7.0;
    float2 cell = floor(cellPos);
    float h = burnHash(cell);
    float2 inCell = fract(cellPos) - (0.3 + 0.4 * float2(burnHash(cell + 3.1), burnHash(cell + 7.7)));
    float sparkShape = exp(-dot(inCell, inCell) * 90.0) * step(0.975, h);
    float inBand = smoothstep(0.02, 0.15, age) * (1.0 - smoothstep(0.35, 1.0, age));
    float inside = step(u.element.x - 30.0, p.x) * step(p.x, u.element.x + u.element.z + 30.0)
                 * step(u.element.y - 60.0, p.y) * step(p.y, u.element.y + u.element.w + 10.0);
    float spark = sparkShape * inBand * inside * (0.6 + 0.4 * sin(u.time * 30.0 + h * 50.0));

    float glow = saturate(emberEdge * 1.4 + spark);
    float3 rgb = color * alpha + emberColor * glow;
    return float4(saturate(rgb), saturate(alpha + glow));
}
