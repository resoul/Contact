//
//  StableFluids.metal
//  demo
//
//  2D incompressible smoke (Jos Stam's "Stable Fluids" on a grid): semi-Lagrangian advection of
//  velocity and dye, vorticity confinement, then a pressure projection solved with Jacobi
//  iterations so the velocity field stays divergence-free. Velocities are in cells per second.
//

#include "EffectsCommon.h"

// Mirrored by `FluidParams` in SmokeFluidView.swift (176 bytes).
struct FluidParams {
    float2 gridSize;
    float deltaTime;
    float vorticity;
    float velocityDissipation;
    float dyeDissipation;
    uint splatCount;
    float padding;
    float4 splatPositions[3];   // xy cells, z radius in cells
    float4 splatForces[3];      // xy cells per second
    float4 splatColors[3];      // rgb
};

constexpr sampler fluidSampler(filter::linear, address::clamp_to_edge);

static float splatWeight(float2 position, float4 splat) {
    float2 d = position - splat.xy;
    return exp(-dot(d, d) / (splat.z * splat.z));
}

static int2 clampCell(int2 cell, int2 size) {
    return clamp(cell, int2(0), size - 1);
}

kernel void fluid_advect_velocity(texture2d<float> velocity [[texture(0)]],
                                  texture2d<float, access::write> out [[texture(1)]],
                                  constant FluidParams &p [[buffer(0)]],
                                  uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= out.get_width() || gid.y >= out.get_height()) return;
    float2 position = float2(gid) + 0.5;
    float2 v = velocity.sample(fluidSampler, position / p.gridSize).xy;
    float2 result = velocity.sample(fluidSampler, (position - p.deltaTime * v) / p.gridSize).xy * p.velocityDissipation;
    for (uint i = 0; i < p.splatCount; i++) {
        result += p.splatForces[i].xy * splatWeight(position, p.splatPositions[i]);
    }
    out.write(float4(result, 0.0, 0.0), gid);
}

kernel void fluid_advect_dye(texture2d<float> velocity [[texture(0)]],
                             texture2d<float> dye [[texture(1)]],
                             texture2d<float, access::write> out [[texture(2)]],
                             constant FluidParams &p [[buffer(0)]],
                             uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= out.get_width() || gid.y >= out.get_height()) return;
    float2 position = float2(gid) + 0.5;
    float2 v = velocity.sample(fluidSampler, position / p.gridSize).xy;
    float3 result = dye.sample(fluidSampler, (position - p.deltaTime * v) / p.gridSize).rgb * p.dyeDissipation;
    for (uint i = 0; i < p.splatCount; i++) {
        result += p.splatColors[i].rgb * splatWeight(position, p.splatPositions[i]);
    }
    out.write(float4(min(result, float3(4.0)), 1.0), gid);
}

kernel void fluid_curl(texture2d<float, access::read> velocity [[texture(0)]],
                       texture2d<float, access::write> curl [[texture(1)]],
                       uint2 gid [[thread_position_in_grid]]) {
    int2 size = int2(velocity.get_width(), velocity.get_height());
    if (int(gid.x) >= size.x || int(gid.y) >= size.y) return;
    int2 c = int2(gid);
    float right = velocity.read(uint2(clampCell(c + int2(1, 0), size))).y;
    float left = velocity.read(uint2(clampCell(c - int2(1, 0), size))).y;
    float down = velocity.read(uint2(clampCell(c + int2(0, 1), size))).x;
    float up = velocity.read(uint2(clampCell(c - int2(0, 1), size))).x;
    curl.write(float4(0.5 * ((right - left) - (down - up))), gid);
}

// Vorticity confinement: pushes along the curl gradient to restore swirls lost to numerical damping.
kernel void fluid_vorticity(texture2d<float, access::read> velocity [[texture(0)]],
                            texture2d<float, access::read> curl [[texture(1)]],
                            texture2d<float, access::write> out [[texture(2)]],
                            constant FluidParams &p [[buffer(0)]],
                            uint2 gid [[thread_position_in_grid]]) {
    int2 size = int2(velocity.get_width(), velocity.get_height());
    if (int(gid.x) >= size.x || int(gid.y) >= size.y) return;
    int2 c = int2(gid);
    float right = abs(curl.read(uint2(clampCell(c + int2(1, 0), size))).x);
    float left = abs(curl.read(uint2(clampCell(c - int2(1, 0), size))).x);
    float down = abs(curl.read(uint2(clampCell(c + int2(0, 1), size))).x);
    float up = abs(curl.read(uint2(clampCell(c - int2(0, 1), size))).x);
    float center = curl.read(gid).x;
    float2 gradient = float2(right - left, down - up) * 0.5;
    float2 direction = gradient / (length(gradient) + 1e-5);
    float2 force = p.vorticity * center * float2(direction.y, -direction.x);
    out.write(float4(velocity.read(gid).xy + force * p.deltaTime, 0.0, 0.0), gid);
}

