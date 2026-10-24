//
//  FerrofluidIslandView.swift
//  controller
//
//  The Dynamic Island as a pool of ferrofluid and the finger as a magnet: spikes grow toward the
//  finger as it comes close, pressing at the island pulls out a tendril that tears off into a spiky
//  blob following the finger, and letting go sends the blob back. Drawn by IslandFluidView.
//

import UIKit

final class FerrofluidIslandView: IslandFluidView {
    /// Farthest a finger can be from the island and still raise spikes, points.
    var magnetRange: CGFloat = 320
    /// Longest island spike, points.
    var maxSpikeLength: CGFloat = 40
    /// How far the tendril stretches before it tears, points.
    var tearDistance: CGFloat = 150
    var blobRadius: CGFloat = 17
    /// 0…1 extra spike length driven from outside, e.g. an audio level. Spikes jump with it.
    var pulse: CGFloat = 0 {
        didSet { if pulse > 0 { isPaused = false } }
    }

    private enum Phase {
        case resting
        case pulling
        case detached
        case returning
    }

    private let islandSpikeCount = 9
    private let blobSpikeCount = 12

    private var phase = Phase.resting
    private var finger: CGPoint?
    private var pressed = false
    private var attraction: CGFloat = 0
    private var hedgehog: CGFloat = 0
    private var blob = IslandSpring(.zero, stiffness: 30, dampingRatio: 0.8)
    private var recoilTime: CFTimeInterval?
    private var spikeLengths: [CGFloat]
    private var spikeVelocities: [CGFloat]
    private var spikesAwake = false

    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    private let rigidHaptic = UIImpactFeedbackGenerator(style: .rigid)
    private let softHaptic = UIImpactFeedbackGenerator(style: .soft)

