//
//  MTChatListPage.swift
//  controller
//
//  The Chats tab:
//  • stories live in the title as a stack of small avatars; pulling the list down pours them out
//    into a row (each avatar drop tears off the stack on its own spring), scrolling up merges them
//    back. The rings are one liquid canvas, so while they are close they flow into each other;
//  • folder tabs with a liquid indicator and unread counters, switched by tap or an edge swipe;
//  • row swipes (read / pin to the right, mute / delete / archive to the left) with a full swipe
//    that stretches the edge button over the whole row;
//  • a long press peeks into the chat over a blur, with a menu;
//  • chats come alive: "is typing…" in the row, messages arrive and move the chat up, ✓ becomes ✓✓.
//

import UIKit

final class MTChatListPage: MTPage {
    var onUnreadChanged: ((Int) -> Void)?

    private var chats: [MTChat] = []
    private weak var storageSession: MTAccountSession?
    private let storageOrigin = UUID()
    private var applyingStoredChange = false
    private var folder: MTFolder = .all
    private var visible: [MTChat] = []
    private var typing: Set<Int> = []

    private let table = UITableView(frame: .zero, style: .plain)
    private let header = MTStoriesHeader()
    private let folders = LiquidSelector(titles: MTFolder.allCases.map(\.title), style: .segments, liquid: MTPalette.accent,
                                         selectedTint: .white, normalTint: MTPalette.secondary)
    private var folderBadges: [UILabel] = []
    private weak var openCell: MTChatCell?
    private var storiesExpanded = false

