import Foundation

public struct KinobaseMovieFrameDTO: Sendable {
    public let thumbURL: String
    public let fullURL: String
    
    public init(thumbURL: String, fullURL: String) {
        self.thumbURL = thumbURL
        self.fullURL = fullURL
    }
}
