//
//  StoryViewer.swift
//  controller
//
//  Stories opening out of their avatar: the story grows from the avatar's circle to the full screen,
//  its edges on separate springs so it stretches a little on the way, like a drop spreading. The
//  progress bars on top are liquid tubes (LiquidTubeView). Tap right / left for the next / previous
//  story, hold to pause; after a person's last story the next person's turns in on a cube. Drag down
//  and the story shrinks back into the avatar it came from.
//

import UIKit

private final class StoryPage: UIView {
    let user: StoryUser
    private let image = UIImageView()
    private var tubes: [LiquidTubeView] = []
    private var levels: [Spring1D] = []
    let shade = UIView()

    init(user: StoryUser) {
        self.user = user
        super.init(frame: .zero)
        backgroundColor = .black
        image.contentMode = .scaleAspectFill
        image.clipsToBounds = true
        addSubview(image)
        let top = CAGradientLayer()
        top.colors = [UIColor(white: 0, alpha: 0.45).cgColor, UIColor.clear.cgColor]
        top.name = "top"
        layer.addSublayer(top)
        for _ in user.photos {
            let tube = LiquidTubeView()
            tube.liquidColor = .white
            tube.trackColor = UIColor(white: 1, alpha: 0.3)
            tube.isUserInteractionEnabled = false
            addSubview(tube)
            tubes.append(tube)
            levels.append(Spring1D(0, stiffness: 14, dampingRatio: 0.7))
        }
        let avatar = UIImageView(image: ChannelAvatar.image(for: user.person, size: 32))
        avatar.tag = 1
        addSubview(avatar)
        let name = UILabel()
        name.text = "\(user.person.name)   2 ч"
        name.font = .systemFont(ofSize: 14, weight: .semibold)
        name.textColor = .white
        name.tag = 2
        addSubview(name)
        shade.backgroundColor = .black
        shade.alpha = 0
        shade.isUserInteractionEnabled = false
        addSubview(shade)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(_ story: Int) {
        image.image = DemoPhotos.image(user.photos[story], size: CGSize(width: 540, height: 960), seed: UInt64(story + 3))
    }

    /// Story `index` is at `progress`; earlier ones are full, later ones empty.
    func setProgress(story index: Int, progress: CGFloat, deltaTime: CFTimeInterval) {
        for (i, tube) in tubes.enumerated() {
            let target: CGFloat = i < index ? 1 : i > index ? 0 : progress
            levels[i].step(toward: target, deltaTime: deltaTime)
            tube.fill = min(max(levels[i].value, 0), 1)
            tube.slosh = levels[i].velocity * 0.3
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        image.frame = bounds
        shade.frame = bounds
        let safeTop = window?.safeAreaInsets.top ?? 59
        layer.sublayers?.first { $0.name == "top" }?.frame = CGRect(x: 0, y: 0, width: bounds.width, height: safeTop + 90)
        let gap: CGFloat = 4
        let width = (bounds.width - 16 - gap * CGFloat(max(tubes.count - 1, 0))) / CGFloat(max(tubes.count, 1))
        for (i, tube) in tubes.enumerated() {
            tube.frame = CGRect(x: 8 + CGFloat(i) * (width + gap), y: safeTop + 6, width: width, height: 4)
        }
        viewWithTag(1)?.frame = CGRect(x: 12, y: safeTop + 20, width: 32, height: 32)
        viewWithTag(2)?.frame = CGRect(x: 52, y: safeTop + 26, width: bounds.width - 100, height: 20)
    }
}

final class StoryViewer: UIView {
    var onClose: (() -> Void)?
    /// A person's stories were all seen.
    var onSeen: ((Int) -> Void)?

    private let users: [StoryUser]
    private let sourceFrame: (Int) -> CGRect
    private let dim = UIView()
    private let stage = UIView()
    private let stageMask = CAShapeLayer()
    private var page: StoryPage
    private var userIndex: Int
    private var storyIndex = 0
    private var progress: CGFloat = 0
    private var top, bottom, left, right, corner: Spring1D
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var closing = false
    private var held = false
    private var dragging = false
    private var turning = false

    init(in host: UIView, users: [StoryUser], start: Int, sourceFrame: @escaping (Int) -> CGRect) {
        self.users = users
        self.sourceFrame = sourceFrame
        userIndex = start
        page = StoryPage(user: users[start])
        let source = sourceFrame(start)
        top = Spring1D(source.minY, stiffness: 12, dampingRatio: 0.7)
        bottom = Spring1D(source.maxY, stiffness: 9.5, dampingRatio: 0.66)
        left = Spring1D(source.minX, stiffness: 11, dampingRatio: 0.7)
        right = Spring1D(source.maxX, stiffness: 10, dampingRatio: 0.68)
        corner = Spring1D(source.width / 2, stiffness: 10, dampingRatio: 0.85)
        super.init(frame: host.bounds)
        host.addSubview(self)
        dim.backgroundColor = .black
        dim.frame = bounds
        dim.alpha = 0
        addSubview(dim)
        stage.frame = bounds
        stage.layer.mask = stageMask
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / 900
        stage.layer.sublayerTransform = perspective
        addSubview(stage)
        page.frame = stage.bounds
        page.show(0)
        stage.addSubview(page)

        let hold = UILongPressGestureRecognizer(target: self, action: #selector(holding(_:)))
        hold.minimumPressDuration = 0.2
        addGestureRecognizer(hold)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.require(toFail: hold)
        addGestureRecognizer(tap)
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(panned(_:))))

        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        apply()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Gestures

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard !closing, !turning else { return }
        if gesture.location(in: self).x < bounds.width * 0.3 {
            previous()
        } else {
            next()
        }
    }

    @objc private func holding(_ gesture: UILongPressGestureRecognizer) {
        held = gesture.state == .began || gesture.state == .changed
    }

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        guard !closing else { return }
        let t = gesture.translation(in: self)
        switch gesture.state {
        case .began, .changed:
            dragging = true
            // The story follows the finger down, shrinking a little.
            let dy = max(t.y, 0)
            let s = 1 - min(dy, 500) / 1400
            let w = bounds.width * s, h = bounds.height * s
            let rect = CGRect(x: bounds.midX - w / 2 + t.x * 0.4, y: dy + (bounds.height - h) / 2, width: w, height: h)
            top = Spring1D(rect.minY, stiffness: top.stiffness, dampingRatio: top.dampingRatio)
            bottom = Spring1D(rect.maxY, stiffness: bottom.stiffness, dampingRatio: bottom.dampingRatio)
            left = Spring1D(rect.minX, stiffness: left.stiffness, dampingRatio: left.dampingRatio)
            right = Spring1D(rect.maxX, stiffness: right.stiffness, dampingRatio: right.dampingRatio)
            corner.value = min(dy / 4, 36)
        default:
            dragging = false
            if t.y > 110 || gesture.velocity(in: self).y > 900 {
                close()
            }
        }
    }

