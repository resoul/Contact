import Foundation
import SwiftSoup

public enum KinobaseHTMLParser {
    public static func parseListing(html: String) throws -> KinobaseMoviePageDTO {
        let doc = try SwiftSoup.parse(html)
        let items = try doc.select("ul.items li.item, .movie_items .item")
        
        let movies: [KinobaseMovieDTO] = items.array().enumerated().compactMap { index, item in
            try? parseListingItem(item: item, index: index)
        }
        
        let nextPageURL = try? parseNextPageURL(doc: doc)
        return KinobaseMoviePageDTO(movies: movies, nextPageURL: nextPageURL)
    }

    private static func parseListingItem(item: Element, index: Int) throws -> KinobaseMovieDTO {
        let titleEl = try item.select(".title a").first()
        let title = (try? titleEl?.text()) ?? "Unknown"
        let href = (try? titleEl?.attr("href")) ?? ""
        let movieURL = href.hasPrefix("http") ? href : "https://kinobase.org\(href)"
        
        let posterEl = try item.select(".poster img").first()
        let posterRaw = (try? posterEl?.attr("src")) ?? ""
        let posterURL = posterRaw.hasPrefix("http") ? posterRaw : "https://kinobase.org\(posterRaw)"
        
        let yearText = (try? item.select("span.year").text()) ?? ""
        let rating = (try? item.select("span.rating").text()) ?? ""
        
        var id = index
        let favId = try? item.select("button.favorite").attr("data-movie-id")
        if let favId = favId, let intId = Int(favId) {
            id = intId
        } else {
            let regex = try? NSRegularExpression(pattern: "/(?:film|serial|tv)/(\\d+)")
            if let match = regex?.firstMatch(in: href, range: NSRange(href.startIndex..., in: href)),
               let r = Range(match.range(at: 1), in: href),
               let parsedId = Int(href[r]) {
                id = parsedId
            }
        }
        
        let isSeries = href.contains("/serial/") || href.contains("/serials") || href.contains("/tv") || href.contains("/animation") || yearText.contains("сезон")
        let quality = yearText.components(separatedBy: ",").last?.trimmingCharacters(in: .whitespaces) ?? ""
        let year = yearText.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? yearText
        
        return KinobaseMovieDTO(
            id: id,
            title: title,
            year: year,
            quality: quality,
            movieURL: movieURL,
            posterURL: posterURL,
            rating: rating,
            isSeries: isSeries
        )
    }

