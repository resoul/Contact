import UIKit

/// Chat types a folder can take in whole, as in Telegram's folder editor.
enum ChatFolderType: CaseIterable {
    case contacts, nonContacts, groups, channels, bots

    var title: String {
        switch self {
        case .contacts: return "Contacts"
        case .nonContacts: return "Non-Contacts"
        case .groups: return "Groups"
        case .channels: return "Channels"
        case .bots: return "Bots"
        }
    }

    var symbol: String {
        switch self {
        case .contacts: return "person.fill"
        case .nonContacts: return "person.fill.questionmark"
        case .groups: return "person.2.fill"
        case .channels: return "megaphone.fill"
        case .bots: return "cpu"
        }
    }

    var color: UIColor {
        switch self {
        case .contacts: return .systemBlue
        case .nonContacts: return .systemOrange
        case .groups: return .systemGreen
        case .channels: return .systemRed
        case .bots: return .systemPurple
        }
    }

    func matches(_ chat: Chat) -> Bool {
        switch self {
        case .contacts: return chat.kind == .person && ChatFolder.isContact(chat)
        case .nonContacts: return chat.kind == .person && !ChatFolder.isContact(chat)
        case .groups: return chat.kind == .group
        case .channels: return chat.kind == .channel
        case .bots: return chat.kind == .bot
        }
    }
}

/// Chat types a folder leaves out. Archived chats never reach the chat list here,
/// so Telegram's "Archived" exclusion has nothing to act on yet.
enum ChatFolderExclusion: CaseIterable {
    case muted, read

    var title: String { self == .muted ? "Muted" : "Read" }
    var symbol: String { self == .muted ? "bell.slash.fill" : "checkmark.message.fill" }
    var color: UIColor { self == .muted ? .systemIndigo : .systemTeal }
}

/// A chat folder of the current account, stored in its database.
struct ChatFolder: Identifiable, Equatable {
    /// Telegram's peer name colors, by stored index.
    static let colors: [UIColor] = [
        UIColor(red: 0.89, green: 0.33, blue: 0.29, alpha: 1), UIColor(red: 0.91, green: 0.53, blue: 0.20, alpha: 1),
        UIColor(red: 0.62, green: 0.40, blue: 0.87, alpha: 1), UIColor(red: 0.30, green: 0.72, blue: 0.27, alpha: 1),
        UIColor(red: 0.18, green: 0.67, blue: 0.78, alpha: 1), UIColor(red: 0.21, green: 0.55, blue: 0.89, alpha: 1),
        UIColor(red: 0.85, green: 0.33, blue: 0.62, alpha: 1),
    ]
    /// Palette order on screen, as in Telegram: blue, green, orange, red, violet, cyan, pink.
    static let colorOrder = [5, 3, 1, 0, 2, 4, 6]

    let id: UUID
    var name: String
    var emoji: String?
    var color: Int?
    var types: Set<ChatFolderType> = []
    var exclusions: Set<ChatFolderExclusion> = []
    /// Always shown, whatever `types` and the exclusions say.
    var included: Set<Int> = []
    /// Never shown, even when a type or an explicit include matches.
    var excluded: Set<Int> = []

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }

    var isEmpty: Bool { types.isEmpty && included.isEmpty }
    var tint: UIColor? { color.flatMap { Self.colors.indices.contains($0) ? Self.colors[$0] : nil } }

    /// Telegram's filter rule: exclusions first, then explicit includes, then types
    /// with the muted/read exclusions.
    func contains(_ chat: Chat) -> Bool {
        if excluded.contains(chat.id) { return false }
        if included.contains(chat.id) { return true }
        guard types.contains(where: { $0.matches(chat) }) else { return false }
        if exclusions.contains(.muted) && chat.muted { return false }
        if exclusions.contains(.read) && chat.unread == 0 { return false }
        return true
    }

    /// Prototype contacts are the people of the Contacts tab.
    private static let contactNames = Set(trickPeople.map(\.name))
    static func isContact(_ chat: Chat) -> Bool { contactNames.contains(chat.person.name) }
}
