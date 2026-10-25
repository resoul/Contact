//
//  MTChatViewController.swift
//  controller
//
//  A Mini-Telegram chat: floating date pills (sticky section headers that fade when scrolling
//  stops), the pinned-messages bar that walks through the pins, the input bar whose button morphs
//  mic ↔ camera ↔ send, voice recording on a liquid blob with slide-up-to-lock and slide-left-to-
//  cancel, and the attach sheet.
//
//  Messages: sent text flies from the field into its bubble and the tail flows on to it; the other
//  side's "typing" bubble swells into their answer; double tap or the long-press menu adds a
//  reaction that flows around the bubbles and drains into a chip; swipe left to reply, edit your own, select several and
//  delete them as dust; a scroll-down button counts what arrived below; and an "unread" band
//  marks where you stopped reading.
//

import UIKit

final class MTChatViewController: UIViewController {
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
            self.wallpaper.setNight(self.traitCollection.userInterfaceStyle == .dark, animated: true)
    }

    private let storageOrigin = UUID()
    private let storageSession: MTAccountSession?
    private var applyingStoredChange = false
    private var loadingOlder = false
    private var hasOlderHistory = true
    private var chat: MTChat
    private weak var home: MTHomeViewController?
    private var sections: [(title: String, messages: [MTMessage])]

    private let wallpaper = ChannelWallpaperView()
    private let table = UITableView(frame: .zero, style: .plain)
    private let replySwipeEffect = MTReplySwipeEffect()
    private let channelEffectsHost = UIView()
    private let channelReactionLiquid = FeedLiquidLayer(color: ChannelPalette.accent, gloss: 0.5)
    private let channelVacuum = SandVacuumAnimator()
    private var channelPicker: ReactionPickerOverlay?
    private var channelForward: ForwardDropOverlay?
    private var channelComments: CommentsSheetOverlay?
    private var channelPostHeights: [Int: (width: CGFloat, height: CGFloat)] = [:]
    private let nextChannelIndicator = MTNextChannelIndicator()
    private let channelAccount: Int
    private var channelTransitioning = false
    private var channelTransitionOverlay: UIView?
    private var channelAvatarFlyer: UIView?
    private var channelHintShown = false
    private let reactionFluid = MTReactionFluidView()
    private let fluidTouchObserver = TouchObserverGestureRecognizer()
    private var lastFluidTouch: (point: CGPoint, time: CFTimeInterval)?
    private var backgroundObserver: NSObjectProtocol?
    private struct ReactionKey: Hashable {
        let messageID: Int
        let emoji: String
    }
    /// Tokens follow message identity across cell reuse and rapid add/remove/add gestures.
    private var pendingReactions: [ReactionKey: UUID] = [:]
    private var reactionFlyers: [ReactionKey: UIView] = [:]
    private var reactionSparks: [ReactionKey: [UIView]] = [:]
    private let header = UIView()
    private let headerBackground = MTViews.barBackground()
    private let backButton = UIButton(type: .system)
    private let nameLabel = MTViews.label(size: 16, weight: .semibold)
    private let statusLabel = MTViews.label(size: 13, color: MTPalette.secondary)
    private let statusDots = MTTypingDots()
    private let avatar = MTAvatarView()
    private let callButton = MTViews.iconButton("phone", size: 18)
    private let pinned = MTPinnedBar(count: MTData.pinnedMessages.count)
    private let input = MTInputBar()
    private let scrollDown = MTScrollDownButton()
    private let selectionHeader = UIView()
    private let selectionTitle = MTViews.label(size: 17, weight: .semibold)
    private let selectionBar = UIView()
    private var recorder: MTVoiceRecorder?
    private var typingFooter: MTTypingFooter?
    private var didScrollToBottom = false
    private var fadeWork: DispatchWorkItem?
    private var jumpingToPin = false

    /// 0 = the usual bar, 1 = pulled down into a mini profile.
    private var headerExpansion: CGFloat = 0
    private var expansionStart: CGFloat = 0
    private let miniButtons = UIStackView()
    private var expiring: [Int: Date] = [:]
    private static let vanishAfter: TimeInterval = 5
    private let searchBar = UIView()
    private let searchField = UITextField()
    private let resultsBar = UIView()
    private let resultsCounter = RollingCounterLabel()
    private var searchQuery: String?
    private var matches: [Int] = []
    private var currentMatch = 0
    private static var hintShown = false

    private var selecting = false
    private var selectedIDs: Set<Int> = []
    private var replyTo: MTMessage?
    private var editingID: Int?

    init(chat: MTChat, home: MTHomeViewController) {
        self.chat = chat
        self.home = home
        storageSession = home.storageSession
        channelAccount = home.currentAccount
        sections = home.storageSession?.sections(for: chat.id) ?? [("Today", [])]
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
        let session = storageSession, token = storageOrigin
        Task { @MainActor in session?.stopObserving(token: token) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = MTPalette.wallpaper
        let theme = MTChatTheme.all[MTChatTheme.current]
        wallpaper.patternAlpha = 0.1
        wallpaper.setTheme(day: theme.day, night: theme.night, animated: false)
        view.addSubview(wallpaper)
        // Day ⇄ night by any means (the app's theme switch too): the wallpaper goes through dusk.


        table.accessibilityIdentifier = "contact.messages"
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.alwaysBounceVertical = true
        table.contentInsetAdjustmentBehavior = .never
        table.keyboardDismissMode = .interactive
        table.sectionHeaderTopPadding = 0
        table.register(MTMessageCell.self, forCellReuseIdentifier: "message")
        table.register(MTChannelPostCell.self, forCellReuseIdentifier: "channelPost")
        table.estimatedRowHeight = 0
        table.register(MTDateHeader.self, forHeaderFooterViewReuseIdentifier: "date")
        table.dataSource = self
        table.delegate = self
        view.addSubview(table)
        view.addSubview(nextChannelIndicator)
        view.addSubview(replySwipeEffect)
        view.addSubview(channelEffectsHost)
        channelEffectsHost.isUserInteractionEnabled = false
        channelEffectsHost.addSubview(channelReactionLiquid)
        view.addSubview(reactionFluid)
        reactionFluid.clipsToBounds = true
        reactionFluid.geometryProvider = { [weak self] in self?.fluidObstacles() ?? [] }
        fluidTouchObserver.onTouch = { [weak self] point, phase in self?.stirReactionFluid(at: point, phase: phase) }
        table.addGestureRecognizer(fluidTouchObserver)
        backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification,
                                                                    object: nil, queue: .main) { [weak self] _ in
            self?.saveChannelReadingPosition()
            self?.stopChannelTransition()
            self?.stopChannelPostEffects()
            self?.replySwipeEffect.stop()
            self?.stopReactionAnimations()
        }

        pinned.addTarget(self, action: #selector(pinnedTapped), for: .touchUpInside)
        view.addSubview(pinned)
        buildHeader()

        input.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(input)
        NSLayoutConstraint.activate([
            input.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            input.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            input.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
        ])
        if #available(iOS 17.0, *) { view.keyboardLayoutGuide.usesBottomSafeArea = false }
        else { input.includesBottomSafeArea = false }
        input.onSend = { [weak self] text in self?.sendText(text) }
        input.onAttach = { [weak self] in self?.openAttach() }
        input.onModeToggle = { [weak self] video in
            guard let self else { return }
            MTViews.toast(video ? "Hold to record a video message" : "Hold to record a voice message", symbol: video ? "video.fill" : "mic.fill",
                          in: self.view, top: self.pinned.frame.maxY + 8)
        }
        input.onHold = { [weak self] gesture in self?.recordGesture(gesture) }
        input.onPanelClose = { [weak self] in self?.clearComposerMode() }
        input.onSticker = { [weak self] sticker, cell in self?.sendSticker(sticker, from: cell) }

        scrollDown.addAction(UIAction { [weak self] _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            self?.scrollToBottom(animated: true)
        }, for: .touchUpInside)
        view.addSubview(scrollDown)
        buildSelectionBars()
        buildSearch()
        configureChannelChrome()
        observeStoredHistory()
    }

    private func committed(_ action: () -> Void) {
        applyingStoredChange = true
        action()
        applyingStoredChange = false
    }

    private func observeStoredHistory() {
        storageSession?.stopObserving(token: storageOrigin)
        storageSession?.observeHistory(chatID: chat.id, token: storageOrigin) { [weak self] origin in
            guard let self, origin != self.storageOrigin, !self.channelTransitioning else { return }
            self.reloadStoredHistory()
        }
    }

    private func reloadStoredHistory() {
        guard let storageSession else { return }
        let offset = table.contentOffset
        let bottom = distanceFromBottom < 80
        sections = storageSession.sections(for: chat.id)
        channelPostHeights.removeAll()
        table.reloadData()
        table.layoutIfNeeded()
        if bottom { scrollToBottom(animated: false) }
        else { table.contentOffset = offset }
    }

    private var nightSet = false

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        // The style is known only now; the dusk animation is for changes after this.
        guard !nightSet else { return }
        nightSet = true
        wallpaper.setNight(traitCollection.userInterfaceStyle == .dark, animated: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if chat.kind == .channel {
            if !channelHintShown {
                channelHintShown = true
                MTViews.toast("Scroll to the end and pull up", symbol: "arrow.up.circle", in: view,
                              top: pinned.frame.maxY + 8)
            }
            return
        }
        guard !Self.hintShown else { return }
        Self.hintShown = true
        MTViews.toast("Double-tap for ❤️ · hold for reactions", symbol: "heart.fill", in: view, top: pinned.frame.maxY + 8)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveChannelReadingPosition()
        stopChannelTransition()
        stopChannelPostEffects()
        replySwipeEffect.stop()
        stopReactionAnimations()
    }

    private func buildHeader() {
        view.addSubview(header)
        header.addSubview(headerBackground)
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "chevron.backward", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold))
        configuration.title = "Chats"
        configuration.imagePadding = 4
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
        backButton.configuration = configuration
        backButton.tintColor = MTPalette.accent
        backButton.addAction(UIAction { [weak self] _ in self?.home?.root?.pop() }, for: .touchUpInside)
        backButton.accessibilityIdentifier = "contact.back"
        header.addSubview(backButton)
        nameLabel.text = chat.person.name
        nameLabel.textAlignment = .center
        header.addSubview(nameLabel)
        statusLabel.textAlignment = .center
        header.addSubview(statusLabel)
        statusDots.alpha = 0
        header.addSubview(statusDots)
        setStatus(typing: false)
        avatar.set(chat.person, size: 38)
        avatar.online = chat.online
        avatar.isUserInteractionEnabled = true
        avatar.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openProfile)))
        header.addSubview(avatar)
        let titleTap = UIView()
        titleTap.tag = 77
        titleTap.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openProfile)))
        titleTap.isAccessibilityElement = true
        titleTap.accessibilityLabel = "Profile"
        titleTap.accessibilityIdentifier = "contact.profile"
        titleTap.accessibilityTraits = .button
        header.addSubview(titleTap)
        callButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.home?.call(self.chat.person)
        }, for: .touchUpInside)
        callButton.accessibilityLabel = "Call"
        callButton.accessibilityIdentifier = "contact.call"
        header.addSubview(callButton)

        miniButtons.axis = .horizontal
        miniButtons.distribution = .fillEqually
        miniButtons.spacing = 8
        miniButtons.alpha = 0
        let actions: [(String, String, () -> Void)] = [
            ("phone.fill", "Call", { [weak self] in
                guard let self else { return }
                self.home?.call(self.chat.person)
            }),
            ("magnifyingglass", "Search", { [weak self] in self?.startSearch() }),
            ("paintpalette.fill", "Theme", { [weak self] in self?.openThemes() }),
            ("person.crop.circle", "Profile", { [weak self] in self?.openProfile() }),
        ]
        for (symbol, title, handler) in actions {
            var configuration = UIButton.Configuration.filled()
            configuration.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold))
            configuration.title = title
            configuration.imagePlacement = .top
            configuration.imagePadding = 4
            configuration.baseBackgroundColor = MTPalette.fill
            configuration.baseForegroundColor = MTPalette.accent
            configuration.cornerStyle = .large
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var attributes = attributes
                attributes.font = .systemFont(ofSize: 11, weight: .medium)
                return attributes
            }
            let button = UIButton(configuration: configuration)
            button.addAction(UIAction { [weak self] _ in
                handler()
                self?.setHeaderExpansion(0, animated: true)
            }, for: .touchUpInside)
            miniButtons.addArrangedSubview(button)
        }
        header.addSubview(miniButtons)
        if chat.kind != .channel {
            header.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(headerPanned(_:))))
        }
    }

    // MARK: Header → mini profile

    private func lerp(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
               width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
    }

    /// Lays the header out between the bar (0) and the mini profile (1): the avatar slides to the
    /// middle and grows, the name follows under it, the buttons rise into place.
    private func layoutHeader() {
        let width = view.bounds.width, top = view.safeAreaInsets.top
        let e = headerExpansion
        header.frame = CGRect(x: 0, y: 0, width: width, height: headerHeight + 196 * min(e, 1.1))
        headerBackground.frame = header.bounds
        backButton.frame = CGRect(x: 0, y: top, width: 92, height: 52)
        callButton.frame = CGRect(x: width - 92, y: top + 4, width: 40, height: 44)
        callButton.alpha = max(0, 1 - e * 2)
        avatar.frame = lerp(CGRect(x: width - 50, y: top + 7, width: 38, height: 38),
                            CGRect(x: width / 2 - 44, y: top + 6, width: 88, height: 88), e)
        let scale = 1 + 0.3 * min(e, 1)
        nameLabel.transform = .identity
        nameLabel.frame = lerp(CGRect(x: 96, y: top + 8, width: width - 192, height: 20),
                               CGRect(x: 40, y: top + 104, width: width - 80, height: 20), e)
        nameLabel.transform = CGAffineTransform(scaleX: scale, y: scale)
        statusLabel.frame = lerp(CGRect(x: 96, y: top + 28, width: width - 192, height: 16),
                                 CGRect(x: 40, y: top + 130, width: width - 80, height: 16), e)
        let typingWidth = statusLabel.intrinsicContentSize.width
        statusDots.frame = CGRect(x: width / 2 + typingWidth / 2 + 2, y: statusLabel.frame.minY + 3, width: 24, height: 10)
        header.viewWithTag(77)?.frame = nameLabel.frame.union(statusLabel.frame)
        miniButtons.frame = CGRect(x: 16, y: top + 160 + (1 - min(e, 1)) * 24, width: width - 32, height: 56)
        miniButtons.alpha = islandSmoothstep(0.55, 1, e)
        pinned.frame = CGRect(x: 0, y: header.frame.maxY, width: width, height: chat.kind == .channel ? 0 : 46)
    }

    private func setHeaderExpansion(_ value: CGFloat, animated: Bool) {
        headerExpansion = value
        guard animated else {
            layoutHeader()
            return
        }
        UIImpactFeedbackGenerator(style: value > 0 ? .medium : .light).impactOccurred()
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.78, initialSpringVelocity: 0) {
            self.layoutHeader()
        }
    }

    @objc private func headerPanned(_ gesture: UIPanGestureRecognizer) {
        let dy = gesture.translation(in: view).y
        switch gesture.state {
        case .began:
            expansionStart = headerExpansion
        case .changed:
            var value = expansionStart + dy / 196
            if value > 1 { value = 1 + (value - 1) * 0.25 }
            headerExpansion = max(0, value)
            layoutHeader()
        case .ended, .cancelled:
            let velocity = gesture.velocity(in: view).y
            let open = velocity > 500 || (headerExpansion > 0.45 && velocity > -300)
            setHeaderExpansion(open ? 1 : 0, animated: true)
        default:
            break
        }
    }

    /// The selection mode's own bars: "Отмена · Выбрано: N" on top, delete / forward at the bottom.
    private func buildSelectionBars() {
        selectionHeader.addSubview(MTViews.barBackground())
        let cancel = UIButton(type: .system)
        cancel.setTitle("Cancel", for: .normal)
        cancel.titleLabel?.font = .systemFont(ofSize: 17)
        cancel.tintColor = MTPalette.accent
        cancel.tag = 1
        cancel.addAction(UIAction { [weak self] _ in self?.setSelecting(false) }, for: .touchUpInside)
        selectionHeader.addSubview(cancel)
        selectionTitle.textAlignment = .center
        selectionHeader.addSubview(selectionTitle)
        selectionHeader.alpha = 0
        view.addSubview(selectionHeader)

        selectionBar.addSubview(MTViews.barBackground())
        let delete = MTViews.iconButton("trash", size: 21, tint: MTPalette.red)
        delete.tag = 1
        delete.addAction(UIAction { [weak self] _ in
            guard let self, !self.selectedIDs.isEmpty else { return }
            let ids = self.selectedIDs
            self.setSelecting(false)
            self.delete(ids)
        }, for: .touchUpInside)
        selectionBar.addSubview(delete)
        let forward = MTViews.iconButton("arrowshape.turn.up.right", size: 21)
        forward.tag = 2
        forward.addAction(UIAction { [weak self] _ in
            guard let self, !self.selectedIDs.isEmpty else { return }
            let count = self.selectedIDs.count
            self.setSelecting(false)
            MTViews.toast("Forwarded to Saved Messages: \(count)", symbol: "arrowshape.turn.up.right.fill", in: self.view,
                          top: self.pinned.frame.maxY + 8)
        }, for: .touchUpInside)
        selectionBar.addSubview(forward)
        selectionBar.transform = CGAffineTransform(translationX: 0, y: 120)
        view.addSubview(selectionBar)
    }

    private var messageAreaBottom: CGFloat {
        chat.kind == .channel ? view.bounds.height - view.safeAreaInsets.bottom : input.frame.minY
    }

    private var headerHeight: CGFloat { view.safeAreaInsets.top + 52 }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = view.bounds.width
        wallpaper.frame = view.bounds
        replySwipeEffect.frame = view.bounds
        channelEffectsHost.frame = view.bounds
        channelReactionLiquid.frame = channelEffectsHost.bounds
        let top = view.safeAreaInsets.top
        layoutHeader()

        selectionHeader.frame = CGRect(x: 0, y: 0, width: width, height: headerHeight)
        searchBar.frame = selectionHeader.frame
        searchBar.subviews.first?.frame = searchBar.bounds
        searchField.frame = CGRect(x: 12, y: top + 8, width: width - 104, height: 36)
        searchBar.viewWithTag(1)?.frame = CGRect(x: width - 88, y: top, width: 80, height: 52)
        resultsBar.bounds = CGRect(x: 0, y: 0, width: width, height: 52 + view.safeAreaInsets.bottom)
        resultsBar.center = CGPoint(x: width / 2, y: view.bounds.height - resultsBar.bounds.height / 2)
        resultsBar.subviews.first?.frame = resultsBar.bounds
        resultsBar.viewWithTag(1)?.frame = CGRect(x: 8, y: 4, width: 44, height: 44)
        resultsBar.viewWithTag(2)?.frame = CGRect(x: 56, y: 4, width: 44, height: 44)
        let counterSize = resultsCounter.intrinsicContentSize
        resultsCounter.frame = CGRect(x: width - 20 - counterSize.width, y: 26 - counterSize.height / 2, width: counterSize.width,
                                      height: counterSize.height)
        selectionHeader.subviews.first?.frame = selectionHeader.bounds
        selectionHeader.viewWithTag(1)?.frame = CGRect(x: 8, y: top, width: 80, height: 52)
        selectionTitle.frame = CGRect(x: 96, y: top, width: width - 192, height: 52)
        let barHeight = 52 + view.safeAreaInsets.bottom
        // Bounds and center: the bar may be moved away by a transform.
        selectionBar.bounds = CGRect(x: 0, y: 0, width: width, height: barHeight)
        selectionBar.center = CGPoint(x: width / 2, y: view.bounds.height - barHeight / 2)
        selectionBar.subviews.first?.frame = selectionBar.bounds
        selectionBar.viewWithTag(1)?.frame = CGRect(x: 8, y: 4, width: 52, height: 44)
        selectionBar.viewWithTag(2)?.frame = CGRect(x: width - 60, y: 4, width: 52, height: 44)

        table.frame = view.bounds
        let topInset = pinned.frame.maxY
        let bottomInset = view.bounds.height - messageAreaBottom + 4
        let wasAtBottom = isNearBottom
        table.contentInset = UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
        table.verticalScrollIndicatorInsets = table.contentInset
        // Keep liquid below the pinned bar and above the composer, including with the keyboard up.
        reactionFluid.frame = CGRect(x: 0, y: topInset, width: width, height: max(0, messageAreaBottom - topInset))
        scrollDown.frame = CGRect(x: width - 54, y: messageAreaBottom - 54, width: 42, height: 42)
        updateNextChannelIndicator(feedback: false)
        if !didScrollToBottom, input.frame.height > 0 {
            didScrollToBottom = true
            table.layoutIfNeeded()
            scrollToBottom(animated: false)
            DispatchQueue.main.async { self.initialPosition() }
        } else if wasAtBottom, !channelTransitioning, !table.isDragging, !table.isDecelerating {
            scrollToBottom(animated: false)
        }
    }

    /// Opens at the unread band (like Telegram) or at the bottom, once the bars have their size.
    private func initialPosition() {
        if chat.kind == .channel, let state = home?.channelReadingStates[channelAccount]?[chat.id] {
            restoreChannelPosition(state)
        } else if let divider = dividerPath {
            let bandTop = table.rectForRow(at: divider).minY - table.contentInset.top - 40
            let bottom = table.contentSize.height - table.bounds.height + table.contentInset.bottom
            table.contentOffset.y = max(-table.contentInset.top, min(bandTop, bottom))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                guard let self, let path = self.dividerPath else { return }
                (self.table.cellForRow(at: path) as? MTMessageCell)?.pulseDivider()
            }
        } else if chat.kind == .channel {
            table.contentOffset.y = -table.contentInset.top
        } else {
            scrollToBottom(animated: false)
        }
        updatePinned()
    }

    private var isNearBottom: Bool {
        distanceFromBottom < 40
    }

    private var distanceFromBottom: CGFloat {
        table.contentSize.height - (table.contentOffset.y + table.bounds.height - table.contentInset.bottom)
    }

    private func scrollToBottom(animated: Bool) {
        let y = max(-table.contentInset.top, table.contentSize.height - table.bounds.height + table.contentInset.bottom)
        table.setContentOffset(CGPoint(x: 0, y: y), animated: animated)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        avatar.online = chat.online
    }

    private func setStatus(typing: Bool) {
        let text = typing ? "typing" : (chat.online ? "online" : (chat.kind == .channel ? "1,248 subscribers" : "last seen recently"))
        UIView.transition(with: statusLabel, duration: 0.2, options: .transitionCrossDissolve) {
            self.statusLabel.text = text
            self.statusLabel.textColor = typing || self.chat.online ? MTPalette.accent : MTPalette.secondary
        }
        UIView.animate(withDuration: 0.2) { self.statusDots.alpha = typing ? 1 : 0 }
        view.setNeedsLayout()
    }

    @objc private func openProfile() {
        view.endEditing(true)
        home?.openProfile(chat.person, online: chat.online)
    }

    // MARK: Model helpers

    private func message(at path: IndexPath) -> MTMessage {
        sections[path.section].messages[path.row]
    }

    private func indexPath(of id: Int) -> IndexPath? {
        for (section, day) in sections.enumerated() {
            if let row = day.messages.firstIndex(where: { $0.id == id }) { return IndexPath(row: row, section: section) }
        }
        return nil
    }

    private var dividerPath: IndexPath? {
        for (section, day) in sections.enumerated() {
            if let row = day.messages.firstIndex(where: \.isDivider) { return IndexPath(row: row, section: section) }
        }
        return nil
    }

    /// Runs of one sender's messages are joined; the band and day breaks split them.
    private func style(at path: IndexPath) -> MTBubbleStyle {
        if chat.kind == .channel { return MTBubbleStyle(outgoing: false) }
        let messages = sections[path.section].messages
        let current = messages[path.row]
        func joins(_ other: MTMessage?) -> Bool {
            guard let other, !other.isDivider else { return false }
            return other.outgoing == current.outgoing
        }
        return MTBubbleStyle(outgoing: current.outgoing,
                             joinedTop: joins(path.row > 0 ? messages[path.row - 1] : nil),
                             joinedBottom: joins(path.row + 1 < messages.count ? messages[path.row + 1] : nil))
    }

    private func cell(for id: Int) -> MTMessageCell? {
        indexPath(of: id).flatMap { table.cellForRow(at: $0) as? MTMessageCell }
    }

    /// After rows came or went: tails flow to their new bubbles, gaps adjust.
    private func refreshStyles(animated: Bool) {
        for path in table.indexPathsForVisibleRows ?? [] {
            (table.cellForRow(at: path) as? MTMessageCell)?.setStyle(style(at: path), animated: animated)
        }
        table.performBatchUpdates(nil)
    }

    // MARK: Sending

    private var now: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }

    private func sendText(_ text: String) {
        if let editingID {
            finishEditing(editingID, text: text)
            return
        }
        let quote = replyTo.map { MTMessage.Quote(name: $0.outgoing ? "You" : chat.person.name, text: $0.summary) }
        let start = input.fieldFrame(in: view)
        let link = input.linkPreview
        clearComposerMode()
        var message = MTMessage(kind: .text(text), outgoing: true, time: now, read: false)
        message.reply = quote
        message.link = link
        append(message, flyFrom: start)
        if let effect = MTMessageEffect.effect(for: text) { playEffect(effect, on: message.id, delay: 0.45) }
    }

    /// The sticker leaves the suggestions strip and flies to its place in the chat, straightening up.
    private func sendSticker(_ sticker: String, from cell: UIImageView) {
        let message = MTMessage(kind: .sticker(sticker), outgoing: true, time: now, read: false)
        storageSession?.save(message, chatID: chat.id, origin: storageOrigin, completion: { [weak self] in
            guard let self else { return }
            self.committed { self.animateSticker(message, from: cell) }
        })
    }

    private func animateSticker(_ message: MTMessage, from cell: UIImageView) {
        guard case .sticker(let sticker) = message.kind else { return }
        let start = cell.convert(cell.bounds, to: view)
        let tilt = atan2(cell.transform.b, cell.transform.a)
        append(message, animated: false)
        guard let target = self.cell(for: message.id)?.bubble else { return }
        let end = target.convert(target.bounds, to: view)
        target.alpha = 0
        if let effect = MTMessageEffect.effect(for: sticker) { playEffect(effect, on: message.id, delay: 0.55) }
        let flyer = UIImageView(image: MTStickers.image(sticker))
        flyer.bounds = CGRect(origin: .zero, size: start.size)
        flyer.center = start.center
        flyer.transform = CGAffineTransform(rotationAngle: tilt)
        view.addSubview(flyer)
        UIView.animate(withDuration: 0.6, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0, animations: {
            flyer.bounds = CGRect(origin: .zero, size: end.size)
            flyer.center = end.center
            flyer.transform = CGAffineTransform(rotationAngle: 0)
        }, completion: { _ in
            target.alpha = 1
            flyer.removeFromSuperview()
        })
    }

    /// The full-screen burst for 🎉 ❤️ 👍 🔥, out of the message's bubble.
    private func playEffect(_ emoji: String, on id: Int, delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, let window = self.view.window, let bubble = self.cell(for: id)?.bubble else { return }
            MTMessageEffect.play(emoji, in: window, from: bubble.convert(bubble.bounds.center, to: window))
        }
    }

    private func send(_ kind: MTMessage.Kind) {
        let message = MTMessage(kind: kind, outgoing: true, time: now, read: false)
        append(message)
    }

    private func append(_ message: MTMessage, flyFrom start: CGRect? = nil, fromTyping: Bool = false, animated: Bool = true) {
        if !applyingStoredChange {
            storageSession?.save(message, chatID: chat.id, origin: storageOrigin, onFailure: { [weak self] in
                if let text = message.text { self?.input.setText(text, editing: false) }
            }) { [weak self] in
                guard let self else { return }
                self.committed { self.append(message, flyFrom: start, fromTyping: fromTyping, animated: animated) }
            }
            return
        }
        let title = MTStorageMapping.day(message.timestamp)
        if sections.last?.title != title {
            sections.append((title, []))
            table.insertSections(IndexSet(integer: sections.count - 1), with: .none)
        }
        let wasAtBottom = distanceFromBottom < 80
        if fromTyping {
            table.tableFooterView = nil
            typingFooter = nil
        }
        let section = sections.count - 1
        sections[section].messages.append(message)
        let indexPath = IndexPath(row: sections[section].messages.count - 1, section: section)
        UIView.performWithoutAnimation {
            table.insertRows(at: [indexPath], with: .none)
        }
        // The previous bubble hands its tail over.
        if indexPath.row > 0 {
            let previous = IndexPath(row: indexPath.row - 1, section: section)
            (table.cellForRow(at: previous) as? MTMessageCell)?.setStyle(style(at: previous), animated: true)
        }
        let follow = message.outgoing || wasAtBottom
        if message.outgoing {
            // Every sent message turns the wallpaper's colors a step and sends a ripple from the send button.
            wallpaper.pulse(from: input.convert(input.actionCenter, to: view))
        }
        if follow { scrollToBottom(animated: start == nil && animated) }
        table.layoutIfNeeded()
        guard let cell = table.cellForRow(at: indexPath) as? MTMessageCell, let bubble = cell.bubble else {
            if !follow { scrollDown.setCount(scrollDown.count + 1) }
            return
        }
        if !animated {
            // The caller animates it.
        } else if let start {
            fly(text: message.text ?? "", from: start, into: bubble)
        } else if fromTyping {
            // The typing bubble swells into the message.
            let typing = MTTypingFooter.bubbleFrame
            let target = bubble.frame
            bubble.transform = CGAffineTransform(translationX: typing.midX - target.midX, y: typing.midY - target.midY)
                .scaledBy(x: typing.width / target.width, y: typing.height / target.height)
            bubble.alpha = 0.5
            UIView.animate(withDuration: 0.55, delay: 0, usingSpringWithDamping: 0.72, initialSpringVelocity: 0) {
                bubble.transform = .identity
                bubble.alpha = 1
            }
        } else {
            cell.transform = CGAffineTransform(translationX: 0, y: 40).scaledBy(x: 0.9, y: 0.9)
            cell.alpha = 0
            UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0) {
                cell.transform = .identity
                cell.alpha = 1
            }
        }
        if !message.outgoing {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if !follow { scrollDown.setCount(scrollDown.count + 1) }
        }
    }

    /// The text leaves the field: its box grows into the bubble and the words glide to their place.
    private func fly(text: String, from start: CGRect, into bubble: UIView) {
        let target = bubble.convert(bubble.bounds, to: view)
        bubble.alpha = 0
        let box = UIView(frame: start)
        box.backgroundColor = MTPalette.background
        box.layer.cornerRadius = 18
        box.layer.cornerCurve = .continuous
        view.insertSubview(box, belowSubview: input)
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 16)
        label.textColor = MTPalette.text
        label.numberOfLines = 0
        label.frame = CGRect(x: start.minX + 14, y: start.minY + 8, width: min(start.width - 28, label.intrinsicContentSize.width),
                             height: 20)
        view.insertSubview(label, aboveSubview: box)
        let finalLabel = bubble.subviews.compactMap { $0 as? UILabel }.first { $0.text == text }
        let labelTarget = finalLabel.map { $0.convert($0.bounds, to: view) }
            ?? CGRect(x: target.minX + 12, y: target.minY + 7, width: target.width - 24, height: target.height - 14)
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, animations: {
            box.frame = target
            box.backgroundColor = MTPalette.outgoing
            box.layer.cornerRadius = min(17, target.height / 2)
            label.frame = labelTarget
        }, completion: { _ in
            bubble.alpha = 1
            UIView.animate(withDuration: 0.12, animations: {
                box.alpha = 0
                label.alpha = 0
            }, completion: { _ in
                box.removeFromSuperview()
                label.removeFromSuperview()
            })
        })
    }

    // MARK: Reactions

    /// Adds `emoji` from a point in this view, or removes an existing reaction.
    private func toggleReaction(_ emoji: String, on id: Int, from point: CGPoint?) {
        if !applyingStoredChange {
            storageSession?.mutateMessage(chatID: chat.id, messageID: id, origin: storageOrigin, change: { value in
                if value.reactions.contains(emoji) { value.reactions.removeAll { $0 == emoji } }
                else { value.reactions = [emoji] + value.reactions.filter { $0 != emoji }.prefix(2) }
            }) { [weak self] in
                guard let self else { return }
                self.committed { self.toggleReaction(emoji, on: id, from: point) }
            }
            return
        }
        guard let path = indexPath(of: id) else { return }
        var message = message(at: path)
        let adding = !message.reactions.contains(emoji)
        let key = ReactionKey(messageID: id, emoji: emoji)
        let token = UUID()
        cancelReactionViews(for: key)
        pendingReactions[key] = adding ? token : nil
        if adding {
            message.reactions = [emoji] + message.reactions.filter { $0 != emoji }.prefix(2)
        } else {
            message.reactions.removeAll { $0 == emoji }
        }
        sections[path.section].messages[path.row] = message
        for staleKey in Set(pendingReactions.keys).union(reactionFlyers.keys).union(reactionSparks.keys)
            where staleKey.messageID == id && !message.reactions.contains(staleKey.emoji) {
            pendingReactions[staleKey] = nil
            cancelReactionViews(for: staleKey)
        }
        guard let cell = table.cellForRow(at: path) as? MTMessageCell else {
            pendingReactions[key] = nil
            return
        }
        let start = point ?? cell.bubble.map { $0.convert($0.bounds.center, to: view) } ?? view.bounds.center
        cell.configure(message, style: style(at: path), selecting: false, selected: false)
        updateReactionChips(in: cell)
        cell.layoutIfNeeded()
        UIView.animate(withDuration: 0.3) { self.table.performBatchUpdates(nil) }
        if isNearBottom || path == lastPath { scrollToBottom(animated: true) }
        guard adding else { return }
        // Let the new chip acquire its row height before starting. The sink keeps tracking it afterwards.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            if emoji == MTReactions.gas {
                self.flowReaction(key, token: token, from: start)
            } else {
                self.flyReaction(key, token: token, from: start)
            }
        }
    }

    private var lastPath: IndexPath? {
        guard let section = sections.indices.last, !sections[section].messages.isEmpty else { return nil }
        return IndexPath(row: sections[section].messages.count - 1, section: section)
    }

    private func flowReaction(_ key: ReactionKey, token: UUID, from point: CGPoint) {
        guard pendingReactions[key] == token else { return }
        guard view.window != nil, !selecting, let cell = cell(for: key.messageID),
              let bubble = cell.bubble, cell.chip(for: key.emoji) != nil else {
            finishReaction(key, token: token, animated: false)
            return
        }
        let source = bubble.convert(bubble.bounds, to: reactionFluid)
        let started = reactionFluid.play(emoji: key.emoji, from: view.convert(point, to: reactionFluid), around: source,
                                        target: { [weak self] in
            guard let self, self.pendingReactions[key] == token,
                  let currentCell = self.cell(for: key.messageID),
                  currentCell.message?.reactions.contains(key.emoji) == true,
                  let chip = currentCell.chip(for: key.emoji) else { return nil }
            self.updateReactionChips(in: currentCell)
            let target = chip.convert(CGPoint(x: 18, y: chip.bounds.midY), to: self.reactionFluid)
            return self.reactionFluid.bounds.contains(target) ? target : nil
        }, completion: { [weak self] in
            self?.finishReaction(key, token: token, animated: true)
        })
        if !started { flyReaction(key, token: token, from: point) }
    }

    private func flyReaction(_ key: ReactionKey, token: UUID, from start: CGPoint) {
        guard pendingReactions[key] == token else { return }
        guard view.window != nil, !selecting,
              let chip = cell(for: key.messageID)?.chip(for: key.emoji) else {
            finishReaction(key, token: token, animated: false)
            return
        }
        guard !UIAccessibility.isReduceMotionEnabled else {
            finishReaction(key, token: token, animated: true)
            return
        }
        let end = chip.convert(CGPoint(x: 18, y: chip.bounds.midY), to: view)
        let flyer = UILabel()
        flyer.text = key.emoji
        flyer.font = .systemFont(ofSize: 34)
        flyer.sizeToFit()
        flyer.center = start
        flyer.isUserInteractionEnabled = false
        view.addSubview(flyer)
        reactionFlyers[key] = flyer

        let path = UIBezierPath()
        path.move(to: start)
        path.addQuadCurve(to: end, controlPoint: CGPoint(x: (start.x + end.x) / 2, y: min(start.y, end.y) - 90))
        let move = CAKeyframeAnimation(keyPath: "position")
        move.path = path.cgPath
        move.duration = 0.55
        move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.fromValue = 1.4
        shrink.toValue = 0.45
        shrink.duration = 0.55
        flyer.layer.position = end
        flyer.transform = CGAffineTransform(scaleX: 0.45, y: 0.45)
        flyer.layer.add(move, forKey: "move")
        flyer.layer.add(shrink, forKey: "shrink")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            self?.finishReaction(key, token: token, animated: true, sparkle: true)
        }
    }

    private func finishReaction(_ key: ReactionKey, token: UUID, animated: Bool, sparkle: Bool = false) {
        guard pendingReactions[key] == token else { return }
        pendingReactions[key] = nil
        reactionFlyers.removeValue(forKey: key)?.removeFromSuperview()
        guard let chip = cell(for: key.messageID)?.chip(for: key.emoji) else { return }
        chip.alpha = 1
        if animated, view.window != nil {
            if !UIAccessibility.isReduceMotionEnabled {
                MTViews.pop(chip, scale: sparkle ? 1.3 : 1.16)
                if sparkle { sparkleReaction(key, at: chip.convert(CGPoint(x: 18, y: chip.bounds.midY), to: view)) }
            }
            UIImpactFeedbackGenerator(style: sparkle ? .light : .soft).impactOccurred(intensity: 0.65)
        }
    }

    private func sparkleReaction(_ key: ReactionKey, at point: CGPoint) {
        var sparks: [UIView] = []
        for index in 0..<7 {
            let spark = UILabel()
            spark.text = key.emoji
            spark.font = .systemFont(ofSize: 11)
            spark.sizeToFit()
            spark.center = point
            view.addSubview(spark)
            sparks.append(spark)
            let angle = CGFloat(index) / 7 * .pi * 2 + CGFloat.random(in: -0.3...0.3)
            let distance = CGFloat.random(in: 26...40)
            UIView.animate(withDuration: 0.55, delay: 0, options: .curveEaseOut, animations: {
                spark.center = CGPoint(x: point.x + cos(angle) * distance, y: point.y + sin(angle) * distance)
                spark.transform = CGAffineTransform(scaleX: 0.5, y: 0.5).rotated(by: angle)
                spark.alpha = 0
            }, completion: { _ in spark.removeFromSuperview() })
        }
        reactionSparks[key] = sparks
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self, weak first = sparks.first] in
            guard let self, let first, self.reactionSparks[key]?.first === first else { return }
            self.reactionSparks[key] = nil
        }
    }

    private func cancelReactionViews(for key: ReactionKey) {
        reactionFlyers.removeValue(forKey: key)?.removeFromSuperview()
        reactionSparks.removeValue(forKey: key)?.forEach { $0.removeFromSuperview() }
    }

    private func updateReactionChips(in cell: MTMessageCell) {
        guard let message = cell.message else { return }
        for emoji in message.reactions {
            let key = ReactionKey(messageID: message.id, emoji: emoji)
            cell.chip(for: emoji)?.alpha = pendingReactions[key] == nil ? 1 : (emoji == MTReactions.gas ? 0.3 : 0)
        }
    }

    private func stopReactionAnimations() {
        pendingReactions.removeAll()
        reactionFluid.stop()
        for key in Set(reactionFlyers.keys).union(reactionSparks.keys) { cancelReactionViews(for: key) }
        lastFluidTouch = nil
        for case let cell as MTMessageCell in table.visibleCells { updateReactionChips(in: cell) }
    }

    /// Geometry only: no UIKit snapshot or texture upload is needed to keep the obstacles current.
    private func fluidObstacles() -> [MTReactionFluidObstacle] {
        table.visibleCells.compactMap { row in
            guard let cell = row as? MTMessageCell, let bubble = cell.bubble,
                  let message = cell.message, !message.isDivider,
                  let path = table.indexPath(for: cell) else { return nil }
            let rect = bubble.convert(bubble.bounds, to: reactionFluid)
            guard rect.intersects(reactionFluid.bounds), rect.width > 0, rect.height > 0 else { return nil }
            let style = style(at: path)
            let big = Float(min(17, rect.height / 2))
            let joinedTop: Float = style.joinedTop ? 6 : big
            let joinedBottom: Float = style.joinedBottom ? 6 : big
            var corners = message.outgoing ? SIMD4(big, joinedTop, joinedBottom, big)
                : SIMD4(joinedTop, big, big, joinedBottom)
            switch message.kind {
            case .round, .sticker:
                corners = SIMD4(repeating: Float(min(rect.width, rect.height) / 2))
            default: break
            }
            return MTReactionFluidObstacle(rect: rect, corners: corners)
        }
    }

    /// Observe without recognizing, so reply swipes, buttons, and scrolling keep their gestures.
    private func stirReactionFluid(at tablePoint: CGPoint, phase: UITouch.Phase) {
        guard reactionFluid.isActive else { lastFluidTouch = nil; return }
        let point = table.convert(tablePoint, to: reactionFluid)
        guard reactionFluid.bounds.contains(point) else { lastFluidTouch = nil; return }
        let now = CACurrentMediaTime()
        switch phase {
        case .began:
            lastFluidTouch = (point, now)
        case .moved:
            if let last = lastFluidTouch {
                let dt = CGFloat(max(now - last.time, 1.0 / 240))
                reactionFluid.stir(at: point, velocity: CGVector(dx: (point.x - last.point.x) / dt,
                                                                dy: (point.y - last.point.y) / dt))
            }
            lastFluidTouch = (point, now)
        default:
            lastFluidTouch = nil
        }
    }

    // MARK: Menu, reply, edit

    private func openMenu(for id: Int) {
        guard let cell = cell(for: id), let bubble = cell.bubble, let message = cell.message else { return }
        view.endEditing(true)
        if chat.kind == .channel {
            var actions: [(String, String, MTMessageMenu.Action)] = [("Forward", "arrowshape.turn.up.right", .forward)]
            if message.text != nil { actions.insert(("Copy", "doc.on.doc", .copy), at: 0) }
            let menu = MTMessageMenu(in: view, bubble: bubble, outgoing: false, actions: actions)
            menu.onReaction = { [weak self] emoji, point in self?.toggleReaction(emoji, on: id, from: point) }
            menu.onAction = { [weak self] action in self?.perform(action, on: id) }
            return
        }
        var actions: [(String, String, MTMessageMenu.Action)] = [("Reply", "arrowshape.turn.up.left", .reply)]
        if message.text != nil { actions.append(("Copy", "doc.on.doc", .copy)) }
        if message.outgoing, message.text != nil { actions.append(("Edit", "pencil", .edit)) }
        actions += [("Forward", "arrowshape.turn.up.right", .forward),
                    ("Disappear in 5s", "timer", .vanish), ("Select", "checkmark.circle", .select),
                    ("Delete", "trash", .delete)]
        let menu = MTMessageMenu(in: view, bubble: bubble, outgoing: message.outgoing, actions: actions)
        menu.onReaction = { [weak self] emoji, point in self?.toggleReaction(emoji, on: id, from: point) }
        menu.onAction = { [weak self] action in self?.perform(action, on: id) }
    }

    private func perform(_ action: MTMessageMenu.Action, on id: Int) {
        guard let path = indexPath(of: id) else { return }
        let message = message(at: path)
        switch action {
        case .reply:
            startReply(to: id)
        case .copy:
            UIPasteboard.general.string = message.text
            MTViews.toast("Copied", symbol: "doc.on.doc.fill", in: view, top: pinned.frame.maxY + 8)
        case .edit:
            editingID = id
            replyTo = nil
            input.showPanel(symbol: "pencil", title: "Editing", text: message.summary)
            input.setText(message.text ?? "", editing: true)
            cell(for: id)?.bubble?.flash()
        case .forward:
            storageSession?.forward(message, from: chat.person.name, to: ChannelPerson(name: "Saved Messages", hue: 0.58)) { [weak self] in
                guard let self else { return }
                MTViews.toast("Forwarded to Saved Messages", symbol: "arrowshape.turn.up.right.fill", in: self.view, top: self.pinned.frame.maxY + 8)
            }
        case .vanish:
            let deadline = Date().addingTimeInterval(Self.vanishAfter)
            expiring[id] = deadline
            cell(for: id)?.showCountdown(until: deadline, total: Self.vanishAfter)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.vanishAfter) { [weak self] in self?.evaporate(id) }
        case .select:
            selectedIDs = [id]
            setSelecting(true)
        case .delete:
            delete([id])
        }
    }

    private func startReply(to id: Int) {
        guard let path = indexPath(of: id) else { return }
        let message = message(at: path)
        replyTo = message
        editingID = nil
        input.showPanel(symbol: "arrowshape.turn.up.left", title: message.outgoing ? "You" : chat.person.name, text: message.summary)
        input.focus()
        cell(for: id)?.bubble?.flash()
    }

    private func clearComposerMode() {
        let wasEditing = editingID != nil
        replyTo = nil
        editingID = nil
        input.hidePanel()
        if wasEditing { input.setText("", editing: false) }
    }

    private func finishEditing(_ id: Int, text: String) {
        if !applyingStoredChange {
            storageSession?.mutateMessage(chatID: chat.id, messageID: id, origin: storageOrigin, change: { value in
                value.kind = .text(text); value.edited = true
            }) { [weak self] in
                guard let self else { return }
                self.committed { self.finishEditing(id, text: text) }
            }
            return
        }
        clearComposerMode()
        input.setText("", editing: false)
        guard let path = indexPath(of: id) else { return }
        var message = message(at: path)
        guard message.text != text else { return }
        message.kind = .text(text)
        message.edited = true
        sections[path.section].messages[path.row] = message
        if let cell = table.cellForRow(at: path) as? MTMessageCell {
            cell.configure(message, style: style(at: path), selecting: false, selected: false)
            updateReactionChips(in: cell)
            UIView.animate(withDuration: 0.3) { self.table.performBatchUpdates(nil) }
            cell.bubble?.flash()
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: Selection, deleting

    private func setSelecting(_ on: Bool) {
        if on { stopReactionAnimations() }
        selecting = on
        if !on { selectedIDs = [] }
        view.endEditing(true)
        updateSelectionTitle()
        for path in table.indexPathsForVisibleRows ?? [] {
            (table.cellForRow(at: path) as? MTMessageCell)?.setSelecting(on, selected: selectedIDs.contains(message(at: path).id),
                                                                       animated: true)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
            self.selectionHeader.alpha = on ? 1 : 0
            self.selectionBar.transform = on ? .identity : CGAffineTransform(translationX: 0, y: 120)
            self.input.alpha = on ? 0 : 1
            self.input.transform = on ? CGAffineTransform(translationX: 0, y: 60) : .identity
        }
    }

    private func updateSelectionTitle() {
        UIView.transition(with: selectionTitle, duration: 0.15, options: .transitionCrossDissolve) {
            self.selectionTitle.text = "Selected: \(self.selectedIDs.count)"
        }
    }

    /// A timed-out message melts upward into haze (dust with convection), then its row closes.
    private func evaporate(_ id: Int) {
        if !applyingStoredChange {
            storageSession?.delete(chatID: chat.id, ids: [id], origin: storageOrigin) { [weak self] in
                guard let self else { return }
                self.committed { self.evaporate(id) }
            }
            return
        }
        expiring[id] = nil
        guard let path = indexPath(of: id) else { return }
        let finish = {
            guard let path = self.indexPath(of: id) else { return }
            self.sections[path.section].messages.remove(at: path.row)
            self.table.performBatchUpdates {
                self.table.deleteRows(at: [path], with: .fade)
            } completion: { _ in
                self.refreshStyles(animated: true)
            }
        }
        guard let cell = table.cellForRow(at: path) as? MTMessageCell, let bubble = cell.bubble else {
            finish()
            return
        }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        cell.contentView.subviews.filter { $0 !== bubble }.forEach { view in UIView.animate(withDuration: 0.3) { view.alpha = 0 } }
        DustAnimator.blowAway(bubble, wind: CGVector(dx: 0, dy: -80), gravity: -140, grain: 0.9, releaseWindow: 0.9)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: finish)
    }

    // MARK: Search

    private func buildSearch() {
        searchBar.addSubview(MTViews.barBackground())
        searchField.placeholder = "Search in chat"
        searchField.backgroundColor = MTPalette.fill
        searchField.layer.cornerRadius = 10
        searchField.textColor = MTPalette.text
        searchField.clearButtonMode = .whileEditing
        let glass = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        glass.tintColor = MTPalette.secondary
        glass.contentMode = .center
        glass.frame = CGRect(x: 0, y: 0, width: 34, height: 36)
        searchField.leftView = glass
        searchField.leftViewMode = .always
        searchField.returnKeyType = .search
        searchField.addAction(UIAction { [weak self] _ in self?.searchChanged() }, for: .editingChanged)
        searchBar.addSubview(searchField)
        let cancel = UIButton(type: .system)
        cancel.setTitle("Cancel", for: .normal)
        cancel.titleLabel?.font = .systemFont(ofSize: 17)
        cancel.tintColor = MTPalette.accent
        cancel.tag = 1
        cancel.addAction(UIAction { [weak self] _ in self?.endSearch() }, for: .touchUpInside)
        searchBar.addSubview(cancel)
        searchBar.alpha = 0
        view.addSubview(searchBar)

        resultsBar.addSubview(MTViews.barBackground())
        let older = MTViews.iconButton("chevron.up", size: 19)
        older.tag = 1
        older.addAction(UIAction { [weak self] _ in self?.moveMatch(-1) }, for: .touchUpInside)
        let newer = MTViews.iconButton("chevron.down", size: 19)
        newer.tag = 2
        newer.addAction(UIAction { [weak self] _ in self?.moveMatch(1) }, for: .touchUpInside)
        resultsBar.addSubview(older)
        resultsBar.addSubview(newer)
        resultsCounter.font = .systemFont(ofSize: 15, weight: .medium)
        resultsCounter.textColor = MTPalette.secondary
        resultsBar.addSubview(resultsCounter)
        resultsBar.transform = CGAffineTransform(translationX: 0, y: 120)
        view.addSubview(resultsBar)
    }

    private func startSearch() {
        searchQuery = ""
        matches = []
        resultsCounter.setText("Enter a search query", animated: false)
        view.setNeedsLayout()
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
            self.searchBar.alpha = 1
            self.resultsBar.transform = .identity
            self.input.alpha = 0
        }
        searchField.becomeFirstResponder()
    }

    func setSearch(_ query: String) {
        if searchQuery == nil { startSearch() }
        searchField.text = query
        searchChanged()
    }

    private func searchChanged() {
        let query = searchField.text ?? ""
        searchQuery = query
        matches = query.isEmpty ? [] : sections.flatMap(\.messages).filter {
            $0.text?.replacingOccurrences(of: "||", with: "").range(of: query, options: .caseInsensitive) != nil
        }.map(\.id)
        currentMatch = max(0, matches.count - 1)
        updateHighlights()
        updateResultsCounter(up: true)
        if !matches.isEmpty { jumpToMatch() }
    }

    private func moveMatch(_ step: Int) {
        guard !matches.isEmpty else { return }
        let next = currentMatch + step
        guard matches.indices.contains(next) else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        currentMatch = next
        UISelectionFeedbackGenerator().selectionChanged()
        updateHighlights()
        updateResultsCounter(up: step > 0)
        jumpToMatch()
    }

    private func updateResultsCounter(up: Bool) {
        let text = searchQuery?.isEmpty != false ? "Enter a search query" : matches.isEmpty ? "No results" : "\(currentMatch + 1) of \(matches.count)"
        resultsCounter.setText(text, animated: true, up: up)
        view.setNeedsLayout()
    }

    private func jumpToMatch() {
        guard let path = indexPath(of: matches[currentMatch]) else { return }
        table.scrollToRow(at: path, at: .middle, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, let cell = self.table.cellForRow(at: path) as? MTMessageCell else { return }
            cell.bubble?.flash()
        }
    }

    private var currentMatchID: Int? { matches.indices.contains(currentMatch) ? matches[currentMatch] : nil }

    private func updateHighlights() {
        for path in table.indexPathsForVisibleRows ?? [] {
            guard let bubble = (table.cellForRow(at: path) as? MTMessageCell)?.bubble as? MTMessageBubble else { continue }
            let id = message(at: path).id
            bubble.highlight(matches.contains(id) ? searchQuery : nil, current: id == currentMatchID)
        }
    }

    private func endSearch() {
        searchQuery = nil
        matches = []
        searchField.text = ""
        view.endEditing(true)
        updateHighlights()
        UIView.animate(withDuration: 0.3) {
            self.searchBar.alpha = 0
            self.resultsBar.transform = CGAffineTransform(translationX: 0, y: 120)
            self.input.alpha = 1
        }
    }

    // MARK: Themes

    private func openThemes() {
        let original = MTChatTheme.current
        let wasNight = traitCollection.userInterfaceStyle == .dark
        let sheet = MTThemeSheet(in: view, selected: original, night: wasNight)
        sheet.onPreview = { [weak self] index in self?.applyTheme(index) }
        sheet.onNight = { [weak self] night in self?.setNight(night) }
        sheet.onCancel = { [weak self] in
            guard let self else { return }
            self.applyTheme(original)
            if (self.traitCollection.userInterfaceStyle == .dark) != wasNight { self.setNight(wasNight) }
        }
    }

    /// The wallpaper glides to the theme's palette and your bubbles take its color.
    private func applyTheme(_ index: Int) {
        guard index != MTChatTheme.current else { return }
        MTChatTheme.current = index
        let theme = MTChatTheme.all[index]
        wallpaper.setTheme(day: theme.day, night: theme.night, animated: true)
        for cell in table.visibleCells {
            cell.contentView.subviews.compactMap { $0 as? MTBubbleContent }.forEach {
                $0.setNeedsLayout()
                $0.layoutIfNeeded()
            }
        }
    }

    /// The chat UI crossfades to the other style while the wallpaper goes through dusk to night.
    private func setNight(_ night: Bool) {
        guard let root = home?.root else { return }
        let covers = [table, header, pinned, input].compactMap { view -> UIView? in
            guard let snapshot = view.snapshotView(afterScreenUpdates: false) else { return nil }
            snapshot.frame = view.frame
            self.view.insertSubview(snapshot, aboveSubview: view)
            return snapshot
        }
        root.overrideUserInterfaceStyle = night ? .dark : .light
        root.setNeedsStatusBarAppearanceUpdate()
        UIView.animate(withDuration: 0.7, delay: 0.1, options: .curveEaseInOut, animations: {
            covers.forEach { $0.alpha = 0 }
        }, completion: { _ in covers.forEach { $0.removeFromSuperview() } })
    }

    // MARK: Photos

    private func openPhotos(_ id: Int, index: Int) {
        guard let photos = cell(for: id)?.bubble as? MTPhotosBubble, let path = indexPath(of: id) else { return }
        view.endEditing(true)
        _ = MTPhotoViewer(in: view, sources: photos.images, start: index,
                          title: "\(message(at: path).outgoing ? "You" : chat.person.name), \(message(at: path).time)")
    }

    /// Bubbles crumble one after another, then their rows close up.
    private func delete(_ ids: Set<Int>) {
        if !applyingStoredChange {
            storageSession?.delete(chatID: chat.id, ids: ids, origin: storageOrigin) { [weak self] in
                guard let self else { return }
                self.committed { self.delete(ids) }
            }
            return
        }
        let paths = ids.compactMap { indexPath(of: $0) }.sorted()
        guard !paths.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        var delay: TimeInterval = 0
        for path in paths {
            guard let cell = table.cellForRow(at: path) as? MTMessageCell, let bubble = cell.bubble else { continue }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                DustAnimator.blowAway(bubble, wind: CGVector(dx: bubble.frame.minX > 100 ? 60 : -60, dy: -50))
                UIView.animate(withDuration: 0.2) { cell.contentView.subviews.filter { $0 is UIControl }.forEach { $0.alpha = 0 } }
            }
            delay += 0.08
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.35) { [weak self] in
            guard let self else { return }
            let current = ids.compactMap { self.indexPath(of: $0) }.sorted()
            for path in current.reversed() {
                self.sections[path.section].messages.remove(at: path.row)
            }
            self.table.performBatchUpdates {
                self.table.deleteRows(at: current, with: .fade)
            } completion: { _ in
                self.refreshStyles(animated: true)
            }
        }
    }

    // MARK: Pinned

    private var pinnedPaths: [IndexPath] {
        var paths = Array(repeating: IndexPath(row: 0, section: 0), count: MTData.pinnedMessages.count)
        for (section, day) in sections.enumerated() {
            for (row, message) in day.messages.enumerated() {
                if let pin = message.pinned { paths[pin] = IndexPath(row: row, section: section) }
            }
        }
        return paths
    }

    /// Shows the newest pin above the top of the screen; when none is above, the newest overall.
    private func updatePinned() {
        guard chat.kind != .channel, !jumpingToPin else { return }
        let topY = table.contentOffset.y + table.contentInset.top
        let paths = pinnedPaths
        var shown = paths.count - 1
        for (index, path) in paths.enumerated() where table.rectForRow(at: path).minY < topY {
            shown = index
        }
        if pinned.current != shown { pinned.set(shown, animated: true) }
    }

    @objc private func pinnedTapped() {
        let index = pinned.current
        let path = pinnedPaths[index]
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        jumpingToPin = true
        table.scrollToRow(at: path, at: .middle, animated: true)
        pinned.set(index == 0 ? MTData.pinnedMessages.count - 1 : index - 1, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self else { return }
            self.jumpingToPin = false
            (self.table.cellForRow(at: path) as? MTMessageCell)?.bubble?.flash()
        }
    }

    // MARK: Floating date

    private func showDates() {
        fadeWork?.cancel()
        for section in sections.indices {
            guard let header = table.headerView(forSection: section) else { continue }
            if header.alpha < 1 { UIView.animate(withDuration: 0.15) { header.alpha = 1 } }
        }
    }

    /// Fades out the header that is stuck to the top (the floating one), keeps the inline ones.
    private func scheduleDateFade() {
        fadeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            for section in self.sections.indices {
                guard let header = self.table.headerView(forSection: section) else { continue }
                let natural = self.table.rectForHeader(inSection: section).minY
                if header.frame.minY > natural + 0.5 {
                    UIView.animate(withDuration: 0.35) { header.alpha = 0 }
                }
            }
        }
        fadeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: work)
    }

    // MARK: Attach

    private func openAttach() {
        view.endEditing(true)
        let sheet = MTAttachSheet(in: view)
        sheet.onSend = { [weak self] scenes in self?.send(.photos(scenes)) }
    }

    // MARK: Voice

    private func recordGesture(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            view.endEditing(true)
            let center = input.convert(input.actionCenter, to: view)
            let recorder = MTVoiceRecorder(in: view, buttonCenter: center, bar: input.frame, video: input.videoMode)
            recorder.onSend = { [weak self] duration, video in
                self?.send(video ? .round(.aurora) : .voice(duration))
            }
            recorder.onFinish = { [weak self] in self?.input.setRecording(false) }
            input.setRecording(true)
            self.recorder = recorder
            recorderStart = gesture.location(in: view)
        case .changed:
            let point = gesture.location(in: view)
            recorder?.drag(CGPoint(x: point.x - recorderStart.x, y: point.y - recorderStart.y))
        case .ended:
            recorder?.release()
        case .cancelled, .failed:
            recorder?.cancel()
        default:
            break
        }
    }

    private var recorderStart = CGPoint.zero
}

