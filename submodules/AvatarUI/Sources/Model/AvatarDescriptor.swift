import UIKit

public struct AvatarDescriptor {
    public let id: String
    public let version: Int
    public let initials: String
    public let colors: [UIColor]
    public let image: AvatarResource?
    public let video: AvatarVideo?
    public let thumbnailVideo: AvatarVideo?

    public init(id: String, version: Int = 1, initials: String, colors: [UIColor],
                image: AvatarResource? = nil, video: AvatarVideo? = nil, thumbnailVideo: AvatarVideo? = nil) {
        self.id = id
        self.version = version
        self.initials = String(initials.prefix(2))
        self.colors = colors.isEmpty ? [.systemBlue, .systemIndigo] : colors
        self.image = image
        self.video = video
        self.thumbnailVideo = thumbnailVideo
    }
}

public enum AvatarPresentation {
    case thumbnail
    case chatList
    case profile
    case gallery

    var priority: Int {
        switch self {
        case .thumbnail: return 0
        case .chatList: return 1
        case .profile: return 10
        case .gallery: return 20
        }
    }
}

public enum AvatarDisplayState: String {
    case initials, photo, video, unavailable
}