    override func viewDidLoad() {
        super.viewDidLoad()
        table.accessibilityIdentifier = "contact.chats"
        table.backgroundColor = MTPalette.background
        table.separatorStyle = .none
        table.rowHeight = 76
        table.contentInsetAdjustmentBehavior = .never
        table.register(MTChatCell.self, forCellReuseIdentifier: "chat")
        table.dataSource = self
        table.delegate = self
        view.addSubview(table)

        header.onSettings = { [weak self] in self?.home?.openSettings() }
        header.onLock = { [weak self] in self?.home?.lock() }
        header.onCompose = { [weak self] in
            guard let self else { return }
            MTViews.toast("New Message", symbol: "square.and.pencil", in: self.view)
        }
        header.onStackTap = { [weak self] in self?.expandStories() }
        header.onOpenStory = { [weak self] index in self?.openStory(index) }
        view.addSubview(header)

        folders.addTarget(self, action: #selector(folderChanged), for: .valueChanged)
        header.addSubview(folders)
        for _ in MTFolder.allCases {
            let badge = UILabel()
            badge.font = .systemFont(ofSize: 11, weight: .bold)
            badge.textColor = .white
            badge.textAlignment = .center
            badge.backgroundColor = MTPalette.muted
            badge.layer.cornerRadius = 8
            badge.clipsToBounds = true
            badge.isUserInteractionEnabled = false
            header.addSubview(badge)
            folderBadges.append(badge)
        }
        for edge in [UIRectEdge.left, .right] {
            let swipe = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(edgeSwiped(_:)))
            swipe.edges = edge
            view.addGestureRecognizer(swipe)
        }
        for direction in [UISwipeGestureRecognizer.Direction.left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(foldersSwiped(_:)))
            swipe.direction = direction
            folders.addGestureRecognizer(swipe)
        }
        refilter()
        updateFolderBadges()
    }

    private var safeTop: CGFloat { view.safeAreaInsets.top }
    private var baseInset: CGFloat { safeTop + MTStoriesHeader.titleHeight + MTStoriesHeader.foldersHeight }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        table.frame = view.bounds
        let top = baseInset + (storiesExpanded ? MTStoriesHeader.storiesHeight : 0)
        if table.contentInset.top != top {
            table.contentInset.top = top
            table.verticalScrollIndicatorInsets.top = top
            table.contentOffset.y = -top
        }
        table.contentInset.bottom = home?.bottomInset ?? 0
        header.safeTop = safeTop
        layoutHeader()
    }

    private func layoutHeader() {
        // How far the list is pulled below its collapsed resting place.
        let pulled = -(table.contentOffset.y + baseInset)
        let storyHeight = min(max(pulled, 0), MTStoriesHeader.storiesHeight)
        header.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: baseInset + storyHeight)
        header.setPull(pulled / MTStoriesHeader.storiesHeight)
        let foldersY = header.bounds.height - MTStoriesHeader.foldersHeight + 4
        folders.frame = CGRect(x: 12, y: foldersY, width: view.bounds.width - 24, height: 32)
        let slot = folders.bounds.width / CGFloat(MTFolder.allCases.count)
        for (index, badge) in folderBadges.enumerated() {
            let title = MTFolder(rawValue: index)!.title as NSString
            let textWidth = title.size(withAttributes: [.font: UIFont.systemFont(ofSize: 15, weight: .semibold)]).width
            let width = max(16, badge.intrinsicContentSize.width + 8)
            badge.frame = CGRect(x: 12 + slot * (CGFloat(index) + 0.5) + textWidth / 2 + 3, y: foldersY + 1,
                                 width: width, height: 16)
        }
    }

    // MARK: Data

    /// Actual account order, independent of the active folder. Groups are not channel destinations.
    var channels: [MTChat] { chats.filter { $0.kind == .channel } }

    var unreadTotal: Int { chats.filter { !$0.muted }.reduce(0) { $0 + $1.unread } }

    func chat(with person: ChannelPerson) -> MTChat? {
        chats.first { $0.person.name == person.name }
    }

    private func refilter() {
        visible = chats.filter { $0.belongs(to: folder) }
    }

    private func updateFolderBadges() {
        for (index, badge) in folderBadges.enumerated() {
            let count = chats.filter { $0.belongs(to: MTFolder(rawValue: index)!) && $0.unread > 0 }.count
            let text = count > 0 ? "\(count)" : ""
            if badge.text != text, !text.isEmpty, badge.text?.isEmpty == false {
                MTViews.pop(badge, scale: 1.3)
            }
            badge.text = text
            badge.isHidden = text.isEmpty
            badge.backgroundColor = index == folder.rawValue ? MTPalette.accent : MTPalette.muted
        }
        layoutHeader()
        onUnreadChanged?(unreadTotal)
    }

    private func update(_ id: Int, _ change: (inout MTChat) -> Void) {
        guard let index = chats.firstIndex(where: { $0.id == id }) else { return }
        change(&chats[index])
        if let row = visible.firstIndex(where: { $0.id == id }) {
            visible[row] = chats[index]
            (table.cellForRow(at: IndexPath(row: row, section: 0)) as? MTChatCell)?.configure(chats[index], typing: typing.contains(id),
                                                                                              animated: true)
        }
        updateFolderBadges()
    }

    func markRead(_ id: Int) {
        storageSession?.markRead(chatID: id)
    }

    /// Another account: the rows leave and the new ones come in one after another.
    func load(account: Int, animated: Bool) {
        storageSession?.onChatsChanged = nil
        storageSession = nil
        chats = []
        typing = []
        closeOpenCell()
        refilter()
        table.reloadData()
        header.setAccount(account)
        updateFolderBadges()
    }

    func bind(session: MTAccountSession) {
        storageSession?.onChatsChanged = nil
        storageSession = session
        session.onChatsChanged = { [weak self, weak session] origin in
            guard let self, let session, self.storageSession === session, origin != self.storageOrigin else { return }
            self.applyStoredChats(session.chats)
        }
        applyStoredChats(session.chats)
    }

    private func applyStoredChats(_ values: [MTChat]) {
        guard isViewLoaded else { chats = values; return }
        let previous = visible.map(\.id)
        chats = values
        refilter()
        if previous == visible.map(\.id) {
            for path in table.indexPathsForVisibleRows ?? [] where visible.indices.contains(path.row) {
                (table.cellForRow(at: path) as? MTChatCell)?.configure(visible[path.row], typing: false, animated: true)
            }
        } else { table.reloadData() }
        updateFolderBadges()
    }

    func updateLock() {
        header.setLock(home?.passcodeEnabled == true)
    }

    // MARK: Folders

    @objc private func folderChanged() {
        switchFolder(to: MTFolder(rawValue: folders.selectedIndex)!)
    }

    @objc private func foldersSwiped(_ gesture: UISwipeGestureRecognizer) {
        let next = folder.rawValue + (gesture.direction == .left ? 1 : -1)
        guard let target = MTFolder(rawValue: next) else { return }
        folders.select(next)
        UISelectionFeedbackGenerator().selectionChanged()
        switchFolder(to: target)
    }

    @objc private func edgeSwiped(_ gesture: UIScreenEdgePanGestureRecognizer) {
        let dx = gesture.translation(in: view).x
        switch gesture.state {
        case .changed:
            table.transform = CGAffineTransform(translationX: dx * 0.5, y: 0)
            table.alpha = 1 - min(abs(dx) / 400, 0.5)
        case .ended, .cancelled:
            let next = folder.rawValue + (dx < 0 ? 1 : -1)
            if abs(dx) > 70, let target = MTFolder(rawValue: next) {
                folders.select(next)
                UISelectionFeedbackGenerator().selectionChanged()
                switchFolder(to: target)
            } else {
                UIView.animate(withDuration: 0.3) {
                    self.table.transform = .identity
                    self.table.alpha = 1
                }
            }
        default:
            break
        }
    }

    private func switchFolder(to target: MTFolder) {
        guard target != folder else { return }
        let direction: CGFloat = target.rawValue > folder.rawValue ? -1 : 1
        folder = target
        closeOpenCell()
        UIView.animate(withDuration: 0.14, animations: {
            self.table.transform = CGAffineTransform(translationX: direction * 60, y: 0)
            self.table.alpha = 0
        }, completion: { _ in
            self.refilter()
            self.table.reloadData()
            self.table.transform = CGAffineTransform(translationX: -direction * 60, y: 0)
            UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
                self.table.transform = .identity
                self.table.alpha = 1
            }
        })
        updateFolderBadges()
    }

    // MARK: Stories

    private func expandStories() {
        guard !storiesExpanded else { return }
        storiesExpanded = true
        let top = baseInset + MTStoriesHeader.storiesHeight
        table.contentInset.top = top
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        UIView.animate(withDuration: 0.6, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
            self.table.contentOffset.y = -top
            self.layoutHeader()
        }
    }

    private func openStory(_ index: Int) {
        guard let host = home?.root?.view else { return }
        let viewer = StoryViewer(in: host, users: MTData.storyUsers, start: index) { [weak self, weak host] user in
            guard let self, let host else { return .zero }
            return self.header.avatarFrame(user, in: host)
        }
        viewer.onSeen = { [weak self] user in self?.header.markSeen(user) }
    }

    // MARK: Row actions

    private func perform(_ action: MTChatCell.Action, on id: Int, cell: MTChatCell?) {
        guard let chat = chats.first(where: { $0.id == id }) else { return }
        if !applyingStoredChange {
            storageSession?.changeChat(chat, action: action, origin: storageOrigin) { [weak self, weak cell] in
                guard let self else { return }
                self.applyingStoredChange = true
                self.perform(action, on: id, cell: cell)
                self.applyingStoredChange = false
            }
            return
        }
        switch action {
        case .read:
            update(id) { $0.unread = $0.unread > 0 ? 0 : 1 }
            cell?.close()
        case .pin:
            update(id) { $0.pinned.toggle() }
            cell?.close()
            if let from = chats.firstIndex(where: { $0.id == id }) {
                let moved = chats.remove(at: from)
                let to = moved.pinned ? 0 : (chats.firstIndex { !$0.pinned } ?? chats.count)
                chats.insert(moved, at: to)
                let oldVisible = visible
                refilter()
                if let oldRow = oldVisible.firstIndex(where: { $0.id == id }), let newRow = visible.firstIndex(where: { $0.id == id }) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        self.table.moveRow(at: IndexPath(row: oldRow, section: 0), to: IndexPath(row: newRow, section: 0))
                    }
                }
            }
        case .mute:
            update(id) { $0.muted.toggle() }
            cell?.close()
            MTViews.toast(chat.muted ? "Notifications enabled" : "Notifications disabled",
                          symbol: chat.muted ? "bell.fill" : "bell.slash.fill", in: view)
        case .delete:
            if let cell {
                cell.dissolve { self.remove(id) }
            } else {
                remove(id)
            }
        case .archive:
            remove(id, animation: .left)
            MTViews.toast("Chat archived", symbol: "archivebox.fill", in: view)
        }
    }

    private func remove(_ id: Int, animation: UITableView.RowAnimation = .fade) {
        guard let row = visible.firstIndex(where: { $0.id == id }) else { return }
        chats.removeAll { $0.id == id }
        typing.remove(id)
        refilter()
        table.deleteRows(at: [IndexPath(row: row, section: 0)], with: animation)
        updateFolderBadges()
    }

    private func closeOpenCell() {
        openCell?.close()
        openCell = nil
    }

    private func peek(_ cell: MTChatCell) {
        guard let indexPath = table.indexPath(for: cell), let root = home?.root?.view else { return }
        closeOpenCell()
        let chat = visible[indexPath.row]
        let peek = MTChatPeek(in: root, chat: chat, from: cell.convert(cell.bounds, to: root))
        peek.onOpen = { [weak self] in self?.home?.openChat(chat) }
        peek.onAction = { [weak self] action in
            guard let self else { return }
            let cell = self.visible.firstIndex { $0.id == chat.id }
                .flatMap { self.table.cellForRow(at: IndexPath(row: $0, section: 0)) as? MTChatCell }
            self.perform(action, on: chat.id, cell: cell)
        }
    }
}

