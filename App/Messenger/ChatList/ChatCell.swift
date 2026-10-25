import UIKit

final class ChatCell: UITableViewCell {
    enum Action { case read, pin, mute, delete, archive }

    var onAction: ((Action) -> Void)?
    var onSwipeBegan: (() -> Void)?
    var onPeek: (() -> Void)?

    let slider = UIView()
    private let avatar = AvatarView()
    private let name = Views.label(size: 16, weight: .semibold)
    private let mutedIcon = UIImageView(image: UIImage(systemName: "speaker.slash.fill",
                                                       withConfiguration: UIImage.SymbolConfiguration(pointSize: 11)))
    private let kindIcon = UIImageView()
    private let message = Views.label(size: 15, color: Palette.secondary)
    private let typingLabel = Views.label("typing", size: 15, color: Palette.accent)
    private let dots = ChatTypingDots()
    private let time = Views.label(size: 14, color: Palette.secondary)
    private let checks = ChecksView()
    private let badge = Badge()
    private let pinIcon = UIImageView(image: UIImage(systemName: "pin.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12)))
    private let separator = UIView()

    private var leftButtons: [SwipeButton] = []
    private var rightButtons: [SwipeButton] = []
    private var offset: CGFloat = 0
    private var startOffset: CGFloat = 0
    private var full = false
    private var isTyping = false
    private let buttonWidth: CGFloat = 76

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.clipsToBounds = true
        slider.backgroundColor = Palette.background
        for view in [avatar, name, mutedIcon, kindIcon, message, typingLabel, dots, time, checks, badge, pinIcon, separator] {
            slider.addSubview(view)
        }
        mutedIcon.tintColor = Palette.secondary
        kindIcon.tintColor = Palette.text
        pinIcon.tintColor = Palette.muted
        separator.backgroundColor = Palette.separator
        message.numberOfLines = 2
        checks.tint = Palette.accent
        typingLabel.alpha = 0
        dots.alpha = 0

        leftButtons = [SwipeButton(title: "Read", symbol: "checkmark.message.fill", color: Palette.accent),
                       SwipeButton(title: "Pin", symbol: "pin.fill", color: Palette.online)]
        rightButtons = [SwipeButton(title: "Mute", symbol: "bell.slash.fill", color: Palette.orange),
                        SwipeButton(title: "Delete", symbol: "trash.fill", color: Palette.red),
                        SwipeButton(title: "Archive", symbol: "archivebox.fill", color: UIColor(white: 0.6, alpha: 1))]
        let leftActions: [Action] = [.read, .pin], rightActions: [Action] = [.mute, .delete, .archive]
        for (button, action) in zip(leftButtons + rightButtons, leftActions + rightActions) {
            button.addAction(UIAction { [weak self] _ in self?.onAction?(action) }, for: .touchUpInside)
            contentView.addSubview(button)
        }
        contentView.addSubview(slider)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.delegate = self
        slider.addGestureRecognizer(pan)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        hold.minimumPressDuration = 0.4
        slider.addGestureRecognizer(hold)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        offset = 0
        full = false
        slider.alpha = 1
        alpha = 1
        transform = .identity
        setNeedsLayout()
    }

    func configure(_ chat: Chat, typing: Bool, animated: Bool) {
        accessibilityIdentifier = "contact.chat.\(chat.id)"
        avatar.set(chat.person, size: 58)
        avatar.online = chat.online && chat.kind == .person
        name.text = chat.person.name
        mutedIcon.isHidden = !chat.muted
        switch chat.kind {
        case .group: kindIcon.image = UIImage(systemName: "person.2.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11))
        case .channel: kindIcon.image = UIImage(systemName: "megaphone.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11))
        case .bot: kindIcon.image = UIImage(systemName: "cpu", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11))
        case .person: kindIcon.image = nil
        }
        if animated, message.text != chat.message, !message.text.isNilOrEmpty {
            let fade = CATransition()
            fade.type = .push
            fade.subtype = .fromTop
            fade.duration = 0.3
            message.layer.add(fade, forKey: "text")
        }
        message.text = chat.message
        time.text = chat.time
        checks.isHidden = chat.outgoingRead == nil
        checks.set(read: chat.outgoingRead == true, animated: animated)
        badge.muted = chat.muted
        badge.set(chat.unread, animated: animated)
        pinIcon.isHidden = !(chat.pinned && chat.unread == 0)
        leftButtons[0].set(title: chat.unread > 0 ? "Read" : "Unread",
                           symbol: chat.unread > 0 ? "checkmark.message.fill" : "message.badge.fill")
        leftButtons[1].set(title: chat.pinned ? "Unpin" : "Pin", symbol: chat.pinned ? "pin.slash.fill" : "pin.fill")
        rightButtons[0].set(title: chat.muted ? "Unmute" : "Mute", symbol: chat.muted ? "bell.fill" : "bell.slash.fill")
        setTyping(typing, animated: animated)
        setNeedsLayout()
    }

    private func setTyping(_ typing: Bool, animated: Bool) {
        guard typing != isTyping || !animated else { return }
        isTyping = typing
        let change = {
            self.message.alpha = typing ? 0 : 1
            self.typingLabel.alpha = typing ? 1 : 0
            self.dots.alpha = typing ? 1 : 0
        }
        animated ? UIView.animate(withDuration: 0.25, animations: change) : change()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = contentView.bounds.width, height = contentView.bounds.height
        slider.frame = CGRect(x: offset, y: 0, width: width, height: height)
        avatar.frame = CGRect(x: 12, y: (height - 58) / 2, width: 58, height: 58)
        let textX: CGFloat = 82
        time.sizeToFit()
        time.frame.origin = CGPoint(x: width - 14 - time.bounds.width, y: 10)
        checks.frame = CGRect(x: time.frame.minX - 22, y: 12, width: 20, height: 14)
        let rightLimit = (checks.isHidden ? time.frame.minX : checks.frame.minX) - 6
        var x = textX
        if kindIcon.image != nil {
            kindIcon.frame = CGRect(x: x, y: 12, width: 16, height: 16)
            x += 19
        }
        name.sizeToFit()
        name.frame = CGRect(x: x, y: 9, width: min(name.bounds.width, rightLimit - x - (mutedIcon.isHidden ? 0 : 18)), height: 20)
        mutedIcon.frame = CGRect(x: name.frame.maxX + 4, y: 12, width: 14, height: 14)
        let badgeWidth = badge.width
        badge.frame = CGRect(x: width - 14 - badgeWidth, y: 40, width: badgeWidth, height: 22)
        pinIcon.frame = CGRect(x: width - 30, y: 42, width: 16, height: 16)
        let messageRight = badgeWidth > 0 ? badge.frame.minX - 8 : (pinIcon.isHidden ? width - 14 : pinIcon.frame.minX - 6)
        message.frame = CGRect(x: textX, y: 30, width: messageRight - textX, height: 40)
        message.sizeToFit()
        message.frame.size.width = messageRight - textX
        typingLabel.frame = CGRect(x: textX, y: 31, width: 76, height: 20)
        dots.frame = CGRect(x: textX + 74, y: 37, width: 24, height: 10)
        separator.frame = CGRect(x: textX, y: height - 0.5, width: width - textX, height: 0.5)
        layoutButtons()
    }

    private func layoutButtons() {
        let width = contentView.bounds.width, height = contentView.bounds.height
        let reveal = abs(offset)
        // Buttons share the revealed strip; on a full swipe the edge one takes all of it.
        for (index, button) in rightButtons.enumerated() {
            let share = reveal / CGFloat(rightButtons.count)
            var frame = CGRect(x: width - reveal + share * CGFloat(index), y: 0, width: share + 1, height: height)
            if full, index == rightButtons.count - 1 { frame = CGRect(x: width - reveal, y: 0, width: reveal, height: height) }
            button.frame = frame
            button.isHidden = offset >= 0
        }
        for (index, button) in leftButtons.enumerated() {
            let share = reveal / CGFloat(leftButtons.count)
            var frame = CGRect(x: reveal - share * CGFloat(index + 1), y: 0, width: share + 1, height: height)
            if full, index == 0 { frame = CGRect(x: 0, y: 0, width: reveal, height: height) }
            button.frame = frame
            button.isHidden = offset <= 0
        }
        contentView.bringSubviewToFront(full ? (offset < 0 ? rightButtons.last! : leftButtons[0]) : slider)
        contentView.bringSubviewToFront(slider)
    }

    override func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        // Also asked about the table's own pan (it is an ancestor's): only judge the row's.
        guard let pan = gesture as? UIPanGestureRecognizer, pan.view === slider else { return true }
        let velocity = pan.velocity(in: self)
        return abs(velocity.x) > abs(velocity.y) * 1.3
    }

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        let width = contentView.bounds.width
        switch gesture.state {
        case .began:
            startOffset = offset
            onSwipeBegan?()
        case .changed:
            var proposed = startOffset + gesture.translation(in: self).x
            // A little resistance past the buttons' width.
            let limit = buttonWidth * CGFloat(proposed < 0 ? rightButtons.count : leftButtons.count)
            if abs(proposed) > limit {
                proposed = (limit + (abs(proposed) - limit) * 0.75) * (proposed < 0 ? -1 : 1)
            }
            offset = proposed
            let nowFull = abs(offset) > width * 0.58
            if nowFull != full {
                full = nowFull
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
                    self.layoutButtons()
                }
            }
            layoutSubviews()
        case .ended, .cancelled:
            let velocity = gesture.velocity(in: self).x
            if full {
                let action: Action = offset < 0 ? .archive : .read
                full = false
                if action == .archive {
                    onAction?(.archive)
                } else {
                    onAction?(.read)
                }
                return
            }
            let count = CGFloat(offset < 0 ? rightButtons.count : leftButtons.count)
            let open = abs(offset) > buttonWidth * count * 0.45 && (offset < 0 ? velocity < 300 : velocity > -300)
            settle(to: open ? buttonWidth * count * (offset < 0 ? -1 : 1) : 0)
        default:
            break
        }
    }

    private func settle(to target: CGFloat) {
        offset = target
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0) {
            self.layoutSubviews()
        }
    }

    func close() {
        full = false
        settle(to: 0)
    }

    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, offset == 0 else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onPeek?()
    }

    /// The row crumbles to dust, then `completion` removes it.
    func dissolve(_ completion: @escaping () -> Void) {
        offset = 0
        layoutSubviews()
        rightButtons.forEach { $0.isHidden = true }
        DustAnimator.blowAway(slider, wind: CGVector(dx: 90, dy: -40), completion: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: completion)
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        UIView.animate(withDuration: highlighted ? 0 : 0.3) {
            self.slider.backgroundColor = highlighted ? Palette.fill : Palette.background
        }
    }
}

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool { self?.isEmpty ?? true }
}
