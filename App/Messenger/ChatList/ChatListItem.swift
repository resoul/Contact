import UIKit
import AsyncDisplayKit
import ListUI

/// Active stories of the chat's person, by index in `MessengerData.storyUsers`.
struct ChatStory: Equatable {
    let userIndex: Int
    let total: Int
    let unseen: Int
}

struct ChatListItem: AsyncListItem {
    let chat: Chat
    let story: ChatStory?
    let accountID: UUID
    let swipeEnabled: Bool
    let onSelect: (Int) -> Void
    let onAction: (Int, ChatCell.Action, ChatListItemNode?) -> Void
    let onPeek: (Int, ChatListItemNode) -> Void
    let onSwipe: (ChatListItemNode) -> Void
    let onOpenStory: (Int, ChatListItemNode) -> Void

    var id: String { Self.identity(accountID: accountID, chatID: chat.id) }
    static func identity(accountID: UUID, chatID: Int) -> String { "\(accountID.uuidString):chat:\(chatID)" }
    var reuseIdentifier: String { swipeEnabled ? "contact.chat.actions" : "contact.chat.paging" }
    var version: Int {
        var hash = Hasher()
        hash.combine(chat.person.name); hash.combine(chat.person.hue); hash.combine(chat.kind.rawValue)
        hash.combine(chat.message); hash.combine(chat.time); hash.combine(chat.unread)
        hash.combine(chat.muted); hash.combine(chat.pinned); hash.combine(chat.outgoingRead)
        hash.combine(chat.online); hash.combine(swipeEnabled)
        hash.combine(story?.userIndex); hash.combine(story?.total); hash.combine(story?.unseen)
        return hash.finalize()
    }
    func height(for width: CGFloat) -> CGFloat { 76 }
    func makeNode() -> ListItemNode { ChatListItemNode() }
    func update(node: ListItemNode, theme: ListTheme) {
        guard let node = node as? ChatListItemNode else { return }
        node.configure(chat, story: story, swipeEnabled: swipeEnabled, theme: theme)
        let chatID = chat.id
        node.onSelect = { onSelect(chatID) }
        node.onOpenStory = story == nil ? nil : { [weak node] in if let node { onOpenStory(chatID, node) } }
        node.cell.onAction = { [weak node] action in onAction(chatID, action, node) }
        node.cell.onPeek = { [weak node] in if let node { onPeek(chatID, node) } }
        node.cell.onSwipeBegan = { [weak node] in if let node { onSwipe(node) } }
        let actions: [(String, ChatCell.Action)] = [
            (chat.unread > 0 ? "Read" : "Unread", .read), (chat.pinned ? "Unpin" : "Pin", .pin),
            (chat.muted ? "Unmute" : "Mute", .mute), ("Delete", .delete), ("Archive", .archive),
        ]
        var custom = actions.map { title, action in
            UIAccessibilityCustomAction(name: title) { [weak node] _ in onAction(chatID, action, node); return true }
        }
        if story != nil {
            custom.insert(UIAccessibilityCustomAction(name: "Open Story") { [weak node] _ in
                if let node { onOpenStory(chatID, node) }
                return node != nil
            }, at: 0)
        }
        node.view.accessibilityCustomActions = custom
    }
    func prepareLayout(for width: CGFloat, theme: ListTheme, traits: UITraitCollection) -> (ListItemNode) -> Void {
        let layout = ChatCell.prepare(chat, width: width, theme: theme, traits: traits)
        return { node in (node as? ChatListItemNode)?.cell.apply(layout) }
    }
    func selected() { onSelect(chat.id) }
}

final class ChatListItemNode: ListItemNode {
    let cell = ChatCell()
    var onSelect: (() -> Void)?
    var onOpenStory: (() -> Void)?
    private var tap: UITapGestureRecognizer!

    override init() {
        super.init()
        contentNode.addSubnode(cell)
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    override func didLoad() {
        super.didLoad()
        cell.view.accessibilityElementsHidden = true
        tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        cell.slider.view.addGestureRecognizer(tap)
        for gesture in cell.selectionFailureGestures {
            tap.require(toFail: gesture)
        }
    }

    override var interactionPanGestures: [UIGestureRecognizer] {
        cell.interactionPanGestures.filter(\.isEnabled)
    }
    override var blocksHorizontalPaging: Bool { cell.isRevealOpen }
    override var selectionFailureGestures: [UIGestureRecognizer] {
        cell.selectionFailureGestures.filter(\.isEnabled)
    }

    @objc private func tapped() {
        if blocksHorizontalPaging { closeInteractions(animated: true) }
        else if let onOpenStory, cell.storyHit(tap.location(in: cell.view)) { onOpenStory() }
        else { onSelect?() }
    }

    override func accessibilityActivate() -> Bool {
        if blocksHorizontalPaging { closeInteractions(animated: true) }
        else { onSelect?() }
        return true
    }

    func configure(_ chat: Chat, story: ChatStory?, swipeEnabled: Bool, theme: ListTheme) {
        cell.configure(chat, story: story, swipeEnabled: swipeEnabled, theme: theme)
        accessibilityIdentifier = "contact.chat.\(chat.id)"
        accessibilityLabel = "\(chat.person.name), \(chat.message), \(chat.time)" + (chat.unread > 0 ? ", \(chat.unread) unread" : "")
            + ((story?.unseen ?? 0) > 0 ? ", new story" : "")
        setNeedsLayout()
    }

    override func layout() {
        super.layout()
        cell.frame = bounds
    }

    override func closeInteractions(animated: Bool) {
        cell.close(animated: animated)
    }

    override func updateViewport(isVisible: Bool, isScrolling: Bool) {
        cell.updateViewport(isVisible: isVisible, isScrolling: isScrolling)
    }

    override func prepareForReuse() {
        closeInteractions(animated: false)
        cell.onAction = nil
        cell.onPeek = nil
        cell.onSwipeBegan = nil
        onSelect = nil
        onOpenStory = nil
        cell.prepareForReuse()
        super.prepareForReuse()
    }
}

struct ChatEmptyItem: ListItem {
    let id: String
    let name: String
    let onEdit: () -> Void
    var version: Int { name.hashValue }
    func height(for width: CGFloat) -> CGFloat { 360 }
    func makeNode() -> ListItemNode { ChatEmptyItemNode() }
    func update(node: ListItemNode, theme: ListTheme) {
        guard let node = node as? ChatEmptyItemNode else { return }
        node.empty.setFolderName(name)
        node.empty.onEdit = onEdit
    }
}

private final class ChatEmptyItemNode: ListItemNode {
    let empty = FolderEmptyView()
    override init() { super.init(); contentNode.view.addSubview(empty) }
    override func layout() { super.layout(); empty.frame = bounds }
}
