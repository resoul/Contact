//
//  ReactionChipsView.swift
//  controller
//
//  The reaction chips under a post, laid out in wrapping rows. Each chip is plain UIKit at rest;
//  effects only run while something happens:
//  - counts roll (RollingCounterLabel), and the chip swells when a reaction lands in it;
//  - taking a reaction back crumbles its emoji into dust (DustAnimator) before it grows back;
//  - the ⭐ chip is held to send stars: it fills with gold liquid (LiquidTubeView), the count runs
//    faster and faster with the haptics, and letting go bursts HDR gold sparks (IslandConfetti);
//  - other people's live reactions float out of a chip as little bubbles.
//

import UIKit

final class ReactionChip: UIView {
    static let height: CGFloat = 32

    let emoji: String
    private(set) var count: Int
    private(set) var chosen: Bool
    var isStar: Bool { emoji == "⭐" }

    var onTap: ((ReactionChip) -> Void)?
    /// Stars sent with one hold (or one tap).
    var onStarsSent: ((ReactionChip, Int) -> Void)?

    let emojiLabel = UILabel()
    private let counter = RollingCounterLabel()
    private let background = UIView()
    private var sparkles: CAEmitterLayer?
    // Star hold
    private var tube: LiquidTubeView?
    private var holdTime: CFTimeInterval = 0
    private var holding = false
    private var pending: CGFloat = 0
    private var sentThisHold = 0
    private var fillLevel = Spring1D(0, stiffness: 7, dampingRatio: 0.5)
    private let tick = UIImpactFeedbackGenerator(style: .light)

