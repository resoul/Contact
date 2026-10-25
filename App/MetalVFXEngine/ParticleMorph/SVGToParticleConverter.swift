//
//  SVGToParticleConverter.swift
//  controller
//
//  Turns vector and raster shapes into point clouds for ParticleMorphEngine:
//  SVG path data, UIBezierPath (fill or stroke), text (CoreText glyph outlines) and UIImage
//  (positions + colors). Shapes are rasterized into a mask and sampled proportionally to coverage,
//  so every request returns exactly `count` points and differently shaped clouds can morph 1:1.
//

import UIKit
import ParticleTypes
import CoreText

enum SVGToParticleConverter {
    struct Sample {
        var position: SIMD2<Float>
        var color: SIMD4<Float>
    }

    enum Distribution {
        /// Random points, denser where the shape is more opaque. Always exactly `count` points.
        case weighted
        /// A regular grid of about `count` cells over the rect (transparent cells are skipped):
        /// fills a picture evenly without holes, e.g. to dissolve a card.
        case grid
    }

    /// Longest side of the sampling mask, in pixels.
    private static let maxMaskSide = 1024

    // MARK: - Paths

    /// Points spread over the path's fill, or over its stroke when `lineWidth` is given,
    /// in the path's own coordinate space.
    static func points(from path: UIBezierPath, count: Int, lineWidth: CGFloat? = nil,
                       seed: UInt64 = 1) -> [SIMD2<Float>] {
        guard count > 0, let raster = rasterize(path, lineWidth: lineWidth) else { return [] }
        var random = SeededRandom(seed: seed)
        let box = raster.box, scale = Float(raster.scale)
        return raster.mask.weightedSamples(count: count, random: &random).map { sample in
            SIMD2(Float(box.minX) + sample.position.x / scale, Float(box.minY) + sample.position.y / scale)
        }
    }

    /// Area in pt² covered by the path's fill (or stroke): how dense a cloud of N points will be.
    static func area(of path: UIBezierPath, lineWidth: CGFloat? = nil) -> CGFloat {
        guard let raster = rasterize(path, lineWidth: lineWidth) else { return 0 }
        return raster.mask.coverage / (raster.scale * raster.scale)
    }

    private static func rasterize(_ path: UIBezierPath, lineWidth: CGFloat?) -> (mask: Mask, box: CGRect, scale: CGFloat)? {
        let cgPath: CGPath
        if let lineWidth {
            cgPath = path.cgPath.copy(strokingWithWidth: lineWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)
        } else {
            cgPath = path.cgPath
        }
        let box = cgPath.boundingBoxOfPath.insetBy(dx: -1, dy: -1)
        guard !box.isNull, box.width > 0, box.height > 0 else { return nil }
        let scale = min(4, CGFloat(maxMaskSide) / max(box.width, box.height))
        let mask = Mask(width: Int(ceil(box.width * scale)), height: Int(ceil(box.height * scale))) { context in
            context.translateBy(x: 0, y: box.height * scale)
            context.scaleBy(x: scale, y: -scale)   // UIKit (y down) path into CG (y up) bitmap
            context.translateBy(x: -box.minX, y: -box.minY)
            context.addPath(cgPath)
            context.setFillColor(UIColor.black.cgColor)
            context.fillPath()
        }
        return mask.map { ($0, box, scale) }
    }

    // MARK: - Text

