//
//  MTChatExtras.swift
//  controller
//
//  Pieces of the Mini-Telegram chat around the messages: the long-press menu (the bubble lifts
//  over a blur, reactions pop in above it, actions below), the scroll-down button with its unread
//  counter, and the incoming "typing" bubble that later grows into the real message.
//

import UIKit

// MARK: - Message menu

final class MTMessageMenu: UIView {
    enum Action {
        case reply, copy, edit, forward, vanish, select, delete
    }

    var onReaction: ((String, CGPoint) -> Void)?
    var onAction: ((Action) -> Void)?
    var onClose: (() -> Void)?

    private let blur = UIVisualEffectView(effect: nil)
    private let lifted: UIView
    private let source: CGRect
    private var target: CGRect
    private let reactionsBar = UIView()
    private var emojiViews: [UILabel] = []
    private let menu = UIView()

    init(in host: UIView, bubble: UIView, outgoing: Bool, actions: [(String, String, Action)]) {
        source = bubble.convert(bubble.bounds, to: host)
        lifted = bubble.snapshotView(afterScreenUpdates: false) ?? UIView()
        target = source
        super.init(frame: host.bounds)
        host.addSubview(self)
        blur.frame = bounds
        blur.contentView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissTapped)))
        addSubview(blur)

        // Keep the lifted bubble, the reactions above it and the menu below it on screen.
        let barHeight: CGFloat = 48, rowHeight: CGFloat = 44
        let menuHeight = rowHeight * CGFloat(actions.count)
        let top = host.safeAreaInsets.top + 12 + barHeight + 8
        let bottom = host.bounds.height - host.safeAreaInsets.bottom - 12 - menuHeight - 8
        let height = min(source.height, bottom - top)
        target.size.height = height
        target.origin.y = min(max(source.minY, top), bottom - height)

        lifted.frame = source
        lifted.layer.shadowColor = UIColor.black.cgColor
        lifted.layer.shadowOpacity = 0.25
        lifted.layer.shadowRadius = 14
        addSubview(lifted)

        let itemWidth = min(40, (bounds.width - 36) / CGFloat(MTReactions.all.count))
        let barWidth = CGFloat(MTReactions.all.count) * itemWidth + 12
        let barX = min(max(12, outgoing ? target.maxX - barWidth : target.minX), bounds.width - barWidth - 12)
        reactionsBar.frame = CGRect(x: barX, y: target.minY - barHeight - 8, width: barWidth, height: barHeight)
        reactionsBar.backgroundColor = MTPalette.cell
        reactionsBar.layer.cornerRadius = barHeight / 2
        reactionsBar.layer.shadowColor = UIColor.black.cgColor
        reactionsBar.layer.shadowOpacity = 0.2
        reactionsBar.layer.shadowRadius = 10
        reactionsBar.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
        reactionsBar.alpha = 0
        addSubview(reactionsBar)
        for (index, emoji) in MTReactions.all.enumerated() {
            let label = UILabel(frame: CGRect(x: 6 + CGFloat(index) * itemWidth, y: 4, width: itemWidth, height: 40))
            label.text = emoji
            label.font = .systemFont(ofSize: 28)
            label.textAlignment = .center
            label.isUserInteractionEnabled = true
            label.isAccessibilityElement = true
            label.accessibilityLabel = emoji == MTReactions.gas ? "Газ" : emoji
            label.accessibilityTraits = .button
            label.tag = index
            label.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
            label.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(emojiTapped(_:))))
            reactionsBar.addSubview(label)
            emojiViews.append(label)
        }

        let menuWidth: CGFloat = 230
        let menuX = outgoing ? max(12, target.maxX - menuWidth) : min(target.minX, bounds.width - menuWidth - 12)
        menu.frame = CGRect(x: menuX, y: target.maxY + 8, width: menuWidth, height: menuHeight)
        menu.backgroundColor = MTPalette.cell
        menu.layer.cornerRadius = 14
        menu.layer.cornerCurve = .continuous
        menu.clipsToBounds = true
        menu.alpha = 0
        menu.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
        for (index, item) in actions.enumerated() {
            let row = UIButton(type: .system)
            row.frame = CGRect(x: 0, y: CGFloat(index) * rowHeight, width: menuWidth, height: rowHeight)
            var configuration = UIButton.Configuration.plain()
            configuration.title = item.0
            configuration.image = UIImage(systemName: item.1)
            configuration.imagePlacement = .trailing
            configuration.baseForegroundColor = item.2 == .delete ? MTPalette.red : MTPalette.text
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
            row.configuration = configuration
            row.contentHorizontalAlignment = .fill
            let action = item.2
            row.addAction(UIAction { [weak self] _ in
                self?.close()
                self?.onAction?(action)
            }, for: .touchUpInside)
            menu.addSubview(row)
            if index < actions.count - 1 {
                let line = UIView(frame: CGRect(x: 0, y: CGFloat(index + 1) * rowHeight - 0.5, width: menuWidth, height: 0.5))
                line.backgroundColor = MTPalette.separator
                menu.addSubview(line)
            }
        }
        addSubview(menu)

        UIView.animate(withDuration: 0.3) { self.blur.effect = UIBlurEffect(style: .systemUltraThinMaterial) }
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0) {
            self.lifted.frame = self.target
            self.lifted.transform = CGAffineTransform(scaleX: 1.03, y: 1.03)
        }
        UIView.animate(withDuration: 0.45, delay: 0.05, usingSpringWithDamping: 0.65, initialSpringVelocity: 0) {
            self.reactionsBar.transform = .identity
            self.reactionsBar.alpha = 1
            self.menu.alpha = 1
            self.menu.transform = .identity
        }
        // The emoji pop in one after another.
        for (index, label) in emojiViews.enumerated() {
            UIView.animate(withDuration: 0.5, delay: 0.1 + Double(index) * 0.035, usingSpringWithDamping: 0.5,
                           initialSpringVelocity: 0.6) {
                label.transform = .identity
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func emojiTapped(_ gesture: UITapGestureRecognizer) {
        guard let label = gesture.view as? UILabel, let emoji = label.text else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let point = label.convert(label.bounds.center, to: superview)
        label.alpha = 0
        close()
        onReaction?(emoji, point)
    }

    @objc private func dismissTapped() {
        close()
    }

    private func close() {
        isUserInteractionEnabled = false
        onClose?()
        UIView.animate(withDuration: 0.2) {
            self.menu.alpha = 0
            self.menu.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
            self.reactionsBar.alpha = 0
            self.reactionsBar.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        }
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, animations: {
            self.lifted.transform = .identity
            self.lifted.frame = self.source
            self.blur.effect = nil
        }, completion: { _ in self.removeFromSuperview() })
    }
}

