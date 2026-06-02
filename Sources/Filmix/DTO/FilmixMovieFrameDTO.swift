import Foundation

public struct FilmixMovieFrameDTO {
    public let thumbURL: String
    public let fullURL: String
    
    public init(thumbURL: String, fullURL: String) {
        self.thumbURL = thumbURL
        self.fullURL = fullURL
    }
}
