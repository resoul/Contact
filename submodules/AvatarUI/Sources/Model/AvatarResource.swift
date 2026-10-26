import Foundation

public struct AvatarResource: Hashable, Codable, Sendable {
    public let id: String
    public let version: Int
    public let url: URL

    public init(id: String, version: Int = 1, url: URL) {
        self.id = id
        self.version = version
        self.url = url
    }
}

public struct AvatarVideo: Hashable, Codable, Sendable {
    public static let maximumDuration: Double = 10
    public let resource: AvatarResource
    public let startTimestamp: Double

    public init(resource: AvatarResource, startTimestamp: Double = 0) {
        self.resource = resource
        self.startTimestamp = startTimestamp.isFinite ? max(0, startTimestamp) : 0
    }
}
