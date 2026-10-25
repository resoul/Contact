//
//  ParticleRender.metal
//  controller
//
//  Draws the particle buffer written by ParticleCompute.metal as point sprites:
//  one vertex per particle, no index or vertex buffers.
//

#include <metal_stdlib>
#include "ParticleStructures.h"
using namespace metal;

struct ParticleVertexOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float4 color;
};

vertex ParticleVertexOut particleVertex(const device Particle *particles [[buffer(ParticleBufferIndexParticles)]],
                                        constant ParticleUniforms &u [[buffer(ParticleBufferIndexUniforms)]],
                                        uint vid [[vertex_id]]) {
    Particle p = particles[vid];
    float2 ndc = p.currentPosition / u.viewSize * 2.0 - 1.0;
    ParticleVertexOut out;
    // Invisible particles are moved outside the clip volume, so they cost no fragments at all.
    out.position = p.color.a > 0.002 ? float4(ndc.x, -ndc.y, 0.0, 1.0) : float4(-4.0, -4.0, 0.0, 1.0);
    out.pointSize = clamp(p.size * u.pointScale * u.scale, 1.0, 511.0);
    out.color = p.color;
    if (u.mode == ParticleModeChart) {
        out.color.a *= 1.0 + min(length(p.velocity) / 450.0, 2.0);   // particles in flight flare up
    }
    return out;
}

/// Neon soft glow for additive blending: a tight white-hot core inside a wide Gaussian halo.
/// Overlapping particles add up, so dense areas bloom towards white like a real light source.
fragment float4 particleGlowFragment(ParticleVertexOut in [[stage_in]],
                                     float2 pointCoord [[point_coord]],
                                     constant ParticleUniforms &u [[buffer(ParticleBufferIndexUniforms)]]) {
    float r2 = length_squared(pointCoord * 2.0 - 1.0);
    float fade = saturate(1.0 - r2);                 // reaches 0 exactly at the sprite edge
    float core = exp(-r2 * 18.0);
    float halo = exp(-r2 * 4.0) * 0.45;
    float energy = (core + halo) * fade * in.color.a * u.intensity;
    float3 rgb = in.color.rgb * energy + core * fade * energy * 0.35;
    return float4(rgb, energy);
}

/// Opaque dust for normal (premultiplied) alpha blending: a solid square, like one pixel of the source.
/// No soft edge on purpose: on a dense grid, overlapping antialiased rims beat against the screen's
/// pixel grid and show up as a moiré pattern over the picture.
fragment float4 particleSolidFragment(ParticleVertexOut in [[stage_in]]) {
    float alpha = saturate(in.color.a);
    return float4(in.color.rgb * alpha, alpha);
}
