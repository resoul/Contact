import Foundation
import SwiftSoup

public enum SeasonvarHTMLParser {
    public static func parseDetail(html: String, movieURL: String) throws -> SeasonvarMovieDetailDTO {
        let doc = try SwiftSoup.parse(html)
        
        let titleFull = (try? doc.select("h1, .pgs-sinfo-title").first()?.text()) ?? ""
        let titleParts = titleFull.components(separatedBy: "/")
        let title = titleParts.first?.trimmingCharacters(in: .whitespaces) ?? titleFull
        let originalTitle = titleParts.count > 1 ? titleParts[1].trimmingCharacters(in: .whitespaces) : ""
        
        let posterRaw = (try? doc.select(".pgs-sinfo-img img, .poster img").attr("src")) ?? ""
        let posterURL = posterRaw.hasPrefix("//") ? "https:\(posterRaw)" : (posterRaw.hasPrefix("http") ? posterRaw : "https://seasonvar.ru\(posterRaw)")
        
        let desc = (try? doc.select(".pgs-sinfo-info, .description").text()) ?? ""
        
        // Serial ID
        var serialId = 0
        let regex = try? NSRegularExpression(pattern: "serial-(\\d+)")
        if let match = regex?.firstMatch(in: movieURL, range: NSRange(movieURL.startIndex..., in: movieURL)),
           let r = Range(match.range(at: 1), in: movieURL) {
            serialId = Int(movieURL[r]) ?? 0
        }
        
        // Seasons
        var seasons: [SeasonvarSeasonItemDTO] = []
        let seasonLinks = try doc.select(".pgs-seaslist ul.tabs-result li h2 a")
        for (idx, link) in seasonLinks.array().enumerated() {
            let sText = (try? link.text()) ?? ""
            let href = (try? link.attr("href")) ?? ""
            let sURL = href.hasPrefix("http") ? href : "https://seasonvar.ru\(href)"
            
            var sId = idx + 1
            if let m = regex?.firstMatch(in: href, range: NSRange(href.startIndex..., in: href)),
               let r = Range(m.range(at: 1), in: href) {
                sId = Int(href[r]) ?? (idx + 1)
            }
            
            let isCurr = sText.contains(">>>") || sURL == movieURL
            let cleanText = sText.replacingOccurrences(of: ">>>", with: "").trimmingCharacters(in: .whitespaces)
            seasons.append(SeasonvarSeasonItemDTO(
                id: sId,
                title: cleanText,
                seasonNumber: idx + 1,
                url: sURL,
                isCurrent: isCurr
            ))
        }
        
        // Translations and playlists
        var plMap: [String: String] = [:]
        let scripts = try doc.select("script").array().map { try? $0.html() }.compactMap { $0 }
        for s in scripts {
            let plMatches = s.ranges(of: #"pl\[(\d+)\]\s*=\s*"([^"]+)""#)
            for range in plMatches {
                let matchStr = String(s[range])
                let parts = matchStr.components(separatedBy: "=")
                if parts.count == 2 {
                    let k = parts[0].components(separatedBy: "[").last?.replacingOccurrences(of: "]", with: "").trimmingCharacters(in: .whitespaces) ?? ""
                    let v = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"; "))
                    if !k.isEmpty && !v.isEmpty {
                        plMap[k] = v
                    }
                }
            }
            if let defaultMatch = s.range(of: #"'0':\s*"([^"]+)""#, options: .regularExpression) {
                let str = String(s[defaultMatch])
                let path = str.components(separatedBy: ":").last?.trimmingCharacters(in: CharacterSet(charactersIn: "\"; '")) ?? ""
                if !path.isEmpty {
                    plMap["0"] = path
                }
            }
        }
        
        var translations: [SeasonvarTranslationDTO] = []
        let transItems = try doc.select(".pgs-trans li[data-click=translate]")
        for item in transItems {
            let tId = (try? item.attr("data-translate")) ?? "0"
            let tName = (try? item.text()) ?? "Стандартный"
            if tName == "Трейлеры" { continue }
            
            if let path = plMap[tId] {
                translations.append(SeasonvarTranslationDTO(
                    id: tId,
                    studio: tName,
                    playlistPath: path,
                    episodes: []
                ))
            }
        }
        
        // Ratings
        let kpRating = (try? doc.select(".svico-kinopoisk").text()) ?? ""
        let imdbRating = (try? doc.select(".svico-imdb").text()) ?? ""
        
        return SeasonvarMovieDetailDTO(
            id: serialId,
            title: title,
            originalTitle: originalTitle,
            posterURL: posterURL,
            year: "",
            country: "",
            genres: [],
            directors: [],
            actors: [],
            description: desc,
            ratingKP: kpRating,
            ratingIMDb: imdbRating,
            movieURL: movieURL,
            seasons: seasons,
            translations: translations
        )
    }
}

private extension String {
    func ranges(of pattern: String) -> [Range<String.Index>] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = regex.matches(in: self, range: NSRange(startIndex..., in: self))
        return matches.compactMap { Range($0.range, in: self) }
    }
}
