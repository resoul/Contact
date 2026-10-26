import UIKit
import ContactStorage

@MainActor final class AccountSession {
    let context: AccountContext
    /// Posted with this session as the object when its folders change.
    static let foldersDidChange = Notification.Name("Contact.AccountSessionFoldersDidChange")
    private(set) var chats: [Chat] = []
    private(set) var folders: [ChatFolder] = []
    /// Where All Chats sits among `folders`, already clamped to their count.
    private(set) var allChatsPosition = 0
    var onChatsChanged: ((UUID?) -> Void)?
    var onIncomingMessage: ((Chat, Message) -> Void)?
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
    private var knownLastMessages: [Int64: UUID] = [:]
    private let openedAt = Int64(Date().timeIntervalSince1970 * 1000)

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

    func openChat(
        _ chat: Chat,
        onFailure: @escaping () -> Void = {},
        completion: @escaping () -> Void
    ) {
        perform(chatID: chat.id, origin: UUID(), operation: { [context] in
            try await context.storage.ensureConversation(StorageMapping.peer(chat))
            try await context.storage.markChatRead(peerID: Int64(chat.id))
        }, onFailure: onFailure, completion: completion)
    }

    func reply(
        to chat: Chat,
        text: String,
        completion: @escaping (Bool) -> Void
    ) {
        let timestamp = nextMessageTimestamp(chatID: chat.id)
        var message = Message(kind: .text(text), outgoing: true, time: StorageMapping.time(timestamp), read: false)
        message.timestamp = timestamp
        let reply = message
        perform(chatID: chat.id, origin: UUID(), operation: { [context] in
            try await context.storage.storeMessage(StorageMapping.local(reply, chatID: chat.id),
                                                    creating: StorageMapping.peer(chat), markingChatRead: true)
        }, onFailure: { completion(false) }, completion: { completion(true) })
    }

    /// Fixtures may be dated later today. Keep a new local message after the
    /// conversation's existing tail even before the future sync clock exists.
    func nextMessageTimestamp(chatID: Int) -> Int64 {
        let latest = chatState?.chats.first { $0.peer.id == Int64(chatID) }?.lastMessage?.timestamp ?? 0
        return max(Int64(Date().timeIntervalSince1970 * 1000), latest + 1)
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

    func createFolder(_ folder: ChatFolder, onFailure: @escaping () -> Void = {}, completion: @escaping () -> Void = {}) {
        let stored = StorageMapping.stored(folder)
        perform(chatID: nil, origin: UUID(), operation: { [context] in try await context.storage.createChatFolder(stored) },
                onFailure: onFailure, completion: completion)
    }

    func saveFolder(_ folder: ChatFolder, onFailure: @escaping () -> Void = {}, completion: @escaping () -> Void = {}) {
        let stored = StorageMapping.stored(folder)
        perform(chatID: nil, origin: UUID(), operation: { [context] in try await context.storage.updateChatFolder(stored) },
                onFailure: onFailure, completion: completion)
    }

    func deleteFolder(id: UUID, completion: @escaping () -> Void = {}) {
        perform(chatID: nil, origin: UUID(), operation: { [context] in try await context.storage.deleteChatFolder(id: id) },
                completion: completion)
    }

    func reorderFolders(_ ids: [UUID], allChatsPosition: Int, completion: @escaping () -> Void = {}) {
        perform(chatID: nil, origin: UUID(), operation: { [context] in
            try await context.storage.reorderChatFolders(ids, allChatsPosition: allChatsPosition)
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
                    let changed = self.chatState?.chats != state.chats || self.chatState?.folders != state.folders
                        || self.chatState?.allChatsPosition != state.allChatsPosition
                    try self.applyChats(state)
                    if changed { self.onChatsChanged?(nil) }
                }
            } catch { if !Task.isCancelled { self?.onError?(error) } }
        }
    }

    private func applyChats(_ state: StoredChatListState) throws {
        let mapped = try state.chats.map(StorageMapping.chat)
        let previous = Dictionary(uniqueKeysWithValues: (chatState?.chats ?? []).map { ($0.peer.id, $0) })
        var incoming: [(Chat, Message)] = []
        for (stored, chat) in zip(state.chats, mapped) {
            guard let message = stored.lastMessage else { continue }
            let known = knownLastMessages[stored.peer.id]
            knownLastMessages[stored.peer.id] = message.localID
            // The initial snapshot establishes a baseline. Edits, read receipts and
            // returning an old conversation to the list must not replay its banner.
            guard chatState != nil, known != message.localID,
                  !message.isOutgoing, message.isUnread, !stored.isMuted, chat.kind != .channel,
                  message.timestamp >= (previous[stored.peer.id]?.lastMessage?.timestamp ?? openedAt),
                  let value = try? StorageMapping.message(message) else { continue }
            incoming.append((chat, value))
        }
        chats = mapped
        let foldersChanged = chatState?.folders != state.folders || chatState?.allChatsPosition != state.allChatsPosition
        folders = state.folders.map(StorageMapping.folder)
        allChatsPosition = min(max(state.allChatsPosition, 0), folders.count)
        chatState = state
        if foldersChanged { NotificationCenter.default.post(name: Self.foldersDidChange, object: self) }
        for (chat, message) in incoming.sorted(by: { $0.1.timestamp < $1.1.timestamp }) {
            onIncomingMessage?(chat, message)
        }
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
                let changed = chatState?.chats != chats.chats || chatState?.folders != chats.folders
                    || chatState?.allChatsPosition != chats.allChatsPosition
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
