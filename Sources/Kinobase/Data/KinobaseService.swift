import Foundation
import Alamofire

public protocol KinobaseService: Sendable {
    func search(query: String) async throws -> [KinobaseSearchResultDTO]
    func fetchCatalog(pageURL: URL?) async throws -> KinobaseMoviePageDTO
    func fetchDetail(urlOrId: String) async throws -> KinobaseMovieDetailDTO
    func fetchStreams(movieId: Int, identifier: String, referer: String) async throws -> [KinobaseTranslationDTO]
}

public final class KinobaseServiceImpl: KinobaseService {
    public static let baseURL = "https://kinobase.org"
    private let client: KinobaseNetworkClient
    
    public init(client: KinobaseNetworkClient = .init()) {
        self.client = client
    }
    
    /// Searches for movies and TV series
    public func search(query: String) async throws -> [KinobaseSearchResultDTO] {
        let url = "\(Self.baseURL)/search"
        let params: Parameters = ["query": query]
        let headers: HTTPHeaders = [
            "X-Requested-With": "XMLHttpRequest",
            "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36"
        ]
        
        let response: KinobaseSearchResponseDTO = try await client.postDecodable(
            url: url,
            parameters: params,
            headers: headers
        )
        return response.suggestions
    }
    
    /// Loads catalog (movies / TV series / pagination pages)
    public func fetchCatalog(pageURL: URL? = nil) async throws -> KinobaseMoviePageDTO {
        let target = pageURL?.absoluteString ?? "\(Self.baseURL)/"
        let data = try await client.get(url: target)
        let html = String(data: data, encoding: .utf8) ?? ""
        return try KinobaseHTMLParser.parseListing(html: html)
    }
    
    /// Loads movie/series details
    public func fetchDetail(urlOrId: String) async throws -> KinobaseMovieDetailDTO {
        let fullURL: String
        if urlOrId.hasPrefix("http") {
            fullURL = urlOrId
        } else if let id = Int(urlOrId) {
            fullURL = "\(Self.baseURL)/film/\(id)"
        } else {
            fullURL = "\(Self.baseURL)/film/\(urlOrId)"
        }
        
        let data = try await client.get(url: fullURL)
        let html = String(data: data, encoding: .utf8) ?? ""
        return try KinobaseHTMLParser.parseDetail(html: html, movieURL: fullURL)
    }
    
    /// Fetches direct stream playlists (m3u8 playlists, qualities, audio tracks, subtitles)
    public func fetchStreams(movieId: Int, identifier: String, referer: String) async throws -> [KinobaseTranslationDTO] {
        let vodURL = "\(Self.baseURL)/vod/\(movieId)"
        let params: Parameters = [
            "identifier": identifier,
            "player_type": "new",
            "file_type": "hls",
            "enable_hdr": "0"
        ]
        
        let headers: HTTPHeaders = [
            "X-Requested-With": "XMLHttpRequest",
            "Referer": referer,
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36"
        ]
        
        let rawResponse = try await client.getString(url: vodURL, parameters: params, headers: headers)
        let parsed = KinobaseStreamDecoder.parsePlaylist(from: rawResponse)
        return parsed.translations
    }
}
