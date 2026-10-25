import Foundation

public struct ListTransaction {
    public let inserted: Set<String>
    public let deleted: Set<String>
    public let moved: Set<String>

    public init(previous: [String], next: [String]) {
        precondition(Set(previous).count == previous.count, "Duplicate previous list identity")
        precondition(Set(next).count == next.count, "Duplicate next list identity")
        let old = Dictionary(uniqueKeysWithValues: previous.enumerated().map { ($0.element, $0.offset) })
        let new = Dictionary(uniqueKeysWithValues: next.enumerated().map { ($0.element, $0.offset) })
        inserted = Set(next).subtracting(previous)
        deleted = Set(previous).subtracting(next)
        moved = Set(next.filter { old[$0] != nil && old[$0] != new[$0] })
    }
}
