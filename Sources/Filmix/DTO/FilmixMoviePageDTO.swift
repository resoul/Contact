import Foundation

public struct FilmixMoviePageDTO {
    public let movies: [FilmixMovieDTO]
    public let nextPageURL: URL?
    
    public init(movies: [FilmixMovieDTO], nextPageURL: URL?) {
        self.movies = movies
        self.nextPageURL = nextPageURL
    }
}
