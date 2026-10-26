//
//  RootViewController.swift
//  controller
//
//  Mini-Telegram: one app that puts the Telegram tricks together. The root holds the theme and its
//  own navigation stack (chat, profile); the home screen under it holds the four tabs, the
//  accounts, the passcode lock and the shared actions every screen calls (open a chat, call).
//

import UIKit
import ContactStorage

final class RootViewController: UIViewController {
    private let stack: UINavigationController
    private let initialChat: Chat?
    let home: HomeViewController

    init(initialChat: Chat? = nil, environment: AppEnvironment = .shared) {
        self.initialChat = initialChat
        home = HomeViewController(environment: environment)
        stack = UINavigationController(rootViewController: home)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = Palette.background
        stack.setNavigationBarHidden(true, animated: false)
        stack.interactivePopGestureRecognizer?.delegate = self
        addChild(stack)
        stack.view.frame = view.bounds
        stack.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(stack.view)
        stack.didMove(toParent: self)
        home.root = self
        if let initialChat {
            home.openWhenStorageReady(initialChat)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        overrideUserInterfaceStyle == .dark ? .lightContent : .darkContent
    }

    var isDark: Bool { overrideUserInterfaceStyle == .dark }

    func push(_ controller: UIViewController) {
        (notificationChatNavigation ?? stack).pushViewController(controller, animated: true)
    }

    func pop() {
        if let navigation = notificationChatNavigation {
            if navigation.viewControllers.count > 1 { navigation.popViewController(animated: true) }
            else { navigation.close() }
        } else { stack.popViewController(animated: true) }
    }

    weak var notificationChatNavigation: NotificationChatNavigationController?

    var visibleChatID: Int? {
        if let navigation = notificationChatNavigation { return (navigation.topViewController as? ChatViewController)?.chatID }
        guard presentedViewController == nil else { return nil }
        return (stack.topViewController as? ChatViewController)?.chatID
    }

    var allowsMessageNotifications: Bool {
        isViewLoaded && view.window?.windowScene?.activationState == .foregroundActive
            && !view.subviews.contains { $0 is PasscodeView }
    }

    /// Flips light/dark with a liquid flood from `point` (in this view).
    func toggleTheme(from point: CGPoint) {
        guard let window = view.window else { return }
        LiquidThemeReveal.transition(in: window, from: view.convert(point, to: window), apply: {
            self.overrideUserInterfaceStyle = self.isDark ? .light : .dark
            self.setNeedsStatusBarAppearanceUpdate()
        })
    }

}

extension RootViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        notificationChatNavigation == nil && stack.viewControllers.count > 1
    }
}

// MARK: - Home

final class HomeViewController: UIViewController {
    weak var root: RootViewController?
    private let environment: AppEnvironment
    private var storageTask: Task<Void, Never>?
    private(set) var accountContext: AccountContext?
    private(set) var storageSession: AccountSession?
    lazy var messageNotifications = MessageNotificationCoordinator(home: self)
    private lazy var demoIncoming = DemoIncomingMessages(home: self)
    private var storageSessions: [UUID: AccountSession] = [:]
    private var pendingInitialChat: Chat?

