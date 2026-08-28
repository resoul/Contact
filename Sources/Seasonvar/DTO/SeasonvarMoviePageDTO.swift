import Foundation

public struct SeasonvarMoviePageDTO: Sendable {
    public let movies: [SeasonvarMovieDTO]
    public let nextPageURL: URL?
    
    public init(movies: [SeasonvarMovieDTO], nextPageURL: URL?) {
        self.movies = movies
        self.nextPageURL = nextPageURL
    }
}
