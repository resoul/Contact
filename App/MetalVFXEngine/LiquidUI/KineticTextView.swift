//
//  KineticTextView.swift
//  controller
//
//  A headline with kinetic type (kinetic_text_fragment in LiquidUI.metal): new text fills its letters
//  with liquid from the bottom, the old text crumbles away in glinting cells as it is replaced, and
//  while pressed the headline "breathes" — its weight swells and settles on a spring.
//

import UIKit
import Metal

/// Mirrors `KineticUniforms` in LiquidUI.metal.
private struct KineticUniforms {
    var viewport: SIMD2<Float>
    var scale: Float
    var reveal: Float
    var color: SIMD4<Float>
    var dissolve: Float
    var time: Float
    var unused: SIMD2<Float> = .zero
}

final class KineticTextView: VFXMetalView {
    var textColor: UIColor = .label
    var fontSize: CGFloat = 46
    private(set) var text = ""

    private var newTexture: MTLTexture?
    private var oldTexture: MTLTexture?
    private var revealStart: CFTimeInterval = -10
    private var dissolveStart: CFTimeInterval = -10
    private let revealDuration: CFTimeInterval = 1.1
    private let dissolveDuration: CFTimeInterval = 0.9
    /// 0 = regular … 1 = black; springs toward `targetWeight` for the breathing.
    private var weight = Spring1D(0.35, stiffness: 9, dampingRatio: 0.35)
    private var targetWeight: CGFloat = 0.35
    private var renderedWeight: CGFloat = -1
    private var pressed = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true
        let press = UILongPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
        press.minimumPressDuration = 0.05
        addGestureRecognizer(press)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Replaces the headline: the old one crumbles while the new one fills up.
    func setText(_ text: String) {
        oldTexture = newTexture
        self.text = text
        renderedWeight = -1
        newTexture = makeTexture()
        revealStart = time
        dissolveStart = oldTexture == nil ? -10 : time
        isPaused = false
    }

    @objc private func handlePress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            pressed = true
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case .ended, .cancelled, .failed:
            pressed = false
        default:
            break
        }
        isPaused = false
    }

    private func makeTexture() -> MTLTexture? {
        guard let gpu, bounds.width > 0 else { return nil }
        let raw = -0.4 + weight.value * 1.02
        let font = UIFont.systemFont(ofSize: fontSize, weight: UIFont.Weight(raw))
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
        let size = bounds.size
        let measured = (text as NSString).size(withAttributes: attributes)
        return gpu.makeTexture(size: size, scale: contentScaleFactor) { _ in
            (text as NSString).draw(at: CGPoint(x: (size.width - measured.width) / 2, y: (size.height - measured.height) / 2),
                                    withAttributes: attributes)
        }
    }

    override func drawableSizeDidChange(_ size: CGSize) {
        if !text.isEmpty {
            newTexture = makeTexture()
        }
    }

    override func update(deltaTime: CFTimeInterval) {
        // Breathing: while held the weight swells and pulses gently; let go and it settles back.
        targetWeight = pressed ? 0.85 + 0.12 * sin(time * 4) : 0.35
        weight.step(toward: targetWeight, deltaTime: deltaTime)
        if abs(weight.value - renderedWeight) > 0.01, revealProgress >= 1 {
            renderedWeight = weight.value
            newTexture = makeTexture()
        }
        let idle = !pressed && weight.isSettled(at: targetWeight, tolerance: 0.002)
            && revealProgress >= 1 && dissolveProgress >= 1
        if idle {
            renderFrame()
            isPaused = true
        }
    }

    private var revealProgress: CGFloat {
        CGFloat(max(0, min(1, (time - revealStart) / revealDuration)))
    }

    private var dissolveProgress: CGFloat {
        CGFloat(max(0, min(1, (time - dissolveStart) / dissolveDuration)))
    }

    override func encode(into commandBuffer: MTLCommandBuffer, target: MTLTexture) {
        guard let gpu, let newTexture,
              let pipeline = gpu.renderPipeline(vertex: "liquid_ui_vertex", fragment: "kinetic_text_fragment"),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass(target: target)) else {
            super.encode(into: commandBuffer, target: target)
            return
        }
        var uniforms = KineticUniforms(
            viewport: SIMD2(Float(target.width), Float(target.height)), scale: Float(contentScaleFactor),
            reveal: Float(revealProgress), color: textColor.vfxSIMD(with: traitCollection),
            dissolve: Float(oldTexture == nil ? 1 : dissolveProgress), time: Float(time))
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(newTexture, index: 0)
        encoder.setFragmentTexture(oldTexture ?? newTexture, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<KineticUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}
