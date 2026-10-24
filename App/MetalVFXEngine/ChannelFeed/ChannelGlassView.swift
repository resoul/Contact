//
//  ChannelGlassView.swift
//  controller
//
//  Glass controls over the feed (channel_glass_fragment in ChannelFX.metal): a strip of the screen
//  with rounded shapes in it — the header pill, round buttons — drawn as thick frosted glass. The
//  posts under the strip and the wallpaper are refracted at the rim and blurred. The rim light sits
//  opposite gravity, so it slides around the edges as the phone tilts. Touch-through: put the real
//  buttons on top.
//
//  Scrolling costs the CPU nothing: posts are rasterized into textures now and then
//  (FeedSnapshotCache), and every frame the GPU just lays those textures out where the posts are
//  and blurs them. Snapshotting the feed every frame instead took ~16 ms per strip.
//

import UIKit
import Metal

/// Mirrors `FeedGlassUniforms` in ChannelFX.metal.
private struct FeedGlassUniforms {
    var viewport: SIMD2<Float>
    var scale: Float
    var count: UInt32
    var snapshotOrigin: SIMD2<Float>
    var snapshotSize: SIMD2<Float>
    var gravity: SIMD2<Float>
    var refraction: Float
    var time: Float
    var tint: SIMD4<Float>
}

/// Mirrors `FeedGlassShape` in ChannelFX.metal.
private struct FeedGlassShape {
    var rect: SIMD4<Float>
    var params: SIMD4<Float>
}

/// Mirrors `FeedQuadUniforms` in ChannelFX.metal.
private struct FeedQuadUniforms {
    var viewport: SIMD2<Float>
    var unused: SIMD2<Float> = .zero
    var rect: SIMD4<Float>
}

/// Low-resolution snapshots of the feed's posts, shared by the glass strips. A post is re-rendered
/// when its size changes or every `maxAge` seconds (live counters — illegible under the blur anyway),
/// and only one per frame, so scrolling never waits on rasterization.
final class FeedSnapshotCache {
    /// Points to pixels: the glass blurs what it shows, so a quarter of the pixels is plenty.
    let scale: CGFloat = 0.5
    var maxAge: CFTimeInterval = 2

    private struct Entry {
        var texture: MTLTexture
        var size: CGSize
        var time: CFTimeInterval
    }

    private var entries: [ObjectIdentifier: Entry] = [:]
    private var lastRender: CFTimeInterval = 0

    func texture(for view: UIView) -> MTLTexture? {
        let key = ObjectIdentifier(view)
        let now = CACurrentMediaTime()
        let entry = entries[key]
        let stale = entry.map { $0.size != view.bounds.size || now - $0.time > maxAge } ?? true
        // A missing snapshot is rendered right away; stale ones wait their turn, one per frame.
        guard stale, entry == nil || now - lastRender > 0.012 else { return entry?.texture }
        guard let texture = render(view) else { return entry?.texture }
        entries[key] = Entry(texture: texture, size: view.bounds.size, time: now)
        lastRender = now
        return texture
    }

    /// Forgets posts that are gone.
    func keep(_ views: [UIView]) {
        let keys = Set(views.map(ObjectIdentifier.init))
        entries = entries.filter { keys.contains($0.key) }
    }

    /// CALayer.render: no round trip to the render server (unlike drawHierarchy). Metal views inside
    /// the post (avatar liquid, the spoiler) are hidden for it: rendering a CAMetalLayer on the CPU can
    /// stall for tens of milliseconds, and under the blurred glass they would not show anyway. Hiding and
    /// unhiding within one transaction never reaches the screen.
    private func render(_ view: UIView) -> MTLTexture? {
        var metal: [UIView] = []
        func collect(_ view: UIView) {
            for subview in view.subviews {
                if subview is VFXMetalView, !subview.isHidden {
                    metal.append(subview)
                } else {
                    collect(subview)
                }
            }
        }
        collect(view)
        metal.forEach { $0.layer.isHidden = true }
        defer { metal.forEach { $0.layer.isHidden = false } }
        return VFXGPU.shared?.makeTexture(size: view.bounds.size, scale: scale) { context in
            view.layer.render(in: context)
        }
    }
}

final class ChannelGlassView: VFXMetalView {
    struct Shape {
        var rect: CGRect
        var cornerRadius: CGFloat
        var opacity: CGFloat = 1
    }

