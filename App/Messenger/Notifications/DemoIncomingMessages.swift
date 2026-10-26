import UIKit

/// Prototype delivery until a server transport exists: about once a minute one
/// person from the current account writes, so in-app notifications show up during
/// normal use. Messages are stored like real incoming ones.
@MainActor final class DemoIncomingMessages {
    private static let interval: TimeInterval = 60
    private static let texts = [
        "Есть минутка? Напиши, когда будет удобно 🙂",
        "Ты где? Мы уже на месте",
        "Глянь, что я нашёл 😄",
        "Созвонимся вечером?",
        "Спасибо за вчера!",
        "Можешь скинуть файл ещё раз?",
        "Как прошло?",
        "Ок, договорились 👍",
    ]

    private weak var home: HomeViewController?
    private var session: AccountSession?
    private var timer: Timer?

    init(home: HomeViewController) { self.home = home }

    deinit { timer?.invalidate() }

    func bind(_ session: AccountSession?) {
        timer?.invalidate()
        timer = nil
        self.session = session
        guard session != nil else { return }
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.deliver() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func deliver() {
        guard let home, let session, home.storageSession === session, let root = home.root,
              root.allowsMessageNotifications, UIApplication.shared.applicationState == .active else { return }
        // Someone you are not looking at right now, and not a muted chat.
        let visible = root.visibleChatID
        guard let chat = session.chats.filter({ $0.kind == .person && !$0.muted && $0.id >= 0 && $0.id != visible }).randomElement(),
              let text = Self.texts.randomElement() else { return }
        Task { @MainActor [weak home] in
            do {
                guard let home, home.storageSession === session else { return }
                let timestamp = session.nextMessageTimestamp(chatID: chat.id)
                var message = Message(kind: .text(text), outgoing: false, time: StorageMapping.time(timestamp))
                message.timestamp = timestamp
                try await session.context.storage.storeMessage(StorageMapping.local(message, chatID: chat.id, unread: true),
                                                                creating: StorageMapping.peer(chat))
            } catch { session.onError?(error) }
        }
    }
}