    init(reaction: ChannelReaction) {
        emoji = reaction.emoji
        count = reaction.count
        chosen = reaction.chosen
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = emoji
        accessibilityValue = "\(count)"
        accessibilityIdentifier = "contact.channel.reaction.\(emoji)"
        background.layer.cornerCurve = .continuous
        background.isUserInteractionEnabled = false
        addSubview(background)
        emojiLabel.text = emoji
        emojiLabel.font = .systemFont(ofSize: 17)
        emojiLabel.sizeToFit()
        addSubview(emojiLabel)
        counter.font = .systemFont(ofSize: 14, weight: .semibold)
        counter.setText(FeedFormat.count(count), animated: false)
        addSubview(counter)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        if isStar {
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
            hold.minimumPressDuration = 0.22
            addGestureRecognizer(hold)
            addSparkles()
        }
        applyStyle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var preferredWidth: CGFloat {
        10 + emojiLabel.bounds.width + 5 + counter.intrinsicContentSize.width + 12
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        background.frame = bounds
        background.layer.cornerRadius = bounds.height / 2
        tube?.frame = bounds
        emojiLabel.center = CGPoint(x: 10 + emojiLabel.bounds.width / 2, y: bounds.midY)
        let size = counter.intrinsicContentSize
        counter.frame = CGRect(x: emojiLabel.frame.maxX + 5, y: (bounds.height - size.height) / 2,
                               width: size.width, height: size.height)
        sparkles?.emitterPosition = CGPoint(x: emojiLabel.center.x, y: bounds.midY)
    }

    private func applyStyle() {
        if isStar {
            background.backgroundColor = ChannelPalette.star.withAlphaComponent(chosen ? 0.42 : 0.2)
            counter.textColor = chosen ? .white : ChannelPalette.star
        } else {
            background.backgroundColor = chosen ? ChannelPalette.accent : UIColor.tertiarySystemFill
            counter.textColor = chosen ? .white : .label
        }
    }

    func set(count newCount: Int, chosen newChosen: Bool, animated: Bool) {
        let up = newCount >= count
        let oldWidth = preferredWidth
        count = newCount
        accessibilityValue = "\(newCount)"
        chosen = newChosen
        counter.setText(FeedFormat.count(count), animated: animated, up: up)
        if animated {
            UIView.animate(withDuration: 0.25) { self.applyStyle() }
        } else {
            applyStyle()
        }
        setNeedsLayout()
        if abs(preferredWidth - oldWidth) > 0.5, let chips = superview as? ReactionChipsView {
            chips.reflow()
        }
    }

    /// The chip swells and wobbles back, as when a reaction lands in it.
    func gulp(_ amount: CGFloat = 0.22) {
        transform = CGAffineTransform(scaleX: 1 + amount, y: 1 + amount * 0.7)
        UIView.animate(withDuration: 0.55, delay: 0, usingSpringWithDamping: 0.35, initialSpringVelocity: 0.6) {
            self.transform = .identity
        }
    }

    /// The emoji crumbles into dust and grows back.
    func crumbleEmoji() {
        guard let window else { return }
        let ghost = UILabel()
        ghost.text = emoji
        ghost.font = emojiLabel.font
        ghost.sizeToFit()
        ghost.frame = emojiLabel.convert(emojiLabel.bounds, to: window).insetBy(dx: -2, dy: -2)
        ghost.textAlignment = .center
        window.addSubview(ghost)
        emojiLabel.alpha = 0
        DispatchQueue.main.async {
            DustAnimator.blowAway(ghost, wind: CGVector(dx: 40, dy: 60), gravity: 260, grain: 0.9, releaseWindow: 0.35) {
                ghost.removeFromSuperview()
            }
        }
        emojiLabel.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
        UIView.animate(withDuration: 0.5, delay: 0.45, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.5) {
            self.emojiLabel.alpha = 1
            self.emojiLabel.transform = .identity
        }
    }

    /// Someone else reacted: a little bubble with the emoji floats up out of the chip.
    func floatBubble(in host: UIView) {
        let bubble = UILabel()
        bubble.text = emoji
        bubble.font = .systemFont(ofSize: 13)
        bubble.textAlignment = .center
        bubble.backgroundColor = UIColor(white: 1, alpha: 0.14)
        bubble.frame = CGRect(x: 0, y: 0, width: 24, height: 24)
        bubble.layer.cornerRadius = 12
        bubble.clipsToBounds = true
        let start = convert(emojiLabel.center, to: host)
        bubble.center = start
        bubble.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
        host.addSubview(bubble)
        let rise = CAKeyframeAnimation(keyPath: "position")
        let path = UIBezierPath()
        path.move(to: start)
        let sway = CGFloat.random(in: -14...14)
        path.addCurve(to: CGPoint(x: start.x + sway * 0.5, y: start.y - 58),
                      controlPoint1: CGPoint(x: start.x + sway, y: start.y - 18),
                      controlPoint2: CGPoint(x: start.x - sway, y: start.y - 40))
        rise.path = path.cgPath
        rise.duration = 1.4
        rise.timingFunction = CAMediaTimingFunction(name: .easeOut)
        bubble.layer.add(rise, forKey: "rise")
        bubble.center = CGPoint(x: start.x + sway * 0.5, y: start.y - 58)
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.5) {
            bubble.transform = .identity
        }
        UIView.animate(withDuration: 0.5, delay: 0.9, options: []) {
            bubble.alpha = 0
            bubble.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
        } completion: { _ in
            bubble.removeFromSuperview()
        }
    }

    // MARK: Tap

    @objc private func tapped() {
        if isStar {
            sendStars(1, burst: 70)
            set(count: count + 1, chosen: true, animated: true)
            gulp(0.15)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            floatLabel("+1")
            onStarsSent?(self, 1)
            return
        }
        onTap?(self)
    }

    // MARK: Star hold

    private func addSparkles() {
        let emitter = CAEmitterLayer()
        emitter.emitterShape = .circle
        emitter.emitterSize = CGSize(width: 18, height: 18)
        emitter.renderMode = .additive
        let cell = CAEmitterCell()
        cell.contents = Self.sparkImage.cgImage
        cell.birthRate = 2.5
        cell.lifetime = 1.1
        cell.velocity = 10
        cell.velocityRange = 8
        cell.emissionRange = .pi * 2
        cell.scale = 0.16
        cell.scaleRange = 0.08
        cell.scaleSpeed = -0.1
        cell.alphaSpeed = -0.8
        cell.color = ChannelPalette.star.cgColor
        cell.name = "spark"
        emitter.emitterCells = [cell]
        layer.addSublayer(emitter)
        sparkles = emitter
    }

