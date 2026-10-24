//
//  OdometerStepper.swift
//  controller
//
//  A − / + stepper whose number rolls like an odometer (Shaders/LiquidUI.metal, odometer_fragment):
//  the shown value follows the real one on a spring, each digit wheel turns with it, carries roll the
//  next wheel only as the lower one passes 9 → 0, and fast wheels are motion blurred. At a limit the
//  stepper shakes its head and the number overshoots past the limit and bounces back.
//

import UIKit
import Metal

/// Mirrors `OdometerUniforms` in LiquidUI.metal.
private struct OdometerUniforms {
    var viewport: SIMD2<Float>
    var scale: Float
    var digitCount: UInt32
    var color: SIMD4<Float>
    var cell: SIMD2<Float>
    var origin: SIMD2<Float>
}

/// Mirrors `OdometerDigit` in LiquidUI.metal.
private struct OdometerDigit {
    var position: Float
    var blur: Float
    var alpha: Float
    var unused: Float = 0
}

/// The rolling number itself.
final class OdometerView: VFXMetalView {
    var textColor: UIColor = .label
    let maxDigits: Int
    private let font = UIFont.monospacedDigitSystemFont(ofSize: 34, weight: .bold)
    private let cell: CGSize
    private var atlas: MTLTexture?
    private var shown: Spring1D
    private(set) var value: Int
    private var lastPositions: [CGFloat] = []

    init(value: Int, maxDigits: Int) {
        self.value = value
        self.maxDigits = maxDigits
        shown = Spring1D(CGFloat(value), stiffness: 13, dampingRatio: 0.72)
        let glyph = ("8" as NSString).size(withAttributes: [.font: font])
        cell = CGSize(width: ceil(glyph.width) + 2, height: ceil(font.lineHeight) + 4)
        super.init(frame: .zero)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: cell.width * CGFloat(maxDigits), height: cell.height)
    }

    func setValue(_ value: Int) {
        self.value = value
        isPaused = false
    }

    /// Pushes the shown number past the target, for the bounce at a limit.
    func kick(_ velocity: CGFloat) {
        shown.velocity += velocity
        isPaused = false
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if atlas == nil, let window {
            atlas = makeAtlas(scale: window.traitCollection.displayScale)
        }
    }

    /// A vertical strip of white digits 0…9, one cell each.
    private func makeAtlas(scale: CGFloat) -> MTLTexture? {
        let size = CGSize(width: cell.width, height: cell.height * 10)
        return gpu?.makeTexture(size: size, scale: scale) { _ in
            for digit in 0..<10 {
                let text = "\(digit)" as NSString
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
                let glyph = text.size(withAttributes: attributes)
                text.draw(at: CGPoint(x: (cell.width - glyph.width) / 2, y: CGFloat(digit) * cell.height + 2),
                          withAttributes: attributes)
            }
        }
    }

    override func update(deltaTime: CFTimeInterval) {
        shown.step(toward: CGFloat(value), deltaTime: deltaTime)
        if shown.isSettled(at: CGFloat(value), tolerance: 0.0005) {
            shown.value = CGFloat(value)
            renderFrame()
            isPaused = true
        }
    }

    /// Wheel `i` (0 = ones): it only turns while every lower wheel passes from 9 to 0.
    private func wheel(_ i: Int, of d: CGFloat) -> CGFloat {
        let unit = pow(10, CGFloat(i))
        guard i > 0 else { return d }
        let lower = d.truncatingRemainder(dividingBy: unit)
        let normalizedLower = lower < 0 ? lower + unit : lower
        return floor(d / unit) + max(0, min(1, normalizedLower - (unit - 1)))
    }

    override func encode(into commandBuffer: MTLCommandBuffer, target: MTLTexture) {
        guard let gpu, let atlas,
              let pipeline = gpu.renderPipeline(vertex: "liquid_ui_vertex", fragment: "odometer_fragment"),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass(target: target)) else {
            super.encode(into: commandBuffer, target: target)
            return
        }
        let d = shown.value
        var digits: [OdometerDigit] = []
        var positions: [CGFloat] = []
        var visible: CGFloat = 0
        // Leftmost wheel first.
        for i in (0..<maxDigits).reversed() {
            let position = wheel(i, of: d)
            positions.append(position)
            // Leading zeros fade out; a wheel appears as the number grows into it.
            let alpha = i == 0 ? 1 : max(0, min(1, d - (pow(10, CGFloat(i)) - 1)))
            visible += alpha
            let previous = lastPositions.count == maxDigits ? lastPositions[maxDigits - 1 - i] : position
            let speed = abs(position - previous) * 120
            digits.append(OdometerDigit(position: Float(position.truncatingRemainder(dividingBy: 10)),
                                        blur: Float(min(speed * 0.05, 1.2)), alpha: Float(alpha)))
        }
        lastPositions = positions
        // Keep the visible digits centered as wheels appear and disappear.
        let empty = CGFloat(maxDigits) - visible
        let originX = (bounds.width - CGFloat(maxDigits) * cell.width) / 2 - empty * cell.width / 2
        var uniforms = OdometerUniforms(
            viewport: SIMD2(Float(target.width), Float(target.height)), scale: Float(contentScaleFactor),
            digitCount: UInt32(maxDigits), color: textColor.vfxSIMD(with: traitCollection),
            cell: SIMD2(Float(cell.width), Float(cell.height)),
            origin: SIMD2(Float(originX), Float((bounds.height - cell.height) / 2)))
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(atlas, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<OdometerUniforms>.stride, index: 0)
        encoder.setFragmentBytes(digits, length: MemoryLayout<OdometerDigit>.stride * digits.count, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}

