//
//  VFXMetalView.swift
//  controller
//
//  Shared plumbing for MetalVFXEngine: one GPU context, pipeline caches, snapshot → texture,
//  and a CAMetalLayer-backed base view driven by a 120 Hz (ProMotion) display link.
//

import UIKit
import Metal

final class VFXGPU {
    static let shared = VFXGPU()

    let device: MTLDevice
    let queue: MTLCommandQueue
    let library: MTLLibrary
    let pixelFormat: MTLPixelFormat = .bgra8Unorm

    private var renderPipelines: [String: MTLRenderPipelineState] = [:]
    private var computePipelines: [String: MTLComputePipelineState] = [:]

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else { return nil }
        self.device = device
        self.queue = queue
        self.library = library
    }

    func renderPipeline(vertex: String, fragment: String, format: MTLPixelFormat? = nil) -> MTLRenderPipelineState? {
        let format = format ?? pixelFormat
        let key = vertex + "|" + fragment + "|\(format.rawValue)"
        if let cached = renderPipelines[key] { return cached }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = key
        descriptor.vertexFunction = library.makeFunction(name: vertex)
        descriptor.fragmentFunction = library.makeFunction(name: fragment)
        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = format
        attachment.isBlendingEnabled = true
        attachment.sourceRGBBlendFactor = .one
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        do {
            let state = try device.makeRenderPipelineState(descriptor: descriptor)
            renderPipelines[key] = state
            return state
        } catch {
            assertionFailure("Render pipeline \(key) failed: \(error)")
            return nil
        }
    }

    func computePipeline(_ name: String) -> MTLComputePipelineState? {
        if let cached = computePipelines[name] { return cached }
        guard let function = library.makeFunction(name: name) else {
            assertionFailure("Missing kernel \(name)")
            return nil
        }
        do {
            let state = try device.makeComputePipelineState(function: function)
            computePipelines[name] = state
            return state
        } catch {
            assertionFailure("Compute pipeline \(name) failed: \(error)")
            return nil
        }
    }

    /// Renders an on-screen view into a premultiplied BGRA texture (top-left origin), keeping transparency.
    func makeTexture(snapshotting view: UIView, scale: CGFloat) -> MTLTexture? {
        let width = Int((view.bounds.width * scale).rounded())
        let height = Int((view.bounds.height * scale).rounded())
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                          | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        UIGraphicsPushContext(context)
        if !view.drawHierarchy(in: view.bounds, afterScreenUpdates: false) {
            view.layer.render(in: context)
        }
        UIGraphicsPopContext()

        guard let bytes = context.data else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: width,
                                                                  height: height, mipmapped: false)
        descriptor.usage = .shaderRead
        let texture = device.makeTexture(descriptor: descriptor)
        texture?.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                         withBytes: bytes, bytesPerRow: context.bytesPerRow)
        return texture
    }
}

/// Snapshots live UI into textures every frame without reallocating: one reused bitmap and a
/// small ring of textures (the GPU may still be reading the previous frames' ones).
final class VFXSnapshotter {
    private var context: CGContext?
    private var ring: [MTLTexture] = []
    private var ringIndex = 0
    private var pixelSize: (width: Int, height: Int) = (0, 0)
    private var mipmapped = false

    /// Draws `region` (in `view`'s coordinates) of `view` as it is on screen right now.
    /// With `mipmapped`, the mip chain is generated in `commandBuffer` (needed for blur via lod).
    func snapshot(_ view: UIView, region: CGRect, scale: CGFloat, mipmapped: Bool = false,
                  commandBuffer: MTLCommandBuffer? = nil) -> MTLTexture? {
        guard let gpu = VFXGPU.shared else { return nil }
        let width = Int((region.width * scale).rounded()), height = Int((region.height * scale).rounded())
        guard width > 0, height > 0 else { return nil }
        if pixelSize != (width, height) || mipmapped != self.mipmapped || context == nil {
            pixelSize = (width, height)
            self.mipmapped = mipmapped
            context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                    | CGBitmapInfo.byteOrder32Little.rawValue)
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: gpu.pixelFormat, width: width,
                                                                      height: height, mipmapped: mipmapped)
            descriptor.usage = .shaderRead
            ring = (0..<3).compactMap { _ in gpu.device.makeTexture(descriptor: descriptor) }
        }
        guard let context, ring.count == 3, let bytes = context.data else { return nil }

        context.saveGState()
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -region.minX, y: -region.minY)
        UIGraphicsPushContext(context)
        if !view.drawHierarchy(in: view.bounds, afterScreenUpdates: false) {
            view.layer.render(in: context)
        }
        UIGraphicsPopContext()
        context.restoreGState()

        let texture = ring[ringIndex]
        ringIndex = (ringIndex + 1) % ring.count
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                        withBytes: bytes, bytesPerRow: context.bytesPerRow)
        if mipmapped, let blit = commandBuffer?.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: texture)
            blit.endEncoding()
        }
        return texture
    }
}

