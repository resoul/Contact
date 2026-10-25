//
//  SocialRoomDemos.swift
//  controller
//
//  The "Social · Live" section of the VFX menu (MetalVFXEngine/SocialRoom):
//  - Voice Room: tiles whose liquid rims breathe with each speaker's voice (simulated; the mic button
//    uses your real microphone), a raised hand oozing out of your tile until the host brings you on
//    stage, rolling counters with reactions floating up.
//  - Chat: messages sent as a drop that spreads into the bubble, a voice message with a liquid
//    playhead, recording into a blob you can tear off into the bin, typing dots, a fanned photo stack.
//  - Bubble Cluster: people as linked drops with physics, orbits mode, hopping "talk" bubbles, a drop
//    that opens into a profile card, a jelly call tile.
//  - Ambient Feed: the background takes on the colours of the photo in focus, the action column is
//    glass over the photo, liquid tabs and segments.
//

import UIKit

private let demoPeople = [
    ChannelPerson(name: "Колин Грэй", hue: 0.07), ChannelPerson(name: "Глэдис Мун", hue: 0.9),
    ChannelPerson(name: "Мэдисон Ли", hue: 0.55), ChannelPerson(name: "Мэделин Роуз", hue: 0.75),
    ChannelPerson(name: "Харли Квин", hue: 0.0), ChannelPerson(name: "Рональд Бейкер", hue: 0.35),
    ChannelPerson(name: "Виктория Стоун", hue: 0.62), ChannelPerson(name: "Шон Митчелл", hue: 0.15),
]
private let me = ChannelPerson(name: "Вы", hue: 0.48)

// MARK: - Voice Room

final class VoiceRoomDemoViewController: UIViewController {
    private let scroll = UIScrollView()
    private let stage = UIView()
    private let rims = VoiceRimsView()
    private let handLiquid = LiquidCanvasView()
    private var speakers: [RoomTile] = []
    private var listeners: [RoomTile] = []
    private var meTile: RoomTile!
    private var simulators: [ObjectIdentifier: SpeechSimulator] = [:]
    private var hands: [RaisedHand] = []
    private var myHand: RaisedHand?
    private let meter = VoiceLevelMeter()
    private var micOn = false
    private let micButton = UIButton(type: .system)
    private var chips: [RoomCounterChip] = []
    private let toast = UILabel()
    private var reactionTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Дизайн и движение"
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = RoomPalette.background
        scroll.frame = view.bounds
        scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.alwaysBounceVertical = true
        view.addSubview(scroll)
        scroll.addSubview(stage)
        stage.addSubview(rims)

        for (index, person) in demoPeople.enumerated() {
            let tile = RoomTile(person: person, speaker: index < 2)
            stage.addSubview(tile)
            if index < 2 {
                speakers.append(tile)
                simulators[ObjectIdentifier(tile)] = SpeechSimulator(energy: index == 0 ? 1 : 0.8, startsTalking: index == 0)
            } else {
                listeners.append(tile)
            }
        }
        meTile = RoomTile(person: me, speaker: false)
        stage.addSubview(meTile)
        listeners.append(meTile)

        handLiquid.liquidColor = RoomPalette.orange
        handLiquid.gloss = 0.6
        handLiquid.rimWidth = 6
        stage.addSubview(handLiquid)
        // Victoria already has her hand up.
        if let victoria = listeners.first(where: { $0.person.name.hasPrefix("Виктория") }) {
            hands.append(RaisedHand(on: victoria, in: stage))
        }