kernel void fluid_divergence(texture2d<float, access::read> velocity [[texture(0)]],
                             texture2d<float, access::write> divergence [[texture(1)]],
                             uint2 gid [[thread_position_in_grid]]) {
    int2 size = int2(velocity.get_width(), velocity.get_height());
    if (int(gid.x) >= size.x || int(gid.y) >= size.y) return;
    int2 c = int2(gid);
    // Solid walls: the neighbour outside the grid mirrors the normal velocity.
    float2 center = velocity.read(gid).xy;
    float right = c.x + 1 < size.x ? velocity.read(uint2(c + int2(1, 0))).x : -center.x;
    float left = c.x > 0 ? velocity.read(uint2(c - int2(1, 0))).x : -center.x;
    float down = c.y + 1 < size.y ? velocity.read(uint2(c + int2(0, 1))).y : -center.y;
    float up = c.y > 0 ? velocity.read(uint2(c - int2(0, 1))).y : -center.y;
    divergence.write(float4(0.5 * (right - left + down - up)), gid);
}

kernel void fluid_jacobi(texture2d<float, access::read> pressure [[texture(0)]],
                         texture2d<float, access::read> divergence [[texture(1)]],
                         texture2d<float, access::write> out [[texture(2)]],
                         uint2 gid [[thread_position_in_grid]]) {
    int2 size = int2(pressure.get_width(), pressure.get_height());
    if (int(gid.x) >= size.x || int(gid.y) >= size.y) return;
    int2 c = int2(gid);
    float sum = pressure.read(uint2(clampCell(c + int2(1, 0), size))).x
              + pressure.read(uint2(clampCell(c - int2(1, 0), size))).x
              + pressure.read(uint2(clampCell(c + int2(0, 1), size))).x
              + pressure.read(uint2(clampCell(c - int2(0, 1), size))).x;
    out.write(float4((sum - divergence.read(gid).x) * 0.25), gid);
}

kernel void fluid_subtract_gradient(texture2d<float, access::read> pressure [[texture(0)]],
                                    texture2d<float, access::read> velocity [[texture(1)]],
                                    texture2d<float, access::write> out [[texture(2)]],
                                    uint2 gid [[thread_position_in_grid]]) {
    int2 size = int2(pressure.get_width(), pressure.get_height());
    if (int(gid.x) >= size.x || int(gid.y) >= size.y) return;
    int2 c = int2(gid);
    float right = pressure.read(uint2(clampCell(c + int2(1, 0), size))).x;
    float left = pressure.read(uint2(clampCell(c - int2(1, 0), size))).x;
    float down = pressure.read(uint2(clampCell(c + int2(0, 1), size))).x;
    float up = pressure.read(uint2(clampCell(c - int2(0, 1), size))).x;
    float2 v = velocity.read(gid).xy - 0.5 * float2(right - left, down - up);
    // No flow through the walls.
    if (c.x == 0 || c.x == size.x - 1) v.x = 0.0;
    if (c.y == 0 || c.y == size.y - 1) v.y = 0.0;
    out.write(float4(v, 0.0, 0.0), gid);
}

fragment float4 smoke_fragment(FullscreenVertexOut in [[stage_in]],
                               texture2d<float> dye [[texture(0)]]) {
    constexpr sampler linear(filter::linear, address::clamp_to_edge);
    float2 texel = 1.0 / float2(dye.get_width(), dye.get_height());
    float3 c = dye.sample(linear, in.uv).rgb;

    // Soft relief from the dye density, so the smoke reads as volume rather than paint.
    float dx = length(dye.sample(linear, in.uv + float2(texel.x, 0.0)).rgb) - length(dye.sample(linear, in.uv - float2(texel.x, 0.0)).rgb);
    float dy = length(dye.sample(linear, in.uv + float2(0.0, texel.y)).rgb) - length(dye.sample(linear, in.uv - float2(0.0, texel.y)).rgb);
    float3 normal = normalize(float3(-dx * 2.0, -dy * 2.0, 1.0));
    float light = 0.75 + 0.35 * dot(normal, normalize(float3(-0.4, -0.6, 0.7)));

    float3 color = (1.0 - exp(-c * 1.4)) * light;
    color += float3(0.01, 0.012, 0.025);
    return float4(color, 1.0);
}
