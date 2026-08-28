import Foundation

public struct SeasonvarSearchRawResponseDTO: Codable, Sendable {
    public let query: String
    public let suggestions: SeasonvarSuggestionsDTO
    public let data: [String]
    public let id: [String]
}

public struct SeasonvarSuggestionsDTO: Codable, Sendable {
    public let valu: [String]
    public let kp: [String]?
}

public struct SeasonvarSearchResultDTO: Identifiable, Sendable {
    public let id: Int
    public let title: String
    public let path: String
    public let rating: String?
    
    public init(id: Int, title: String, path: String, rating: String?) {
        self.id = id
        self.title = title
        self.path = path
        self.rating = rating
    }
    
    public var fullURL: String {
        if path.hasPrefix("http") { return path }
        return "https://seasonvar.ru/\(path)"
    }
}