extension MTChatViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].messages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let message = message(at: indexPath)
        if chat.kind == .channel, message.channelPost != nil {
            let cell = tableView.dequeueReusableCell(withIdentifier: "channelPost", for: indexPath) as! MTChannelPostCell
            cell.configure(message, channel: chat.person)
            if let post = cell.postView { bindChannelPost(post, messageID: message.id) }
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: "message", for: indexPath) as! MTMessageCell
        let id = message.id
        cell.configure(message, style: style(at: indexPath), selecting: selecting, selected: selectedIDs.contains(id))
        updateReactionChips(in: cell)
        cell.onDoubleTap = { [weak self, weak cell] point in
            guard let self, let cell else { return }
            self.toggleReaction("❤️", on: id, from: cell.convert(point, to: self.view))
        }
        cell.onLongPress = { [weak self] in self?.openMenu(for: id) }
        cell.onReply = { [weak self] in
            guard let self, self.chat.kind != .channel else { return }
            self.startReply(to: id)
        }
        cell.onReplySwipe = { [weak self] bubble, pull, snapped in
            self?.replySwipeEffect.update(bubble: bubble, pull: pull, snapped: snapped)
        }
        cell.onReaction = { [weak self] emoji in self?.toggleReaction(emoji, on: id, from: nil) }
        cell.onPhoto = { [weak self] index, _ in self?.openPhotos(id, index: index) }
        if let deadline = expiring[id] { cell.showCountdown(until: deadline, total: Self.vanishAfter) }
        if searchQuery != nil, matches.contains(id) {
            (cell.bubble as? MTMessageBubble)?.highlight(searchQuery, current: id == currentMatchID)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let message = message(at: indexPath)
        if let post = message.channelPost {
            let width = tableView.bounds.width
            if let cached = channelPostHeights[message.id], cached.width == width { return cached.height }
            let height = MTChannelPostCell.height(for: post, channel: chat.person, width: width)
            channelPostHeights[message.id] = (width, height)
            return height
        }
        return MTMessageCell.height(message, style: style(at: indexPath), width: tableView.bounds.width)
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let message = message(at: indexPath)
        guard selecting, !message.isDivider else { return }
        if selectedIDs.remove(message.id) == nil { selectedIDs.insert(message.id) }
        UISelectionFeedbackGenerator().selectionChanged()
        (tableView.cellForRow(at: indexPath) as? MTMessageCell)?.setSelecting(true, selected: selectedIDs.contains(message.id),
                                                                              animated: true)
        updateSelectionTitle()
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: "date") as! MTDateHeader
        header.pill.text = sections[section].title
        header.alpha = 1
        return header
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        36
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView.isDragging, hasOlderHistory, !loadingOlder,
           scrollView.contentOffset.y < -scrollView.contentInset.top + 40,
           sections.reduce(0, { $0 + $1.messages.count }) >= 500 {
            loadingOlder = true
            let count = sections.reduce(0) { $0 + $1.messages.count }
            let oldHeight = table.contentSize.height
            let oldOffset = table.contentOffset
            storageSession?.loadOlder(chatID: chat.id) { [weak self] in
                guard let self else { return }
                self.reloadStoredHistory()
                self.hasOlderHistory = self.sections.reduce(0, { $0 + $1.messages.count }) > count
                self.table.contentOffset.y = oldOffset.y + self.table.contentSize.height - oldHeight
                self.loadingOlder = false
            }
        }
        guard didScrollToBottom else { return }
        updatePinned()
        updateNextChannelIndicator(feedback: scrollView.isDragging)
        if scrollView.isDragging || scrollView.isDecelerating { showDates() }
        scrollDown.setShown(distanceFromBottom > 220)
        // Pulling the chat down past its first message opens the mini profile.
        if chat.kind != .channel, scrollView.isDragging, headerExpansion == 0, scrollView.contentOffset.y < -scrollView.contentInset.top - 90 {
            setHeaderExpansion(1, animated: true)
        }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        if headerExpansion > 0 { setHeaderExpansion(0, animated: true) }
    }

    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard nextChannelIndicator.armed, !channelTransitioning, let next = nextChannel else { return }
        targetContentOffset.pointee.y = max(-table.contentInset.top,
            table.contentSize.height - table.bounds.height + table.contentInset.bottom)
        beginChannelTransition(to: next)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { scheduleDateFade() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        scheduleDateFade()
    }
}

