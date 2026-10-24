//
//  WaterRipple.metal
//  controller
//
//  Water ripples over a snapshot of live UI: a height field simulated with the 2D wave equation
//  (ping-pong textures, fixed time step), rendered as refraction plus specular highlights.
//

#include <metal_stdlib>
using namespace metal;

// Keep in sync with `RippleStep` / `RippleDrop` in WaterRippleOverlay.swift.
struct RippleStep {
    float damping;     // per step, e.g. 0.985
    uint  dropCount;
};

struct RippleDrop {
    float2 position;   // grid cells
    float  radius;     // grid cells
    float  strength;
};

kernel void ripple_step(texture2d<half, access::read> previous [[texture(0)]],
                        texture2d<half, access::read> current [[texture(1)]],
                        texture2d<half, access::write> next [[texture(2)]],
                        constant RippleStep &s [[buffer(0)]],
                        constant RippleDrop *drops [[buffer(1)]],
                        uint2 gid [[thread_position_in_grid]]) {
    uint w = current.get_width(), h = current.get_height();
    if (gid.x >= w || gid.y >= h) {
        return;
    }
    // Clamped neighbours: the screen edges reflect waves like the walls of a pool.
    float l = current.read(uint2(gid.x > 0 ? gid.x - 1 : 0, gid.y)).r;
    float r = current.read(uint2(min(gid.x + 1, w - 1), gid.y)).r;
    float t = current.read(uint2(gid.x, gid.y > 0 ? gid.y - 1 : 0)).r;
    float b = current.read(uint2(gid.x, min(gid.y + 1, h - 1))).r;
    // Discrete wave equation (c² = 0.5): next = (neighbours) / 2 − previous.
    float height = ((l + r + t + b) * 0.5 - float(previous.read(gid).r)) * s.damping;
    for (uint i = 0; i < s.dropCount; ++i) {
        float dist = length(float2(gid) - drops[i].position);
        if (dist < drops[i].radius) {
            height += drops[i].strength * (0.5 + 0.5 * cos(M_PI_F * dist / drops[i].radius));
        }
    }
    next.write(half4(half(clamp(height, -8.0, 8.0))), gid);
}

// Keep in sync with `RippleUniforms` in WaterRippleOverlay.swift.
struct RippleUniforms {
    float2 viewSize;     // points
    float  refraction;   // points of shift per unit of slope
    float  shine;        // specular strength
};

struct RippleOut {
    float4 position [[position]];
    float2 uv;
};

constexpr sampler rippleSampler(coord::normalized, address::clamp_to_edge, filter::linear);

vertex RippleOut ripple_vertex(uint vid [[vertex_id]]) {
    float2 pos = float2((vid << 1) & 2, vid & 2);
    RippleOut out;
    out.position = float4(pos * 2.0 - 1.0, 0.0, 1.0);
    out.uv = float2(pos.x, 1.0 - pos.y);
    return out;
}

fragment float4 ripple_fragment(RippleOut in [[stage_in]],
                                texture2d<float> snapshot [[texture(0)]],
                                texture2d<half> heightField [[texture(1)]],
                                constant RippleUniforms &u [[buffer(0)]]) {
    float2 texel = 1.0 / float2(heightField.get_width(), heightField.get_height());
    float hl = heightField.sample(rippleSampler, in.uv - float2(texel.x, 0.0)).r;
    float hr = heightField.sample(rippleSampler, in.uv + float2(texel.x, 0.0)).r;
    float ht = heightField.sample(rippleSampler, in.uv - float2(0.0, texel.y)).r;
    float hb = heightField.sample(rippleSampler, in.uv + float2(0.0, texel.y)).r;
    float2 slope = float2(hr - hl, hb - ht);

    // Refraction: the surface slope shifts what is seen through the water.
    float2 shifted = in.uv + slope * u.refraction / u.viewSize;
    float4 color = snapshot.sample(rippleSampler, shifted);

    // Lighting from a key light above the top-left.
    float3 normal = normalize(float3(-slope * 3.0, 1.0));
    float3 light = normalize(float3(-0.4, -0.6, 0.7));
    float3 halfway = normalize(light + float3(0.0, 0.0, 1.0));
    float spec = pow(saturate(dot(normal, halfway)), 60.0) * u.shine;
    float shade = 1.0 + dot(normal.xy, -light.xy) * 0.6;   // crests lighter, troughs darker
    color.rgb = color.rgb * shade + spec * color.a;
    return float4(saturate(color.rgb), color.a);
}
