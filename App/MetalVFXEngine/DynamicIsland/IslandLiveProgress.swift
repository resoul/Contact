//
//  IslandLiveProgress.swift
//  controller
//
//  An in-app Live Activity: the Dynamic Island grows a little wider and down (staying clear of the
//  clock and the battery), showing an icon, a percentage and a glass tube of liquid that fills up, sloshing when the progress jumps (Shaders/IslandFluid.metal,
//  island_tube_fragment). On completion the pill shrinks back and a drop with a check mark pops out.
//

import UIKit
import Metal

/// Mirrors `IslandTubeUniforms` in IslandFluid.metal.
private struct IslandTubeUniforms {
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

final class IslandLiveProgress: IslandFluidView {
    var fillColor: UIColor = .systemGreen
    /// 0…1. The liquid catches up with a slosh.
    var progress: CGFloat = 0 {
        didSet {
            progress = max(0, min(1, progress))
            label.text = "\(Int((progress * 100).rounded()))%"
            isPaused = false
        }
    }

    private enum Phase {
        case hidden
        case shown
        case completing(CFTimeInterval)
        case celebrating(CFTimeInterval)
    }

    private var phase = Phase.hidden
    private var swell = IslandSpring(.zero, stiffness: 13, dampingRatio: 0.45)
    private var fill: CGFloat = 0
    private var fillVelocity: CGFloat = 0
    private var drop = IslandSpring(.zero, stiffness: 15, dampingRatio: 0.42)
    private var dropRadius: CGFloat = 0
    private var recoilTime: CFTimeInterval?
    private let icon = UIImageView()
    private let label = UILabel()
    private let check = UIImageView(image: UIImage(systemName: "checkmark"))
    private let haptic = UIImpactFeedbackGenerator(style: .soft)
    private let success = UINotificationFeedbackGenerator()

