//
//  CommentsSheetOverlay.swift
//  controller
//
//  "67 Comments" opens by pouring the post's bubble into a sheet: the bubble is liquid
//  (LiquidCanvasView), its four edges ride their own springs — the top flies up first, the sides
//  follow, the bottom lags — so it stretches like jelly on the way, with a gooey tail left at the
//  button it came from. The comments fade in once it has settled; closing pours it back.
//

import UIKit

final class CommentsSheetOverlay: UIView {
    private let canvas = LiquidCanvasView()
    private let dim = UIView()
    private let content = UIView()
    private let source: CGRect
    private let button: CGPoint
    private var target: CGRect = .zero
    private var top: Spring1D
    private var bottom: Spring1D
    private var left: Spring1D
    private var right: Spring1D
    private var corner: Spring1D
    private var tail = Spring1D(1, stiffness: 7, dampingRatio: 0.8)
    private var open = true
    private var clock: CFTimeInterval = 0
    private var shownContent = false
    private var fading = false
    var onClose: (() -> Void)?

    /// Pours `bubble` (a post's bubble) into a sheet over `host`; `buttonPoint` is the comments row, in `host`.
    init(in host: UIView, bubble: UIView, buttonPoint: CGPoint, count: Int, people: [ChannelPerson]) {
        source = bubble.convert(bubble.bounds, to: host)
        button = buttonPoint
        top = Spring1D(source.minY, stiffness: 12, dampingRatio: 0.62)
        bottom = Spring1D(source.maxY, stiffness: 8, dampingRatio: 0.55)
        left = Spring1D(source.minX, stiffness: 10, dampingRatio: 0.6)
        right = Spring1D(source.maxX, stiffness: 9.5, dampingRatio: 0.58)
        corner = Spring1D(18, stiffness: 10, dampingRatio: 0.8)
        super.init(frame: host.bounds)
        host.addSubview(self)
        let safe = host.safeAreaInsets
        target = CGRect(x: 6, y: safe.top + 8, width: bounds.width - 12, height: bounds.height - safe.top - 14)

        dim.frame = bounds
        dim.backgroundColor = UIColor(white: 0, alpha: 0.5)
        dim.alpha = 0
        addSubview(dim)
        canvas.frame = bounds
        canvas.liquidColor = ChannelPalette.bubble
        canvas.gloss = 0.22
        canvas.rimWidth = 12
        canvas.onUpdate = { [weak self] dt in self?.step(dt) }
        addSubview(canvas)
        content.frame = target
        content.alpha = 0
        addSubview(content)
        buildContent(count: count, people: people)
        dim.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(close)))
        UIView.animate(withDuration: 0.3) { self.dim.alpha = 1 }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildContent(count: Int, people: [ChannelPerson]) {
        let title = UILabel()
        title.text = "\(count) comments"
        title.font = .systemFont(ofSize: 17, weight: .bold)
        title.textColor = .label
        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)),
                             for: .normal)
        closeButton.tintColor = .white
        closeButton.backgroundColor = UIColor(white: 1, alpha: 0.12)
        closeButton.layer.cornerRadius = 16
        closeButton.accessibilityLabel = "Close comments"
        closeButton.accessibilityIdentifier = "contact.channel.comments.close"
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        let grabber = UIView()
        grabber.backgroundColor = UIColor(white: 1, alpha: 0.25)
        grabber.layer.cornerRadius = 2.5

        let texts = [
            "Springs make all the difference. Linear animations are hard to look at now",
            "Could we get the same glass effect for the tab bar?",
            "We added droplet reactions and engagement went up noticeably",
            "The key is not to overdo it. The feed should feel calm",
            "Stars with golden fluid look premium 🔥",
            "Looking forward to the Metal dust breakdown!",
        ]
        let list = UIStackView()
        list.axis = .vertical
        list.spacing = 16
        for (index, text) in texts.enumerated() {
            let person = people[index % people.count]
            let avatar = UIImageView(image: ChannelAvatar.image(for: person, size: 38))
            avatar.setContentHuggingPriority(.required, for: .horizontal)
            avatar.widthAnchor.constraint(equalToConstant: 38).isActive = true
            avatar.heightAnchor.constraint(equalToConstant: 38).isActive = true
            let name = UILabel()
            name.text = person.name
            name.font = .systemFont(ofSize: 14, weight: .semibold)
            name.textColor = UIColor(hue: person.hue, saturation: 0.45, brightness: 1, alpha: 1)
            let body = UILabel()
            body.text = text
            body.numberOfLines = 0
            body.font = .systemFont(ofSize: 15)
            body.textColor = .label
            let column = UIStackView(arrangedSubviews: [name, body])
            column.axis = .vertical
            column.spacing = 2
            let row = UIStackView(arrangedSubviews: [avatar, column])
            row.spacing = 10
            row.alignment = .top
            list.addArrangedSubview(row)
        }
        let input = UILabel()
        input.text = "   Comment…"
        input.textColor = ChannelPalette.secondaryText
        input.backgroundColor = UIColor(white: 1, alpha: 0.08)
        input.layer.cornerRadius = 20
        input.clipsToBounds = true

        for view in [grabber, title, closeButton, list, input] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            grabber.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            grabber.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            grabber.widthAnchor.constraint(equalToConstant: 36),
            grabber.heightAnchor.constraint(equalToConstant: 5),
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 26),
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            closeButton.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32),
            list.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 22),
            list.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            list.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            input.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            input.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            input.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -26),
            input.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    @objc private func close() {
        guard open else { return }
        open = false
        clock = 0
        UIView.animate(withDuration: 0.18) { self.content.alpha = 0 }
        UIView.animate(withDuration: 0.4, delay: 0.15) { self.dim.alpha = 0 }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        canvas.isPaused = false
    }

    private func step(_ dt: CFTimeInterval) {
        clock += dt
        // Closing waits for the comments to fade before the liquid moves.
        let moving = open || clock > 0.12
        let goal = open ? target : source
        if moving {
            top.step(toward: goal.minY, deltaTime: dt)
            bottom.step(toward: goal.maxY, deltaTime: dt)
            left.step(toward: goal.minX, deltaTime: dt)
            right.step(toward: goal.maxX, deltaTime: dt)
            corner.step(toward: open ? 30 : 18, deltaTime: dt)
            tail.step(toward: open ? 0 : 1, deltaTime: dt)
        }
        let rect = CGRect(x: left.value, y: top.value, width: max(right.value - left.value, 1),
                          height: max(bottom.value - top.value, 1))
        var shapes = [IslandFluidShape(center: rect.center, halfSize: CGSize(width: rect.width / 2, height: rect.height / 2),
                                       cornerRadius: corner.value, blend: 0)]
        var spikes: [IslandFluidSpike] = []
        // The gooey tail at the comments button, thinning as the sheet pulls away.
        if tail.value > 0.04 {
            let r = 16 * tail.value
            shapes.append(.circle(center: button, radius: r, blend: 14))
            let anchor = CGPoint(x: min(max(button.x, rect.minX + 20), rect.maxX - 20), y: min(max(button.y, rect.minY + 20), rect.maxY - 20))
            spikes.append(IslandFluidSpike(base: anchor, tip: button, baseRadius: 14 * tail.value, tipRadius: r * 0.8, blend: 10))
        }
        canvas.shapes = shapes
        canvas.spikes = spikes

        let remaining = max(abs(top.value - target.minY), abs(bottom.value - target.maxY))
        if open, !shownContent, clock > 0.25, remaining < 40 {
            shownContent = true
            UIView.animate(withDuration: 0.3) { self.content.alpha = 1 }
        }
        if open {
            let settled = top.isSettled(at: goal.minY, tolerance: 0.3) && bottom.isSettled(at: goal.maxY, tolerance: 0.3)
                && left.isSettled(at: goal.minX, tolerance: 0.3) && right.isSettled(at: goal.maxX, tolerance: 0.3)
            if settled, clock > 0.5 {
                canvas.renderFrame()
                canvas.isPaused = true
            }
        } else if !fading, clock > 0.3,
                  max(abs(top.value - goal.minY), abs(bottom.value - goal.maxY), abs(left.value - goal.minX),
                      abs(right.value - goal.maxX)) < 8 {
            // Back in the bubble's shape: melt away over the real post instead of waiting for the wobble to end.
            fading = true
            UIView.animate(withDuration: 0.2) {
                self.canvas.alpha = 0
            } completion: { _ in
                self.canvas.isPaused = true
                self.onClose?()
                self.removeFromSuperview()
            }
        }
    }
}