    private static let sparkImage: UIImage = {
        UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { context in
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: nil, colors: colors, locations: [0, 1])!
            context.cgContext.drawRadialGradient(gradient, startCenter: CGPoint(x: 16, y: 16), startRadius: 0,
                                                 endCenter: CGPoint(x: 16, y: 16), endRadius: 16, options: [])
        }
    }()

    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            holding = true
            holdTime = 0
            pending = 0
            sentThisHold = 0
            startTube()
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case .ended, .cancelled, .failed:
            guard holding else { return }
            holding = false
            let sent = max(sentThisHold, 1)
            if sentThisHold == 0 {
                set(count: count + 1, chosen: true, animated: true)
            }
            sendStars(sent, burst: 120 + min(sent * 10, 420))
            floatLabel("+\(sent)")
            gulp(0.28)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onStarsSent?(self, sent)
        default:
            break
        }
    }

    private func startTube() {
        let tube = self.tube ?? {
            let tube = LiquidTubeView()
            tube.isUserInteractionEnabled = false
            tube.liquidColor = ChannelPalette.star
            tube.trackColor = .clear
            insertSubview(tube, aboveSubview: background)
            self.tube = tube
            tube.onUpdate = { [weak self] dt in self?.stepHold(dt) }
            return tube
        }()
        tube.frame = bounds
        tube.isHidden = false
        tube.isPaused = false
    }

    private func stepHold(_ dt: CFTimeInterval) {
        guard let tube else { return }
        if holding {
            holdTime += dt
            // Faster and faster: 5 stars a second at first, up to 40.
            let ramp = min(holdTime / 2.0, 1)
            pending += CGFloat(5 + 35 * pow(ramp, 1.5)) * CGFloat(dt)
            while pending >= 1 {
                pending -= 1
                sentThisHold += 1
                set(count: count + 1, chosen: true, animated: true)
                tick.impactOccurred(intensity: 0.35 + 0.65 * CGFloat(ramp))
                emojiLabel.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
                UIView.animate(withDuration: 0.18) { self.emojiLabel.transform = .identity }
            }
            sparkles?.setValue(Float(3 + 40 * ramp), forKeyPath: "emitterCells.spark.birthRate")
            sparkles?.setValue(Float(10 + 50 * ramp), forKeyPath: "emitterCells.spark.velocity")
        }
        fillLevel.step(toward: holding ? min(0.15 + holdTime / 2.0, 1) : 0, deltaTime: dt)
        tube.fill = max(0, fillLevel.value)
        tube.slosh = fillLevel.velocity
        if !holding, fillLevel.isSettled(at: 0, tolerance: 0.01) {
            tube.fill = 0
            tube.renderFrame()
            tube.isPaused = true
            tube.isHidden = true
            sparkles?.setValue(Float(2.5), forKeyPath: "emitterCells.spark.birthRate")
            sparkles?.setValue(Float(10), forKeyPath: "emitterCells.spark.velocity")
        }
    }

    private func sendStars(_ amount: Int, burst particles: Int) {
        guard let window else { return }
        let origin = convert(CGPoint(x: bounds.midX, y: bounds.midY), to: window)
        IslandConfetti.burst(in: window, from: origin, direction: -.pi / 2, spread: 1.9, particles: particles,
                             sparkShare: 1, sparkColor: ChannelPalette.star, speedScale: 0.42 + min(CGFloat(amount) / 60, 0.3))
    }

    /// "+12" rises out of the chip and fades.
    private func floatLabel(_ text: String) {
        guard let host = superview else { return }
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 17, weight: .heavy)
        label.textColor = ChannelPalette.star
        label.sizeToFit()
        label.center = convert(CGPoint(x: bounds.midX, y: 0), to: host)
        host.addSubview(label)
        label.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.6) {
            label.transform = .identity
        }
        UIView.animate(withDuration: 1.0, delay: 0, options: [.curveEaseOut]) {
            label.center.y -= 44
        }
        UIView.animate(withDuration: 0.35, delay: 0.75, options: []) {
            label.alpha = 0
        } completion: { _ in
            label.removeFromSuperview()
        }
    }
}

