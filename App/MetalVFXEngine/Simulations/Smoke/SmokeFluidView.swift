import UIKit
import Metal

/// Mirrors `FluidParams` in StableFluids.metal (176 bytes).
private struct FluidParams {
    var gridSize: SIMD2<Float>
    var deltaTime: Float
    var vorticity: Float
    var velocityDissipation: Float
    var dyeDissipation: Float
    var splatCount: UInt32
    var padding: Float = 0
    var splatPositions: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>) = (.zero, .zero, .zero)
    var splatForces: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>) = (.zero, .zero, .zero)
    var splatColors: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>) = (.zero, .zero, .zero)
}

/// 2D smoke and ink on a grid (Stable Fluids). Each frame runs advection, vorticity confinement
/// and a pressure solve with tens of Jacobi iterations, all as compute passes over textures.
/// Dragging a finger pushes the fluid and injects colored dye; two nozzles keep it moving.
final class SmokeFluidView: MetalAnimationView {
    private static let resolutions = [128, 256, 512]
    private static let maxSplats = 3

    private var resolutionIndex = 1
    private var pressureIterations = 30
    private var needsClear = false

    private var velocity: [MTLTexture] = []
    private var dye: [MTLTexture] = []
    private var pressure: [MTLTexture] = []
    private var divergence: MTLTexture?
    private var curl: MTLTexture?
    private var velocityIndex = 0
    private var dyeIndex = 0
    private var pressureIndex = 0

    private var previousTouch: CGPoint?
    private var fingerVelocity: SIMD2<Float> = .zero

    private let advectVelocity = MetalEffectContext.shared?.computePipeline(function: "fluid_advect_velocity")
    private let advectDye = MetalEffectContext.shared?.computePipeline(function: "fluid_advect_dye")
    private let curlPipeline = MetalEffectContext.shared?.computePipeline(function: "fluid_curl")
    private let vorticityPipeline = MetalEffectContext.shared?.computePipeline(function: "fluid_vorticity")
    private let divergencePipeline = MetalEffectContext.shared?.computePipeline(function: "fluid_divergence")
    private let jacobiPipeline = MetalEffectContext.shared?.computePipeline(function: "fluid_jacobi")
    private let gradientPipeline = MetalEffectContext.shared?.computePipeline(function: "fluid_subtract_gradient")
    private let displayPipeline = MetalEffectContext.shared?.renderPipeline(vertex: "fullscreen_vertex", fragment: "smoke_fragment")

    override var controls: [MetalEffectControl] {
        [
            .segments(items: Self.resolutions.map { "Сетка \($0)" }, selected: resolutionIndex) { [weak self] index in
                self?.resolutionIndex = index
                self?.velocity = []
            },
            .slider(
                title: "Итераций",
                range: 5...80,
                value: Float(pressureIterations),
                format: { "\(Int($0.rounded()))" },
                onChange: { [weak self] value in self?.pressureIterations = Int(value.rounded()) }
            ),
            .button(title: "Очистить") { [weak self] in
                self?.needsClear = true
            },
        ]
    }

    override func update(_ uniforms: inout EffectUniforms, deltaTime: Double) {
        // Finger velocity in points per second, smoothed a little.
        if touch.isActive, let previous = previousTouch, deltaTime > 0 {
            let raw = SIMD2(Float(touch.location.x - previous.x), Float(touch.location.y - previous.y)) / Float(deltaTime)
            fingerVelocity = fingerVelocity * 0.5 + raw * 0.5
        } else {
            fingerVelocity = .zero
        }
        previousTouch = touch.isActive ? touch.location : nil
    }

    override func encode(into commandBuffer: MTLCommandBuffer, pass: MTLRenderPassDescriptor, uniforms: inout EffectUniforms) {
        guard let advectVelocity, let advectDye, let curlPipeline, let vorticityPipeline,
              let divergencePipeline, let jacobiPipeline, let gradientPipeline, let displayPipeline else { return }
        allocateIfNeeded(resolution: uniforms.resolution)
        guard velocity.count == 2, dye.count == 2, pressure.count == 2, let divergence, let curl else { return }
        let width = velocity[0].width, height = velocity[0].height

        if needsClear, let blit = commandBuffer.makeBlitCommandEncoder() {
            needsClear = false
            for texture in velocity + dye + pressure {
                clear(texture, with: blit)
            }
            blit.endEncoding()
        }

        var params = makeParams(width: width, height: height, uniforms: uniforms)
        let size = MemoryLayout<FluidParams>.stride
        guard let compute = commandBuffer.makeComputeCommandEncoder() else { return }
        compute.setBytes(&params, length: size, index: 0)

        // 1. Advect velocity (adds the splat forces).
        compute.setTexture(velocity[velocityIndex], index: 0)
        compute.setTexture(velocity[1 - velocityIndex], index: 1)
        compute.dispatch(advectVelocity, width: width, height: height)
        velocityIndex = 1 - velocityIndex

        // 2. Vorticity confinement.
        compute.setTexture(velocity[velocityIndex], index: 0)
        compute.setTexture(curl, index: 1)
        compute.dispatch(curlPipeline, width: width, height: height)
        compute.setTexture(velocity[velocityIndex], index: 0)
        compute.setTexture(curl, index: 1)
        compute.setTexture(velocity[1 - velocityIndex], index: 2)
        compute.dispatch(vorticityPipeline, width: width, height: height)
        velocityIndex = 1 - velocityIndex

        // 3. Pressure projection.
        compute.setTexture(velocity[velocityIndex], index: 0)
        compute.setTexture(divergence, index: 1)
        compute.dispatch(divergencePipeline, width: width, height: height)
        for _ in 0..<pressureIterations {
            compute.setTexture(pressure[pressureIndex], index: 0)
            compute.setTexture(divergence, index: 1)
            compute.setTexture(pressure[1 - pressureIndex], index: 2)
            compute.dispatch(jacobiPipeline, width: width, height: height)
            pressureIndex = 1 - pressureIndex
        }
        compute.setTexture(pressure[pressureIndex], index: 0)
        compute.setTexture(velocity[velocityIndex], index: 1)
        compute.setTexture(velocity[1 - velocityIndex], index: 2)
        compute.dispatch(gradientPipeline, width: width, height: height)
        velocityIndex = 1 - velocityIndex

        // 4. Advect dye through the divergence-free velocity (adds the splat colors).
        compute.setTexture(velocity[velocityIndex], index: 0)
        compute.setTexture(dye[dyeIndex], index: 1)
        compute.setTexture(dye[1 - dyeIndex], index: 2)
        compute.dispatch(advectDye, width: width, height: height)
        dyeIndex = 1 - dyeIndex
        compute.endEncoding()

        encodeFullscreen(displayPipeline, into: commandBuffer, pass: pass, uniforms: &uniforms, textures: [dye[dyeIndex]])
    }