// MARK: - Telegram Post interactions (channels only)

private extension MTChatViewController {
    func bindChannelPost(_ post: ChannelPostView, messageID: Int) {
        post.onLongPress = { [weak self] post, gesture in
            self?.channelLongPress(post, messageID: messageID, gesture: gesture)
        }
        post.onDoubleTap = { [weak self] post, point in
            guard let self else { return }
            self.reactToChannelPost(post, messageID: messageID,
                                   emoji: "❤️", from: post.convert(point, to: self.channelEffectsHost), heart: true)
        }
        post.onChipTap = { [weak self] post, chip in
            guard let self else { return }
            if chip.chosen {
                chip.crumbleEmoji()
                chip.set(count: max(0, chip.count - 1), chosen: false, animated: true)
                if chip.count == 0 { post.chips.remove(chip) }
                self.storeChannelPost(post, messageID: messageID)
                self.resizeChannelPosts()
            } else {
                let point = post.chips.landingPoint(of: chip, in: self.channelEffectsHost)
                self.reactToChannelPost(post, messageID: messageID, emoji: chip.emoji,
                                         from: CGPoint(x: point.x, y: point.y - 70))
            }
        }
        post.onStarsSent = { [weak self] post, _ in
            guard let self else { return }
            self.storeChannelPost(post, messageID: messageID)
            self.wallpaper.pulse(from: post.bubble.convert(CGPoint(x: post.bubble.bounds.midX, y: post.bubble.bounds.maxY),
                                                         to: self.wallpaper))
            self.resizeChannelPosts()
        }
        post.onComments = { [weak self] post in
            guard let self else { return }
            self.channelComments?.removeFromSuperview()
            let sheet = CommentsSheetOverlay(in: self.view, bubble: post.bubble, buttonPoint: post.commentsPoint(in: self.view),
                                             count: post.post.comments, people: trickPeople)
            sheet.onClose = { [weak self] in self?.channelComments = nil }
            self.channelComments = sheet
        }
        post.onForward = { [weak self] post, gesture in
            guard let self else { return }
            switch gesture.state {
            case .began:
                self.channelForward?.removeFromSuperview()
                self.channelForward = ForwardDropOverlay(in: self.view, button: post.forwardButton, post: post.bubble,
                                                         people: Array(trickPeople.prefix(5)))
                self.channelForward?.onSend = { [weak self] person, done in
                    guard let self, let path = self.indexPath(of: messageID) else { return }
                    self.storageSession?.forward(self.message(at: path), from: self.chat.person.name, to: person, completion: done)
                }
            case .changed:
                self.channelForward?.move(to: gesture.location(in: self.view))
            default:
                self.channelForward?.release()
            }
        }
    }

