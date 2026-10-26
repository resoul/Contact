import UIKit
import AsyncDisplayKit
import AvatarUI
import ListUI

/// Texture row content is measured before it reaches the main thread. UIKit is
/// used only for the swipe buttons, which are created when a reveal starts.
final class ChatCell: ASDisplayNode, UIGestureRecognizerDelegate {
    enum Action { case read, pin, mute, delete, archive }

    var onAction: ((Action) -> Void)?
    var onSwipeBegan: (() -> Void)?
    var onPeek: (() -> Void)?

    let slider = ASDisplayNode()
    private let avatar = AvatarUI.AvatarNode()
    private let onlineDot = ASDisplayNode()
    private var prepared: PreparedLayout?
    private var chat: Chat?
    private var pan: UIPanGestureRecognizer!
    private var hold: UILongPressGestureRecognizer!
    private var swipeEnabled = true
    private var leftButtons: [SwipeButton] = []
    private var rightButtons: [SwipeButton] = []
    private var offset: CGFloat = 0
    private var startOffset: CGFloat = 0
    private var full = false
    private var viewportVisible = false
    private var viewportScrolling = true
    private var revealing = false
    private let buttonWidth: CGFloat = 76

    var interactionPanGestures: [UIGestureRecognizer] { pan.map { [$0] } ?? [] }
    var selectionFailureGestures: [UIGestureRecognizer] { [pan, hold].compactMap { $0 } }
    var isRevealOpen: Bool { abs(offset) > 0.5 }

    override init() {
        super.init()
        avatar.setPlaybackEnabled(false)
        addSubnode(slider)
        slider.addSubnode(avatar)
        avatar.isUserInteractionEnabled = false
        onlineDot.isLayerBacked = true
        onlineDot.backgroundColor = Palette.online
        onlineDot.cornerRadius = 7.8
        onlineDot.borderWidth = 2.5
        onlineDot.isHidden = true
        slider.addSubnode(onlineDot)
    }

    override func didLoad() {
        super.didLoad()
        clipsToBounds = true
        pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.delegate = self
        pan.isEnabled = swipeEnabled
        slider.view.addGestureRecognizer(pan)
        hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        hold.minimumPressDuration = 0.4
        slider.view.addGestureRecognizer(hold)
    }

    func configure(_ chat: Chat, swipeEnabled: Bool, theme: ListTheme) {
        self.chat = chat
        self.swipeEnabled = swipeEnabled
        if isNodeLoaded { pan.isEnabled = swipeEnabled }
        if !swipeEnabled { close(animated: false) }
        slider.backgroundColor = theme.rowBackground
        avatar.apply(AvatarProvider.descriptor(for: chat.person, peerID: chat.id), presentation: .chatList)
        onlineDot.isHidden = !chat.online || chat.kind != .person
        onlineDot.borderColor = theme.rowBackground.cgColor
        // Existing controls change only on a model update, never on a scroll tick.
        if !leftButtons.isEmpty { updateButtons(chat) }
    }

    func apply(_ layout: PreparedLayout) {
        let previous = prepared
        prepared?.content.removeFromSupernode()
        prepared = layout
        slider.insertSubnode(layout.content, belowSubnode: avatar)
        if let previous, previous.unread != layout.unread, layout.unread > 0,
           let badge = layout.badge, !UIAccessibility.isReduceMotionEnabled {
            let pop = CASpringAnimation(keyPath: "transform.scale")
            pop.fromValue = previous.unread == 0 ? 0.3 : 1.15
            pop.toValue = 1
            pop.damping = 12
            pop.duration = 0.45
            badge.layer.add(pop, forKey: "unread")
        }
        if let previous, previous.message != layout.message, !previous.message.isEmpty,
           !UIAccessibility.isReduceMotionEnabled {
            let transition = CATransition()
            transition.type = .push
            transition.subtype = .fromTop
            transition.duration = 0.3
            layout.messageNode.layer.add(transition, forKey: "message")
        }
        setNeedsLayout()
    }

