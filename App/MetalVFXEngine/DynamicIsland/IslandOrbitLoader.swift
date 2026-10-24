//
//  IslandOrbitLoader.swift
//  controller
//
//  A loading indicator with no spinner: little moons orbit the Dynamic Island. Their orbits breathe
//  in and out, so on close passes they melt into the island and tear off again. `stop()` swallows
//  them.
//

import UIKit

final class IslandOrbitLoader: IslandFluidView {
    private struct Moon {
        let radius: CGFloat
        let speed: CGFloat
        let phase: CGFloat
    }

    private let moons = [Moon(radius: 6.5, speed: 2.3, phase: 0),
                         Moon(radius: 5, speed: 3.0, phase: 2.1),
                         Moon(radius: 4, speed: 3.8, phase: 4.2)]
    private var running = false
    private var appear: CGFloat = 0
    private var clock: CGFloat = 0
    private var recoilTime: CFTimeInterval?
    private let haptic = UIImpactFeedbackGenerator(style: .soft)

    override init(frame: CGRect) {
        super.init(frame: frame)
        gloss = 0.9
        rimWidth = 5
        isPaused = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isLoading: Bool {
        running
    }

    func start() {
        running = true
        isPaused = false
    }

    func stop() {
        guard running else { return }
        running = false
        haptic.prepare()
    }

    override func update(deltaTime: CFTimeInterval) {
        let dt = CGFloat(deltaTime)
        clock += dt
        let wasVisible = appear > 0
        appear = running ? min(1, appear + dt * 3) : max(0, appear - dt * 2.5)
        if wasVisible, appear == 0, !running {
            recoilTime = 0
            haptic.impactOccurred(intensity: 0.7)
        }
        if let t = recoilTime {
            recoilTime = t > 1 ? nil : t + deltaTime
        }

        var newShapes: [IslandFluidShape] = []
        let center = CGPoint(x: island.midX, y: island.midY)
        let ease = appear * appear * (3 - 2 * appear)
        for moon in moons where ease > 0 {
            // The orbit breathes: close passes merge with the island, far ones tear off.
            let distance = (7 + 13 * (0.5 + 0.5 * sin(clock * 1.6 + moon.phase * 1.3))) * ease
            let angle = moon.phase + moon.speed * clock
            let position = CGPoint(x: center.x + (island.width / 2 + distance) * cos(angle),
                                   y: center.y + (island.height / 2 + distance) * sin(angle))
            newShapes.append(.circle(center: position, radius: moon.radius * sqrt(ease), blend: 13))
        }
        if let t = recoilTime {
            newShapes.append(recoilBump(t, amplitude: 8))
        }
        shapes = newShapes
        if !running, appear == 0, recoilTime == nil {
            settle()
        }
    }
}