    /// Outline of the text from CoreText glyph paths, y down, top-left of the first line at (0, 0).
    /// Lines separated by "\n" are stacked and centered on each other.
    static func path(forText text: String, font: UIFont) -> UIBezierPath {
        let result = CGMutablePath()
        let lines = text.components(separatedBy: "\n")
        let widths = lines.map { CGFloat(CTLineGetTypographicBounds(makeLine($0, font: font), nil, nil, nil)) }
        let widest = widths.max() ?? 0
        for (number, text) in lines.enumerated() {
            let line = makeLine(text, font: font)
            let origin = CGPoint(x: (widest - widths[number]) / 2, y: font.ascender + CGFloat(number) * font.lineHeight)
            let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
            for run in runs {
                let attributes = CTRunGetAttributes(run) as NSDictionary
                let runFont = attributes[kCTFontAttributeName as String] as! CTFont
                let glyphCount = CTRunGetGlyphCount(run)
                var glyphs = [CGGlyph](repeating: 0, count: glyphCount)
                var positions = [CGPoint](repeating: .zero, count: glyphCount)
                CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
                CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
                for index in 0..<glyphCount {
                    guard let glyph = CTFontCreatePathForGlyph(runFont, glyphs[index], nil) else { continue }
                    // Glyph outlines are y-up around the baseline; flip them into y-down at the line's baseline.
                    let transform = CGAffineTransform(translationX: origin.x + positions[index].x, y: origin.y)
                        .scaledBy(x: 1, y: -1)
                    result.addPath(glyph, transform: transform)
                }
            }
        }
        return UIBezierPath(cgPath: result)
    }

    private static func makeLine(_ text: String, font: UIFont) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
    }

    /// Points filling the text's letters, scaled down if needed to fit `rect` and centered in it.
    static func points(fromText text: String, font: UIFont, count: Int, fitting rect: CGRect,
                       seed: UInt64 = 1) -> [SIMD2<Float>] {
        let path = path(forText: text, font: font)
        let box = path.cgPath.boundingBoxOfPath
        guard !box.isNull, box.width > 0, box.height > 0 else { return [] }
        let fit = min(1, rect.width / box.width, rect.height / box.height)
        var transform = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: fit, y: fit)
            .translatedBy(x: -box.midX, y: -box.midY)
        guard let placed = path.cgPath.copy(using: &transform) else { return [] }
        return points(from: UIBezierPath(cgPath: placed), count: count, seed: seed)
    }

    // MARK: - Images

    /// Points with the image's colors, placed so the image fills `rect`.
    /// Pixels with alpha below `alphaThreshold` (0…1) never produce particles.
    static func samples(from image: UIImage, count: Int, in rect: CGRect,
                        distribution: Distribution = .weighted, alphaThreshold: CGFloat = 0.1,
                        seed: UInt64 = 1) -> [Sample] {
        guard count > 0, rect.width > 0, rect.height > 0 else { return [] }
        let pixelScale = min(image.scale * max(image.size.width, image.size.height),
                             CGFloat(maxMaskSide)) / max(rect.width, rect.height)
        let width = max(Int((rect.width * pixelScale).rounded()), 1)
        let height = max(Int((rect.height * pixelScale).rounded()), 1)
        guard let mask = Mask(width: width, height: height, draw: { context in
            UIGraphicsPushContext(context)
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
            UIGraphicsPopContext()
        }) else { return [] }
        let threshold = UInt8(max(min(alphaThreshold, 1), 0) * 255)
        let raw: [Sample]
        switch distribution {
        case .weighted:
            var random = SeededRandom(seed: seed)
            raw = mask.weightedSamples(count: count, random: &random, threshold: threshold)
        case .grid:
            raw = mask.gridSamples(count: count, threshold: threshold)
        }
        let sx = Float(rect.width) / Float(width), sy = Float(rect.height) / Float(height)
        return raw.map { sample in
            Sample(position: SIMD2(Float(rect.minX) + sample.position.x * sx, Float(rect.minY) + sample.position.y * sy),
                   color: sample.color)
        }
    }

    /// Snapshot of an on-screen view as an image (keeps transparency, e.g. rounded corners).
    static func snapshot(of view: UIView) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = view.window?.screen.scale ?? view.traitCollection.displayScale
        return UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { context in
            view.layer.render(in: context.cgContext)
        }
    }

    // MARK: - SVG

    /// Parses SVG path data (the `d` attribute): M L H V C S Q T Z, absolute and relative.
    /// Elliptical arcs (A) are approximated by a straight line to their end point.
    static func path(fromSVG data: String) -> UIBezierPath {
        let path = UIBezierPath()
        var scanner = SVGScanner(data)
        var command: Character = "M"
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastControl: CGPoint?
        var lastCommand: Character = "M"

        while let next = scanner.nextCommandOrNumber() {
            if case .command(let c) = next {
                command = c
                if c == "Z" || c == "z" {
                    path.close()
                    current = subpathStart
                    lastControl = nil
                    lastCommand = c
                    continue
                }
            } else {
                scanner.rewindNumber()
            }
            let relative = command.isLowercase
            let base = relative ? current : .zero
            func point() -> CGPoint? {
                guard let x = scanner.number(), let y = scanner.number() else { return nil }
                return CGPoint(x: base.x + x, y: base.y + y)
            }
            switch command.uppercased() {
            case "M":
                guard let p = point() else { return path }
                path.move(to: p)
                current = p
                subpathStart = p
                lastControl = nil
                command = relative ? "l" : "L"   // further pairs are implicit line-tos
            case "L":
                guard let p = point() else { return path }
                path.addLine(to: p)
                current = p
                lastControl = nil
            case "H":
                guard let x = scanner.number() else { return path }
                current = CGPoint(x: (relative ? current.x : 0) + x, y: current.y)
                path.addLine(to: current)
                lastControl = nil
            case "V":
                guard let y = scanner.number() else { return path }
                current = CGPoint(x: current.x, y: (relative ? current.y : 0) + y)
                path.addLine(to: current)
                lastControl = nil
            case "C":
                guard let c1 = point(), let c2 = point(), let p = point() else { return path }
                path.addCurve(to: p, controlPoint1: c1, controlPoint2: c2)
                current = p
                lastControl = c2
            case "S":
                guard let c2 = point(), let p = point() else { return path }
                let c1 = "CcSs".contains(lastCommand) ? reflect(lastControl, around: current) : current
                path.addCurve(to: p, controlPoint1: c1, controlPoint2: c2)
                current = p
                lastControl = c2
            case "Q":
                guard let c = point(), let p = point() else { return path }
                path.addQuadCurve(to: p, controlPoint: c)
                current = p
                lastControl = c
            case "T":
                guard let p = point() else { return path }
                let c = "QqTt".contains(lastCommand) ? reflect(lastControl, around: current) : current
                path.addQuadCurve(to: p, controlPoint: c)
                current = p
                lastControl = c
            case "A":
                guard scanner.number() != nil, scanner.number() != nil, scanner.number() != nil,
                      scanner.number() != nil, scanner.number() != nil, let p = point() else { return path }
                path.addLine(to: p)
                current = p
                lastControl = nil
            default:
                return path
            }
            lastCommand = command
        }
        return path
    }

    private static func reflect(_ control: CGPoint?, around point: CGPoint) -> CGPoint {
        guard let control else { return point }
        return CGPoint(x: 2 * point.x - control.x, y: 2 * point.y - control.y)
    }
}

