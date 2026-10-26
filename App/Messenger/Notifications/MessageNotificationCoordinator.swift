import UIKit

/// One foreground notification queue for the selected account, independent of
/// which tab or screen is visible. Message bursts coalesce by conversation.
@MainActor final class MessageNotificationCoordinator: NSObject {
    private struct Pending {
        let chat: Chat
        let message: Message
    }

    private weak var home: HomeViewController?
    private var session: AccountSession?
    private var pending: [Pending] = []
    private var current: MessageNotificationView?
    private var overlay: MessageNotificationOverlayController?
    private var currentChatID: Int?
    private var drafts: [Int: String] = [:]

    init(home: HomeViewController) {
        self.home = home
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(applicationWillResignActive),
                                               name: UIApplication.willResignActiveNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func applicationWillResignActive() { suspend() }

    func bind(_ session: AccountSession?) {
        self.session?.onIncomingMessage = nil
        suspend()
        drafts.removeAll()
        self.session = session
        session?.onIncomingMessage = { [weak self, weak session] chat, message in
            guard let self, let session, self.session === session else { return }
            self.receive(chat: chat, message: message)
        }
    }

    func suspend() {
        pending.removeAll()
        current?.onFinish = nil
        current?.dismiss(immediately: true)
        removeOverlay()
        current = nil
        currentChatID = nil
    }

    private func receive(chat: Chat, message: Message) {
        guard let home, let root = home.root,
              home.storageSession === session, root.allowsMessageNotifications,
              UIApplication.shared.applicationState == .active else { return }
        if root.visibleChatID == chat.id {
            session?.markRead(chatID: chat.id)
            return
        }
        if currentChatID == chat.id, current?.acceptsUpdates == true {
            current?.update(text: message.summary)
            return
        }
        pending.removeAll { $0.chat.id == chat.id }
        pending.append(Pending(chat: chat, message: message))
        // Keep the newest conversations if a burst arrives while composing.
        if pending.count > 12 { pending.removeFirst(pending.count - 12) }
        showNext()
    }

    func showNext() {
        guard current == nil, let home, let root = home.root,
              root.allowsMessageNotifications, root.notificationChatNavigation == nil,
              root.presentedViewController == nil,
              UIApplication.shared.applicationState == .active,
              root.view.window != nil else { return }
        while !pending.isEmpty {
            let next = pending.removeFirst()
            guard next.chat.id != root.visibleChatID,
                  let chat = session?.chats.first(where: { $0.id == next.chat.id }),
                  chat.unread > 0, !chat.muted else { continue }
            present(next)
            break
        }
    }

    private func present(_ pending: Pending) {
        guard let session, let root = home?.root else { return }
        let chat = pending.chat
        let notification = MessageNotificationView(chat: chat, text: pending.message.summary, draft: drafts[chat.id] ?? "")
        let overlay = MessageNotificationOverlayController(notification: notification)
        self.overlay = overlay
        current = notification
        currentChatID = chat.id
        notification.onDraftChanged = { [weak self] text in
            self?.drafts[chat.id] = text.isEmpty ? nil : text
        }
        notification.onSend = { [weak self, weak session] text, completion in
            guard let self, let session, self.session === session else { completion(false); return }
            session.reply(to: chat, text: text) { [weak self] success in
                if success, self?.session === session { self?.drafts[chat.id] = nil }
                completion(success)
            }
        }
        notification.onPrepareChat = { [weak self, weak session, weak notification] completion in
            guard let self, let home = self.home, let session, self.session === session else { completion(false); return }
            session.openChat(chat, onFailure: { completion(false) }) { [weak self, weak notification] in
                guard let self, let notification, self.current === notification,
                      self.session === session, home.storageSession === session,
                      self.overlay?.prepareChat(chat, home: home) != nil else {
                    completion(false)
                    return
                }
                completion(true)
            }
        }
        // Only an expanded card counts as the visible chat: while collapsed, new
        // messages from this person still update the banner text.
        notification.onExpandedChanged = { [weak self] expanded in
            guard let self, let root = self.home?.root else { return }
            if expanded { root.notificationChatNavigation = self.overlay?.navigation }
            else if root.notificationChatNavigation === self.overlay?.navigation { root.notificationChatNavigation = nil }
        }
        notification.onOpenFullChat = { [weak self, weak notification] draft in
            guard let self, let home = self.home else { return }
            notification?.dismiss(immediately: true)
            // The full chat's composer owns the draft from here.
            self.drafts[chat.id] = nil
            home.openChat(chat, draft: draft.isEmpty ? nil : draft)
        }
        notification.onWillDismiss = { [weak overlay] in overlay?.beginClosing() }
        notification.onFinish = { [weak self, weak notification] in
            guard let self, self.current === notification else { return }
            self.current = nil
            self.currentChatID = nil
            self.removeOverlay()
            self.showNext()
        }
        root.addChild(overlay)
        overlay.beginAppearanceTransition(true, animated: false)
        overlay.view.frame = root.view.bounds
        overlay.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        root.view.addSubview(overlay.view)
        overlay.didMove(toParent: root)
        overlay.endAppearanceTransition()
        notification.start()
    }

    private func removeOverlay() {
        if home?.root?.notificationChatNavigation === overlay?.navigation {
            home?.root?.notificationChatNavigation = nil
        }
        overlay?.remove()
        overlay = nil
    }
}