extension MTChatListPage: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        visible.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "chat", for: indexPath) as! MTChatCell
        let chat = visible[indexPath.row]
        cell.configure(chat, typing: typing.contains(chat.id), animated: false)
        cell.onAction = { [weak self, weak cell] action in
            self?.perform(action, on: chat.id, cell: cell)
        }
        cell.onSwipeBegan = { [weak self, weak cell] in
            guard let self, let cell else { return }
            if self.openCell !== cell { self.openCell?.close() }
            self.openCell = cell
        }
        cell.onPeek = { [weak self, weak cell] in
            guard let self, let cell else { return }
            self.peek(cell)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if let openCell {
            openCell.close()
            self.openCell = nil
            return
        }
        home?.openChat(visible[indexPath.row])
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let pulled = -(scrollView.contentOffset.y + baseInset)
        // Scrolled past the stories row: fold it back into the title.
        if storiesExpanded, pulled <= 0 {
            storiesExpanded = false
            table.contentInset.top = baseInset
            table.verticalScrollIndicatorInsets.top = baseInset
        }
        layoutHeader()
        if scrollView.isDragging { closeOpenCell() }
    }

    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        let pulled = -(scrollView.contentOffset.y + baseInset)
        let full = MTStoriesHeader.storiesHeight
        if !storiesExpanded, pulled > full * 0.55 {
            storiesExpanded = true
            table.contentInset.top = baseInset + full
            targetContentOffset.pointee.y = -(baseInset + full)
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        } else if storiesExpanded {
            let targetPulled = -(targetContentOffset.pointee.y + baseInset)
            if targetPulled > 0, targetPulled < full {
                targetContentOffset.pointee.y = targetPulled > full * 0.5 && velocity.y <= 0 ? -(baseInset + full) : -baseInset
            }
        }
    }
}

// MARK: - Header with the stories

