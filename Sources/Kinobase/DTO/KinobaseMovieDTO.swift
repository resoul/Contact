import Foundation

public struct KinobaseMovieDTO: Identifiable, Sendable {
    public let id: Int
    public let title: String
    public let year: String
    public let quality: String
    public let movieURL: String
    public let posterURL: String
    public let rating: String
    public let isSeries: Bool
    
    public init(
        id: Int,
        title: String,
        year: String,
        quality: String,
        movieURL: String,
        posterURL: String,
        rating: String,
        isSeries: Bool
    ) {
        self.id = id
        self.title = title
        self.year = year
        self.quality = quality
        self.movieURL = movieURL
        self.posterURL = posterURL
        self.rating = rating
        self.isSeries = isSeries
    }
}
