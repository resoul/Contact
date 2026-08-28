import Foundation

public struct SeasonvarMovieDetailDTO: Sendable {
    public let id: Int
    public let title: String
    public let originalTitle: String
    public let posterURL: String
    public let year: String
    public let country: String
    public let genres: [String]
    public let directors: [String]
    public let actors: [String]
    public let description: String
    public let ratingKP: String
    public let ratingIMDb: String
    public let movieURL: String
    public let seasons: [SeasonvarSeasonItemDTO]
    public let translations: [SeasonvarTranslationDTO]
    
    public init(
        id: Int,
        title: String,
        originalTitle: String,
        posterURL: String,
        year: String,
        country: String,
        genres: [String],
        directors: [String],
        actors: [String],
        description: String,
        ratingKP: String,
        ratingIMDb: String,
        movieURL: String,
        seasons: [SeasonvarSeasonItemDTO],
        translations: [SeasonvarTranslationDTO]
    ) {
        self.id = id
        self.title = title
        self.originalTitle = originalTitle
        self.posterURL = posterURL
        self.year = year
        self.country = country
        self.genres = genres
        self.directors = directors
        self.actors = actors
        self.description = description
        self.ratingKP = ratingKP
        self.ratingIMDb = ratingIMDb
        self.movieURL = movieURL
        self.seasons = seasons
        self.translations = translations
    }
}
