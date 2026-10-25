//
//  ParticleMorphDemoViewController.swift
//  controller
//
//  All six ParticleMorphEngine scenarios behind one segmented control.
//

import UIKit

final class ParticleMorphDemoViewController: UIViewController {
    private let modes = ["Pay", "AI", "VIP", "Load"]
    private let picker: UISegmentedControl
    private let container = UIView()
    private var scene: (UIView & ParticleDemoScene)?

    init() {
        picker = UISegmentedControl(items: modes)
        super.init(nibName: nil, bundle: nil)
        title = "Particle Morph"
        overrideUserInterfaceStyle = .dark
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.03, green: 0.03, blue: 0.06, alpha: 1)

        picker.selectedSegmentIndex = 0
        picker.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        container.clipsToBounds = true

        for subview in [picker, container] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            picker.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            picker.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            picker.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            container.topAnchor.constraint(equalTo: picker.bottomAnchor, constant: 10),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        modeChanged()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        scene?.activeEngine?.isPaused = false
        navigationController?.overrideUserInterfaceStyle = .dark   // legible title over the dark screen
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        scene?.activeEngine?.isPaused = true
        navigationController?.overrideUserInterfaceStyle = .unspecified
    }

    @objc private func modeChanged() {
        scene?.removeFromSuperview()
        let next: UIView & ParticleDemoScene
        switch picker.selectedSegmentIndex {
        case 0: next = PaywallDemoScene()
        case 1: next = VoiceDemoScene()
        case 2: next = BadgeDemoScene()
        case 3: next = LoaderDemoScene()
        default: next = LoaderDemoScene()
        }
        next.frame = container.bounds
        next.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(next)
        scene = next
    }


}

private protocol ParticleDemoScene {
    var activeEngine: ParticleMorphEngine? { get }
}

private func makeHint(_ text: String) -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = .preferredFont(forTextStyle: .footnote)
    label.textColor = UIColor(white: 1, alpha: 0.55)
    label.textAlignment = .center
    label.numberOfLines = 0
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
}

private func makeButton(_ title: String, symbol: String? = nil, color: UIColor = .systemIndigo) -> UIButton {
    var configuration = UIButton.Configuration.filled()
    configuration.title = title
    configuration.image = symbol.flatMap { UIImage(systemName: $0) }
    configuration.imagePadding = 8
    configuration.baseBackgroundColor = color
    configuration.baseForegroundColor = .white
    configuration.cornerStyle = .capsule
    configuration.buttonSize = .large
    let button = UIButton(configuration: configuration)
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
}

// MARK: - 1. Paywall

private final class PaywallDemoScene: UIView, ParticleDemoScene {
    private let payButton = UIButton(type: .system)
    private let resultLabel = UILabel()
    private let againButton = makeButton("Again", symbol: "arrow.counterclockwise", color: UIColor(white: 0.18, alpha: 1))
    private lazy var animator = PaywallSuccessAnimator(button: payButton, container: self)

    var activeEngine: ParticleMorphEngine? { animator.engine }

    override init(frame: CGRect) {
        super.init(frame: frame)
        let title = UILabel()
        title.text = "Premium"
        title.font = .systemFont(ofSize: 40, weight: .heavy)
        title.textColor = .white
        let features = ["Unlimited projects", "Metal-powered effects", "Priority support"].map { text -> UIView in
            let label = UILabel()
            label.text = text
            label.textColor = UIColor(white: 1, alpha: 0.8)
            let icon = UIImageView(image: UIImage(systemName: "checkmark.seal.fill"))
            icon.tintColor = .systemIndigo
            icon.setContentHuggingPriority(.required, for: .horizontal)
            let row = UIStackView(arrangedSubviews: [icon, label])
            row.spacing = 10
            return row
        }
        let stack = UIStackView(arrangedSubviews: [title] + features)
        stack.axis = .vertical
        stack.spacing = 14
        stack.setCustomSpacing(28, after: title)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        var configuration = UIButton.Configuration.filled()
        configuration.baseBackgroundColor = UIColor(red: 0.45, green: 0.3, blue: 1.0, alpha: 1)
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .large
        configuration.title = "Pay $4.99"
        configuration.attributedTitle?.font = .systemFont(ofSize: 19, weight: .bold)
        payButton.configuration = configuration
        payButton.addTarget(self, action: #selector(pay), for: .touchUpInside)
        payButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(payButton)

        resultLabel.text = "Payment complete"
        resultLabel.font = .systemFont(ofSize: 22, weight: .bold)
        resultLabel.textColor = UIColor(red: 0.4, green: 1.0, blue: 0.6, alpha: 1)
        resultLabel.alpha = 0
        resultLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(resultLabel)
        againButton.alpha = 0
        againButton.addTarget(self, action: #selector(again), for: .touchUpInside)
        addSubview(againButton)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 40),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
            payButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            payButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
            payButton.heightAnchor.constraint(equalToConstant: 60),
            payButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -150),
            resultLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            resultLabel.topAnchor.constraint(equalTo: payButton.bottomAnchor, constant: 56),
            againButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            againButton.topAnchor.constraint(equalTo: resultLabel.bottomAnchor, constant: 16),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func pay() {
        payButton.configuration?.showsActivityIndicator = true
        payButton.isUserInteractionEnabled = false
        // Pretend to wait for the server, then morph.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            self.payButton.configuration?.showsActivityIndicator = false
            self.payButton.layoutIfNeeded()
            self.animator.trigger { [weak self] in
                UIView.animate(withDuration: 0.4) {
                    self?.resultLabel.alpha = 1
                    self?.againButton.alpha = 1
                }
            }
        }
    }

