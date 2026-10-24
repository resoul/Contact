//
//  LiquidAvatarStack.swift
//  controller
//
//  The commenters' avatars as drops of one liquid (LiquidCanvasView behind the images): each sits in
//  a liquid disc, and neighbours are joined by gooey necks. Tap and the stack spreads out to show
//  one more person — the necks stretch thin but hold; tap again and they flow back together.
//  `drop(_:)` lets a new commenter fall in from above: it splats, squashes, and shoulders the
//  others aside, and the last one shrinks away.
//

import UIKit

final class LiquidAvatarStack: UIView {
    private struct Slot {
        let person: ChannelPerson
        let image: UIImageView
        var position: IslandSpring
        var scale: Spring1D
        var leaving = false
    }

    private(set) var people: [ChannelPerson]
    private(set) var expanded = false
    var ringColor = UIColor(red: 0.25, green: 0.23, blue: 0.31, alpha: 1)

    private let canvas = LiquidCanvasView()
    private var slots: [Slot] = []
    private let size: CGFloat = 26
    private let room: CGFloat = 30

    init(people: [ChannelPerson]) {
        self.people = people
        super.init(frame: .zero)
        clipsToBounds = false
        canvas.liquidColor = ringColor
        canvas.gloss = 0.3
        canvas.rimWidth = 5
        canvas.onUpdate = { [weak self] dt in self?.step(dt) }
        addSubview(canvas)
        for (index, person) in people.prefix(visibleCount).enumerated() {
            slots.append(makeSlot(person, at: restingPoint(index)))
        }
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggle)))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var visibleCount: Int { min(people.count, expanded ? 4 : 3) }
    private var spacing: CGFloat { expanded ? 30 : 18 }

    private func restingPoint(_ index: Int) -> CGPoint {
        CGPoint(x: size / 2 + 2 + CGFloat(index) * spacing, y: bounds.height > 0 ? bounds.midY : 18)
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: size + 4 + CGFloat(max(visibleCount - 1, 0)) * spacing, height: 36)
    }

    private func makeSlot(_ person: ChannelPerson, at point: CGPoint) -> Slot {
        let image = UIImageView(image: ChannelAvatar.image(for: person, size: size))
        image.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        image.center = point
        // Earlier commenters sit on top, like the overlapping stack in Telegram.
        if let last = slots.last?.image {
            insertSubview(image, belowSubview: last)
        } else {
            addSubview(image)
        }
        return Slot(person: person, image: image, position: IslandSpring(point, stiffness: 13, dampingRatio: 0.5),
                    scale: Spring1D(1, stiffness: 14, dampingRatio: 0.45))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        canvas.frame = bounds.insetBy(dx: -room, dy: -room)
        for index in slots.indices where !slots[index].leaving {
            let rest = restingPoint(index)
            if slots[index].position.speed < 1, abs(slots[index].position.position.y - rest.y) > 1 {
                slots[index].position.position = rest
            }
        }
        wake()
    }

    private func wake() {
        canvas.isPaused = false
    }

    @objc func toggle() {
        expanded.toggle()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        // Show more people when spread, fewer when gathered back.
        let wanted = visibleCount
        if slots.count < wanted || slots.contains(where: \.leaving) {
            for index in slots.indices {
                slots[index].leaving = index >= wanted
            }
            while slots.count < wanted {
                var slot = makeSlot(people[slots.count], at: restingPoint(max(slots.count - 1, 0)))
                slot.scale.value = 0.2
                slots.append(slot)
            }
        } else if slots.count > wanted {
            for index in wanted..<slots.count {
                slots[index].leaving = true
            }
        }
        invalidateIntrinsicContentSize()
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.2) {
            self.superview?.layoutIfNeeded()
        }
        wake()
    }

    /// A new commenter falls in at the front and pushes the others along.
    func drop(_ person: ChannelPerson) {
        people.insert(person, at: 0)
        let start = CGPoint(x: restingPoint(0).x, y: restingPoint(0).y - 46)
        var slot = makeSlot(person, at: start)
        slot.position = IslandSpring(start, stiffness: 11, dampingRatio: 0.42)
        slot.position.velocity = CGVector(dx: 0, dy: 260)
        bringSubviewToFront(slot.image)
        slots.insert(slot, at: 0)
        if slots.filter({ !$0.leaving }).count > visibleCount, let last = slots.lastIndex(where: { !$0.leaving }) {
            slots[last].leaving = true
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7)
        wake()
    }

    private func step(_ dt: CFTimeInterval) {
        var shapes: [IslandFluidShape] = []
        var settled = true
        var index = 0
        for i in slots.indices {
            var slot = slots[i]
            let target = slot.leaving ? restingPoint(max(index - 1, 0)) : restingPoint(index)
            slot.position.step(toward: target, deltaTime: dt)
            slot.scale.step(toward: slot.leaving ? 0 : 1, deltaTime: dt)
            if !slot.leaving {
                index += 1
            }
            // Squash on impact: wide and flat while moving down fast, tall while bouncing up.
            let squash = max(-0.25, min(0.25, slot.position.velocity.dy / 1400))
            let s = max(slot.scale.value, 0)
            slot.image.center = slot.position.position
            slot.image.transform = CGAffineTransform(scaleX: s * (1 + squash), y: s * (1 - squash))
            let r = (size / 2 + 2.5) * s
            if r > 0.5 {
                let center = CGPoint(x: slot.position.position.x + room, y: slot.position.position.y + room)
                shapes.append(IslandFluidShape(center: center, halfSize: CGSize(width: r * (1 + squash), height: r * (1 - squash)),
                                               cornerRadius: r, blend: 9))
            }
            if slot.position.speed > 2 || abs(slot.position.position.x - target.x) > 0.3
                || abs(slot.position.position.y - target.y) > 0.3 || !slot.scale.isSettled(at: slot.leaving ? 0 : 1, tolerance: 0.01) {
                settled = false
            }
            slots[i] = slot
        }
        // Gone ones leave once they have shrunk away.
        slots.removeAll { slot in
            if slot.leaving, slot.scale.value < 0.03 {
                slot.image.removeFromSuperview()
                return true
            }
            return false
        }
        canvas.shapes = shapes
        canvas.spikes = []
        if settled {
            canvas.renderFrame()
            canvas.isPaused = true
        }
    }
}
