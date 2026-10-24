//
//  CharacterRingView.swift
//  controller
//
//  The composer's character counter as a ring-shaped tube of liquid (character_ring_fragment in
//  SocialFX.metal). It fills as you type and the front sloshes; near the limit it turns amber, grows
//  a little and shows how many characters are left; past it, it turns red, overflows and drips.
//

import UIKit
import Metal

/// Mirrors `CharacterRingUniforms` in SocialFX.metal.
private struct CharacterRingUniforms {
    var viewport: SIMD2<Float>
    var scale: Float
    var time: Float
    var center: SIMD2<Float>
    var radius: Float
    var width: Float
    var fill: Float
    var slosh: Float
    var dripCount: UInt32
    var unused: Float = 0
    var liquid: SIMD4<Float>
    var track: SIMD4<Float>
}

final class CharacterRingView: VFXMetalView {
    var limit = 120
    private(set) var count = 0

    private let remainingLabel = UILabel()
    private var level = Spring1D(0, stiffness: 9, dampingRatio: 0.55)
    private var grow = Spring1D(1, stiffness: 14, dampingRatio: 0.5)
    private var drips: [(position: CGPoint, velocity: CGFloat, radius: CGFloat, age: CFTimeInterval)] = []
    private var dripTimer: CFTimeInterval = 0
    private var lastZone = 0
    private let ringRadius: CGFloat = 10

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        remainingLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        remainingLabel.textAlignment = .center
        remainingLabel.alpha = 0
        addSubview(remainingLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The ring sits at the top center; the rest of the view is room for drips.
    override var intrinsicContentSize: CGSize {
        CGSize(width: 44, height: 70)
    }

    private var ringCenter: CGPoint {
        CGPoint(x: bounds.midX, y: 22)
    }

    func setCount(_ newCount: Int) {
        count = newCount
        let remaining = limit - count
        remainingLabel.text = "\(remaining)"
        // 0 fine, 1 close to the limit, 2 over it: a haptic tick when the zone changes.
        let zone = remaining < 0 ? 2 : remaining <= 20 ? 1 : 0
        if zone != lastZone {
            UIImpactFeedbackGenerator(style: zone == 2 ? .rigid : .light).impactOccurred()
            if zone > lastZone {
                grow.velocity += 6
            }
            lastZone = zone
        }
        isPaused = false
    }

    private var color: UIColor {
        let remaining = limit - count
        if remaining < 0 { return UIColor(red: 0.96, green: 0.13, blue: 0.18, alpha: 1) }
        if remaining <= 20 { return UIColor(red: 1.0, green: 0.68, blue: 0.0, alpha: 1) }
        return TimelinePalette.accent
    }

    override func update(deltaTime: CFTimeInterval) {
        let target = CGFloat(count) / CGFloat(max(limit, 1))
        level.step(toward: min(target, 1.05), deltaTime: deltaTime)
        let remaining = limit - count
        grow.step(toward: remaining <= 20 ? 1.3 : 1, deltaTime: deltaTime)
        remainingLabel.textColor = color
        remainingLabel.alpha = remaining <= 20 ? 1 : 0
        remainingLabel.sizeToFit()
        remainingLabel.center = ringCenter

        // Over the limit: drips run off the bottom of the ring, faster the further over.
        let overflow = max(0, count - limit)
        if overflow > 0 {
            dripTimer += deltaTime
            let interval = max(0.18, 0.6 - Double(overflow) * 0.03)
            if dripTimer > interval, drips.count < 6 {
                dripTimer = 0
                let r = ringRadius * grow.value
                drips.append((CGPoint(x: ringCenter.x + CGFloat.random(in: -4...4), y: ringCenter.y + r + 1), 0,
                              CGFloat.random(in: 2.2...3.2), 0))
            }
        }
        drips = drips.compactMap { drip in
            var drip = drip
            drip.age += deltaTime
            // Clings at first, then lets go and falls, shrinking.
            drip.velocity += CGFloat(deltaTime) * (drip.age < 0.25 ? 40 : 420)
            drip.position.y += drip.velocity * CGFloat(deltaTime)
            drip.radius -= CGFloat(deltaTime) * 1.6
            return drip.radius > 0.4 && drip.position.y < bounds.height + 4 ? drip : nil
        }
        let settled = level.isSettled(at: min(target, 1.05), tolerance: 0.001) && grow.isSettled(at: remaining <= 20 ? 1.3 : 1,
                                                                                                    tolerance: 0.002)
        if settled, drips.isEmpty, overflow == 0 {
            renderFrame()
            isPaused = true
        }
    }

    override func encode(into commandBuffer: MTLCommandBuffer, target: MTLTexture) {
        guard let gpu, let pipeline = gpu.renderPipeline(vertex: "social_vertex", fragment: "character_ring_fragment"),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass(target: target)) else {
            super.encode(into: commandBuffer, target: target)
            return
        }
        let r = ringRadius * grow.value
        var uniforms = CharacterRingUniforms(
            viewport: SIMD2(Float(target.width), Float(target.height)), scale: Float(contentScaleFactor), time: Float(time),
            center: SIMD2(Float(ringCenter.x), Float(ringCenter.y)), radius: Float(r), width: Float(3 + (grow.value - 1) * 4),
            fill: Float(max(level.value, 0)), slosh: Float(level.velocity), dripCount: UInt32(drips.count),
            liquid: color.vfxSIMD(with: traitCollection),
            track: SIMD4(1, 1, 1, 0.16))
        let dripData = drips.isEmpty ? [SIMD4<Float>(-100, -100, 0, 0)]
            : drips.map { SIMD4(Float($0.position.x), Float($0.position.y), Float($0.radius), 0) }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<CharacterRingUniforms>.stride, index: 0)
        encoder.setFragmentBytes(dripData, length: MemoryLayout<SIMD4<Float>>.stride * dripData.count, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}
