import Foundation

public struct ItemListState {
    public let pages: [ListPage]
    public let selectedPageID: String?

    public init(pages: [ListPage], selectedPageID: String? = nil) {
        precondition(Set(pages.map(\.id)).count == pages.count, "Duplicate page identity")
        self.pages = pages
        self.selectedPageID = selectedPageID
    }
}