    init(environment: AppEnvironment) {
        self.environment = environment
        accountCount = min(MessengerData.accounts.count, max(1, UserDefaults.standard.integer(forKey: "messenger.accountCount")))
        currentAccount = min(accountCount - 1, max(0, UserDefaults.standard.integer(forKey: "messenger.currentAccount")))
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { storageTask?.cancel() }

    let chatList = ChatListPage()
    /// Reading state belongs to an account and survives reopening a channel during this session.
    var channelReadingStates: [Int: [Int: ChannelReadingState]] = [:]
    private let contacts = ContactsPage()
    private let calls = CallsPage()
    private let settings = SettingsPage()
    let tabBar = TabBar()
    private var menu: AccountMenu?

    private(set) var accountCount = 1
    private(set) var currentAccount = 0
    private(set) var passcodeEnabled = false
    var account: Account { MessengerData.accounts[currentAccount] }

    private var pages: [UIViewController] { [contacts, calls, chatList, settings] }
    private var hintShown = false

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(protectedDataAvailable),
                                               name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
        prepareAccountStorage()
        view.backgroundColor = Palette.background
        for page in pages {
            (page as? Page)?.home = self
            addChild(page)
            view.addSubview(page.view)
            page.didMove(toParent: self)
            page.view.isHidden = page !== chatList
        }
        view.addSubview(tabBar)
        tabBar.select(.chats, animated: false)
        tabBar.setAvatar(account.person, animated: false)
        tabBar.onSelect = { [weak self] tab in self?.show(tab) }
        tabBar.onSettingsHold = { [weak self] gesture in self?.settingsHeld(gesture) }
        tabBar.onChatsHold = { [weak self] gesture in self?.chatsHeld(gesture) }
        tabBar.onAddFolder = { [weak self] in self?.createFolder() }
        tabBar.onSettingsDoubleTap = { [weak self] in self?.switchToNextAccount() }
        chatList.onUnreadChanged = { [weak self] count in self?.tabBar.setUnread(count, animated: true) }
        chatList.load(account: currentAccount, animated: false)
        tabBar.setUnread(chatList.unreadTotal, animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let barHeight = TabBar.height + view.safeAreaInsets.bottom
        tabBar.frame = CGRect(x: 0, y: view.bounds.height - barHeight, width: view.bounds.width, height: barHeight)
        for page in pages {
            page.view.frame = view.bounds
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hintShown else { return }
        hintShown = true
        showHint("Pull chats down for stories\nHold Settings for accounts")
    }

    var bottomInset: CGFloat { TabBar.height + view.safeAreaInsets.bottom }

    private func show(_ tab: TabBar.Tab) {
        let page = pages[tab.rawValue]
        guard page.view.isHidden else { return }
        chatList.setTabVisible(page === chatList)
        for other in pages where other !== page {
            other.view.isHidden = true
        }
        page.view.isHidden = false
        page.view.alpha = 0
        page.view.transform = CGAffineTransform(scaleX: 0.985, y: 0.985)
        UIView.animate(withDuration: 0.22, delay: 0, options: .curveEaseOut) {
            page.view.alpha = 1
            page.view.transform = .identity
        }
    }

    func showHint(_ text: String) {
        let hint = UILabel()
        hint.text = text
        hint.font = .systemFont(ofSize: 13, weight: .semibold)
        hint.textColor = .white
        hint.textAlignment = .center
        hint.numberOfLines = 0
        hint.backgroundColor = UIColor(white: 0, alpha: 0.7)
        hint.layer.cornerRadius = 15
        hint.clipsToBounds = true
        hint.isUserInteractionEnabled = false
        let size = hint.sizeThatFits(CGSize(width: view.bounds.width - 70, height: 200))
        hint.bounds = CGRect(x: 0, y: 0, width: size.width + 28, height: size.height + 14)
        hint.center = CGPoint(x: view.bounds.midX, y: view.bounds.height - bottomInset - 40)
        hint.alpha = 0
        view.addSubview(hint)
        UIView.animate(withDuration: 0.4) { hint.alpha = 1 }
        UIView.animate(withDuration: 0.6, delay: 4.5, animations: { hint.alpha = 0 }, completion: { _ in hint.removeFromSuperview() })
    }

    // MARK: Navigation shared by the pages

    func openChat(_ chat: Chat, draft: String? = nil) {
        guard let session = storageSession else { showHint("Storage is still opening"); return }
        session.openChat(chat) { [weak self] in
            guard let self, self.storageSession === session else { return }
            self.root?.push(ChatViewController(chat: chat, home: self, draft: draft))
        }
    }

    func openWhenStorageReady(_ chat: Chat) {
        if storageSession != nil { openChat(chat) }
        else { pendingInitialChat = chat }
    }

    func openChat(with person: ChannelPerson) {
        if let chat = chatList.chat(with: person) {
            openChat(chat)
        } else {
            openChat(Chat(id: 1000 + Int(person.hue * 1000), person: person, kind: .person, message: "", time: "", online: true))
        }
    }

    func openProfile(_ person: ChannelPerson, online: Bool, peerID: Int? = nil) {
        root?.push(ProfileViewController(person: person, online: online, home: self, peerID: peerID))
    }

    func call(_ person: ChannelPerson, from sourceView: UIView? = nil) {
        let call = CallViewController(person: person)
        call.modalPresentationStyle = .overFullScreen
        call.modalTransitionStyle = .crossDissolve
        root?.present(call, animated: true)
    }

    func toggleTheme(from view: UIView) {
        guard let root else { return }
        root.toggleTheme(from: view.convert(view.bounds.center, to: root.view))
    }

    var isDark: Bool { root?.isDark ?? true }

    func openSettings() {
        tabBar.select(.settings)
        show(.settings)
    }

    /// Settings → Chat Folders. The app's stack keeps its bar hidden, so the screen
    /// gets its own navigation (back, Edit, the editor) inside a host, like VFX pages.
    func openFolders() {
        guard let session = storageSession else { showHint("Storage is still opening"); return }
        root?.push(VFXNavigationHost(FoldersViewController(session: session), onClose: { [weak self] in self?.root?.pop() }))
    }

    /// Opens the folder's editor; used by the empty folder's Add Chats button.
    func editFolder(_ id: UUID) {
        guard let session = storageSession, let root, root.presentedViewController == nil,
              let folder = session.folders.first(where: { $0.id == id }) else { return }
        let navigation = UINavigationController(rootViewController: FolderEditorViewController(session: session, folder: folder))
        navigation.modalPresentationStyle = .pageSheet
        root.present(navigation, animated: true)
    }

    private func openFolder(_ id: UUID?) {
        tabBar.select(.chats)
        show(.chats)
        chatList.selectFolder(id)
    }

    private func createFolder() {
        guard let session = storageSession else { showHint("Storage is still opening"); return }
        guard let root, root.presentedViewController == nil else { return }
        FolderCreation.present(from: root, session: session) { [weak self, weak session] id in
            guard let self, let session, self.storageSession === session else { return }
            self.openFolder(id)
        }
    }

    private func chatsHeld(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            menu?.close()
            let anchor = tabBar.convert(tabBar.itemCenter(.chats), to: view)
            let menu = AccountMenu(in: view, anchor: anchor, items: [
                AccountMenu.Item(title: "Add Folder", symbol: "folder.badge.plus", person: nil, accent: true),
            ])
            menu.onPick = { [weak self] _ in
                self?.menu = nil
                self?.createFolder()
            }
            self.menu = menu
        case .changed: menu?.track(gesture.location(in: menu))
        case .ended: menu?.release()
        case .cancelled, .failed: menu?.close()
        default: break
        }
    }

    // MARK: Accounts

    private func menuItems() -> [AccountMenu.Item] {
        if accountCount == 1 {
            return [
                AccountMenu.Item(title: "My Profile", symbol: "person.crop.circle", person: nil),
                AccountMenu.Item(title: "Saved Messages", symbol: "bookmark", person: nil),
                AccountMenu.Item(title: passcodeEnabled ? "Lock" : "Passcode", symbol: "lock", person: nil),
                AccountMenu.Item(title: "Add account", symbol: "plus.circle", person: nil, accent: true),
            ]
        }
        var items = (0..<accountCount).map { index in
            AccountMenu.Item(title: MessengerData.accounts[index].person.name, symbol: nil, person: MessengerData.accounts[index].person,
                               checked: index == currentAccount)
        }
        if accountCount < MessengerData.accounts.count {
            items.append(AccountMenu.Item(title: "Add account", symbol: "plus.circle", person: nil, accent: true))
        }
        return items
    }

    private func settingsHeld(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            menu?.close()
            let anchor = tabBar.convert(tabBar.itemCenter(.settings), to: view)
            let items = menuItems()
            let menu = AccountMenu(in: view, anchor: anchor, items: items)
            menu.onPick = { [weak self] index in self?.picked(index, of: items) }
            self.menu = menu
        case .changed:
            menu?.track(gesture.location(in: menu))
        case .ended:
            menu?.release()
        case .cancelled, .failed:
            menu?.close()
        default:
            break
        }
    }

