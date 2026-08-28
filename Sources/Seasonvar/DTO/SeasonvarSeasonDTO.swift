import Foundation

public struct SeasonvarSeasonItemDTO: Identifiable, Sendable {
    public let id: Int
    public let title: String
    public let seasonNumber: Int
    public let url: String
    public let isCurrent: Bool
    
    public init(id: Int, title: String, seasonNumber: Int, url: String, isCurrent: Bool) {
        self.id = id
        self.title = title
        self.seasonNumber = seasonNumber
        self.url = url
        self.isCurrent = isCurrent
    }
}
