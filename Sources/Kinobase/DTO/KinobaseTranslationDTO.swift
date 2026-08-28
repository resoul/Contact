import Foundation

public struct KinobaseTranslationDTO: Sendable {
    public let studio: String
    public let streams: [String: [String]]       // [Quality ("1080p", "720p"): [m3u8 mirrors]]
    public let subtitles: [String: [String]]     // [Subtitle language: [vtt mirrors]]
    public let seasons: [KinobaseSeasonDTO]
    
    public init(
        studio: String,
        streams: [String: [String]],
        subtitles: [String: [String]] = [:],
        seasons: [KinobaseSeasonDTO] = []
    ) {
        self.studio = studio
        self.streams = streams
        self.subtitles = subtitles
        self.seasons = seasons
    }
    
    public var isSeries: Bool { !seasons.isEmpty }
    
    public var sortedQualities: [String] {
        let order = ["2160p", "4K UHD", "1080p", "720p", "480p", "360p"]
        let known = order.filter { streams[$0] != nil }
        let unknown = streams.keys.filter { !order.contains($0) }.sorted()
        return known + unknown
    }

    public var bestQuality: String? { sortedQualities.first }
    public var bestURL: String? {
        bestQuality.flatMap { streams[$0]?.first }
    }
}
