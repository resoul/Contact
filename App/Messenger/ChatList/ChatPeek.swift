import UIKit

final class ChatPeek: UIView {
    var onOpen: (() -> Void)?
    var onAction: ((ChatCell.Action) -> Void)?

    private let blur = UIVisualEffectView(effect: nil)
    private let card = UIView()
    private let menu = UIView()
    private let source: CGRect
    private let target: CGRect
    private let chat: Chat

    init(in host: UIView, chat: Chat, from source: CGRect) {
        self.source = source
        self.chat = chat
        let width = host.bounds.width - 32
        let menuHeight: CGFloat = 5 * 46
        let height = min(430, host.bounds.height - host.safeAreaInsets.top - host.safeAreaInsets.bottom - menuHeight - 40)
        target = CGRect(x: 16, y: host.safeAreaInsets.top + 12, width: width, height: height)
        super.init(frame: host.bounds)
        host.addSubview(self)
        blur.frame = bounds
        addSubview(blur)
        blur.contentView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismiss)))

        card.frame = source
        card.layer.cornerRadius = 16
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true
        card.backgroundColor = Palette.wallpaper
        addSubview(card)
        buildPreview()
        card.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(open)))

        menu.backgroundColor = Palette.cell
        menu.layer.cornerRadius = 14
        menu.layer.cornerCurve = .continuous
        menu.clipsToBounds = true
        menu.frame = CGRect(x: target.maxX - 240, y: target.maxY + 10, width: 240, height: menuHeight)
        let items: [(String, String, ChatCell.Action, Bool)] = [
            (chat.unread > 0 ? "Read" : "Unread", "checkmark.message", .read, false),
            (chat.pinned ? "Unpin" : "Pin", "pin", .pin, false),
            (chat.muted ? "Unmute" : "Mute", "bell.slash", .mute, false),
            ("Delete", "trash", .delete, true),
            ("Archive", "archivebox", .archive, false),
        ]
        for (index, item) in items.enumerated() {
            let row = UIButton(type: .system)
            row.frame = CGRect(x: 0, y: CGFloat(index) * 46, width: 240, height: 46)
            var configuration = UIButton.Configuration.plain()
            configuration.title = item.0
            configuration.image = UIImage(systemName: item.1)
            configuration.imagePlacement = .trailing
            configuration.baseForegroundColor = item.3 ? Palette.red : Palette.text
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
            row.configuration = configuration
            row.contentHorizontalAlignment = .fill
            let action = item.2
            row.addAction(UIAction { [weak self] _ in
                self?.close {
                    self?.onAction?(action)
                }
            }, for: .touchUpInside)
            menu.addSubview(row)
            if index < items.count - 1 {
                let line = UIView(frame: CGRect(x: 0, y: CGFloat(index + 1) * 46 - 0.5, width: 240, height: 0.5))
                line.backgroundColor = Palette.separator
                menu.addSubview(line)
            }
        }
        menu.alpha = 0
        menu.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
        addSubview(menu)

        UIView.animate(withDuration: 0.3) { self.blur.effect = UIBlurEffect(style: .systemUltraThinMaterial) }
        UIView.animate(withDuration: 0.55, delay: 0, usingSpringWithDamping: 0.78, initialSpringVelocity: 0) {
            self.card.frame = self.target
            self.layoutPreview()
        }
        UIView.animate(withDuration: 0.45, delay: 0.08, usingSpringWithDamping: 0.7, initialSpringVelocity: 0) {
            self.menu.alpha = 1
            self.menu.transform = .identity
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let previewHeader = UIView()
    private var bubbles: [UIView] = []
    private var bubbleSides: [Bool] = []

    private func buildPreview() {
        previewHeader.backgroundColor = Palette.bar
        card.addSubview(previewHeader)
        let avatar = UIImageView(image: ChannelAvatar.image(for: chat.person, size: 36))
        avatar.frame = CGRect(x: 12, y: 8, width: 36, height: 36)
        previewHeader.addSubview(avatar)
        let name = Views.label(chat.person.name, size: 16, weight: .semibold)
        name.frame = CGRect(x: 58, y: 8, width: 240, height: 20)
        previewHeader.addSubview(name)
        let status = Views.label(chat.online ? "online" : "last seen recently", size: 13,
                                   color: chat.online ? Palette.accent : Palette.secondary)
        status.frame = CGRect(x: 58, y: 28, width: 240, height: 16)
        previewHeader.addSubview(status)
        let lines: [(String, Bool)] = [("Hey! How are you?", false), ("Great, building a mini-Telegram demo 🚀", true),
                                       ("Can I see it?", false), ("I’ll send a video tonight", true),
                                       (chat.message.isEmpty ? "👋" : chat.message, chat.outgoingRead != nil)]
        bubbleSides = lines.map(\.1)
        for (text, outgoing) in lines {
            let bubble = MessageBubble(text: text, outgoing: outgoing, time: "20:4\(bubbles.count)", read: true)
            card.addSubview(bubble)
            bubbles.append(bubble)
        }
        layoutPreview()
    }

    private func layoutPreview() {
        previewHeader.frame = CGRect(x: 0, y: 0, width: target.width, height: 52)
        var y = target.height - 10
        for (bubble, outgoing) in zip(bubbles.reversed(), bubbleSides.reversed()) {
            let size = (bubble as! MessageBubble).fittingSize(maxWidth: target.width * 0.75)
            y -= size.height + 6
            bubble.frame = CGRect(x: outgoing ? target.width - 10 - size.width : 10, y: y, width: size.width, height: size.height)
        }
    }

    @objc private func open() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onOpen?()
        UIView.animate(withDuration: 0.25, animations: { self.alpha = 0 }, completion: { _ in self.removeFromSuperview() })
    }

    @objc private func dismiss() {
        close(nil)
    }

    private func close(_ completion: (() -> Void)?) {
        isUserInteractionEnabled = false
        UIView.animate(withDuration: 0.2) {
            self.menu.alpha = 0
            self.menu.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        }
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, animations: {
            self.card.frame = self.source
            self.card.alpha = 0
            self.blur.effect = nil
        }, completion: { _ in
            self.removeFromSuperview()
            completion?()
        })
    }
}
