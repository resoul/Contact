import UIKit
import ContactStorage

@MainActor final class AccountSession {
    let context: AccountContext
    private(set) var chats: [Chat] = []
    var onChatsChanged: ((UUID?) -> Void)?
    var onError: ((Error) -> Void)?
    private var chatState: StoredChatListState?
    private var historyStates: [Int: StoredHistoryState] = [:]
    private var historyRows: [Int: [StoredMessage]] = [:]
    private var historyTasks: [Int: Task<Void, Never>] = [:]
    private var listeners: [UUID: (Int, (UUID?) -> Void)] = [:]
    private var chatTask: Task<Void, Never>?
    private var writeTail: Task<Void, Never>?
    private var writing = false
    private var pendingChats: StoredChatListState?
    private var pendingHistories: [Int: StoredHistoryState] = [:]

    private init(context: AccountContext) { self.context = context }
    deinit { chatTask?.cancel(); historyTasks.values.forEach { $0.cancel() } }

    static func open(context: AccountContext, account: Int) async throws -> AccountSession {
        try await FixtureSeeder.seedIfNeeded(storage: context.storage, account: account)
        let session = AccountSession(context: context)
        try session.applyChats(await context.storage.chatListState())
        for chat in session.chats where chat.kind == .channel {
            try session.applyHistory(await context.storage.historyState(peerID: Int64(chat.id)), chatID: chat.id)
        }
        session.startObservingChats()
        return session
    }

    func sections(for chatID: Int) -> [(title: String, messages: [Message])] {
        let messages = (historyRows[chatID] ?? []).compactMap { try? StorageMapping.message($0) }
        return StorageMapping.sections(messages).map { ($0.title, $0.messages) }
    }

    func readingState(for chatID: Int) -> ChannelReadingState? {
        guard let payload = historyStates[chatID]?.interfaceState,
              let value = try? JSONDecoder().decode(ReadingPosition.self, from: payload) else { return nil }
        return value.state(sections: sections(for: chatID))
    }

    func observeHistory(chatID: Int, token: UUID, changed: @escaping (UUID?) -> Void) {
        listeners[token] = (chatID, changed)
        guard historyTasks[chatID] == nil else { return }
        let storage = context.storage
        historyTasks[chatID] = Task { [weak self] in
            do {
                for try await state in storage.observeHistoryState(peerID: Int64(chatID)) {
                    guard !Task.isCancelled, let self else { return }
                    if self.writing { self.pendingHistories[chatID] = state; continue }
                    guard state.revision >= (self.historyStates[chatID]?.revision ?? -1) else { continue }
                    let changed = self.historyStates[chatID]?.messages != state.messages
                    try self.applyHistory(state, chatID: chatID)
                    if changed { self.notifyHistory(chatID, origin: nil) }
                }
            } catch { if !Task.isCancelled { self?.onError?(error) } }
        }
    }

    func stopObserving(token: UUID) {
        guard let removed = listeners.removeValue(forKey: token) else { return }
        if !listeners.values.contains(where: { $0.0 == removed.0 }) {
            historyTasks.removeValue(forKey: removed.0)?.cancel()
        }
    }

    func openChat(_ chat: Chat, completion: @escaping () -> Void) {
        perform(chatID: chat.id, origin: UUID(), operation: { [context] in
            try await context.storage.ensureConversation(StorageMapping.peer(chat))
            try await context.storage.markChatRead(peerID: Int64(chat.id))
        }, completion: completion)
    }

    func save(_ message: Message, chatID: Int, origin: UUID, onFailure: @escaping () -> Void = {}, completion: @escaping () -> Void = {}) {
        perform(chatID: chatID, origin: origin, operation: { [context] in
            try await context.storage.storeMessage(StorageMapping.local(message, chatID: chatID))
        }, onFailure: onFailure, completion: completion)
    }

    func mutateMessage(
        chatID: Int,
        messageID: Int,
        origin: UUID,
        change: @escaping (inout Message) -> Void,
        completion: @escaping () -> Void
    ) {
        perform(chatID: chatID, origin: origin, operation: { [weak self, context] in
            guard let self, let stored = self.historyRows[chatID]?.first(where: { (try? StorageMapping.message($0).id) == messageID }) else {
                throw StorageError.messageNotFound
            }
            var value = try StorageMapping.message(stored)
            change(&value)
            try await context.storage.storeMessage(StorageMapping.local(value, chatID: chatID, state: stored.state))
            if let updated = try await context.storage.message(localID: stored.localID),
               let index = self.historyRows[chatID]?.firstIndex(where: { $0.localID == stored.localID }) {
                self.historyRows[chatID]?[index] = updated
            }
        }, completion: completion)
    }

    func delete(chatID: Int, ids: Set<Int>, origin: UUID, completion: @escaping () -> Void) {
        perform(chatID: chatID, origin: origin, operation: { [weak self, context] in
            let rows = self?.historyRows[chatID] ?? []
            let keys = rows.filter { ids.contains((try? StorageMapping.message($0).id) ?? -1) }.map(\.localID)
            try await context.storage.deleteMessages(keys)
            self?.historyRows[chatID]?.removeAll { keys.contains($0.localID) }
        }, completion: completion)
    }

