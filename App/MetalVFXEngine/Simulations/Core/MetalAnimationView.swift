import UIKit
import MetalKit

/// Mirrors `EffectUniforms` in EffectsCommon.h (144 bytes).
struct EffectUniforms {
    static let maxBlobs = 5

    var progress: Float = 0
    var time: Float = 0
    var resolution: SIMD2<Float> = .zero
    var touch: SIMD2<Float> = .zero
    var touchStrength: Float = 0
    var blobCount: Int32 = 0
    var blobs: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>) = (.zero, .zero, .zero, .zero, .zero)
    var custom: (SIMD4<Float>, SIMD4<Float>) = (.zero, .zero)

    mutating func setBlob(_ index: Int, _ value: SIMD4<Float>) {
        precondition(index < Self.maxBlobs)
        withUnsafeMutableBytes(of: &blobs) {
            $0.storeBytes(of: value, toByteOffset: index * MemoryLayout<SIMD4<Float>>.stride, as: SIMD4<Float>.self)
        }
    }

    mutating func setCustom(_ index: Int, _ value: SIMD4<Float>) {
        precondition(index < 2)
        withUnsafeMutableBytes(of: &custom) {
            $0.storeBytes(of: value, toByteOffset: index * MemoryLayout<SIMD4<Float>>.stride, as: SIMD4<Float>.self)
        }
    }
}

/// Device, queue and pipelines shared by every Metal effect on screen.
final class MetalEffectContext {
    static let shared = MetalEffectContext()

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    private let library: MTLLibrary
    private var renderPipelines: [String: MTLRenderPipelineState] = [:]
    private var computePipelines: [String: MTLComputePipelineState] = [:]

    private init?() {
        guard let gpu = VFXGPU.shared else { return nil }
        device = gpu.device
        commandQueue = gpu.queue
        library = gpu.library
    }

    enum Blending {
        case none
        /// one + one: light accumulates (particles, glow).
        case additive
        /// one + (1 - source alpha): for textures with premultiplied alpha.
        case premultipliedAlpha
    }

    /// Render pipeline; by default for the drawable's pixel format without depth.
    func renderPipeline(
        vertex: String,
        fragment: String,
        blending: Blending = .none,
        pixelFormat: MTLPixelFormat = .bgra8Unorm,
        depthFormat: MTLPixelFormat = .invalid
    ) -> MTLRenderPipelineState? {
        let key = "\(vertex)|\(fragment)|\(blending)|\(pixelFormat.rawValue)|\(depthFormat.rawValue)"
        if let cached = renderPipelines[key] {
            return cached
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: vertex)
        descriptor.fragmentFunction = library.makeFunction(name: fragment)
        descriptor.depthAttachmentPixelFormat = depthFormat
        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = pixelFormat
        if blending != .none {
            attachment.isBlendingEnabled = true
            attachment.rgbBlendOperation = .add
            attachment.alphaBlendOperation = .add
            attachment.sourceRGBBlendFactor = .one
            attachment.sourceAlphaBlendFactor = .one
            let destination: MTLBlendFactor = blending == .additive ? .one : .oneMinusSourceAlpha
            attachment.destinationRGBBlendFactor = destination
            attachment.destinationAlphaBlendFactor = destination
        }
        let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor)
        renderPipelines[key] = pipeline
        return pipeline
    }

    func computePipeline(function name: String) -> MTLComputePipelineState? {
        if let cached = computePipelines[name] {
            return cached
        }
        let pipeline = library.makeFunction(name: name).flatMap { try? device.makeComputePipelineState(function: $0) }
        computePipelines[name] = pipeline
        return pipeline
    }

    func makeFunction(name: String) -> MTLFunction? {
        library.makeFunction(name: name)
    }

    /// GPU-private 2D (or 3D when `depth` > 1) texture that kernels read and write.
    func makeTexture(
        width: Int,
        height: Int,
        depth: Int = 1,
        format: MTLPixelFormat,
        usage: MTLTextureUsage = [.shaderRead, .shaderWrite]
    ) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = depth > 1 ? .type3D : .type2D
        descriptor.pixelFormat = format
        descriptor.width = max(width, 1)
        descriptor.height = max(height, 1)
        descriptor.depth = max(depth, 1)
        descriptor.usage = usage
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)
    }
}

extension MTLComputeCommandEncoder {
    /// One thread per element; kernels must ignore threads past `count`.
    func dispatch(_ pipeline: MTLComputePipelineState, count: Int) {
        guard count > 0 else { return }
        let width = min(pipeline.maxTotalThreadsPerThreadgroup, 256)
        setComputePipelineState(pipeline)
        dispatchThreadgroups(
            MTLSize(width: (count + width - 1) / width, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1)
        )
    }

    /// One thread per texel; kernels must ignore threads outside the grid.
    func dispatch(_ pipeline: MTLComputePipelineState, width: Int, height: Int, depth: Int = 1) {
        guard width > 0, height > 0, depth > 0 else { return }
        let group = depth > 1 ? MTLSize(width: 8, height: 8, depth: 4) : MTLSize(width: 16, height: 16, depth: 1)
        setComputePipelineState(pipeline)
        dispatchThreadgroups(
            MTLSize(
                width: (width + group.width - 1) / group.width,
                height: (height + group.height - 1) / group.height,
                depth: (depth + group.depth - 1) / group.depth
            ),
            threadsPerThreadgroup: group
        )
    }
}