    private func picked(_ index: Int, of items: [AccountMenu.Item]) {
        let item = items[index]
        if item.title == "Add account" {
            addAccount()
        } else if let person = item.person, let account = MessengerData.accounts.firstIndex(where: { $0.person.name == person.name }) {
            switchAccount(to: account)
        } else if item.title == "My Profile" {
            openProfile(account.person, online: true)
        } else if item.title == "Saved Messages" {
            openChat(Chat(id: 999, person: ChannelPerson(name: "Saved Messages", hue: 0.58), kind: .person, message: "", time: ""))
        } else if item.title == "Passcode" {
            setPasscode(true)
        } else if item.title == "Lock" {
            lock()
        }
    }

    func addAccount() {
        guard accountCount < MessengerData.accounts.count else { return }
        accountCount += 1
        UserDefaults.standard.set(accountCount, forKey: "messenger.accountCount")
        settings.reload()
        Views.toast("Account added", symbol: "person.crop.circle.badge.plus", in: view)
        switchAccount(to: accountCount - 1)
    }

    func switchToNextAccount() {
        guard accountCount > 1 else {
            Views.toast("Add a second account", symbol: "person.2", in: view)
            return
        }
        switchAccount(to: (currentAccount + 1) % accountCount)
    }

    func switchAccount(to index: Int) {
        guard index != currentAccount else { return }
        currentAccount = index
        UserDefaults.standard.set(index, forKey: "messenger.currentAccount")
        prepareAccountStorage()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        tabBar.setAvatar(account.person, animated: true)
        chatList.load(account: index, animated: true)
        settings.reload()
    }

