//
//  BubbleClusterView.swift
//  controller
//
//  People as drops of one liquid (LiquidCanvasView): each avatar sits in a dark liquid ring, and
//  rings that come close grow gooey necks between them. The drops float on soft springs, push each
//  other apart, drift with the phone's tilt and can be dragged — the neighbours follow on their
//  necks. Little "talk" bubbles hop between people. Switch to orbits and the cluster comes apart into
//  rings around a centre, each ring turning at its own pace with tilt parallax, tags floating by.
//  Also here: LiquidMorphPanel (a drop that spreads into a card) and CallTile (a jelly PiP tile).
//

import UIKit

final class BubbleClusterView: UIView, UIGestureRecognizerDelegate {
    struct Member {
        let person: ChannelPerson
        let radius: CGFloat
        let home: CGPoint      // cluster layout, relative to the centre
        let tag: String?
    }

    private struct Bubble {
        let member: Member
        let image: UIImageView
        var position: CGPoint
        var velocity: CGVector = .zero
        let ring: Int
        let angle: CGFloat
    }

    private struct Talk {
        let view: UILabel
        var host: Int
        var angle: CGFloat
        var spring: IslandSpring
        var nextHop: CFTimeInterval
    }

    var onOpen: ((Int, CGRect) -> Void)?
    private(set) var orbitMode = false

    private let canvas = LiquidCanvasView()
    private var bubbles: [Bubble] = []
    private var talks: [Talk] = []
    private var tags: [UILabel?] = []
    private let rings = (0..<3).map { _ in CAShapeLayer() }
    private var mode = Spring1D(0, stiffness: 5, dampingRatio: 0.9)
    private var clock: CFTimeInterval = 0
    private var dragIndex: Int?
    private var dragPoint = CGPoint.zero
    private let ringRadii: [CGFloat] = [100, 158, 212]
    private let ringSpeeds: [CGFloat] = [0.2, -0.13, 0.08]
    /// Orbits: the biggest person stays in the middle, the rest share the two inner rings.
    private let orbitPlan: [(ring: Int, angle: CGFloat)] = [(0, 0), (0, 2.09), (1, 1.05), (-1, 0), (1, 3.14), (0, 4.19), (1, 5.24)]

    init(members: [Member]) {
        super.init(frame: .zero)
        for ring in rings {
            ring.fillColor = UIColor.clear.cgColor
            ring.strokeColor = UIColor(white: 1, alpha: 0.07).cgColor
            ring.lineWidth = 1
            ring.opacity = 0
            layer.addSublayer(ring)
        }
        canvas.liquidColor = UIColor(red: 0.07, green: 0.2, blue: 0.23, alpha: 1)
        canvas.gloss = 0.35
        canvas.rimWidth = 10
        canvas.onUpdate = { [weak self] dt in self?.step(dt) }
        addSubview(canvas)
        for (index, member) in members.enumerated() {
            let image = UIImageView(image: ChannelAvatar.image(for: member.person, size: member.radius * 2))
            image.layer.cornerRadius = member.radius
            image.clipsToBounds = true
            addSubview(image)
            let plan = orbitPlan[index % orbitPlan.count]
            bubbles.append(Bubble(member: member, image: image, position: .zero, ring: plan.ring, angle: plan.angle))
            if let tag = member.tag {
                let label = UILabel()
                label.text = "  \(tag)  "
                label.font = .systemFont(ofSize: 12, weight: .medium)
                label.textColor = .white
                label.backgroundColor = UIColor(white: 1, alpha: 0.12)
                label.layer.cornerRadius = 12
                label.clipsToBounds = true
                label.sizeToFit()
                label.bounds.size.height = 24
                label.alpha = 0
                addSubview(label)
                tags.append(label)
            } else {
                tags.append(nil)
            }
        }
        for (index, size) in [CGFloat(30), 24, 40].enumerated() {
            let talk = UILabel()
            talk.text = "talk"
            talk.font = .systemFont(ofSize: size * 0.3, weight: .heavy)
            talk.textColor = .white
            talk.textAlignment = .center
            talk.backgroundColor = RoomPalette.cyan
            talk.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            talk.layer.cornerRadius = size / 2
            talk.clipsToBounds = true
            addSubview(talk)
            talks.append(Talk(view: talk, host: index * 2 % members.count, angle: CGFloat(index) * 2.1,
                              spring: IslandSpring(.zero, stiffness: 7, dampingRatio: 0.7), nextHop: 2 + Double(index)))
        }
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.delegate = self
        addGestureRecognizer(pan)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var centre: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }

    override func layoutSubviews() {
        super.layoutSubviews()
        canvas.frame = bounds
        for (index, ring) in rings.enumerated() {
            let r = ringRadii[index]
            ring.path = UIBezierPath(ovalIn: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2)).cgPath
        }
        for index in bubbles.indices where bubbles[index].position == .zero {
            bubbles[index].position = home(index)
        }
        for index in talks.indices where talks[index].spring.position == .zero {
            talks[index].spring.position = talkTarget(index)
        }
    }

    func setOrbits(_ on: Bool) {
        orbitMode = on
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    // MARK: Layout targets

    private func home(_ index: Int) -> CGPoint {
        let bubble = bubbles[index]
        let cluster = CGPoint(x: centre.x + bubble.member.home.x, y: centre.y + bubble.member.home.y)
        guard bubble.ring >= 0 else {
            return CGPoint.lerp(cluster, centre, min(max(mode.value, 0), 1))
        }
        let r = ringRadii[bubble.ring]
        let angle = bubble.angle + CGFloat(clock) * ringSpeeds[bubble.ring]
        // Outer rings drift further with the tilt: parallax.
        let g = LiquidUIMotion.shared.gravity
        let depth = CGFloat(bubble.ring + 1) * 9
        let orbit = CGPoint(x: centre.x + cos(angle) * r + g.x * depth, y: centre.y + sin(angle) * r * 0.92 + (g.y - 0.85) * depth)
        let m = min(max(mode.value, 0), 1)
        return CGPoint.lerp(cluster, orbit, m)
    }

    /// Smaller on the orbits, so the rings have room.
    private func radius(_ index: Int) -> CGFloat {
        bubbles[index].member.radius * (1 - 0.28 * min(max(mode.value, 0), 1))
    }

    private func talkTarget(_ index: Int) -> CGPoint {
        let talk = talks[index]
        let host = bubbles[talk.host]
        let distance = host.member.radius + 26
        return CGPoint(x: host.position.x + cos(talk.angle) * distance, y: host.position.y + sin(talk.angle) * distance)
    }

    // MARK: Gestures

    private func bubble(at point: CGPoint) -> Int? {
        bubbles.indices.last { bubbles[$0].position.distance(to: point) < bubbles[$0].member.radius + 6 }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer is UIPanGestureRecognizer else { return true }
        return bubble(at: gestureRecognizer.location(in: self)) != nil
    }

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: self)
        switch gesture.state {
        case .began:
            dragIndex = bubble(at: point)
            dragPoint = point
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .changed:
            dragPoint = point
        default:
            if let index = dragIndex {
                let v = gesture.velocity(in: self)
                bubbles[index].velocity = CGVector(dx: v.x * 0.5, dy: v.y * 0.5)
            }
            dragIndex = nil
        }
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard let index = bubble(at: gesture.location(in: self)) else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onOpen?(index, frameOfBubble(index))
    }

    /// The bubble's avatar now, in this view.
    func frameOfBubble(_ index: Int) -> CGRect {
        let b = bubbles[index]
        return CGRect(x: b.position.x - b.member.radius, y: b.position.y - b.member.radius,
                      width: b.member.radius * 2, height: b.member.radius * 2)
    }

    func person(at index: Int) -> ChannelPerson { bubbles[index].member.person }

    // MARK: Simulation

    private func step(_ dt: CFTimeInterval) {
        clock += dt
        mode.step(toward: orbitMode ? 1 : 0, deltaTime: dt)
        let m = min(max(mode.value, 0), 1)
        let substeps = 2
        let h = CGFloat(dt) / CGFloat(substeps)
        for _ in 0..<substeps {
            var forces = [CGVector](repeating: .zero, count: bubbles.count)
            for i in bubbles.indices {
                let target = dragIndex == i ? dragPoint : home(i)
                let k: CGFloat = dragIndex == i ? 500 : 26
                forces[i].dx += (target.x - bubbles[i].position.x) * k
                forces[i].dy += (target.y - bubbles[i].position.y) * k
                for j in bubbles.indices where j != i {
                    let d = CGPoint(x: bubbles[i].position.x - bubbles[j].position.x, y: bubbles[i].position.y - bubbles[j].position.y)
                    let dist = max(hypot(d.x, d.y), 0.01)
                    let minDist = radius(i) + radius(j) + 22
                    if dist < minDist {
                        let push = (minDist - dist) * 320
                        forces[i].dx += d.x / dist * push
                        forces[i].dy += d.y / dist * push
                    }
                }
            }
            for i in bubbles.indices {
                bubbles[i].velocity.dx = (bubbles[i].velocity.dx + forces[i].dx * h) * max(0, 1 - 7 * h)
                bubbles[i].velocity.dy = (bubbles[i].velocity.dy + forces[i].dy * h) * max(0, 1 - 7 * h)
                bubbles[i].position.x += bubbles[i].velocity.dx * h
                bubbles[i].position.y += bubbles[i].velocity.dy * h
            }
        }

        // Liquid rings: merged into necks in the cluster, separate drops on the orbits.
        var shapes: [IslandFluidShape] = []
        for (index, bubble) in bubbles.enumerated() {
            let wobble = 1 + 0.03 * sin(clock * 2 + Double(index))
            let r = radius(index)
            shapes.append(.circle(center: bubble.position, radius: (r + 9) * wobble, blend: 30 * (1 - m)))
            bubble.image.bounds = CGRect(x: 0, y: 0, width: r * 2, height: r * 2)
            bubble.image.layer.cornerRadius = r
            bubble.image.center = bubble.position
            if let tag = tags[index] {
                tag.alpha = m
                tag.center = CGPoint(x: bubble.position.x + (index % 2 == 0 ? -1 : 1) * (r + tag.bounds.width / 2 - 4),
                                     y: bubble.position.y - r - 2)
            }
        }
        canvas.shapes = shapes
        canvas.spikes = []
        rings.forEach { $0.opacity = Float(m) }

        // Talk bubbles: circle their person, now and then hop to another along an arc.
        for index in talks.indices {
            talks[index].angle += CGFloat(dt) * 0.6
            if clock > talks[index].nextHop {
                talks[index].nextHop = clock + Double.random(in: 2.5...4.5)
                var next = Int.random(in: 0..<bubbles.count)
                if next == talks[index].host {
                    next = (next + 1) % bubbles.count
                }
                talks[index].host = next
                talks[index].spring.velocity = CGVector(dx: 0, dy: -260)
            }
            talks[index].spring.step(toward: talkTarget(index), deltaTime: dt)
            let talk = talks[index]
            talk.view.center = talk.spring.position
            let pulse = 1 + 0.06 * sin(clock * 3 + Double(index))
            talk.view.transform = CGAffineTransform(scaleX: pulse, y: pulse)
            talk.view.alpha = 1 - m
        }
    }
}

