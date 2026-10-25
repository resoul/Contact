import UIKit

class TrickChatPage: TrickPage, UITextFieldDelegate {
    let scroll = UIScrollView()
    let stack = UIStackView()
    let inputBar = UIView()
    let input = UITextField()
    let sendButton = UIButton(type: .custom)

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = trickPeople[0].name
        scroll.alwaysBounceVertical = true
        scroll.keyboardDismissMode = .interactive
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        inputBar.translatesAutoresizingMaskIntoConstraints = false
        inputBar.backgroundColor = TrickPalette.telegramBackground
        view.addSubview(inputBar)
        input.placeholder = "Сообщение"
        input.textColor = .white
        input.backgroundColor = TrickPalette.telegramPanel
        input.layer.cornerRadius = 20
        input.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 10))
        input.leftViewMode = .always
        input.keyboardAppearance = .dark
        input.returnKeyType = .send
        input.delegate = self
        input.translatesAutoresizingMaskIntoConstraints = false
        inputBar.addSubview(input)
        sendButton.backgroundColor = TrickPalette.telegramBlue
        sendButton.tintColor = .white
        sendButton.layer.cornerRadius = 20
        sendButton.setImage(UIImage(systemName: "arrow.up", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .bold)),
                            for: .normal)
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        inputBar.addSubview(sendButton)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: inputBar.topAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor),
            inputBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputBar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            inputBar.heightAnchor.constraint(equalToConstant: 58),
            input.leadingAnchor.constraint(equalTo: inputBar.leadingAnchor, constant: 10),
            input.centerYAnchor.constraint(equalTo: inputBar.centerYAnchor),
            input.heightAnchor.constraint(equalToConstant: 40),
            sendButton.leadingAnchor.constraint(equalTo: input.trailingAnchor, constant: 8),
            sendButton.trailingAnchor.constraint(equalTo: inputBar.trailingAnchor, constant: -10),
            sendButton.centerYAnchor.constraint(equalTo: inputBar.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 40),
            sendButton.heightAnchor.constraint(equalToConstant: 40),
        ])
        let seed = [("Привет! Как тебе новые эффекты?", false), ("Очень круто, особенно жидкие реакции 😍", true),
                    ("А попробуй эффекты сообщений и кружки", false), ("Сейчас попробую!", true)]
        for (text, outgoing) in seed {
            addBubble(text, outgoing: outgoing)
        }
    }

    @discardableResult
    func addBubble(_ text: String, outgoing: Bool) -> UIView {
        let bubble = TrickViews.bubble(text, outgoing: outgoing)
        stack.addArrangedSubview(TrickViews.row(bubble, outgoing: outgoing))
        return bubble
    }

    func scrollToBottom(animated: Bool) {
        view.layoutIfNeeded()
        let y = max(-scroll.adjustedContentInset.top,
                    scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height)
        scroll.setContentOffset(CGPoint(x: 0, y: y), animated: animated)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        sendTapped()
        return false
    }

    func sendTapped() {}
}