/// Base for the GPU implementations. By default it draws one full-screen triangle with
/// `fragmentFunction`; effects with their own passes (compute, particles) override `encode`.
/// The CPU only fills `EffectUniforms` and encodes the frame.
class MetalAnimationView: UIView, MTKViewDelegate {
    /// Fragment function of the default full-screen pass.
    class var fragmentFunction: String? { nil }
    /// Set to a depth format for effects that draw 3D geometry.
    class var depthPixelFormat: MTLPixelFormat { .invalid }

    var progress: Float = 0 {
        didSet { progress = min(max(progress, 0), 1) }
    }
    var controls: [MetalEffectControl] { [] }

    private(set) var displayedProgress: Float = 0
    private(set) var touch = TouchInput()

    var pixelsPerPoint: CGFloat {
        bounds.width > 0 ? metalView.drawableSize.width / bounds.width : contentScaleFactor
    }

    private let metalView = MTKView(frame: .zero, device: MetalEffectContext.shared?.device)
    private lazy var fullscreenPipeline = Self.fragmentFunction.flatMap {
        MetalEffectContext.shared?.renderPipeline(vertex: "fullscreen_vertex", fragment: $0)
    }
    private var animationTime: Float = 0
    private var lastFrameTime: CFTimeInterval = 0
    private var animationRequested = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        backgroundColor = .black
        clipsToBounds = true
        isMultipleTouchEnabled = false

        metalView.colorPixelFormat = .bgra8Unorm
        metalView.depthStencilPixelFormat = Self.depthPixelFormat
        metalView.framebufferOnly = true
        metalView.preferredFramesPerSecond = 120
        metalView.enableSetNeedsDisplay = false
        metalView.isPaused = true
        metalView.isUserInteractionEnabled = false
        metalView.delegate = self
        metalView.frame = bounds
        metalView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(metalView)
        NotificationCenter.default.addObserver(self, selector: #selector(updateAnimationState),
                                               name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateAnimationState),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    /// Hook for effect-specific uniforms and CPU-side simulation; runs on the main thread
    /// before each frame is encoded.
    func update(_ uniforms: inout EffectUniforms, deltaTime: Double) {}

    /// Encodes the frame. The default draws `fragmentFunction` over the whole view.
    func encode(into commandBuffer: MTLCommandBuffer, pass: MTLRenderPassDescriptor, uniforms: inout EffectUniforms) {
        guard let fullscreenPipeline else { return }
        encodeFullscreen(fullscreenPipeline, into: commandBuffer, pass: pass, uniforms: &uniforms)
    }

    /// Draws one full-screen triangle with `pipeline`, binding the uniforms and `textures` to the
    /// fragment stage. Every pixel is overwritten, so the previous contents are not loaded.
    func encodeFullscreen(
        _ pipeline: MTLRenderPipelineState,
        into commandBuffer: MTLCommandBuffer,
        pass: MTLRenderPassDescriptor,
        uniforms: inout EffectUniforms,
        textures: [MTLTexture] = []
    ) {
        pass.colorAttachments[0].loadAction = .dontCare
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<EffectUniforms>.stride, index: 0)
        for (index, texture) in textures.enumerated() {
            encoder.setFragmentTexture(texture, index: index)
        }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    // MARK: - Animation

    func startAnimation() {
        animationRequested = true
        updateAnimationState()
    }

    func stopAnimation() {
        animationRequested = false
        touch = TouchInput()
        updateAnimationState()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateAnimationState()
    }

    @objc private func updateAnimationState(_ notification: Notification? = nil) {
        let active = notification?.name != UIApplication.willResignActiveNotification
            && UIApplication.shared.applicationState == .active
        let paused = !animationRequested || window == nil || !active
        if metalView.isPaused && !paused { lastFrameTime = CACurrentMediaTime() }
        metalView.isPaused = paused
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let context = MetalEffectContext.shared,
              let passDescriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = context.commandQueue.makeCommandBuffer() else { return }

        // Advance simulation time after acquiring the next drawable.
        let frameTime = CACurrentMediaTime()
        let dt = max(0, min(frameTime - lastFrameTime, 0.1))
        lastFrameTime = frameTime
        animationTime += Float(dt)
        displayedProgress = eased(displayedProgress, toward: progress, deltaTime: dt)
        touch.advance(deltaTime: dt)

        let scale = Float(pixelsPerPoint)
        var uniforms = EffectUniforms()
        uniforms.progress = displayedProgress
        uniforms.time = animationTime
        uniforms.resolution = SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height))
        uniforms.touch = SIMD2(Float(touch.location.x), Float(touch.location.y)) * scale
        uniforms.touchStrength = touch.strength
        update(&uniforms, deltaTime: dt)
        encode(into: commandBuffer, pass: passDescriptor, uniforms: &uniforms)

        commandBuffer.present(drawable)
        commandBuffer.commit()

    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        touch.track(touches, in: self, isActive: true)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        touch.track(touches, in: self, isActive: true)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        touch.track(touches, in: self, isActive: false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touch.track(touches, in: self, isActive: false)
    }
}
