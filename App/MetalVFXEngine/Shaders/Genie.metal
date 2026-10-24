//
//  Genie.metal
//  controller
//
//  macOS-style genie: a snapshot drawn as a vertical strip mesh whose sides bend into an
//  S-curve tube towards the target, then the content slides down the tube into it.
//  Computed in "down" space; when the target is above the source the Swift side mirrors y.
//

#include <metal_stdlib>
using namespace metal;

// Keep in sync with `GenieUniforms` in GenieAnimator.swift.
struct GenieUniforms {
    float2 viewport;   // px
    float  scale;      // px per point
    float  progress;   // 0 = source, 1 = inside the target
    float4 source;     // x, y, w, h in down space
    float4 target;     // x, y, w, h in down space
    uint   rows;
    float  flip;       // 1 when y is mirrored
};

struct GenieOut {
    float4 position [[position]];
    float2 uv;
    float  squeeze;
};

constexpr sampler genieSampler(coord::normalized, address::clamp_to_zero, filter::linear);

vertex GenieOut genie_vertex(uint vid [[vertex_id]], constant GenieUniforms &u [[buffer(0)]]) {
    float row = float(vid / 2) / float(u.rows);   // 0 = top of the image (in down space)
    float column = float(vid & 1);
    float4 S = u.source, D = u.target;
    float sTop = S.y, sBottom = S.y + S.w, dTop = D.y, dBottom = D.y + D.w;

    float tube = smoothstep(0.0, 0.45, u.progress);   // phase 1: the sides bend
    float slide = smoothstep(0.25, 1.0, u.progress);  // phase 2: the content pours in
    // The bottom reaches the target first, the top follows: the image stretches, then squeezes.
    float top = mix(sTop, dTop, slide);
    float bottom = mix(sBottom, dBottom, smoothstep(0.0, 0.6, slide));
    float y = mix(top, max(bottom, top + 1.0), row);

    // Tube: full source width at the source's top, target width from the target's top down.
    float bendFactor = smoothstep(sTop, dTop, y) * tube;
    float left = mix(S.x, D.x, bendFactor);
    float right = mix(S.x + S.z, D.x + D.z, bendFactor);
    float x = mix(left, right, column);

    float2 point = float2(x, u.flip > 0.5 ? -y : y);
    float2 ndc = point * u.scale / u.viewport * 2.0 - 1.0;
    GenieOut out;
    out.position = float4(ndc.x, -ndc.y, 0.0, 1.0);
    out.uv = float2(column, u.flip > 0.5 ? 1.0 - row : row);
    out.squeeze = 1.0 - (right - left) / max(S.z, 1.0);
    return out;
}

fragment float4 genie_fragment(GenieOut in [[stage_in]],
                               texture2d<float> snapshot [[texture(0)]],
                               constant GenieUniforms &u [[buffer(0)]]) {
    float4 color = snapshot.sample(genieSampler, in.uv);
    color.rgb *= 1.0 - 0.25 * saturate(in.squeeze);         // squeezed parts turn away from the light
    return color * (1.0 - smoothstep(0.9, 1.0, u.progress)); // the last bit vanishes into the target
}