    @objc private func again() {
        animator.reset()
        payButton.isUserInteractionEnabled = true
        resultLabel.alpha = 0
        againButton.alpha = 0
    }
}

// MARK: - 2. Tab bar

private final class TabBarDemoScene: UIView, ParticleDemoScene {
    private let tabs: [(symbol: String, title: String, color: UIColor)] = [
        ("house.fill", "Home", UIColor(red: 0.3, green: 0.75, blue: 1.0, alpha: 1)),
        ("magnifyingglass", "Search", UIColor(red: 0.75, green: 0.45, blue: 1.0, alpha: 1)),
        ("heart.fill", "Likes", UIColor(red: 1.0, green: 0.35, blue: 0.5, alpha: 1)),
        ("person.fill", "Profile", UIColor(red: 1.0, green: 0.75, blue: 0.3, alpha: 1)),
    ]
    private let bar: MorphingTabBar
    private let pageIcon = UIImageView()
    private let pageTitle = UILabel()

    var activeEngine: ParticleMorphEngine? { bar.engine }

    override init(frame: CGRect) {
        bar = MorphingTabBar(items: tabs.map { MorphingTabBarItem(symbolName: $0.symbol, title: $0.title, accentColor: $0.color) })
        super.init(frame: frame)
        pageIcon.contentMode = .scaleAspectFit
        pageIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 64, weight: .bold)
        pageTitle.font = .systemFont(ofSize: 28, weight: .bold)
        let hint = makeHint("Tap a tab or swipe left / right")
        let page = UIStackView(arrangedSubviews: [pageIcon, pageTitle, hint])
        page.axis = .vertical
        page.alignment = .center
        page.spacing = 12
        page.translatesAutoresizingMaskIntoConstraints = false
        addSubview(page)
        bar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar)
        NSLayoutConstraint.activate([
            page.centerXAnchor.constraint(equalTo: centerXAnchor),
            page.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -40),
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        bar.onSelect = { [weak self] index in self?.showPage(index) }
        for direction in [UISwipeGestureRecognizer.Direction.left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
            swipe.direction = direction
            addGestureRecognizer(swipe)
        }
        showPage(0)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
        let step = gesture.direction == .left ? 1 : -1
        bar.select(min(max(bar.selectedIndex + step, 0), tabs.count - 1))
    }

    private func showPage(_ index: Int) {
        pageIcon.image = UIImage(systemName: tabs[index].symbol)
        pageIcon.tintColor = tabs[index].color
        pageTitle.text = tabs[index].title
        pageTitle.textColor = tabs[index].color
    }
}

// MARK: - 3. AI voice

private final class VoiceDemoScene: UIView, ParticleDemoScene {
    private let voice = VoiceAssistantParticleView()
    private let statusLabel = UILabel()
    private let talkButton = makeButton("Hold to talk", symbol: "mic.fill", color: UIColor(red: 0.2, green: 0.4, blue: 1.0, alpha: 1))
    private let answers = ["Hello, User", "Sunny, +18°", "Done!\nAnything else?", "Metal × 60K"]
    private var answerIndex = 0
    private var isTalking = false
    private var speechTime: Float = 0

    var activeEngine: ParticleMorphEngine? { voice.engine }

