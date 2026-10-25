//
//  ChannelPostView.swift
//  controller
//
//  One channel post, laid out like Telegram's: the channel name, an optional quote, the text (with
//  an ink spoiler), reaction chips, views and time, and the comments row with the liquid avatar
//  stack; the share button sits outside the bubble. It reports gestures to its owner, which runs
//  the effects that leave the post (picker, flights, comments sheet, forwarding).
//

import UIKit

final class ChannelPostView: UIView, UIGestureRecognizerDelegate {
    private(set) var post: ChannelPost

    let bubble = UIView()
    let chips: ReactionChipsView
    let avatars: LiquidAvatarStack
    let forwardButton = UIView()
    private let content = UIStackView()
    private var communityContext: CommunityContextNoteView?

    func setCommunityContext(expanded: Bool, onToggle: ((Bool) -> Void)? = nil) {
        if communityContext == nil {
            let note = CommunityContextNoteView(expanded: expanded)
            content.addArrangedSubview(note)
            communityContext = note
        }
        communityContext?.setExpanded(expanded)
        communityContext?.onToggle = onToggle
    }

    func removeCommunityContext() {
        if let communityContext {
            content.removeArrangedSubview(communityContext)
            communityContext.removeFromSuperview()
        }
        communityContext = nil
    }
    private let textLabel = UILabel()
    private let viewsLabel = RollingCounterLabel()
    private let commentsLabel = RollingCounterLabel()
    private let commentsRow = UIView()
    private let channel: ChannelPerson?
    private(set) var spoiler: InkSpoilerView?

    var onLongPress: ((ChannelPostView, UILongPressGestureRecognizer) -> Void)?
    var onDoubleTap: ((ChannelPostView, CGPoint) -> Void)?
    var onChipTap: ((ChannelPostView, ReactionChip) -> Void)?
    var onStarsSent: ((ChannelPostView, Int) -> Void)?
    var onComments: ((ChannelPostView) -> Void)?
    var onForward: ((ChannelPostView, UILongPressGestureRecognizer) -> Void)?

    init(post: ChannelPost, channel: ChannelPerson? = nil) {
        self.post = post
        self.channel = channel
        chips = ReactionChipsView(reactions: post.reactions)
        avatars = LiquidAvatarStack(people: post.commenters)
        super.init(frame: .zero)
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build() {
        bubble.backgroundColor = ChannelPalette.bubble
        bubble.layer.cornerRadius = 18
        bubble.layer.cornerCurve = .continuous
        bubble.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bubble)

        content.axis = .vertical
        content.spacing = 6
        content.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(content)

        let name = UILabel()
        name.text = channel?.name ?? "VFX Daily"
        name.font = .systemFont(ofSize: 15, weight: .semibold)
        name.textColor = ChannelPalette.name
        content.addArrangedSubview(name)

        if let quote = post.quote {
            content.addArrangedSubview(makeQuote(quote))
        }

        textLabel.numberOfLines = 0
        textLabel.attributedText = attributedText()
        content.addArrangedSubview(textLabel)
        if let scene = post.image {
            let image = UIImageView(image: DemoPhotos.image(scene, size: CGSize(width: 700, height: 420)))
            image.contentMode = .scaleAspectFill
            image.clipsToBounds = true
            image.layer.cornerRadius = 10
            image.heightAnchor.constraint(equalTo: image.widthAnchor, multiplier: 0.6).isActive = true
            content.addArrangedSubview(image)
        }
        if let spoilerText = post.spoiler {
            let spoiler = InkSpoilerView()
            spoiler.translatesAutoresizingMaskIntoConstraints = false
            let full = textLabel.attributedText!
            let range = (full.string as NSString).range(of: spoilerText)
            spoiler.configure(text: full, hidden: range)
            bubble.addSubview(spoiler)
            NSLayoutConstraint.activate([
                spoiler.leadingAnchor.constraint(equalTo: textLabel.leadingAnchor),
                spoiler.trailingAnchor.constraint(equalTo: textLabel.trailingAnchor),
                spoiler.topAnchor.constraint(equalTo: textLabel.topAnchor),
                spoiler.bottomAnchor.constraint(equalTo: textLabel.bottomAnchor),
            ])
            self.spoiler = spoiler
        }

        content.setCustomSpacing(10, after: textLabel)
        chips.onChipTap = { [weak self] chip in
            guard let self else { return }
            onChipTap?(self, chip)
        }
        chips.onStarsSent = { [weak self] _, amount in
            guard let self else { return }
            onStarsSent?(self, amount)
        }
        content.addArrangedSubview(chips)

        // Views and time, right-aligned.
        let eye = UIImageView(image: UIImage(systemName: "eye.fill"))
        eye.tintColor = ChannelPalette.secondaryText
        eye.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 10)
        viewsLabel.font = .systemFont(ofSize: 12)
        viewsLabel.textColor = ChannelPalette.secondaryText
        viewsLabel.setText(FeedFormat.count(post.views), animated: false)
        let time = UILabel()
        time.text = post.time
        time.font = .systemFont(ofSize: 12)
        time.textColor = ChannelPalette.secondaryText
        let spacer = UIView()
        let footer = UIStackView(arrangedSubviews: [spacer, eye, viewsLabel, time])
        footer.spacing = 4
        footer.setCustomSpacing(8, after: viewsLabel)
        footer.alignment = .center
        content.addArrangedSubview(footer)