/// The chips in wrapping rows. Adding or removing a chip reflows the rest on a spring.
final class ReactionChipsView: UIView {
    private(set) var chips: [ReactionChip] = []
    var onChipTap: ((ReactionChip) -> Void)?
    var onStarsSent: ((ReactionChip, Int) -> Void)?
    private let spacing: CGFloat = 6
    private var lastHeight: CGFloat = 0

    init(reactions: [ChannelReaction]) {
        super.init(frame: .zero)
        clipsToBounds = false
        reactions.forEach { addChip(for: $0) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @discardableResult
    private func addChip(for reaction: ChannelReaction, at index: Int? = nil) -> ReactionChip {
        let chip = ReactionChip(reaction: reaction)
        chip.onTap = { [weak self] in self?.onChipTap?($0) }
        chip.onStarsSent = { [weak self] in self?.onStarsSent?($0, $1) }
        chips.insert(chip, at: index ?? chips.count)
        addSubview(chip)
        accessibilityElements = chips
        return chip
    }

    func chip(for emoji: String) -> ReactionChip? {
        chips.first { $0.emoji == emoji }
    }

    private func frames(for width: CGFloat) -> [CGRect] {
        var x: CGFloat = 0, y: CGFloat = 0
        return chips.map { chip in
            let w = chip.preferredWidth
            if x > 0, x + w > width {
                x = 0
                y += ReactionChip.height + spacing
            }
            defer { x += w + spacing }
            return CGRect(x: x, y: y, width: w, height: ReactionChip.height)
        }
    }

    private var contentHeight: CGFloat {
        let width = bounds.width > 0 ? bounds.width : 280
        return (frames(for: width).map(\.maxY).max() ?? 0)
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: contentHeight)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        for (chip, frame) in zip(chips, frames(for: bounds.width)) where chip.transform == .identity {
            chip.frame = frame
        }
        if abs(contentHeight - lastHeight) > 0.5 {
            lastHeight = contentHeight
            invalidateIntrinsicContentSize()
        }
    }

    /// Adds a chip for a reaction nobody has used yet; the others make room on a spring.
    /// The chip starts invisible: the landing effect reveals it.
    func insertChip(_ reaction: ChannelReaction) -> ReactionChip {
        let chip = addChip(for: reaction)
        chip.alpha = 0
        reflow()
        return chip
    }

    func remove(_ chip: ReactionChip) {
        chips.removeAll { $0 === chip }
        accessibilityElements = chips
        UIView.animate(withDuration: 0.25) {
            chip.alpha = 0
            chip.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
        } completion: { _ in
            chip.removeFromSuperview()
        }
        reflow()
    }

    /// Reflows the chips on a spring, and the post around them when their height changes.
    func reflow() {
        let targets = frames(for: bounds.width)
        // Relaying out the whole feed is the expensive part: skip it when the rows stay the same.
        let heightChanged = abs((targets.map(\.maxY).max() ?? 0) - lastHeight) > 0.5
        let root = heightChanged
            ? sequence(first: self as UIView, next: { $0.superview }).first { $0 is UIScrollView } ?? superview : nil
        if heightChanged {
            invalidateIntrinsicContentSize()
        }
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.72, initialSpringVelocity: 0.3) {
            for (chip, frame) in zip(self.chips, targets) {
                chip.bounds.size = frame.size
                chip.center = frame.center
                chip.layoutIfNeeded()
            }
            root?.layoutIfNeeded()
        }
    }

    /// The window-space center of a chip's emoji, where flying reactions land.
    func landingPoint(of chip: ReactionChip, in view: UIView) -> CGPoint {
        chip.convert(chip.emojiLabel.center, to: view)
    }
}
