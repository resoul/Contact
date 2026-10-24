//
//  InkSpoilerView.swift
//  controller
//
//  Hidden text under living ink (channel_spoiler_fragment in ChannelFX.metal): the ink churns with an
//  oil-slick sheen and glinting motes. Drag a finger over it to wipe holes in it; tap and the ink
//  soaks away from the tap outward. Lay it over a UILabel with the same frame and give it the
//  label's attributed text and the hidden range: it finds the line rects with TextKit.
//

import UIKit
import Metal

/// Mirrors `SpoilerUniforms` in ChannelFX.metal.
private struct SpoilerUniforms {
    var viewport: SIMD2<Float>
    var scale: Float
    var time: Float
    var rectCount: UInt32
    var stampCount: UInt32
    var seed: Float
    var unused: Float = 0
    var reveal: SIMD4<Float>
    var ink: SIMD4<Float>
}

final class InkSpoilerView: VFXMetalView, UIGestureRecognizerDelegate {
    var inkColor = UIColor(red: 0.30, green: 0.27, blue: 0.40, alpha: 1)
    private(set) var isRevealed = false
    var onReveal: (() -> Void)?

    private var text: NSAttributedString?
    private var range = NSRange(location: 0, length: 0)
    private var rects: [CGRect] = []
    private var stamps: [SIMD4<Float>] = []
    private var revealOrigin: CGPoint?
    private var revealStart: CFTimeInterval = 0
    private let seed = Float.random(in: 0...50)
    private let maxStamps = 96
    private var lastStamp: CGPoint?
    private let wipeHaptic = UIImpactFeedbackGenerator(style: .soft)

    override init(frame: CGRect) {
        super.init(frame: frame)
        preferredFramesPerSecond = 60
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        addGestureRecognizer(pan)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(text: NSAttributedString, hidden range: NSRange) {
        self.text = text
        self.range = range
        setNeedsLayout()
    }

    func reset() {
        stamps = []
        revealOrigin = nil
        isRevealed = false
        isHidden = false
        isPaused = false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        rects = lineRects()
    }

    /// One rect per line the hidden range spans, in this view's coordinates.
    private func lineRects() -> [CGRect] {
        guard let text, bounds.width > 0, range.length > 0 else { return [] }
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: bounds.width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var result: [CGRect] = []
        layout.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                       in: container) { rect, _ in
            result.append(rect)
        }
        // UILabel centers its text vertically when it is taller than the text.
        let used = layout.usedRect(for: container)
        let offset = max(0, (bounds.height - used.height) / 2)
        return result.map { $0.offsetBy(dx: 0, dy: offset) }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        !isRevealed && rects.contains { $0.insetBy(dx: -6, dy: -6).contains(point) }
    }

    // MARK: Gestures

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard !isRevealed, revealOrigin == nil else { return }
        revealOrigin = gesture.location(in: self)
        revealStart = time
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        isPaused = false
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: self)
        switch gesture.state {
        case .began:
            // The pan only begins after some movement: wipe from where the finger went down.
            let translation = gesture.translation(in: self)
            lastStamp = nil
            addStamp(at: CGPoint(x: point.x - translation.x, y: point.y - translation.y))
            addStamp(at: point)
        case .changed:
            addStamp(at: point)
        default:
            lastStamp = nil
            if coverage() > 0.7 {
                // Mostly wiped: let the rest soak away.
                revealOrigin = point
                revealStart = time
            }
        }
    }

    private func addStamp(at point: CGPoint) {
        if let last = lastStamp, last.distance(to: point) < 5 { return }
        // Fill the gap when the finger moves fast.
        let from = lastStamp ?? point
        let steps = max(1, Int(from.distance(to: point) / 5))
        for i in 1...steps {
            let p = CGPoint.lerp(from, point, CGFloat(i) / CGFloat(steps))
            stamps.append(SIMD4(Float(p.x), Float(p.y), 14, 0))
        }
        if stamps.count > maxStamps {
            stamps.removeFirst(stamps.count - maxStamps)
        }
        lastStamp = point
        wipeHaptic.impactOccurred(intensity: 0.3)
    }

    /// Rough share of the ink already wiped away, sampled on a grid.
    private func coverage() -> CGFloat {
        var total = 0, wiped = 0
        for rect in rects {
            var y = rect.minY + 3
            while y < rect.maxY {
                var x = rect.minX + 3
                while x < rect.maxX {
                    total += 1
                    if stamps.contains(where: { hypot(CGFloat($0.x) - x, CGFloat($0.y) - y) < 14 }) {
                        wiped += 1
                    }
                    x += 6
                }
                y += 6
            }
        }
        return total == 0 ? 1 : CGFloat(wiped) / CGFloat(total)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // The feed's scroll waits: a drag that starts on the ink wipes it instead of scrolling.
        otherGestureRecognizer.view is UIScrollView
    }

    // MARK: Rendering

    private var revealRadius: CGFloat {
        guard revealOrigin != nil else { return 0 }
        let t = CGFloat((time - revealStart) / 0.8)
        return (1 - pow(1 - min(t, 1), 2.2)) * (bounds.width + 40)
    }

    override func update(deltaTime: CFTimeInterval) {
        if revealOrigin != nil, time - revealStart > 0.85, !isRevealed {
            isRevealed = true
            isHidden = true
            isPaused = true
            onReveal?()
        }
    }

    override func encode(into commandBuffer: MTLCommandBuffer, target: MTLTexture) {
        guard let gpu, !rects.isEmpty,
              let pipeline = gpu.renderPipeline(vertex: "channel_vertex", fragment: "channel_spoiler_fragment"),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass(target: target)) else {
            super.encode(into: commandBuffer, target: target)
            return
        }
        let origin = revealOrigin ?? .zero
        var uniforms = SpoilerUniforms(
            viewport: SIMD2(Float(target.width), Float(target.height)), scale: Float(contentScaleFactor), time: Float(time),
            rectCount: UInt32(rects.count), stampCount: UInt32(stamps.count), seed: seed,
            reveal: SIMD4(Float(origin.x), Float(origin.y), Float(revealRadius), 0),
            ink: inkColor.vfxSIMD(with: traitCollection))
        let rectData = rects.map { SIMD4(Float($0.minX), Float($0.minY), Float($0.width), Float($0.height)) }
        let stampData = stamps.isEmpty ? [SIMD4<Float>(-1000, -1000, 0, 0)] : stamps
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SpoilerUniforms>.stride, index: 0)
        encoder.setFragmentBytes(rectData, length: MemoryLayout<SIMD4<Float>>.stride * rectData.count, index: 1)
        encoder.setFragmentBytes(stampData, length: MemoryLayout<SIMD4<Float>>.stride * stampData.count, index: 2)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}
