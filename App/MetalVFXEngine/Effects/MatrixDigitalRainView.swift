//
//  MatrixDigitalRainView.swift
//  controller
//
//  "Matrix" digital rain: thousands of glyphs in one instanced draw call, at up to 120 FPS.
//  Shaders: Shaders/VFXEffects.metal (matrix_vertex / matrix_fragment).
//

import UIKit
import Metal

struct MatrixConfiguration {
    /// Base fall speed of a drop head, in points per second.
    var fallSpeed: CGFloat = 260
    /// Per-column spread of the fall speed: 0.5 means each stream runs at 50…150% of `fallSpeed`.
    var fallSpeedVariance: CGFloat = 0.5
    /// Glyph size in points; it also sets the number of columns that fit on screen.
    var fontSize: CGFloat = 16
    /// Leading (head) glyph.
    var primaryColor = UIColor(red: 0.85, green: 1.0, blue: 0.9, alpha: 1)
    /// Fading tail.
    var trailColor = UIColor(red: 0.0, green: 0.8, blue: 0.3, alpha: 1)
    /// Brightness lost per glyph behind the head (exponential). Higher = shorter trails.
    var fadeSpeed: CGFloat = 0.16
    /// How often a glyph is swapped for a random one, per second (on average).
    var glyphChangeRate: CGFloat = 1.5
    var backgroundColor: UIColor = .black
}

/// Mirrors `MatrixUniforms` in VFXEffects.metal — keep field order and types in sync.
private struct MatrixUniforms {
    var viewportSize: SIMD2<Float>
    var cellSize: SIMD2<Float>
    var atlasGrid: SIMD2<Float>
    var columns: UInt32
    var rows: UInt32
    var glyphCount: UInt32
    var time: Float
    var fallSpeed: Float
    var fadeSpeed: Float
    var glyphChangeRate: Float
    var primaryColor: SIMD4<Float>
    var trailColor: SIMD4<Float>
}

/// Mirrors `MatrixColumn` in VFXEffects.metal.
private struct MatrixColumn {
    var speed: SIMD2<Float>
    var phase: SIMD2<Float>
}

final class MatrixDigitalRainView: VFXMetalView {
    var configuration: MatrixConfiguration {
        didSet { configurationDidChange(from: oldValue) }
    }

    // Mirrored half-width katakana, digits and a few symbols, as in the film.
    private static let glyphs = Array("ｦｱｳｴｵｶｷｹｺｻｼｽｾｿﾀﾂﾃﾅﾆﾇﾈﾊﾋﾎﾏﾐﾑﾒﾓﾔﾕﾗﾘﾜ0123456789Z:.\"=*+-<>¦").map(String.init)
    private static let atlasColumns = 8

    private var atlas: MTLTexture?
    private var atlasCellSize: SIMD2<Int> = .zero
    private var columnBuffer: MTLBuffer?
    private var columnCount = 0
    private var rowCount = 0

    init(frame: CGRect = .zero, configuration: MatrixConfiguration = MatrixConfiguration()) {
        self.configuration = configuration
        super.init(frame: frame)
        applyBackground()
    }

    required init?(coder: NSCoder) {
        configuration = MatrixConfiguration()
        super.init(coder: coder)
        applyBackground()
    }

    private func applyBackground() {
        backgroundColor = configuration.backgroundColor
        isOpaque = true
        metalLayer.isOpaque = true
        let background = configuration.backgroundColor.vfxSIMD(with: traitCollection)
        clearColor = MTLClearColor(red: Double(background.x), green: Double(background.y),
                                   blue: Double(background.z), alpha: 1)
    }

    private func configurationDidChange(from old: MatrixConfiguration) {
        applyBackground()
        if configuration.fontSize != old.fontSize {
            atlasCellSize = .zero
        }
        if configuration.fallSpeedVariance != old.fallSpeedVariance {
            columnCount = 0
        }
        rebuildGrid(drawableSize: metalLayer.drawableSize)
    }

    override func drawableSizeDidChange(_ size: CGSize) {
        rebuildGrid(drawableSize: size)
    }

    // MARK: Grid, columns and glyph atlas

