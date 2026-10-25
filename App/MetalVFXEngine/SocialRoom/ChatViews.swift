//
//  ChatViews.swift
//  controller
//
//  Pieces of the chat:
//  - RingAvatar, ChatRow (text bubbles, mine in an orange gradient), ProfileChip.
//  - VoiceMessageView: a squiggly waveform; the played part lights up, and the playhead is a drop of
//    liquid riding the wave that stretches when you drag it to scrub.
//  - PhotoStackView: a fanned stack of photos that spreads out when tapped.
//  - TypingDots: three dots of liquid that bounce, part and merge.
//  - RecordBlob: holding the mic grows it into a blob that quivers with your voice; slide left and the
//    blob tears off its neck and falls into the bin.
//

import UIKit

final class RingAvatar: UIView {
    private let image = UIImageView()
    private let ring = CAGradientLayer()
    private let ringMask = CAShapeLayer()
    private let dot = UIView()

    init(person: ChannelPerson, online: Bool = false) {
        super.init(frame: .zero)
        image.image = ChannelAvatar.image(for: person, size: 64)
        image.clipsToBounds = true
        addSubview(image)
        ring.colors = [RoomPalette.orange.cgColor, RoomPalette.pink.cgColor, UIColor.systemPurple.cgColor]
        ring.startPoint = CGPoint(x: 0, y: 0)
        ring.endPoint = CGPoint(x: 1, y: 1)
        ringMask.fillColor = UIColor.clear.cgColor
        ringMask.strokeColor = UIColor.black.cgColor
        ringMask.lineWidth = 2
        ring.mask = ringMask
        layer.addSublayer(ring)
        dot.backgroundColor = .systemGreen
        dot.layer.borderColor = RoomPalette.background.cgColor
        dot.layer.borderWidth = 2
        dot.isHidden = !online
        addSubview(dot)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        ring.frame = bounds
        ringMask.path = UIBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).cgPath
        image.frame = bounds.insetBy(dx: 5, dy: 5)
        image.layer.cornerRadius = image.bounds.width / 2
        let s = bounds.width * 0.22
        dot.frame = CGRect(x: bounds.maxX - s - 2, y: bounds.maxY - s - 2, width: s, height: s)
        dot.layer.cornerRadius = s / 2
    }
}

/// A rounded chip with an SF Symbol and a title, as in the profile header.
final class ProfileChip: UIView {
    init(symbol: String, title: String) {
        super.init(frame: .zero)
        backgroundColor = RoomPalette.chip
        layer.cornerRadius = 19
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = UIColor(white: 1, alpha: 0.75)
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 12)
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white
        let row = UIStackView(arrangedSubviews: [icon, label])
        row.spacing = 5
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 38),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// One message row: avatar, bubble (or any content view) and time.
final class ChatRow: UIView {
    let content: UIView
    let outgoing: Bool

    init(content: UIView, person: ChannelPerson, outgoing: Bool, time: String) {
        self.content = content
        self.outgoing = outgoing
        super.init(frame: .zero)
        let avatar = RingAvatar(person: person)
        avatar.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        let timeLabel = UILabel()
        timeLabel.text = time
        timeLabel.font = .systemFont(ofSize: 13)
        timeLabel.textColor = RoomPalette.secondary
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        for view in [avatar, content, timeLabel] {
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            avatar.widthAnchor.constraint(equalToConstant: 48),
            avatar.heightAnchor.constraint(equalToConstant: 48),
            avatar.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            content.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.72),
            timeLabel.topAnchor.constraint(equalTo: content.bottomAnchor, constant: 6),
            timeLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
        if outgoing {
            NSLayoutConstraint.activate([
                avatar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
                content.trailingAnchor.constraint(equalTo: avatar.leadingAnchor, constant: -10),
                timeLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            ])
        } else {
            NSLayoutConstraint.activate([
                avatar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
                content.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 10),
                timeLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            ])
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// A text bubble: mine in an orange gradient, theirs on a dark panel.
    static func bubble(_ text: String, outgoing: Bool) -> UIView {
        let bubble = GradientBubble(outgoing: outgoing)
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 16)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 13),
            label.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -13),
            label.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -18),
        ])
        return bubble
    }
}

