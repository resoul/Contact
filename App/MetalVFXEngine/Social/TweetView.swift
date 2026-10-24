//
//  TweetView.swift
//  controller
//
//  X-style posts for the timeline demo:
//  - TweetView: avatar, name, text, optional photo and the action row; counts roll, the heart pops
//    with sparks, and the repost arrows spin while a copy of the post is carried off in a green drop.
//  - ThreadView: tweets connected by a liquid stream between their avatars. Replying sends a drop
//    running down the stream; where it stops, the reply's avatar grows out of it and the reply
//    fills in.
//

import UIKit

struct TweetModel {
    let author: ChannelPerson
    let handle: String
    let time: String
    let text: String
    var photo: DemoPhotos.Scene?
    var replies = 0
    var reposts = 0
    var likes = 0
    var views = 0
}

/// Icon + rolling count, as in the tweet's action row.
final class TweetActionButton: UIControl {
    let icon = UIImageView()
    let counter = RollingCounterLabel()
    private(set) var count: Int
    private let symbol: String
    private let activeSymbol: String

    init(symbol: String, activeSymbol: String? = nil, count: Int) {
        self.symbol = symbol
        self.activeSymbol = activeSymbol ?? symbol
        self.count = count
        super.init(frame: .zero)
        icon.image = UIImage(systemName: symbol)
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        icon.tintColor = TimelinePalette.secondary
        icon.contentMode = .center
        icon.isUserInteractionEnabled = false
        counter.font = .systemFont(ofSize: 13)
        counter.textColor = TimelinePalette.secondary
        counter.setText(count > 0 ? FeedFormat.count(count) : "", animated: false)
        addSubview(icon)
        addSubview(counter)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: 64, height: 34)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        icon.bounds = CGRect(x: 0, y: 0, width: 22, height: 22)
        icon.center = CGPoint(x: 11, y: bounds.midY)
        let size = counter.intrinsicContentSize
        counter.frame = CGRect(x: 26, y: bounds.midY - size.height / 2, width: max(size.width, 30), height: size.height)
    }

    func set(count newCount: Int, active: Bool, color: UIColor) {
        let up = newCount >= count
        count = newCount
        counter.setText(newCount > 0 ? FeedFormat.count(newCount) : "", animated: true, up: up)
        icon.image = UIImage(systemName: active ? activeSymbol : symbol)
        icon.tintColor = active ? color : TimelinePalette.secondary
        counter.textColor = active ? color : TimelinePalette.secondary
        setNeedsLayout()
    }

    /// The icon pops: shrinks under the finger, then springs past its size.
    func pop() {
        icon.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.4, initialSpringVelocity: 0.8) {
            self.icon.transform = .identity
        }
    }
}

final class TweetView: UIView {
    private(set) var model: TweetModel
    let avatar = UIImageView()
    private let content = UIStackView()
    let reply: TweetActionButton
    let repost: TweetActionButton
    let like: TweetActionButton
    private let views: TweetActionButton
    private var liked = false
    private var reposted = false

    var onReply: ((TweetView) -> Void)?
    var onRepost: ((TweetView, Bool) -> Void)?