    func channelLongPress(_ post: ChannelPostView, messageID: Int, gesture: UILongPressGestureRecognizer) {
        guard !channelTransitioning else { return }
        let point = gesture.location(in: view)
        switch gesture.state {
        case .began:
            channelPicker?.removeFromSuperview()
            let picker = ReactionPickerOverlay(in: view, bubble: post.bubble, at: point,
                emojis: ["❤️", "👍", "🔥", "😁", "🙏", "👏", "🤯"],
                more: ["😂", "🥰", "😍", "🤩", "😎", "🤔", "😱", "🥳",
                       "😭", "🤝", "💯", "⚡", "🎉", "🙈", "😇", "🤗",
                       "👀", "💔", "🤡", "🏆", "🍾", "🌚", "🥱", "🤓",
                       "✍️", "💅", "🫡", "🦄", "🐳", "🍓", "🌭", "👻"])
            picker.onChoice = { [weak self] choice in
                guard let self else { return }
                self.channelPicker = nil
                switch choice {
                case let .emoji(emoji, origin):
                    guard let path = self.indexPath(of: messageID) else { return }
                    if let current = (self.table.cellForRow(at: path) as? MTChannelPostCell)?.postView {
                        self.reactToChannelPost(current, messageID: messageID, emoji: emoji,
                                               from: self.view.convert(origin, to: self.channelEffectsHost))
                    } else if var value = self.sections[path.section].messages[path.row].channelPost {
                        if let index = value.reactions.firstIndex(where: { $0.emoji == emoji }) {
                            if !value.reactions[index].chosen {
                                value.reactions[index].count += 1
                                value.reactions[index].chosen = true
                            }
                        } else {
                            value.reactions.append(ChannelReaction(emoji: emoji, count: 1, chosen: true))
                        }
                        self.persistChannelValue(value, messageID: messageID)
                    }
                case .delete:
                    self.deleteChannelPost(messageID)
                case .dismissed: break
                }
            }
            channelPicker = picker
        case .changed: channelPicker?.move(to: point)
        default: channelPicker?.release()
        }
    }

