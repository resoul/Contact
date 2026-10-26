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

/// Prepare measurements and unloaded Texture nodes on a worker queue. The returned
/// closure runs on main, only while the row still represents this version and width.
/// Capture immutable input here; never access a loaded node or UIView in preparation.
public protocol AsyncListItem: ListItem {
    func prepareLayout(for width: CGFloat, theme: ListTheme, traits: UITraitCollection) -> (ListItemNode) -> Void
}