    init(model: TweetModel) {
        self.model = model
        reply = TweetActionButton(symbol: "bubble.left", count: model.replies)
        repost = TweetActionButton(symbol: "arrow.2.squarepath", count: model.reposts)
        like = TweetActionButton(symbol: "heart", activeSymbol: "heart.fill", count: model.likes)
        views = TweetActionButton(symbol: "chart.bar.xaxis", count: model.views)
        super.init(frame: .zero)
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build() {
        avatar.image = ChannelAvatar.image(for: model.author, size: 44)
        avatar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(avatar)

        let header = UILabel()
        let name = NSMutableAttributedString(string: model.author.name,
                                             attributes: [.font: UIFont.systemFont(ofSize: 15, weight: .bold),
                                                          .foregroundColor: UIColor.white])
        name.append(NSAttributedString(string: "  @\(model.handle) · \(model.time)",
                                       attributes: [.font: UIFont.systemFont(ofSize: 15),
                                                    .foregroundColor: TimelinePalette.secondary]))
        header.attributedText = name
        header.lineBreakMode = .byTruncatingTail

        let text = UILabel()
        text.text = model.text
        text.numberOfLines = 0
        text.font = .systemFont(ofSize: 15)
        text.textColor = .white

        content.axis = .vertical
        content.spacing = 4
        content.translatesAutoresizingMaskIntoConstraints = false
        content.addArrangedSubview(header)
        content.addArrangedSubview(text)
        if let photo = model.photo {
            let image = UIImageView(image: DemoPhotos.image(photo, size: CGSize(width: 640, height: 400)))
            image.contentMode = .scaleAspectFill
            image.clipsToBounds = true
            image.layer.cornerRadius = 16
            image.layer.cornerCurve = .continuous
            image.layer.borderWidth = 0.5
            image.layer.borderColor = TimelinePalette.separator.cgColor
            image.heightAnchor.constraint(equalTo: image.widthAnchor, multiplier: 0.62).isActive = true
            content.setCustomSpacing(10, after: text)
            content.addArrangedSubview(image)
        }

        let share = UIImageView(image: UIImage(systemName: "square.and.arrow.up"))
        share.tintColor = TimelinePalette.secondary
        share.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 15)
        share.contentMode = .center
        let actions = UIStackView(arrangedSubviews: [reply, repost, like, views, share])
        actions.distribution = .equalSpacing
        actions.alignment = .center
        content.setCustomSpacing(6, after: content.arrangedSubviews.last!)
        content.addArrangedSubview(actions)
        addSubview(content)

        reply.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            reply.pop()
            onReply?(self)
        }, for: .touchUpInside)
        like.addAction(UIAction { [weak self] _ in self?.toggleLike() }, for: .touchUpInside)
        repost.addAction(UIAction { [weak self] _ in self?.toggleRepost() }, for: .touchUpInside)

        NSLayoutConstraint.activate([
            avatar.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            avatar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            avatar.widthAnchor.constraint(equalToConstant: 44),
            avatar.heightAnchor.constraint(equalToConstant: 44),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            content.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 10),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    func addReply() {
        model.replies += 1
        reply.set(count: model.replies, active: false, color: TimelinePalette.accent)
    }

    private func toggleLike() {
        liked.toggle()
        model.likes += liked ? 1 : -1
        like.set(count: model.likes, active: liked, color: TimelinePalette.like)
        like.pop()
        UIImpactFeedbackGenerator(style: liked ? .medium : .light).impactOccurred()
        if liked, let window {
            let center = like.icon.convert(CGPoint(x: 11, y: 11), to: window)
            IslandConfetti.burst(in: window, from: center, direction: -.pi / 2, spread: 2 * .pi, particles: 70,
                                 sparkShare: 1, sparkColor: TimelinePalette.like, speedScale: 0.28)
        }
    }

    private func toggleRepost() {
        reposted.toggle()
        model.reposts += reposted ? 1 : -1
        repost.set(count: model.reposts, active: reposted, color: TimelinePalette.repost)
        // The arrows chase each other once around.
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = reposted ? CGFloat.pi * 2 : -CGFloat.pi * 2
        spin.duration = 0.55
        spin.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 0, 0.2, 1)
        repost.icon.layer.add(spin, forKey: "spin")
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onRepost?(self, reposted)
    }

    /// The avatar's center in `view`, for the thread stream.
    func avatarCenter(in view: UIView) -> CGPoint {
        avatar.convert(CGPoint(x: 22, y: 22), to: view)
    }

    /// The reply fills in from the top down (its avatar is grown by the thread).
    func revealContent() {
        let mask = CAGradientLayer()
        mask.frame = content.bounds.insetBy(dx: 0, dy: -30)
        mask.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
        let animation = CABasicAnimation(keyPath: "locations")
        animation.fromValue = [0, 0, 0.1]
        animation.toValue = [0, 1, 1.1]
        animation.duration = 0.5
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        mask.locations = [0, 1, 1.1]
        mask.add(animation, forKey: "reveal")
        content.layer.mask = mask
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in self?.content.layer.mask = nil }
    }
}

