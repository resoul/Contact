//
//  ChannelFeedSupport.swift
//  controller
//
//  Shared pieces for the channel feed: the data model, compact count formatting, generated avatars,
//  a UIKit counter whose characters roll like an odometer, and FeedLiquidLayer — one shared liquid
//  canvas that any number of short-lived effects draw into, instead of a Metal view per effect.
//

import UIKit

// MARK: - Model

struct ChannelPerson: Codable {
    let name: String
    let hue: CGFloat

    var initials: String {
        String(name.split(separator: " ").compactMap(\.first).prefix(2))
    }
}

struct ChannelReaction: Codable {
    let emoji: String
    var count: Int
    var chosen = false

    var isStar: Bool { emoji == "⭐" }
}

struct ChannelPost: Codable {
    var image: DemoPhotos.Scene? = nil
    var quote: String?
    var body: String
    var source: String?
    var spoiler: String?
    var reactions: [ChannelReaction]
    var views: Int
    var time: String
    var comments: Int
    var commenters: [ChannelPerson]
}

enum ChannelPalette {
    static let bubble = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.16, green: 0.145, blue: 0.21, alpha: 1) : .secondarySystemBackground }
    static let accent = UIColor(red: 0.33, green: 0.58, blue: 1.0, alpha: 1)
    static let name = UIColor(red: 0.42, green: 0.80, blue: 0.85, alpha: 1)
    static let star = UIColor(red: 1.0, green: 0.76, blue: 0.20, alpha: 1)
    static let secondaryText = UIColor.secondaryLabel
    static let picker = UIColor(red: 0.20, green: 0.19, blue: 0.25, alpha: 1)
}

enum FeedFormat {
    /// 809 · 3.3K · 101.8K · 1.2M
    static func count(_ n: Int) -> String {
        func short(_ value: Double, _ suffix: String) -> String {
            let rounded = (value * 10).rounded(.down) / 10
            let text = rounded.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(rounded)) : String(format: "%.1f", rounded)
            return text + suffix
        }
        switch n {
        case ..<1000: return "\(n)"
        case ..<1_000_000: return short(Double(n) / 1000, "K")
        default: return short(Double(n) / 1_000_000, "M")
        }
    }
}

// MARK: - Avatars

enum ChannelAvatar {
    private static var cache: [String: UIImage] = [:]

    /// A gradient disc with the person's initials.
    static func image(for person: ChannelPerson, size: CGFloat) -> UIImage {
        let key = "\(person.name)|\(size)"
        if let cached = cache[key] { return cached }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let image = renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            UIBezierPath(ovalIn: rect).addClip()
            let top = UIColor(hue: person.hue, saturation: 0.55, brightness: 0.98, alpha: 1)
            let bottom = UIColor(hue: person.hue + 0.06, saturation: 0.75, brightness: 0.78, alpha: 1)
            let gradient = CGGradient(colorsSpace: nil, colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1])!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size), options: [])
            let font = UIFont.systemFont(ofSize: size * 0.4, weight: .semibold)
            let text = person.initials as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
            let textSize = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: (size - textSize.width) / 2, y: (size - textSize.height) / 2), withAttributes: attributes)
        }
        cache[key] = image
        return image
    }
}

// MARK: - Rolling counter