/// A drop that spreads from `source` into a card (its edges on separate springs, so it wobbles like
/// jelly), shows `content`, and on a tap outside pours back into wherever the source is by then.
final class LiquidMorphPanel: UIView {
    private let canvas = LiquidCanvasView()
    private let dim = UIView()
    private let content: UIView
    private let source: () -> CGRect
    private let target: CGRect
    private let sourceCorner: CGFloat
    private var top, bottom, left, right, corner: Spring1D
    private var open = true
    private var clock: CFTimeInterval = 0
    private var shown = false
    private var fading = false
    var onClose: (() -> Void)?

    init(in host: UIView, from source: @escaping () -> CGRect, sourceCorner: CGFloat, to target: CGRect, color: UIColor,
         content: UIView) {
        self.source = source
        self.target = target
        self.sourceCorner = sourceCorner
        self.content = content
        let start = source()
        top = Spring1D(start.minY, stiffness: 13, dampingRatio: 0.6)
        bottom = Spring1D(start.maxY, stiffness: 10, dampingRatio: 0.55)
        left = Spring1D(start.minX, stiffness: 11.5, dampingRatio: 0.58)
        right = Spring1D(start.maxX, stiffness: 12.5, dampingRatio: 0.6)
        corner = Spring1D(sourceCorner, stiffness: 11, dampingRatio: 0.8)
        super.init(frame: host.bounds)
        host.addSubview(self)
        dim.frame = bounds
        dim.backgroundColor = UIColor(white: 0, alpha: 0.55)
        dim.alpha = 0
        addSubview(dim)
        canvas.frame = bounds
        canvas.liquidColor = color
        canvas.gloss = 0.3
        canvas.rimWidth = 12
        canvas.onUpdate = { [weak self] dt in self?.step(dt) }
        addSubview(canvas)
        content.frame = target
        content.alpha = 0
        addSubview(content)
        dim.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(close)))
        UIView.animate(withDuration: 0.3) { self.dim.alpha = 1 }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func close() {
        guard open else { return }
        open = false
        clock = 0
        UIView.animate(withDuration: 0.15) { self.content.alpha = 0 }
        UIView.animate(withDuration: 0.35, delay: 0.1) { self.dim.alpha = 0 }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        canvas.isPaused = false
    }

    private func step(_ dt: CFTimeInterval) {
        clock += dt
        let goal = open ? target : source()
        if open || clock > 0.1 {
            top.step(toward: goal.minY, deltaTime: dt)
            bottom.step(toward: goal.maxY, deltaTime: dt)
            left.step(toward: goal.minX, deltaTime: dt)
            right.step(toward: goal.maxX, deltaTime: dt)
            corner.step(toward: open ? 34 : sourceCorner, deltaTime: dt)
        }
        let rect = CGRect(x: left.value, y: top.value, width: max(right.value - left.value, 1), height: max(bottom.value - top.value, 1))
        canvas.shapes = [IslandFluidShape(center: rect.center, halfSize: CGSize(width: rect.width / 2, height: rect.height / 2),
                                          cornerRadius: corner.value, blend: 0)]
        let remaining = max(abs(top.value - goal.minY), abs(bottom.value - goal.maxY), abs(left.value - goal.minX), abs(right.value - goal.maxX))
        if open, !shown, clock > 0.2, remaining < 30 {
            shown = true
            UIView.animate(withDuration: 0.25) { self.content.alpha = 1 }
        }
        if open, shown, remaining < 0.3 {
            canvas.renderFrame()
            canvas.isPaused = true
        }
        if !open, !fading, clock > 0.25, remaining < 4 {
            fading = true
            UIView.animate(withDuration: 0.15) { self.alpha = 0 } completion: { _ in
                self.canvas.isPaused = true
                self.onClose?()
                self.removeFromSuperview()
            }
        }
    }
}