final class GradientBubble: UIView {
    private let gradient = CAGradientLayer()

    init(outgoing: Bool) {
        super.init(frame: .zero)
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        clipsToBounds = true
        if outgoing {
            gradient.colors = [RoomPalette.orange.cgColor, UIColor(red: 1, green: 0.22, blue: 0.1, alpha: 1).cgColor]
            gradient.startPoint = CGPoint(x: 0, y: 0)
            gradient.endPoint = CGPoint(x: 1, y: 1)
            layer.insertSublayer(gradient, at: 0)
        } else {
            backgroundColor = RoomPalette.panel
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
    }
}

// MARK: - Voice message

final class VoiceMessageView: UIView {
    private let playButton = UIButton(type: .custom)
    private let wave = CAShapeLayer()
    private let played = CAShapeLayer()
    private let playedMask = CALayer()
    private let durationLabel = UILabel()
    private let drop = LiquidCanvasView()
    private let amplitudes: [CGFloat]
    private let duration: TimeInterval
    private var progress: CGFloat = 0
    private var playing = false
    private var scrubbing = false
    private var head = Spring1D(0, stiffness: 30, dampingRatio: 0.7)
    private var tail = Spring1D(0, stiffness: 9, dampingRatio: 0.9)
    private var size = Spring1D(5, stiffness: 20, dampingRatio: 0.45)
    private let waveInset = UIEdgeInsets(top: 0, left: 76, bottom: 0, right: 52)