// MARK: - Mask sampling

/// An 8-bit RGBA bitmap with top-left origin that can be sampled by coverage.
private struct Mask {
    let width: Int
    let height: Int
    /// Premultiplied RGBA, row 0 = top.
    let pixels: [UInt8]

    init?(width: Int, height: Int, draw: (CGContext) -> Void) {
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            // CG's bitmap memory starts at the top row, while its user space is y-up; callers flip.
            draw(context)
            return true
        }
        guard drawn else { return nil }
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// Sum of alpha in pixels (a fully opaque pixel counts as 1).
    var coverage: CGFloat {
        var total = 0
        pixels.withUnsafeBufferPointer { px in
            for i in 0..<(width * height) { total += Int(px[i * 4 + 3]) }
        }
        return CGFloat(total) / 255
    }

    private func color(at index: Int) -> SIMD4<Float> {
        let a = Float(pixels[index * 4 + 3]) / 255
        guard a > 0 else { return .zero }
        // Unpremultiply into straight color.
        return SIMD4(Float(pixels[index * 4]) / 255 / a, Float(pixels[index * 4 + 1]) / 255 / a,
                     Float(pixels[index * 4 + 2]) / 255 / a, a)
    }

    /// Exactly `count` jittered points, chosen with probability proportional to pixel alpha.
    func weightedSamples(count: Int, random: inout SeededRandom, threshold: UInt8 = 1) -> [SVGToParticleConverter.Sample] {
        var cumulative = [UInt32](repeating: 0, count: width * height)
        var total: UInt32 = 0
        pixels.withUnsafeBufferPointer { px in
            cumulative.withUnsafeMutableBufferPointer { sums in
                for i in 0..<(width * height) {
                    let a = px[i * 4 + 3]
                    if a >= max(threshold, 1) { total += UInt32(a) }
                    sums[i] = total
                }
            }
        }
        guard total > 0 else { return [] }
        var result: [SVGToParticleConverter.Sample] = []
        result.reserveCapacity(count)
        cumulative.withUnsafeBufferPointer { sums in
            for _ in 0..<count {
                let r = UInt32(random.next() % UInt64(total))
                // First pixel whose running sum exceeds r.
                var low = 0, high = sums.count - 1
                while low < high {
                    let mid = (low + high) / 2
                    if sums[mid] > r { high = mid } else { low = mid + 1 }
                }
                let x = Float(low % width) + random.unit()
                let y = Float(low / width) + random.unit()
                result.append(.init(position: SIMD2(x, y), color: color(at: low)))
            }
        }
        return result
    }