    @objc private func protectedDataAvailable() {
        if accountContext == nil { prepareAccountStorage() }
    }

    private func prepareAccountStorage() {
        storageTask?.cancel()
        messageNotifications.bind(nil)
        demoIncoming.bind(nil)
        accountContext = nil
        storageSession = nil
        let accountIndex = currentAccount
        let id = AccountID(account.id)
        let environment = environment
        storageTask = Task { [weak self] in
            do {
                let context = try await environment.accountContext(for: id)
                guard !Task.isCancelled, let self, self.account.id == id.rawValue else { return }
                let session: AccountSession
                if let cached = self.storageSessions[id.rawValue] { session = cached }
                else { session = try await AccountSession.open(context: context, account: accountIndex) }
                guard !Task.isCancelled, self.account.id == id.rawValue else { return }
                self.storageSessions[id.rawValue] = session
                self.accountContext = context
                self.storageSession = session
                self.messageNotifications.bind(session)
                self.demoIncoming.bind(session)
                session.onError = { [weak self] _ in
                    guard let self, self.account.id == id.rawValue else { return }
                    self.showHint("Could not save the change. Please try again.")
                }
                self.chatList.bind(session: session)
                if let initial = self.pendingInitialChat {
                    self.pendingInitialChat = nil
                    self.openChat(initial)
                }
                for chat in session.chats where chat.kind == .channel {
                    if let state = session.readingState(for: chat.id) {
                        self.channelReadingStates[accountIndex, default: [:]][chat.id] = state
                    }
                }
            } catch {
                guard !Task.isCancelled, let self, self.account.id == id.rawValue else { return }
                // Keychain becomes available after the first unlock. Retry on the notification above.
                if !UIApplication.shared.isProtectedDataAvailable { return }
                let alert = UIAlertController(title: "Could not open storage",
                    message: "Your data was not deleted. Try opening storage again.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Retry", style: .default) { [weak self] _ in self?.prepareAccountStorage() })
                alert.addAction(UIAlertAction(title: "Close", style: .cancel))
                self.present(alert, animated: true)
            }
        }
    }

    // MARK: Passcode

    func setPasscode(_ enabled: Bool) {
        passcodeEnabled = enabled
        chatList.updateLock()
        settings.reload()
        if enabled {
            Views.toast("Passcode 1234 · lock in Chats", symbol: "lock.fill", in: view)
        }
    }

    func lock() {
        guard let root else { return }
        messageNotifications.suspend()
        let lock = PasscodeView(frame: root.view.bounds)
        root.view.addSubview(lock)
        lock.appear()
    }
}

/// A tab's page: knows the home screen and keeps its content clear of the tab bar.
class Page: UIViewController {
    weak var home: HomeViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.background
    }
}

// MARK: - Passcode lock

