import UIKit
import AsyncDisplayKit

private final class ListScrollView: UIScrollView {
    var externalScroll: ((CGFloat) -> Void)?
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panGestureRecognizer {
            let velocity = panGestureRecognizer.velocity(in: self)
            return abs(velocity.y) >= abs(velocity.x)
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
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
    private static let layoutQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "Contact.ListUI.layout"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 2
        return queue
    }()
    public var theme: ListTheme { didSet { if theme != oldValue { invalidatePresentation() } } }
    public var hasPages = false
    public var contentGeometryChanged: (() -> Void)?
    public var scrollingChanged: ((ListView) -> Void)?
    public var scrollingBegan: ((ListView) -> Void)?
    public var scrollingTarget: ((ListView, CGPoint, CGPoint) -> CGPoint)?
    public var mediaPlaybackEnabled = true {
        didSet {
            guard mediaPlaybackEnabled != oldValue else { return }
            updateMediaVisibility()
        }
    }
    private var mediaScrolling = false
    private var lastMediaScrollTime: CFTimeInterval = 0
    private var mediaResume: DispatchWorkItem?
    public var contentInsets: UIEdgeInsets = .zero {
        didSet {
            guard isNodeLoaded, contentInsets != oldValue else { return }
            scrollView.contentInset = contentInsets
            scrollView.verticalScrollIndicatorInsets = contentInsets
        }
    }
    var pagingRecognizer: UIGestureRecognizer?
    var gestureLocation: ((UIView, CGPoint) -> (CGFloat, CGFloat))?
    private var items: [any ListItem] = []
    private var itemIDs: [String] = []
    private var itemVersions: [Int] = []
    private var itemReuseIdentifiers: [String] = []
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
        get { pendingOffset ?? (isNodeLoaded ? scrollView.contentOffset.y : 0) }
        set {
            if isNodeLoaded && layoutWidth > 0 {
                restoreOffset(newValue)
                pendingOffset = nil
            } else {
                pendingOffset = newValue
            }
        }
    }
    public var hasOpenReveal: Bool { active.values.contains { $0.blocksHorizontalPaging } }
    public func itemNode(for id: String) -> ListItemNode? { active[id] }

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
        scrollView.contentInset = contentInsets
        scrollView.verticalScrollIndicatorInsets = contentInsets
        tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tapRecognizer.delegate = self
        scrollView.addGestureRecognizer(tapRecognizer)
        if let pagingRecognizer {
            tapRecognizer.require(toFail: pagingRecognizer)
        }
        applyScrollDriver()
    }

    public func apply(items next: [any ListItem], animated: Bool = true) {
        let nextIDs = next.map(\.id)
        let transaction = ListTransaction(previous: itemIDs, next: nextIDs)
        let anchorIndex = frames.firstIndex { $0.maxY > contentOffset }
        let anchor = anchorIndex.map { (itemIDs[$0], frames[$0].minY - contentOffset) }
        let oldOffset = contentOffset
        closeReveals(animated: false)
        items = next
        itemIDs = nextIDs
        itemVersions = next.map(\.version)
        itemReuseIdentifiers = next.map(\.reuseIdentifier)
        guard isNodeLoaded, layoutWidth > 0 else { setNeedsLayout(); return }
        rebuildFrames()
        if oldOffset > 0, let anchor, let index = itemIDs.firstIndex(of: anchor.0) {
            restoreOffset(frames[index].minY - anchor.1)
        } else {
            restoreOffset(oldOffset)
        }
        for id in transaction.deleted {
            guard let node = active.removeValue(forKey: id) else { continue }

            node.view.isUserInteractionEnabled = false
            node.updateViewport(isVisible: false, isScrolling: false)
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
        let minimum = -contentInsets.top
        let maximum = max(minimum, scrollView.contentSize.height + contentInsets.bottom - bounds.height)
        scrollView.contentOffset.y = min(max(minimum, offset), maximum)
    }

    func setDrivenContentOffset(_ offset: CGFloat) {
        if !isNodeLoaded || layoutWidth == 0 { pendingOffset = offset }
        else { scrollView.setContentOffset(CGPoint(x: 0, y: offset), animated: false) }
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
        let visibleIDs = Set(indices.map { itemIDs[$0] })
        for id in Array(active.keys) where !visibleIDs.contains(id) {
            if let node = active.removeValue(forKey: id) { recycle(node) }
        }
        for index in indices {
            let item = items[index]
            let id = itemIDs[index]
            let reuseIdentifier = itemReuseIdentifiers[index]
            let node: ListItemNode
            if let existing = active[id], existing.reuseIdentifier == reuseIdentifier {
                node = existing
            } else {
                if let old = active.removeValue(forKey: id) { recycle(old) }
                node = pool[reuseIdentifier]?.popLast() ?? item.makeNode()
                node.reuseIdentifier = reuseIdentifier
                node.itemID = id
                node.view.isUserInteractionEnabled = true
                active[id] = node
                content.addSubnode(node)
                if animated && inserted.contains(id) { node.view.alpha = 0 }
            }
            let version = itemVersions[index]
            if node.appliedVersion != version || node.appliedWidth != layoutWidth {
                node.layoutOperation?.cancel()
                node.layoutOperation = nil
                let resolvedTheme = theme.resolved(for: view.traitCollection)
                item.update(node: node, theme: resolvedTheme)
                node.appliedVersion = version
                node.appliedWidth = layoutWidth
                configureGestures(node)
                if let item = item as? any AsyncListItem {
                    prepare(item, node: node, width: layoutWidth, theme: resolvedTheme)
                }
            }
            if node.frame != frames[index] { node.frame = frames[index] }
            if node.view.alpha != 1 { node.view.alpha = 1 }
        }
        updateMediaVisibility()
    }

    private func updateMediaVisibility() {
        let viewport = CGRect(x: 0, y: scrollView.contentOffset.y + contentInsets.top,
                              width: bounds.width,
                              height: max(0, bounds.height - contentInsets.top - contentInsets.bottom))
        for node in active.values {
            let visibleHeight = node.frame.intersection(viewport).height
            let visible = mediaPlaybackEnabled && node.frame.height > 0
                && visibleHeight >= node.frame.height * 0.75
            node.updateViewport(isVisible: visible, isScrolling: mediaScrolling)
        }
    }

    private func suspendMediaForScrolling() {
        lastMediaScrollTime = CACurrentMediaTime()
        if !mediaScrolling {
            mediaScrolling = true
            updateMediaVisibility()
        }
        scheduleMediaResume()
    }

    private func scheduleMediaResume() {
        guard mediaResume == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.mediaResume = nil
            if self.scrollView.isDragging || self.scrollView.isDecelerating
                || CACurrentMediaTime() - self.lastMediaScrollTime < 0.2 {
                self.scheduleMediaResume()
                return
            }
            self.mediaScrolling = false
            self.updateMediaVisibility()
        }
        mediaResume = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func prepare(_ item: any AsyncListItem, node: ListItemNode, width: CGFloat, theme: ListTheme) {
        let id = item.id
        let traits = view.traitCollection
        let operation = BlockOperation()
        node.layoutOperation = operation
        operation.addExecutionBlock { [weak self, weak node, weak operation] in
            guard let operation, !operation.isCancelled else { return }
            let apply = item.prepareLayout(for: width, theme: theme, traits: traits)
            guard !operation.isCancelled else { return }
            DispatchQueue.main.async { [weak self, weak node] in
                guard let self, let node, !operation.isCancelled,
                      self.active[id] === node, node.layoutOperation === operation else { return }
                node.layoutOperation = nil
                apply(node)
            }
        }
        Self.layoutQueue.addOperation(operation)
    }

    private func configureGestures(_ node: ListItemNode) {
        for gesture in node.interactionPanGestures {
            scrollView.panGestureRecognizer.require(toFail: gesture)
        }
        for gesture in node.selectionFailureGestures {
            tapRecognizer?.require(toFail: gesture)
        }
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
        node.updateViewport(isVisible: false, isScrolling: false)
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

    public func closeReveals(except: ListItemNode? = nil, animated: Bool = true) {
        for node in active.values {
            guard node !== except else { continue }
            node.closeInteractions(animated: animated)
        }
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        suspendMediaForScrolling()
        updateVisible()
        scrollingChanged?(self)
    }
    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        suspendMediaForScrolling()
        closeReveals()
        scrollingBegan?(self)
    }
    public func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                         targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        if let scrollingTarget { targetContentOffset.pointee = scrollingTarget(self, velocity, targetContentOffset.pointee) }
    }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { scheduleMediaResume() }
    }
    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { scheduleMediaResume() }
    public func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { scheduleMediaResume() }

    deinit { mediaResume?.cancel() }

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