    override func layout() {
        super.layout()
        slider.frame = bounds.offsetBy(dx: offset, dy: 0)
        avatar.frame = CGRect(x: 12, y: (bounds.height - 58) / 2, width: 58, height: 58)
        onlineDot.frame = CGRect(x: 55.3, y: (bounds.height - 58) / 2 + 43.3, width: 15.6, height: 15.6)
        layoutButtons()
    }

    func prepareForReuse() {
        viewportVisible = false
        viewportScrolling = true
        revealing = false
        updateAvatarPlayback()
        close(animated: false)
        prepared?.content.removeFromSupernode()
        prepared = nil
        chat = nil
        avatar.prepareForReuse()
        onlineDot.isHidden = true
        slider.alpha = 1
        alpha = 1
        transform = CATransform3DIdentity
        leftButtons.forEach { $0.removeFromSuperview() }
        rightButtons.forEach { $0.removeFromSuperview() }
        leftButtons = []
        rightButtons = []
    }

    func updateViewport(isVisible: Bool, isScrolling: Bool) {
        viewportVisible = isVisible
        viewportScrolling = isScrolling
        updateAvatarPlayback()
    }

    private func updateAvatarPlayback() {
        let visible = viewportVisible && isInHierarchy
        avatar.setPlaybackEnabled(visible && !viewportScrolling && !revealing && !isRevealOpen,
                                  releaseResources: !visible)
    }

    override func didEnterHierarchy() {
        super.didEnterHierarchy()
        avatar.setVisible(true)
        updateAvatarPlayback()
    }
    override func didExitHierarchy() {
        super.didExitHierarchy()
        avatar.setPlaybackEnabled(false, releaseResources: true)
        avatar.setVisible(false)
    }

    private func ensureButtons() {
        guard leftButtons.isEmpty, let chat else { return }
        leftButtons = [SwipeButton(title: "Read", symbol: "checkmark.message.fill", color: Palette.accent),
                       SwipeButton(title: "Pin", symbol: "pin.fill", color: Palette.online)]
        rightButtons = [SwipeButton(title: "Mute", symbol: "bell.slash.fill", color: Palette.orange),
                        SwipeButton(title: "Delete", symbol: "trash.fill", color: Palette.red),
                        SwipeButton(title: "Archive", symbol: "archivebox.fill", color: UIColor(white: 0.6, alpha: 1))]
        let actions: [Action] = [.read, .pin, .mute, .delete, .archive]
        for (button, action) in zip(leftButtons + rightButtons, actions) {
            button.addAction(UIAction { [weak self] _ in self?.onAction?(action) }, for: .touchUpInside)
            view.insertSubview(button, belowSubview: slider.view)
        }
        updateButtons(chat)
    }

    private func updateButtons(_ chat: Chat) {
        leftButtons[0].set(title: chat.unread > 0 ? "Read" : "Unread",
                           symbol: chat.unread > 0 ? "checkmark.message.fill" : "message.badge.fill")
        leftButtons[1].set(title: chat.pinned ? "Unpin" : "Pin", symbol: chat.pinned ? "pin.slash.fill" : "pin.fill")
        rightButtons[0].set(title: chat.muted ? "Unmute" : "Mute", symbol: chat.muted ? "bell.fill" : "bell.slash.fill")
    }

    private func layoutButtons() {
        let reveal = abs(offset)
        for (index, button) in rightButtons.enumerated() {
            let share = reveal / CGFloat(rightButtons.count)
            var frame = CGRect(x: bounds.width - reveal + share * CGFloat(index), y: 0, width: share + 1, height: bounds.height)
            if full, index == rightButtons.count - 1 { frame = CGRect(x: bounds.width - reveal, y: 0, width: reveal, height: bounds.height) }
            button.frame = frame
            button.isHidden = offset >= 0
        }
        for (index, button) in leftButtons.enumerated() {
            let share = reveal / CGFloat(leftButtons.count)
            var frame = CGRect(x: reveal - share * CGFloat(index + 1), y: 0, width: share + 1, height: bounds.height)
            if full, index == 0 { frame = CGRect(x: 0, y: 0, width: reveal, height: bounds.height) }
            button.frame = frame
            button.isHidden = offset <= 0
        }
    }

