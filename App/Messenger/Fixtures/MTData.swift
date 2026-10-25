import UIKit

// Local fixtures for the messenger prototype. Replace this source when storage/networking is added.
let trickPeople = [
    ChannelPerson(name: "Анна Смирнова", hue: 0.93), ChannelPerson(name: "Михаил Орлов", hue: 0.58),
    ChannelPerson(name: "Катя Лебедева", hue: 0.08), ChannelPerson(name: "Игорь Ким", hue: 0.36),
    ChannelPerson(name: "Ольга Белова", hue: 0.75), ChannelPerson(name: "Дмитрий Волков", hue: 0.15),
    ChannelPerson(name: "Софья Ли", hue: 0.5), ChannelPerson(name: "Рустам Ахмедов", hue: 0.02),
    ChannelPerson(name: "Вера Ким", hue: 0.66), ChannelPerson(name: "Лев Гордон", hue: 0.27),
]

enum MTData {
    static let accounts = [
        MTAccount(id: UUID(uuidString: "e385df1b-e640-40d2-bc78-d5556e6484b1")!, person: ChannelPerson(name: "Максим Ветров", hue: 0.6), phone: "+7 912 345-67-89", username: "@vetrov"),
        MTAccount(id: UUID(uuidString: "0c158ca4-230c-4688-9f84-dc8690182eba")!, person: ChannelPerson(name: "Студия Ветров", hue: 0.83), phone: "+7 900 111-22-33", username: "@vetrov_studio"),
        MTAccount(id: UUID(uuidString: "f8292fc4-0abd-4d9e-a1c8-eb94de3648e3")!, person: ChannelPerson(name: "Макс Тест", hue: 0.12), phone: "+44 7700 900123", username: "@max_test"),
    ]

    static let storyUsers: [StoryUser] = trickPeople.prefix(7).enumerated().map { index, person in
        let scenes = DemoPhotos.Scene.allCases
        return StoryUser(person: person, photos: [scenes[index % scenes.count], scenes[(index + 3) % scenes.count]])
    }

    /// A different chat list for every account, so switching accounts visibly changes the screen.
    static func chats(for account: Int) -> [MTChat] {
        let people = trickPeople
        var chats: [MTChat] = [
            MTChat(id: 0, person: ChannelPerson(name: "Design Team", hue: 0.45), kind: .group,
                   message: "Anna: the tab bar mockups are ready, take a look 👀", time: "21:04", unread: 12, pinned: true),
            MTChat(id: 1, person: people[0], kind: .person, message: "Call tomorrow at 10, don’t forget", time: "20:51",
                   unread: 2, online: true),
            MTChat(id: 2, person: people[1], kind: .person, message: "I sent you the files", time: "20:30",
                   outgoingRead: false),
            channelExamples[0],
            MTChat(id: 4, person: people[2], kind: .person, message: "Haha, this is the best 😂", time: "18:40", online: true),
            MTChat(id: 5, person: ChannelPerson(name: "Weather Bot", hue: 0.55), kind: .bot,
                   message: "☀️ Tomorrow: 18°, no rain", time: "18:00", unread: 1),
            MTChat(id: 6, person: people[3], kind: .person, message: "Okay, it’s a deal", time: "17:22", outgoingRead: true),
            MTChat(id: 7, person: ChannelPerson(name: "iOS Dev Chat", hue: 0.7), kind: .group,
                   message: "Igor: has anyone tried iOS 27 beta?", time: "16:05", unread: 5, muted: true),
            MTChat(id: 8, person: people[4], kind: .person, message: "Photos from the weekend 📷", time: "15:47", unread: 3),
            channelExamples[1],
            MTChat(id: 10, person: people[5], kind: .person, message: "Voice message", time: "13:02", outgoingRead: true),
            MTChat(id: 11, person: ChannelPerson(name: "Taxi Bot", hue: 0.15), kind: .bot,
                   message: "Your ride is complete. Rate your driver", time: "12:15"),
            MTChat(id: 12, person: people[6], kind: .person, message: "Thanks!", time: "Yesterday", online: true),
            MTChat(id: 13, person: people[7], kind: .person, message: "Where should we meet?", time: "Yesterday", unread: 1),
            MTChat(id: 14, person: people[8], kind: .person, message: "Sticker", time: "Mon", outgoingRead: true),
            MTChat(id: 15, person: people[9], kind: .person, message: "See you 👋", time: "Sun"),
        ]
        chats += Array(channelExamples.dropFirst(2))
        guard account > 0 else { return chats }
        // Other accounts: another order, other counters, fewer chats.
        var generator = SplitMix(seed: UInt64(account * 977))
        chats = chats.filter { $0.kind == .channel || generator.next() > 0.3 }
        for index in chats.indices {
            chats[index].unread = generator.next() > 0.5 ? Int(generator.next() * 30) : 0
            chats[index].pinned = index == 0
        }
        // Pinned first, the rest in a seeded order.
        return [chats[0]] + chats.dropFirst().map { ($0, generator.next()) }.sorted { $0.1 < $1.1 }.map(\.0)
    }

    static let pinnedMessages = [
        "📌 Chat rules: no spam",
        "Link to the Figma designs",
        "Friday call at 11:00",
        "Release 2.0 — November 1 🚀",
    ]
}