    init(seconds: TimeInterval, seed: UInt64) {
        duration = seconds
        var random = SplitMix(seed: seed)
        amplitudes = (0..<14).map { _ in 0.25 + random.next() * 0.75 }
        super.init(frame: .zero)
        backgroundColor = RoomPalette.panel
        layer.cornerRadius = 26
        layer.cornerCurve = .continuous
        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: "play.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .bold))
        config.baseBackgroundColor = RoomPalette.cyan
        config.baseForegroundColor = RoomPalette.background
        config.cornerStyle = .capsule
        playButton.configuration = config
        playButton.addAction(UIAction { [weak self] _ in self?.togglePlay() }, for: .touchUpInside)
        addSubview(playButton)
        for (layer, color) in [(wave, RoomPalette.cyan.withAlphaComponent(0.3)), (played, RoomPalette.cyan)] {
            layer.fillColor = UIColor.clear.cgColor
            layer.strokeColor = color.cgColor
            layer.lineWidth = 2
            layer.lineCap = .round
            layer.lineJoin = .round
            self.layer.addSublayer(layer)
        }
        playedMask.backgroundColor = UIColor.black.cgColor
        played.mask = playedMask
        drop.liquidColor = RoomPalette.cyan
        drop.gloss = 0.6
        drop.rimWidth = 3
        drop.onUpdate = { [weak self] dt in self?.step(dt) }
        addSubview(drop)
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        durationLabel.textColor = RoomPalette.secondary
        addSubview(durationLabel)
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(scrub(_:))))
        updateLabel()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: 300, height: 76)
    }

    private var waveRect: CGRect { bounds.inset(by: waveInset) }

    /// The squiggle: a carrier wave whose loudness follows the message's amplitudes.
    private func waveY(_ u: CGFloat) -> CGFloat {
        let rect = waveRect
        let position = u * CGFloat(amplitudes.count - 1)
        let i = Int(position), f = position - CGFloat(i)
        let a = amplitudes[min(i, amplitudes.count - 1)] * (1 - f) + amplitudes[min(i + 1, amplitudes.count - 1)] * f
        let envelope = sin(u * .pi) * 0.8 + 0.2
        return rect.midY + sin(u * 38) * a * envelope * rect.height * 0.22
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playButton.frame = CGRect(x: 14, y: bounds.midY - 26, width: 52, height: 52)
        let rect = waveRect
        let path = UIBezierPath()
        let steps = 160
        for s in 0...steps {
            let u = CGFloat(s) / CGFloat(steps)
            let point = CGPoint(x: rect.minX + u * rect.width, y: waveY(u))
            s == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        wave.path = path.cgPath
        played.path = path.cgPath
        updateMask()
        drop.frame = bounds
        durationLabel.sizeToFit()
        durationLabel.frame.origin = CGPoint(x: bounds.maxX - durationLabel.bounds.width - 16, y: bounds.midY - durationLabel.bounds.height / 2)
        drop.isPaused = false
    }

    private func updateMask() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playedMask.frame = CGRect(x: 0, y: 0, width: waveRect.minX + waveRect.width * progress, height: bounds.height)
        CATransaction.commit()
    }

    private func updateLabel() {
        let seconds = Int((playing || progress > 0 ? Double(1 - progress) : 1) * duration * 5.5)
        durationLabel.text = String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func togglePlay() {
        playing.toggle()
        if playing, progress >= 1 {
            progress = 0
        }
        playButton.configuration?.image = UIImage(systemName: playing ? "pause.fill" : "play.fill",
                                                  withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .bold))
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        drop.isPaused = false
    }

    /// Scrubbing is horizontal: vertical drags scroll the chat.
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: self)
        return abs(velocity.x) > abs(velocity.y)
    }

    @objc private func scrub(_ gesture: UIPanGestureRecognizer) {
        let x = gesture.location(in: self).x
        progress = min(max((x - waveRect.minX) / waveRect.width, 0), 1)
        switch gesture.state {
        case .began:
            scrubbing = true
            size.velocity += 40
            UISelectionFeedbackGenerator().selectionChanged()
        case .changed:
            break
        default:
            scrubbing = false
        }
        updateMask()
        updateLabel()
        drop.isPaused = false
    }

    private func step(_ dt: CFTimeInterval) {
        if playing, !scrubbing {
            progress += CGFloat(dt / duration)
            if progress >= 1 {
                progress = 1
                togglePlay()
            }
            updateMask()
            updateLabel()
        }
        head.step(toward: progress, deltaTime: dt)
        tail.step(toward: progress, deltaTime: dt)
        size.step(toward: scrubbing ? 8 : (playing || progress > 0 ? 5.5 : 0), deltaTime: dt)
        let rect = waveRect
        let a = CGPoint(x: rect.minX + rect.width * head.value, y: waveY(min(max(head.value, 0), 1)))
        let b = CGPoint(x: rect.minX + rect.width * tail.value, y: waveY(min(max(tail.value, 0), 1)))
        let r = max(size.value, 0)
        if r > 0.3 {
            drop.shapes = [.circle(center: a, radius: r, blend: 0), .circle(center: b, radius: r * 0.7, blend: 4)]
            drop.spikes = a.distance(to: b) > 1 ? [IslandFluidSpike(base: b, tip: a, baseRadius: r * 0.5, tipRadius: r * 0.8, blend: 3)] : []
        } else {
            drop.shapes = []
            drop.spikes = []
        }
        if !playing, !scrubbing, head.isSettled(at: progress), tail.isSettled(at: progress), size.isSettled(at: progress > 0 ? 5.5 : 0) {
            drop.renderFrame()
            drop.isPaused = true
        }
    }
}

// MARK: - Photo stack

final class PhotoStackView: UIView {
    private var cards: [UIImageView] = []
    private var spread = false

