import UIKit
import AsyncDisplayKit
import ListUI

/// Main Chats screen: ListUI scrolling with the messenger's story and row components.
final class ChatListPage: Page {
    var onUnreadChanged: ((Int) -> Void)?
    private var chats: [Chat] = []
    private weak var storageSession: AccountSession?
    private let storageOrigin = UUID()
    private var accountID = MessengerData.accounts[0].id
    private var customFolders: [SessionFolder] = []
    private var choices: [ChatListFolder] = []
    private var lists: [String: WeakList] = [:]
    private let pager = ListPagerNode(theme: ListTheme(background: Palette.background, rowBackground: Palette.background,
        primary: Palette.text, secondary: Palette.secondary, separator: Palette.separator, accent: Palette.accent))
    private let header = StoriesHeader()
    private let folders = ChatFolderTabsView()
    private var storiesExpanded = false
    private var updatingHeader = false
    private var applyingAnimated = false
    private var hasFolders: Bool { !customFolders.isEmpty }
    private var baseInset: CGFloat {
        view.safeAreaInsets.top + StoriesHeader.titleHeight + (hasFolders ? StoriesHeader.foldersHeight : 0)
    }
    private var topInset: CGFloat { baseInset + (storiesExpanded ? StoriesHeader.storiesHeight : 0) }

    var channels: [Chat] { chats.filter { $0.kind == .channel } }
    var unreadTotal: Int { chats.filter { !$0.muted }.reduce(0) { $0 + $1.unread } }
    func chat(with person: ChannelPerson) -> Chat? { chats.first { $0.person.name == person.name } }
    func markRead(_ id: Int) { storageSession?.markRead(chatID: id) }

