//
//  LiquidSlider.swift
//  controller
//
//  A volume slider made of a glass tube of liquid (island_tube_fragment in IslandFluid.metal), with no
//  thumb hiding the surface: the level follows the finger on a soft spring, so a quick yank makes the
//  front slosh. Drag past either end and the whole tube stretches like jelly, then wobbles back.
//

import UIKit
import Metal

/// Mirrors `IslandTubeUniforms` in IslandFluid.metal.
private struct TubeUniforms {
    var viewport: SIMD2<Float>
    var scale: Float
    var time: Float
    var rect: SIMD4<Float>
    var fill: Float
    var slosh: Float
    var unused: SIMD2<Float> = .zero
    var liquid: SIMD4<Float>
    var track: SIMD4<Float>
}

/// Draws one liquid tube at `tubeRect` (its bounds when nil).
final class LiquidTubeView: VFXMetalView {
    var tubeRect: CGRect?
    var liquidColor: UIColor = .systemBlue
    var trackColor = UIColor.label.withAlphaComponent(0.1)
    var fill: CGFloat = 0
    var slosh: CGFloat = 0
    var onUpdate: ((CFTimeInterval) -> Void)?

    override func update(deltaTime: CFTimeInterval) {
        onUpdate?(deltaTime)
    }

    override func encode(into commandBuffer: MTLCommandBuffer, target: MTLTexture) {
        guard let gpu, let pipeline = gpu.renderPipeline(vertex: "island_fluid_vertex", fragment: "island_tube_fragment"),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass(target: target)) else { return }
        let track = trackColor.vfxSIMD(with: traitCollection)
        let rect = tubeRect ?? bounds
        var uniforms = TubeUniforms(
            viewport: SIMD2(Float(target.width), Float(target.height)), scale: Float(contentScaleFactor),
            time: Float(time), rect: SIMD4(Float(rect.minX), Float(rect.minY), Float(rect.width), Float(rect.height)),
            fill: Float(fill), slosh: Float(slosh), liquid: liquidColor.vfxSIMD(with: traitCollection),
            track: SIMD4(track.x, track.y, track.z, track.w))
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<TubeUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}

final class LiquidSlider: UIControl {
    /// 0…1.
    private(set) var value: CGFloat = 0.5
    var liquidColor: UIColor = .systemBlue {
        didSet { tube.liquidColor = liquidColor }
    }

    private let tube = LiquidTubeView()
    private let tubeHeight: CGFloat = 30
    /// Room around the tube for it to stretch into without resizing the Metal layer.
    private let slack: CGFloat = 48
    private var level = Spring1D(0.5, stiffness: 8, dampingRatio: 0.45)
    private var stretch = Spring1D(0, stiffness: 14, dampingRatio: 0.35)
    private var overdrag: CGFloat = 0
    private var dragging = false
    private var lastTick = -1
    private let tick = UISelectionFeedbackGenerator()
    private let edge = UIImpactFeedbackGenerator(style: .soft)

    override init(frame: CGRect) {
        super.init(frame: frame)
        tube.liquidColor = liquidColor
        tube.isUserInteractionEnabled = false
        addSubview(tube)
        tube.onUpdate = { [weak self] dt in self?.step(dt) }
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:))))
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 36)
    }

    func setValue(_ value: CGFloat, animated: Bool) {
        self.value = max(0, min(1, value))
        if !animated {
            level.value = self.value
            level.velocity = 0
        }
        tube.isPaused = false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        tube.frame = bounds.insetBy(dx: -slack, dy: 0)
        layoutTube()
    }

    // MARK: Touches

    private func valueAt(_ x: CGFloat) -> CGFloat {
        x / max(bounds.width, 1)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let x = gesture.location(in: self).x
        switch gesture.state {
        case .began, .changed:
            dragging = true
            let raw = valueAt(x)
            value = max(0, min(1, raw))
            // Past either end the slider stretches, with diminishing returns.
            let past = raw < 0 ? raw : (raw > 1 ? raw - 1 : 0)
            let newOverdrag = past * bounds.width
            if (overdrag == 0) != (newOverdrag == 0), newOverdrag != 0 {
                edge.impactOccurred(intensity: 0.6)
            }
            overdrag = newOverdrag
            let ticks = Int(value * 16)
            if ticks != lastTick {
                lastTick = ticks
                tick.selectionChanged()
            }
            sendActions(for: .valueChanged)
        default:
            dragging = false
            overdrag = 0
        }
        tube.isPaused = false
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        value = max(0, min(1, valueAt(gesture.location(in: self).x)))
        sendActions(for: .valueChanged)
        tube.isPaused = false
    }

    // MARK: Simulation

    private func step(_ dt: CFTimeInterval) {
        level.step(toward: value, deltaTime: dt)
        let target = overdrag == 0 ? 0 : (overdrag > 0 ? 1 : -1) * 34 * (1 - exp(-abs(overdrag) / 60))
        stretch.step(toward: target, deltaTime: dt)
        tube.fill = max(0, min(1, level.value))
        tube.slosh = level.velocity
        layoutTube()
        if !dragging, level.isSettled(at: value, tolerance: 0.0005), stretch.isSettled(at: 0, tolerance: 0.05) {
            tube.renderFrame()
            tube.isPaused = true
        }
    }

    /// The tube grows by the stretch, toward the side being pulled, and thins a little as it does.
    private func layoutTube() {
        let s = stretch.value
        let width = bounds.width + abs(s)
        let height = tubeHeight * (1 - min(abs(s) / 120, 0.25))
        let x = s < 0 ? s : 0
        tube.tubeRect = CGRect(x: slack + x, y: bounds.midY - height / 2, width: width, height: height)
    }
}
