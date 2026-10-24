import UIKit

enum MTReactions {
    static let gas = "💨"
    static let all = ["❤️", "👍", "🔥", "😂", "😮", "😢", "🎉", gas]
}

struct MTAccount {
    let person: ChannelPerson
    let phone: String
    let username: String
}

enum MTFolder: Int, CaseIterable {
    case all, personal, channels, bots

    var title: String {
        switch self {
        case .all: return "Все"
        case .personal: return "Личные"
        case .channels: return "Каналы"
        case .bots: return "Боты"
        }
    }
}

enum MTChatKind {
    case person, group, channel, bot
}

struct MTChat {
    let id: Int
    let person: ChannelPerson
    let kind: MTChatKind
    var message: String
    var time: String
    var unread = 0
    var muted = false
    var pinned = false
    /// Our last message: nil when the last message is theirs, false = delivered, true = read.
    var outgoingRead: Bool?
    var online = false

    static let fluidReactionsDemo = MTChat(id: -100, person: ChannelPerson(name: "Жидкие реакции", hue: 0.92),
                                          kind: .person, message: "Попробуй реакции как жидкость", time: "", online: true)

    func belongs(to folder: MTFolder) -> Bool {
        switch folder {
        case .all: return true
        case .personal: return kind == .person
        case .channels: return kind == .channel || kind == .group
        case .bots: return kind == .bot
        }
    }
}