    override func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        guard gesture === pan else { return true }
        let velocity = pan.velocity(in: view)
        return swipeEnabled && abs(velocity.x) > abs(velocity.y) * 1.3
    }

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            revealing = true
            updateAvatarPlayback()
            ensureButtons()
            startOffset = offset
            onSwipeBegan?()
        case .changed:
            var proposed = startOffset + gesture.translation(in: view).x
            let limit = buttonWidth * CGFloat(proposed < 0 ? rightButtons.count : leftButtons.count)
            if abs(proposed) > limit { proposed = (limit + (abs(proposed) - limit) * 0.75) * (proposed < 0 ? -1 : 1) }
            offset = proposed
            let nowFull = abs(offset) > bounds.width * 0.58
            if nowFull != full {
                full = nowFull
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0) { self.layoutButtons() }
            }
            layout()
        case .ended, .cancelled:
            revealing = false
            let velocity = gesture.velocity(in: view).x
            if full, gesture.state == .ended {
                full = false
                onAction?(offset < 0 ? .archive : .read)
                return
            }
            let count = CGFloat(offset < 0 ? rightButtons.count : leftButtons.count)
            let open = gesture.state != .cancelled && abs(offset) > buttonWidth * count * 0.45 && (offset < 0 ? velocity < 300 : velocity > -300)
            settle(to: open ? buttonWidth * count * (offset < 0 ? -1 : 1) : 0, animated: true)
        default: break
        }
    }

    private func settle(to target: CGFloat, animated: Bool) {
        guard offset != target else { updateAvatarPlayback(); return }
        offset = target
        updateAvatarPlayback()
        if animated {
            UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0) { self.layout() }
        } else {
            if isNodeLoaded { slider.view.layer.removeAllAnimations() }
            layout()
        }
    }

    func close(animated: Bool = true) { full = false; settle(to: 0, animated: animated) }

    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, offset == 0 else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onPeek?()
    }

    func dissolve(_ completion: @escaping () -> Void) {
        offset = 0
        layout()
        rightButtons.forEach { $0.isHidden = true }
        DustAnimator.blowAway(slider.view, wind: CGVector(dx: 90, dy: -40), completion: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: completion)
    }
}

extension ChatCell {
    struct PreparedLayout {
        let content: ASDisplayNode
        let messageNode: ASTextNode
        let badge: ASDisplayNode?
        let unread: Int
        let message: String
    }

