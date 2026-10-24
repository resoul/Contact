//
//  LiquidIslandToast.swift
//  controller
//
//  A notification that drips out of the Dynamic Island: a drop forms under the island, tears off,
//  swells into a pill and settles with a jelly wobble. Drag it around (it stretches), flick it up
//  or wait — a countdown ring shows how long it stays — and it shrinks back into a drop that is sucked
//  into the island. With `onReply`, a tap makes
//  it flow taller into a reply field; sending shoots it back into the island as a drop.
//  Drawn by IslandFluidView; the text is ordinary UIKit on top, squashed together with the liquid.
//

import UIKit

final class LiquidIslandToast: IslandFluidView, UITextFieldDelegate {
    private static weak var current: LiquidIslandToast?

    /// Shows a toast in `window`, replacing the one already visible.
    @discardableResult
    static func show(in window: UIWindow, title: String, message: String? = nil, symbol: String? = nil,
                     duration: TimeInterval = 5, showsTimer: Bool = true, onTap: (() -> Void)? = nil,
                     onReply: ((String) -> Void)? = nil) -> LiquidIslandToast {
        current?.dismiss()
        let toast = LiquidIslandToast(title: title, message: message, symbol: symbol)
        toast.duration = duration
        toast.ring.isHidden = !showsTimer
        toast.onTap = onTap
        toast.onReply = onReply
        toast.install(in: window)
        toast.start()
        current = toast
        return toast
    }

    /// Seconds the toast stays before going home on its own; the countdown ring shows what is left.
    var duration: TimeInterval = 5
    /// Colors the countdown ring passes through, from a full timer to an empty one.
    var timerColors: [UIColor] {
        get { ring.colors }
        set { ring.colors = newValue }
    }
    var onTap: (() -> Void)?
    /// Makes the toast repliable: a tap grows it into a text field, Send calls this with the text.
    var onReply: ((String) -> Void)?

    private enum Phase: Equatable {
        case emerging
        case shown
        case dismissing
        case finished
    }

    private let content = UIView()
    private var toastHeight: CGFloat { expanded ? 124 : 64 }
    private var toastWidth: CGFloat = 340
    private let gap: CGFloat = 14

    private var phase = Phase.emerging
    private var phaseTime: CFTimeInterval = 0
    private var shownTime: CFTimeInterval = 0
    private var pillCenter = IslandSpring(.zero, stiffness: 15, dampingRatio: 0.55)
    /// Half width / half height, as a point so it can use the same spring.
    private var size = IslandSpring(CGPoint(x: 6, y: 6), stiffness: 17, dampingRatio: 0.4)
    private var neck: CGFloat = 22
    private var tornOff = false
    private var recoilTime: CFTimeInterval?
    private var drag: CGPoint?
    private var expanded = false
    private var sent = false
    private let replyField = UITextField()
    private let ring = CountdownRing()
    private var ringRemaining: CGFloat = 1

    private let rigidHaptic = UIImpactFeedbackGenerator(style: .rigid)
    private let softHaptic = UIImpactFeedbackGenerator(style: .soft)

