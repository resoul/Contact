//
//  ChannelWallpaperView.swift
//  controller
//
//  The chat wallpaper (channel_wallpaper_fragment in ChannelFX.metal): a Telegram-style four-color
//  gradient under a doodle pattern. The doodles sit on a nearer layer than the gradient, so tilting
//  the phone slides them more — a little parallax depth. `pulse(from:)` steps the gradient's colors
//  one place around their ring and sends a ripple through the doodles from that point.
//

import UIKit
import Metal

/// Mirrors `WallpaperUniforms` in ChannelFX.metal. Shared with the glass, which draws the wallpaper too.
struct WallpaperUniforms {
    var viewport: SIMD2<Float>
    var scale: Float
    var patternAlpha: Float
    var size: SIMD2<Float>
    var origin: SIMD2<Float>
    var color0: SIMD4<Float>
    var color1: SIMD4<Float>
    var color2: SIMD4<Float>
    var color3: SIMD4<Float>
    var points01: SIMD4<Float>
    var points23: SIMD4<Float>
    var patternOffset: SIMD2<Float>
    var gradientOffset: SIMD2<Float>
    var rippleOrigin: SIMD2<Float>
    var rippleRadius: Float
    var rippleStrength: Float
    var tile: Float
    var time: Float
    var night: Float = 0
    var unused: Float = 0
}

final class ChannelWallpaperView: VFXMetalView {
    var colors: [UIColor] = [
        UIColor(red: 0.20, green: 0.13, blue: 0.33, alpha: 1),
        UIColor(red: 0.08, green: 0.10, blue: 0.20, alpha: 1),
        UIColor(red: 0.27, green: 0.12, blue: 0.30, alpha: 1),
        UIColor(red: 0.06, green: 0.17, blue: 0.24, alpha: 1),
    ]
    var patternAlpha: CGFloat = 0.075
    let tile: CGFloat = 300
    private(set) var pattern: MTLTexture?

    /// Telegram's ring of eight gradient positions; the four colors sit on every other one.
    private let ring: [CGPoint] = [
        CGPoint(x: 0.80, y: 0.10), CGPoint(x: 0.60, y: 0.20), CGPoint(x: 0.35, y: 0.25), CGPoint(x: 0.25, y: 0.60),
        CGPoint(x: 0.20, y: 0.90), CGPoint(x: 0.40, y: 0.80), CGPoint(x: 0.65, y: 0.75), CGPoint(x: 0.75, y: 0.40),
    ]
    private var phase = Spring1D(0, stiffness: 4.5, dampingRatio: 0.95)
    private var phaseTarget: CGFloat = 0
    private var parallax = IslandSpring(.zero, stiffness: 5, dampingRatio: 0.9)
    private var ripple: (origin: CGPoint, start: CFTimeInterval)?
    /// Theme palettes (the Mini-Telegram chat): colors glide to a new theme, and day turns to night
    /// through a dusk with stars. When nil, `colors` is used as is.
    private var themeDay: [SIMD4<Float>]?
    private var themeNight: [SIMD4<Float>] = []
    private var shownDay: [SIMD4<Float>] = []
    private var shownNight: [SIMD4<Float>] = []
    private var nightSpring = Spring1D(0, stiffness: 2.3, dampingRatio: 1)
    private var nightTarget: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        preferredFramesPerSecond = 60
        clearColor = MTLClearColor(red: 0.08, green: 0.07, blue: 0.12, alpha: 1)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Steps the gradient around its ring and sends a ripple out from `point` (own coordinates).
    func pulse(from point: CGPoint) {
        phaseTarget += 1
        ripple = (point, time)
    }

    /// Moves the gradient to a theme's day and night palettes.
    func setTheme(day: [UIColor], night: [UIColor], animated: Bool) {
        let dayColors = day.map { $0.vfxSIMD(with: traitCollection) }
        let nightColors = night.map { $0.vfxSIMD(with: traitCollection) }
        themeDay = dayColors
        themeNight = nightColors
        if !animated || shownDay.isEmpty {
            shownDay = dayColors
            shownNight = nightColors
        }
        isPaused = false
    }

    /// Day → dusk → night (or back) over a couple of seconds.
    func setNight(_ on: Bool, animated: Bool) {
        nightTarget = on ? 1 : 0
        if !animated { nightSpring.value = nightTarget }
        isPaused = false
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if pattern == nil, window != nil {
            pattern = makePattern()
        }
    }

    override func update(deltaTime: CFTimeInterval) {
        let gravity = LiquidUIMotion.shared.gravity
        parallax.step(toward: CGPoint(x: gravity.x * 22, y: (gravity.y - 0.85) * 22), deltaTime: deltaTime)
        phase.step(toward: phaseTarget, deltaTime: deltaTime)
        nightSpring.step(toward: nightTarget, deltaTime: deltaTime)
        if let themeDay {
            let rate = Float(min(1, deltaTime * 3.5))
            shownDay = zip(shownDay, themeDay).map { $0 + ($1 - $0) * rate }
            shownNight = zip(shownNight, themeNight).map { $0 + ($1 - $0) * rate }
        }
        if let ripple, time - ripple.start > 1.6 {
            self.ripple = nil
        }
    }

