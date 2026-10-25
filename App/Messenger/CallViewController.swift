//
//  CallViewController.swift
//  controller
//
//  A Mini-Telegram call: a flowing gradient (blue-violet while ringing, green once connected),
//  soft blobs around the avatar that wobble and swell with the other person's voice, the emoji
//  key pill that opens into an explanation, and round buttons that slide in and out.
//

import UIKit

final class CallViewController: UIViewController {
    private let person: ChannelPerson
    private let ringing = FluidMeshGradientView()
    private let connected = FluidMeshGradientView()
    private let blobs = CallBlobs()
    private let avatar = UIImageView()
    private let name = Views.label(size: 28, weight: .semibold, color: .white)
    private let status = Views.label(size: 16, color: UIColor(white: 1, alpha: 0.8))
    private let keyPill = UIButton(type: .system)
    private let keyPanel = UIView()
    private var buttons: [UIButton] = []
    private var buttonLabels: [UILabel] = []
    private var timer: Timer?
    private var started: Date?
    private var keyOpen = false
    private var ended = false

    init(person: ChannelPerson) {
        self.person = person
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = .black
        ringing.colors = [UIColor(red: 0.33, green: 0.36, blue: 0.95, alpha: 1), UIColor(red: 0.55, green: 0.3, blue: 0.9, alpha: 1),
                          UIColor(red: 0.2, green: 0.55, blue: 0.95, alpha: 1), UIColor(red: 0.72, green: 0.35, blue: 0.85, alpha: 1)]
        connected.colors = [UIColor(red: 0.2, green: 0.7, blue: 0.5, alpha: 1), UIColor(red: 0.15, green: 0.55, blue: 0.75, alpha: 1),
                            UIColor(red: 0.45, green: 0.8, blue: 0.4, alpha: 1), UIColor(red: 0.1, green: 0.6, blue: 0.6, alpha: 1)]
        for gradient in [ringing, connected] {
            gradient.speed = 0.6
            gradient.warp = 0.5
            gradient.frame = view.bounds
            gradient.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(gradient)
        }
        connected.alpha = 0
        connected.isPaused = true

        view.addSubview(blobs)
        avatar.image = ChannelAvatar.image(for: person, size: 140)
        view.addSubview(avatar)
        name.text = person.name
        name.textAlignment = .center
        view.addSubview(name)
        status.text = "Calling…"
        status.textAlignment = .center
        view.addSubview(status)

        keyPill.setTitle("🔒", for: .normal)
        keyPill.titleLabel?.font = .systemFont(ofSize: 18)
        keyPill.backgroundColor = Palette.glass
        keyPill.layer.cornerRadius = 18
        keyPill.addAction(UIAction { [weak self] _ in self?.toggleKey() }, for: .touchUpInside)
        view.addSubview(keyPill)
        keyPanel.backgroundColor = UIColor(white: 0, alpha: 0.25)
        keyPanel.layer.cornerRadius = 22
        keyPanel.alpha = 0
        let keyText = Views.label("Your call is encrypted.\nIf your emojis match, no one else can listen.",
                                    size: 15, color: .white)
        keyText.numberOfLines = 0
        keyText.textAlignment = .center
        keyText.tag = 1
        keyPanel.addSubview(keyText)
        view.addSubview(keyPanel)

        let items: [(String, String, UIColor)] = [("speaker.wave.2.fill", "speaker", Palette.glass),
                                                   ("video.fill", "video", Palette.glass),
                                                   ("mic.slash.fill", "mute", Palette.glass),
                                                   ("phone.down.fill", "end", Palette.red)]
        for (index, item) in items.enumerated() {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: item.0, withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)),
                            for: .normal)
            button.accessibilityLabel = item.1
            button.accessibilityIdentifier = "contact.call.action.\(index)"
            button.tintColor = .white
            button.backgroundColor = item.2
            button.layer.cornerRadius = 32
            button.addAction(UIAction { [weak self, weak button] _ in
                guard let self, let button else { return }
                index == 3 ? self.end() : self.toggle(button)
            }, for: .touchUpInside)
            view.addSubview(button)
            buttons.append(button)
            let label = Views.label(item.1, size: 12, color: .white)
            label.textAlignment = .center
            view.addSubview(label)
            buttonLabels.append(label)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        let center = CGPoint(x: width / 2, y: view.bounds.height * 0.33)
        blobs.frame = CGRect(x: center.x - 150, y: center.y - 150, width: 300, height: 300)
        avatar.frame = CGRect(x: center.x - 70, y: center.y - 70, width: 140, height: 140)
        avatar.layer.cornerRadius = 70
        avatar.clipsToBounds = true
        name.frame = CGRect(x: 20, y: center.y + 112, width: width - 40, height: 34)
        status.frame = CGRect(x: 20, y: center.y + 148, width: width - 40, height: 20)
        let pillWidth: CGFloat = keyOpen || started != nil ? 132 : 44
        if !keyOpen {
            keyPill.frame = CGRect(x: width - pillWidth - 16, y: view.safeAreaInsets.top + 8, width: pillWidth, height: 36)
        }
        keyPanel.frame = CGRect(x: 24, y: view.safeAreaInsets.top + 60, width: width - 48, height: 120)
        keyPanel.viewWithTag(1)?.frame = keyPanel.bounds.insetBy(dx: 16, dy: 12)
        let spacing = (width - 32) / 4
        for (index, button) in buttons.enumerated() {
            let x = 16 + spacing * (CGFloat(index) + 0.5)
            button.bounds = CGRect(x: 0, y: 0, width: 64, height: 64)
            button.center = CGPoint(x: x, y: view.bounds.height - view.safeAreaInsets.bottom - 70)
            buttonLabels[index].frame = CGRect(x: x - 45, y: button.center.y + 38, width: 90, height: 16)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard started == nil, !ended else { return }
        for (index, button) in buttons.enumerated() {
            let label = buttonLabels[index]
            button.transform = CGAffineTransform(translationX: 0, y: 160)
            label.transform = button.transform
            UIView.animate(withDuration: 0.6, delay: Double(index) * 0.05, usingSpringWithDamping: 0.75, initialSpringVelocity: 0) {
                button.transform = .identity
                label.transform = .identity
            }
        }
        avatar.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
        UIView.animate(withDuration: 0.7, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0) {
            self.avatar.transform = .identity
        }
        blobs.ringing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in self?.connect() }
    }

    private func connect() {
        guard !ended else { return }
        started = Date()
        blobs.ringing = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        connected.isPaused = false
        UIView.animate(withDuration: 1.2, animations: { self.connected.alpha = 1 }, completion: { _ in
            self.ringing.isPaused = true
        })
        keyPill.setTitle("🐶 🍉 🚀 🎸", for: .normal)
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0) {
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateTime() }
        }
        updateTime()
    }

    private func updateTime() {
        guard let started else { return }
        let seconds = Int(Date().timeIntervalSince(started))
        status.text = String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func toggle(_ button: UIButton) {
        let on = button.backgroundColor != .white
        UISelectionFeedbackGenerator().selectionChanged()
        UIView.animate(withDuration: 0.2) {
            button.backgroundColor = on ? .white : Palette.glass
            button.tintColor = on ? .black : .white
        }
        Views.pop(button, scale: 0.9)
    }

    private func toggleKey() {
        guard started != nil else { return }
        keyOpen.toggle()
        let width = view.bounds.width
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0) {
            if self.keyOpen {
                self.keyPill.frame = CGRect(x: (width - 200) / 2, y: self.view.safeAreaInsets.top + 8, width: 200, height: 44)
                self.keyPill.titleLabel?.font = .systemFont(ofSize: 28)
                self.keyPanel.alpha = 1
                self.keyPanel.transform = .identity
            } else {
                self.keyPill.frame = CGRect(x: width - 148, y: self.view.safeAreaInsets.top + 8, width: 132, height: 36)
                self.keyPill.titleLabel?.font = .systemFont(ofSize: 18)
                self.keyPanel.alpha = 0
            }
        }
        if keyOpen {
            keyPanel.transform = CGAffineTransform(translationX: 0, y: -30).scaledBy(x: 0.9, y: 0.9)
        }
    }

    private func end() {
        guard !ended else { return }
        ended = true
        timer?.invalidate()
        status.text = "Call ended"
        blobs.fade()
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        for (index, button) in buttons.enumerated() {
            UIView.animate(withDuration: 0.4, delay: Double(3 - index) * 0.04, options: .curveEaseIn) {
                button.transform = CGAffineTransform(translationX: 0, y: 180)
                self.buttonLabels[index].transform = button.transform
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            self?.dismiss(animated: true)
        }
    }
}

