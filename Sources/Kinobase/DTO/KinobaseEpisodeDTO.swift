import Foundation

public struct KinobaseEpisodeDTO: Sendable {
    public let title: String
    public let id: String
    public let streams: [String: [String]] // [Quality: [m3u8 mirrors]]
    
    public init(title: String, id: String, streams: [String: [String]]) {
        self.title = title
        self.id = id
        self.streams = streams
    }
}
