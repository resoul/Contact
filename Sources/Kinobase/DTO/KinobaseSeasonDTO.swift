import Foundation

public struct KinobaseSeasonDTO: Sendable {
    public let title: String
    public let episodes: [KinobaseEpisodeDTO]
    
    public init(title: String, episodes: [KinobaseEpisodeDTO]) {
        self.title = title
        self.episodes = episodes
    }
}
