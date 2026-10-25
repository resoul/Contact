//
//  SocialSupport.swift
//  controller
//
//  Shared pieces for the social demos: color palettes for the X-style timeline and the
//  Instagram-style photo feed, and DemoPhotos — little landscapes painted with Core Graphics, so the
//  demos need no image assets.
//

import UIKit

enum TimelinePalette {
    /// The "dim" dark theme: a blue-grey that the island's black liquid stands out against.
    static let background = UIColor(red: 0.08, green: 0.11, blue: 0.16, alpha: 1)
    static let panel = UIColor(red: 0.11, green: 0.15, blue: 0.21, alpha: 1)
    static let separator = UIColor(white: 1, alpha: 0.1)
    static let secondary = UIColor(red: 0.55, green: 0.6, blue: 0.66, alpha: 1)
    static let accent = UIColor(red: 0.11, green: 0.61, blue: 0.94, alpha: 1)
    static let like = UIColor(red: 0.98, green: 0.11, blue: 0.5, alpha: 1)
    static let repost = UIColor(red: 0.0, green: 0.73, blue: 0.49, alpha: 1)
}

enum PhotoFeedPalette {
    static let background = UIColor.black
    static let secondary = UIColor(white: 1, alpha: 0.55)
    static let accent = UIColor(red: 0.0, green: 0.58, blue: 0.96, alpha: 1)
    static let like = UIColor(red: 1.0, green: 0.19, blue: 0.31, alpha: 1)
}

enum DemoPhotos {
    enum Scene: Int, CaseIterable, Codable {
        case sunset, ocean, city, forest, desert, aurora, bloom
    }

    private static var cache: [String: UIImage] = [:]