        // The comments row under a hairline, edge to edge.
        let separator = UIView()
        separator.backgroundColor = UIColor(white: 1, alpha: 0.08)
        separator.translatesAutoresizingMaskIntoConstraints = false
        commentsRow.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(separator)
        bubble.addSubview(commentsRow)
        avatars.translatesAutoresizingMaskIntoConstraints = false
        commentsLabel.font = .systemFont(ofSize: 16, weight: .medium)
        commentsLabel.textColor = ChannelPalette.accent
        commentsLabel.setText(commentsText(post.comments), animated: false)
        commentsLabel.translatesAutoresizingMaskIntoConstraints = false
        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = ChannelPalette.accent
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        chevron.translatesAutoresizingMaskIntoConstraints = false
        for view in [avatars, commentsLabel, chevron] {
            commentsRow.addSubview(view)
        }
        commentsRow.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(commentsTapped)))
        commentsRow.isAccessibilityElement = true
        commentsRow.accessibilityLabel = "\(post.comments) comments"
        commentsRow.accessibilityTraits = .button
        commentsRow.accessibilityIdentifier = "contact.channel.comments"

        // The share button outside the bubble.
        forwardButton.backgroundColor = UIColor(white: 0, alpha: 0.28)
        forwardButton.layer.cornerRadius = 17
        forwardButton.translatesAutoresizingMaskIntoConstraints = false
        let arrow = UIImageView(image: UIImage(systemName: "arrowshape.turn.up.right.fill"))
        arrow.tintColor = .white
        arrow.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 14)
        arrow.translatesAutoresizingMaskIntoConstraints = false
        forwardButton.addSubview(arrow)
        addSubview(forwardButton)
        let forwardPress = UILongPressGestureRecognizer(target: self, action: #selector(forwardPressed(_:)))
        forwardPress.minimumPressDuration = 0
        forwardButton.addGestureRecognizer(forwardPress)
        forwardButton.isAccessibilityElement = true
        forwardButton.accessibilityLabel = "Repost"
        forwardButton.accessibilityTraits = .button
        forwardButton.accessibilityIdentifier = "contact.channel.forward"

        NSLayoutConstraint.activate([
            bubble.topAnchor.constraint(equalTo: topAnchor),
            bubble.bottomAnchor.constraint(equalTo: bottomAnchor),
            bubble.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            bubble.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -58),
            content.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 9),
            content.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 13),
            content.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -13),
            separator.topAnchor.constraint(equalTo: content.bottomAnchor, constant: 8),
            separator.leadingAnchor.constraint(equalTo: bubble.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: bubble.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),
            commentsRow.topAnchor.constraint(equalTo: separator.bottomAnchor),
            commentsRow.leadingAnchor.constraint(equalTo: bubble.leadingAnchor),
            commentsRow.trailingAnchor.constraint(equalTo: bubble.trailingAnchor),
            commentsRow.bottomAnchor.constraint(equalTo: bubble.bottomAnchor),
            commentsRow.heightAnchor.constraint(equalToConstant: 46),
            avatars.leadingAnchor.constraint(equalTo: commentsRow.leadingAnchor, constant: 11),
            avatars.centerYAnchor.constraint(equalTo: commentsRow.centerYAnchor),
            commentsLabel.leadingAnchor.constraint(equalTo: avatars.trailingAnchor, constant: 10),
            commentsLabel.centerYAnchor.constraint(equalTo: commentsRow.centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: commentsRow.trailingAnchor, constant: -14),
            chevron.centerYAnchor.constraint(equalTo: commentsRow.centerYAnchor),
            forwardButton.widthAnchor.constraint(equalToConstant: 34),
            forwardButton.heightAnchor.constraint(equalToConstant: 34),
            forwardButton.leadingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: 10),
            forwardButton.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -6),
            arrow.centerXAnchor.constraint(equalTo: forwardButton.centerXAnchor),
            arrow.centerYAnchor.constraint(equalTo: forwardButton.centerYAnchor),
        ])

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))
        longPress.minimumPressDuration = 0.32
        longPress.delegate = self
        bubble.addGestureRecognizer(longPress)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = self
        bubble.addGestureRecognizer(doubleTap)
    }

    private func makeQuote(_ text: String) -> UIView {
        let box = UIView()
        box.backgroundColor = ChannelPalette.name.withAlphaComponent(0.12)
        box.layer.cornerRadius = 6
        let bar = UIView()
        bar.backgroundColor = ChannelPalette.name
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 15)
        label.textColor = .label
        let mark = UIImageView(image: UIImage(systemName: "quote.closing"))
        mark.tintColor = ChannelPalette.name
        mark.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 10, weight: .bold)
        for view in [bar, label, mark] {
            view.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(view)
        }
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            bar.topAnchor.constraint(equalTo: box.topAnchor),
            bar.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            bar.widthAnchor.constraint(equalToConstant: 3),
            label.leadingAnchor.constraint(equalTo: bar.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -18),
            label.topAnchor.constraint(equalTo: box.topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -6),
            mark.topAnchor.constraint(equalTo: box.topAnchor, constant: 5),
            mark.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -5),
        ])
        box.clipsToBounds = true
        return box
    }

    private func attributedText() -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 1.5
        let base: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 17), .foregroundColor: UIColor.label,
                                                   .paragraphStyle: paragraph]
        let text = NSMutableAttributedString(string: post.body, attributes: base)
        if let source = post.source {
            text.append(NSAttributedString(string: ", - ", attributes: base))
            var link = base
            link[.foregroundColor] = ChannelPalette.accent
            text.append(NSAttributedString(string: source, attributes: link))
        }
        if let spoiler = post.spoiler {
            text.append(NSAttributedString(string: " " + spoiler, attributes: base))
        }
        return text
    }

    private func commentsText(_ count: Int) -> String {
        "\(count) comments"
    }

    // MARK: Updates

    var currentPost: ChannelPost {
        var value = post
        value.reactions = chips.chips.map { ChannelReaction(emoji: $0.emoji, count: $0.count, chosen: $0.chosen) }
        return value
    }

    func addComment(from person: ChannelPerson) {
        post.comments += 1
        commentsLabel.setText(commentsText(post.comments), animated: true)
        avatars.drop(person)
    }

    func bumpViews(by amount: Int) {
        post.views += amount
        viewsLabel.setText(FeedFormat.count(post.views), animated: true)
    }

    /// The text fades in from the top down, as if the bubble was being filled with it.
    func revealContent() {
        let mask = CAGradientLayer()
        mask.frame = bubble.bounds.insetBy(dx: 0, dy: -40)
        mask.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
        mask.startPoint = CGPoint(x: 0.5, y: 0)
        mask.endPoint = CGPoint(x: 0.5, y: 1)
        content.layer.mask = mask
        let animation = CABasicAnimation(keyPath: "locations")
        animation.fromValue = [0, 0, 0.08]
        animation.toValue = [0, 1, 1.08]
        animation.duration = 0.55
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        mask.locations = [0, 1, 1.08]
        mask.add(animation, forKey: "reveal")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.content.layer.mask = nil
        }
    }

    // MARK: Gestures

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Chips, the spoiler and the comments row handle their own touches.
        guard let view = touch.view else { return true }
        let excluded: [UIView?] = [chips, spoiler, commentsRow]
        return !excluded.contains { $0.map { view.isDescendant(of: $0) } ?? false }
    }

    @objc private func longPressed(_ gesture: UILongPressGestureRecognizer) {
        onLongPress?(self, gesture)
    }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        onDoubleTap?(self, gesture.location(in: self))
    }

    @objc private func commentsTapped(_ gesture: UITapGestureRecognizer) {
        // The avatar stack has its own tap (spread/gather).
        if avatars.bounds.insetBy(dx: -4, dy: -6).contains(gesture.location(in: avatars)) {
            return
        }
        onComments?(self)
    }

    @objc private func forwardPressed(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            UIView.animate(withDuration: 0.15) { self.forwardButton.transform = CGAffineTransform(scaleX: 0.88, y: 0.88) }
        } else if gesture.state != .changed {
            UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.5) {
                self.forwardButton.transform = .identity
            }
        }
        onForward?(self, gesture)
    }

    /// The comments row's center, in `view`.
    func commentsPoint(in view: UIView) -> CGPoint {
        commentsRow.convert(CGPoint(x: commentsRow.bounds.midX, y: commentsRow.bounds.midY), to: view)
    }
}
