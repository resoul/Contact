import Foundation

public struct FilmixMovieDetailDTO {
    public let id: Int
    public let movieURL: String
    public let posterThumb: String
    public let posterFull: String
    public let title: String
    public let originalTitle: String
    public let quality: String
    public let date: String
    public let dateISO: String
    public let year: String
    public let durationMinutes: Int?
    public let mpaa: String
    public let slogan: String
    public let statusOnAir: String?
    public let statusHint: String?
    public let lastAdded: String?
    public let directors: [String]
    public let actors: [String]
    public let writers: [String]
    public let producers: [String]
    public let genres: [String]
    public let countries: [String]
    public let translate: String
    public let description: String
    public let isAdIn: Bool
    public let isNotMovie: Bool
    public let frames: [FilmixMovieFrameDTO]
    public let kinopoiskRating: String
    public let kinopoiskVotes: String
    public let imdbRating: String
    public let imdbVotes: String
    public let userPositivePercent: Int
    public let userLikes: Int
    public let userDislikes: Int
    
    public init(
        id: Int, movieURL: String,
        posterThumb: String, posterFull: String,
        title: String, originalTitle: String,
        quality: String, date: String, dateISO: String,
        year: String, durationMinutes: Int?,
        mpaa: String, slogan: String,
        statusOnAir: String?, statusHint: String?, lastAdded: String?,
        directors: [String], actors: [String],
        writers: [String], producers: [String],
        genres: [String], countries: [String],
        translate: String, description: String,
        isAdIn: Bool, isNotMovie: Bool, frames: [FilmixMovieFrameDTO],
        kinopoiskRating: String, kinopoiskVotes: String,
        imdbRating: String, imdbVotes: String,
        userPositivePercent: Int, userLikes: Int, userDislikes: Int
    ) {
        self.id = id; self.movieURL = movieURL
        self.posterThumb = posterThumb; self.posterFull = posterFull
        self.title = title; self.originalTitle = originalTitle
        self.quality = quality; self.date = date; self.dateISO = dateISO
        self.year = year; self.durationMinutes = durationMinutes
        self.mpaa = mpaa; self.slogan = slogan
        self.statusOnAir = statusOnAir; self.statusHint = statusHint; self.lastAdded = lastAdded
        self.directors = directors; self.actors = actors
        self.writers = writers; self.producers = producers
        self.genres = genres; self.countries = countries
        self.translate = translate; self.description = description
        self.isAdIn = isAdIn; self.isNotMovie = isNotMovie; self.frames = frames
        self.kinopoiskRating = kinopoiskRating; self.kinopoiskVotes = kinopoiskVotes
        self.imdbRating = imdbRating; self.imdbVotes = imdbVotes
        self.userPositivePercent = userPositivePercent
        self.userLikes = userLikes; self.userDislikes = userDislikes
    }
    
    public var isSeries: Bool {
        statusOnAir != nil || lastAdded != nil || year.contains("Сезон")
    }
    
    public var durationFormatted: String {
        guard let m = durationMinutes, m > 0 else { return quality }
        let h = m / 60, min = m % 60
        let base = h > 0 ? "\(h)ч \(min)м" : "\(min)м"
        return isSeries ? "\(base)/серия" : base
    }
    
    public var userRating: String {
        let total = userLikes + userDislikes
        guard total > 0 else { return "—" }
        return String(format: "%.1f", Double(userLikes) / Double(total) * 10)
    }
}