    override init(frame: CGRect) {
        super.init(frame: frame)
        voice.translatesAutoresizingMaskIntoConstraints = false
        addSubview(voice)
        statusLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        statusLabel.textColor = UIColor(white: 1, alpha: 0.6)
        statusLabel.text = "Listening sphere"
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusLabel)
        addSubview(talkButton)
        NSLayoutConstraint.activate([
            voice.topAnchor.constraint(equalTo: topAnchor),
            voice.leadingAnchor.constraint(equalTo: leadingAnchor),
            voice.trailingAnchor.constraint(equalTo: trailingAnchor),
            voice.bottomAnchor.constraint(equalTo: bottomAnchor),
            statusLabel.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            statusLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            talkButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            talkButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -32),
        ])
        talkButton.addTarget(self, action: #selector(startTalking), for: .touchDown)
        talkButton.addTarget(self, action: #selector(stopTalking), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        // No microphone here: a synthetic "speech" envelope stands in for the input level.
        let previous = voice.engine?.onFrame
        voice.engine?.onFrame = { [weak self] engine, deltaTime in
            guard let self else { return }
            if self.isTalking {
                self.speechTime += Float(deltaTime)
                let t = self.speechTime
                let syllables = max(0, sin(t * 7.3) * 0.55 + sin(t * 2.9 + 1) * 0.35 + sin(t * 17) * 0.15)
                self.voice.audioVolume = min(syllables + 0.15, 1)
            } else {
                self.voice.audioVolume = 0
            }
            previous?(engine, deltaTime)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func startTalking() {
        isTalking = true
        statusLabel.text = "Listening…"
        if voice.isShowingText { voice.showSphere() }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @objc private func stopTalking() {
        guard isTalking else { return }
        isTalking = false
        statusLabel.text = "Thinking…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, !self.isTalking else { return }
            self.statusLabel.text = "Answer"
            self.voice.show(text: self.answers[self.answerIndex % self.answers.count])
            self.answerIndex += 1
        }
    }
}

// MARK: - 4. Thanos snap

private final class ThanosDemoScene: UIView, ParticleDemoScene {
    private let card = DisintegratingCardView()
    private let undoButton = makeButton("Undo", symbol: "arrow.uturn.backward", color: UIColor(white: 0.2, alpha: 1))
    private let deleteButton = makeButton("Delete", symbol: "trash", color: .systemRed)

    var activeEngine: ParticleMorphEngine? { card.engine }

    override init(frame: CGRect) {
        super.init(frame: frame)
        buildCard()
        let hint = makeHint("Swipe the card or tap Delete")
        addSubview(hint)
        undoButton.alpha = 0
        undoButton.addTarget(self, action: #selector(undo), for: .touchUpInside)
        deleteButton.addTarget(self, action: #selector(snap), for: .touchUpInside)
        addSubview(undoButton)
        addSubview(deleteButton)
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: centerXAnchor),
            card.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -60),
            card.widthAnchor.constraint(equalToConstant: 330),
            card.heightAnchor.constraint(equalToConstant: 210),
            hint.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 20),
            hint.centerXAnchor.constraint(equalTo: centerXAnchor),
            deleteButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            deleteButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -32),
            undoButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            undoButton.bottomAnchor.constraint(equalTo: deleteButton.bottomAnchor),
        ])
        for direction in [UISwipeGestureRecognizer.Direction.left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(snap))
            swipe.direction = direction
            card.addGestureRecognizer(swipe)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildCard() {
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = UIColor(white: 0.97, alpha: 1)
        card.layer.cornerRadius = 26
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true
        addSubview(card)

        let header = GradientView(colors: [UIColor(red: 1.0, green: 0.45, blue: 0.3, alpha: 1),
                                           UIColor(red: 0.95, green: 0.25, blue: 0.6, alpha: 1),
                                           UIColor(red: 0.45, green: 0.3, blue: 1.0, alpha: 1)])
        let icon = UIImageView(image: UIImage(systemName: "sparkles",
                                              withConfiguration: UIImage.SymbolConfiguration(pointSize: 40, weight: .bold)))
        icon.tintColor = .white
        let title = UILabel()
        title.text = "Weekend in Lisbon"
        title.font = .systemFont(ofSize: 20, weight: .bold)
        title.textColor = .black
        let body = UILabel()
        body.text = "3 photos · 2 notes · shared with Anna"
        body.font = .systemFont(ofSize: 14)
        body.textColor = .darkGray
        for subview in [header, icon, title, body] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: card.topAnchor),
            header.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 120),
            icon.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            title.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 16),
            title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            body.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            body.leadingAnchor.constraint(equalTo: title.leadingAnchor),
        ])
    }

    @objc private func snap() {
        guard !card.isDisintegrated else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        card.disintegrate()
        UIView.animate(withDuration: 0.3) {
            self.deleteButton.alpha = 0
            self.undoButton.alpha = 1
        }
    }

    @objc private func undo() {
        card.revert()
        UIView.animate(withDuration: 0.3) {
            self.deleteButton.alpha = 1
            self.undoButton.alpha = 0
        }
    }
}