    init(scenes: [DemoPhotos.Scene]) {
        super.init(frame: .zero)
        for (index, scene) in scenes.enumerated() {
            let card = UIImageView(image: DemoPhotos.image(scene, size: CGSize(width: 240, height: 300), seed: UInt64(index + 7)))
            card.contentMode = .scaleAspectFill
            card.clipsToBounds = true
            card.layer.cornerRadius = 18
            card.layer.cornerCurve = .continuous
            card.layer.borderColor = RoomPalette.background.cgColor
            card.layer.borderWidth = 2
            addSubview(card)
            cards.append(card)
        }
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggle)))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: 240, height: 112)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        arrange()
    }

    private func arrange() {
        for (index, card) in cards.enumerated() {
            let offset = CGFloat(index) - CGFloat(cards.count - 1) / 2
            card.bounds = CGRect(x: 0, y: 0, width: 86, height: 104)
            if spread {
                card.center = CGPoint(x: bounds.midX + offset * 96, y: bounds.midY)
                card.transform = .identity
            } else {
                card.center = CGPoint(x: 60 + CGFloat(index) * 34, y: bounds.midY + abs(offset) * 4)
                card.transform = CGAffineTransform(rotationAngle: offset * 0.12)
            }
        }
    }

    @objc private func toggle() {
        spread.toggle()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        UIView.animate(withDuration: 0.55, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.4) {
            self.arrange()
        }
    }
}

// MARK: - Typing dots

final class TypingDots: UIView {
    private let canvas = LiquidCanvasView()
    private let label = UILabel()
    private var clock: CFTimeInterval = 0

    init(name: String) {
        super.init(frame: .zero)
        canvas.liquidColor = UIColor(white: 1, alpha: 0.55)
        canvas.gloss = 0.4
        canvas.rimWidth = 3
        canvas.onUpdate = { [weak self] dt in self?.step(dt) }
        addSubview(canvas)
        label.text = "\(name) is typing…"
        label.font = .systemFont(ofSize: 14)
        label.textColor = RoomPalette.secondary
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 30)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        canvas.frame = CGRect(x: 14, y: 0, width: 60, height: bounds.height)
        label.sizeToFit()
        label.frame.origin = CGPoint(x: 70, y: bounds.midY - label.bounds.height / 2)
    }

    private func step(_ dt: CFTimeInterval) {
        clock += dt
        // Each dot hops in turn; close together they merge, apart they part like drops.
        canvas.shapes = (0..<3).map { i in
            let hop = max(0, sin(clock * 6.5 - Double(i) * 0.9))
            return .circle(center: CGPoint(x: 12 + CGFloat(i) * 11, y: bounds.midY - CGFloat(hop) * 6),
                           radius: 4.2 + CGFloat(hop) * 0.6, blend: 6)
        }
    }
}

// MARK: - Recording

/// The mic button, held: grows into a blob that quivers with the voice. Drag left past the threshold
/// and the blob tears off and falls into the bin; let go anywhere else to send.
final class RecordBlob: UIView {
    private let canvas = LiquidCanvasView()
    private let trash = UIImageView(image: UIImage(systemName: "trash"))
    private let timer = UILabel()
    private let hint = UILabel()
    private let mic: CGPoint
    private let level: () -> CGFloat
    private var dx: CGFloat = 0
    private var clock: CFTimeInterval = 0
    private var radius = Spring1D(22, stiffness: 14, dampingRatio: 0.5)
    private enum State { case recording, torn, sending }
    private var state = State.recording
    private var fall = IslandSpring(.zero, stiffness: 9, dampingRatio: 0.7)
    private var endTime: CFTimeInterval = 0
    var onFinish: ((_ sent: Bool, _ seconds: TimeInterval) -> Void)?

