import Foundation

public struct SeasonvarRawEpisodeDTO: Codable, Sendable {
    public let title: String
    public let file: String
    public let id: String
    public let subtitle: String?
}

public struct SeasonvarEpisodeDTO: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let videoURL: String
    public let subtitleURL: String?
    
    public init(id: String, title: String, videoURL: String, subtitleURL: String? = nil) {
        self.id = id
        self.title = title
        self.videoURL = videoURL
        self.subtitleURL = subtitleURL
    }
}
