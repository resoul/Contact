//
//  IslandGooeyMenu.swift
//  controller
//
//  A context menu squeezed out of the Dynamic Island: on a long press, bubbles ooze out on an arc,
//  each still tied to the island by a gooey strand. Slide the finger over them — the nearest one
//  swells — and let go to pick it; the others are sucked back in.
//  Feed it the long press with `begin(at:)`, `move(to:)` and `end()`.
//

import UIKit

final class IslandGooeyMenu: IslandFluidView {
    struct Item {
        let symbol: String
        let title: String
        let action: () -> Void
    }

    /// Distance of the bubbles from the island, points.
    var reach: CGFloat = 112
    var bubbleRadius: CGFloat = 21

    private struct Bubble {
        var position: IslandSpring
        var radius: CGFloat = 0
        var radiusVelocity: CGFloat = 0
        let icon: UIImageView
    }

    private let items: [Item]
    private var bubbles: [Bubble] = []
    private var open = false
    private var openTime: CFTimeInterval = 0
    private var finger: CGPoint?
    private var selected: Int?
    private var picked: Int?
    private var recoilTime: CFTimeInterval?
    private let titleLabel = UILabel()
    private let selection = UISelectionFeedbackGenerator()
    private let impact = UIImpactFeedbackGenerator(style: .medium)

    init(items: [Item]) {
        self.items = items
        super.init(frame: .zero)
        gloss = 0.8
        rimWidth = 8
        isPaused = true
        bubbles = items.map { item in
            let icon = UIImageView(image: UIImage(systemName: item.symbol))
            icon.tintColor = .white
            icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
            icon.alpha = 0
            addSubview(icon)
            return Bubble(position: IslandSpring(.zero, stiffness: 15, dampingRatio: 0.45), icon: icon)
        }
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.alpha = 0
        addSubview(titleLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Where bubble `index` rests when the menu is open: an arc fanning down from the island.
    private func restingPoint(_ index: Int) -> CGPoint {
        let count = max(items.count, 1)
        let spread: CGFloat = count == 1 ? 0 : 2.5
        let angle = .pi / 2 + (CGFloat(index) / CGFloat(max(count - 1, 1)) - 0.5) * spread
        return CGPoint(x: islandMouth.x + cos(angle) * reach, y: islandMouth.y + sin(angle) * reach * 0.85)
    }

    // MARK: Public API

    func begin(at point: CGPoint) {
        guard !open else { return }
        open = true
        openTime = 0
        picked = nil
        selected = nil
        finger = point
        for index in bubbles.indices {
            bubbles[index].position = IslandSpring(CGPoint(x: islandMouth.x, y: islandMouth.y - 4),
                                                   stiffness: 15, dampingRatio: 0.45)
            bubbles[index].radius = 4
        }
        impact.impactOccurred(intensity: 0.6)
        selection.prepare()
        isPaused = false
    }

    func move(to point: CGPoint) {
        finger = point
        guard open else { return }
        var nearest: Int?
        var best: CGFloat = 52
        for index in bubbles.indices {
            let distance = point.distance(to: bubbles[index].position.position)
            if distance < best {
                best = distance
                nearest = index
            }
        }
        if nearest != selected {
            selected = nearest
            if nearest != nil {
                selection.selectionChanged()
            }
            titleLabel.text = nearest.map { items[$0].title }
        }
    }

    /// Lets go: runs the selected item, if any, and sucks the bubbles back in.
    func end() {
        guard open else { return }
        open = false
        openTime = 0
        finger = nil
        if let selected {
            picked = selected
            bubbles[selected].radiusVelocity += 260   // the chosen one pops
            impact.impactOccurred()
            let action = items[selected].action
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { action() }
        }
        selected = nil
    }

    // MARK: Simulation

    override func update(deltaTime: CFTimeInterval) {
        openTime += deltaTime
        let dt = CGFloat(deltaTime)
        let mouth = islandMouth
        var allHome = true
        for index in bubbles.indices {
            var bubble = bubbles[index]
            // Staggered: they ooze out one after another.
            let started = openTime > Double(index) * 0.035
            let target: CGPoint
            let targetRadius: CGFloat
            if open, started {
                var rest = restingPoint(index)
                // The selected bubble leans toward the finger a little.
                if index == selected, let finger {
                    rest = CGPoint(x: rest.x + (finger.x - rest.x) * 0.25, y: rest.y + (finger.y - rest.y) * 0.25)
                }
                target = rest
                targetRadius = index == selected ? bubbleRadius * 1.3 : bubbleRadius
            } else if open {
                target = CGPoint(x: mouth.x, y: mouth.y - 4)
                targetRadius = 4
            } else {
                target = CGPoint(x: mouth.x, y: mouth.y - 6)
                targetRadius = index == picked && openTime < 0.15 ? bubbleRadius * 1.6 : 3
            }
            bubble.position.step(toward: target, deltaTime: deltaTime)
            bubble.radiusVelocity += (520 * (targetRadius - bubble.radius) - 26 * bubble.radiusVelocity) * dt
            bubble.radius = max(0, bubble.radius + bubble.radiusVelocity * dt)
            bubble.icon.center = bubble.position.position
            bubble.icon.alpha = open ? islandSmoothstep(bubbleRadius * 0.6, bubbleRadius * 0.9, bubble.radius) : 0
            if bubble.position.position.distance(to: mouth) > 8 || bubble.position.speed > 20 {
                allHome = false
            }
            bubbles[index] = bubble
        }

        if let selected, open {
            titleLabel.sizeToFit()
            let point = bubbles[selected].position.position
            titleLabel.center = CGPoint(x: point.x, y: point.y + bubbleRadius * 1.3 + 18)
            titleLabel.alpha = 1
        } else {
            titleLabel.alpha = 0
        }

        if !open, allHome, recoilTime == nil, openTime > 0.2 {
            recoilTime = 0
        }
        if let t = recoilTime {
            recoilTime = t > 1 ? nil : t + deltaTime
        }
        rebuildShapes()
        if !open, allHome, recoilTime == nil, openTime > 0.3 {
            settle()
        }
    }

    private func rebuildShapes() {
        let mouth = islandMouth
        var newShapes: [IslandFluidShape] = []
        var newSpikes: [IslandFluidSpike] = []
        let anyOut = bubbles.contains { $0.position.position.distance(to: mouth) > 10 }
        if anyOut {
            newShapes.append(.circle(center: CGPoint(x: mouth.x, y: mouth.y - 2), radius: 11, blend: 10))
        }
        for bubble in bubbles where bubble.radius > 0.5 {
            let center = bubble.position.position
            newShapes.append(.circle(center: center, radius: bubble.radius, blend: 6))
            // A gooey strand back to the island, thinner the farther the bubble is.
            let distance = center.distance(to: mouth)
            if distance > 14 {
                let thickness = max(1.2, 4.5 - distance / 40)
                newSpikes.append(IslandFluidSpike(base: CGPoint(x: mouth.x, y: mouth.y - 3), tip: center,
                                                  baseRadius: thickness + 2, tipRadius: thickness, blend: 5))
            }
        }
        if let t = recoilTime {
            newShapes.append(recoilBump(t, amplitude: 9))
        }
        shapes = newShapes
        spikes = newSpikes
    }
}