/// [ − ] 42 [ + ] with the odometer in the middle.
final class OdometerStepper: UIControl {
    let range: ClosedRange<Int>
    private(set) var value: Int
    private let odometer: OdometerView
    private let minus = UIButton(type: .system)
    private let plus = UIButton(type: .system)
    private let background = UIView()
    private var shake = Spring1D(0, stiffness: 30, dampingRatio: 0.25)
    private var shakeLink: CADisplayLink?
    private let tap = UIImpactFeedbackGenerator(style: .light)
    private let wall = UIImpactFeedbackGenerator(style: .rigid)

    init(value: Int, range: ClosedRange<Int>) {
        self.range = range
        self.value = value
        odometer = OdometerView(value: value, maxDigits: String(range.upperBound).count)
        super.init(frame: .zero)
        background.backgroundColor = .secondarySystemBackground
        background.layer.cornerCurve = .continuous
        background.isUserInteractionEnabled = false
        for (button, symbol, step) in [(minus, "minus", -1), (plus, "plus", 1)] {
            button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)),
                            for: .normal)
            button.addAction(UIAction { [weak self] _ in self?.change(by: step) }, for: .touchUpInside)
        }
        for view in [background, odometer, minus, plus] {
            addSubview(view)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: odometer.intrinsicContentSize.width + 140, height: 64)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        background.frame = bounds
        background.layer.cornerRadius = bounds.height / 2
        minus.frame = CGRect(x: 0, y: 0, width: 64, height: bounds.height)
        plus.frame = CGRect(x: bounds.width - 64, y: 0, width: 64, height: bounds.height)
        odometer.frame = CGRect(x: 64, y: 0, width: bounds.width - 128, height: bounds.height)
    }

    private func change(by step: Int) {
        let next = value + step
        guard range.contains(next) else {
            // At the limit: shake, and let the number overshoot past it and bounce back.
            wall.impactOccurred()
            odometer.kick(CGFloat(step) * 9)
            shake.velocity += CGFloat(step) * 260
            startShake()
            return
        }
        tap.impactOccurred(intensity: 0.6)
        value = next
        odometer.setValue(next)
        sendActions(for: .valueChanged)
    }

    private func startShake() {
        guard shakeLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(stepShake(_:)))
        link.add(to: .main, forMode: .common)
        shakeLink = link
    }

    @objc private func stepShake(_ link: CADisplayLink) {
        shake.step(toward: 0, deltaTime: min(link.targetTimestamp - link.timestamp, 1.0 / 30))
        transform = CGAffineTransform(translationX: shake.value, y: 0)
        if shake.isSettled(at: 0, tolerance: 0.05) {
            transform = .identity
            link.invalidate()
            shakeLink = nil
        }
    }
}
