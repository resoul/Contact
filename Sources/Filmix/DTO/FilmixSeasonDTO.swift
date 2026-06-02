import Foundation

public struct FilmixSeasonDTO {
    public let title: String
    public let episodes: [FilmixEpisodeDTO]
    
    public nonisolated init(title: String, episodes: [FilmixEpisodeDTO]) {
        self.title = title
        self.episodes = episodes
    }
}