final class MTStoriesHeader: UIView {
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
            self.tintBorders()
    }

    static let titleHeight: CGFloat = 44
    static let foldersHeight: CGFloat = 42
    static let storiesHeight: CGFloat = 92

    var onSettings: (() -> Void)?
    var onLock: (() -> Void)?
    var onCompose: (() -> Void)?
    var onStackTap: (() -> Void)?
    var onOpenStory: ((Int) -> Void)?
    var safeTop: CGFloat = 0

    private let background = MTViews.barBackground()
    private let hairline = UIView()
    private let exitButton = MTViews.iconButton("gearshape", size: 19)
    private let composeButton = MTViews.iconButton("square.and.pencil", size: 19)
    private let lockButton = MTViews.iconButton("lock.open.fill", size: 13, tint: MTPalette.text)
    private let title = MTViews.label("Chats", size: 17, weight: .semibold)
    private let canvas = LiquidCanvasView()
    private var avatars: [UIImageView] = []
    private var names: [UILabel] = []
    private var springs: [Spring1D] = []
    private var seen: [Bool] = []
    private var pull: CGFloat = 0
    private var lockShown = false
    private let users = MTData.storyUsers
    private let stackCount = 3
    private let expandedSize: CGFloat = 46
    private let stackSize: CGFloat = 26

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(background)
        hairline.backgroundColor = MTPalette.separator
        addSubview(hairline)
        exitButton.accessibilityLabel = "Settings"
        composeButton.accessibilityLabel = "New Message"
        lockButton.accessibilityLabel = "Lock"
        exitButton.addAction(UIAction { [weak self] _ in self?.onSettings?() }, for: .touchUpInside)
        composeButton.addAction(UIAction { [weak self] _ in self?.onCompose?() }, for: .touchUpInside)
        lockButton.addAction(UIAction { [weak self] _ in self?.onLock?() }, for: .touchUpInside)
        lockButton.alpha = 0
        addSubview(exitButton)
        addSubview(composeButton)
        addSubview(lockButton)
        title.textAlignment = .left
        addSubview(title)

        canvas.liquidColor = MTPalette.storyRing
        canvas.gloss = 0.5
        canvas.rimWidth = 4
        canvas.onUpdate = { [weak self] dt in self?.step(dt) }
        addSubview(canvas)
        for (index, user) in users.enumerated() {
            let avatar = UIImageView(image: ChannelAvatar.image(for: user.person, size: expandedSize))
            avatar.clipsToBounds = true
            avatar.isUserInteractionEnabled = true
            avatar.tag = index
            avatar.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(avatarTapped(_:))))
            addSubview(avatar)
            avatars.append(avatar)
            let name = MTViews.label(index == 0 ? "You" : String(user.person.name.split(separator: " ")[0]),
                                     size: 10, color: MTPalette.text)
            name.textAlignment = .center
            addSubview(name)
            names.append(name)
            springs.append(Spring1D(0, stiffness: 16 - CGFloat(index) * 1.2, dampingRatio: 0.62))
            seen.append(false)
        }

        tintBorders()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func tintBorders() {
        let color = MTPalette.background.resolvedColor(with: traitCollection).cgColor
        avatars.forEach { $0.layer.borderColor = color }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        background.frame = bounds
        hairline.frame = CGRect(x: 0, y: bounds.height - 0.5, width: bounds.width, height: 0.5)
        exitButton.frame = CGRect(x: 4, y: safeTop, width: 44, height: Self.titleHeight)
        composeButton.frame = CGRect(x: bounds.width - 48, y: safeTop, width: 44, height: Self.titleHeight)
        canvas.frame = CGRect(x: 0, y: 0, width: bounds.width, height: safeTop + Self.titleHeight + Self.storiesHeight + 20)
        canvas.isPaused = false
        place()
    }

    /// `amount`: 0 = stories folded into the title, 1 = poured out into the row.
    func setPull(_ amount: CGFloat) {
        pull = amount
        canvas.isPaused = false
        setNeedsLayout()
    }

    private func stackCenter(_ index: Int, titleWidth: CGFloat) -> CGPoint {
        let stackWidth = stackSize + CGFloat(stackCount - 1) * 15
        let group = stackWidth + 8 + titleWidth
        let start = (bounds.width - group) / 2
        let slot = CGFloat(min(index, stackCount - 1))
        return CGPoint(x: start + stackSize / 2 + slot * 15, y: safeTop + Self.titleHeight / 2)
    }

    private func rowCenter(_ index: Int) -> CGPoint {
        let spacing = (bounds.width - 16) / CGFloat(users.count)
        return CGPoint(x: 8 + spacing * (CGFloat(index) + 0.5), y: safeTop + Self.titleHeight + 10 + expandedSize / 2)
    }

    /// Lays out the title and the avatars from the springs.
    private func place() {
        let titleWidth = title.intrinsicContentSize.width
        let open = springs.map { min(max($0.value, 0), 1.15) }
        let titleOpen = min(max(pull, 0), 1)
        let stackStart = stackCenter(0, titleWidth: titleWidth).x - stackSize / 2
        let collapsedTitleX = stackStart + stackSize + CGFloat(stackCount - 1) * 15 + 8
        let titleX = collapsedTitleX + ((bounds.width - titleWidth) / 2 - collapsedTitleX) * titleOpen
        title.frame = CGRect(x: titleX, y: safeTop, width: titleWidth, height: Self.titleHeight)
        lockButton.frame = CGRect(x: title.frame.maxX + 2, y: safeTop, width: 24, height: Self.titleHeight)

        var shapes: [IslandFluidShape] = []
        for index in avatars.indices.reversed() {
            let t = open[index]
            let start = stackCenter(index, titleWidth: titleWidth)
            let end = rowCenter(index)
            // Drops sag a little on their way down, like they are poured.
            var center = CGPoint.lerp(start, end, t)
            center.y += sin(min(t, 1) * .pi) * 10
            let size = stackSize + (expandedSize - stackSize) * min(t, 1.05)
            let avatar = avatars[index]
            avatar.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            avatar.center = center
            avatar.layer.cornerRadius = size / 2
            avatar.layer.borderWidth = 1.5 + 1.5 * min(t, 1)
            let hiddenInStack = index >= stackCount
            avatar.alpha = hiddenInStack ? islandSmoothstep(0.05, 0.4, t) : 1
            avatar.isUserInteractionEnabled = t > 0.9 || (t < 0.1 && index < stackCount)
            names[index].frame = CGRect(x: end.x - 30, y: end.y + expandedSize / 2 + 6, width: 60, height: 13)
            names[index].alpha = islandSmoothstep(0.7, 1, t)
            guard !seen[index] || t < 0.9 else { continue }
            let ring = size / 2 + 2 + 1.5 * min(t, 1)
            // Close together they flow into one blob; apart, each is a ring of its own.
            shapes.append(.circle(center: center, radius: ring * avatar.alpha, blend: 14 * (1 - min(t, 1)) + 1))
        }
        canvas.shapes = shapes
    }

    private func step(_ dt: CFTimeInterval) {
        var settled = true
        for index in springs.indices {
            // Later avatars wait a little before they tear off the stack.
            let delay = CGFloat(index) * 0.06
            let target = min(max((pull - delay) / (1 - 0.36), 0), 1)
            springs[index].step(toward: target, deltaTime: dt)
            if !springs[index].isSettled(at: target, tolerance: 0.002) { settled = false }
        }
        place()
        if settled {
            canvas.renderFrame()
            canvas.isPaused = true
        }
    }

    func avatarFrame(_ index: Int, in view: UIView) -> CGRect {
        avatars[index].convert(avatars[index].bounds, to: view)
    }

    func markSeen(_ index: Int) {
        seen[index] = true
        canvas.isPaused = false
    }

    func setAccount(_ index: Int) {
        UIView.transition(with: title, duration: 0.3, options: .transitionCrossDissolve) {
            self.title.text = index == 0 ? "Chats" : "Chats · \(MTData.accounts[index].person.name.split(separator: " ")[0])"
        }
        setNeedsLayout()
    }

    func setLock(_ shown: Bool) {
        lockShown = shown
        UIView.animate(withDuration: 0.3) { self.lockButton.alpha = shown ? 1 : 0 }
        if shown { MTViews.pop(lockButton, scale: 0.4) }
    }

    @objc private func avatarTapped(_ gesture: UITapGestureRecognizer) {
        guard let index = gesture.view?.tag else { return }
        if pull < 0.5 {
            onStackTap?()
            return
        }
        MTViews.pop(avatars[index], scale: 0.9)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onOpenStory?(index)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // The collapsed stack is small: accept taps around it.
        if pull < 0.1, point.y > safeTop, point.y < safeTop + Self.titleHeight {
            let stack = CGRect(x: stackCenter(0, titleWidth: title.intrinsicContentSize.width).x - 24, y: safeTop,
                               width: 90, height: Self.titleHeight)
            if stack.contains(point) { return avatars[0] }
        }
        return super.hitTest(point, with: event)
    }
}

