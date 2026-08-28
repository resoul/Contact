import Foundation

public struct KinobaseSearchResponseDTO: Codable, Sendable {
    public let query: String
    public let suggestions: [KinobaseSearchResultDTO]
}

public struct KinobaseSearchResultDTO: Codable, Sendable {
    public let url: String
    public let image: String
    public let value: String
    public let rating: Double?
    public let video: String?
    public let year: Int?
    public let type: String?
    
    public var fullImageURL: String {
        if image.hasPrefix("http") { return image }
        return "https://kinobase.org\(image)"
    }
    
    public var fullMovieURL: String {
        if url.hasPrefix("http") { return url }
        return "https://kinobase.org\(url)"
    }
    
    public var movieId: Int? {
        let regex = try? NSRegularExpression(pattern: "/film/(\\d+)")
        if let match = regex?.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
           let r = Range(match.range(at: 1), in: url) {
            return Int(url[r])
        }
        return nil
    }
}