    private func rebuildGrid(drawableSize: CGSize) {
        guard let device = gpu?.device, drawableSize.width > 0, drawableSize.height > 0 else { return }
        let scale = contentScaleFactor
        // Half-width glyphs are narrow: columns are tighter than rows.
        let cell = SIMD2(max(Int((configuration.fontSize * 0.72 * scale).rounded()), 4),
                         max(Int((configuration.fontSize * 1.08 * scale).rounded()), 4))
        if cell != atlasCellSize {
            atlas = Self.makeAtlas(device: device, cellSize: cell, fontSize: configuration.fontSize * scale)
            atlasCellSize = cell
            columnCount = 0
        }

        let columns = Int((drawableSize.width / CGFloat(cell.x)).rounded(.up))
        rowCount = Int((drawableSize.height / CGFloat(cell.y)).rounded(.up))
        guard columns != columnCount else { return }

        let variance = Float(min(max(configuration.fallSpeedVariance, 0), 0.95))
        let speed = { Float.random(in: (1 - variance)...(1 + variance)) }
        let data = (0..<columns).map { _ in
            MatrixColumn(speed: SIMD2(speed(), speed()),
                         phase: SIMD2(Float.random(in: 0...1), Float.random(in: 0...1)))
        }
        columnBuffer = device.makeBuffer(bytes: data, length: MemoryLayout<MatrixColumn>.stride * data.count)
        columnCount = columns
    }

    /// Renders every glyph mirrored and white-on-black into a single-channel texture,
    /// with a soft halo baked in so the rain glows without a separate bloom pass.
    private static func makeAtlas(device: MTLDevice, cellSize: SIMD2<Int>, fontSize: CGFloat) -> MTLTexture? {
        let rows = (glyphs.count + atlasColumns - 1) / atlasColumns
        let width = cellSize.x * atlasColumns
        let height = cellSize.y * rows
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        let font = UIFont(name: "HiraginoSans-W6", size: fontSize)
            ?? .monospacedSystemFont(ofSize: fontSize, weight: .semibold)
        let halo = NSShadow()
        halo.shadowColor = UIColor(white: 1, alpha: 0.55)
        halo.shadowBlurRadius = fontSize * 0.18
        halo.shadowOffset = .zero
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white, .shadow: halo]

        UIGraphicsPushContext(context)
        for (index, glyph) in glyphs.enumerated() {
            let cell = CGRect(x: CGFloat(index % atlasColumns * cellSize.x), y: CGFloat(index / atlasColumns * cellSize.y),
                              width: CGFloat(cellSize.x), height: CGFloat(cellSize.y))
            let text = NSAttributedString(string: glyph, attributes: attributes)
            let size = text.size()
            context.saveGState()
            context.clip(to: cell)
            context.translateBy(x: cell.midX, y: 0)
            context.scaleBy(x: -1, y: 1)   // mirrored, like the film
            text.draw(at: CGPoint(x: -size.width / 2, y: cell.midY - size.height / 2))
            context.restoreGState()
        }
        UIGraphicsPopContext()

        guard let bytes = context.data else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: width,
                                                                  height: height, mipmapped: false)
        descriptor.usage = .shaderRead
        let texture = device.makeTexture(descriptor: descriptor)
        texture?.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                         withBytes: bytes, bytesPerRow: context.bytesPerRow)
        return texture
    }

    // MARK: Rendering

    override func encode(into commandBuffer: MTLCommandBuffer, target: MTLTexture) {
        guard let gpu, let atlas, let columnBuffer, columnCount > 0, rowCount > 0,
              let pipeline = gpu.renderPipeline(vertex: "matrix_vertex", fragment: "matrix_fragment"),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass(target: target)) else {
            super.encode(into: commandBuffer, target: target)
            return
        }
        let scale = Float(contentScaleFactor)
        let atlasRows = (Self.glyphs.count + Self.atlasColumns - 1) / Self.atlasColumns
        var uniforms = MatrixUniforms(
            viewportSize: SIMD2(Float(target.width), Float(target.height)),
            cellSize: SIMD2(Float(atlasCellSize.x), Float(atlasCellSize.y)),
            atlasGrid: SIMD2(Float(Self.atlasColumns), Float(atlasRows)),
            columns: UInt32(columnCount),
            rows: UInt32(rowCount),
            glyphCount: UInt32(Self.glyphs.count),
            // Float precision degrades over hours; wrap well before that (one jump per ~68 min).
            time: Float(time.truncatingRemainder(dividingBy: 4096)),
            fallSpeed: Float(configuration.fallSpeed) * scale,
            fadeSpeed: Float(max(configuration.fadeSpeed, 0.01)),
            glyphChangeRate: Float(max(configuration.glyphChangeRate, 0)),
            primaryColor: configuration.primaryColor.vfxSIMD(with: traitCollection),
            trailColor: configuration.trailColor.vfxSIMD(with: traitCollection))

        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<MatrixUniforms>.stride, index: 0)
        encoder.setVertexBuffer(columnBuffer, offset: 0, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<MatrixUniforms>.stride, index: 0)
        encoder.setFragmentTexture(atlas, index: 0)
        // The whole screen of glyphs in one instanced draw call.
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4,
                               instanceCount: columnCount * rowCount)
        encoder.endEncoding()
    }
}
