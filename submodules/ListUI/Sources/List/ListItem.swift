import UIKit

public protocol ListItem {
    var id: String { get }
    var version: Int { get }
    var reuseIdentifier: String { get }
    func height(for width: CGFloat) -> CGFloat
    func makeNode() -> ListItemNode
    func update(node: ListItemNode, theme: ListTheme)
    func selected()
}

public extension ListItem {
    var version: Int { 0 }
    var reuseIdentifier: String { String(reflecting: Self.self) }
    func selected() {}
}
