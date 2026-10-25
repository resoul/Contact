//
//  Fullscreen.metal
//  demo
//

#include "EffectsCommon.h"

// Single triangle that covers the whole viewport; no vertex buffer needed.
vertex FullscreenVertexOut fullscreen_vertex(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);
    FullscreenVertexOut out;
    out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    out.uv = float2(p.x, 1.0 - p.y);
    return out;
}