    override init(frame: CGRect) {
        super.init(frame: frame)
        gloss = 0.5
        rimWidth = 10
        isPaused = true
        icon.tintColor = .white
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .right
        label.text = "0%"
        check.tintColor = .systemGreen
        check.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 15, weight: .heavy)
        for view in [icon, label, check] {
            view.alpha = 0
            addSubview(view)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var restHalf: CGPoint {
        CGPoint(x: island.width / 2, y: island.height / 2)
    }

    /// Wide enough for a row under the island, narrow enough to leave the status bar readable.
    private var expandedHalf: CGPoint {
        CGPoint(x: island.width / 2 + 32, y: (island.height + 32) / 2)
    }

    /// Vertical center of the row under the island, once grown.
    private var rowY: CGFloat {
        island.minY + swell.position.y * 2 - 16
    }

    // MARK: Public API

    func show(symbol: String) {
        icon.image = UIImage(systemName: symbol)
        icon.sizeToFit()
        if case .hidden = phase {
            swell.position = restHalf
            fill = 0
            fillVelocity = 0
        }
        phase = .shown
        haptic.impactOccurred(intensity: 0.6)
        isPaused = false
    }

    /// Fills up, then the pill shrinks back and a check-mark drop pops out.
    func complete() {
        guard case .shown = phase else { return }
        progress = 1
        phase = .completing(0)
    }

    func hide() {
        phase = .hidden
        isPaused = false
    }

    // MARK: Simulation

    private var tubeRect: CGRect {
        let half = swell.position
        let minX = island.midX - half.x + 36, maxX = island.midX + half.x - 52
        return CGRect(x: minX, y: rowY - 4, width: max(maxX - minX, 0), height: 8)
    }

    /// 0 while the pill is island-sized, 1 when fully stretched.
    private var openness: CGFloat {
        let rest = restHalf.y, full = expandedHalf.y
        return max(0, min(1, (swell.position.y - rest) / max(full - rest, 1)))
    }

    override func update(deltaTime: CFTimeInterval) {
        let dt = CGFloat(deltaTime)
        let mouth = islandMouth
        var swellTarget = restHalf
        switch phase {
        case .hidden:
            break
        case .shown:
            swellTarget = expandedHalf
        case .completing(let t):
            swellTarget = expandedHalf
            let now = t + deltaTime
            phase = .completing(now)
            if fill > 0.985, now > 0.5 {
                phase = .celebrating(0)
                drop = IslandSpring(CGPoint(x: mouth.x, y: mouth.y - 6), stiffness: 15, dampingRatio: 0.42)
                dropRadius = 4
                success.notificationOccurred(.success)
            }
        case .celebrating(let t):
            let now = t + deltaTime
            phase = .celebrating(now)
            let hanging = now < 1.2
            drop.step(toward: hanging ? CGPoint(x: mouth.x, y: mouth.y + 30) : CGPoint(x: mouth.x, y: mouth.y - 4),
                      deltaTime: deltaTime)
            dropRadius += ((hanging ? 15 : 6) - dropRadius) * min(1, dt * 9)
            check.center = drop.position
            check.alpha = hanging && now > 0.15 ? 1 : 0
            if !hanging, drop.position.distance(to: mouth) < 8 {
                phase = .hidden
                dropRadius = 0
                recoilTime = 0
                haptic.impactOccurred()
            }
        }
        swell.step(toward: swellTarget, deltaTime: deltaTime)
        // The liquid level: a soft spring, so a jump in progress sloshes.
        fillVelocity += (60 * (progress - fill) - 6 * fillVelocity) * dt
        fill = max(0, min(1, fill + fillVelocity * dt))

        let open = openness
        icon.alpha = open > 0.6 ? 1 : 0
        label.alpha = icon.alpha
        icon.center = CGPoint(x: island.midX - swell.position.x + 20, y: rowY)
        label.frame = CGRect(x: island.midX + swell.position.x - 50, y: rowY - 9, width: 40, height: 18)

        if let t = recoilTime {
            recoilTime = t > 1 ? nil : t + deltaTime
        }
        rebuildShapes()
        if case .hidden = phase, open == 0, swell.speed < 0.5, recoilTime == nil, dropRadius == 0 {
            settle()
        }
    }

    private func rebuildShapes() {
        var newShapes: [IslandFluidShape] = []
        let half = swell.position
        if half.x > restHalf.x + 0.3 || half.y > restHalf.y + 0.3 {
            newShapes.append(IslandFluidShape(center: CGPoint(x: island.midX, y: island.minY + half.y),
                                              halfSize: CGSize(width: max(half.x, restHalf.x), height: max(half.y, restHalf.y)),
                                              cornerRadius: min(restHalf.y + 4, max(half.y, restHalf.y)), blend: 0))
        }
        if dropRadius > 0.5 {
            newShapes.append(.circle(center: drop.position, radius: dropRadius, blend: 12))
        }
        if let t = recoilTime {
            newShapes.append(recoilBump(t, amplitude: 8))
        }
        shapes = newShapes
    }

    override func encode(into commandBuffer: MTLCommandBuffer, target: MTLTexture) {
        super.encode(into: commandBuffer, target: target)
        let tube = tubeRect
        guard openness > 0.85, tube.width > 4, let gpu,
              let pipeline = gpu.renderPipeline(vertex: "island_fluid_vertex", fragment: "island_tube_fragment")
        else { return }
        let pass = renderPass(target: target)
        pass.colorAttachments[0].loadAction = .load
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        let scale = contentScaleFactor
        let pixels = CGRect(x: tube.minX * scale, y: tube.minY * scale, width: tube.width * scale, height: tube.height * scale)
            .insetBy(dx: -2, dy: -2).integral
            .intersection(CGRect(x: 0, y: 0, width: target.width, height: target.height))
        if !pixels.isNull, pixels.width > 0, pixels.height > 0 {
            encoder.setScissorRect(MTLScissorRect(x: Int(pixels.minX), y: Int(pixels.minY),
                                                  width: Int(pixels.width), height: Int(pixels.height)))
            var uniforms = IslandTubeUniforms(
                viewport: SIMD2(Float(target.width), Float(target.height)), scale: Float(scale), time: Float(time),
                rect: SIMD4(Float(tube.minX), Float(tube.minY), Float(tube.width), Float(tube.height)),
                fill: Float(fill), slosh: Float(fillVelocity),
                liquid: fillColor.vfxSIMD(with: traitCollection),
                track: SIMD4(1, 1, 1, 0.16))
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<IslandTubeUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        encoder.endEncoding()
    }
}