// MARK: - Chat row

final class MTChatCell: UITableViewCell {
    enum Action { case read, pin, mute, delete, archive }

    var onAction: ((Action) -> Void)?
    var onSwipeBegan: (() -> Void)?
    var onPeek: (() -> Void)?

    let slider = UIView()
    private let avatar = MTAvatarView()
    private let name = MTViews.label(size: 16, weight: .semibold)
    private let mutedIcon = UIImageView(image: UIImage(systemName: "speaker.slash.fill",
                                                       withConfiguration: UIImage.SymbolConfiguration(pointSize: 11)))
    private let kindIcon = UIImageView()
    private let message = MTViews.label(size: 15, color: MTPalette.secondary)
    private let typingLabel = MTViews.label("typing", size: 15, color: MTPalette.accent)
    private let dots = MTTypingDots()
    private let time = MTViews.label(size: 14, color: MTPalette.secondary)
    private let checks = MTChecksView()
    private let badge = MTBadge()
    private let pinIcon = UIImageView(image: UIImage(systemName: "pin.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12)))
    private let separator = UIView()

    private var leftButtons: [MTSwipeButton] = []
    private var rightButtons: [MTSwipeButton] = []
    private var offset: CGFloat = 0
    private var startOffset: CGFloat = 0
    private var full = false
    private var isTyping = false
    private let buttonWidth: CGFloat = 76

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.clipsToBounds = true
        slider.backgroundColor = MTPalette.background
        for view in [avatar, name, mutedIcon, kindIcon, message, typingLabel, dots, time, checks, badge, pinIcon, separator] {
            slider.addSubview(view)
        }
        mutedIcon.tintColor = MTPalette.secondary
        kindIcon.tintColor = MTPalette.text
        pinIcon.tintColor = MTPalette.muted
        separator.backgroundColor = MTPalette.separator
        message.numberOfLines = 2
        checks.tint = MTPalette.accent
        typingLabel.alpha = 0
        dots.alpha = 0

        leftButtons = [MTSwipeButton(title: "Read", symbol: "checkmark.message.fill", color: MTPalette.accent),
                       MTSwipeButton(title: "Pin", symbol: "pin.fill", color: MTPalette.online)]
        rightButtons = [MTSwipeButton(title: "Mute", symbol: "bell.slash.fill", color: MTPalette.orange),
                        MTSwipeButton(title: "Delete", symbol: "trash.fill", color: MTPalette.red),
                        MTSwipeButton(title: "Archive", symbol: "archivebox.fill", color: UIColor(white: 0.6, alpha: 1))]
        let leftActions: [Action] = [.read, .pin], rightActions: [Action] = [.mute, .delete, .archive]
        for (button, action) in zip(leftButtons + rightButtons, leftActions + rightActions) {
            button.addAction(UIAction { [weak self] _ in self?.onAction?(action) }, for: .touchUpInside)
            contentView.addSubview(button)
        }
        contentView.addSubview(slider)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.delegate = self
        slider.addGestureRecognizer(pan)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        hold.minimumPressDuration = 0.4
        slider.addGestureRecognizer(hold)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        offset = 0
        full = false
        slider.alpha = 1
        alpha = 1
        transform = .identity
        setNeedsLayout()
    }

    func configure(_ chat: MTChat, typing: Bool, animated: Bool) {
        accessibilityIdentifier = "contact.chat.\(chat.id)"
        avatar.set(chat.person, size: 58)
        avatar.online = chat.online && chat.kind == .person
        name.text = chat.person.name
        mutedIcon.isHidden = !chat.muted
        switch chat.kind {
        case .group: kindIcon.image = UIImage(systemName: "person.2.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11))
        case .channel: kindIcon.image = UIImage(systemName: "megaphone.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11))
        case .bot: kindIcon.image = UIImage(systemName: "cpu", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11))
        case .person: kindIcon.image = nil
        }
        if animated, message.text != chat.message, !message.text.isNilOrEmpty {
            let fade = CATransition()
            fade.type = .push
            fade.subtype = .fromTop
            fade.duration = 0.3
            message.layer.add(fade, forKey: "text")
        }
        message.text = chat.message
        time.text = chat.time
        checks.isHidden = chat.outgoingRead == nil
        checks.set(read: chat.outgoingRead == true, animated: animated)
        badge.muted = chat.muted
        badge.set(chat.unread, animated: animated)
        pinIcon.isHidden = !(chat.pinned && chat.unread == 0)
        leftButtons[0].set(title: chat.unread > 0 ? "Read" : "Unread",
                           symbol: chat.unread > 0 ? "checkmark.message.fill" : "message.badge.fill")
        leftButtons[1].set(title: chat.pinned ? "Unpin" : "Pin", symbol: chat.pinned ? "pin.slash.fill" : "pin.fill")
        rightButtons[0].set(title: chat.muted ? "Unmute" : "Mute", symbol: chat.muted ? "bell.fill" : "bell.slash.fill")
        setTyping(typing, animated: animated)
        setNeedsLayout()
    }

    private func setTyping(_ typing: Bool, animated: Bool) {
        guard typing != isTyping || !animated else { return }
        isTyping = typing
        let change = {
            self.message.alpha = typing ? 0 : 1
            self.typingLabel.alpha = typing ? 1 : 0
            self.dots.alpha = typing ? 1 : 0
        }
        animated ? UIView.animate(withDuration: 0.25, animations: change) : change()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = contentView.bounds.width, height = contentView.bounds.height
        slider.frame = CGRect(x: offset, y: 0, width: width, height: height)
        avatar.frame = CGRect(x: 12, y: (height - 58) / 2, width: 58, height: 58)
        let textX: CGFloat = 82
        time.sizeToFit()
        time.frame.origin = CGPoint(x: width - 14 - time.bounds.width, y: 10)
        checks.frame = CGRect(x: time.frame.minX - 22, y: 12, width: 20, height: 14)
        let rightLimit = (checks.isHidden ? time.frame.minX : checks.frame.minX) - 6
        var x = textX
        if kindIcon.image != nil {
            kindIcon.frame = CGRect(x: x, y: 12, width: 16, height: 16)
            x += 19
        }
        name.sizeToFit()
        name.frame = CGRect(x: x, y: 9, width: min(name.bounds.width, rightLimit - x - (mutedIcon.isHidden ? 0 : 18)), height: 20)
        mutedIcon.frame = CGRect(x: name.frame.maxX + 4, y: 12, width: 14, height: 14)
        let badgeWidth = badge.width
        badge.frame = CGRect(x: width - 14 - badgeWidth, y: 40, width: badgeWidth, height: 22)
        pinIcon.frame = CGRect(x: width - 30, y: 42, width: 16, height: 16)
        let messageRight = badgeWidth > 0 ? badge.frame.minX - 8 : (pinIcon.isHidden ? width - 14 : pinIcon.frame.minX - 6)
        message.frame = CGRect(x: textX, y: 30, width: messageRight - textX, height: 40)
        message.sizeToFit()
        message.frame.size.width = messageRight - textX
        typingLabel.frame = CGRect(x: textX, y: 31, width: 76, height: 20)
        dots.frame = CGRect(x: textX + 74, y: 37, width: 24, height: 10)
        separator.frame = CGRect(x: textX, y: height - 0.5, width: width - textX, height: 0.5)
        layoutButtons()
    }

    private func layoutButtons() {
        let width = contentView.bounds.width, height = contentView.bounds.height
        let reveal = abs(offset)
        // Buttons share the revealed strip; on a full swipe the edge one takes all of it.
        for (index, button) in rightButtons.enumerated() {
            let share = reveal / CGFloat(rightButtons.count)
            var frame = CGRect(x: width - reveal + share * CGFloat(index), y: 0, width: share + 1, height: height)
            if full, index == rightButtons.count - 1 { frame = CGRect(x: width - reveal, y: 0, width: reveal, height: height) }
            button.frame = frame
            button.isHidden = offset >= 0
        }
        for (index, button) in leftButtons.enumerated() {
            let share = reveal / CGFloat(leftButtons.count)
            var frame = CGRect(x: reveal - share * CGFloat(index + 1), y: 0, width: share + 1, height: height)
            if full, index == 0 { frame = CGRect(x: 0, y: 0, width: reveal, height: height) }
            button.frame = frame
            button.isHidden = offset <= 0
        }
        contentView.bringSubviewToFront(full ? (offset < 0 ? rightButtons.last! : leftButtons[0]) : slider)
        contentView.bringSubviewToFront(slider)
    }

    override func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        // Also asked about the table's own pan (it is an ancestor's): only judge the row's.
        guard let pan = gesture as? UIPanGestureRecognizer, pan.view === slider else { return true }
        let velocity = pan.velocity(in: self)
        return abs(velocity.x) > abs(velocity.y) * 1.3
    }

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        let width = contentView.bounds.width
        switch gesture.state {
        case .began:
            startOffset = offset
            onSwipeBegan?()
        case .changed:
            var proposed = startOffset + gesture.translation(in: self).x
            // A little resistance past the buttons' width.
            let limit = buttonWidth * CGFloat(proposed < 0 ? rightButtons.count : leftButtons.count)
            if abs(proposed) > limit {
                proposed = (limit + (abs(proposed) - limit) * 0.75) * (proposed < 0 ? -1 : 1)
            }
            offset = proposed
            let nowFull = abs(offset) > width * 0.58
            if nowFull != full {
                full = nowFull
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
                    self.layoutButtons()
                }
            }
            layoutSubviews()
        case .ended, .cancelled:
            let velocity = gesture.velocity(in: self).x
            if full {
                let action: Action = offset < 0 ? .archive : .read
                full = false
                if action == .archive {
                    onAction?(.archive)
                } else {
                    onAction?(.read)
                }
                return
            }
            let count = CGFloat(offset < 0 ? rightButtons.count : leftButtons.count)
            let open = abs(offset) > buttonWidth * count * 0.45 && (offset < 0 ? velocity < 300 : velocity > -300)
            settle(to: open ? buttonWidth * count * (offset < 0 ? -1 : 1) : 0)
        default:
            break
        }
    }

    private func settle(to target: CGFloat) {
        offset = target
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0) {
            self.layoutSubviews()
        }
    }

    func close() {
        full = false
        settle(to: 0)
    }

    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, offset == 0 else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onPeek?()
    }

    /// The row crumbles to dust, then `completion` removes it.
    func dissolve(_ completion: @escaping () -> Void) {
        offset = 0
        layoutSubviews()
        rightButtons.forEach { $0.isHidden = true }
        DustAnimator.blowAway(slider, wind: CGVector(dx: 90, dy: -40), completion: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: completion)
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        UIView.animate(withDuration: highlighted ? 0 : 0.3) {
            self.slider.backgroundColor = highlighted ? MTPalette.fill : MTPalette.background
        }
    }
}

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool { self?.isEmpty ?? true }
}