    private func makeParams(width: Int, height: Int, uniforms: EffectUniforms) -> FluidParams {
        let grid = SIMD2(Float(width), Float(height))
        let cellsPerPoint = grid.x / Float(max(bounds.width, 1))
        let t = uniforms.time
        var params = FluidParams(
            gridSize: grid,
            deltaTime: 1.0 / 60,
            vorticity: 30,
            velocityDissipation: 0.995,
            dyeDissipation: 0.992,
            splatCount: 0
        )
        var splats: [(position: SIMD4<Float>, force: SIMD4<Float>, color: SIMD4<Float>)] = []

        // Splats are per-frame impulses: velocity added to the cells under them every frame.
        // Two nozzles at the bottom corners, sweeping and changing hue.
        for side in [Float(-1), 1] {
            let angle = -Float.pi / 2 + side * (0.45 + 0.25 * sin(t * 0.8 + side))
            let origin = SIMD2(grid.x * (0.5 + side * 0.38), grid.y * 0.93)
            let force = SIMD2(cos(angle), sin(angle)) * grid.y * 0.08
            let color = Self.hue(t * 0.07 + (side > 0 ? 0.5 : 0)) * 0.06
            splats.append((SIMD4(origin.x, origin.y, grid.x * 0.025, 0), SIMD4(force.x, force.y, 0, 0), color))
        }
        // The finger pushes with its own velocity and paints.
        if touch.isActive {
            let position = SIMD2(Float(touch.location.x), Float(touch.location.y)) * cellsPerPoint
            let force = fingerVelocity * cellsPerPoint * 0.1
            splats.append((SIMD4(position.x, position.y, grid.x * 0.035, 0), SIMD4(force.x, force.y, 0, 0), Self.hue(t * 0.2) * 0.12))
        }

        params.splatCount = UInt32(min(splats.count, Self.maxSplats))
        withUnsafeMutableBytes(of: &params.splatPositions) { positions in
            withUnsafeMutableBytes(of: &params.splatForces) { forces in
                withUnsafeMutableBytes(of: &params.splatColors) { colors in
                    let stride = MemoryLayout<SIMD4<Float>>.stride
                    for (index, splat) in splats.prefix(Self.maxSplats).enumerated() {
                        positions.storeBytes(of: splat.position, toByteOffset: index * stride, as: SIMD4<Float>.self)
                        forces.storeBytes(of: splat.force, toByteOffset: index * stride, as: SIMD4<Float>.self)
                        colors.storeBytes(of: splat.color, toByteOffset: index * stride, as: SIMD4<Float>.self)
                    }
                }
            }
        }
        return params
    }

    private func allocateIfNeeded(resolution: SIMD2<Float>) {
        let width = Self.resolutions[resolutionIndex]
        let height = max(Int(Float(width) * resolution.y / max(resolution.x, 1)), 1)
        guard velocity.first?.width != width || velocity.first?.height != height else { return }
        guard let context = MetalEffectContext.shared else { return }
        velocity = (0..<2).compactMap { _ in context.makeTexture(width: width, height: height, format: .rg16Float) }
        dye = (0..<2).compactMap { _ in context.makeTexture(width: width, height: height, format: .rgba16Float) }
        pressure = (0..<2).compactMap { _ in context.makeTexture(width: width, height: height, format: .r16Float) }
        divergence = context.makeTexture(width: width, height: height, format: .r16Float)
        curl = context.makeTexture(width: width, height: height, format: .r16Float)
        needsClear = true
    }

    /// Private textures start with undefined contents; zero them with a blit from a zeroed buffer.
    private func clear(_ texture: MTLTexture, with blit: MTLBlitCommandEncoder) {
        let bytesPerPixel = texture.pixelFormat == .rgba16Float ? 8 : (texture.pixelFormat == .rg16Float ? 4 : 2)
        let bytesPerRow = texture.width * bytesPerPixel
        let length = bytesPerRow * texture.height
        guard let zeros = MetalEffectContext.shared?.device.makeBuffer(length: length, options: .storageModePrivate) else { return }
        blit.fill(buffer: zeros, range: 0..<length, value: 0)
        blit.copy(
            from: zeros, sourceOffset: 0, sourceBytesPerRow: bytesPerRow, sourceBytesPerImage: length,
            sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1),
            to: texture, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
    }

    private static func hue(_ value: Float) -> SIMD4<Float> {
        let h = value - floor(value)
        let r = abs(h * 6 - 3) - 1
        let g = 2 - abs(h * 6 - 2)
        let b = 2 - abs(h * 6 - 4)
        return SIMD4(min(max(r, 0), 1), min(max(g, 0), 1), min(max(b, 0), 1), 0)
    }
}
