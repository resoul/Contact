import Foundation

public struct FilmixMovieDTO: Identifiable, Hashable {
    public let id: Int
    public let title: String
    public let originalTitle: String
    public let year: String
    public let description: String
    public let genre: String
    public let genreList: [String]
    public let rating: String
    public let duration: String
    public let type: ContentType
    public let translate: String
    public let isAdIn: Bool
    public let movieURL: String
    public let posterURL: String
    public let actors: [String]
    public let directors: [String]
    public let lastAdded: String?
    
    public init(
        id: Int, title: String, originalTitle: String,
        year: String, description: String,
        genre: String, genreList: [String],
        rating: String, duration: String,
        type: ContentType, translate: String, isAdIn: Bool,
        movieURL: String, posterURL: String,
        actors: [String], directors: [String], lastAdded: String?
    ) {
        self.id = id; self.title = title; self.originalTitle = originalTitle
        self.year = year; self.description = description
        self.genre = genre; self.genreList = genreList
        self.rating = rating; self.duration = duration
        self.type = type; self.translate = translate; self.isAdIn = isAdIn
        self.movieURL = movieURL; self.posterURL = posterURL
        self.actors = actors; self.directors = directors; self.lastAdded = lastAdded
    }
    
    public enum ContentType: Hashable {
        case movie
        case series(seasons: [FilmixSeasonDTO])

        public var isSeries: Bool {
            if case .series = self { return true }
            return false
        }

        public static func == (lhs: ContentType, rhs: ContentType) -> Bool {
            switch (lhs, rhs) {
            case (.movie, .movie): return true
            case (.series, .series): return true
            default: return false
            }
        }

        public func hash(into hasher: inout Hasher) {
            switch self {
            case .movie:   hasher.combine(0)
            case .series:  hasher.combine(1)
            }
        }
    }
}