    func reactToChannelPost(_ post: ChannelPostView, messageID: Int, emoji: String, from point: CGPoint, heart: Bool = false) {
        guard indexPath(of: messageID) != nil, !channelTransitioning else { return }
        let chip = post.chips.chip(for: emoji) ?? post.chips.insertChip(ChannelReaction(emoji: emoji, count: 0))
        if !chip.chosen { chip.set(count: chip.count + 1, chosen: true, animated: true) }
        chip.alpha = 1
        // Commit before flight so scrolling, reuse, or switching cannot lose the user's choice.
        storeChannelPost(post, messageID: messageID)
        resizeChannelPosts()
        guard !UIAccessibility.isReduceMotionEnabled else { chip.gulp(); return }
        let channelID = chat.id
        let target: () -> (point: CGPoint, chip: CGRect) = { [weak self, weak post, weak chip] in
            guard let self, let post, let chip, self.chat.id == channelID, post.window != nil else { return (point, .zero) }
            return (post.chips.landingPoint(of: chip, in: self.channelEffectsHost),
                    chip.convert(chip.bounds, to: self.channelEffectsHost))
        }
        let landed: () -> Void = { [weak self, weak post, weak chip] in
            guard let self, self.chat.id == channelID, post?.window != nil else { return }
            chip?.gulp(0.3)
            UIAccessibility.post(notification: .layoutChanged, argument: chip)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        if heart {
            HeartPop.show(at: point, in: channelEffectsHost, target: { target().point }, arrive: landed)
        } else {
            ReactionFlight.fly(emoji, from: point, in: channelEffectsHost, liquid: channelReactionLiquid,
                               target: target, landed: landed)
        }
    }

    func storeChannelPost(_ post: ChannelPostView, messageID: Int) {
        var value = post.currentPost
        value.reactions.removeAll { $0.count == 0 }
        persistChannelValue(value, messageID: messageID)
    }

    func persistChannelValue(_ value: ChannelPost, messageID: Int) {
        let peerID = chat.id
        storageSession?.mutateMessage(chatID: peerID, messageID: messageID, origin: storageOrigin,
                                     change: { $0.channelPost = value }) { [weak self] in
            guard let self, self.chat.id == peerID, let path = self.indexPath(of: messageID) else { return }
            self.sections[path.section].messages[path.row].channelPost = value
            self.channelPostHeights[messageID] = nil
        }
    }

    func resizeChannelPosts() {
        let keepBottom = isNearBottom
        table.performBatchUpdates(nil) { [weak self] _ in
            guard let self, keepBottom, let lastPath = self.lastPath else { return }
            self.table.scrollToRow(at: lastPath, at: .bottom, animated: false)
        }
    }

    func deleteChannelPost(_ messageID: Int) {
        if !applyingStoredChange {
            storageSession?.delete(chatID: chat.id, ids: [messageID], origin: storageOrigin) { [weak self] in
                guard let self else { return }
                self.committed { self.deleteChannelPost(messageID) }
            }
            return
        }
        guard let path = indexPath(of: messageID) else { return }
        if UIAccessibility.isReduceMotionEnabled {
            sections[path.section].messages.remove(at: path.row)
            table.deleteRows(at: [path], with: .fade)
        } else {
            channelVacuum.deleteRow(at: path, in: table) { self.sections[path.section].messages.remove(at: path.row) }
        }
        saveChannelReadingPosition()
    }

    func stopChannelPostEffects() {
        channelPicker?.removeFromSuperview()
        channelPicker = nil
        channelForward?.removeFromSuperview()
        channelForward = nil
        channelComments?.removeFromSuperview()
        channelComments = nil
        channelReactionLiquid.stop()
        for child in channelEffectsHost.subviews where child !== channelReactionLiquid { child.removeFromSuperview() }
    }
}

// MARK: - Channel reading and pull-to-next transition

private extension MTChatViewController {
    var nextChannel: MTChat? {
        guard chat.kind == .channel, let home, home.currentAccount == channelAccount else { return nil }
        let channels = home.chatList.channels
        guard channels.count > 1, let current = channels.firstIndex(where: { $0.id == chat.id }) else { return nil }
        return channels[(current + 1) % channels.count]
    }