        rims.rims = { [weak self] in self?.currentRims() ?? [] }
        rims.onFrame = { [weak self] dt in self?.step(dt) }
        buildBottom()
        toast.font = .systemFont(ofSize: 14, weight: .semibold)
        toast.textColor = .white
        toast.backgroundColor = RoomPalette.orange
        toast.textAlignment = .center
        toast.layer.cornerRadius = 18
        toast.clipsToBounds = true
        toast.alpha = 0
        view.addSubview(toast)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.overrideUserInterfaceStyle = .dark
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        reactionTimer = Timer.scheduledTimer(withTimeInterval: 2.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.someoneReacts() }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.navigationBar.overrideUserInterfaceStyle = .unspecified
        reactionTimer?.invalidate()
        meter.stop()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutTiles()
        let safe = view.safeAreaInsets
        let bottomBar = view.viewWithTag(500)
        bottomBar?.frame = CGRect(x: 0, y: view.bounds.height - safe.bottom - 132, width: view.bounds.width, height: 132)
        scroll.contentInset.bottom = 140
    }

    // MARK: Layout

    private func layoutTiles() {
        let width = view.bounds.width
        let margin: CGFloat = 16, gap: CGFloat = 12
        let big = (width - margin * 2 - gap) / 2
        var y: CGFloat = 12
        for (index, tile) in speakers.enumerated() {
            let column = index % 2
            if index > 0, column == 0 { y += big * 1.22 + gap }
            tile.frame = CGRect(x: margin + CGFloat(column) * (big + gap), y: y, width: big, height: big * 1.22)
        }
        y += big * 1.22 + 26
        let small: CGFloat = 92
        let spacing = (width - margin * 2 - small * 3) / 2
        for (index, tile) in listeners.enumerated() {
            let column = index % 3, row = index / 3
            tile.frame = CGRect(x: margin + CGFloat(column) * (small + spacing), y: y + CGFloat(row) * (small + 44),
                                width: small, height: small + 26)
        }
        let rows = (listeners.count + 2) / 3
        let height = y + CGFloat(rows) * (small + 44) + 20
        stage.frame = CGRect(x: 0, y: 0, width: width, height: height)
        rims.frame = stage.bounds.insetBy(dx: 0, dy: -40)   // room for the glow above the first row
        handLiquid.frame = stage.bounds
        scroll.contentSize = CGSize(width: width, height: height)
    }

    private func buildBottom() {
        let bar = UIView()
        bar.tag = 500
        view.addSubview(bar)
        let controls = UIStackView()
        controls.distribution = .equalSpacing
        controls.translatesAutoresizingMaskIntoConstraints = false
        let actions: [(String, () -> Void)] = [
            ("hand.raised", { [weak self] in self?.raiseHand() }),
            ("video", {}),
            ("mic.slash", { [weak self] in self?.toggleMic() }),
            ("person.badge.plus", {}),
            ("rectangle.portrait.and.arrow.right", { [weak self] in self?.navigationController?.popViewController(animated: true) }),
        ]
        for (index, (symbol, action)) in actions.enumerated() {
            let button = index == 2 ? micButton : UIButton(type: .system)
            button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 21)), for: .normal)
            button.tintColor = .white
            button.addAction(UIAction { _ in action() }, for: .touchUpInside)
            button.widthAnchor.constraint(equalToConstant: 48).isActive = true
            controls.addArrangedSubview(button)
        }
        chips = [RoomCounterChip(avatar: demoPeople[0], count: 83, highlighted: true),
                 RoomCounterChip(symbol: "bubble.left.and.text.bubble.right", count: 83),
                 RoomCounterChip(symbol: "hand.raised", count: 2),
                 RoomCounterChip(symbol: "hand.thumbsup", count: 13)]
        chips[3].addAction(UIAction { [weak self] _ in
            guard let self else { return }
            chips[3].setCount(chips[3].count + 1)
            chips[3].float("👍", in: view)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }, for: .touchUpInside)
        let chipRow = UIStackView(arrangedSubviews: chips)
        chipRow.spacing = 10
        chipRow.distribution = .fillEqually
        chipRow.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(controls)
        bar.addSubview(chipRow)
        NSLayoutConstraint.activate([
            controls.topAnchor.constraint(equalTo: bar.topAnchor),
            controls.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 26),
            controls.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -26),
            controls.heightAnchor.constraint(equalToConstant: 48),
            chipRow.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 18),
            chipRow.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 16),
            chipRow.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -16),
            chipRow.heightAnchor.constraint(equalToConstant: 56),
        ])
        bar.backgroundColor = RoomPalette.background.withAlphaComponent(0.92)
    }

    // MARK: Voices

    private func myLevel(_ dt: Double) -> CGFloat {
        if micOn { return meter.level }
        guard meTile.isSpeaker else { return 0 }
        var sim = simulators[ObjectIdentifier(meTile)] ?? SpeechSimulator(energy: 0.9)
        sim.step(dt)
        simulators[ObjectIdentifier(meTile)] = sim
        return sim.level
    }

    private func step(_ dt: CFTimeInterval) {
        for tile in speakers where tile !== meTile {
            guard var sim = simulators[ObjectIdentifier(tile)] else { continue }
            sim.step(dt)
            simulators[ObjectIdentifier(tile)] = sim
            tile.level = tile.isMuted ? 0 : sim.level
        }
        meTile.level = myLevel(dt)
        var shapes: [IslandFluidShape] = []
        var spikes: [IslandFluidSpike] = []
        for hand in hands {
            let liquid = hand.step(dt, in: stage)
            shapes += liquid.shapes
            spikes += liquid.spikes
        }
        hands.removeAll { $0.isDone }
        handLiquid.shapes = shapes
        handLiquid.spikes = spikes
        handLiquid.isPaused = hands.isEmpty
        if hands.isEmpty {
            handLiquid.shapes = []
            handLiquid.renderFrame()
        }
    }

    private func currentRims() -> [(rect: CGRect, radius: CGFloat, level: CGFloat)] {
        var list = speakers.map { ($0.convert($0.tileRect, to: rims), $0.cornerRadius, $0.level) }
        if micOn, !meTile.isSpeaker {
            list.append((meTile.convert(meTile.tileRect, to: rims), meTile.cornerRadius, meTile.level))
        }
        return list
    }

    // MARK: Actions

    private func toggleMic() {
        if micOn {
            micOn = false
            meter.stop()
            updateMicButton()
            return
        }
        meter.start { [weak self] granted in
            guard let self else { return }
            micOn = granted
            updateMicButton()
            if !granted {
                showToast("Нет доступа к микрофону — голос имитируется")
            }
        }
    }

    private func updateMicButton() {
        micButton.setImage(UIImage(systemName: micOn ? "mic.fill" : "mic.slash",
                                   withConfiguration: UIImage.SymbolConfiguration(pointSize: 21)), for: .normal)
        micButton.tintColor = micOn ? RoomPalette.orange : .white
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func raiseHand() {
        guard myHand == nil, !meTile.isSpeaker else { return }
        let hand = RaisedHand(on: meTile, in: stage)
        hands.append(hand)
        myHand = hand
        chips[2].setCount(chips[2].count + 1)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        // The host notices and invites you up.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in self?.bringOnStage() }
    }

    private func bringOnStage() {
        showToast("Ведущий пригласил вас на сцену")
        myHand?.lower()
        chips[2].setCount(chips[2].count - 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            listeners.removeAll { $0 === self.meTile }
            speakers.append(meTile)
            meTile.becomeSpeaker()
            stage.bringSubviewToFront(meTile)
            stage.bringSubviewToFront(handLiquid)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            UIView.animate(withDuration: 0.7, delay: 0, usingSpringWithDamping: 0.72, initialSpringVelocity: 0.3) {
                self.layoutTiles()
                self.meTile.layoutIfNeeded()
            }
        }
    }

    private func someoneReacts() {
        guard Bool.random() else { return }
        chips[3].setCount(chips[3].count + 1)
        chips[3].float(["👍", "🔥", "❤️", "👏"].randomElement()!, in: view)
        if Bool.random() {
            chips[0].setCount(chips[0].count + Int.random(in: -1...2))
        }
    }

    private func showToast(_ text: String) {
        toast.text = text
        let size = toast.sizeThatFits(CGSize(width: view.bounds.width - 40, height: 40))
        toast.bounds = CGRect(x: 0, y: 0, width: size.width + 32, height: 36)
        toast.center = CGPoint(x: view.bounds.midX, y: view.safeAreaInsets.top + 30)
        toast.transform = CGAffineTransform(translationX: 0, y: -20).scaledBy(x: 0.8, y: 0.8)
        UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.4) {
            self.toast.alpha = 1
            self.toast.transform = .identity
        }
        UIView.animate(withDuration: 0.3, delay: 2.2) { self.toast.alpha = 0 }
    }
}