    // MARK: Stories

    private func next() {
        if storyIndex + 1 < users[userIndex].photos.count {
            storyIndex += 1
            progress = 0
            page.show(storyIndex)
            UISelectionFeedbackGenerator().selectionChanged()
        } else if userIndex + 1 < users.count {
            onSeen?(userIndex)
            turn(to: userIndex + 1, forward: true)
        } else {
            onSeen?(userIndex)
            close()
        }
    }

    private func previous() {
        if storyIndex > 0 {
            storyIndex -= 1
            progress = 0
            page.show(storyIndex)
            UISelectionFeedbackGenerator().selectionChanged()
        } else if userIndex > 0 {
            turn(to: userIndex - 1, forward: false)
        } else {
            progress = 0
        }
    }

    /// The cube: the current person's face turns away as the next one's turns in.
    private func turn(to index: Int, forward: Bool) {
        turning = true
        let incoming = StoryPage(user: users[index])
        incoming.frame = stage.bounds
        incoming.show(0)
        stage.addSubview(incoming)
        let outgoing = page
        let w = stage.bounds.width
        func face(_ angle: CGFloat) -> CATransform3D {
            let pushed = CATransform3DMakeTranslation(0, 0, -w / 2)
            return CATransform3DTranslate(CATransform3DRotate(pushed, angle, 0, 1, 0), 0, 0, w / 2)
        }
        let quarter = CGFloat.pi / 2 * (forward ? 1 : -1)
        incoming.layer.transform = face(quarter)
        incoming.shade.alpha = 0.6
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        UIView.animate(withDuration: 0.6, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0.2) {
            incoming.layer.transform = CATransform3DIdentity
            incoming.shade.alpha = 0
            outgoing.layer.transform = face(-quarter)
            outgoing.shade.alpha = 0.6
        } completion: { _ in
            outgoing.removeFromSuperview()
            self.turning = false
        }
        page = incoming
        userIndex = index
        storyIndex = 0
        progress = 0
    }

    private func close() {
        guard !closing else { return }
        closing = true
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    // MARK: Animation

    @objc private func tick(_ link: CADisplayLink) {
        let dt = lastTimestamp.map { min(link.timestamp - $0, 1.0 / 30) } ?? 1.0 / 60
        lastTimestamp = link.timestamp
        let goal = closing ? sourceFrame(userIndex) : bounds
        if !dragging {
            top.step(toward: goal.minY, deltaTime: dt)
            bottom.step(toward: goal.maxY, deltaTime: dt)
            left.step(toward: goal.minX, deltaTime: dt)
            right.step(toward: goal.maxX, deltaTime: dt)
            corner.step(toward: closing ? goal.width / 2 : 0, deltaTime: dt)
        }
        if !closing, !held, !dragging, !turning {
            progress += CGFloat(dt / 5)
            if progress >= 1 {
                next()
            }
        }
        page.setProgress(story: storyIndex, progress: min(progress, 1), deltaTime: dt)
        apply()
        if closing, abs(top.value - goal.minY) < 1.5, abs(left.value - goal.minX) < 1.5 {
            link.invalidate()
            UIView.animate(withDuration: 0.12) { self.alpha = 0 } completion: { _ in
                self.onClose?()
                self.removeFromSuperview()
            }
        }
    }

    /// Scales the stage uniformly into the current rect (cropping with the mask), like a drop spreading.
    private func apply() {
        let rect = CGRect(x: left.value, y: top.value, width: max(right.value - left.value, 1),
                          height: max(bottom.value - top.value, 1))
        let s = max(rect.width / bounds.width, rect.height / bounds.height)
        stage.transform = CGAffineTransform(translationX: rect.midX - bounds.midX, y: rect.midY - bounds.midY).scaledBy(x: s, y: s)
        let local = CGRect(x: bounds.midX - rect.width / s / 2, y: bounds.midY - rect.height / s / 2,
                           width: rect.width / s, height: rect.height / s)
        stageMask.path = UIBezierPath(roundedRect: local, cornerRadius: max(corner.value, 0) / s).cgPath
        let open = min(1, rect.height / bounds.height)
        dim.alpha = open * (closing ? 0.6 : 1)
    }
}