    func configureChannelChrome() {
        guard chat.kind == .channel else { return }
        input.isHidden = true
        pinned.isHidden = true
        callButton.isHidden = true
        backButton.accessibilityCustomActions = [UIAccessibilityCustomAction(name: "Next channel") { [weak self] _ in
            guard let self, !self.channelTransitioning, let next = self.nextChannel else { return false }
            self.beginChannelTransition(to: next)
            return true
        }]
    }

    func saveChannelReadingPosition() {
        guard chat.kind == .channel, didScrollToBottom, let home else { return }
        let bottom = max(0, table.contentSize.height - table.bounds.height + table.contentInset.top + table.contentInset.bottom)
        let position = min(max(0, table.contentOffset.y + table.contentInset.top), bottom)
        let top = table.contentOffset.y + table.contentInset.top
        let anchor = (table.indexPathsForVisibleRows ?? []).sorted().first { path in
            guard sections.indices.contains(path.section), sections[path.section].messages.indices.contains(path.row) else { return false }
            return table.rectForRow(at: path).maxY > top
        }
        home.channelReadingStates[channelAccount, default: [:]][chat.id] = MTChannelReadingState(
            sections: sections, position: position, anchorMessageID: anchor.map { message(at: $0).id },
            anchorOffset: anchor.map { table.rectForRow(at: $0).minY - top } ?? 0, atBottom: distanceFromBottom < 40)
        if let state = home.channelReadingStates[channelAccount]?[chat.id] {
            storageSession?.savePosition(chatID: chat.id, state: state)
        }
    }

