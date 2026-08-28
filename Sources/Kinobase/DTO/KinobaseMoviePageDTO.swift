import Foundation

public struct KinobaseMoviePageDTO: Sendable {
    public let movies: [KinobaseMovieDTO]
    public let nextPageURL: URL?
    
    public init(movies: [KinobaseMovieDTO], nextPageURL: URL?) {
        self.movies = movies
        self.nextPageURL = nextPageURL
    }
}
