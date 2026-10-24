//
//  IslandScrollJelly.swift
//  controller
//
//  The Dynamic Island reacts to a scroll view like jelly: it widens a little while content flies
//  past, a drip bulges out of it when the content is pulled down past the top, and it wobbles when
//  a fling slams into the top. `pulse()` (for a status-bar tap) shoots out a drop that tugs the
//  content up and springs back. It only ever grows: the real island can't shrink.
//

import UIKit

final class IslandScrollJelly: IslandFluidView {
    private weak var scrollView: UIScrollView?
    private var observation: NSKeyValueObservation?
    /// Extra half width / extra height of the island, sprung so it wobbles.
    private var deform = IslandSpring(.zero, stiffness: 13, dampingRatio: 0.32)
    private var drop: IslandSpring?
    private var lastOffset: CGFloat?
    private var velocity: CGFloat = 0
    private var pull: CGFloat = 0
    private var recoilTime: CFTimeInterval?
    private let haptic = UIImpactFeedbackGenerator(style: .soft)

    override init(frame: CGRect) {
        super.init(frame: frame)
        gloss = 0.6
        isPaused = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func attach(to scrollView: UIScrollView) {
        detach()
        guard let window = scrollView.window else { return }
        self.scrollView = scrollView
        install(in: window)
        observation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.isPaused = false }
        }
    }

    func detach() {
        observation = nil
        scrollView = nil
        removeFromSuperview()
    }

    /// A drop shoots out of the island and springs back, as if tugging the content to the top.
    func pulse() {
        var spring = IslandSpring(CGPoint(x: islandMouth.x, y: islandMouth.y - 4), stiffness: 9, dampingRatio: 0.42)
        spring.velocity = CGVector(dx: 0, dy: 1100)
        drop = spring
        haptic.impactOccurred(intensity: 0.7)
        isPaused = false
    }

    override func update(deltaTime: CFTimeInterval) {
        guard let scrollView else { return }
        let offset = scrollView.contentOffset.y
        let top = -scrollView.adjustedContentInset.top
        let newPull = max(0, top - offset)
        if let lastOffset, deltaTime > 0 {
            let newVelocity = CGFloat((offset - lastOffset) / deltaTime)
            // A fast fling up that just hit the top: the island takes the blow.
            if velocity < -1400, offset <= top + 1, lastOffset > top + 1 {
                deform.velocity.dx += min(-velocity / 30, 90)
                deform.velocity.dy += min(-velocity / 14, 220)
                haptic.impactOccurred(intensity: min(1, -velocity / 5000))
            }
            velocity = velocity * 0.6 + newVelocity * 0.4
        }
        lastOffset = offset
        pull = newPull

        let speed = min(abs(velocity) / 9000, 1)
        deform.step(toward: CGPoint(x: speed * 9, y: speed * 3 + min(pull * 0.16, 26)), deltaTime: deltaTime)

        if var spring = drop {
            spring.step(toward: CGPoint(x: islandMouth.x, y: islandMouth.y - 4), deltaTime: deltaTime)
            drop = spring
            if spring.speed < 30, spring.position.distance(to: islandMouth) < 6 {
                drop = nil
                recoilTime = 0
            }
        }
        if let t = recoilTime {
            recoilTime = t > 1 ? nil : t + deltaTime
        }
        rebuildShapes()

        let still = abs(velocity) < 5 && pull == 0 && deform.speed < 0.5
            && abs(deform.position.x) < 0.2 && abs(deform.position.y) < 0.2
        if still, drop == nil, recoilTime == nil {
            settle()
        }
    }

    private func rebuildShapes() {
        var newShapes: [IslandFluidShape] = []
        let grow = CGPoint(x: max(deform.position.x, 0), y: max(deform.position.y, 0))
        if grow.x > 0.1 || grow.y > 0.1 {
            let half = CGSize(width: island.width / 2 + grow.x, height: island.height / 2 + grow.y * 0.25)
            newShapes.append(IslandFluidShape(center: CGPoint(x: island.midX, y: island.minY + half.height),
                                              halfSize: half, cornerRadius: half.height, blend: 0))
        }
        if pull > 2 || grow.y > 4 {
            // The drip: a bulge hanging from the middle, longer the further the content is pulled.
            let depth = max(grow.y, 0)
            newShapes.append(.circle(center: CGPoint(x: islandMouth.x, y: islandMouth.y - 6 + depth * 0.75),
                                     radius: 6 + depth * 0.18, blend: 12))
        }
        if let drop {
            newShapes.append(.circle(center: drop.position, radius: 9, blend: 14))
        }
        if let t = recoilTime {
            newShapes.append(recoilBump(t, amplitude: 9))
        }
        shapes = newShapes
    }
}
