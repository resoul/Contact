//
//  IslandUndoDrop.swift
//  controller
//
//  Undo as a drop of liquid: after something is deleted into the island, a drop with an undo arrow
//  hangs under it on a liquid neck. The neck thins out over `duration` — that is the timer — and
//  when it tears the drop falls and evaporates: the deletion is final. Tap the drop to take it back.
//

import UIKit

final class IslandUndoDrop: IslandFluidView {
    private static weak var current: IslandUndoDrop?

    /// Hangs an undo drop under the island in `window`. A drop already hanging is committed first.
    @discardableResult
    static func show(in window: UIWindow, duration: TimeInterval = 5,
                     onUndo: @escaping () -> Void, onCommit: (() -> Void)? = nil) -> IslandUndoDrop {
        current?.commitNow()
        let drop = IslandUndoDrop(duration: duration)
        drop.onUndo = onUndo
        drop.onCommit = onCommit
        drop.install(in: window)
        drop.start()
        current = drop
        return drop
    }

    private enum Phase {
        case hanging
        case undoing
        case falling
        case finished
    }

    private let duration: TimeInterval
    private var onUndo: (() -> Void)?
    private var onCommit: (() -> Void)?

    private let radius: CGFloat = 16
    private let hangDepth: CGFloat = 46
    private var phase = Phase.hanging
    private var phaseTime: CFTimeInterval = 0
    private var drop = IslandSpring(.zero, stiffness: 16, dampingRatio: 0.35)
    private var dropRadius: CGFloat = 4
    private var fallVelocity: CGFloat = 0
    private var recoilTime: CFTimeInterval?
    private let icon = UIImageView(image: UIImage(systemName: "arrow.uturn.backward"))

    private let rigidHaptic = UIImpactFeedbackGenerator(style: .rigid)
    private let softHaptic = UIImpactFeedbackGenerator(style: .soft)

    private init(duration: TimeInterval) {
        self.duration = duration
        super.init(frame: .zero)
        isUserInteractionEnabled = true
        icon.tintColor = .white
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        icon.alpha = 0
        addSubview(icon)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var hangPoint: CGPoint {
        CGPoint(x: islandMouth.x, y: islandMouth.y + hangDepth)
    }

    private func start() {
        drop.position = CGPoint(x: islandMouth.x, y: islandMouth.y - 4)
        rigidHaptic.prepare()
        isPaused = false
    }

    /// Ends the countdown right away, as if the neck had torn.
    func commitNow() {
        guard phase == .hanging else { return }
        tear()
    }

    // MARK: Touches

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        phase == .hanging && point.distance(to: drop.position) < radius + 14
    }

    @objc private func handleTap() {
        guard phase == .hanging else { return }
        phase = .undoing
        phaseTime = 0
        drop.stiffness = 26
        drop.dampingRatio = 0.8
        softHaptic.prepare()
        UIView.animate(withDuration: 0.12) { self.icon.alpha = 0 }
    }

    // MARK: Simulation

    /// 1 → 0 over the countdown.
    private var remaining: CGFloat {
        CGFloat(max(0, 1 - phaseTime / duration))
    }

    private func tear() {
        phase = .falling
        phaseTime = 0
        fallVelocity = 120
        recoilTime = 0
        rigidHaptic.impactOccurred()
        UIView.animate(withDuration: 0.25) { self.icon.alpha = 0 }
        let onCommit = onCommit
        DispatchQueue.main.async { onCommit?() }
    }

    override func update(deltaTime: CFTimeInterval) {
        phaseTime += deltaTime
        let dt = CGFloat(deltaTime)
        switch phase {
        case .hanging:
            dropRadius += (radius - dropRadius) * min(1, dt * 10)
            // A slow pendulum sway; in the last quarter the drop starts to tremble.
            let tremble = remaining < 0.25 ? sin(CGFloat(phaseTime) * 55) * (0.25 - remaining) * 8 : 0
            let sway = sin(CGFloat(phaseTime) * 2.2) * 3 + tremble
            drop.step(toward: CGPoint(x: hangPoint.x + sway, y: hangPoint.y + (1 - remaining) * 8), deltaTime: deltaTime)
            if icon.alpha == 0, phaseTime > 0.25 {
                UIView.animate(withDuration: 0.2) { self.icon.alpha = 1 }
            }
            if remaining == 0 {
                tear()
            }
        case .undoing:
            drop.step(toward: CGPoint(x: islandMouth.x, y: islandMouth.y - 2), deltaTime: deltaTime)
            dropRadius += (8 - dropRadius) * min(1, dt * 6)
            if drop.position.distance(to: islandMouth) < 10 {
                phase = .finished
                phaseTime = 0
                recoilTime = 0
                softHaptic.impactOccurred()
                DispatchQueue.main.async { [weak self] in self?.onUndo?() }
            }
        case .falling:
            // Torn off: it drops, shrinks and evaporates.
            fallVelocity += 2200 * dt
            drop.position.y += fallVelocity * dt
            dropRadius = max(0, dropRadius - dt * 32)
            if dropRadius == 0 {
                phase = .finished
                phaseTime = 0
            }
        case .finished:
            if phaseTime > 1 {
                removeFromSuperview()
                isPaused = true
                return
            }
        }
        if let t = recoilTime {
            recoilTime = t > 1 ? nil : t + deltaTime
        }
        rebuildShapes()
        icon.center = drop.position
    }

    private func rebuildShapes() {
        let mouth = islandMouth
        var newShapes: [IslandFluidShape] = []
        var newSpikes: [IslandFluidSpike] = []
        if phase != .finished, dropRadius > 0.5 {
            newShapes.append(.circle(center: drop.position, radius: dropRadius, blend: phase == .undoing ? 16 : 4))
        }
        if phase == .hanging {
            // The neck: two cones pinching in the middle. Its thickness is the countdown.
            let neck = 0.9 + 5.5 * pow(remaining, 1.2)
            let top = CGPoint(x: mouth.x, y: mouth.y - 4)
            let mid = CGPoint(x: (top.x + drop.position.x) / 2, y: (top.y + drop.position.y) / 2)
            newSpikes.append(IslandFluidSpike(base: top, tip: mid, baseRadius: 3 + 5 * remaining, tipRadius: neck, blend: 5))
            newSpikes.append(IslandFluidSpike(base: mid, tip: drop.position, baseRadius: neck,
                                              tipRadius: dropRadius * 0.6, blend: 5))
        }
        if let t = recoilTime {
            newShapes.append(recoilBump(t))
        }
        shapes = newShapes
        spikes = newSpikes
    }
}