    static func image(_ scene: Scene, size: CGSize = CGSize(width: 600, height: 600), seed: UInt64 = 1) -> UIImage {
        let key = "\(scene.rawValue)|\(Int(size.width))x\(Int(size.height))|\(seed)"
        if let cached = cache[key] { return cached }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            var random = SplitMix(seed: seed &* 7919 &+ UInt64(scene.rawValue))
            paint(scene, in: context.cgContext, size: size, random: &random)
        }
        cache[key] = image
        return image
    }

    // MARK: Painting

    private static func gradient(_ context: CGContext, _ colors: [UIColor], from: CGPoint, to: CGPoint) {
        let cgColors = colors.map(\.cgColor) as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: cgColors, locations: nil) else { return }
        context.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    private static func glow(_ context: CGContext, at center: CGPoint, radius: CGFloat, color: UIColor) {
        let colors = [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1]) else { return }
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }

    /// A mountain ridge: a sum of sines, filled down to the bottom.
    private static func ridge(_ context: CGContext, size: CGSize, base: CGFloat, height: CGFloat, color: UIColor,
                              random: inout SplitMix) {
        let phases = (0..<3).map { _ in random.next() * 6.28 }
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0, y: size.height))
        var x: CGFloat = 0
        while x <= size.width + 4 {
            let u = x / size.width
            let y = base - height * (0.55 * sin(u * 5.1 + phases[0]) + 0.3 * sin(u * 11.7 + phases[1])
                                     + 0.15 * sin(u * 27 + phases[2]) + 0.4)
            path.addLine(to: CGPoint(x: x, y: y))
            x += 4
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.close()
        context.setFillColor(color.cgColor)
        context.addPath(path.cgPath)
        context.fillPath()
    }

    private static func paint(_ scene: Scene, in context: CGContext, size: CGSize, random: inout SplitMix) {
        let w = size.width, h = size.height
        switch scene {
        case .sunset:
            gradient(context, [UIColor(red: 0.98, green: 0.62, blue: 0.3, alpha: 1), UIColor(red: 0.93, green: 0.36, blue: 0.45, alpha: 1),
                               UIColor(red: 0.38, green: 0.2, blue: 0.48, alpha: 1)], from: CGPoint(x: 0, y: h * 0.75), to: .zero)
            glow(context, at: CGPoint(x: w * 0.62, y: h * 0.58), radius: w * 0.45, color: UIColor(red: 1, green: 0.85, blue: 0.5, alpha: 0.8))
            context.setFillColor(UIColor(red: 1, green: 0.93, blue: 0.7, alpha: 1).cgColor)
            context.fillEllipse(in: CGRect(x: w * 0.62 - w * 0.08, y: h * 0.58 - w * 0.08, width: w * 0.16, height: w * 0.16))
            let layers: [(CGFloat, CGFloat, UIColor)] = [
                (0.68, 0.18, UIColor(red: 0.55, green: 0.27, blue: 0.45, alpha: 1)),
                (0.8, 0.16, UIColor(red: 0.36, green: 0.17, blue: 0.36, alpha: 1)),
                (0.92, 0.14, UIColor(red: 0.2, green: 0.1, blue: 0.24, alpha: 1)),
            ]
            for (base, height, color) in layers {
                ridge(context, size: size, base: h * base, height: h * height, color: color, random: &random)
            }
        case .ocean:
            gradient(context, [UIColor(red: 0.45, green: 0.75, blue: 0.95, alpha: 1), UIColor(red: 0.85, green: 0.93, blue: 0.98, alpha: 1)],
                     from: .zero, to: CGPoint(x: 0, y: h * 0.55))
            glow(context, at: CGPoint(x: w * 0.3, y: h * 0.42), radius: w * 0.3, color: UIColor(white: 1, alpha: 0.9))
            context.saveGState()
            context.clip(to: CGRect(x: 0, y: h * 0.55, width: w, height: h * 0.45))
            gradient(context, [UIColor(red: 0.1, green: 0.5, blue: 0.7, alpha: 1), UIColor(red: 0.03, green: 0.2, blue: 0.4, alpha: 1)],
                     from: CGPoint(x: 0, y: h * 0.55), to: CGPoint(x: 0, y: h))
            context.setStrokeColor(UIColor(white: 1, alpha: 0.35).cgColor)
            for row in 0..<14 {
                let y = h * 0.57 + CGFloat(row * row) * h * 0.0024
                context.setLineWidth(1 + CGFloat(row) * 0.25)
                let x0 = random.next() * w
                context.move(to: CGPoint(x: x0, y: y))
                context.addLine(to: CGPoint(x: x0 + w * (0.08 + random.next() * 0.2), y: y))
                context.strokePath()
            }
            context.restoreGState()
        case .city:
            gradient(context, [UIColor(red: 0.04, green: 0.05, blue: 0.15, alpha: 1), UIColor(red: 0.2, green: 0.12, blue: 0.35, alpha: 1)],
                     from: .zero, to: CGPoint(x: 0, y: h * 0.8))
            context.setFillColor(UIColor(white: 1, alpha: 0.8).cgColor)
            for _ in 0..<70 {
                let s = 0.8 + random.next() * 1.6
                context.fillEllipse(in: CGRect(x: random.next() * w, y: random.next() * h * 0.5, width: s, height: s))
            }
            var x: CGFloat = -10
            while x < w {
                let bw = w * (0.07 + random.next() * 0.1), bh = h * (0.25 + random.next() * 0.45)
                let rect = CGRect(x: x, y: h - bh, width: bw, height: bh)
                context.setFillColor(UIColor(red: 0.07, green: 0.06, blue: 0.14, alpha: 1).cgColor)
                context.fill(rect)
                var wy = rect.minY + 8
                while wy < h - 6 {
                    var wx = rect.minX + 5
                    while wx < rect.maxX - 6 {
                        if random.next() > 0.55 {
                            let warm = random.next() > 0.3
                            context.setFillColor((warm ? UIColor(red: 1, green: 0.8, blue: 0.45, alpha: 0.9)
                                                       : UIColor(red: 0.5, green: 0.85, blue: 1, alpha: 0.8)).cgColor)
                            context.fill(CGRect(x: wx, y: wy, width: 4, height: 6))
                        }
                        wx += 9
                    }
                    wy += 12
                }
                x += bw + 2
            }
        case .forest:
            gradient(context, [UIColor(red: 0.75, green: 0.88, blue: 0.82, alpha: 1), UIColor(red: 0.42, green: 0.62, blue: 0.5, alpha: 1)],
                     from: .zero, to: CGPoint(x: 0, y: h))
            let shades = [UIColor(red: 0.36, green: 0.55, blue: 0.45, alpha: 1), UIColor(red: 0.2, green: 0.4, blue: 0.3, alpha: 1),
                          UIColor(red: 0.08, green: 0.24, blue: 0.17, alpha: 1)]
            for (layer, color) in shades.enumerated() {
                context.setFillColor(color.cgColor)
                let baseY = h * (0.55 + CGFloat(layer) * 0.17)
                var x = -random.next() * 30
                while x < w + 30 {
                    let th = h * (0.25 + random.next() * 0.2) * (1 + CGFloat(layer) * 0.3)
                    let tw = th * 0.42
                    context.move(to: CGPoint(x: x, y: baseY - th))
                    context.addLine(to: CGPoint(x: x + tw / 2, y: baseY + 4))
                    context.addLine(to: CGPoint(x: x - tw / 2, y: baseY + 4))
                    context.closePath()
                    context.fillPath()
                    x += tw * (0.45 + random.next() * 0.4)
                }
                context.fill(CGRect(x: 0, y: baseY, width: w, height: h - baseY))
                glow(context, at: CGPoint(x: w * 0.5, y: baseY - h * 0.05), radius: w * 0.7, color: UIColor(white: 1, alpha: 0.15))
            }
        case .desert:
            gradient(context, [UIColor(red: 0.98, green: 0.82, blue: 0.6, alpha: 1), UIColor(red: 0.55, green: 0.75, blue: 0.95, alpha: 1)],
                     from: CGPoint(x: 0, y: h * 0.6), to: .zero)
            glow(context, at: CGPoint(x: w * 0.25, y: h * 0.3), radius: w * 0.25, color: UIColor(white: 1, alpha: 0.95))
            let dunes = [UIColor(red: 0.93, green: 0.66, blue: 0.4, alpha: 1), UIColor(red: 0.85, green: 0.52, blue: 0.3, alpha: 1),
                         UIColor(red: 0.7, green: 0.38, blue: 0.22, alpha: 1)]
            for (index, color) in dunes.enumerated() {
                ridge(context, size: size, base: h * (0.7 + CGFloat(index) * 0.1), height: h * 0.1, color: color, random: &random)
            }
        case .aurora:
            gradient(context, [UIColor(red: 0.02, green: 0.04, blue: 0.1, alpha: 1), UIColor(red: 0.05, green: 0.15, blue: 0.22, alpha: 1)],
                     from: .zero, to: CGPoint(x: 0, y: h))
            context.setFillColor(UIColor(white: 1, alpha: 0.7).cgColor)
            for _ in 0..<50 {
                context.fillEllipse(in: CGRect(x: random.next() * w, y: random.next() * h * 0.6, width: 1.5, height: 1.5))
            }
            context.setLineCap(.round)
            for (index, color) in [UIColor(red: 0.2, green: 1, blue: 0.6, alpha: 0.22), UIColor(red: 0.5, green: 0.4, blue: 1, alpha: 0.18),
                                   UIColor(red: 0.3, green: 1, blue: 0.75, alpha: 0.25)].enumerated() {
                context.setStrokeColor(color.cgColor)
                for band in 0..<8 {
                    context.setLineWidth(CGFloat(26 - band * 3))
                    let y = h * (0.2 + CGFloat(index) * 0.1)
                    context.move(to: CGPoint(x: -20, y: y + CGFloat(band) * 2))
                    context.addCurve(to: CGPoint(x: w + 20, y: y - h * 0.08),
                                     control1: CGPoint(x: w * 0.3, y: y - h * 0.2), control2: CGPoint(x: w * 0.6, y: y + h * 0.18))
                    context.strokePath()
                }
            }
            ridge(context, size: size, base: h * 0.9, height: h * 0.14, color: UIColor(red: 0.01, green: 0.03, blue: 0.06, alpha: 1),
                  random: &random)
        case .bloom:
            gradient(context, [UIColor(red: 0.98, green: 0.78, blue: 0.85, alpha: 1), UIColor(red: 0.75, green: 0.68, blue: 0.98, alpha: 1)],
                     from: .zero, to: CGPoint(x: w, y: h))
            for _ in 0..<9 {
                let center = CGPoint(x: random.next() * w, y: random.next() * h)
                let r = w * (0.06 + random.next() * 0.1)
                let hue = 0.85 + random.next() * 0.2
                for petal in 0..<6 {
                    let a = CGFloat(petal) / 6 * .pi * 2
                    let c = CGPoint(x: center.x + cos(a) * r * 0.7, y: center.y + sin(a) * r * 0.7)
                    context.setFillColor(UIColor(hue: hue.truncatingRemainder(dividingBy: 1), saturation: 0.45, brightness: 1, alpha: 0.85).cgColor)
                    context.fillEllipse(in: CGRect(x: c.x - r * 0.55, y: c.y - r * 0.55, width: r * 1.1, height: r * 1.1))
                }
                context.setFillColor(UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 1).cgColor)
                context.fillEllipse(in: CGRect(x: center.x - r * 0.35, y: center.y - r * 0.35, width: r * 0.7, height: r * 0.7))
            }
        }
    }
}
