import Foundation

public struct SeasonvarTranslationDTO: Identifiable, Sendable {
    public let id: String                    // e.g. "0", "2", "242", "1"
    public let studio: String                // e.g. "LostFilm", "RuDub", "HDRezka", "Subtitles"
    public let playlistPath: String          // e.g. "/playls2/cfab.../transLostFilm/38457/plist.txt?time=..."
    public var episodes: [SeasonvarEpisodeDTO]
    
    public init(id: String, studio: String, playlistPath: String, episodes: [SeasonvarEpisodeDTO] = []) {
        self.id = id
        self.studio = studio
        self.playlistPath = playlistPath
        self.episodes = episodes
    }
}