/// Telegram's call blobs: two translucent wobbly shapes around the avatar. Ringing they pulse
/// slowly; in the call they swell and ripple with the (simulated) voice.
final class CallBlobs: UIView {
    var ringing = false

    private let outer = CAShapeLayer()
    private let inner = CAShapeLayer()
    private var link: CADisplayLink?
    private var lastTime: CFTimeInterval?
    private var time: CGFloat = 0
    private var speech = SpeechSimulator(energy: 1)
    private var level: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        outer.fillColor = UIColor(white: 1, alpha: 0.13).cgColor
        inner.fillColor = UIColor(white: 1, alpha: 0.2).cgColor
        layer.addSublayer(outer)
        layer.addSublayer(inner)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        link?.invalidate()
        link = nil
        guard window != nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func fade() {
        UIView.animate(withDuration: 0.5) { self.alpha = 0 }
    }

    @objc private func tick(_ link: CADisplayLink) {
        let dt = lastTime.map { min(link.timestamp - $0, 1.0 / 30) } ?? 1.0 / 60
        lastTime = link.timestamp
        time += CGFloat(dt)
        let target: CGFloat
        if ringing {
            target = 0.25 + 0.25 * (sin(time * 3) * 0.5 + 0.5)
        } else {
            speech.step(dt)
            target = speech.level
        }
        level += (target - level) * min(1, CGFloat(dt) * 8)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        outer.path = blob(radius: 92 + level * 34, wobble: 0.07 + level * 0.07, speed: 0.9, seed: 0)
        inner.path = blob(radius: 80 + level * 20, wobble: 0.05 + level * 0.05, speed: 1.3, seed: 2.7)
        CATransaction.commit()
    }

    /// A closed smooth curve through points at a wobbling radius (Catmull-Rom → cubic Béziers).
    private func blob(radius: CGFloat, wobble: CGFloat, speed: CGFloat, seed: CGFloat) -> CGPath {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let count = 9
        let points: [CGPoint] = (0..<count).map { index in
            let angle = CGFloat(index) / CGFloat(count) * .pi * 2 + time * 0.2 * speed
            let noise = sin(angle * 3 + time * 1.7 * speed + seed) * 0.6 + sin(angle * 5 - time * 1.1 * speed + seed * 2) * 0.4
            let r = radius * (1 + wobble * noise)
            return CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
        }
        let path = UIBezierPath()
        path.move(to: points[0])
        for index in 0..<count {
            let p0 = points[(index - 1 + count) % count], p1 = points[index]
            let p2 = points[(index + 1) % count], p3 = points[(index + 2) % count]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, controlPoint1: c1, controlPoint2: c2)
        }
        path.close()
        return path.cgPath
    }
}
