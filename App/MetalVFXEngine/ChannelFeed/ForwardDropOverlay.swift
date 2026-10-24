//
//  ForwardDropOverlay.swift
//  controller
//
//  Forwarding by dragging: press the share button and a row of contacts rises; pull, and a drop
//  carrying a thumbnail of the post stretches out of the button on a liquid strand. Hover a contact
//  and it leans in; let go over it and the strand snaps, the drop flies in and the contact gulps it
//  with a check mark. Let go anywhere else and the drop is pulled back into the button.
//  Feed it the press with `move(to:)` and `release()`.
//

import UIKit

final class ForwardDropOverlay: UIView {
    private let canvas = LiquidCanvasView()
    private let origin: CGPoint
    private let thumbnail = UIImageView()
    private let row = UIView()
    private var contacts: [(view: UIImageView, name: UILabel, person: ChannelPerson)] = []
    private let hint = UILabel()
    private var drop: IslandSpring
    private var dropRadius = Spring1D(0, stiffness: 14, dampingRatio: 0.5)
    private var finger: CGPoint?
    private var hovered: Int?
    private var sentTo: Int?
    private var snapTime: CFTimeInterval?
    private var clock: CFTimeInterval = 0
    private var dragged = false
    private var gulped = false
    private var finished = false
    private let selection = UISelectionFeedbackGenerator()

    /// `button` is the share button, `post` the bubble to carry; both are snapshotted from `host`.
    init(in host: UIView, button: UIView, post: UIView, people: [ChannelPerson]) {
        origin = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: host)
        drop = IslandSpring(origin, stiffness: 18, dampingRatio: 0.6)
        super.init(frame: host.bounds)
        host.addSubview(self)

        canvas.frame = bounds
        canvas.liquidColor = ChannelPalette.picker
        canvas.gloss = 0.5
        canvas.rimWidth = 8
        canvas.onUpdate = { [weak self] dt in self?.step(dt) }

        // The contacts row, rising above the bottom bar.
        let safe = host.safeAreaInsets
        row.frame = CGRect(x: 10, y: bounds.height - safe.bottom - 170, width: bounds.width - 20, height: 96)
        row.backgroundColor = UIColor(red: 0.12, green: 0.11, blue: 0.16, alpha: 0.96)
        row.layer.cornerRadius = 28
        row.layer.cornerCurve = .continuous
        row.transform = CGAffineTransform(translationX: 0, y: 140)
        addSubview(row)
        let spacing = row.bounds.width / CGFloat(people.count)
        for (index, person) in people.enumerated() {
            let avatar = UIImageView(image: ChannelAvatar.image(for: person, size: 52))
            avatar.frame = CGRect(x: 0, y: 0, width: 52, height: 52)
            avatar.center = CGPoint(x: spacing * (CGFloat(index) + 0.5), y: 38)
            row.addSubview(avatar)
            let name = UILabel()
            name.text = String(person.name.split(separator: " ").first ?? "")
            name.font = .systemFont(ofSize: 11, weight: .medium)
            name.textColor = ChannelPalette.secondaryText
            name.sizeToFit()
            name.center = CGPoint(x: avatar.center.x, y: 78)
            row.addSubview(name)
            contacts.append((avatar, name, person))
        }
        hint.text = "Перетащите пост на контакт"
        hint.font = .systemFont(ofSize: 13, weight: .semibold)
        hint.textColor = .white
        hint.sizeToFit()
        hint.center = CGPoint(x: bounds.midX, y: row.frame.minY - 18)
        hint.alpha = 0
        addSubview(hint)
        addSubview(canvas)