/// A label whose changed characters roll: up when the number grows, down when it shrinks.
/// Plain UIKit, so it costs nothing at rest and shows up in snapshots (glass, dust).
final class RollingCounterLabel: UIView {
    var font: UIFont = .systemFont(ofSize: 14, weight: .semibold) {
        didSet { rebuild(animated: false, up: true) }
    }
    var textColor: UIColor = .white {
        didSet { slots.forEach { $0.textColor = textColor } }
    }
    private(set) var text = ""
    private var slots: [UILabel] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        let size = (text as NSString).size(withAttributes: [.font: font])
        return CGSize(width: ceil(size.width), height: ceil(font.lineHeight))
    }

    func setText(_ newText: String, animated: Bool, up: Bool = true) {
        guard newText != text else { return }
        let old = text
        text = newText
        invalidateIntrinsicContentSize()
        rebuild(animated: animated, up: up, old: old)
    }

    private func characterFrames(_ string: String) -> [CGRect] {
        var x: CGFloat = 0
        return string.map { char in
            let width = (String(char) as NSString).size(withAttributes: [.font: font]).width
            defer { x += width }
            return CGRect(x: x, y: 0, width: ceil(width) + 1, height: ceil(font.lineHeight))
        }
    }

    private func rebuild(animated: Bool, up: Bool, old: String = "") {
        let oldChars = Array(old), newChars = Array(text)
        let frames = characterFrames(text)
        var newSlots: [UILabel] = []
        // Characters are compared right-aligned, like digits: only the ones that changed roll.
        let sameLength = oldChars.count == newChars.count
        for (index, char) in newChars.enumerated() {
            let oldIndex = index - (newChars.count - oldChars.count)
            let reused = sameLength && oldIndex >= 0 && oldIndex < slots.count && oldChars[oldIndex] == char
            let label = reused ? slots[oldIndex] : makeSlot(String(char))
            label.frame = frames[index]
            if !reused, animated {
                let travel = font.lineHeight * 0.8 * (up ? 1 : -1)
                label.transform = CGAffineTransform(translationX: 0, y: travel).scaledBy(x: 0.6, y: 0.6)
                label.alpha = 0
                UIView.animate(withDuration: 0.42, delay: Double(index) * 0.02, usingSpringWithDamping: 0.62,
                               initialSpringVelocity: 0.4) {
                    label.transform = .identity
                    label.alpha = 1
                }
            }
            newSlots.append(label)
        }
        for (index, slot) in slots.enumerated() where !newSlots.contains(slot) {
            guard animated else {
                slot.removeFromSuperview()
                continue
            }
            let travel = font.lineHeight * 0.8 * (up ? -1 : 1)
            UIView.animate(withDuration: 0.3, delay: Double(index) * 0.02, options: [.curveEaseIn]) {
                slot.transform = CGAffineTransform(translationX: 0, y: travel).scaledBy(x: 0.6, y: 0.6)
                slot.alpha = 0
            } completion: { _ in
                slot.removeFromSuperview()
            }
        }
        slots = newSlots
    }

    private func makeSlot(_ string: String) -> UILabel {
        let label = UILabel()
        label.text = string
        label.font = font
        label.textColor = textColor
        label.textAlignment = .center
        addSubview(label)
        return label
    }
}

// MARK: - Shared liquid layer

/// One liquid canvas shared by every short-lived liquid effect of a screen. Each effect adds an
/// actor: a closure called every frame that returns its shapes, or nil once it is done. The canvas
/// draws all of them as one merged liquid and stops its display link when no actor is left.
final class FeedLiquidLayer: LiquidCanvasView {
    typealias Actor = (CFTimeInterval) -> (shapes: [IslandFluidShape], spikes: [IslandFluidSpike])?

    private var actors: [Actor] = []

    init(color: UIColor, gloss: CGFloat) {
        super.init(frame: .zero)
        liquidColor = color
        self.gloss = gloss
        rimWidth = 7
        isPaused = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func add(_ actor: @escaping Actor) {
        actors.append(actor)
        isPaused = false
    }

    func stop() {
        actors.removeAll()
        shapes = []
        spikes = []
        renderFrame()
        isPaused = true
    }

    override func update(deltaTime: CFTimeInterval) {
        var newShapes: [IslandFluidShape] = []
        var newSpikes: [IslandFluidSpike] = []
        actors = actors.filter { actor in
            guard let frame = actor(deltaTime) else { return false }
            newShapes += frame.shapes
            newSpikes += frame.spikes
            return true
        }
        shapes = newShapes
        spikes = newSpikes
        if actors.isEmpty {
            settle()
        }
    }
}

extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

extension CGPoint {
    static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}
