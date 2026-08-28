import Foundation

public enum KinobaseError: LocalizedError, Sendable {
    case movieNotFound
    case invalidURL(String)
    case playerInitNotFound
    case decodingFailed
    
    public var errorDescription: String? {
        switch self {
        case .movieNotFound:
            return "Movie not found or failed to parse movie page."
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .playerInitNotFound:
            return "Failed to extract player metadata (MOV_ID / IDENTIFIER) from movie page."
        case .decodingFailed:
            return "Failed to decode streaming sources."
        }
    }
}
