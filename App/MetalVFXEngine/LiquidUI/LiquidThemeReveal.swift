//
//  LiquidThemeReveal.swift
//  controller
//
//  Switching light/dark with liquid: the old screen is snapshotted, the new theme is applied under
//  it, and the new theme spreads from the touch point as a wobbling liquid front that throws drops
//  ahead of itself, the old screen bending at the edge (theme_reveal_fragment in LiquidUI.metal).
//

import UIKit
import Metal

/// Mirrors `ThemeRevealUniforms` in LiquidUI.metal.
private struct ThemeRevealUniforms {
    var viewport: SIMD2<Float>
    var scale: Float
    var radius: Float
    var origin: SIMD2<Float>
    var time: Float
    var seed: Float
}

enum LiquidThemeReveal {
    /// Snapshots `window`, runs `apply` (e.g. flips `overrideUserInterfaceStyle`) under the snapshot,
    /// then floods the new look in from `point` (window coordinates).
    static func transition(
        in window: UIWindow,
        from point: CGPoint,
        duration: TimeInterval = 0.95,
        apply: () -> Void,
        completion: (() -> Void)? = nil
    ) {
        guard let snapshot = VFXGPU.shared?.makeTexture(snapshotting: window, scale: window.traitCollection.displayScale)
        else {
            apply()
            completion?()
            return
        }
        let overlay = ThemeRevealView(snapshot: snapshot, origin: point, duration: duration)
        overlay.frame = window.bounds
        overlay.accessibilityIdentifier = "contact.theme.reveal"
        overlay.onFinish = { [weak overlay] in
            overlay?.removeFromSuperview()
            completion?()
        }
        window.addSubview(overlay)
        apply()
        window.bringSubviewToFront(overlay)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
}

private final class ThemeRevealView: VFXMetalView {
    var onFinish: (() -> Void)?
    private let snapshot: MTLTexture
    private let origin: CGPoint
    private let duration: TimeInterval
    private let seed = Float.random(in: 0...40)
    private var finished = false
    private var started: CFTimeInterval?
    private var elapsed: TimeInterval { started.map { CACurrentMediaTime() - $0 } ?? 0 }

    override func didMoveToWindow() {
        if window != nil, started == nil { started = CACurrentMediaTime() }
        super.didMoveToWindow()
    }

    init(snapshot: MTLTexture, origin: CGPoint, duration: TimeInterval) {
        self.snapshot = snapshot
        self.origin = origin
        self.duration = duration
        super.init(frame: .zero)
        isUserInteractionEnabled = true   // the old screen is gone: swallow taps until the reveal ends
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Far enough to clear the farthest corner, plus the wobble and the drops ahead of the front.
    private var maxRadius: CGFloat {
        let corners = [CGPoint.zero, CGPoint(x: bounds.width, y: 0), CGPoint(x: 0, y: bounds.height),
                       CGPoint(x: bounds.width, y: bounds.height)]
        return (corners.map { $0.distance(to: origin) }.max() ?? 0) + 90
    }

    override func update(deltaTime: CFTimeInterval) {
        if elapsed >= duration, !finished {
            finished = true
            isPaused = true
            DispatchQueue.main.async { [weak self] in self?.onFinish?() }
        }
    }

    override func encode(into commandBuffer: MTLCommandBuffer, target: MTLTexture) {
        guard let gpu, let pipeline = gpu.renderPipeline(vertex: "liquid_ui_vertex", fragment: "theme_reveal_fragment"),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass(target: target)) else { return }
        // Ease in-out: a slow start as the liquid wells up, then it floods.
        let t = min(1, elapsed / duration)
        let eased = t * t * (3 - 2 * t)
        var uniforms = ThemeRevealUniforms(
            viewport: SIMD2(Float(target.width), Float(target.height)), scale: Float(contentScaleFactor),
            radius: Float(eased * maxRadius), origin: SIMD2(Float(origin.x), Float(origin.y)),
            time: Float(time), seed: seed)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(snapshot, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ThemeRevealUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}
