//
//  ClayButton.swift
//  controller
//
//  A soft, tactile button that looks like modelling clay (Shaders/LiquidUI.metal, clay_fragment):
//  a rounded slab lit by a light that stays put while the phone tilts. Pressing leaves a dent right
//  under the finger, the shadow tightens, and on release the clay springs back — overshooting into
//  a little bulge before it settles.
//

import UIKit
import Metal

/// Mirrors `ClayUniforms` in LiquidUI.metal.
private struct ClayUniforms {
    var viewport: SIMD2<Float>
    var scale: Float
    var depth: Float
    var rect: SIMD4<Float>
    var color: SIMD4<Float>
    var press: SIMD2<Float>
    var light: SIMD2<Float>
    var radius: Float
    var bevel: Float
    var pressRadius: Float
    var time: Float
}

final class ClayButton: UIControl {
    var clayColor: UIColor = UIColor(red: 0.98, green: 0.80, blue: 0.70, alpha: 1)
    var cornerRadius: CGFloat = 22

    private let surface = ClaySurface()
    private let titleLabel = UILabel()
    private let iconView = UIImageView()
    private let content = UIStackView()
    private var depth = Spring1D(0, stiffness: 20, dampingRatio: 0.32)
    private var pressPoint = CGPoint.zero
    private var pressed = false
    private let shadowRoom: CGFloat = 40
    private let down = UIImpactFeedbackGenerator(style: .soft)
    private let up = UIImpactFeedbackGenerator(style: .light)

    init(title: String, symbol: String? = nil, color: UIColor? = nil) {
        super.init(frame: .zero)
        if let color {
            clayColor = color
        }
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)
        titleLabel.textColor = UIColor(white: 0.15, alpha: 0.85)
        iconView.image = symbol.flatMap { UIImage(systemName: $0) }
        iconView.tintColor = titleLabel.textColor
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 17, weight: .bold)
        iconView.isHidden = symbol == nil
        content.addArrangedSubview(iconView)
        content.addArrangedSubview(titleLabel)
        content.spacing = 8
        content.alignment = .center
        content.isUserInteractionEnabled = false
        surface.isUserInteractionEnabled = false
        surface.button = self
        addSubview(surface)
        addSubview(content)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        let size = content.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        return CGSize(width: size.width + 56, height: 60)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        surface.frame = bounds.insetBy(dx: -shadowRoom, dy: -shadowRoom)
        content.sizeToFit()
        content.bounds = CGRect(origin: .zero, size: content.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize))
        positionContent()
    }

    // MARK: Touches

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        pressed = true
        pressPoint = touch.location(in: self)
        down.impactOccurred()
        surface.isPaused = false
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        pressPoint = touch.location(in: self)
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        release()
    }

    override func cancelTracking(with event: UIEvent?) {
        release()
    }

    private func release() {
        guard pressed else { return }
        pressed = false
        up.impactOccurred(intensity: 0.5)
    }

    // MARK: Simulation

    fileprivate func step(_ dt: CFTimeInterval) {
        depth.step(toward: pressed ? 1 : 0, deltaTime: dt)
        positionContent()
    }

    /// The label sinks into the dent with the clay.
    private func positionContent() {
        let d = depth.value
        let lean = CGPoint(x: (pressPoint.x - bounds.midX) * 0.04 * max(d, 0), y: 1.8 * d)
        content.center = CGPoint(x: bounds.midX + lean.x, y: bounds.midY + lean.y)
        content.transform = CGAffineTransform(scaleX: 1 - 0.03 * d, y: 1 - 0.03 * d)
    }

    fileprivate func uniforms(target: MTLTexture, scale: CGFloat, time: CFTimeInterval) -> ClayUniforms {
        let gravity = LiquidUIMotion.shared.gravity
        // The light sits above the screen, against gravity, so it stays put as the phone tilts.
        let light = SIMD2(Float(-gravity.x), Float(-max(gravity.y, 0.3)))
        let press = pressPoint == .zero ? CGPoint(x: bounds.midX, y: bounds.midY) : pressPoint
        return ClayUniforms(
            viewport: SIMD2(Float(target.width), Float(target.height)), scale: Float(scale),
            depth: Float(depth.value),
            rect: SIMD4(Float(shadowRoom), Float(shadowRoom), Float(bounds.width), Float(bounds.height)),
            color: clayColor.vfxSIMD(with: traitCollection),
            press: SIMD2(Float(press.x + shadowRoom), Float(press.y + shadowRoom)),
            light: light,
            radius: Float(min(cornerRadius, bounds.height / 2)),
            bevel: Float(min(18, bounds.height / 2)),
            pressRadius: Float(min(bounds.width, bounds.height) * 0.45),
            time: Float(time))
    }
}

/// The Metal surface behind a ClayButton; keeps drawing so the light can follow the tilt.
private final class ClaySurface: VFXMetalView {
    weak var button: ClayButton?

    override init(frame: CGRect) {
        super.init(frame: frame)
        preferredFramesPerSecond = 60
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func update(deltaTime: CFTimeInterval) {
        button?.step(deltaTime)
    }

    override func encode(into commandBuffer: MTLCommandBuffer, target: MTLTexture) {
        guard let gpu, let button,
              let pipeline = gpu.renderPipeline(vertex: "liquid_ui_vertex", fragment: "clay_fragment"),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass(target: target)) else {
            super.encode(into: commandBuffer, target: target)
            return
        }
        var uniforms = button.uniforms(target: target, scale: contentScaleFactor, time: time)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ClayUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}