    private func ringPoint(_ position: CGFloat) -> SIMD2<Float> {
        let count = CGFloat(ring.count)
        let wrapped = (position.truncatingRemainder(dividingBy: count) + count).truncatingRemainder(dividingBy: count)
        let index = Int(wrapped)
        let t = wrapped - CGFloat(index)
        let point = CGPoint.lerp(ring[index], ring[(index + 1) % ring.count], t)
        return SIMD2(Float(point.x), Float(point.y))
    }

    /// The wallpaper as seen by a target of `viewport` pixels whose top-left is `origin` in this view.
    func uniforms(viewport: SIMD2<Float>, scale: CGFloat, origin: CGPoint) -> WallpaperUniforms {
        let night = Float(min(max(nightSpring.value, 0), 1))
        let resolved = themeDay == nil ? colors.map { $0.vfxSIMD(with: traitCollection) }
            : zip(shownDay, shownNight).map { $0 + ($1 - $0) * night }
        let p = (0..<4).map { ringPoint(phase.value + CGFloat($0 * 2)) }
        let rippleAge = ripple.map { time - $0.start } ?? 0
        return WallpaperUniforms(
            viewport: viewport, scale: Float(scale), patternAlpha: Float(patternAlpha),
            size: SIMD2(Float(bounds.width), Float(bounds.height)),
            origin: SIMD2(Float(origin.x), Float(origin.y)),
            color0: resolved[0], color1: resolved[1], color2: resolved[2], color3: resolved[3],
            points01: SIMD4(p[0].x, p[0].y, p[1].x, p[1].y), points23: SIMD4(p[2].x, p[2].y, p[3].x, p[3].y),
            patternOffset: SIMD2(Float(parallax.position.x), Float(parallax.position.y)),
            gradientOffset: SIMD2(Float(parallax.position.x * 0.35), Float(parallax.position.y * 0.35)),
            rippleOrigin: SIMD2(Float(ripple?.origin.x ?? 0), Float(ripple?.origin.y ?? 0)),
            rippleRadius: Float(rippleAge * 620),
            rippleStrength: ripple == nil ? 0 : Float(max(0, 1 - rippleAge / 1.6)),
            tile: Float(tile), time: Float(time), night: night)
    }

    override func encode(into commandBuffer: MTLCommandBuffer, target: MTLTexture) {
        guard let gpu, let pattern,
              let pipeline = gpu.renderPipeline(vertex: "channel_vertex", fragment: "channel_wallpaper_fragment"),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass(target: target)) else {
            super.encode(into: commandBuffer, target: target)
            return
        }
        var uniforms = uniforms(viewport: SIMD2(Float(target.width), Float(target.height)), scale: contentScaleFactor,
                                origin: .zero)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<WallpaperUniforms>.stride, index: 0)
        encoder.setFragmentTexture(pattern, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    // MARK: Doodles

    /// One seamless tile of outlined doodles in white, mipmapped so the glass can sample it blurred.
    private func makePattern() -> MTLTexture? {
        guard let gpu else { return nil }
        let symbols = ["bubble.left", "heart", "star", "music.note", "camera", "paperplane", "gamecontroller",
                       "cup.and.saucer", "leaf", "moon", "bolt", "gift", "pawprint", "cloud", "sparkles", "headphones",
                       "airplane", "balloon", "theatermasks", "umbrella", "bicycle", "puzzlepiece", "fish", "crown",
                       "lightbulb"]
        let scale: CGFloat = 2
        let pixels = Int(tile * scale)
        guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: pixels * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                          | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        context.translateBy(x: 0, y: CGFloat(pixels))
        context.scaleBy(x: scale, y: -scale)
        UIGraphicsPushContext(context)
        var random = SplitMix(seed: 7)
        let grid = 5
        let cell = tile / CGFloat(grid)
        for row in 0..<grid {
            for column in 0..<grid {
                let name = symbols[(row * grid + column) % symbols.count]
                let size = 20 + random.next() * 10
                let config = UIImage.SymbolConfiguration(pointSize: size, weight: .light)
                guard let image = UIImage(systemName: name, withConfiguration: config)?
                    .withTintColor(.white, renderingMode: .alwaysOriginal) else { continue }
                let jitter = CGPoint(x: (random.next() - 0.5) * cell * 0.3, y: (random.next() - 0.5) * cell * 0.3)
                let center = CGPoint(x: (CGFloat(column) + 0.5) * cell + jitter.x, y: (CGFloat(row) + 0.5) * cell + jitter.y)
                context.saveGState()
                context.translateBy(x: center.x, y: center.y)
                context.rotate(by: (random.next() - 0.5) * 1.2)
                image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2,
                                      width: image.size.width, height: image.size.height))
                context.restoreGState()
            }
        }
        UIGraphicsPopContext()
        guard let bytes = context.data else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: gpu.pixelFormat, width: pixels, height: pixels,
                                                                  mipmapped: true)
        descriptor.usage = .shaderRead
        guard let texture = gpu.device.makeTexture(descriptor: descriptor) else { return nil }
        texture.replace(region: MTLRegionMake2D(0, 0, pixels, pixels), mipmapLevel: 0, withBytes: bytes,
                        bytesPerRow: context.bytesPerRow)
        if let commandBuffer = gpu.queue.makeCommandBuffer(), let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: texture)
            blit.endEncoding()
            commandBuffer.commit()
        }
        return texture
    }
}

/// Small deterministic random numbers, so the doodle tile is the same every launch.
struct SplitMix {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    /// 0…1
    mutating func next() -> CGFloat {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return CGFloat(z >> 11) / CGFloat(1 << 53)
    }
}