private final class GradientView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }

    init(colors: [UIColor]) {
        super.init(frame: .zero)
        let gradient = layer as! CAGradientLayer
        gradient.colors = colors.map(\.cgColor)
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - 5. VIP badge

private final class BadgeDemoScene: UIView, ParticleDemoScene {
    private let badge = MagneticBadgeView()

    var activeEngine: ParticleMorphEngine? { badge.engine }

    override init(frame: CGRect) {
        super.init(frame: frame)
        badge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badge)
        let hint = makeHint("Touch and drag across the badge")
        addSubview(hint)
        NSLayoutConstraint.activate([
            badge.topAnchor.constraint(equalTo: topAnchor),
            badge.leadingAnchor.constraint(equalTo: leadingAnchor),
            badge.trailingAnchor.constraint(equalTo: trailingAnchor),
            badge.bottomAnchor.constraint(equalTo: bottomAnchor),
            hint.centerXAnchor.constraint(equalTo: centerXAnchor),
            hint.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -40),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - 6. Progress loader

private final class LoaderDemoScene: UIView, ParticleDemoScene {
    private let loader = MorphingProgressLoaderView()
    private let startButton = makeButton("Load", symbol: "arrow.down.circle.fill")
    private var loading: Task<Void, Never>?

    var activeEngine: ParticleMorphEngine? { loader.engine }

    override init(frame: CGRect) {
        super.init(frame: frame)
        loader.translatesAutoresizingMaskIntoConstraints = false
        addSubview(loader)
        buildContent()
        startButton.addTarget(self, action: #selector(start), for: .touchUpInside)
        addSubview(startButton)
        NSLayoutConstraint.activate([
            loader.topAnchor.constraint(equalTo: topAnchor),
            loader.leadingAnchor.constraint(equalTo: leadingAnchor),
            loader.trailingAnchor.constraint(equalTo: trailingAnchor),
            loader.bottomAnchor.constraint(equalTo: bottomAnchor),
            startButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            startButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -32),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil { loading?.cancel() }
    }

    private func buildContent() {
        let content = loader.contentView
        content.backgroundColor = loader.cardColor
        content.layer.cornerRadius = 24
        content.layer.cornerCurve = .continuous
        let icon = UIImageView(image: UIImage(systemName: "doc.richtext.fill",
                                              withConfiguration: UIImage.SymbolConfiguration(pointSize: 34, weight: .semibold)))
        icon.tintColor = .white
        let title = UILabel()
        title.text = "Annual Report.pdf"
        title.font = .systemFont(ofSize: 21, weight: .bold)
        title.textColor = .white
        let subtitle = UILabel()
        subtitle.text = "24.6 MB · downloaded just now"
        subtitle.font = .systemFont(ofSize: 14)
        subtitle.textColor = UIColor(white: 1, alpha: 0.75)
        let stack = UIStackView(arrangedSubviews: [icon, title, subtitle])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(18, after: icon)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 22),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
    }

    @objc private func start() {
        loading?.cancel()
        loader.reset()
        startButton.isEnabled = false
        // Fake download with uneven chunks, like a real network.
        loading = Task { [weak self] in
            var progress: Float = 0
            try? await Task.sleep(for: .milliseconds(500))
            while progress < 1 {
                try? await Task.sleep(for: .milliseconds(Int.random(in: 180...420)))
                guard let self, !Task.isCancelled else { return }
                progress = min(progress + Float.random(in: 0.04...0.13), 1)
                self.loader.setProgress(progress)
            }
            try? await Task.sleep(for: .milliseconds(700))
            guard let self, !Task.isCancelled else { return }
            self.loader.finish { [weak self] in
                self?.startButton.isEnabled = true
            }
        }
    }
}