    override func viewDidLoad() {
        super.viewDidLoad()
        pager.showsBuiltInTabs = false
        pager.usesFullWidthPaging = true
        pager.view.accessibilityIdentifier = "contact.chats"
        view.addSubview(pager.view)
        view.addSubview(header)
        header.addSubview(folders)
        header.onSettings = { [weak self] in self?.home?.openSettings() }
        header.onLock = { [weak self] in self?.home?.lock() }
        header.onCompose = { [weak self] in
            guard let self else { return }
            Views.toast("New Message", symbol: "square.and.pencil", in: self.view)
        }
        header.onStackTap = { [weak self] in self?.expandStories() }
        header.onOpenStory = { [weak self] index in self?.openStory(index) }
        folders.addTarget(self, action: #selector(folderSelected), for: .valueChanged)
        pager.pageTransitionUpdated = { [weak self] progress in self?.folders.setTransitionProgress(progress) }
        pager.selectedPageChanged = { [weak self] _ in
            guard let self else { return }
            self.storiesExpanded = (-(self.pager.currentList?.contentOffset ?? -self.baseInset) - self.baseInset) > 1
            self.updateFolderTabs()
            self.synchronizeInsets()
            self.layoutHeader()
        }
        refresh(animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        ASTraitCollectionPropagateDown(pager, ASPrimitiveTraitCollectionFromUITraitCollection(traitCollection))
        pager.frame = CGRect(x: 0, y: 0, width: view.bounds.width,
                             height: max(0, view.bounds.height - (home?.bottomInset ?? view.safeAreaInsets.bottom)))
        synchronizeInsets()
        layoutHeader()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pager.currentPane?.closeInteractions()
    }

    func load(account: Int, animated: Bool) {
        storageSession?.onChatsChanged = nil
        storageSession = nil
        accountID = MessengerData.accounts[account].id
        chats = []
        customFolders = FolderSessionStore.shared.folders(for: accountID)
        storiesExpanded = false
        lists = [:]
        if isViewLoaded {
            pager.apply(state: ItemListState(pages: []), theme: theme, animated: false)
            header.setAccount(account)
            refresh(animated: false)
        }
    }

    func bind(session: AccountSession) {
        storageSession?.onChatsChanged = nil
        storageSession = session
        session.onChatsChanged = { [weak self, weak session] origin in
            guard let self, let session, self.storageSession === session, origin != self.storageOrigin else { return }
            self.applyStoredChats(session.chats)
        }
        applyStoredChats(session.chats)
    }

    func updateLock() { header.setLock(home?.passcodeEnabled == true) }

    func refreshSessionFolders() {
        customFolders = FolderSessionStore.shared.folders(for: accountID)
        guard isViewLoaded else { return }
        refresh(animated: false)
    }

    func selectSessionFolder(_ id: UUID?) {
        refreshSessionFolders()
        let choice = id.flatMap { id in choices.first(where: { $0.customID == id }) } ?? choices.first
        if let choice { pager.selectPage(id: choice.id) }
    }

    private var theme: ListTheme {
        ListTheme(background: Palette.background, rowBackground: Palette.background,
                  primary: Palette.text, secondary: Palette.secondary,
                  separator: Palette.separator, accent: Palette.accent)
    }

    private func applyStoredChats(_ value: [Chat]) {
        chats = value
        guard isViewLoaded else { return }
        refresh()
    }

    private func refresh(animated: Bool = true) {
        choices = ChatListAdapter.folders(accountID: accountID, custom: customFolders)
        applyingAnimated = animated
        let pages = choices.map { choice -> ListPage in
            let items: [any ListItem]
            if choice.customID != nil {
                items = [ChatEmptyItem(id: "empty:\(choice.id)", name: choice.title)]
            } else {
                items = choice.chats(from: chats).map { self.item($0) }
            }
            return ListPage(id: choice.id, title: choice.title, makePane: { [weak self] theme in
                let list = ListView(theme: theme)
                self?.configure(list, pageID: choice.id)
                return ListPane(list: list)
            }, updatePane: { [weak self] pane, theme in
                guard let self, let list = (pane as? ListPane)?.list else { return }
                list.theme = theme
                self.configureInsets(list)
                list.apply(items: items, animated: self.applyingAnimated)
            })
        }
        pager.apply(state: ItemListState(pages: pages), theme: theme, animated: animated)
        updateFolderTabs()
        layoutHeader()
        onUnreadChanged?(unreadTotal)
    }

    private func item(_ chat: Chat) -> ChatListItem {
        ChatListItem(chat: chat, accountID: accountID, swipeEnabled: !hasFolders,
            onSelect: { [weak self] id in
                guard let self, let chat = self.chats.first(where: { $0.id == id }) else { return }
                if self.pager.currentList?.hasOpenReveal == true {
                    self.pager.currentList?.closeReveals()
                    return
                }
                self.home?.openChat(chat)
            }, onAction: { [weak self] id, action, node in self?.perform(action, id: id, node: node) },
            onPeek: { [weak self] id, node in self?.peek(id: id, node: node) },
            onSwipe: { [weak self] node in self?.pager.currentList?.closeReveals(except: node) })
    }

    private func configure(_ list: ListView, pageID: String) {
        lists[pageID] = WeakList(list)
        configureInsets(list)
        list.scrollingChanged = { [weak self] list in self?.listDidScroll(list) }
        list.scrollingTarget = { [weak self] list, velocity, target in
            self?.scrollingTarget(list, velocity: velocity, target: target) ?? target
        }
    }

    private func configureInsets(_ list: ListView) {
        let desired = UIEdgeInsets(top: topInset, left: 0, bottom: 0, right: 0)
        guard list.contentInsets != desired else { return }
        let wasAtTop = list.contentOffset <= -list.contentInsets.top + 1
        list.contentInsets = desired
        if wasAtTop && !list.scrollView.isDragging { list.contentOffset = -desired.top }
    }

    private func synchronizeInsets() {
        for (id, weakList) in lists {
            if let list = weakList.value { configureInsets(list) }
            else { lists.removeValue(forKey: id) }
        }
    }

    private func updateFolderTabs() {
        let selected = choices.firstIndex(where: { $0.id == pager.selectedPageID }) ?? 0
        let counts = choices.map { $0.chats(from: chats).filter { $0.unread > 0 }.count }
        folders.apply(titles: choices.map(\.title), counts: counts, selectedIndex: selected)
        folders.isHidden = !hasFolders
    }

    @objc private func folderSelected() {
        guard choices.indices.contains(folders.selectedIndex) else { return }
        pager.selectPage(id: choices[folders.selectedIndex].id)
    }

    private func layoutHeader() {
        guard !updatingHeader else { return }
        let pulled = -((pager.currentList?.contentOffset ?? -topInset) + baseInset)
        let storyHeight = min(max(pulled, 0), StoriesHeader.storiesHeight)
        header.safeTop = view.safeAreaInsets.top
        header.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: baseInset + storyHeight)
        header.setPull(pulled / StoriesHeader.storiesHeight)
        folders.frame = CGRect(x: 12, y: header.bounds.height - StoriesHeader.foldersHeight + 4,
                               width: max(0, view.bounds.width - 24), height: 32)
    }

    private func listDidScroll(_ list: ListView) {
        guard pager.currentList === list, !updatingHeader else { return }
        let pulled = -(list.contentOffset + baseInset)
        if storiesExpanded && pulled <= 0 {
            updatingHeader = true
            storiesExpanded = false
            synchronizeInsets()
            updatingHeader = false
        }
        layoutHeader()
    }

    private func scrollingTarget(_ list: ListView, velocity: CGPoint, target: CGPoint) -> CGPoint {
        guard pager.currentList === list else { return target }
        let pulled = -(list.contentOffset + baseInset)
        let full = StoriesHeader.storiesHeight
        var result = target
        if !storiesExpanded && pulled > full * 0.55 {
            storiesExpanded = true
            configureInsets(list)
            result.y = -(baseInset + full)
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        } else if storiesExpanded {
            let targetPulled = -(target.y + baseInset)
            if targetPulled > 0 && targetPulled < full {
                result.y = targetPulled > full * 0.5 && velocity.y <= 0 ? -(baseInset + full) : -baseInset
            }
        }
        return result
    }

    private func expandStories() {
        guard let list = pager.currentList else { return }
        storiesExpanded = true
        configureInsets(list)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        UIView.animate(withDuration: 0.6, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
            list.scrollView.contentOffset.y = -self.topInset
            self.layoutHeader()
        }
    }

    private func openStory(_ index: Int) {
        guard let host = home?.root?.view else { return }
        let viewer = StoryViewer(in: host, users: MessengerData.storyUsers, start: index) { [weak self, weak host] user in
            guard let self, let host else { return .zero }
            return self.header.avatarFrame(user, in: host)
        }
        viewer.onSeen = { [weak self] user in self?.header.markSeen(user) }
    }

    private func perform(_ action: ChatCell.Action, id: Int, node: ChatListItemNode?) {
        guard let session = storageSession, let chat = chats.first(where: { $0.id == id }) else { return }
        let identity = ChatListItem.identity(accountID: accountID, chatID: id)
        session.changeChat(chat, action: action, origin: storageOrigin) { [weak self, weak session, weak node] in
            guard let self, let session, self.storageSession === session else { return }
            let node = node.flatMap { $0.itemID == identity ? $0 : nil }
            node?.closeInteractions(animated: true)
            if action == .delete, let node {
                node.cell.dissolve { [weak self, weak session] in
                    guard let self, let session, self.storageSession === session else { return }
                    self.applyStoredChats(session.chats)
                }
            } else {
                self.applyStoredChats(session.chats)
            }
            if action == .archive { Views.toast("Chat archived", symbol: "archivebox.fill", in: self.view) }
            if action == .mute {
                Views.toast(chat.muted ? "Notifications enabled" : "Notifications disabled",
                              symbol: chat.muted ? "bell.fill" : "bell.slash.fill", in: self.view)
            }
        }
    }

    private func peek(id: Int, node: ChatListItemNode) {
        guard let chat = chats.first(where: { $0.id == id }), let root = home?.root?.view else { return }
        pager.currentList?.closeReveals()
        let peek = ChatPeek(in: root, chat: chat, from: node.cell.convert(node.cell.bounds, to: root))
        peek.onOpen = { [weak self] in self?.home?.openChat(chat) }
        peek.onAction = { [weak self] action in
            guard let self else { return }
            let idString = ChatListItem.identity(accountID: self.accountID, chatID: id)
            self.perform(action, id: id, node: self.pager.currentList?.itemNode(for: idString) as? ChatListItemNode)
        }
    }
}

private final class WeakList {
    weak var value: ListView?
    init(_ value: ListView) { self.value = value }
}