    private init(title: String, message: String?, symbol: String?) {
        super.init(frame: .zero)
        gloss = 0.5
        rimWidth = 10
        isUserInteractionEnabled = true
        buildContent(title: title, message: message, symbol: symbol)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildContent(title: String, message: String?, symbol: String?) {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .white
        let messageLabel = UILabel()
        messageLabel.text = message
        messageLabel.font = .systemFont(ofSize: 13)
        messageLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        messageLabel.isHidden = message == nil
        let texts = UIStackView(arrangedSubviews: [titleLabel, messageLabel])
        texts.axis = .vertical
        texts.spacing = 1

        let icon = UIImageView(image: symbol.flatMap { UIImage(systemName: $0) })
        icon.tintColor = .white
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        icon.isHidden = symbol == nil
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [icon, texts, ring])
        row.spacing = 12
        row.alignment = .center

        replyField.attributedPlaceholder = NSAttributedString(
            string: "Reply…", attributes: [.foregroundColor: UIColor.white.withAlphaComponent(0.45)])
        replyField.textColor = .white
        replyField.tintColor = .white
        replyField.font = .systemFont(ofSize: 15)
        replyField.backgroundColor = UIColor.white.withAlphaComponent(0.13)
        replyField.layer.cornerRadius = 18
        replyField.layer.cornerCurve = .continuous
        replyField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
        replyField.leftViewMode = .always
        replyField.returnKeyType = .send
        replyField.enablesReturnKeyAutomatically = true
        replyField.delegate = self
        replyField.isHidden = true
        replyField.heightAnchor.constraint(equalToConstant: 38).isActive = true

        let column = UIStackView(arrangedSubviews: [row, replyField])
        column.axis = .vertical
        column.spacing = 12
        column.alignment = .fill
        column.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 26),
            column.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            column.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        content.alpha = 0
        addSubview(content)
    }

    override func install(in window: UIWindow) {
        super.install(in: window)
        toastWidth = min(window.bounds.width - 24, 360)
        content.bounds = CGRect(x: 0, y: 0, width: toastWidth, height: toastHeight)
    }

    private var restCenter: CGPoint {
        CGPoint(x: island.midX, y: island.maxY + gap + toastHeight / 2)
    }

    private func start() {
        pillCenter.position = CGPoint(x: island.midX, y: island.maxY - 6)
        rigidHaptic.prepare()
        isPaused = false
    }

    /// Picks up from a drop that is already hanging under the island (e.g. the typing indicator),
    /// instead of forming its own. Call right after `show`.
    func continueFrom(dropAt center: CGPoint, radius: CGFloat) {
        guard phase == .emerging else { return }
        pillCenter.position = center
        pillCenter.velocity = .zero
        size.position = CGPoint(x: radius, y: radius)
        size.velocity = .zero
        phaseTime = 0.12
    }

    /// Sends the toast back into the island. Safe to call more than once.
    func dismiss() {
        guard phase == .emerging || phase == .shown else { return }
        phase = .dismissing
        phaseTime = 0
        drag = nil
        softHaptic.prepare()
        if replyField.isFirstResponder {
            replyField.resignFirstResponder()
        }
        if sent {
            // Sent: it shoots back into the island instead of drifting.
            pillCenter.stiffness = 26
            pillCenter.dampingRatio = 0.7
        }
        UIView.animate(withDuration: 0.12) { self.content.alpha = 0 }
    }

    // MARK: Touches

    /// Only the toast itself takes touches; everything else falls through to the app.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard phase == .shown || phase == .emerging else { return false }
        let half = size.position
        return abs(point.x - pillCenter.position.x) <= half.x && abs(point.y - pillCenter.position.y) <= half.y + 6
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard phase == .shown || phase == .emerging else { return }
        let t = gesture.translation(in: self)
        switch gesture.state {
        case .began, .changed:
            // Free upward, heavy rubber band downward and sideways.
            drag = CGPoint(x: t.x * 0.4, y: t.y < 0 ? t.y : t.y * 0.35)
        default:
            let flung = gesture.velocity(in: self).y < -400 || t.y < -30
            drag = nil
            if flung {
                dismiss()
            } else {
                shownTime = 0   // give it its full time again after being played with
            }
        }
    }

    @objc private func handleTap() {
        guard !expanded else { return }
        if onReply != nil {
            startReply()
            return
        }
        // Squash: wider and flatter for a moment, then it wobbles back.
        size.velocity.dx += 140
        size.velocity.dy -= 160
        onTap?()
    }

    /// Flows taller into a reply field; the toast stays until the reply is sent.
    func startReply() {
        guard onReply != nil, !expanded, phase == .emerging || phase == .shown else { return }
        expanded = true
        // Waiting for the reply now: no countdown.
        UIView.animate(withDuration: 0.15) { self.ring.alpha = 0 }
        content.bounds = CGRect(x: 0, y: 0, width: toastWidth, height: toastHeight)
        replyField.isHidden = false
        replyField.alpha = 0
        UIView.animate(withDuration: 0.25, delay: 0.08) { self.replyField.alpha = 1 }
        size.velocity.dy += 80
        replyField.becomeFirstResponder()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let text = textField.text ?? ""
        guard !text.isEmpty else { return false }
        sent = true
        onReply?(text)
        rigidHaptic.impactOccurred(intensity: 0.7)
        dismiss()
        return false
    }

    // MARK: Simulation

    override func update(deltaTime: CFTimeInterval) {
        phaseTime += deltaTime
        let mouth = islandMouth
        let full = CGPoint(x: toastWidth / 2, y: toastHeight / 2)
        var centerTarget = restCenter
        var sizeTarget = full

        switch phase {
        case .emerging:
            if phaseTime < 0.2 {
                // A drop forms under the island first.
                centerTarget = CGPoint(x: mouth.x, y: mouth.y + 20)
                sizeTarget = CGPoint(x: 14, y: 14)
            }
            // The neck thins after the drop forms and tears as the pill pulls away.
            neck = 22 * max(0, 1 - max(0, phaseTime - 0.2) / 0.22)
            if neck == 0, !tornOff {
                tornOff = true
                recoilTime = 0
                rigidHaptic.impactOccurred(intensity: 0.8)
            }
            if size.position.x > full.x * 0.82, content.alpha == 0 {
                UIView.animate(withDuration: 0.18) { self.content.alpha = 1 }
            }
            if phaseTime > 0.75 {
                phase = .shown
                shownTime = 0
            }
        case .shown:
            if drag == nil, !expanded {
                shownTime += deltaTime
                if shownTime > duration {
                    dismiss()
                }
            }
        case .dismissing:
            let shrink = phaseTime > 0.08
            sizeTarget = shrink ? CGPoint(x: 11, y: 11) : full
            centerTarget = phaseTime > 0.16 ? CGPoint(x: mouth.x, y: mouth.y + 6) : pillCenter.position
            // The neck reaches out again once the drop is close, and swallows it.
            let distance = pillCenter.position.distance(to: mouth)
            neck = distance < 70 ? 20 : 0
            if distance < 16, size.position.x < 16 {
                phase = .finished
                phaseTime = 0
                recoilTime = 0
                softHaptic.impactOccurred()
            }
        case .finished:
            if phaseTime > 0.9 {
                removeFromSuperview()
                isPaused = true
            }
        }

        if let drag {
            centerTarget = CGPoint(x: restCenter.x + drag.x, y: restCenter.y + drag.y)
            // Pulled down it stretches tall and thin, like a strand of jelly.
            let stretch = max(drag.y, 0)
            sizeTarget = CGPoint(x: full.x - stretch * 0.25, y: full.y + stretch * 0.45)
        }
        pillCenter.step(toward: centerTarget, deltaTime: deltaTime)
        size.step(toward: sizeTarget, deltaTime: deltaTime)
        if let t = recoilTime {
            recoilTime = t > 1 ? nil : t + deltaTime
        }

        updateRing(deltaTime: deltaTime)
        rebuildShapes()
        layoutContent(full: full)
    }

    /// Drains with the time left; refills smoothly when the toast gets its time back after a drag.
    private func updateRing(deltaTime: CFTimeInterval) {
        guard phase == .shown || phase == .emerging else { return }
        let target = phase == .shown ? CGFloat(max(0, 1 - shownTime / duration)) : 1
        if target > ringRemaining {
            ringRemaining += (target - ringRemaining) * min(1, CGFloat(deltaTime) * 10)
        } else {
            ringRemaining = target
        }
        ring.update(remaining: ringRemaining, secondsLeft: Int(ceil(Double(ringRemaining) * duration)))
    }

    private func rebuildShapes() {
        var newShapes: [IslandFluidShape] = []
        if phase != .finished {
            let half = CGSize(width: max(size.position.x, 1), height: max(size.position.y, 1))
            newShapes.append(IslandFluidShape(center: pillCenter.position, halfSize: half,
                                              cornerRadius: min(half.width, half.height, 32), blend: neck))
        }
        if let t = recoilTime {
            let mouth = islandMouth
            let extent = 11 * exp(-7 * t) * cos(18 * t)
            newShapes.append(.circle(center: CGPoint(x: mouth.x, y: mouth.y - 7 + max(extent, -4)), radius: 7, blend: 10))
        }
        shapes = newShapes
    }

    /// Text rides on the liquid and is squashed and stretched with it.
    private func layoutContent(full: CGPoint) {
        content.center = pillCenter.position
        let sx = max(size.position.x / full.x, 0.01), sy = max(size.position.y / full.y, 0.01)
        content.transform = CGAffineTransform(scaleX: sx, y: sy)
    }
}

