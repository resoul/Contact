import UIKit
import ContactStorage

struct ChatIdentity: Codable {
    let person: ChannelPerson
    let online: Bool
}

struct MessageSection {
    var title: String
    var messages: [Message]
}

struct ReadingPosition: Codable {
    var position: CGFloat
    var anchorMessageID: Int?
    var anchorOffset: CGFloat
    var atBottom: Bool
    init(_ state: ChannelReadingState) {
        position = state.position; anchorMessageID = state.anchorMessageID
        anchorOffset = state.anchorOffset; atBottom = state.atBottom
    }
    func state(sections: [(title: String, messages: [Message])]) -> ChannelReadingState {
        ChannelReadingState(sections: sections, position: position, anchorMessageID: anchorMessageID,
                              anchorOffset: anchorOffset, atBottom: atBottom)
    }
}

enum StorageMapping {
    static func peer(_ chat: Chat) throws -> StoragePeer {
        StoragePeer(id: Int64(chat.id), kind: PeerKind(rawValue: chat.kind.rawValue)!, displayName: chat.person.name,
                    presentation: try JSONEncoder().encode(ChatIdentity(person: chat.person, online: chat.online)))
    }

    static func local(_ message: Message, chatID: Int, unread: Bool = false, seeded: Bool = false, state: MessageState? = nil) throws -> LocalMessage {
        LocalMessage(id: message.storageID, peerID: Int64(chatID), timestamp: message.timestamp,
                     text: message.channelPost?.body ?? message.text ?? message.summary, outgoing: message.outgoing,
                     unread: unread, state: state ?? (message.outgoing ? (message.read ? .read : seeded ? .sent : .pending) : .received),
                     presentation: try JSONEncoder().encode(message))
    }

    static func message(_ stored: StoredMessage) throws -> Message {
        var value: Message
        if let payload = stored.presentation { value = try JSONDecoder().decode(Message.self, from: payload) }
        else { value = Message(kind: .text(stored.text), outgoing: stored.isOutgoing, time: time(stored.timestamp)) }
        value.storageID = stored.localID
        value.timestamp = stored.timestamp
        value.time = time(stored.timestamp)
        value.outgoing = stored.isOutgoing
        value.read = stored.state == .read
        value.edited = value.edited || stored.editedAt != nil
        if case .text = value.kind { value.kind = .text(stored.text) }
        if value.channelPost != nil { value.channelPost?.body = stored.text }
        return value
    }

    static func chat(_ stored: StoredChat) throws -> Chat {
        let identity = try stored.peer.presentation.map { try JSONDecoder().decode(ChatIdentity.self, from: $0) }
        let last = try stored.lastMessage.map(message)
        return Chat(id: Int(stored.peer.id), person: identity?.person ?? ChannelPerson(name: stored.peer.displayName, hue: 0.6),
                      kind: ChatKind(rawValue: stored.peer.kind.rawValue)!, message: last?.summary ?? "",
                      time: last?.time ?? "", unread: max(stored.unreadCount, stored.manuallyUnread ? 1 : 0),
                      muted: stored.isMuted, pinned: stored.isPinned,
                      outgoingRead: last?.outgoing == true ? last?.read : nil, online: identity?.online ?? false)
    }

    static func sections(_ messages: [Message]) -> [MessageSection] {
        var result: [MessageSection] = []
        for message in messages.sorted(by: { ($0.timestamp, $0.storageID.uuidString) < ($1.timestamp, $1.storageID.uuidString) }) {
            let title = day(message.timestamp)
            if result.last?.title != title { result.append(MessageSection(title: title, messages: [])) }
            result[result.count - 1].messages.append(message)
        }
        return result.isEmpty ? [MessageSection(title: "Today", messages: [])] : result
    }

    static func time(_ timestamp: Int64) -> String {
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: Double(timestamp) / 1000))
    }

    static func day(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(timestamp) / 1000)
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US"); formatter.dateFormat = "d MMMM"
        return formatter.string(from: date)
    }
}

enum FixtureSeeder {
    @MainActor static func seedIfNeeded(storage: AccountStorage, account: Int) async throws {
        guard try await !storage.hasFixtureSeed() else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var conversations: [SeedConversation] = []
        for chat in MessengerData.chats(for: account) {
            var messages: [Message] = []
            for section in ChatScript.sections(for: chat) {
                let date: Date
                if section.title == "Today" { date = today }
                else if section.title == "Yesterday" { date = calendar.date(byAdding: .day, value: -1, to: today)! }
                else {
                    let day = Int(section.title.split(separator: " ").first ?? "") ?? 18
                    date = calendar.date(from: DateComponents(year: calendar.component(.year, from: today), month: 10, day: day))!
                }
                for (index, original) in section.messages.enumerated() where !original.isDivider {
                    var message = original
                    let components = message.time.split(separator: ":").compactMap { Int($0) }
                    let instant = calendar.date(bySettingHour: components.count == 2 ? components[0] : 0,
                                                minute: components.count == 2 ? components[1] : index,
                                                second: 0, of: date)!
                    message.timestamp = Int64(instant.timeIntervalSince1970 * 1000) + Int64(index)
                    messages.append(message)
                }
            }
            let unreadIDs = Set(messages.filter { !$0.outgoing }.suffix(chat.unread).map(\.storageID))
            let inputs = try messages.map { try StorageMapping.local($0, chatID: chat.id, unread: unreadIDs.contains($0.storageID), seeded: true) }
            conversations.append(SeedConversation(peer: try StorageMapping.peer(chat), muted: chat.muted, pinned: chat.pinned, messages: inputs))
        }
        try await storage.seedFixturesIfNeeded(conversations)
    }
}
