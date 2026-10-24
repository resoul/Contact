//
//  IslandBeadStack.swift
//  controller
//
//  Grouped notifications as beads on a string hanging from the Dynamic Island: every new one drips
//  out on top and pushes the others down; the string sways. Tap it and the beads swell into a list of
//  liquid toasts; tap or flick up to string them back. `clear()` sucks them in one by one.
//

import UIKit

final class IslandBeadStack: IslandFluidView {
    private struct Bead {
        var position: IslandSpring
        var size: IslandSpring
        let content: UIView
        var leaving = false
        var leaveAt: CFTimeInterval = 0
    }

    /// Beads shown on the string; older ones hide behind the last.
    var maxVisibleBeads = 6

    private var beads: [Bead] = []
    private var expanded = false
    private var clock: CFTimeInterval = 0
    private var recoilTime: CFTimeInterval?
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    private let softHaptic = UIImpactFeedbackGenerator(style: .soft)

    private let pillHeight: CGFloat = 60
    private let pillGap: CGFloat = 8

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true
        gloss = 0.55
        rimWidth = 8
        isPaused = true
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggle)))
        let swipe = UISwipeGestureRecognizer(target: self, action: #selector(collapse))
        swipe.direction = .up
        addGestureRecognizer(swipe)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var count: Int {
        beads.filter { !$0.leaving }.count
    }

    private var pillWidth: CGFloat {
        min(bounds.width - 24, 360)
    }

    // MARK: Public API

    func push(title: String, message: String, symbol: String) {
        let content = makeContent(title: title, message: message, symbol: symbol)
        addSubview(content)
        let start = CGPoint(x: islandMouth.x, y: islandMouth.y - 4)
        let bead = Bead(position: IslandSpring(start, stiffness: 14, dampingRatio: 0.4),
                        size: IslandSpring(CGPoint(x: 3, y: 3), stiffness: 16, dampingRatio: 0.45),
                        content: content)
        beads.insert(bead, at: 0)
        // The string jolts as the new bead drips in.
        for index in beads.indices.dropFirst() {
            beads[index].position.velocity.dy += 60
        }
        lightHaptic.impactOccurred(intensity: 0.7)
        isPaused = false
    }

    /// Sucks every bead back into the island, newest first.
    func clear() {
        expanded = false
        var order: CFTimeInterval = 0
        for index in beads.indices where !beads[index].leaving {
            beads[index].leaving = true
            beads[index].leaveAt = clock + order
            order += 0.09
        }
        softHaptic.prepare()
        isPaused = false
    }

    /// Swells the beads into a list of toasts, or strings them back.
    @objc func toggle() {
        guard count > 0 else { return }
        expanded.toggle()
        lightHaptic.impactOccurred()
        isPaused = false
    }

    @objc private func collapse() {
        guard expanded else { return }
        expanded = false
        isPaused = false
    }

    private func makeContent(title: String, message: String, symbol: String) -> UIView {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .white
        let messageLabel = UILabel()
        messageLabel.text = message
        messageLabel.font = .systemFont(ofSize: 13)
        messageLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        let texts = UIStackView(arrangedSubviews: [titleLabel, messageLabel])
        texts.axis = .vertical
        texts.spacing = 1
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = .white
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [icon, texts])
        row.spacing = 12
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        let content = UIView(frame: CGRect(x: 0, y: 0, width: max(pillWidth, 240), height: pillHeight))
        content.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            row.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -24),
            row.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        content.alpha = 0
        content.isUserInteractionEnabled = false
        return content
    }

    // MARK: Touches

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let live = beads.filter { !$0.leaving }
        guard let first = live.first else { return false }
        var rect = CGRect(origin: first.position.position, size: .zero)
        for bead in live {
            let p = bead.position.position, s = bead.size.position
            rect = rect.union(CGRect(x: p.x - s.x, y: p.y - s.y, width: s.x * 2, height: s.y * 2))
        }
        return rect.insetBy(dx: expanded ? -4 : -18, dy: expanded ? -4 : -10).contains(point)
    }

    // MARK: Simulation

    override func update(deltaTime: CFTimeInterval) {
        clock += deltaTime
        let mouth = islandMouth
        let full = CGPoint(x: pillWidth / 2, y: pillHeight / 2)
        var slot = 0
        var moving = false

        for index in beads.indices.reversed() where beads[index].leaving && clock >= beads[index].leaveAt {
            let bead = beads[index]
            if bead.position.position.distance(to: mouth) < 8, bead.size.position.x < 6 {
                bead.content.removeFromSuperview()
                beads.remove(at: index)
                recoilTime = 0
                softHaptic.impactOccurred(intensity: 0.5)
            }
        }

        for index in beads.indices {
            var bead = beads[index]
            var target: CGPoint
            var sizeTarget: CGPoint
            if bead.leaving && clock >= bead.leaveAt {
                target = CGPoint(x: mouth.x, y: mouth.y - 3)
                sizeTarget = CGPoint(x: 3, y: 3)
            } else if expanded {
                target = CGPoint(x: mouth.x, y: mouth.y + 14 + full.y + CGFloat(slot) * (pillHeight + pillGap))
                sizeTarget = full
                slot += 1
            } else {
                let visibleSlot = CGFloat(min(slot, maxVisibleBeads - 1))
                // A gentle sway that grows down the string, like a pendulum chain.
                let sway = sin(CGFloat(clock) * 1.7 + visibleSlot * 0.5) * visibleSlot * 1.3
                target = CGPoint(x: mouth.x + sway, y: mouth.y + 16 + visibleSlot * 21)
                let radius: CGFloat = slot == 0 ? 9.5 : 8
                sizeTarget = CGPoint(x: radius, y: radius)
                slot += 1
            }
            bead.position.step(toward: target, deltaTime: deltaTime)
            bead.size.step(toward: sizeTarget, deltaTime: deltaTime)
            if bead.position.speed > 2 || bead.size.speed > 2 {
                moving = true
            }

            let showText = expanded && !bead.leaving && bead.size.position.x > full.x * 0.85
            if showText != (bead.content.alpha > 0.5) {
                let content = bead.content
                UIView.animate(withDuration: showText ? 0.18 : 0.08) { content.alpha = showText ? 1 : 0 }
            }
            bead.content.center = bead.position.position
            bead.content.transform = CGAffineTransform(scaleX: max(bead.size.position.x / full.x, 0.01),
                                                       y: max(bead.size.position.y / full.y, 0.01))
            beads[index] = bead
        }

        if let t = recoilTime {
            recoilTime = t > 1 ? nil : t + deltaTime
        }
        rebuildShapes()
        // Collapsed beads keep swaying while there are any; otherwise sleep once still.
        if beads.isEmpty, recoilTime == nil {
            settle()
        } else if expanded, !moving, recoilTime == nil {
            renderFrame()
            isPaused = true
        }
    }

    private func rebuildShapes() {
        let mouth = islandMouth
        var newShapes: [IslandFluidShape] = []
        var newSpikes: [IslandFluidSpike] = []
        var previous: CGPoint?
        for (index, bead) in beads.enumerated() {
            let center = bead.position.position
            let half = bead.size.position
            let blend: CGFloat = index == 0 ? (expanded ? 10 : 6) : 5
            newShapes.append(IslandFluidShape(center: center, halfSize: CGSize(width: max(half.x, 0.5), height: max(half.y, 0.5)),
                                              cornerRadius: min(half.x, half.y), blend: blend))
            // The string: a thin strand from the island to the first bead and between beads.
            if !expanded, !bead.leaving, index < maxVisibleBeads {
                let from = previous ?? CGPoint(x: mouth.x, y: mouth.y - 3)
                newSpikes.append(IslandFluidSpike(base: from, tip: center, baseRadius: previous == nil ? 3.2 : 2,
                                                  tipRadius: 1.8, blend: 3))
                previous = center
            }
        }
        if let t = recoilTime {
            newShapes.append(recoilBump(t, amplitude: 7))
        }
        shapes = newShapes
        spikes = newSpikes
    }
}