/// Base class: a CAMetalLayer that tracks the view's size and screen scale, plus a display link.
/// Subclasses override `update(deltaTime:)` for simulation and `encode(into:target:)` for drawing.
class VFXMetalView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }

    let gpu = VFXGPU.shared
    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    /// Stops the display link without removing the view. Rendering resumes from where it stopped.
    var isPaused = false {
        didSet { updateDisplayLink() }
    }
    var preferredFramesPerSecond: Float = 120 {
        didSet { applyFrameRate() }
    }
    /// Animation clock in seconds; paused time is excluded.
    private(set) var time: CFTimeInterval = 0
    /// Background the target is cleared to; transparent by default (overlay views).
    var clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayer()
    }

    private func configureLayer() {
        backgroundColor = .clear
        isOpaque = false
        metalLayer.device = gpu?.device
        metalLayer.pixelFormat = gpu?.pixelFormat ?? .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.isOpaque = false
        metalLayer.maximumDrawableCount = 3
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let window {
            contentScaleFactor = window.traitCollection.displayScale
            setNeedsLayout()
        }
        updateDisplayLink()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        metalLayer.contentsScale = contentScaleFactor
        let size = CGSize(width: (bounds.width * contentScaleFactor).rounded(),
                          height: (bounds.height * contentScaleFactor).rounded())
        guard size.width > 0, size.height > 0 else { return }
        // Only on a real resize: layout passes are frequent (any sibling changing size relayouts its
        // parents), and rendering synchronously here can block on nextDrawable mid-scroll.
        if size != metalLayer.drawableSize {
            metalLayer.drawableSize = size
            drawableSizeDidChange(size)
            renderFrame()   // fill the new size right away instead of waiting for the next tick
        }
    }

    // MARK: Subclass hooks

    func drawableSizeDidChange(_ size: CGSize) {}

    func update(deltaTime: CFTimeInterval) {}

    /// Encode this frame's passes. The default just clears to `clearColor`.
    func encode(into commandBuffer: MTLCommandBuffer, target: MTLTexture) {
        commandBuffer.makeRenderCommandEncoder(descriptor: renderPass(target: target))?.endEncoding()
    }

    func renderPass(target: MTLTexture) -> MTLRenderPassDescriptor {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = clearColor
        return pass
    }

    /// Draws one frame immediately (also used by subclasses to refresh while paused).
    func renderFrame() {
        guard let gpu, let drawable = metalLayer.nextDrawable(),
              let commandBuffer = gpu.queue.makeCommandBuffer() else { return }
        encode(into: commandBuffer, target: drawable.texture)
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: Display link

    private func updateDisplayLink() {
        let shouldRun = window != nil && !isPaused && gpu != nil
        if shouldRun, displayLink == nil {
            let link = CADisplayLink(target: VFXDisplayLinkTarget(view: self),
                                     selector: #selector(VFXDisplayLinkTarget.tick(_:)))
            displayLink = link
            applyFrameRate()
            link.add(to: .main, forMode: .common)
        } else if !shouldRun, let link = displayLink {
            link.invalidate()
            displayLink = nil
            lastTimestamp = nil
        }
    }

    private func applyFrameRate() {
        let fps = preferredFramesPerSecond
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, fps), maximum: fps, preferred: fps)
    }

    fileprivate func step(_ link: CADisplayLink) {
        let now = link.targetTimestamp
        let delta = lastTimestamp.map { min(now - $0, 1.0 / 20) } ?? 0   // clamp hitches
        lastTimestamp = now
        time += delta
        update(deltaTime: delta)
        renderFrame()
    }
}

/// Weak trampoline: CADisplayLink retains its target. Invalidates itself once the view is gone.
private final class VFXDisplayLinkTarget: NSObject {
    private weak var view: VFXMetalView?

    init(view: VFXMetalView) {
        self.view = view
    }

    @objc func tick(_ link: CADisplayLink) {
        guard let view else {
            link.invalidate()
            return
        }
        view.step(link)
    }
}

extension UIColor {
    /// Resolved sRGB components, for passing colors to shaders.
    func vfxSIMD(with traits: UITraitCollection = .current) -> SIMD4<Float> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD4(Float(r), Float(g), Float(b), Float(a))
    }
}
