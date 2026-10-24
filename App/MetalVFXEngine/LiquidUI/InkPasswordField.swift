//
//  InkPasswordField.swift
//  controller
//
//  A password field whose strength is liquid: the field fills from the left like a tube
//  (LiquidTubeView), red when weak through yellow to green when strong, sloshing as you type.
//  `rejectInk()` makes red ink soak out of its border with ragged tendrils (ink_bleed_fragment in
//  LiquidUI.metal); `approveRipple()` sends green rings racing out of it.
//

import UIKit
import Metal

/// Mirrors `InkBleedUniforms` in LiquidUI.metal.
private struct InkBleedUniforms {
    var viewport: SIMD2<Float>
    var scale: Float
    var progress: Float
    var rect: SIMD4<Float>
    var color: SIMD4<Float>
    var radius: Float
    var mode: UInt32
    var seed: Float
    var unused: Float = 0
}

final class InkPasswordField: UIView, UITextFieldDelegate {
    let textField = UITextField()
    /// 0…1, from the length and the variety of characters.
    private(set) var strength: CGFloat = 0

    private let tube = LiquidTubeView()
    private let bleed = InkBleedView()
    private var level = Spring1D(0, stiffness: 7, dampingRatio: 0.45)
    private let height: CGFloat = 56
    private let bleedRoom: CGFloat = 60

    override init(frame: CGRect) {
        super.init(frame: frame)
        tube.trackColor = UIColor.label.withAlphaComponent(0.06)
        tube.isUserInteractionEnabled = false
        tube.onUpdate = { [weak self] dt in self?.step(dt) }
        bleed.isUserInteractionEnabled = false
        bleed.isHidden = true
        textField.placeholder = "Password"
        textField.isSecureTextEntry = true
        textField.font = .systemFont(ofSize: 17, weight: .medium)
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        addSubview(bleed)
        addSubview(tube)
        addSubview(textField)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        tube.frame = bounds
        textField.frame = bounds.insetBy(dx: 22, dy: 0)
        bleed.frame = bounds.insetBy(dx: -bleedRoom, dy: -bleedRoom)
        bleed.fieldRect = CGRect(x: bleedRoom, y: bleedRoom, width: bounds.width, height: bounds.height)
    }

    /// Red ink soaks out of the field.
    func rejectInk() {
        bleed.play(mode: 0, color: .systemRed)
    }

    /// Green rings ripple out of the field.
    func approveRipple() {
        bleed.play(mode: 1, color: .systemGreen)
    }

    @objc private func textChanged() {
        let text = textField.text ?? ""
        var variety = 0
        if text.rangeOfCharacter(from: .lowercaseLetters) != nil { variety += 1 }
        if text.rangeOfCharacter(from: .uppercaseLetters) != nil { variety += 1 }
        if text.rangeOfCharacter(from: .decimalDigits) != nil { variety += 1 }
        if text.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) != nil { variety += 1 }
        strength = min(1, CGFloat(text.count) / 14 * 0.6 + CGFloat(variety) / 4 * 0.4)
        if text.isEmpty {
            strength = 0
        }
        tube.isPaused = false
    }

    private func step(_ dt: CFTimeInterval) {
        level.step(toward: strength, deltaTime: dt)
        tube.fill = max(0, min(1, level.value))
        tube.slosh = level.velocity
        tube.liquidColor = color(for: level.value).withAlphaComponent(0.35)
        if level.isSettled(at: strength, tolerance: 0.001) {
            tube.renderFrame()
            tube.isPaused = true
        }
    }

    /// Red → orange → yellow → green with strength.
    private func color(for value: CGFloat) -> UIColor {
        let stops: [UIColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen]
        let scaled = max(0, min(1, value)) * CGFloat(stops.count - 1)
        let index = min(Int(scaled), stops.count - 2)
        let f = scaled - CGFloat(index)
        var a = (r: CGFloat(0), g: CGFloat(0), b: CGFloat(0), alpha: CGFloat(0)), b = a
        stops[index].resolvedColor(with: traitCollection).getRed(&a.r, green: &a.g, blue: &a.b, alpha: &a.alpha)
        stops[index + 1].resolvedColor(with: traitCollection).getRed(&b.r, green: &b.g, blue: &b.b, alpha: &b.alpha)
        return UIColor(red: a.r + (b.r - a.r) * f, green: a.g + (b.g - a.g) * f, blue: a.b + (b.b - a.b) * f, alpha: 1)
    }
}

/// Plays the ink or the ripple around the field, then hides itself.
private final class InkBleedView: VFXMetalView {
    var fieldRect: CGRect = .zero
    private var mode: UInt32 = 0
    private var color: UIColor = .systemRed
    private var startTime: CFTimeInterval = 0
    private var seed: Float = 0
    private let duration: CFTimeInterval = 1.5

    func play(mode: UInt32, color: UIColor) {
        self.mode = mode
        self.color = color
        seed = .random(in: 0...50)
        startTime = time
        isHidden = false
        isPaused = false
    }

    override func update(deltaTime: CFTimeInterval) {
        if time - startTime > duration {
            isHidden = true
            isPaused = true
        }
    }

    override func encode(into commandBuffer: MTLCommandBuffer, target: MTLTexture) {
        guard !isHidden, let gpu,
              let pipeline = gpu.renderPipeline(vertex: "liquid_ui_vertex", fragment: "ink_bleed_fragment"),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass(target: target)) else {
            super.encode(into: commandBuffer, target: target)
            return
        }
        var uniforms = InkBleedUniforms(
            viewport: SIMD2(Float(target.width), Float(target.height)), scale: Float(contentScaleFactor),
            progress: Float(min(1, (time - startTime) / duration)),
            rect: SIMD4(Float(fieldRect.minX), Float(fieldRect.minY), Float(fieldRect.width), Float(fieldRect.height)),
            color: color.vfxSIMD(with: traitCollection), radius: Float(fieldRect.height / 2), mode: mode, seed: seed)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<InkBleedUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}
