import UIKit
import AsyncDisplayKit

private final class ListScrollView: UIScrollView {
    var externalScroll: ((CGFloat) -> Void)?
    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        guard let externalScroll else { return super.accessibilityScroll(direction) }
        switch direction {
        case .down: externalScroll(bounds.height * 0.8)
        case .up: externalScroll(-bounds.height * 0.8)
        default: return false
        }
        return true
    }
}

public final class ListView: ASDisplayNode, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    public var theme: ListTheme { didSet { if theme != oldValue { invalidatePresentation() } } }
    public var hasPages = false
    public var contentGeometryChanged: (() -> Void)?
    var pagingRecognizer: UIGestureRecognizer?
    var gestureLocation: ((UIView, CGPoint) -> (CGFloat, CGFloat))?
    private var items: [any ListItem] = []
    private var frames: [CGRect] = []
    private var active: [String: ListItemNode] = [:]
    private var pool: [String: [ListItemNode]] = [:]
    private let content = ASDisplayNode()
    private let scrollNode: ASDisplayNode
    public let scrollView: UIScrollView
    private var layoutWidth: CGFloat = 0
    private var layoutHeight: CGFloat = 0
    private var tapRecognizer: UITapGestureRecognizer!
    private var pendingOffset: CGFloat?
    private var externalScrollDriver: ((CGFloat) -> Void)?
    private var renderedTraits: UITraitCollection?
    public var contentOffset: CGFloat {
        get { isNodeLoaded ? scrollView.contentOffset.y : pendingOffset ?? 0 }
        set {
            if isNodeLoaded && layoutWidth > 0 {
                restoreOffset(newValue)
                pendingOffset = nil
            } else {
                pendingOffset = newValue
            }
        }
    }
    public var hasOpenReveal: Bool { active.values.contains { ($0 as? RevealableItemNode)?.isRevealOpen == true } }

    public init(theme: ListTheme) {
        self.theme = theme
        let scroller = ListScrollView()
        scrollView = scroller
        scrollNode = ASDisplayNode(viewBlock: { scroller })
        super.init()
        addSubnode(scrollNode)
        scrollNode.addSubnode(content)
    }

    public override func didLoad() {
        super.didLoad()
        scrollView.delegate = self
        scrollView.alwaysBounceVertical = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.keyboardDismissMode = .onDrag
        scrollView.backgroundColor = theme.background
        tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tapRecognizer.delegate = self
        scrollView.addGestureRecognizer(tapRecognizer)
        if let pagingRecognizer {
            scrollView.panGestureRecognizer.require(toFail: pagingRecognizer)
            tapRecognizer.require(toFail: pagingRecognizer)
        }
        applyScrollDriver()
    }

    public func apply(items next: [any ListItem], animated: Bool = true) {
        let transaction = ListTransaction(previous: items.map(\.id), next: next.map(\.id))
        let anchorIndex = frames.firstIndex { $0.maxY > contentOffset }
        let anchor = anchorIndex.map { (items[$0].id, frames[$0].minY - contentOffset) }
        let oldOffset = contentOffset
        closeReveals(animated: false)
        items = next
        guard isNodeLoaded, layoutWidth > 0 else { setNeedsLayout(); return }
        rebuildFrames()
        if oldOffset > 0, let anchor, let index = items.firstIndex(where: { $0.id == anchor.0 }) {
            restoreOffset(frames[index].minY - anchor.1)
        } else {
            restoreOffset(oldOffset)
        }
        for id in transaction.deleted {
            guard let node = active.removeValue(forKey: id) else { continue }

            node.view.isUserInteractionEnabled = false
            ListTransition.animate(animated, changes: { node.view.alpha = 0 }, completion: { [weak self] _ in
                self?.recycle(node)
            })
        }
        ListTransition.animate(animated, changes: { self.updateVisible(inserted: transaction.inserted, animated: animated) })
        contentGeometryChanged?()
    }

    public override func layout() {
        super.layout()
        let width = bounds.width
        guard width > 0 else { return }
        scrollNode.frame = bounds

        applyScrollDriver()
        if renderedTraits == nil || view.traitCollection.hasDifferentColorAppearance(comparedTo: renderedTraits) {
            renderedTraits = view.traitCollection
            active.values.forEach { $0.appliedVersion = nil }
        }
        let geometryChanged = width != layoutWidth || bounds.height != layoutHeight
        layoutHeight = bounds.height
        if width != layoutWidth {
            layoutWidth = width
            rebuildFrames()
            if let pendingOffset { restoreOffset(pendingOffset); self.pendingOffset = nil }
        }
        updateVisible()
        if geometryChanged { contentGeometryChanged?() }
    }

    func setExternalScrollDriver(_ driver: ((CGFloat) -> Void)?) {
        externalScrollDriver = driver
        if isNodeLoaded { applyScrollDriver() }
    }

    private func applyScrollDriver() {
        let nativeScrolling = externalScrollDriver == nil
        if scrollView.isScrollEnabled != nativeScrolling { scrollView.isScrollEnabled = nativeScrolling }
        if scrollView.panGestureRecognizer.isEnabled != nativeScrolling {
            scrollView.panGestureRecognizer.isEnabled = nativeScrolling
        }
        scrollView.scrollsToTop = nativeScrolling
        (scrollView as? ListScrollView)?.externalScroll = externalScrollDriver
    }

    private func rebuildFrames() {
        var y: CGFloat = 0
        frames = items.map { item in
            let height = max(1, item.height(for: layoutWidth))
            defer { y += height }
            return CGRect(x: 0, y: y, width: layoutWidth, height: height)
        }
        content.frame = CGRect(x: 0, y: 0, width: layoutWidth, height: y)
        scrollView.contentSize = CGSize(width: layoutWidth, height: y)
    }

    private func restoreOffset(_ offset: CGFloat) {
        scrollView.contentOffset.y = min(max(0, offset), max(0, scrollView.contentSize.height - bounds.height))
    }

    private func updateVisible(inserted: Set<String> = [], animated: Bool = false) {
        guard layoutWidth > 0, frames.count == items.count else { return }
        let viewport = CGRect(x: 0, y: scrollView.contentOffset.y, width: layoutWidth, height: bounds.height)
        let preload = viewport.insetBy(dx: 0, dy: -240)

        var low = 0, high = frames.count
        while low < high {
            let middle = (low + high) / 2
            if frames[middle].maxY < preload.minY { low = middle + 1 } else { high = middle }
        }
        var indices: [Int] = []
        while low < frames.count && frames[low].minY <= preload.maxY { indices.append(low); low += 1 }
        let visibleIDs = Set(indices.map { items[$0].id })
        for id in Array(active.keys) where !visibleIDs.contains(id) {
            if let node = active.removeValue(forKey: id) { recycle(node) }
        }
        for index in indices {
            let item = items[index]
            let node: ListItemNode
            if let existing = active[item.id], existing.reuseIdentifier == item.reuseIdentifier {
                node = existing
            } else {
                if let old = active.removeValue(forKey: item.id) { recycle(old) }
                node = pool[item.reuseIdentifier]?.popLast() ?? item.makeNode()
                node.reuseIdentifier = item.reuseIdentifier
                node.itemID = item.id
                node.view.isUserInteractionEnabled = true
                active[item.id] = node
                content.addSubnode(node)
                if animated && inserted.contains(item.id) { node.view.alpha = 0 }
            }
            if node.appliedVersion != item.version || node.appliedWidth != layoutWidth {
                item.update(node: node, theme: theme.resolved(for: view.traitCollection))
                node.appliedVersion = item.version
                node.appliedWidth = layoutWidth
            }
            configureGestures(node)
            node.frame = frames[index]
            node.view.alpha = 1
        }
    }

    private func configureGestures(_ node: ListItemNode) {
        guard let reveal = node as? RevealableItemNode else { return }
        reveal.requirePagingFailure(pagingRecognizer)
        scrollView.panGestureRecognizer.require(toFail: reveal.revealRecognizer)
        tapRecognizer?.require(toFail: reveal.revealRecognizer)
        reveal.allowsReveal = { [weak self, weak reveal] point in
            guard let self, let reveal else { return false }
            let location = self.gestureLocation?(reveal.view, point) ?? (point.x, self.layoutWidth)
            return ListGesturePolicy.owner(hasPages: self.hasPages, startX: location.0, width: location.1,
                                           rowHasActions: reveal.hasActions, rowIsOpen: reveal.isRevealOpen) == .reveal
        }
        reveal.revealBegan = { [weak self, weak reveal] in self?.closeReveals(except: reveal, animated: true) }
    }

    private func recycle(_ node: ListItemNode) {
        node.removeFromSupernode()
        let kind = node.reuseIdentifier
        node.prepareForReuse()
        if (pool[kind]?.count ?? 0) < 24 { pool[kind, default: []].append(node) }
    }

    private func invalidatePresentation() {
        guard isNodeLoaded else { return }
        scrollView.backgroundColor = theme.background
        active.values.forEach { $0.appliedVersion = nil }
        updateVisible()
    }

    func row(at point: CGPoint, from source: UIView) -> ListItemNode? {
        let location = source.convert(point, to: content.view)
        return active.values.first { $0.frame.contains(location) }
    }

    public func closeReveals(except: RevealableItemNode? = nil, animated: Bool = true) {
        for node in active.values {
            guard let reveal = node as? RevealableItemNode, reveal !== except else { continue }
            reveal.closeReveal(animated: animated)
        }
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) { updateVisible() }
    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { closeReveals() }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var target = touch.view
        while let view = target, view !== scrollView {
            if view is UIControl { return false }
            target = view.superview
        }
        return true
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        if hasOpenReveal { closeReveals(); return }
        guard let id = row(at: gesture.location(in: scrollView), from: scrollView)?.itemID,
              let item = items.first(where: { $0.id == id }) else { return }
        item.selected()
    }
}
