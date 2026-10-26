import Foundation

/// Match fixture people rather than chat IDs, including identities restored from storage.
enum MessengerAvatarFixtures {
    enum Media {
        case photo, video
    }

    private static let assignments: [(person: ChannelPerson, media: Media)] = [
        (trickPeople[0], .video), // Анна Смирнова
        (trickPeople[2], .photo), // Катя Лебедева
    ]

    static func media(for person: ChannelPerson) -> Media? {
        assignments.first { $0.person.name == person.name && $0.person.hue == person.hue }?.media
    }
}
