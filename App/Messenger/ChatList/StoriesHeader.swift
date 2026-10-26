import UIKit

final class StoriesHeader: UIView {
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
            self.tintBorders()
    }

    static let titleHeight: CGFloat = 44
    static let foldersHeight: CGFloat = 42
    static let storiesHeight: CGFloat = 92

    var onSettings: (() -> Void)?
    var onLock: (() -> Void)?
    var onCompose: (() -> Void)?
    var onStackTap: (() -> Void)?
    var onOpenStory: ((Int) -> Void)?
    var safeTop: CGFloat = 0

    private let background = Views.barBackground()
    private let hairline = UIView()
    private let exitButton = Views.iconButton("gearshape", size: 19)
    private let composeButton = Views.iconButton("square.and.pencil", size: 19)
    private let lockButton = Views.iconButton("lock.open.fill", size: 13, tint: Palette.text)
    private let title = Views.label("Chats", size: 17, weight: .semibold)
    private let canvas = LiquidCanvasView()
    private var avatars: [UIImageView] = []
    private var names: [UILabel] = []
    private var springs: [Spring1D] = []
    private var seen: [Bool] = []
    private var pull: CGFloat = 0
    private var lockShown = false
    private let users = MessengerData.storyUsers
    private let stackCount = 3
    private let expandedSize: CGFloat = 46
    private let stackSize: CGFloat = 26

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(background)
        hairline.backgroundColor = Palette.separator
        addSubview(hairline)
        exitButton.accessibilityLabel = "Settings"
        composeButton.accessibilityLabel = "New Message"
        lockButton.accessibilityLabel = "Lock"
        exitButton.addAction(UIAction { [weak self] _ in self?.onSettings?() }, for: .touchUpInside)
        composeButton.addAction(UIAction { [weak self] _ in self?.onCompose?() }, for: .touchUpInside)
        lockButton.addAction(UIAction { [weak self] _ in self?.onLock?() }, for: .touchUpInside)
        lockButton.alpha = 0
        addSubview(exitButton)
        addSubview(composeButton)
        addSubview(lockButton)
        title.textAlignment = .left
        addSubview(title)

        canvas.liquidColor = Palette.storyRing
        canvas.gloss = 0.5
        canvas.rimWidth = 4
        canvas.onUpdate = { [weak self] dt in self?.step(dt) }
        addSubview(canvas)
        for (index, user) in users.enumerated() {
            let avatar = UIImageView(image: ChannelAvatar.image(for: user.person, size: expandedSize))
            avatar.clipsToBounds = true
            avatar.isUserInteractionEnabled = true
            avatar.tag = index
            avatar.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(avatarTapped(_:))))
            addSubview(avatar)
            avatars.append(avatar)
            let name = Views.label(index == 0 ? "You" : String(user.person.name.split(separator: " ")[0]),
                                     size: 10, color: Palette.text)
            name.textAlignment = .center
            addSubview(name)
            names.append(name)
            springs.append(Spring1D(0, stiffness: 16 - CGFloat(index) * 1.2, dampingRatio: 0.62))
            seen.append(false)
        }

        tintBorders()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func tintBorders() {
        let color = Palette.background.resolvedColor(with: traitCollection).cgColor
        avatars.forEach { $0.layer.borderColor = color }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        background.frame = bounds
        hairline.frame = CGRect(x: 0, y: bounds.height - 0.5, width: bounds.width, height: 0.5)
        exitButton.frame = CGRect(x: 4, y: safeTop, width: 44, height: Self.titleHeight)
        composeButton.frame = CGRect(x: bounds.width - 48, y: safeTop, width: 44, height: Self.titleHeight)
        canvas.frame = CGRect(x: 0, y: 0, width: bounds.width, height: safeTop + Self.titleHeight + Self.storiesHeight + 20)
        place()
        if canvas.isPaused { canvas.renderFrame() }
    }

    func setPull(_ amount: CGFloat) {
        let next = min(max(amount, 0), 1)
        guard pull != next else { return }
        pull = next
        canvas.isPaused = false
        setNeedsLayout()
    }

    private func stackCenter(_ index: Int, titleWidth: CGFloat) -> CGPoint {
        let stackWidth = stackSize + CGFloat(stackCount - 1) * 15
        let group = stackWidth + 8 + titleWidth
        let start = (bounds.width - group) / 2
        let slot = CGFloat(min(index, stackCount - 1))
        return CGPoint(x: start + stackSize / 2 + slot * 15, y: safeTop + Self.titleHeight / 2)
    }

    private func rowCenter(_ index: Int) -> CGPoint {
        let spacing = (bounds.width - 16) / CGFloat(users.count)
        return CGPoint(x: 8 + spacing * (CGFloat(index) + 0.5), y: safeTop + Self.titleHeight + 10 + expandedSize / 2)
    }

    private func place() {
        let titleWidth = title.intrinsicContentSize.width
        let open = springs.map { min(max($0.value, 0), 1.15) }
        let titleOpen = min(max(pull, 0), 1)
        let stackStart = stackCenter(0, titleWidth: titleWidth).x - stackSize / 2
        let collapsedTitleX = stackStart + stackSize + CGFloat(stackCount - 1) * 15 + 8
        let titleX = collapsedTitleX + ((bounds.width - titleWidth) / 2 - collapsedTitleX) * titleOpen
        title.frame = CGRect(x: titleX, y: safeTop, width: titleWidth, height: Self.titleHeight)
        lockButton.frame = CGRect(x: title.frame.maxX + 2, y: safeTop, width: 24, height: Self.titleHeight)

        var shapes: [IslandFluidShape] = []
        for index in avatars.indices.reversed() {
            let t = open[index]
            let start = stackCenter(index, titleWidth: titleWidth)
            let end = rowCenter(index)

            var center = CGPoint.lerp(start, end, t)
            center.y += sin(min(t, 1) * .pi) * 10
            let size = stackSize + (expandedSize - stackSize) * min(t, 1.05)
            let avatar = avatars[index]
            avatar.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            avatar.center = center
            avatar.layer.cornerRadius = size / 2
            avatar.layer.borderWidth = 1.5 + 1.5 * min(t, 1)
            let hiddenInStack = index >= stackCount
            avatar.alpha = hiddenInStack ? islandSmoothstep(0.05, 0.4, t) : 1
            avatar.isUserInteractionEnabled = t > 0.9 || (t < 0.1 && index < stackCount)
            names[index].frame = CGRect(x: end.x - 30, y: end.y + expandedSize / 2 + 6, width: 60, height: 13)
            names[index].alpha = islandSmoothstep(0.7, 1, t)
            guard !seen[index] || t < 0.9 else { continue }
            let ring = size / 2 + 2 + 1.5 * min(t, 1)

            shapes.append(.circle(center: center, radius: ring * avatar.alpha, blend: 14 * (1 - min(t, 1)) + 1))
        }
        canvas.shapes = shapes
    }

    private func step(_ dt: CFTimeInterval) {
        var settled = true
        for index in springs.indices {
            // Later avatars wait a little before they tear off the stack.
            let delay = CGFloat(index) * 0.06
            let target = min(max((pull - delay) / (1 - 0.36), 0), 1)
            springs[index].step(toward: target, deltaTime: dt)
            if !springs[index].isSettled(at: target, tolerance: 0.002) { settled = false }
        }
        place()
        if settled {
            canvas.renderFrame()
            canvas.isPaused = true
        }
    }

    func avatarFrame(_ index: Int, in view: UIView) -> CGRect {
        avatars[index].convert(avatars[index].bounds, to: view)
    }

    func markSeen(_ index: Int) {
        seen[index] = true
        canvas.isPaused = false
    }

    func setAccount(_ index: Int) {
        UIView.transition(with: title, duration: 0.3, options: .transitionCrossDissolve) {
            self.title.text = index == 0 ? "Chats" : "Chats · \(MessengerData.accounts[index].person.name.split(separator: " ")[0])"
        }
        setNeedsLayout()
    }

    func setLock(_ shown: Bool) {
        lockShown = shown
        UIView.animate(withDuration: 0.3) { self.lockButton.alpha = shown ? 1 : 0 }
        if shown { Views.pop(lockButton, scale: 0.4) }
    }

    @objc private func avatarTapped(_ gesture: UITapGestureRecognizer) {
        guard let index = gesture.view?.tag else { return }
        if pull < 0.5 {
            onStackTap?()
            return
        }
        Views.pop(avatars[index], scale: 0.9)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onOpenStory?(index)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // The collapsed stack is small: accept taps around it.
        if pull < 0.1, point.y > safeTop, point.y < safeTop + Self.titleHeight {
            let stack = CGRect(x: stackCenter(0, titleWidth: title.intrinsicContentSize.width).x - 24, y: safeTop,
                               width: 90, height: Self.titleHeight)
            if stack.contains(point) { return avatars[0] }
        }
        return super.hitTest(point, with: event)
    }
}
