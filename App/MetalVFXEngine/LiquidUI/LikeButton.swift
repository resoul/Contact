//
//  LikeButton.swift
//  controller
//
//  A like button whose heart fills up with liquid from the tip (Shaders/LiquidUI.metal,
//  heart_fragment). The surface sloshes on the way up; when it's full the heart pops and bursts
//  into sparks that glow brighter than white on HDR screens. Tapping again drains it.
//

import UIKit
import Metal

/// Mirrors `HeartUniforms` in LiquidUI.metal.
private struct HeartUniforms {
    var viewport: SIMD2<Float>
    var scale: Float
    var level: Float
    var center: SIMD2<Float>
    var size: Float
    var slosh: Float
    var color: SIMD4<Float>
    var time: Float
    var stroke: Float
    var unused: SIMD2<Float> = .zero
}

final class LikeButton: UIControl {
    var heartColor: UIColor = .systemPink
    private(set) var isLiked = false

    private let heart = HeartView()
    private var level = Spring1D(0, stiffness: 6.5, dampingRatio: 0.55)
    private var pop = Spring1D(1, stiffness: 18, dampingRatio: 0.3)
    private var burst = false
    private let fillHaptic = UIImpactFeedbackGenerator(style: .soft)
    private let popHaptic = UIImpactFeedbackGenerator(style: .rigid)

    override init(frame: CGRect) {
        super.init(frame: frame)
        heart.isUserInteractionEnabled = false
        heart.owner = self
        addSubview(heart)
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: 80, height: 80)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        heart.bounds = bounds
        heart.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    @objc private func tapped() {
        isLiked.toggle()
        burst = false
        if isLiked {
            fillHaptic.impactOccurred(intensity: 0.6)
            popHaptic.prepare()
        } else {
            level.velocity = -1.5
        }
        heart.isPaused = false
        sendActions(for: .valueChanged)
    }

    fileprivate func step(_ dt: CFTimeInterval) {
        level.step(toward: isLiked ? 1 : 0, deltaTime: dt)
        if isLiked, !burst, level.value > 0.97 {
            burst = true
            pop.velocity += 6
            popHaptic.impactOccurred()
            if let window {
                let center = convert(CGPoint(x: bounds.midX, y: bounds.midY), to: window)
                IslandConfetti.burst(in: window, from: center, direction: -.pi / 2, spread: 2 * .pi, particles: 180,
                                     sparkShare: 1, sparkColor: heartColor, speedScale: 0.45)
            }
        }
        pop.step(toward: 1, deltaTime: dt)
        heart.transform = CGAffineTransform(scaleX: pop.value, y: pop.value)
        if level.isSettled(at: isLiked ? 1 : 0, tolerance: 0.002), pop.isSettled(at: 1, tolerance: 0.002) {
            heart.renderFrame()
            heart.isPaused = true
        }
    }

    fileprivate func uniforms(target: MTLTexture, scale: CGFloat, time: CFTimeInterval, size: CGSize) -> HeartUniforms {
        HeartUniforms(viewport: SIMD2(Float(target.width), Float(target.height)), scale: Float(scale),
                      level: Float(max(0, min(1, level.value))),
                      center: SIMD2(Float(size.width / 2), Float(size.height / 2)),
                      size: Float(min(size.width, size.height) * 0.62), slosh: Float(level.velocity),
                      color: heartColor.vfxSIMD(with: traitCollection), time: Float(time), stroke: 3)
    }
}

private final class HeartView: VFXMetalView {
    weak var owner: LikeButton?

    override func update(deltaTime: CFTimeInterval) {
        owner?.step(deltaTime)
    }

    override func encode(into commandBuffer: MTLCommandBuffer, target: MTLTexture) {
        guard let gpu, let owner,
              let pipeline = gpu.renderPipeline(vertex: "liquid_ui_vertex", fragment: "heart_fragment"),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass(target: target)) else {
            super.encode(into: commandBuffer, target: target)
            return
        }
        var uniforms = owner.uniforms(target: target, scale: contentScaleFactor, time: time, size: bounds.size)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<HeartUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}