/// A picture-in-picture call tile: drag it and it squashes along the motion like jelly; let go and it
/// flies to the nearest corner, overshooting a little.
final class CallTile: UIView {
    private var spring = IslandSpring(.zero, stiffness: 9, dampingRatio: 0.62)
    private var dragging = false
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var target = CGPoint.zero
    var margins = UIEdgeInsets(top: 120, left: 16, bottom: 120, right: 16)

    init(person: ChannelPerson) {
        super.init(frame: CGRect(x: 0, y: 0, width: 116, height: 150))
        layer.cornerRadius = 26
        layer.cornerCurve = .continuous
        clipsToBounds = true
        let gradient = CAGradientLayer()
        gradient.frame = bounds
        gradient.colors = [UIColor(hue: person.hue, saturation: 0.4, brightness: 0.6, alpha: 1).cgColor,
                           UIColor(hue: person.hue, saturation: 0.6, brightness: 0.25, alpha: 1).cgColor]
        layer.addSublayer(gradient)
        let avatar = UIImageView(image: ChannelAvatar.image(for: person, size: 70))
        avatar.frame = CGRect(x: 23, y: 28, width: 70, height: 70)
        addSubview(avatar)
        let name = UILabel()
        name.text = "\(person.name.split(separator: " ").first ?? "")  ılıl"
        name.font = .systemFont(ofSize: 15, weight: .semibold)
        name.textColor = .white
        name.sizeToFit()
        name.frame.origin = CGPoint(x: 12, y: bounds.height - 30)
        addSubview(name)
        let mute = UIImageView(image: UIImage(systemName: "mic.slash"))
        mute.tintColor = .white
        mute.frame = CGRect(x: bounds.width - 30, y: 8, width: 20, height: 20)
        addSubview(mute)
        layer.borderColor = UIColor(white: 1, alpha: 0.15).cgColor
        layer.borderWidth = 1
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(panned(_:))))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        link?.invalidate()
        guard superview != nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func place(at corner: CGPoint) {
        target = corner
        spring = IslandSpring(corner, stiffness: 9, dampingRatio: 0.62)
        center = corner
    }

    private var corners: [CGPoint] {
        guard let host = superview else { return [] }
        let w = bounds.width / 2, h = bounds.height / 2
        let left = margins.left + w, right = host.bounds.width - margins.right - w
        let top = margins.top + h, bottom = host.bounds.height - margins.bottom - h
        return [CGPoint(x: left, y: top), CGPoint(x: right, y: top), CGPoint(x: left, y: bottom), CGPoint(x: right, y: bottom)]
    }

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        guard let host = superview else { return }
        switch gesture.state {
        case .began:
            dragging = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .changed:
            let t = gesture.translation(in: host)
            spring.position = CGPoint(x: spring.position.x + t.x, y: spring.position.y + t.y)
            gesture.setTranslation(.zero, in: host)
            let v = gesture.velocity(in: host)
            spring.velocity = CGVector(dx: v.x, dy: v.y)
        default:
            dragging = false
            // Where it would coast to decides the corner.
            let v = gesture.velocity(in: host)
            let projected = CGPoint(x: spring.position.x + v.x * 0.2, y: spring.position.y + v.y * 0.2)
            target = corners.min { $0.distance(to: projected) < $1.distance(to: projected) } ?? spring.position
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        let dt = lastTimestamp.map { min(link.timestamp - $0, 1.0 / 30) } ?? 1.0 / 60
        lastTimestamp = link.timestamp
        if !dragging {
            spring.step(toward: target, deltaTime: dt)
        }
        center = spring.position
        // Jelly: stretch along the motion, thin across it.
        let speed = spring.speed
        let stretch = min(speed / 3500, 0.18)
        let angle = atan2(spring.velocity.dy, spring.velocity.dx)
        transform = CGAffineTransform(rotationAngle: angle).scaledBy(x: 1 + stretch, y: 1 - stretch * 0.7).rotated(by: -angle)
    }
}