    public static func parseDetail(html: String, movieURL: String) throws -> KinobaseMovieDetailDTO {
        let doc = try SwiftSoup.parse(html)
        
        let title = (try? doc.select("#title h1").text()) ?? ""
        let originalTitle = (try? doc.select("div.value[itemprop=alternativeHeadline]").text()) ?? ""
        
        let posterSrc = (try? doc.select("#media .poster img").attr("src")) ?? ""
        let posterFull = posterSrc.hasPrefix("http") ? posterSrc : "https://kinobase.org\(posterSrc)"
        let posterThumb = posterFull.replacingOccurrences(of: "360x534", with: "180x267")
        
        let desc = (try? doc.select("#content_description .description").text()) ?? ""
        
        // JavaScript runtime variables
        let scripts = try doc.select("script").array().map { try? $0.html() }.compactMap { $0 }
        var movId = 0
        var identifier = ""
        var playerCUID = ""
        var trailer = ""
        
        let trimChars = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"; "))
        
        for script in scripts {
            if script.contains("MOV_ID") {
                if let m = script.range(of: #"MOV_ID\s*=\s*(\d+)"#, options: .regularExpression) {
                    let num = script[m].components(separatedBy: "=").last?.trimmingCharacters(in: trimChars)
                    movId = Int(num ?? "") ?? 0
                }
            }
            if script.contains("IDENTIFIER") {
                if let m = script.range(of: #"IDENTIFIER\s*=\s*"([^"]+)""#, options: .regularExpression) {
                    let raw = script[m].components(separatedBy: "=").last?.trimmingCharacters(in: trimChars)
                    identifier = raw ?? ""
                }
            }
            if script.contains("PLAYER_CUID") {
                if let m = script.range(of: #"PLAYER_CUID\s*=\s*"([^"]+)""#, options: .regularExpression) {
                    let raw = script[m].components(separatedBy: "=").last?.trimmingCharacters(in: trimChars)
                    playerCUID = raw ?? ""
                }
            }
            if script.contains("MOVIE_TRAILER") {
                if let m = script.range(of: #"MOVIE_TRAILER\s*=\s*"([^"]+)""#, options: .regularExpression) {
                    let raw = script[m].components(separatedBy: "=").last?.trimmingCharacters(in: trimChars)
                    trailer = raw ?? ""
                }
            }
        }
        
        var year = ""
        var countries: [String] = []
        var genres: [String] = []
        var directors: [String] = []
        var actors: [String] = []
        var writers: [String] = []
        var producers: [String] = []
        var durationMinutes: Int?
        
        let infoItems = try doc.select("#info .info_item")
        for item in infoItems {
            let key = (try? item.select(".key").text()) ?? ""
            let val = (try? item.select(".value").text()) ?? ""
            
            switch key {
            case "Год": year = val
            case "Страна": countries = val.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            case "Жанр": genres = try item.select("span[itemprop=genre]").array().compactMap { try? $0.text() }
            case "Режиссер": directors = try item.select("span[itemprop=director] span[itemprop=name]").array().compactMap { try? $0.text() }
            case "В главных ролях", "Актеры": actors = try item.select("span[itemprop=actor] span[itemprop=name]").array().compactMap { try? $0.text() }
            case "Сценарий": writers = val.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            case "Продюсер": producers = try item.select("span[itemprop=producer] span[itemprop=name]").array().compactMap { try? $0.text() }
            case "Время":
                let regex = try? NSRegularExpression(pattern: "(\\d+)\\s*мин")
                if let match = regex?.firstMatch(in: val, range: NSRange(val.startIndex..., in: val)),
                   let r = Range(match.range(at: 1), in: val) {
                    durationMinutes = Int(val[r])
                }
            default: break
            }
        }
        
        // Frames / Screenshots
        let frames: [KinobaseMovieFrameDTO] = try doc.select("#frames a").array().compactMap { a in
            guard let href = try? a.attr("href"), !href.isEmpty else { return nil }
            let img = (try? a.select("img").attr("src")) ?? ""
            let full = href.hasPrefix("http") ? href : "https://kinobase.org\(href)"
            let thumb = img.hasPrefix("http") ? img : "https://kinobase.org\(img)"
            return KinobaseMovieFrameDTO(thumbURL: thumb, fullURL: full)
        }
        
        // Ratings
        let kpRating = (try? doc.select(".kp_rating").text()) ?? ""
        let imdbRating = (try? doc.select(".imdb_rating").text()) ?? ""
        
        return KinobaseMovieDetailDTO(
            id: movId,
            identifier: identifier,
            playerCUID: playerCUID,
            movieURL: movieURL,
            posterThumb: posterThumb,
            posterFull: posterFull,
            title: title,
            originalTitle: originalTitle,
            year: year,
            durationMinutes: durationMinutes,
            trailerURL: trailer.isEmpty ? nil : trailer,
            directors: directors,
            actors: actors,
            writers: writers,
            producers: producers,
            genres: genres,
            countries: countries,
            description: desc,
            frames: frames,
            kinopoiskRating: kpRating,
            kinopoiskVotes: "",
            imdbRating: imdbRating,
            imdbVotes: "",
            isSeries: movieURL.contains("/serial/")
        )
    }

    private static func parseNextPageURL(doc: Document) throws -> URL? {
        if let href = try? doc.select("ul.pagination li.active + li a").first()?.attr("href"),
           !href.isEmpty {
            let full = href.hasPrefix("http") ? href : "https://kinobase.org\(href)"
            return URL(string: full)
        }
        return nil
    }
}