/// Tweets in one conversation, joined by a liquid stream between their avatars. A lone tweet is a
/// thread of one: replying to it starts the stream.
final class ThreadView: UIView {
    private(set) var tweets: [TweetView] = []
    private let stack = UIStackView()
    private let stream = LiquidCanvasView()
    private let separator = UIView()
    /// A drop on its way down the stream: from where, to where, how far along.
    private var drop: (from: CGPoint, to: TweetView, progress: Spring1D)?
    private var grown: Set<ObjectIdentifier> = []

    var onReply: ((TweetView) -> Void)?
    var onRepost: ((TweetView, Bool) -> Void)?

    init(models: [TweetModel]) {
        super.init(frame: .zero)
        stream.liquidColor = UIColor(red: 0.26, green: 0.33, blue: 0.4, alpha: 1)
        stream.gloss = 0.5
        stream.rimWidth = 2
        stream.onUpdate = { [weak self] dt in self?.step(dt) }
        addSubview(stream)
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        separator.backgroundColor = TimelinePalette.separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),
        ])
        models.forEach { add($0) }
        tweets.forEach { grown.insert(ObjectIdentifier($0)) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @discardableResult
    private func add(_ model: TweetModel) -> TweetView {
        let tweet = TweetView(model: model)
        tweet.onReply = { [weak self] in self?.onReply?($0) }
        tweet.onRepost = { [weak self] in self?.onRepost?($0, $1) }
        tweets.append(tweet)
        stack.addArrangedSubview(tweet)
        return tweet
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        stream.frame = bounds
        stream.isPaused = false
    }

    /// Appends a reply: a drop runs down the stream from the last avatar, and the reply grows out of it.
    func appendReply(_ model: TweetModel, completion: (() -> Void)? = nil) {
        guard let last = tweets.last else { return }
        last.addReply()
        let from = last.avatarCenter(in: self)
        let reply = add(model)
        reply.alpha = 0
        reply.avatar.transform = CGAffineTransform(scaleX: 0.01, y: 0.01)
        let scroll = sequence(first: self as UIView, next: { $0.superview }).first { $0 is UIScrollView }
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
            scroll?.layoutIfNeeded()
        }
        drop = (from, reply, Spring1D(0, stiffness: 7, dampingRatio: 0.85))
        onArrive = completion
        stream.isPaused = false
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    private var onArrive: (() -> Void)?

    private func step(_ dt: CFTimeInterval) {
        var spikes: [IslandFluidSpike] = []
        var shapes: [IslandFluidShape] = []
        // The stream between every pair of grown avatars.
        let centers = tweets.map { $0.avatarCenter(in: self) }
        for i in 0..<max(tweets.count - 1, 0) where grown.contains(ObjectIdentifier(tweets[i + 1])) {
            spikes.append(IslandFluidSpike(base: CGPoint(x: centers[i].x, y: centers[i].y + 26),
                                           tip: CGPoint(x: centers[i + 1].x, y: centers[i + 1].y - 26),
                                           baseRadius: 1.4, tipRadius: 1.4, blend: 0))
        }
        if var drop {
            drop.progress.step(toward: 1, deltaTime: dt)
            let to = drop.to.avatarCenter(in: self)
            let p = min(max(drop.progress.value, 0), 1)
            let head = CGPoint(x: drop.from.x, y: drop.from.y + 26 + (to.y - drop.from.y - 26) * p)
            // The stream grows behind the drop; the drop swells as it nears the end.
            spikes.append(IslandFluidSpike(base: CGPoint(x: drop.from.x, y: drop.from.y + 26), tip: head,
                                           baseRadius: 1.4, tipRadius: 1.4, blend: 0))
            shapes.append(.circle(center: head, radius: 4 + 10 * p * p, blend: 6))
            if p > 0.97 {
                let tweet = drop.to
                grown.insert(ObjectIdentifier(tweet))
                self.drop = nil
                UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.4) {
                    tweet.avatar.transform = .identity
                    tweet.alpha = 1
                }
                tweet.revealContent()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onArrive?()
                onArrive = nil
            } else {
                self.drop = drop
            }
        }
        stream.shapes = shapes
        stream.spikes = spikes
        if drop == nil {
            stream.renderFrame()
            stream.isPaused = true
        }
    }
}
