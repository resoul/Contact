import Foundation
import Alamofire

public protocol SeasonvarService: Sendable {
    func search(query: String) async throws -> [SeasonvarSearchResultDTO]
    func fetchDetail(urlOrPath: String) async throws -> SeasonvarMovieDetailDTO
    func fetchEpisodes(for translation: SeasonvarTranslationDTO, referer: String) async throws -> [SeasonvarEpisodeDTO]
    func fetchAllTranslationsWithEpisodes(urlOrPath: String) async throws -> [SeasonvarTranslationDTO]
}

public final class SeasonvarServiceImpl: SeasonvarService {
    public static let baseURL = "https://seasonvar.ru"
    private let client: SeasonvarNetworkClient
    
    public init(client: SeasonvarNetworkClient = .init()) {
        self.client = client
    }
    
    /// Searches for TV series
    public func search(query: String) async throws -> [SeasonvarSearchResultDTO] {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return []
        }
        let url = "\(Self.baseURL)/autocomplete.php?query=\(encodedQuery)"
        let headers: HTTPHeaders = [
            "X-Requested-With": "XMLHttpRequest",
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36"
        ]
        
        let raw: SeasonvarSearchRawResponseDTO = try await client.postDecodable(
            url: url,
            parameters: [:],
            headers: headers
        )
        
        var results: [SeasonvarSearchResultDTO] = []
        for i in 0..<min(raw.suggestions.valu.count, raw.data.count) {
            let title = raw.suggestions.valu[i]
            let path = raw.data[i]
            let idStr = i < raw.id.count ? raw.id[i] : "0"
            let id = Int(idStr) ?? 0
            
            if !path.isEmpty && !path.contains("actor/") {
                results.append(SeasonvarSearchResultDTO(
                    id: id,
                    title: title,
                    path: path,
                    rating: nil
                ))
            }
        }
        return results
    }
    
    /// Fetches detailed series info, available seasons and translations
    public func fetchDetail(urlOrPath: String) async throws -> SeasonvarMovieDetailDTO {
        let fullURL: String
        if urlOrPath.hasPrefix("http") {
            fullURL = urlOrPath
        } else {
            let clean = urlOrPath.hasPrefix("/") ? String(urlOrPath.dropFirst()) : urlOrPath
            fullURL = "\(Self.baseURL)/\(clean)"
        }
        
        let data = try await client.get(url: fullURL)
        let html = String(data: data, encoding: .utf8) ?? ""
        return try SeasonvarHTMLParser.parseDetail(html: html, movieURL: fullURL)
    }
    
    /// Fetches episode list and decodes direct MP4 stream links for the selected translation
    public func fetchEpisodes(for translation: SeasonvarTranslationDTO, referer: String) async throws -> [SeasonvarEpisodeDTO] {
        let plistURL: String
        if translation.playlistPath.hasPrefix("http") {
            plistURL = translation.playlistPath
        } else {
            plistURL = "\(Self.baseURL)\(translation.playlistPath)"
        }
        
        let headers: HTTPHeaders = [
            "X-Requested-With": "XMLHttpRequest",
            "Referer": referer,
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36"
        ]
        
        let rawJSON = try await client.getString(url: plistURL, parameters: nil, headers: headers)
        guard let data = rawJSON.data(using: .utf8),
              let rawEpisodes = try? JSONDecoder().decode([SeasonvarRawEpisodeDTO].self, from: data) else {
            return []
        }
        
        return rawEpisodes.map { ep in
            let cleanTitle = SeasonvarStreamDecoder.cleanTitle(ep.title)
            let videoURL = SeasonvarStreamDecoder.decodeVideoURL(from: ep.file)
            return SeasonvarEpisodeDTO(
                id: ep.id,
                title: cleanTitle,
                videoURL: videoURL,
                subtitleURL: ep.subtitle
            )
        }
    }
    
    /// Fetches all translations along with their episodes and video stream links concurrently
    public func fetchAllTranslationsWithEpisodes(urlOrPath: String) async throws -> [SeasonvarTranslationDTO] {
        let detail = try await fetchDetail(urlOrPath: urlOrPath)
        
        return try await withThrowingTaskGroup(of: SeasonvarTranslationDTO.self) { group in
            for trans in detail.translations {
                group.addTask {
                    let episodes = try await self.fetchEpisodes(for: trans, referer: detail.movieURL)
                    var updated = trans
                    updated.episodes = episodes
                    return updated
                }
            }
            
            var results: [SeasonvarTranslationDTO] = []
            for try await res in group {
                results.append(res)
            }
            return results.sorted { $0.studio < $1.studio }
        }
    }
}
