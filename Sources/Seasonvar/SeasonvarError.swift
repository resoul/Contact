import Foundation

public enum SeasonvarError: LocalizedError, Sendable {
    case serialNotFound
    case invalidURL(String)
    case playlistNotFound
    case decodingFailed
    
    public var errorDescription: String? {
        switch self {
        case .serialNotFound:
            return "Serial not found or failed to parse serial page."
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .playlistNotFound:
            return "Failed to find playlist or secure token on page."
        case .decodingFailed:
            return "Failed to decode video file URL."
        }
    }
}