final class VanishModeDemoViewController: TrickChatPage, UIScrollViewDelegate {
    private let indicator = UIView()
    private let ring = CAShapeLayer()
    private let hintLabel = UILabel()
    private let banner = UILabel()
    private var armed = false
    private var vanish = false
    private let threshold: CGFloat = 100

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = trickPeople[2].name
        scroll.delegate = self
        sendButton.addAction(UIAction { [weak self] _ in self?.sendTapped() }, for: .touchUpInside)
        ring.fillColor = UIColor.clear.cgColor
        ring.strokeColor = UIColor.white.cgColor
        ring.lineWidth = 3
        ring.lineCap = .round
        ring.strokeEnd = 0
        indicator.layer.addSublayer(ring)
        let icon = UIImageView(image: UIImage(systemName: "moon.stars.fill"))
        icon.tintColor = .white
        icon.contentMode = .center
        icon.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        icon.tag = 1
        indicator.addSubview(icon)
        hintLabel.font = .systemFont(ofSize: 13, weight: .medium)
        hintLabel.textColor = TrickPalette.secondary
        hintLabel.textAlignment = .center
        indicator.addSubview(hintLabel)
        indicator.isUserInteractionEnabled = false
        view.insertSubview(indicator, belowSubview: inputBar)
        banner.font = .systemFont(ofSize: 13, weight: .semibold)
        banner.textColor = .white
        banner.textAlignment = .center
        banner.numberOfLines = 2
        banner.alpha = 0
        view.addSubview(banner)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scrollToBottom(animated: false)
        showHint("Потяните чат вверх у последнего сообщения", bottom: 150)
    }

    override func sendTapped() {
        guard let text = input.text, !text.isEmpty else { return }
        input.text = ""
        let bubble = addBubble(text, outgoing: true)
        styleBubble(bubble, outgoing: true)
        scrollToBottom(animated: true)
    }

    private var overscroll: CGFloat {
        let bottom = max(scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height,
                         -scroll.adjustedContentInset.top)
        return scroll.contentOffset.y - bottom
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let pull = max(overscroll, 0)
        let bottom = inputBar.frame.minY
        indicator.frame = CGRect(x: 0, y: bottom - pull + 6, width: view.bounds.width, height: 80)
        let center = CGPoint(x: indicator.bounds.midX, y: 22)
        ring.path = UIBezierPath(arcCenter: center, radius: 20, startAngle: -.pi / 2, endAngle: .pi * 1.5, clockwise: true).cgPath
        indicator.viewWithTag(1)?.center = center
        hintLabel.frame = CGRect(x: 0, y: 48, width: indicator.bounds.width, height: 18)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.strokeEnd = min(pull / threshold, 1)
        CATransaction.commit()
        indicator.alpha = min(1, pull / 30)
        let now = pull >= threshold
        hintLabel.text = now ? "Отпустите" : (vanish ? "Проведите вверх, чтобы выключить" : "Проведите вверх для исчезающего режима")
        if now != armed {
            armed = now
            UIImpactFeedbackGenerator(style: now ? .medium : .light).impactOccurred()
        }
    }

    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard armed, let window = view.window else { return }
        armed = false
        let origin = inputBar.convert(CGPoint(x: inputBar.bounds.midX, y: 0), to: window)
        let turningOn = !vanish
        LiquidThemeReveal.transition(in: window, from: origin, duration: 0.9, apply: {
            self.vanish = turningOn
            self.applyStyle()
        })
        if turningOn {
            sparkle(from: origin, in: window)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func applyStyle() {
        let background = vanish ? UIColor(red: 0.03, green: 0.02, blue: 0.08, alpha: 1) : TrickPalette.telegramBackground
        view.backgroundColor = background
        inputBar.backgroundColor = background
        input.placeholder = vanish ? "Сообщение исчезнет…" : "Сообщение"
        navigationItem.title = vanish ? "Исчезающий режим" : trickPeople[2].name
        for row in stack.arrangedSubviews {
            guard let bubble = row.subviews.first else { continue }
            let outgoing = bubble.frame.maxX > row.bounds.midX + 20
            styleBubble(bubble, outgoing: outgoing)
        }
        banner.text = "Исчезающий режим включён\nСообщения исчезнут, когда вы закроете чат"
        banner.frame = CGRect(x: 30, y: view.safeAreaInsets.top + 6, width: view.bounds.width - 60, height: 40)
        banner.alpha = vanish ? 1 : 0
        scroll.contentInset.top = vanish ? 50 : 0
    }

    private func styleBubble(_ bubble: UIView, outgoing: Bool) {
        if vanish {
            bubble.backgroundColor = outgoing ? UIColor(red: 0.5, green: 0.25, blue: 0.95, alpha: 1) : UIColor(white: 0.14, alpha: 1)
            bubble.layer.borderWidth = outgoing ? 0 : 1
            bubble.layer.borderColor = UIColor(white: 1, alpha: 0.15).cgColor
        } else {
            bubble.backgroundColor = outgoing ? TrickPalette.outgoing : TrickPalette.incoming
            bubble.layer.borderWidth = 0
        }
    }

    /// Little stars rising from the bottom as the dark floods in.
    private func sparkle(from point: CGPoint, in window: UIWindow) {
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = CGPoint(x: window.bounds.midX, y: point.y)
        emitter.emitterShape = .line
        emitter.emitterSize = CGSize(width: window.bounds.width, height: 1)
        let cell = CAEmitterCell()
        cell.contents = TrickViews.emojiImage("✦", size: 24).cgImage
        cell.color = UIColor(red: 0.8, green: 0.7, blue: 1, alpha: 1).cgColor
        cell.birthRate = 60
        cell.lifetime = 2
        cell.velocity = 260
        cell.velocityRange = 160
        cell.emissionLongitude = -.pi / 2
        cell.emissionRange = 0.5
        cell.scale = 0.4
        cell.scaleRange = 0.3
        cell.alphaSpeed = -0.5
        emitter.emitterCells = [cell]
        window.layer.addSublayer(emitter)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { emitter.birthRate = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { emitter.removeFromSuperlayer() }
    }
}

