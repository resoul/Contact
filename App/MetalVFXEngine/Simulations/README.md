# Metal simulations

These views were copied from the local `demo/demo/demo` project on 2026-10-25:

- `Effects/Lava` and `Effects/Fire`: the single lava progress bar and procedural fire.
- `GPUCompute/NBody`: GPU gravity with the original galaxy initialization.
- `GPUCompute/Smoke`: the original 2D Stable Fluids simulation and dye injection.
- `GPUWorlds/Boids`: the interacting fish school and GPU spatial search grid.

`Core` contains the Metal view, shared context, uniforms, touch handling, effect
controls and spatial grid. The context reuses Contact's existing `VFXGPU` device,
queue and shader library. Shaders and their shared headers live in
`App/MetalVFXEngine/Shaders` and are compiled into Contact's `default.metallib`.

Benchmark recorders, profiler overlays, CPU gravity, independent-particle comparison
controls and GPU neighbor-count instrumentation were removed. The visual kernels,
initial simulation settings and touch interactions are preserved. Swarm output
buffers were renumbered consistently in Swift and Metal after removing the counter.

`App/Messenger/MetalEffects/MetalEffectsViewController.swift` presents one effect
at a time from Settings. It owns mode selection and starts/stops the active view
with screen visibility. The Metal base view also pauses outside an active app or
window, resets elapsed frame time on resume and excludes paused time from animation.
