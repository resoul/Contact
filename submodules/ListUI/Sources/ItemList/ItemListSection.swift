import UIKit
import AsyncDisplayKit

public struct ItemListSection {
    public let id: String
    public let title: String?
    public let items: [any ListItem]

    public init(id: String, title: String? = nil, items: [any ListItem]) {
        self.id = id
        self.title = title
        self.items = items
    }

    var flattened: [any ListItem] {
        guard let title, !title.isEmpty else { return items }
        return [SectionTitleItem(id: "section:\(id)", title: title)] + items
    }
}

private struct SectionTitleItem: ListItem {
    let id: String
    let title: String
    var version: Int { title.hashValue }
    func height(for width: CGFloat) -> CGFloat { 38 }
    func makeNode() -> ListItemNode { SectionTitleNode() }
    func update(node: ListItemNode, theme: ListTheme) {
        guard let node = node as? SectionTitleNode else { return }
        node.backgroundColor = theme.background
        node.text.attributedText = NSAttributedString(string: title.uppercased(), attributes: [
            .font: UIFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: theme.secondary,
        ])
    }
}

private final class SectionTitleNode: ListItemNode {
    let text = ASTextNode()
    override init() {
        super.init()
        text.isUserInteractionEnabled = false
        contentNode.addSubnode(text)
    }
    override func layout() {
        super.layout()
        text.frame = CGRect(x: 20, y: 14, width: max(0, bounds.width - 40), height: 20)
    }
}