final class MTSwipeButton: UIControl {
    private let icon = UIImageView()
    private let label = MTViews.label(size: 12, weight: .medium, color: .white)

    init(title: String, symbol: String, color: UIColor) {
        super.init(frame: .zero)
        backgroundColor = color
        clipsToBounds = true
        icon.tintColor = .white
        icon.contentMode = .center
        label.textAlignment = .center
        addSubview(icon)
        addSubview(label)
        set(title: title, symbol: symbol)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func set(title: String, symbol: String) {
        label.text = title
        icon.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Content keeps its size and stays at the inner edge, like Telegram's.
        let contentWidth: CGFloat = 76
        let x = (bounds.width - contentWidth) / 2
        icon.frame = CGRect(x: x, y: bounds.midY - 22, width: contentWidth, height: 26)
        label.frame = CGRect(x: x - 4, y: bounds.midY + 6, width: contentWidth + 8, height: 16)
        let visible = min(1, bounds.width / 40)
        icon.alpha = visible
        label.alpha = visible
    }
}

// MARK: - Peek

/// A long-pressed chat opens as a card over a blur, with a menu under it. Tap the card to go in.
final class MTChatPeek: UIView {
    var onOpen: (() -> Void)?
    var onAction: ((MTChatCell.Action) -> Void)?

