//
//  IslandCoachMarks.swift
//  controller
//
//  Onboarding hints on a liquid thread: a drop leaves the Dynamic Island and crawls to each control
//  in turn, trailing a thin rope (Verlet physics, pinned to the island and to the drop). At the
//  control the drop swells into a bubble with the hint. Tap anywhere for the next step; after the
//  last one the drop is reeled back in.
//

import UIKit

final class IslandCoachMarks: IslandFluidView {
    struct Step {
        weak var target: UIView?
        let text: String
    }

    var onFinish: (() -> Void)?

    private enum Phase {
        case travelling
        case showing
        case closing
        case returning
        case finished
    }

    private let ropeSegments = 18
    private let bubbleWidth: CGFloat = 250

    private var steps: [Step] = []
    private var index = 0
    private var phase = Phase.travelling
    private var phaseTime: CFTimeInterval = 0
    private var drop = IslandSpring(.zero, stiffness: 9, dampingRatio: 0.72)
    private var bubbleSize = IslandSpring(CGPoint(x: 7, y: 7), stiffness: 16, dampingRatio: 0.5)
    private var rope: [CGPoint] = []
    private var ropePrevious: [CGPoint] = []
    private var recoilTime: CFTimeInterval?
    private let label = UILabel()
    private let bubbleContent = UIView()
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true
        gloss = 0.6
        rimWidth = 8
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        bubbleContent.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: bubbleContent.leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: bubbleContent.trailingAnchor, constant: -18),
            label.centerYAnchor.constraint(equalTo: bubbleContent.centerYAnchor),
        ])
        bubbleContent.alpha = 0
        bubbleContent.isUserInteractionEnabled = false
        addSubview(bubbleContent)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(advance)))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Starts the tour over the window of the first target.
    func start(_ steps: [Step], in window: UIWindow) {
        self.steps = steps
        install(in: window)
        index = 0
        phase = .travelling
        phaseTime = 0
        drop = IslandSpring(CGPoint(x: islandMouth.x, y: islandMouth.y - 2), stiffness: 9, dampingRatio: 0.72)
        rope = (0...ropeSegments).map { _ in drop.position }
        ropePrevious = rope
        prepareBubble()
        haptic.impactOccurred()
        isPaused = false
    }

    // MARK: Layout

    private var targetFrame: CGRect {
        guard index < steps.count, let target = steps[index].target else { return .zero }
        return target.convert(target.bounds, to: self)
    }

    private var bubbleHeight: CGFloat {
        let size = label.sizeThatFits(CGSize(width: bubbleWidth - 36, height: .greatestFiniteMagnitude))
        return max(48, size.height + 26)
    }

    /// Below the target when there is room, otherwise above; kept on screen.
    private var bubbleFrame: CGRect {
        let target = targetFrame
        let height = bubbleHeight
        let below = target.maxY + 16 + height < bounds.height - 40
        let y = below ? target.maxY + 16 : target.minY - 16 - height
        let x = min(max(target.midX - bubbleWidth / 2, 16), bounds.width - 16 - bubbleWidth)
        return CGRect(x: x, y: y, width: bubbleWidth, height: height)
    }

    /// Where the thread ties onto the bubble: the edge facing the island.
    private var anchor: CGPoint {
        let bubble = bubbleFrame
        return CGPoint(x: bubble.midX, y: bubble.minY + 7)
    }

    private func prepareBubble() {
        guard index < steps.count else { return }
        label.text = steps[index].text
        bubbleContent.bounds = CGRect(x: 0, y: 0, width: bubbleWidth, height: bubbleHeight)
    }

    // MARK: Touches

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        phase != .finished   // the tour is modal: any tap moves it on
    }

    /// Closes the current hint and moves on to the next step.
    @objc func advance() {
        guard phase == .showing || phase == .travelling else { return }
        phase = .closing
        phaseTime = 0
        haptic.impactOccurred(intensity: 0.6)
        UIView.animate(withDuration: 0.1) { self.bubbleContent.alpha = 0 }
    }

    // MARK: Simulation

    override func update(deltaTime: CFTimeInterval) {
        phaseTime += deltaTime
        let mouth = islandMouth
        let bubble = bubbleFrame
        switch phase {
        case .travelling:
            drop.step(toward: anchor, deltaTime: deltaTime)
            bubbleSize.step(toward: CGPoint(x: 7, y: 7), deltaTime: deltaTime)
            if drop.position.distance(to: anchor) < 4, drop.speed < 60 {
                phase = .showing
                phaseTime = 0
                haptic.impactOccurred(intensity: 0.5)
            }
        case .showing:
            drop.step(toward: anchor, deltaTime: deltaTime)
            bubbleSize.step(toward: CGPoint(x: bubble.width / 2, y: bubble.height / 2), deltaTime: deltaTime)
            if bubbleSize.position.x > bubble.width * 0.42, bubbleContent.alpha == 0 {
                UIView.animate(withDuration: 0.18) { self.bubbleContent.alpha = 1 }
            }
        case .closing:
            bubbleSize.step(toward: CGPoint(x: 7, y: 7), deltaTime: deltaTime)
            if bubbleSize.position.x < 12 {
                index += 1
                phaseTime = 0
                if index < steps.count {
                    prepareBubble()
                    phase = .travelling
                } else {
                    phase = .returning
                    drop.stiffness = 12
                }
            }
        case .returning:
            drop.step(toward: CGPoint(x: mouth.x, y: mouth.y - 2), deltaTime: deltaTime)
            if drop.position.distance(to: mouth) < 8 {
                phase = .finished
                phaseTime = 0
                recoilTime = 0
                haptic.impactOccurred()
            }
        case .finished:
            if phaseTime > 1 {
                removeFromSuperview()
                isPaused = true
                let onFinish = onFinish
                DispatchQueue.main.async { onFinish?() }
                return
            }
        }
        if let t = recoilTime {
            recoilTime = t > 1 ? nil : t + deltaTime
        }
        simulateRope(deltaTime: deltaTime)
        rebuildShapes(bubble: bubble)
    }

    /// Verlet rope pinned at the island and the drop, a little longer than the gap so it sags.
    private func simulateRope(deltaTime: CFTimeInterval) {
        guard rope.count == ropeSegments + 1 else { return }
        let start = CGPoint(x: islandMouth.x, y: islandMouth.y - 3)
        let end = drop.position
        let dt = CGFloat(min(deltaTime, 1.0 / 60))
        let gravity: CGFloat = 900
        for i in 1..<ropeSegments {
            let p = rope[i], prev = ropePrevious[i]
            let velocity = CGPoint(x: (p.x - prev.x) * 0.985, y: (p.y - prev.y) * 0.985)
            ropePrevious[i] = p
            rope[i] = CGPoint(x: p.x + velocity.x, y: p.y + velocity.y + gravity * dt * dt)
        }
        let length = max(start.distance(to: end) * 1.07, 6) / CGFloat(ropeSegments)
        for _ in 0..<14 {
            rope[0] = start
            rope[ropeSegments] = end
            for i in 0..<ropeSegments {
                let a = rope[i], b = rope[i + 1]
                let distance = max(a.distance(to: b), 1e-3)
                let correction = (distance - length) / distance * 0.5
                let delta = CGPoint(x: (b.x - a.x) * correction, y: (b.y - a.y) * correction)
                if i != 0 {
                    rope[i] = CGPoint(x: a.x + delta.x, y: a.y + delta.y)
                }
                if i + 1 != ropeSegments {
                    rope[i + 1] = CGPoint(x: b.x - delta.x, y: b.y - delta.y)
                }
            }
        }
        rope[0] = start
        rope[ropeSegments] = end
    }

    private func rebuildShapes(bubble: CGRect) {
        var newShapes: [IslandFluidShape] = []
        var newSpikes: [IslandFluidSpike] = []
        if phase != .finished {
            newShapes.append(.circle(center: drop.position, radius: 7, blend: 4))
            let half = bubbleSize.position
            if half.x > 7.5 {
                // The bubble grows out of the drop, downward from where the thread ties on.
                let center = CGPoint(x: bubble.midX, y: drop.position.y - 7 + half.y)
                let x = drop.position.x + (center.x - drop.position.x) * islandSmoothstep(7, bubble.width / 2, half.x)
                newShapes.append(IslandFluidShape(center: CGPoint(x: x, y: center.y),
                                                  halfSize: CGSize(width: half.x, height: half.y),
                                                  cornerRadius: min(20, min(half.x, half.y)), blend: 6))
                bubbleContent.center = CGPoint(x: x, y: center.y)
                bubbleContent.transform = CGAffineTransform(scaleX: max(half.x / (bubble.width / 2), 0.01),
                                                            y: max(half.y / (bubble.height / 2), 0.01))
            }
            for i in 0..<min(ropeSegments, rope.count - 1) {
                let t = CGFloat(i) / CGFloat(ropeSegments)
                newSpikes.append(IslandFluidSpike(base: rope[i], tip: rope[i + 1], baseRadius: 2.4 - t * 0.9,
                                                  tipRadius: 2.4 - (t + 1 / CGFloat(ropeSegments)) * 0.9, blend: 1.5))
            }
        }
        if let t = recoilTime {
            newShapes.append(recoilBump(t, amplitude: 8))
        }
        shapes = newShapes
        spikes = newSpikes
    }
}