    /// Runs on ListUI's bounded layout queue. These nodes have no loaded views/layers.
    static func prepare(_ chat: Chat, width: CGFloat, theme: ListTheme, traits: UITraitCollection) -> PreparedLayout {
        assert(!Thread.isMainThread)
        let content = ASDisplayNode()
        content.isLayerBacked = true
        content.frame = CGRect(x: 0, y: 0, width: width, height: 76)

        func text(_ value: String, size: CGFloat, weight: UIFont.Weight = .regular,
                  color: UIColor, width: CGFloat, lines: UInt = 1) -> ASTextNode {
            let node = ASTextNode()
            node.isLayerBacked = true
            node.maximumNumberOfLines = lines
            node.truncationMode = .byTruncatingTail
            node.attributedText = NSAttributedString(string: value, attributes: [
                .font: UIFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color,
            ])
            let measured = node.layoutThatFits(ASSizeRange(min: .zero, max: CGSize(width: max(1, width), height: lines == 1 ? 24 : 40))).size
            node.frame = CGRect(origin: .zero, size: measured)
            return node
        }
        func icon(_ symbol: String, size: CGFloat, color: UIColor, frame: CGRect) -> ASImageNode {
            let node = ASImageNode()
            node.isLayerBacked = true
            node.image = RowSymbols.image(symbol, size: size, color: color, scale: traits.displayScale)
            node.contentMode = .center
            node.frame = frame
            content.addSubnode(node)
            return node
        }

        let textX: CGFloat = 82
        let time = text(chat.time, size: 14, color: theme.secondary, width: max(1, width - textX - 14))
        time.frame.origin = CGPoint(x: width - 14 - time.frame.width, y: 10)
        content.addSubnode(time)
        let checksX = time.frame.minX - 22
        if let read = chat.outgoingRead {
            _ = icon("checkmark", size: 11, color: theme.accent, frame: CGRect(x: checksX, y: 12, width: 14, height: 14))
            if read { _ = icon("checkmark", size: 11, color: theme.accent, frame: CGRect(x: checksX + 5, y: 12, width: 14, height: 14)) }
        }
        let rightLimit = (chat.outgoingRead == nil ? time.frame.minX : checksX) - 6
        var titleX = textX
        let symbol: String?
        switch chat.kind {
        case .group: symbol = "person.2.fill"
        case .channel: symbol = "megaphone.fill"
        case .bot: symbol = "cpu"
        case .person: symbol = nil
        }
        if let symbol {
            _ = icon(symbol, size: 11, color: theme.primary, frame: CGRect(x: titleX, y: 12, width: 16, height: 16))
            titleX += 19
        }
        let name = text(chat.person.name, size: 16, weight: .semibold, color: theme.primary,
                        width: rightLimit - titleX - (chat.muted ? 18 : 0))
        name.frame.origin = CGPoint(x: titleX, y: 9)
        content.addSubnode(name)
        if chat.muted {
            _ = icon("speaker.slash.fill", size: 11, color: theme.secondary,
                     frame: CGRect(x: name.frame.maxX + 4, y: 12, width: 14, height: 14))
        }

        var badge: ASDisplayNode?
        var messageRight = width - 14
        if chat.unread > 0 {
            let number = text(FeedFormat.count(chat.unread), size: 14, weight: .semibold, color: .white, width: max(22, width / 3))
            let badgeWidth = max(22, number.frame.width + 14)
            let background = ASDisplayNode()
            background.isLayerBacked = true
            background.backgroundColor = chat.muted ? Palette.muted.resolvedColor(with: traits) : theme.accent
            background.cornerRadius = 11
            background.frame = CGRect(x: width - 14 - badgeWidth, y: 40, width: badgeWidth, height: 22)
            number.frame.origin = CGPoint(x: (badgeWidth - number.frame.width) / 2, y: (22 - number.frame.height) / 2)
            background.addSubnode(number)
            content.addSubnode(background)
            badge = background
            messageRight = background.frame.minX - 8
        } else if chat.pinned {
            _ = icon("pin.fill", size: 12, color: theme.secondary, frame: CGRect(x: width - 30, y: 42, width: 16, height: 16))
            messageRight = width - 36
        }
        let message = text(chat.message, size: 15, color: theme.secondary, width: messageRight - textX, lines: 2)
        message.frame.origin = CGPoint(x: textX, y: 30)
        content.addSubnode(message)
        let separator = ASDisplayNode()
        separator.isLayerBacked = true
        separator.backgroundColor = theme.separator
        separator.frame = CGRect(x: textX, y: 75.5, width: max(0, width - textX), height: 0.5)
        content.addSubnode(separator)
        ASTraitCollectionPropagateDown(content, ASPrimitiveTraitCollectionFromUITraitCollection(traits))
        return PreparedLayout(content: content, messageNode: message, badge: badge, unread: chat.unread, message: chat.message)
    }
}

private enum RowSymbols {
    private static let images = NSCache<NSString, UIImage>()
    static func image(_ name: String, size: CGFloat, color: UIColor, scale: CGFloat) -> UIImage? {
        let key = "\(name)|\(size)|\(color)|\(scale)" as NSString
        if let image = images.object(forKey: key) { return image }
        guard let symbol = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: .semibold))?
            .withTintColor(color, renderingMode: .alwaysOriginal) else { return nil }
        // ASImageNode needs bitmap contents; SF Symbols can have no CGImage.
        let format = UIGraphicsImageRendererFormat()
        format.scale = max(1, scale)
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: symbol.size, format: format).image { _ in symbol.draw(at: .zero) }
        images.setObject(image, forKey: key)
        return image
    }
}