// MARK: - Scroll-down button

/// A round button that slides in when the chat is scrolled up, counting messages that arrived
/// below meanwhile.
final class MTScrollDownButton: UIControl {
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
    private let arrow = UIImageView(image: UIImage(systemName: "chevron.down",
                                                   withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)))
    private let badge = MTBadge()
    private(set) var shown = false
    private(set) var count = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        blur.layer.cornerRadius = 21
        blur.clipsToBounds = true
        blur.isUserInteractionEnabled = false
        addSubview(blur)
        arrow.tintColor = MTPalette.secondary
        arrow.contentMode = .center
        addSubview(arrow)
        badge.isUserInteractionEnabled = false
        badge.set(0, animated: false)
        addSubview(badge)
        alpha = 0
        transform = CGAffineTransform(translationX: 0, y: 60).scaledBy(x: 0.5, y: 0.5)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        blur.frame = bounds
        arrow.frame = bounds
        badge.frame = CGRect(x: (bounds.width - badge.width) / 2, y: -12, width: badge.width, height: 22)
    }

    func setShown(_ shown: Bool) {
        guard shown != self.shown else { return }
        self.shown = shown
        if !shown { setCount(0) }
        UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0) {
            self.alpha = shown ? 1 : 0
            self.transform = shown ? .identity : CGAffineTransform(translationX: 0, y: 60).scaledBy(x: 0.5, y: 0.5)
        }
    }

    func setCount(_ count: Int) {
        self.count = count
        badge.set(count, animated: true)
        setNeedsLayout()
        if count > 0 { MTViews.pop(self, scale: 1.12) }
    }
}

// MARK: - Typing bubble

/// The other side's "typing" bubble at the bottom of the chat (the table's footer).
final class MTTypingFooter: UIView {
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
            self.fill.update(in: self.bubble)
    }

    let bubble = UIView()
    private let fill = MTBubbleFill(style: MTBubbleStyle(outgoing: false), color: MTPalette.incoming)
    private let dots = MTTypingDots()

    static let bubbleFrame = CGRect(x: 14, y: 5, width: 62, height: 36)

    override init(frame: CGRect) {
        super.init(frame: frame)
        bubble.frame = Self.bubbleFrame
        fill.attach(to: bubble)
        fill.update(in: bubble)
        addSubview(bubble)
        dots.color = MTPalette.secondary
        dots.frame = CGRect(x: 19, y: 13, width: 24, height: 10)
        bubble.addSubview(dots)

    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        fill.update(in: bubble)
    }

    func appear() {
        bubble.layer.anchorPoint = CGPoint(x: 0, y: 1)
        bubble.frame = Self.bubbleFrame
        bubble.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
        bubble.alpha = 0
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0) {
            self.bubble.transform = .identity
            self.bubble.alpha = 1
        }
    }
}