/// A small countdown ring with the seconds left in the middle. Its color runs through `colors`
/// as the time drains: calm while there is plenty left, urgent at the end.
private final class CountdownRing: UIView {
    var colors: [UIColor] = [.systemGreen, .systemYellow, .systemOrange, .systemRed]

    private let track = CAShapeLayer()
    private let progress = CAShapeLayer()
    private let label = UILabel()
    private let diameter: CGFloat = 26

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        let path = UIBezierPath(arcCenter: CGPoint(x: diameter / 2, y: diameter / 2), radius: diameter / 2 - 1.5,
                                startAngle: -.pi / 2, endAngle: 1.5 * .pi, clockwise: true).cgPath
        for shape in [track, progress] {
            shape.path = path
            shape.fillColor = nil
            shape.strokeColor = UIColor.white.withAlphaComponent(0.2).cgColor
            shape.lineWidth = 2.5
            shape.lineCap = .round
            layer.addSublayer(shape)
        }
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        label.textColor = UIColor.white.withAlphaComponent(0.85)
        label.textAlignment = .center
        label.frame = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        addSubview(label)
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: diameter, height: diameter)
    }

    func update(remaining: CGFloat, secondsLeft: Int) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progress.strokeEnd = max(0, min(1, remaining))
        progress.strokeColor = color(at: 1 - remaining).cgColor
        CATransaction.commit()
        let text = "\(max(secondsLeft, 0))"
        if label.text != text {
            label.text = text
        }
    }

    /// Linear blend between neighbouring stops of `colors`, `t` from 0 (first) to 1 (last).
    private func color(at t: CGFloat) -> UIColor {
        guard colors.count > 1 else { return colors.first ?? .white }
        let scaled = max(0, min(1, t)) * CGFloat(colors.count - 1)
        let index = min(Int(scaled), colors.count - 2)
        let f = scaled - CGFloat(index)
        var a = (r: CGFloat(0), g: CGFloat(0), b: CGFloat(0), alpha: CGFloat(0))
        var b = a
        colors[index].resolvedColor(with: traitCollection).getRed(&a.r, green: &a.g, blue: &a.b, alpha: &a.alpha)
        colors[index + 1].resolvedColor(with: traitCollection).getRed(&b.r, green: &b.g, blue: &b.b, alpha: &b.alpha)
        return UIColor(red: a.r + (b.r - a.r) * f, green: a.g + (b.g - a.g) * f,
                       blue: a.b + (b.b - a.b) * f, alpha: a.alpha + (b.alpha - a.alpha) * f)
    }
}