    override init(frame: CGRect) {
        spikeLengths = Array(repeating: 0, count: islandSpikeCount)
        spikeVelocities = Array(repeating: 0, count: islandSpikeCount)
        super.init(frame: frame)
        rimWidth = 7
        isPaused = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Moves the magnet. `point` is in window coordinates; nil when no finger is on the screen.
    func magnet(at point: CGPoint?, pressed: Bool) {
        finger = point
        self.pressed = pressed && point != nil
        if point != nil {
            lightHaptic.prepare()
            rigidHaptic.prepare()
        }
        isPaused = false
    }

    // MARK: Simulation

    override func update(deltaTime: CFTimeInterval) {
        let mouth = islandMouth
        let targetAttraction: CGFloat
        if let finger, phase == .resting || phase == .pulling {
            targetAttraction = max(0, min(1, 1 - (finger.distance(to: mouth) - 30) / magnetRange))
        } else {
            targetAttraction = 0
        }
        attraction += (targetAttraction - attraction) * min(1, CGFloat(deltaTime) * 9)
        if attraction > 0.15, !spikesAwake {
            spikesAwake = true
            lightHaptic.impactOccurred(intensity: 0.6)
        } else if attraction < 0.05 {
            spikesAwake = false
        }

        switch phase {
        case .resting:
            if pressed, let finger, finger.distance(to: mouth) < 70 {
                phase = .pulling
                blob = IslandSpring(CGPoint(x: mouth.x, y: mouth.y - 4), stiffness: 30, dampingRatio: 0.8)
            }
        case .pulling:
            if let finger, pressed {
                blob.step(toward: finger, deltaTime: deltaTime)
                if blob.position.distance(to: mouth) > tearDistance {
                    phase = .detached
                    blob.stiffness = 16
                    blob.dampingRatio = 0.5
                    recoilTime = 0
                    rigidHaptic.impactOccurred()
                }
            } else {
                beginReturn()
            }
        case .detached:
            if let finger, pressed {
                blob.step(toward: finger, deltaTime: deltaTime)
            } else {
                beginReturn()
            }
        case .returning:
            blob.step(toward: CGPoint(x: mouth.x, y: mouth.y + 4), deltaTime: deltaTime)
            if blob.position.distance(to: mouth) < 16 {
                phase = .resting
                recoilTime = 0
                softHaptic.impactOccurred()
            }
        }
        let targetHedgehog: CGFloat = phase == .detached ? 1 : 0
        hedgehog += (targetHedgehog - hedgehog) * min(1, CGFloat(deltaTime) * (phase == .detached ? 6 : 10))
        if let t = recoilTime {
            recoilTime = t > 1.2 ? nil : t + deltaTime
        }

        updateIslandSpikes(deltaTime: deltaTime)
        rebuildShapes()

        let settled = phase == .resting && attraction < 0.002 && recoilTime == nil && pulse == 0
            && spikeLengths.allSatisfy { abs($0) < 0.2 } && !pressed
        if settled {
            shapes = []
            spikes = []
            renderFrame()
            isPaused = true
        }
    }

    private func beginReturn() {
        phase = .returning
        blob.stiffness = 22
        blob.dampingRatio = 0.75
        softHaptic.prepare()
    }

    /// The bulge under the island that leans toward the magnet; island spikes grow from it.
    private var bulge: (center: CGPoint, radius: CGFloat) {
        let mouth = islandMouth
        let lean = finger.map { max(-1, min(1, ($0.x - mouth.x) / 160)) } ?? 0
        let a = attraction + pulse * 0.3
        return (CGPoint(x: mouth.x + lean * 16 * a, y: mouth.y - 8 + 9 * a), 9 + 5 * a)
    }

    /// Target length of each island spike, eased by a jelly spring so they overshoot as they rise.
    private func updateIslandSpikes(deltaTime: CFTimeInterval) {
        let (center, _) = bulge
        let reach = finger.map { max(0, $0.distance(to: center) - 34) } ?? .infinity
        let dt = CGFloat(deltaTime)
        for i in 0..<islandSpikeCount {
            let offset = (CGFloat(i) / CGFloat(islandSpikeCount - 1) - 0.5) * 2.3
            let falloff = pow(max(cos(offset * 0.95), 0), 2)
            let shimmer = 0.85 + 0.15 * sin(CGFloat(time) * 7 + CGFloat(i) * 2.3)
            let level = attraction + pulse * (0.5 + 0.5 * falloff)
            var target = maxSpikeLength * level * falloff * shimmer
            target = min(target, reach)
            if phase != .resting && phase != .pulling {
                target = 0
            }
            // Spring with ζ ≈ 0.35: they spring up and wobble before settling.
            let k: CGFloat = 900, c: CGFloat = 21
            spikeVelocities[i] += (k * (target - spikeLengths[i]) - c * spikeVelocities[i]) * dt
            spikeLengths[i] += spikeVelocities[i] * dt
        }
    }

    private func rebuildShapes() {
        let mouth = islandMouth
        var newShapes: [IslandFluidShape] = []
        var newSpikes: [IslandFluidSpike] = []

        let (bulgeCenter, bulgeRadius) = bulge
        let a = max(attraction, pulse * 0.6)
        if a > 0.01 || phase == .pulling {
            newShapes.append(.circle(center: bulgeCenter, radius: bulgeRadius * min(1, a * 3 + (phase == .pulling ? 1 : 0)),
                                     blend: 10))
        }

        // Island spikes fan out around the direction of the finger.
        let toFinger = finger.map { atan2($0.y - bulgeCenter.y, $0.x - bulgeCenter.x) } ?? .pi / 2
        let aim = max(0.25, min(.pi - 0.25, toFinger))
        for i in 0..<islandSpikeCount where spikeLengths[i] > 0.8 {
            let offset = (CGFloat(i) / CGFloat(islandSpikeCount - 1) - 0.5) * 2.3
            let angle = aim + offset
            let radial = CGVector(dx: cos(angle), dy: sin(angle))
            // Field lines bend toward the magnet: tilt each spike partly toward the finger.
            var dir = radial
            if let finger {
                let to = CGVector(dx: finger.x - bulgeCenter.x, dy: finger.y - bulgeCenter.y)
                let len = max(hypot(to.dx, to.dy), 1)
                dir = CGVector(dx: radial.dx * 0.55 + to.dx / len * 0.45, dy: radial.dy * 0.55 + to.dy / len * 0.45)
                let dirLen = max(hypot(dir.dx, dir.dy), 1e-3)
                dir = CGVector(dx: dir.dx / dirLen, dy: dir.dy / dirLen)
            }
            let base = CGPoint(x: bulgeCenter.x + radial.dx * bulgeRadius * 0.6,
                               y: max(bulgeCenter.y + radial.dy * bulgeRadius * 0.6, mouth.y - 6))
            let length = spikeLengths[i] + bulgeRadius * 0.4
            let tip = CGPoint(x: base.x + dir.dx * length, y: base.y + dir.dy * length)
            newSpikes.append(IslandFluidSpike(base: base, tip: tip, baseRadius: 5, tipRadius: 0.45, blend: 3.5))
        }

        if phase != .resting {
            let center = blob.position
            let distance = center.distance(to: mouth)
            let stretch = min(1, distance / tearDistance)
            let radius = phase == .pulling ? 8 + (blobRadius - 8) * min(1, distance / 80) : blobRadius
            newShapes.append(.circle(center: center, radius: radius, blend: phase == .pulling ? 10 : 6))

            // Tendril while pulling: two tapered cones that pinch in the middle as it stretches.
            if phase == .pulling {
                let mid = CGPoint(x: (mouth.x + center.x) / 2, y: (mouth.y + center.y) / 2)
                let neck = 1.2 + 5 * pow(1 - stretch, 1.5)
                newSpikes.append(IslandFluidSpike(base: CGPoint(x: mouth.x, y: mouth.y - 4), tip: mid,
                                                  baseRadius: 9 * (1 - stretch) + 3, tipRadius: neck, blend: 6))
                newSpikes.append(IslandFluidSpike(base: mid, tip: center, baseRadius: neck,
                                                  tipRadius: radius * 0.7, blend: 6))
            }

            // A drop of liquid lagging behind a fast blob: a teardrop instead of a ball.
            if phase != .pulling {
                let lag = CGVector(dx: -blob.velocity.dx * 0.035, dy: -blob.velocity.dy * 0.035)
                let lagLength = min(hypot(lag.dx, lag.dy), 26)
                if lagLength > 1 {
                    let scale = lagLength / hypot(lag.dx, lag.dy)
                    newShapes.append(.circle(center: CGPoint(x: center.x + lag.dx * scale, y: center.y + lag.dy * scale),
                                             radius: radius * 0.62, blend: 14))
                }
            }

            // Hedgehog: a crown of spikes standing up around the magnet under the blob.
            let crown = hedgehog * (1 + pulse * 0.6)
            if crown > 0.02 {
                for i in 0..<blobSpikeCount {
                    let angle = CGFloat(i) / CGFloat(blobSpikeCount) * 2 * .pi + CGFloat(time) * 0.5
                    let radial = CGVector(dx: cos(angle), dy: sin(angle))
                    let length = (13 + 4 * sin(CGFloat(time) * 5 + CGFloat(i) * 1.3)) * crown
                    // Spikes lean back against the motion, like hair in the wind.
                    let drag = CGVector(dx: -blob.velocity.dx * 0.012, dy: -blob.velocity.dy * 0.012)
                    let base = CGPoint(x: center.x + radial.dx * radius * 0.7, y: center.y + radial.dy * radius * 0.7)
                    let tip = CGPoint(x: center.x + radial.dx * (radius + length) + drag.dx * crown,
                                      y: center.y + radial.dy * (radius + length) + drag.dy * crown)
                    newSpikes.append(IslandFluidSpike(base: base, tip: tip, baseRadius: 4.6, tipRadius: 0.5, blend: 3))
                }
            }
        }

        // The torn neck springs back into the island.
        if let t = recoilTime {
            let extent = 12 * exp(-7 * t) * cos(18 * t)
            newShapes.append(.circle(center: CGPoint(x: mouth.x, y: mouth.y - 7 + max(extent, -4)), radius: 7, blend: 10))
        }

        shapes = newShapes
        spikes = newSpikes
    }
}
