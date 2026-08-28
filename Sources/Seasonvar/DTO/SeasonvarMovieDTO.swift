import Foundation

public struct SeasonvarMovieDTO: Identifiable, Sendable {
    public let id: Int
    public let title: String
    public let url: String
    public let posterURL: String
    public let year: String
    public let genre: String
    public let rating: String
    
    public init(id: Int, title: String, url: String, posterURL: String, year: String, genre: String, rating: String) {
        self.id = id
        self.title = title
        self.url = url
        self.posterURL = posterURL
        self.year = year
        self.genre = genre
        self.rating = rating
    }
}
