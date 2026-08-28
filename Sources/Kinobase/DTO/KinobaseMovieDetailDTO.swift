import Foundation

public struct KinobaseMovieDetailDTO: Sendable {
    public let id: Int
    public let identifier: String
    public let playerCUID: String
    public let movieURL: String
    public let posterThumb: String
    public let posterFull: String
    public let title: String
    public let originalTitle: String
    public let year: String
    public let durationMinutes: Int?
    public let trailerURL: String?
    public let directors: [String]
    public let actors: [String]
    public let writers: [String]
    public let producers: [String]
    public let genres: [String]
    public let countries: [String]
    public let description: String
    public let frames: [KinobaseMovieFrameDTO]
    public let kinopoiskRating: String
    public let kinopoiskVotes: String
    public let imdbRating: String
    public let imdbVotes: String
    public let isSeries: Bool
    
    public init(
        id: Int,
        identifier: String,
        playerCUID: String,
        movieURL: String,
        posterThumb: String,
        posterFull: String,
        title: String,
        originalTitle: String,
        year: String,
        durationMinutes: Int?,
        trailerURL: String?,
        directors: [String],
        actors: [String],
        writers: [String],
        producers: [String],
        genres: [String],
        countries: [String],
        description: String,
        frames: [KinobaseMovieFrameDTO],
        kinopoiskRating: String,
        kinopoiskVotes: String,
        imdbRating: String,
        imdbVotes: String,
        isSeries: Bool
    ) {
        self.id = id
        self.identifier = identifier
        self.playerCUID = playerCUID
        self.movieURL = movieURL
        self.posterThumb = posterThumb
        self.posterFull = posterFull
        self.title = title
        self.originalTitle = originalTitle
        self.year = year
        self.durationMinutes = durationMinutes
        self.trailerURL = trailerURL
        self.directors = directors
        self.actors = actors
        self.writers = writers
        self.producers = producers
        self.genres = genres
        self.countries = countries
        self.description = description
        self.frames = frames
        self.kinopoiskRating = kinopoiskRating
        self.kinopoiskVotes = kinopoiskVotes
        self.imdbRating = imdbRating
        self.imdbVotes = imdbVotes
        self.isSeries = isSeries
    }
    
    public var durationFormatted: String {
        guard let m = durationMinutes, m > 0 else { return "" }
        let h = m / 60, min = m % 60
        let base = h > 0 ? "\(h)ч \(min)м" : "\(min)м"
        return isSeries ? "\(base)/серия" : base
    }
}