        let image = UIGraphicsImageRenderer(bounds: post.bounds).image { _ in
            post.drawHierarchy(in: post.bounds, afterScreenUpdates: false)
        }
        thumbnail.image = image
        thumbnail.contentMode = .scaleAspectFill
        thumbnail.bounds = CGRect(x: 0, y: 0, width: 36, height: 36)
        thumbnail.layer.cornerRadius = 18
        thumbnail.clipsToBounds = true
        thumbnail.alpha = 0
        thumbnail.center = origin
        addSubview(thumbnail)

        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0.3) {
            self.row.transform = .identity
        }
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissTap)))
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func move(to point: CGPoint) {
        guard !finished else { return }
        if point.distance(to: origin) > 12 {
            dragged = true
        }
        finger = point
        let index = contacts.indices.first { i in
            let frame = contacts[i].view.convert(contacts[i].view.bounds, to: self).insetBy(dx: -14, dy: -16)
            return frame.contains(point)
        }
        if index != hovered {
            hovered = index
            if index != nil {
                selection.selectionChanged()
            }
            UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.55, initialSpringVelocity: 0.4) {
                for (i, contact) in self.contacts.enumerated() {
                    let scale: CGFloat = i == index ? 1.22 : 1
                    contact.view.transform = CGAffineTransform(translationX: 0, y: i == index ? -8 : 0).scaledBy(x: scale, y: scale)
                    contact.name.textColor = i == index ? .white : ChannelPalette.secondaryText
                }
            }
        }
    }

    func release() {
        guard !finished else { return }
        finger = nil
        if let hovered {
            send(to: hovered)
        } else if !dragged {
            // Just a tap: keep the contacts up with a hint, and pass taps on them through.
            UIView.animate(withDuration: 0.3) { self.hint.alpha = 1 }
            isTapMode = true
        } else {
            dismiss()
        }
    }

    private var isTapMode = false

    @objc private func dismissTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        if isTapMode, let index = contacts.indices.first(where: {
            contacts[$0].view.convert(contacts[$0].view.bounds, to: self).insetBy(dx: -10, dy: -10).contains(point)
        }) {
            hovered = index
            send(to: index)
        } else {
            dismiss()
        }
    }

    private func send(to index: Int) {
        sentTo = index
        snapTime = clock
        finished = true
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        canvas.isPaused = false
    }

    private func dismiss() {
        finished = true
        UIView.animate(withDuration: 0.35, delay: 0.05, options: [.curveEaseIn]) {
            self.row.transform = CGAffineTransform(translationX: 0, y: 160)
            self.hint.alpha = 0
        } completion: { _ in
            self.canvas.isPaused = true
            self.removeFromSuperview()
        }
        canvas.isPaused = false
    }

    private func contactCenter(_ index: Int) -> CGPoint {
        contacts[index].view.convert(CGPoint(x: 26, y: 26), to: self)
    }

    private func step(_ dt: CFTimeInterval) {
        clock += dt
        let pulling = finger != nil && dragged && !finished
        var target = origin
        if let finger, pulling {
            target = finger
        } else if let sentTo {
            target = contactCenter(sentTo)
        }
        drop.step(toward: target, deltaTime: dt)
        let arrived = sentTo != nil && drop.position.distance(to: target) < 10
        dropRadius.step(toward: (pulling || (sentTo != nil && !arrived)) ? 24 : 0, deltaTime: dt)
        if arrived, let sentTo, !gulped {
            gulped = true
            gulp(sentTo)
        }

        let r = max(dropRadius.value, 0)
        thumbnail.center = drop.position
        thumbnail.alpha = gulped ? 0 : min(1, max(0, (r - 12) / 8))
        thumbnail.transform = CGAffineTransform(scaleX: max(r / 24, 0.01), y: max(r / 24, 0.01))

        var shapes: [IslandFluidShape] = []
        var spikes: [IslandFluidSpike] = []
        if r > 0.5 {
            shapes.append(.circle(center: drop.position, radius: r, blend: 0))
        }
        let distance = drop.position.distance(to: origin)
        if snapTime == nil, r > 0.5, distance > 4 {
            // The strand thins as it stretches; the button keeps a little bead of liquid.
            let thickness = max(2, 9 - distance / 40)
            shapes.append(.circle(center: origin, radius: 12, blend: 10))
            spikes.append(IslandFluidSpike(base: origin, tip: drop.position, baseRadius: thickness + 3, tipRadius: thickness,
                                           blend: 8))
        } else if let snapTime, clock - snapTime < 0.6 {
            // Snapped: the bead at the button springs back in.
            let t = clock - snapTime
            let wobble = 12 * exp(-6 * t) * (1 + 0.3 * cos(22 * t))
            shapes.append(.circle(center: origin, radius: wobble, blend: 0))
        }
        canvas.shapes = shapes
        canvas.spikes = spikes
    }

    /// The contact swallows the drop: it swells, wobbles back and gets a check mark.
    private func gulp(_ index: Int) {
        let contact = contacts[index].view
        let pop = CAKeyframeAnimation(keyPath: "transform.scale")
        pop.values = [1.22, 1.45, 0.92, 1.08, 1.0]
        pop.keyTimes = [0, 0.25, 0.55, 0.8, 1]
        pop.duration = 0.55
        contact.layer.add(pop, forKey: "gulp")
        contact.transform = .identity
        let check = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        check.tintColor = .systemGreen
        check.backgroundColor = .white
        check.layer.cornerRadius = 9
        check.frame = CGRect(x: 36, y: 36, width: 18, height: 18)
        check.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
        contact.addSubview(check)
        UIView.animate(withDuration: 0.4, delay: 0.1, usingSpringWithDamping: 0.45, initialSpringVelocity: 0.6) {
            check.transform = .identity
        }
        hint.text = "Отправлено: \(contacts[index].person.name)"
        hint.sizeToFit()
        hint.center.x = bounds.midX
        UIView.animate(withDuration: 0.25) { self.hint.alpha = 1 }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in self?.dismiss() }
    }
}