    /// The views that scroll under the glass (the posts), and the snapshot cache they share.
    var backdropViews: (() -> [UIView])?
    var snapshots: FeedSnapshotCache?
    weak var wallpaper: ChannelWallpaperView?
    /// Shapes in this view's coordinates.
    var shapes: [Shape] = []
    /// When set, asked for the shapes every frame (for controls that move or fade).
    var shapeProvider: (() -> [Shape])?
    var refraction: CGFloat = 10
    var tint = UIColor(red: 0.10, green: 0.09, blue: 0.14, alpha: 0.5)

    private var backdrop: MTLTexture?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        preferredFramesPerSecond = 60
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The posts under the strip, laid out where they are right now, into a mipmapped texture.
    private func composeBackdrop(region: CGRect, commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        guard let gpu, let snapshots, let views = backdropViews?(),
              let pipeline = gpu.renderPipeline(vertex: "channel_quad_vertex", fragment: "channel_quad_fragment")
        else { return nil }
        let width = max(1, Int((region.width * snapshots.scale).rounded()))
        let height = max(1, Int((region.height * snapshots.scale).rounded()))
        if backdrop?.width != width || backdrop?.height != height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: gpu.pixelFormat, width: width,
                                                                      height: height, mipmapped: true)
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .private
            backdrop = gpu.device.makeTexture(descriptor: descriptor)
        }
        guard let backdrop else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = backdrop
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        encoder.setRenderPipelineState(pipeline)
        for view in views where !view.isHidden && view.alpha > 0.05 {
            let frame = view.convert(view.bounds, to: self)
            guard frame.intersects(region), let texture = snapshots.texture(for: view) else { continue }
            var uniforms = FeedQuadUniforms(
                viewport: SIMD2(Float(region.width), Float(region.height)),
                rect: SIMD4(Float(frame.minX - region.minX), Float(frame.minY - region.minY),
                            Float(frame.width), Float(frame.height)))
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<FeedQuadUniforms>.stride, index: 0)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        encoder.endEncoding()
        if let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: backdrop)
            blit.endEncoding()
        }
        return backdrop
    }

    override func encode(into commandBuffer: MTLCommandBuffer, target: MTLTexture) {
        if let shapeProvider {
            shapes = shapeProvider()
        }
        // The posts under the strip, padded so the rim can bend in what is just outside it.
        let pad = refraction + 6
        let region = bounds.insetBy(dx: -pad, dy: -pad)
        let composed = composeBackdrop(region: region, commandBuffer: commandBuffer)
        guard let gpu, let wallpaper, let pattern = wallpaper.pattern, !shapes.isEmpty,
              let pipeline = gpu.renderPipeline(vertex: "channel_vertex", fragment: "channel_glass_fragment"),
              let snapshot = composed,
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass(target: target)) else {
            super.encode(into: commandBuffer, target: target)
            return
        }
        let viewport = SIMD2(Float(target.width), Float(target.height))
        let gravity = LiquidUIMotion.shared.gravity
        var uniforms = FeedGlassUniforms(
            viewport: viewport, scale: Float(contentScaleFactor), count: UInt32(shapes.count),
            snapshotOrigin: SIMD2(Float(-pad), Float(-pad)),
            snapshotSize: SIMD2(Float(region.width), Float(region.height)),
            gravity: SIMD2(Float(gravity.x), Float(gravity.y)), refraction: Float(refraction), time: Float(time),
            tint: tint.vfxSIMD(with: traitCollection))
        var wall = wallpaper.uniforms(viewport: viewport, scale: contentScaleFactor, origin: convert(CGPoint.zero, to: wallpaper))
        let data = shapes.map {
            FeedGlassShape(rect: SIMD4(Float($0.rect.minX), Float($0.rect.minY), Float($0.rect.width), Float($0.rect.height)),
                           params: SIMD4(Float($0.cornerRadius), Float($0.opacity), 0, 0))
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FeedGlassUniforms>.stride, index: 0)
        encoder.setFragmentBytes(data, length: MemoryLayout<FeedGlassShape>.stride * data.count, index: 1)
        encoder.setFragmentBytes(&wall, length: MemoryLayout<WallpaperUniforms>.stride, index: 2)
        encoder.setFragmentTexture(snapshot, index: 0)
        encoder.setFragmentTexture(pattern, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}