    func changeChat(_ chat: Chat, action: ChatCell.Action, origin: UUID, completion: @escaping () -> Void) {
        perform(chatID: nil, origin: origin, operation: { [weak self, context] in
            let current = self?.chats.first(where: { $0.id == chat.id }) ?? chat
            switch action {
            case .read: try await context.storage.setChatManuallyUnread(peerID: Int64(chat.id), unread: current.unread == 0)
            case .pin: try await context.storage.setChatOptions(peerID: Int64(chat.id), isMuted: current.muted, isPinned: !current.pinned)
            case .mute: try await context.storage.setChatOptions(peerID: Int64(chat.id), isMuted: !current.muted, isPinned: current.pinned)
            case .delete: try await context.storage.deleteChat(peerID: Int64(chat.id))
            case .archive: try await context.storage.setChatArchived(peerID: Int64(chat.id), archived: true)
            }
        }, completion: completion)
    }

    func forward(_ original: Message, from source: String, to person: ChannelPerson, completion: @escaping () -> Void) {
        let chat = chats.first(where: { $0.person.name == person.name }) ?? Chat(
            id: person.name == "Saved Messages" ? 999 : 1000 + Int(person.hue * 1000), person: person, kind: .person, message: "", time: "")
        var copy = Message(kind: original.kind, outgoing: true, time: StorageMapping.time(Int64(Date().timeIntervalSince1970 * 1000)), read: false)
        copy.reply = Message.Quote(name: "Forwarded from \(source)", text: original.summary)
        copy.link = original.link
        let forwarded = copy
        perform(chatID: chat.id, origin: UUID(), operation: { [context] in
            try await context.storage.storeMessage(StorageMapping.local(forwarded, chatID: chat.id), creating: StorageMapping.peer(chat))
        }, completion: completion)
    }

    func markRead(chatID: Int) {
        perform(chatID: chatID, origin: UUID(), operation: { [context] in try await context.storage.markChatRead(peerID: Int64(chatID)) })
    }

    func savePosition(chatID: Int, state: ChannelReadingState) {
        perform(chatID: nil, origin: UUID(), operation: { [context] in
            try await context.storage.storeInterfaceState(peerID: Int64(chatID), payload: JSONEncoder().encode(ReadingPosition(state)))
        })
    }

    func loadOlder(chatID: Int, completion: @escaping () -> Void) {
        guard let oldest = historyRows[chatID]?.min(by: { ($0.timestamp, $0.localID.uuidString) < ($1.timestamp, $1.localID.uuidString) }) else { return }
        perform(chatID: nil, origin: UUID(), operation: { [weak self, context] in
            let older = try await context.storage.historyState(peerID: Int64(chatID), before: MessageCursor(message: oldest))
            _ = try older.messages.map(StorageMapping.message)
            let known = Set((self?.historyRows[chatID] ?? []).map(\.localID))
            self?.historyRows[chatID, default: []].append(contentsOf: older.messages.filter { !known.contains($0.localID) })
        }, completion: completion)
    }

    private func perform(
        chatID: Int?,
        origin: UUID,
        operation: @escaping @MainActor () async throws -> Void,
        onFailure: @escaping () -> Void = {},
        completion: @escaping () -> Void = {}
    ) {
        let previous = writeTail
        writeTail = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            let background = UIApplication.shared.beginBackgroundTask(withName: "ContactStorage", expirationHandler: nil)
            defer { if background != .invalid { UIApplication.shared.endBackgroundTask(background) } }
            self.writing = true
            defer { self.writing = false; self.flushPendingObservations() }
            var committed = false
            do {
                try await operation()
                committed = true
                try self.applyChats(await self.context.storage.chatListState())
                if let chatID { try self.applyHistory(await self.context.storage.historyState(peerID: Int64(chatID)), chatID: chatID) }
                completion()
                self.onChatsChanged?(origin)
                if let chatID { self.notifyHistory(chatID, origin: origin) }
            } catch { if !committed { onFailure() }; self.onError?(error) }
        }
    }

    private func startObservingChats() {
        let storage = context.storage
        chatTask = Task { [weak self] in
            do {
                for try await state in storage.observeChatListState() {
                    guard !Task.isCancelled, let self else { return }
                    if self.writing { self.pendingChats = state; continue }
                    guard state.revision >= (self.chatState?.revision ?? -1) else { continue }
                    let changed = self.chatState?.chats != state.chats
                    try self.applyChats(state)
                    if changed { self.onChatsChanged?(nil) }
                }
            } catch { if !Task.isCancelled { self?.onError?(error) } }
        }
    }

    private func applyChats(_ state: StoredChatListState) throws {
        chats = try state.chats.map(StorageMapping.chat)
        chatState = state
    }

    private func applyHistory(_ state: StoredHistoryState, chatID: Int) throws {
        _ = try state.messages.map(StorageMapping.message)
        let older: [StoredMessage]
        if state.messages.count == 500, let boundary = state.messages.last {
            older = (historyRows[chatID] ?? []).filter { ($0.timestamp, $0.localID.uuidString) < (boundary.timestamp, boundary.localID.uuidString) }
        } else { older = [] }
        historyRows[chatID] = state.messages + older
        historyStates[chatID] = state
    }

    private func notifyHistory(_ chatID: Int, origin: UUID?) {
        for (_, item) in listeners where item.0 == chatID { item.1(origin) }
    }

    private func flushPendingObservations() {
        let chats = pendingChats; pendingChats = nil
        let histories = pendingHistories; pendingHistories.removeAll()
        do {
            if let chats, chats.revision > (chatState?.revision ?? -1) {
                let changed = chatState?.chats != chats.chats
                try applyChats(chats)
                if changed { onChatsChanged?(nil) }
            }
            for (id, state) in histories where state.revision > (historyStates[id]?.revision ?? -1) {
                let changed = historyStates[id]?.messages != state.messages
                try applyHistory(state, chatID: id)
                if changed { notifyHistory(id, origin: nil) }
            }
        } catch { onError?(error) }
    }
}
