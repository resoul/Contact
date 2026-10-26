import UIKit
import AsyncDisplayKit
import ListUI

struct ProfileAttachmentItem: ListItem {
    enum Kind: String { case files, links, voice }
    let kind: Kind
    let index: Int
    let title: String
    let detail: String
    let onSelect: (String) -> Void
    var id: String { "profile.\(kind.rawValue).\(index)" }
    var symbol: String {
        switch kind {
        case .files: return ["doc.fill", "doc.richtext.fill", "archivebox.fill"][index % 3]
        case .links: return "link"
        case .voice: return "play.fill"
        }
    }
    func height(for width: CGFloat) -> CGFloat { 76 }
    func makeNode() -> ListItemNode { ProfileAttachmentItemNode() }
    func update(node: ListItemNode, theme: ListTheme) {
        (node as? ProfileAttachmentItemNode)?.update(item: self, theme: theme)
    }
    func selected() { onSelect("Demo · " + title) }

    static func pages(onSelect: @escaping (String) -> Void) -> [ListPage] {
        [(Kind.files, "Files"), (.links, "Links"), (.voice, "Voice")].map { kind, name in
            let items: [any ListItem] = (0..<36).map { index in
                let day = 25 - index % 25
                let title: String
                let detail: String
                switch kind {
                case .files:
                    let files = ["Project notes.pdf", "Contact design.fig", "Resources.zip", "Meeting notes.txt"]
                    title = files[index % files.count]
                    detail = "\(index % 8 + 1).\(index % 9 + 1) MB · October \(day), 2026"
                case .links:
                    let links = [("Texture", "texturegroup.org"), ("Swift", "swift.org"),
                                 ("Apple Developer", "developer.apple.com"), ("Contact", "Contact project")]
                    let link = links[index % links.count]
                    title = link.0
                    detail = "\(link.1) · October \(day), 2026"
                case .voice:
                    title = "Voice message"
                    detail = "0:\(String(format: "%02d", 12 + index % 46)) · October \(day), 2026"
                }
                return ProfileAttachmentItem(kind: kind, index: index, title: title, detail: detail, onSelect: onSelect)
            }
            return ListPage(id: kind.rawValue, title: name, sections: [ItemListSection(id: kind.rawValue, items: items)])
        }
    }
}

private final class ProfileAttachmentItemNode: ListItemNode {
    private let tile = ASDisplayNode()
    private let icon = ASImageNode()
    private let heading = ASTextNode()
    private let detail = ASTextNode()
    private let separator = ASDisplayNode()

    override init() {
        super.init()
        [tile, icon, heading, detail, separator].forEach {
            $0.isUserInteractionEnabled = false
            contentNode.addSubnode($0)
        }
        tile.cornerRadius = 12
        icon.contentMode = .scaleAspectFit
        heading.maximumNumberOfLines = 1
        detail.maximumNumberOfLines = 1
    }

    func update(item: ProfileAttachmentItem, theme: ListTheme) {
        contentNode.backgroundColor = theme.rowBackground
        tile.backgroundColor = theme.accent.withAlphaComponent(0.16)
        icon.image = UIImage(systemName: item.symbol)?.withTintColor(theme.accent, renderingMode: .alwaysOriginal)
        heading.attributedText = NSAttributedString(string: item.title, attributes: [
            .font: UIFont.systemFont(ofSize: 16, weight: .medium), .foregroundColor: theme.primary,
        ])
        detail.attributedText = NSAttributedString(string: item.detail, attributes: [
            .font: UIFont.systemFont(ofSize: 13), .foregroundColor: theme.secondary,
        ])
        separator.backgroundColor = theme.separator.withAlphaComponent(0.4)
        isAccessibilityElement = true
        accessibilityLabel = "\(item.title), \(item.detail)"
        accessibilityTraits = .button
        setNeedsLayout()
    }

    override func layout() {
        super.layout()
        tile.frame = CGRect(x: 16, y: 14, width: 48, height: 48)
        icon.frame = CGRect(x: 28, y: 26, width: 24, height: 24)
        heading.frame = CGRect(x: 78, y: 16, width: max(0, bounds.width - 94), height: 23)
        detail.frame = CGRect(x: 78, y: 43, width: max(0, bounds.width - 94), height: 19)
        separator.frame = CGRect(x: 78, y: bounds.height - 0.5, width: max(0, bounds.width - 78), height: 0.5)
    }
}
