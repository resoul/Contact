import UIKit
import AsyncDisplayKit
import ListUI

struct ChatListItem: ListItem {
    let chat: Chat
    let accountID: UUID
    let swipeEnabled: Bool
    let onSelect: (Int) -> Void
    let onAction: (Int, ChatCell.Action, ChatListItemNode?) -> Void
    let onPeek: (Int, ChatListItemNode) -> Void
    let onSwipe: (ChatListItemNode) -> Void

    var id: String { Self.identity(accountID: accountID, chatID: chat.id) }
    static func identity(accountID: UUID, chatID: Int) -> String { "\(accountID.uuidString):chat:\(chatID)" }
    var reuseIdentifier: String { swipeEnabled ? "contact.chat.actions" : "contact.chat.paging" }
    var version: Int {
        var hash = Hasher()
        hash.combine(chat.person.name); hash.combine(chat.person.hue); hash.combine(chat.kind.rawValue)
        hash.combine(chat.message); hash.combine(chat.time); hash.combine(chat.unread)
        hash.combine(chat.muted); hash.combine(chat.pinned); hash.combine(chat.outgoingRead)
        hash.combine(chat.online); hash.combine(swipeEnabled)
        return hash.finalize()
    }
    func height(for width: CGFloat) -> CGFloat { 76 }
    func makeNode() -> ListItemNode { ChatListItemNode() }
    func update(node: ListItemNode, theme: ListTheme) {
        guard let node = node as? ChatListItemNode else { return }
        node.configure(chat, swipeEnabled: swipeEnabled)
        let chatID = chat.id
        node.onSelect = { onSelect(chatID) }
        node.cell.onAction = { [weak node] action in onAction(chatID, action, node) }
        node.cell.onPeek = { [weak node] in if let node { onPeek(chatID, node) } }
        node.cell.onSwipeBegan = { [weak node] in if let node { onSwipe(node) } }
        let actions: [(String, ChatCell.Action)] = [
            (chat.unread > 0 ? "Read" : "Unread", .read), (chat.pinned ? "Unpin" : "Pin", .pin),
            (chat.muted ? "Unmute" : "Mute", .mute), ("Delete", .delete), ("Archive", .archive),
        ]
        node.view.accessibilityCustomActions = actions.map { title, action in
            UIAccessibilityCustomAction(name: title) { [weak node] _ in onAction(chatID, action, node); return true }
        }
    }
    func selected() { onSelect(chat.id) }
}

/// Hosts the original UIKit row unchanged, keeping its layout, swipe buttons and animations.
final class ChatListItemNode: ListItemNode {
    let cell = ChatCell(style: .default, reuseIdentifier: nil)
    private var configured = false
    var onSelect: (() -> Void)?
    private var tap: UITapGestureRecognizer!

    override init() {
        super.init()
        contentNode.view.addSubview(cell)
        isAccessibilityElement = true
        accessibilityTraits = .button
        cell.accessibilityElementsHidden = true
        tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        cell.slider.addGestureRecognizer(tap)
        for gesture in cell.slider.gestureRecognizers ?? [] where gesture !== tap {
            tap.require(toFail: gesture)
        }
    }

    override var interactionPanGestures: [UIGestureRecognizer] {
        (cell.slider.gestureRecognizers ?? []).filter { $0 is UIPanGestureRecognizer && $0.isEnabled }
    }
    override var blocksHorizontalPaging: Bool { abs(cell.slider.frame.minX) > 0.5 }
    override var selectionFailureGestures: [UIGestureRecognizer] {
        (cell.slider.gestureRecognizers ?? []).filter(\.isEnabled)
    }

    @objc private func tapped() {
        if blocksHorizontalPaging { closeInteractions(animated: true) }
        else { onSelect?() }
    }

    override func accessibilityActivate() -> Bool {
        tapped()
        return true
    }

    func configure(_ chat: Chat, swipeEnabled: Bool) {
        if !swipeEnabled { closeInteractions(animated: false) }
        for gesture in cell.slider.gestureRecognizers ?? [] where gesture is UIPanGestureRecognizer {
            gesture.isEnabled = swipeEnabled
        }
        cell.configure(chat, typing: false, animated: configured)
        configured = true
        accessibilityIdentifier = "contact.chat.\(chat.id)"
        accessibilityLabel = "\(chat.person.name), \(chat.message), \(chat.time)" + (chat.unread > 0 ? ", \(chat.unread) unread" : "")
        setNeedsLayout()
    }

    override func layout() {
        super.layout()
        cell.frame = bounds
        cell.layoutIfNeeded()
    }

    override func closeInteractions(animated: Bool) {
        if animated { cell.close() }
        else { UIView.performWithoutAnimation { cell.close(); cell.layoutIfNeeded() } }
    }

    override func prepareForReuse() {
        closeInteractions(animated: false)
        cell.onAction = nil
        cell.onPeek = nil
        cell.onSwipeBegan = nil
        onSelect = nil
        cell.prepareForReuse()
        configured = false
        super.prepareForReuse()
    }
}

struct ChatEmptyItem: ListItem {
    let id: String
    let name: String
    var version: Int { name.hashValue }
    func height(for width: CGFloat) -> CGFloat { 360 }
    func makeNode() -> ListItemNode { ChatEmptyItemNode() }
    func update(node: ListItemNode, theme: ListTheme) {
        (node as? ChatEmptyItemNode)?.empty.setFolderName(name)
    }
}

private final class ChatEmptyItemNode: ListItemNode {
    let empty = FolderEmptyView()
    override init() { super.init(); contentNode.view.addSubview(empty) }
    override func layout() { super.layout(); empty.frame = bounds }
}
