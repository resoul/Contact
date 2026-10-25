import UIKit

enum Reactions {
    static let gas = "💨"
    static let all = ["❤️", "👍", "🔥", "😂", "😮", "😢", "🎉", gas]
}

struct Account {
    let id: UUID
    let person: ChannelPerson
    let phone: String
    let username: String
}

enum Folder: Int, CaseIterable {
    case all, personal, channels, bots

    var title: String {
        switch self {
        case .all: return "All"
        case .personal: return "Personal"
        case .channels: return "Channels"
        case .bots: return "Bots"
        }
    }
}

enum ChatKind: String, Codable {
    case person, group, channel, bot
}

struct Chat {
    let id: Int
    let person: ChannelPerson
    let kind: ChatKind
    var message: String
    var time: String
    var unread = 0
    var muted = false
    var pinned = false
    /// Our last message: nil when the last message is theirs, false = delivered, true = read.
    var outgoingRead: Bool?
    var online = false

    static let fluidReactionsDemo = Chat(id: -100, person: ChannelPerson(name: "Fluid Reactions", hue: 0.92),
                                          kind: .person, message: "Try reactions as fluid", time: "", online: true)

    func belongs(to folder: Folder) -> Bool {
        switch folder {
        case .all: return true
        case .personal: return kind == .person
        case .channels: return kind == .channel || kind == .group
        case .bots: return kind == .bot
        }
    }
}