/// The lock screen: liquid PIN drops and a round keypad. A wrong code splashes and shakes; the
/// right one (1234) merges the drops and the lock opens as a growing hole from the middle.
final class PasscodeView: UIView {
    private let blur = UIVisualEffectView(effect: nil)
    private let content = UIView()
    private let icon = UIImageView()
    private let title = Views.label("Enter passcode", size: 20, weight: .semibold)
    private let drops = PinDropsView(length: 4)
    private var code = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        blur.frame = bounds
        addSubview(blur)
        content.frame = bounds
        content.alpha = 0
        addSubview(content)
        icon.image = UIImage(systemName: "lock.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 34, weight: .semibold))
        icon.tintColor = Palette.text
        icon.contentMode = .center
        icon.frame = CGRect(x: 0, y: bounds.height * 0.12, width: bounds.width, height: 44)
        content.addSubview(icon)
        title.textAlignment = .center
        title.frame = CGRect(x: 0, y: icon.frame.maxY + 14, width: bounds.width, height: 26)
        content.addSubview(title)
        let hint = Views.label("Demo code: 1234", size: 13, color: Palette.secondary)
        hint.textAlignment = .center
        hint.frame = CGRect(x: 0, y: title.frame.maxY + 4, width: bounds.width, height: 18)
        content.addSubview(hint)
        drops.liquidColor = Palette.text
        drops.frame = CGRect(x: 0, y: hint.frame.maxY, width: bounds.width, height: 120)
        content.addSubview(drops)

        let key: CGFloat = 78, gap: CGFloat = 22
        let gridWidth = key * 3 + gap * 2
        let top = drops.frame.maxY + 10
        let labels = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "⌫"]
        for (index, text) in labels.enumerated() where !text.isEmpty {
            let button = UIButton(type: .system)
            button.frame = CGRect(x: (bounds.width - gridWidth) / 2 + CGFloat(index % 3) * (key + gap),
                                  y: top + CGFloat(index / 3) * (key + 14), width: key, height: key)
            button.setTitle(text, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: text == "⌫" ? 24 : 32, weight: .regular)
            button.setTitleColor(Palette.text, for: .normal)
            button.backgroundColor = text == "⌫" ? .clear : Palette.fill
            button.layer.cornerRadius = key / 2
            button.addAction(UIAction { [weak self, weak button] _ in
                self?.pressed(text)
                if let button { Views.pop(button, scale: 0.9) }
            }, for: .touchUpInside)
            content.addSubview(button)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func appear() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        UIView.animate(withDuration: 0.35) {
            self.blur.effect = UIBlurEffect(style: .systemThickMaterial)
            self.content.alpha = 1
        }
        content.transform = CGAffineTransform(scaleX: 1.08, y: 1.08)
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
            self.content.transform = .identity
        }
    }

    private func pressed(_ key: String) {
        if key == "⌫" {
            guard !code.isEmpty else { return }
            code.removeLast()
            drops.deleteLast()
            return
        }
        guard code.count < 4 else { return }
        code += key
        drops.append()
        guard code.count == 4 else { return }
        if code == "1234" {
            isUserInteractionEnabled = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self.drops.accept()
                self.icon.setContactSymbol(UIImage(systemName: "lock.open.fill")!, transition: .replace)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.unlock() }
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self.drops.reject()
                self.code = ""
            }
        }
    }

    /// A hole opens in the middle and grows until the lock screen is gone.
    private func unlock() {
        let mask = CAShapeLayer()
        mask.fillRule = .evenOdd
        let center = bounds.center
        func path(_ radius: CGFloat) -> CGPath {
            let path = UIBezierPath(rect: bounds.insetBy(dx: -10, dy: -10))
            path.append(UIBezierPath(arcCenter: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: true))
            return path.cgPath
        }
        let radius = hypot(bounds.width, bounds.height) / 2 + 20
        mask.path = path(radius)
        layer.mask = mask
        let grow = CABasicAnimation(keyPath: "path")
        grow.fromValue = path(1)
        grow.toValue = path(radius)
        grow.duration = 0.55
        grow.timingFunction = CAMediaTimingFunction(controlPoints: 0.6, 0, 0.3, 1)
        mask.add(grow, forKey: "grow")
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIView.animate(withDuration: 0.5, animations: {
            self.content.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
        })
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.56) { self.removeFromSuperview() }
    }
}