    func restoreChannelPosition(_ state: MTChannelReadingState) {
        if state.atBottom, let lastPath {
            table.scrollToRow(at: lastPath, at: .bottom, animated: false)
            table.layoutIfNeeded()
            scrollToBottom(animated: false)
            return
        }
        if let id = state.anchorMessageID, let path = indexPath(of: id) {
            table.scrollToRow(at: path, at: .top, animated: false)
            table.layoutIfNeeded()
            let y = table.rectForRow(at: path).minY - table.contentInset.top - state.anchorOffset
            table.setContentOffset(CGPoint(x: 0, y: max(-table.contentInset.top, y)), animated: false)
            return
        }
        let position = state.position
        let bottom = max(-table.contentInset.top, table.contentSize.height - table.bounds.height + table.contentInset.bottom)
        table.setContentOffset(CGPoint(x: 0, y: min(bottom, max(-table.contentInset.top, position - table.contentInset.top))),
                               animated: false)
    }

    func updateNextChannelIndicator(feedback: Bool) {
        guard chat.kind == .channel, !channelTransitioning, !selecting, searchQuery == nil,
              !UIAccessibility.isVoiceOverRunning else {
            nextChannelIndicator.reset()
            return
        }
        let bottom = max(-table.contentInset.top, table.contentSize.height - table.bounds.height + table.contentInset.bottom)
        let pull = max(0, table.contentOffset.y - bottom)
        nextChannelIndicator.frame = CGRect(x: 0, y: max(pinned.frame.maxY + 8, messageAreaBottom - pull - 4),
                                            width: view.bounds.width, height: 102)
        nextChannelIndicator.update(pull: pull, next: nextChannel, feedback: feedback)
    }

    func beginChannelTransition(to next: MTChat) {
        guard !channelTransitioning, chat.kind == .channel, next.id != chat.id, view.window != nil else { return }
        channelTransitioning = true
        let origin = nextChannelIndicator.alpha > 0.1 ? nextChannelIndicator.avatarRect
            : CGRect(x: view.bounds.midX - 22, y: messageAreaBottom - 54, width: 44, height: 44)
        nextChannelIndicator.reset()
        // Finish the drag callback before stopping deceleration and replacing its data source.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.channelTransitioning else { return }
            guard self.view.window != nil else { self.stopChannelTransition(); return }
            self.switchChannel(to: next, avatarOrigin: origin)
        }
    }

    func switchChannel(to next: MTChat, avatarOrigin: CGRect) {
        saveChannelReadingPosition()
        stopChannelPostEffects()
        stopReactionAnimations()
        fadeWork?.cancel()
        table.isScrollEnabled = false
        let viewport = CGRect(x: 0, y: pinned.frame.maxY, width: view.bounds.width,
                              height: max(0, messageAreaBottom - pinned.frame.maxY))
        let old = table.resizableSnapshotView(from: table.convert(viewport, from: view), afterScreenUpdates: false,
                                              withCapInsets: .zero)
        let overlay = UIView(frame: viewport)
        overlay.clipsToBounds = true
        view.insertSubview(overlay, belowSubview: pinned)
        channelTransitionOverlay = overlay

        chat = next
        sections = storageSession?.sections(for: next.id) ?? [("Today", [])]
        hasOlderHistory = true
        observeStoredHistory()
        home?.chatList.markRead(next.id)
        table.reloadData()
        table.layoutIfNeeded()
        initialPosition()
        nameLabel.text = next.person.name
        avatar.set(next.person, size: 38)
        avatar.online = false
        setStatus(typing: false)
        layoutHeader()

        let incoming = table.resizableSnapshotView(from: table.convert(viewport, from: view), afterScreenUpdates: true,
                                                   withCapInsets: .zero)
        for snapshot in [old, incoming].compactMap({ $0 }) {
            snapshot.frame = overlay.bounds
            overlay.addSubview(snapshot)
        }
        let reducedMotion = UIAccessibility.isReduceMotionEnabled
        table.alpha = incoming == nil ? 1 : 0
        incoming?.alpha = 0
        if !reducedMotion { incoming?.transform = CGAffineTransform(translationX: 0, y: viewport.height * 0.6) }
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        if !reducedMotion {
            let flyer = UIImageView(image: ChannelAvatar.image(for: next.person, size: 44))
            flyer.frame = avatarOrigin
            view.addSubview(flyer)
            channelAvatarFlyer = flyer
            avatar.alpha = 0
            UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
                flyer.frame = self.avatar.convert(self.avatar.bounds, to: self.view)
            } completion: { [weak self] _ in
                flyer.removeFromSuperview()
                self?.avatar.alpha = 1
            }
        }
        UIView.animate(withDuration: reducedMotion ? 0.2 : 0.45, delay: 0, options: .curveEaseIn) {
            if !reducedMotion {
                old?.transform = CGAffineTransform(translationX: 0, y: -viewport.height * 0.4).scaledBy(x: 0.92, y: 0.92)
            }
            old?.alpha = 0
        }
        UIView.animate(withDuration: reducedMotion ? 0.2 : 0.7, delay: reducedMotion ? 0 : 0.1,
                       usingSpringWithDamping: 0.78, initialSpringVelocity: 0.2) {
            incoming?.transform = .identity
            incoming?.alpha = 1
        } completion: { [weak self] _ in
            guard let self, self.channelTransitionOverlay === overlay else { return }
            self.stopChannelTransition()
            self.saveChannelReadingPosition()
            UIAccessibility.post(notification: .screenChanged, argument: self.nameLabel)
        }
    }

    func stopChannelTransition() {
        channelTransitionOverlay?.removeFromSuperview()
        channelTransitionOverlay = nil
        channelAvatarFlyer?.removeFromSuperview()
        channelAvatarFlyer = nil
        channelTransitioning = false
        avatar.alpha = 1
        table.alpha = 1
        table.isScrollEnabled = true
        nextChannelIndicator.reset()
    }
}

// MARK: - Script

enum MTChatScript {
    static func sections(for chat: MTChat) -> [(title: String, messages: [MTMessage])] {
        if chat.kind == .channel { return MTData.channelSections(for: chat) }
        if chat.id == MTChat.fluidReactionsDemo.id {
            return [("Today", [
                MTMessage(kind: .text("Double-tap a message and the pink stream will flow around the bubbles and form a ❤️."),
                          outgoing: false, time: "12:00"),
                MTMessage(kind: .text("Hold a message and choose 🔥 or 👍 to mix the colors."),
                          outgoing: true, time: "12:01"),
                MTMessage(kind: .text("Swipe through the paint. Messages act as obstacles for the fluid 💧"),
                          outgoing: false, time: "12:02"),
            ])]
        }
        let days = ["October 18", "October 20", "Yesterday", "Today"]
        let lines: [[(String, Bool)]] = [
            [("Hey! Have you seen Telegram’s new design?", false), ("Yes, the glass tab bar looks amazing", true),
             ("And the drop that flows between tabs 😍", false), ("I want that in our demo", true),
             ("📌 Chat rules: no spam", false), ("Let’s build a mini-Telegram", false),
             ("Okay, I’ll start with stories in the nav bar", true), ("👍", false)],
            [("How’s it going?", false), ("Stories already flow out when pulled", true),
             ("Link to the Figma designs", false), ("Send me a video!", false), ("Tonight", true),
             ("Add chat swipes too, by the way", false), ("Already on the list", true),
             ("And make deletion dissolve into dust ✨", false), ("Will do", true)],
            [("Friday call at 11:00", false), ("I remember", true), ("Can you show the locked voice recording?", false),
             ("Yes, drag the mic up to lock the recording", true), ("Swipe left to cancel and discard", true),
             ("Awesome 🔥", false), ("Also, pinch to change the media grid", true), ("Like in the iOS Photos app?", false),
             ("Yes, 3 → 5 columns, with flowing cells", true)],
            [("Release 2.0 — November 1 🚀", false), ("Spoiler: ||the release will have a fluid tab bar 🤫||", false),
             ("Will we make it?", false), ("We should 😅", true),
             (chat.message.isEmpty ? "Message me when it’s ready" : chat.message, false)],
        ]
        var pin = 0
        var result: [(String, [MTMessage])] = []
        for (day, script) in zip(days, lines) {
            var messages: [MTMessage] = []
            for (index, line) in script.enumerated() {
                let time = String(format: "%02d:%02d", 10 + index, (index * 7) % 60)
                var message = MTMessage(kind: .text(line.0), outgoing: line.1, time: time)
                if pin < MTData.pinnedMessages.count, line.0 == MTData.pinnedMessages[pin] {
                    message.pinned = pin
                    pin += 1
                }
                messages.append(message)
            }
            if day == "October 20" {
                messages.insert(MTMessage(kind: .photos([.sunset, .ocean, .city]), outgoing: false, time: "12:30"), at: 4)
            }
            if day == "Yesterday" {
                messages.insert(MTMessage(kind: .voice(9), outgoing: true, time: "14:02"), at: 5)
            }
            result.append((day, messages))
        }
        return result
    }
}