    /// Cell centers of a grid with about `count` cells, skipping transparent ones.
    func gridSamples(count: Int, threshold: UInt8) -> [SVGToParticleConverter.Sample] {
        let aspect = Double(width) / Double(height)
        let columns = max(Int((Double(count) * aspect).squareRoot().rounded()), 1)
        let rows = max(Int((Double(count) / Double(columns)).rounded()), 1)
        let cellWidth = Float(width) / Float(columns), cellHeight = Float(height) / Float(rows)
        var result: [SVGToParticleConverter.Sample] = []
        result.reserveCapacity(columns * rows)
        for row in 0..<rows {
            for column in 0..<columns {
                let x = (Float(column) + 0.5) * cellWidth, y = (Float(row) + 0.5) * cellHeight
                let index = min(Int(y), height - 1) * width + min(Int(x), width - 1)
                guard pixels[index * 4 + 3] >= max(threshold, 1) else { continue }
                result.append(.init(position: SIMD2(x, y), color: color(at: index)))
            }
        }
        return result
    }
}

/// SplitMix64: fast and deterministic, so the same shape always produces the same cloud.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in 0..<1.
    mutating func unit() -> Float {
        Float(next() >> 40) / Float(1 << 24)
    }
}

// MARK: - SVG tokenizer

private struct SVGScanner {
    enum Token {
        case command(Character)
        case number(CGFloat)
    }

    private let characters: [Character]
    private var index = 0
    private var lastNumberStart: Int?

    init(_ string: String) {
        characters = Array(string)
    }

    private mutating func skipSeparators() {
        while index < characters.count, characters[index].isWhitespace || characters[index] == "," {
            index += 1
        }
    }

    mutating func nextCommandOrNumber() -> Token? {
        skipSeparators()
        guard index < characters.count else { return nil }
        let c = characters[index]
        if c.isLetter, c != "e", c != "E" {
            index += 1
            return .command(c)
        }
        lastNumberStart = index
        return number().map { .number($0) }
    }

    /// Steps back over the number just returned by `nextCommandOrNumber` (an implicit repeat).
    mutating func rewindNumber() {
        if let lastNumberStart { index = lastNumberStart }
    }

    mutating func number() -> CGFloat? {
        skipSeparators()
        let start = index
        if index < characters.count, characters[index] == "-" || characters[index] == "+" { index += 1 }
        var seenDot = false
        var seenExponent = false
        while index < characters.count {
            let c = characters[index]
            if c.isNumber {
                index += 1
            } else if c == ".", !seenDot, !seenExponent {
                seenDot = true
                index += 1
            } else if (c == "e" || c == "E"), !seenExponent {
                seenExponent = true
                index += 1
                if index < characters.count, characters[index] == "-" || characters[index] == "+" { index += 1 }
            } else {
                break
            }
        }
        guard index > start, let value = Double(String(characters[start..<index])) else {
            index = start
            return nil
        }
        return CGFloat(value)
    }
}
