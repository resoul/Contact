//
//  ParticleStructures.h
//  controller
//
//  Types shared by Swift (through controller-Bridging-Header.h) and MSL (#include), so the memory
//  layout of every struct is defined once and is identical on the CPU and the GPU.
//

#ifndef ParticleStructures_h
#define ParticleStructures_h

#include <simd/simd.h>

/// One particle. Positions are in points of the engine's view, top-left origin (UIKit space).
typedef struct {
    simd_float2 currentPosition;
    simd_float2 targetPosition;
    simd_float2 startPosition;
    simd_float2 velocity;
    simd_float4 color;            // straight (not premultiplied) sRGB; .a is brightness / opacity
    simd_float4 targetColor;      // chart: `color` eases towards it; .a < 0.01 releases the particle as dust
    float size;                   // diameter in points
    float seed;                   // 0…1, per-particle randomness
    float stiffness;              // chart: multiplies the spring towards the target (text snaps, shapes flow)
} Particle;

/// Which scenario `particleComputeKernel` runs.
typedef enum ParticleMode {
    ParticleModePaywall = 0,      // button → explosion + vortex → checkmark
    ParticleModeTabBar  = 1,      // icon A → Bézier arc → icon B
    ParticleModeVoice   = 2,      // pulsing audio sphere ↔ text
    ParticleModeThanos  = 3,      // card → dust carried by the wind, reversible
    ParticleModeBadge   = 4,      // magnetic 3D badge repelled by the finger
    ParticleModeLoader  = 5,      // "0%" → "50%" → "100%" → content card
    ParticleModeChart   = 6,      // data charts: springs to targets, dust when released, finger repels
} ParticleMode;

/// Chart mode: how released particles (targetColor.a ≈ 0) leave. Each one waits for its delay on the
/// `stage` timeline (0…1 over `releaseDuration` seconds), then goes.
typedef enum ParticleReleaseStyle {
    ParticleReleaseDust      = 0,   // a ragged front sweeps left → right, wind carries the dust away
    ParticleReleaseBlackHole = 1,   // spiral into the center of `bounds` and vanish there
    ParticleReleaseSweep     = 2,   // a clock hand from 12 o'clock flicks particles off clockwise
    ParticleReleaseGravity   = 3,   // fall, bounce on `floorY`, settle into a heap and fade
    ParticleReleaseNova      = 4,   // contract and glow, then burst outwards as cooling embers
    ParticleReleaseSteam     = 5,   // rise and whirl like steam, fading to white
    ParticleReleaseHome      = 6,   // fly to targetPosition (e.g. a legend row) and fade on arrival
} ParticleReleaseStyle;

typedef struct {
    // --- Fields from the spec ---
    float progress;               // 0…1
    float time;                   // seconds
    simd_float2 touchPos;         // points
    float touchRadius;            // points
    float noiseStrength;          // curl-noise strength (meaning depends on the mode)

    // --- Engine extensions ---
    float deltaTime;              // seconds since the previous frame
    unsigned int mode;            // ParticleMode
    simd_float2 viewSize;         // points
    simd_float4 bounds;           // x, y, width, height of the scenario's shape (button, card, sphere…)
    simd_float4 colorA;
    simd_float4 colorB;
    float scale;                  // pixels per point
    float touchActive;            // 1 while a finger is down
    float touchPower;             // repulsion at the finger, points / s²
    float audioVolume;            // 0…1
    float arcHeight;              // tab bar: signed control-point offset, points
    float stage;                  // loader: collapse into the final card; chart: release timeline; 0…1
    float pointScale;             // multiplies Particle.size
    float intensity;              // glow brightness
    unsigned int particleCount;
    unsigned int releaseStyle;    // chart: ParticleReleaseStyle
    float releaseDuration;        // chart: seconds the `stage` timeline of a release lasts
    float floorY;                 // chart, gravity release: the ground, points
    float charge;                 // chart: 0…1, attached particles tremble (hold-to-clear)
} ParticleUniforms;

/// What `particleRetargetKernel` changes without touching the particles' current motion.
typedef enum ParticleRetargetFlags {
    ParticleRetargetCommitStart  = 1 << 0,   // startPosition = currentPosition
    ParticleRetargetTargets      = 1 << 1,   // targetPosition = targets[i]
    ParticleRetargetColors       = 1 << 2,   // color = colors[i]
    ParticleRetargetStopVelocity = 1 << 3,   // velocity = 0
    ParticleRetargetTargetColors = 1 << 4,   // targetColor = colors[i] (`color` follows it gradually)
} ParticleRetargetFlags;

typedef struct {
    unsigned int count;
    unsigned int flags;
} ParticleRetarget;

typedef enum ParticleBufferIndex {
    ParticleBufferIndexParticles = 0,
    ParticleBufferIndexUniforms  = 1,
    ParticleBufferIndexKeyframes = 2,        // loader: Buffer_0, Buffer_50, Buffer_100, card (N points each)
} ParticleBufferIndex;

#endif /* ParticleStructures_h */