    init(in host: UIView, mic: CGPoint, level: @escaping () -> CGFloat) {
        self.mic = mic
        self.level = level
        super.init(frame: host.bounds)
        isUserInteractionEnabled = false
        host.addSubview(self)
        canvas.frame = bounds
        canvas.liquidColor = RoomPalette.orange
        canvas.gloss = 0.6
        canvas.rimWidth = 9
        canvas.onUpdate = { [weak self] dt in self?.step(dt) }
        addSubview(canvas)
        trash.tintColor = RoomPalette.secondary
        trash.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 22)
        trash.sizeToFit()
        trash.center = CGPoint(x: 40, y: mic.y)
        trash.alpha = 0
        addSubview(trash)
        timer.font = .monospacedDigitSystemFont(ofSize: 16, weight: .medium)
        timer.textColor = .white
        addSubview(timer)
        hint.text = "‹  Slide to cancel"
        hint.font = .systemFont(ofSize: 15)
        hint.textColor = RoomPalette.secondary
        hint.sizeToFit()
        hint.center = CGPoint(x: bounds.midX - 10, y: mic.y)
        addSubview(hint)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func move(by translation: CGFloat) {
        guard state == .recording else { return }
        dx = min(0, translation)
        trash.alpha = min(1, -dx / 60)
        hint.alpha = max(0, 1 + dx / 80)
        if dx < -150 {
            tear()
        }
    }

    func release() {
        guard state == .recording else { return }
        state = .sending
        endTime = clock
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// A little left of the mic, so the swollen blob stays on screen.
    private var blobCenter: CGPoint { CGPoint(x: mic.x - 24 + dx, y: mic.y) }

    private func tear() {
        state = .torn
        endTime = clock
        fall = IslandSpring(blobCenter, stiffness: 9, dampingRatio: 0.75)
        fall.velocity = CGVector(dx: -120, dy: -260)
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    private func step(_ dt: CFTimeInterval) {
        clock += dt
        let v = state == .recording ? level() : 0
        let seconds = Int(state == .recording ? clock : endTime)
        timer.text = String(format: "● %d:%02d", seconds / 60, seconds % 60)
        timer.sizeToFit()
        timer.center = CGPoint(x: 70, y: mic.y - 52)
        var shapes: [IslandFluidShape] = []
        var spikes: [IslandFluidSpike] = []
        switch state {
        case .recording:
            radius.step(toward: 30 + 16 * v + 1.5 * sin(clock * 8), deltaTime: dt)
            let r = radius.value
            let c = blobCenter
            shapes.append(.circle(center: c, radius: r, blend: 0))
            // Satellites orbit just inside the rim: louder voice, wilder blob.
            for i in 0..<3 {
                let angle = clock * (1.8 + Double(i) * 0.7) + Double(i) * 2.1
                let distance = r * 0.72 + 8 * v
                shapes.append(.circle(center: CGPoint(x: c.x + cos(angle) * distance, y: c.y + sin(angle) * distance),
                                      radius: 7 + 11 * v, blend: 12))
            }
            // Still rooted at the mic: dragging away stretches the neck thinner until it tears.
            shapes.append(.circle(center: mic, radius: 14, blend: 12))
            spikes.append(IslandFluidSpike(base: mic, tip: c, baseRadius: max(3, 12 + dx / 14), tipRadius: max(5, r * 0.5),
                                           blend: 10))
        case .torn:
            fall.step(toward: trash.center, deltaTime: dt)
            radius.step(toward: 0, deltaTime: dt)
            shapes.append(.circle(center: fall.position, radius: max(radius.value, 0) * 0.8, blend: 0))
            let t = clock - endTime
            shapes.append(.circle(center: mic, radius: 14 * max(0, 1 - t * 3), blend: 0))
            // The bin's lid swings open to catch it, then shuts.
            trash.transform = CGAffineTransform(rotationAngle: t < 0.45 ? -0.35 * sin(min(t / 0.45, 1) * .pi) : 0)
            if t > 0.55, radius.value < 1 {
                finish(sent: false)
                return
            }
        case .sending:
            radius.step(toward: 0, deltaTime: dt)
            shapes.append(.circle(center: blobCenter, radius: max(radius.value, 0), blend: 0))
            if clock - endTime > 0.25 {
                finish(sent: true)
                return
            }
        }
        canvas.shapes = shapes
        canvas.spikes = spikes
    }

    private func finish(sent: Bool) {
        canvas.isPaused = true
        UIView.animate(withDuration: 0.2) { self.alpha = 0 } completion: { _ in self.removeFromSuperview() }
        if !sent {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        onFinish?(sent, endTime)
    }
}