    private let blur = UIVisualEffectView(effect: nil)
    private let card = UIView()
    private let menu = UIView()
    private let source: CGRect
    private let target: CGRect
    private let chat: MTChat

    init(in host: UIView, chat: MTChat, from source: CGRect) {
        self.source = source
        self.chat = chat
        let width = host.bounds.width - 32
        let menuHeight: CGFloat = 4 * 46
        let height = min(430, host.bounds.height - host.safeAreaInsets.top - host.safeAreaInsets.bottom - menuHeight - 40)
        target = CGRect(x: 16, y: host.safeAreaInsets.top + 12, width: width, height: height)
        super.init(frame: host.bounds)
        host.addSubview(self)
        blur.frame = bounds
        addSubview(blur)
        blur.contentView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismiss)))

        card.frame = source
        card.layer.cornerRadius = 16
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true
        card.backgroundColor = MTPalette.wallpaper
        addSubview(card)
        buildPreview()
        card.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(open)))

        menu.backgroundColor = MTPalette.cell
        menu.layer.cornerRadius = 14
        menu.layer.cornerCurve = .continuous
        menu.clipsToBounds = true
        menu.frame = CGRect(x: target.maxX - 240, y: target.maxY + 10, width: 240, height: menuHeight)
        let items: [(String, String, MTChatCell.Action, Bool)] = [
            (chat.unread > 0 ? "Read" : "Unread", "checkmark.message", .read, false),
            (chat.pinned ? "Unpin" : "Pin", "pin", .pin, false),
            (chat.muted ? "Unmute" : "Mute", "bell.slash", .mute, false),
            ("Delete", "trash", .delete, true),
        ]
        for (index, item) in items.enumerated() {
            let row = UIButton(type: .system)
            row.frame = CGRect(x: 0, y: CGFloat(index) * 46, width: 240, height: 46)
            var configuration = UIButton.Configuration.plain()
            configuration.title = item.0
            configuration.image = UIImage(systemName: item.1)
            configuration.imagePlacement = .trailing
            configuration.baseForegroundColor = item.3 ? MTPalette.red : MTPalette.text
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
            row.configuration = configuration
            row.contentHorizontalAlignment = .fill
            let action = item.2
            row.addAction(UIAction { [weak self] _ in
                self?.close {
                    self?.onAction?(action)
                }
            }, for: .touchUpInside)
            menu.addSubview(row)
            if index < items.count - 1 {
                let line = UIView(frame: CGRect(x: 0, y: CGFloat(index + 1) * 46 - 0.5, width: 240, height: 0.5))
                line.backgroundColor = MTPalette.separator
                menu.addSubview(line)
            }
        }
        menu.alpha = 0
        menu.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
        addSubview(menu)

        UIView.animate(withDuration: 0.3) { self.blur.effect = UIBlurEffect(style: .systemUltraThinMaterial) }
        UIView.animate(withDuration: 0.55, delay: 0, usingSpringWithDamping: 0.78, initialSpringVelocity: 0) {
            self.card.frame = self.target
            self.layoutPreview()
        }
        UIView.animate(withDuration: 0.45, delay: 0.08, usingSpringWithDamping: 0.7, initialSpringVelocity: 0) {
            self.menu.alpha = 1
            self.menu.transform = .identity
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let previewHeader = UIView()
    private var bubbles: [UIView] = []
    private var bubbleSides: [Bool] = []

    private func buildPreview() {
        previewHeader.backgroundColor = MTPalette.bar
        card.addSubview(previewHeader)
        let avatar = UIImageView(image: ChannelAvatar.image(for: chat.person, size: 36))
        avatar.frame = CGRect(x: 12, y: 8, width: 36, height: 36)
        previewHeader.addSubview(avatar)
        let name = MTViews.label(chat.person.name, size: 16, weight: .semibold)
        name.frame = CGRect(x: 58, y: 8, width: 240, height: 20)
        previewHeader.addSubview(name)
        let status = MTViews.label(chat.online ? "online" : "last seen recently", size: 13,
                                   color: chat.online ? MTPalette.accent : MTPalette.secondary)
        status.frame = CGRect(x: 58, y: 28, width: 240, height: 16)
        previewHeader.addSubview(status)
        let lines: [(String, Bool)] = [("Hey! How are you?", false), ("Great, building a mini-Telegram demo 🚀", true),
                                       ("Can I see it?", false), ("I’ll send a video tonight", true),
                                       (chat.message.isEmpty ? "👋" : chat.message, chat.outgoingRead != nil)]
        bubbleSides = lines.map(\.1)
        for (text, outgoing) in lines {
            let bubble = MTMessageBubble(text: text, outgoing: outgoing, time: "20:4\(bubbles.count)", read: true)
            card.addSubview(bubble)
            bubbles.append(bubble)
        }
        layoutPreview()
    }

    private func layoutPreview() {
        previewHeader.frame = CGRect(x: 0, y: 0, width: target.width, height: 52)
        var y = target.height - 10
        for (bubble, outgoing) in zip(bubbles.reversed(), bubbleSides.reversed()) {
            let size = (bubble as! MTMessageBubble).fittingSize(maxWidth: target.width * 0.75)
            y -= size.height + 6
            bubble.frame = CGRect(x: outgoing ? target.width - 10 - size.width : 10, y: y, width: size.width, height: size.height)
        }
    }

    @objc private func open() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onOpen?()
        UIView.animate(withDuration: 0.25, animations: { self.alpha = 0 }, completion: { _ in self.removeFromSuperview() })
    }

    @objc private func dismiss() {
        close(nil)
    }

    private func close(_ completion: (() -> Void)?) {
        isUserInteractionEnabled = false
        UIView.animate(withDuration: 0.2) {
            self.menu.alpha = 0
            self.menu.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        }
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, animations: {
            self.card.frame = self.source
            self.card.alpha = 0
            self.blur.effect = nil
        }, completion: { _ in
            self.removeFromSuperview()
            completion?()
        })
    }
}
