import Foundation

public struct ListPage {
    public let id: String
    public let title: String
    public let sections: [ItemListSection]
    let makePane: ((ListTheme) -> any ScrollablePane)?
    let updatePane: ((any ScrollablePane, ListTheme) -> Void)?
    public var items: [any ListItem] { sections.flatMap(\.flattened) }

    public init(id: String, title: String, sections: [ItemListSection]) {
        self.id = id
        self.title = title
        self.sections = sections
        makePane = nil
        updatePane = nil
    }

    public init(
        id: String,
        title: String,
        makePane: @escaping (ListTheme) -> any ScrollablePane,
        updatePane: @escaping (any ScrollablePane, ListTheme) -> Void = { _, _ in }
    ) {
        self.id = id
        self.title = title
        sections = []
        self.makePane = makePane
        self.updatePane = updatePane
    }
}