// MARK: - Bubble Cluster

final class BubbleClusterDemoViewController: UIViewController {
    private var cluster: BubbleClusterView!
    private let modes = LiquidSelector(titles: ["Кластер", "Орбиты"], style: .segments, liquid: RoomPalette.cyan.withAlphaComponent(0.9),
                                       selectedTint: RoomPalette.background)
    private let call = CallTile(person: demoPeople[4])
    private let camera = UIButton(type: .custom)

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = RoomPalette.background
        let title = UILabel()
        let text = NSMutableAttributedString(string: "Social", attributes: [
            .font: UIFont(name: "SnellRoundhand-Black", size: 36) ?? .systemFont(ofSize: 30, weight: .heavy), .foregroundColor: UIColor.white])
        text.append(NSAttributedString(string: " Feed", attributes: [.font: UIFont.systemFont(ofSize: 30, weight: .medium),
                                                                      .foregroundColor: UIColor.white]))
        title.attributedText = text
        navigationItem.titleView = title
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "magnifyingglass"), style: .plain, target: nil, action: nil),
            UIBarButtonItem(image: UIImage(systemName: "plus"), style: .plain, target: nil, action: nil),
        ]

        let members: [BubbleClusterView.Member] = [
            .init(person: demoPeople[0], radius: 46, home: CGPoint(x: 10, y: -110), tag: "Content Creator"),
            .init(person: demoPeople[1], radius: 50, home: CGPoint(x: -95, y: -20), tag: nil),
            .init(person: demoPeople[2], radius: 38, home: CGPoint(x: 115, y: -70), tag: "Influencer"),
            .init(person: demoPeople[3], radius: 48, home: CGPoint(x: 45, y: 25), tag: nil),
            .init(person: demoPeople[5], radius: 38, home: CGPoint(x: -60, y: 100), tag: "Social Activist"),
            .init(person: demoPeople[6], radius: 36, home: CGPoint(x: 115, y: 95), tag: nil),
            .init(person: demoPeople[7], radius: 28, home: CGPoint(x: -140, y: 80), tag: "APD"),
        ]
        cluster = BubbleClusterView(members: members)
        cluster.onOpen = { [weak self] index, _ in self?.openProfile(index) }
        view.addSubview(cluster)
        modes.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            cluster.setOrbits(modes.selectedIndex == 1)
        }, for: .valueChanged)
        view.addSubview(modes)

        let row = UIView()
        row.tag = 300
        let avatar = RingAvatar(person: demoPeople[3], online: true)
        avatar.frame = CGRect(x: 16, y: 0, width: 64, height: 64)
        row.addSubview(avatar)
        let name = UILabel()
        name.text = "Мэделин Роуз  ✓"
        name.font = .systemFont(ofSize: 19, weight: .semibold)
        name.textColor = .white
        name.frame = CGRect(x: 92, y: 10, width: 220, height: 24)
        row.addSubview(name)
        let status = UILabel()
        status.text = "Просто хочу быть счастливой"
        status.font = .systemFont(ofSize: 14)
        status.textColor = RoomPalette.secondary
        status.frame = CGRect(x: 92, y: 36, width: 220, height: 20)
        row.addSubview(status)
        view.addSubview(row)

        camera.backgroundColor = RoomPalette.orange
        camera.setImage(UIImage(systemName: "camera", withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)),
                        for: .normal)
        camera.tintColor = .white
        camera.layer.cornerRadius = 36
        camera.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            camera.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
            UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.4, initialSpringVelocity: 0.6) {
                self.camera.transform = .identity
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }, for: .touchUpInside)
        view.addSubview(camera)
        view.addSubview(call)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.overrideUserInterfaceStyle = .dark
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.navigationBar.overrideUserInterfaceStyle = .unspecified
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let safe = view.safeAreaInsets
        let width = view.bounds.width
        modes.frame = CGRect(x: (width - 230) / 2, y: safe.top + 8, width: 230, height: 40)
        cluster.frame = CGRect(x: 0, y: modes.frame.maxY + 6, width: width, height: 400)
        view.viewWithTag(300)?.frame = CGRect(x: 0, y: cluster.frame.maxY + 6, width: width, height: 70)
        camera.frame = CGRect(x: width - 92, y: view.bounds.height - safe.bottom - 92, width: 72, height: 72)
        call.margins = UIEdgeInsets(top: cluster.frame.maxY + 84, left: 16, bottom: safe.bottom + 16, right: 16)
        if call.center == CGPoint(x: 58, y: 75) {
            call.place(at: CGPoint(x: 16 + 58, y: view.bounds.height - safe.bottom - 16 - 75))
        }
    }

    private func openProfile(_ index: Int) {
        let person = cluster.person(at: index)
        let host = navigationController?.view ?? view!
        let card = UIView()
        let avatar = RingAvatar(person: person, online: true)
        let name = UILabel()
        name.text = person.name + "  ✓"
        name.font = .systemFont(ofSize: 24, weight: .bold)
        name.textColor = .white
        let status = UILabel()
        status.text = "В сети · 2 км от вас"
        status.font = .systemFont(ofSize: 15)
        status.textColor = RoomPalette.secondary
        let chips = UIStackView(arrangedSubviews: [ProfileChip(symbol: "music.note", title: "Музыка"),
                                                   ProfileChip(symbol: "film", title: "Кино"),
                                                   ProfileChip(symbol: "figure.run", title: "Спорт")])
        chips.spacing = 8
        var message = UIButton.Configuration.filled()
        message.title = "Написать"
        message.cornerStyle = .capsule
        message.baseBackgroundColor = RoomPalette.orange
        var callConfig = UIButton.Configuration.gray()
        callConfig.title = "Позвонить"
        callConfig.cornerStyle = .capsule
        let buttons = UIStackView(arrangedSubviews: [UIButton(configuration: message), UIButton(configuration: callConfig)])
        buttons.spacing = 12
        buttons.distribution = .fillEqually
        let column = UIStackView(arrangedSubviews: [avatar, name, status, chips, buttons])
        column.axis = .vertical
        column.alignment = .center
        column.spacing = 14
        column.setCustomSpacing(26, after: chips)
        column.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(column)
        NSLayoutConstraint.activate([
            avatar.widthAnchor.constraint(equalToConstant: 120),
            avatar.heightAnchor.constraint(equalToConstant: 120),
            column.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            column.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            buttons.widthAnchor.constraint(equalToConstant: 300),
            buttons.heightAnchor.constraint(equalToConstant: 48),
        ])
        let target = CGRect(x: 16, y: host.safeAreaInsets.top + 80, width: host.bounds.width - 32, height: 470)
        _ = LiquidMorphPanel(in: host, from: { [weak self, weak host] in
            guard let self, let host else { return .zero }
            return cluster.convert(cluster.frameOfBubble(index), to: host).insetBy(dx: -9, dy: -9)
        }, sourceCorner: 60, to: target, color: UIColor(red: 0.07, green: 0.2, blue: 0.23, alpha: 1), content: card)
    }
}