// MARK: - Voice recorder

/// Recording on a liquid blob under the finger. The blob breathes with the voice and throws off
/// lumps; sliding up to the lock pins the recording (the button turns into send), sliding left
/// past the hint cancels it and the mic drops into a bin.
final class MTVoiceRecorder: UIView {
    var onSend: ((TimeInterval, Bool) -> Void)?
    var onFinish: (() -> Void)?

    private let canvas = LiquidCanvasView()
    private let buttonCenter: CGPoint
    private let video: Bool
    private let mic = UIImageView()
    private let sendButton = UIButton(type: .system)
    private let lockPill = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
    private let lockIcon = UIImageView()
    private let lockArrow = UIImageView()
    private let panel = UIView()
    private let dot = UIView()
    private let timeLabel = MTViews.label(size: 15, weight: .medium)
    private let slideLabel = MTViews.label("‹ Swipe left to cancel", size: 15, color: MTPalette.secondary)
    private let cancelButton = UIButton(type: .system)

    private var speech = SpeechSimulator(energy: 0.9)
    private var scale = Spring1D(0, stiffness: 14, dampingRatio: 0.6)
    private var level = Spring1D(0, stiffness: 18, dampingRatio: 0.7)
    private var follow = CGPoint.zero
    private var finger = CGPoint.zero
    private var lockProgress: CGFloat = 0
    private var locked = false
    private var finished = false
    private var elapsed: TimeInterval = 0
    private var phase: CGFloat = 0

    init(in host: UIView, buttonCenter: CGPoint, bar: CGRect, video: Bool) {
        self.buttonCenter = buttonCenter
        self.video = video
        super.init(frame: host.bounds)
        host.addSubview(self)

        panel.frame = CGRect(x: 0, y: bar.minY, width: bar.width, height: 52)
        addSubview(panel)
        dot.backgroundColor = MTPalette.red
        dot.layer.cornerRadius = 5
        dot.frame = CGRect(x: 18, y: 21, width: 10, height: 10)
        panel.addSubview(dot)
        let blink = CABasicAnimation(keyPath: "opacity")
        blink.fromValue = 1
        blink.toValue = 0.15
        blink.duration = 0.55
        blink.autoreverses = true
        blink.repeatCount = .infinity
        dot.layer.add(blink, forKey: "blink")
        timeLabel.frame = CGRect(x: 36, y: 0, width: 80, height: 52)
        panel.addSubview(timeLabel)
        slideLabel.textAlignment = .center
        slideLabel.frame = CGRect(x: 110, y: 0, width: bar.width - 220, height: 52)
        panel.addSubview(slideLabel)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        cancelButton.tintColor = MTPalette.accent
        cancelButton.frame = slideLabel.frame
        cancelButton.alpha = 0
        cancelButton.addAction(UIAction { [weak self] _ in self?.cancel() }, for: .touchUpInside)
        panel.addSubview(cancelButton)
        panel.alpha = 0
        panel.transform = CGAffineTransform(translationX: 40, y: 0)

        canvas.frame = bounds
        canvas.liquidColor = video ? MTPalette.red : MTPalette.accent
        canvas.gloss = 0.55
        canvas.rimWidth = 9
        canvas.onUpdate = { [weak self] dt in self?.step(dt) }
        addSubview(canvas)

        lockPill.layer.cornerRadius = 20
        lockPill.clipsToBounds = true
        lockPill.frame = CGRect(x: buttonCenter.x - 20, y: buttonCenter.y - 170, width: 40, height: 84)
        lockIcon.image = UIImage(systemName: "lock.open", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold))
        lockIcon.tintColor = MTPalette.secondary
        lockIcon.contentMode = .center
        lockPill.contentView.addSubview(lockIcon)
        lockArrow.image = UIImage(systemName: "chevron.up", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold))
        lockArrow.tintColor = MTPalette.secondary
        lockArrow.contentMode = .center
        lockPill.contentView.addSubview(lockArrow)
        let bob = CABasicAnimation(keyPath: "transform.translation.y")
        bob.fromValue = 3
        bob.toValue = -3
        bob.duration = 0.6
        bob.autoreverses = true
        bob.repeatCount = .infinity
        lockArrow.layer.add(bob, forKey: "bob")
        lockPill.alpha = 0
        lockPill.transform = CGAffineTransform(translationX: 0, y: 40)
        addSubview(lockPill)

        mic.image = UIImage(systemName: video ? "video.fill" : "mic.fill",
                            withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .semibold))
        mic.tintColor = .white
        mic.contentMode = .center
        mic.frame = CGRect(x: 0, y: 0, width: 60, height: 60)
        mic.center = buttonCenter
        addSubview(mic)
        sendButton.frame = CGRect(x: buttonCenter.x - 40, y: buttonCenter.y - 40, width: 80, height: 80)
        sendButton.isHidden = true
        sendButton.addAction(UIAction { [weak self] _ in self?.send() }, for: .touchUpInside)
        addSubview(sendButton)

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
            self.panel.alpha = 1
            self.panel.transform = .identity
            self.lockPill.alpha = 1
            self.lockPill.transform = .identity
        }
        layoutLock()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard locked, !finished else { return nil }
        let hit = super.hitTest(point, with: event)
        return hit === sendButton || hit === cancelButton || cancelButton.frame.contains(convert(point, to: panel)) ? hit : nil
    }

    private func layoutLock() {
        let height = 84 - 44 * lockProgress
        lockPill.bounds.size.height = height
        lockPill.center = CGPoint(x: buttonCenter.x, y: buttonCenter.y - 128 - 30 * lockProgress + (84 - height) / 2)
        lockIcon.frame = CGRect(x: 0, y: 0, width: 40, height: 40)
        lockArrow.frame = CGRect(x: 0, y: 40, width: 40, height: 36)
        lockArrow.alpha = 1 - lockProgress * 1.5
    }

    // MARK: Gesture

    func drag(_ translation: CGPoint) {
        guard !locked, !finished else { return }
        // One direction at a time, like Telegram.
        let horizontal = abs(translation.x) > abs(translation.y)
        finger = horizontal ? CGPoint(x: min(translation.x, 0), y: 0) : CGPoint(x: 0, y: min(translation.y, 0))
        lockProgress = min(max(-finger.y / 90, 0), 1)
        layoutLock()
        let cancelProgress = min(max(-finger.x / 130, 0), 1)
        slideLabel.transform = CGAffineTransform(translationX: finger.x * 0.6, y: 0)
        slideLabel.alpha = 1 - cancelProgress
        if lockProgress >= 1 { lock() }
        if cancelProgress >= 1 { cancel() }
    }

    func release() {
        guard !locked, !finished else { return }
        if elapsed < 0.6 {
            cancel(silent: true)
            if let host = superview {
                MTViews.toast("Hold to record", symbol: video ? "video.fill" : "mic.fill", in: host,
                              top: host.safeAreaInsets.top + 110)
            }
            return
        }
        send()
    }

    private func lock() {
        locked = true
        finger = .zero
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        lockIcon.setContactSymbol(UIImage(systemName: "lock.fill")!, transition: .replace)
        lockIcon.tintColor = MTPalette.accent
        mic.setContactSymbol(UIImage(systemName: "arrow.up", withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .bold))!,
                           transition: .replace)
        sendButton.isHidden = false
        UIView.animate(withDuration: 0.3) {
            self.slideLabel.alpha = 0
            self.cancelButton.alpha = 1
        }
    }

    private func send() {
        guard !finished else { return }
        finished = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onSend?(max(elapsed, 1), video)
        finish()
    }

    func cancel(silent: Bool = false) {
        guard !finished else { return }
        finished = true
        if !silent { binAnimation() }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        finish(delay: silent ? 0 : 0.9)
    }

    private func finish(delay: TimeInterval = 0) {
        isUserInteractionEnabled = false
        UIView.animate(withDuration: 0.25) {
            self.lockPill.alpha = 0
            self.lockPill.transform = CGAffineTransform(translationX: 0, y: 30)
            self.mic.alpha = 0
        }
        UIView.animate(withDuration: 0.25, delay: delay, animations: {
            self.panel.alpha = 0
        }, completion: { _ in
            self.onFinish?()
            self.removeFromSuperview()
        })
    }

    /// The mic jumps out of the panel and drops into a bin that then closes and sinks.
    private func binAnimation() {
        dot.layer.removeAllAnimations()
        dot.isHidden = true
        timeLabel.alpha = 0
        let bin = UIImageView(image: UIImage(systemName: "trash", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)))
        bin.tintColor = MTPalette.red
        bin.contentMode = .center
        bin.frame = CGRect(x: 6, y: 52, width: 36, height: 36)
        bin.alpha = 0
        panel.addSubview(bin)
        let flying = UIImageView(image: UIImage(systemName: "mic.fill"))
        flying.tintColor = MTPalette.red
        flying.frame = CGRect(x: 14, y: 16, width: 18, height: 20)
        panel.addSubview(flying)
        UIView.animate(withDuration: 0.25, animations: {
            bin.alpha = 1
            bin.frame.origin.y = 8
        })
        UIView.animateKeyframes(withDuration: 0.6, delay: 0, options: [], animations: {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.45) {
                flying.center.y -= 60
                flying.transform = CGAffineTransform(rotationAngle: .pi)
            }
            UIView.addKeyframe(withRelativeStartTime: 0.45, relativeDuration: 0.55) {
                flying.center = CGPoint(x: bin.center.x, y: 26)
                flying.transform = CGAffineTransform(rotationAngle: .pi * 2).scaledBy(x: 0.3, y: 0.3)
                flying.alpha = 0.2
            }
        }, completion: { _ in
            flying.removeFromSuperview()
            let wobble = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            wobble.values = [0, -0.25, 0.2, -0.1, 0]
            wobble.duration = 0.35
            bin.layer.add(wobble, forKey: "wobble")
            UIView.animate(withDuration: 0.25, delay: 0.3) { bin.frame.origin.y = 52 }
        })
    }

    // MARK: Liquid

    private func step(_ dt: CFTimeInterval) {
        if !finished {
            elapsed += dt
            speech.step(dt)
        }
        let seconds = Int(elapsed)
        timeLabel.text = String(format: "%d:%02d,%d", seconds / 60, seconds % 60, Int(elapsed * 10) % 10)
        scale.step(toward: finished ? 0 : 1, deltaTime: dt)
        level.step(toward: finished ? 0 : speech.level, deltaTime: dt)
        follow.x += (finger.x * 0.3 - follow.x) * min(1, CGFloat(dt) * 14)
        follow.y += (finger.y * 0.3 - follow.y) * min(1, CGFloat(dt) * 14)
        phase += CGFloat(dt) * (1.2 + level.value * 3)

        let s = max(scale.value, 0)
        let center = CGPoint(x: buttonCenter.x + follow.x, y: buttonCenter.y + follow.y)
        let radius = (40 + level.value * 14) * s
        var shapes: [IslandFluidShape] = [.circle(center: center, radius: radius, blend: 0)]
        // Lumps riding the surface swell with the voice.
        for index in 0..<4 {
            let angle = phase * (index % 2 == 0 ? 1 : -0.7) + CGFloat(index) * .pi / 2
            let distance = radius * 0.78 + level.value * 16 * s
            let point = CGPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance)
            shapes.append(.circle(center: point, radius: (9 + level.value * 9) * s, blend: 14))
        }
        canvas.shapes = shapes
        // A neck back to the button while the blob is pulled away.
        let pulled = hypot(follow.x, follow.y)
        canvas.spikes = pulled > 4 ? [IslandFluidSpike(base: buttonCenter, tip: center, baseRadius: 16 * s, tipRadius: radius * 0.6,
                                                       blend: 10)] : []
        mic.center = center
        let iconScale = 0.8 + 0.2 * min(s, 1.2)
        mic.transform = CGAffineTransform(scaleX: iconScale, y: iconScale)
        if finished, scale.value < 0.02 {
            canvas.settle()
        }
    }
}
