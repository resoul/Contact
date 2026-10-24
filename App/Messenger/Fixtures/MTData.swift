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
        MTAccount(person: ChannelPerson(name: "Максим Ветров", hue: 0.6), phone: "+7 912 345-67-89", username: "@vetrov"),
        MTAccount(person: ChannelPerson(name: "Студия Ветров", hue: 0.83), phone: "+7 900 111-22-33", username: "@vetrov_studio"),
        MTAccount(person: ChannelPerson(name: "Макс Тест", hue: 0.12), phone: "+44 7700 900123", username: "@max_test"),
    ]

    static let storyUsers: [StoryUser] = trickPeople.prefix(7).enumerated().map { index, person in
        let scenes = DemoPhotos.Scene.allCases
        return StoryUser(person: person, photos: [scenes[index % scenes.count], scenes[(index + 3) % scenes.count]])
    }

    /// A different chat list for every account, so switching accounts visibly changes the screen.
    static func chats(for account: Int) -> [MTChat] {
        let people = trickPeople
        var chats: [MTChat] = [
            MTChat(id: 0, person: ChannelPerson(name: "Дизайн-команда", hue: 0.45), kind: .group,
                   message: "Анна: макеты таб-бара готовы, гляньте 👀", time: "21:04", unread: 12, pinned: true),
            MTChat(id: 1, person: people[0], kind: .person, message: "Завтра в 10 созвон, не забудь", time: "20:51",
                   unread: 2, online: true),
            MTChat(id: 2, person: people[1], kind: .person, message: "Отправил тебе файлы", time: "20:30",
                   outgoingRead: false),
            MTChat(id: 3, person: ChannelPerson(name: "Metal Weekly", hue: 0.02), kind: .channel,
                   message: "Шейдеры SDF: как сделать жидкость за 40 строк", time: "19:12", unread: 48, muted: true),
            MTChat(id: 4, person: people[2], kind: .person, message: "Ахах, это лучшее 😂", time: "18:40", online: true),
            MTChat(id: 5, person: ChannelPerson(name: "Погода Бот", hue: 0.55), kind: .bot,
                   message: "☀️ Завтра +18°, без осадков", time: "18:00", unread: 1),
            MTChat(id: 6, person: people[3], kind: .person, message: "Ок, договорились", time: "17:22", outgoingRead: true),
            MTChat(id: 7, person: ChannelPerson(name: "iOS Dev Chat", hue: 0.7), kind: .group,
                   message: "Игорь: кто пробовал iOS 27 beta?", time: "16:05", unread: 5, muted: true),
            MTChat(id: 8, person: people[4], kind: .person, message: "Фото с выходных 📷", time: "15:47", unread: 3),
            MTChat(id: 9, person: ChannelPerson(name: "Новости Tech", hue: 0.1), kind: .channel,
                   message: "Apple показала новые MacBook", time: "14:30", unread: 210, muted: true),
            MTChat(id: 10, person: people[5], kind: .person, message: "Голосовое сообщение", time: "13:02", outgoingRead: true),
            MTChat(id: 11, person: ChannelPerson(name: "Такси Бот", hue: 0.15), kind: .bot,
                   message: "Ваша поездка завершена. Оцените водителя", time: "12:15"),
            MTChat(id: 12, person: people[6], kind: .person, message: "Спасибо!", time: "Вчера", online: true),
            MTChat(id: 13, person: people[7], kind: .person, message: "Где встречаемся?", time: "Вчера", unread: 1),
            MTChat(id: 14, person: people[8], kind: .person, message: "Стикер", time: "Пн", outgoingRead: true),
            MTChat(id: 15, person: people[9], kind: .person, message: "До встречи 👋", time: "Вс"),
        ]
        guard account > 0 else { return chats }
        // Other accounts: another order, other counters, fewer chats.
        var generator = SplitMix(seed: UInt64(account * 977))
        chats = chats.filter { _ in generator.next() > 0.3 }
        for index in chats.indices {
            chats[index].unread = generator.next() > 0.5 ? Int(generator.next() * 30) : 0
            chats[index].pinned = index == 0
        }
        // Pinned first, the rest in a seeded order.
        return [chats[0]] + chats.dropFirst().map { ($0, generator.next()) }.sorted { $0.1 < $1.1 }.map(\.0)
    }

    static let pinnedMessages = [
        "📌 Правила чата: без спама",
        "Ссылка на макеты в Figma",
        "Созвон по пятницам в 11:00",
        "Релиз 2.0 — 1 ноября 🚀",
    ]
}

