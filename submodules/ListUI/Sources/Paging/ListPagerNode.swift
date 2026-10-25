import UIKit
import AsyncDisplayKit

public final class ListPagerNode: ASDisplayNode, UIGestureRecognizerDelegate {
    public var selectedPageChanged: ((String) -> Void)?
    public private(set) var selectedPageID: String?
    private var pages: [ListPage] = []
    private var panes: [String: any ScrollablePane] = [:]
    private var savedOffsets: [String: CGFloat] = [:]
    private let tabs = ListTabsNode()
    private var pan: PagingGestureRecognizer!
    private var theme: ListTheme
    private var pagePosition: CGFloat = 0
    private var initialPosition: CGFloat = 0
    private var settling = false
    private var transitionGeneration = 0
    private var selectedIndex: Int { pages.firstIndex(where: { $0.id == selectedPageID }) ?? 0 }
    private var tabsHeight: CGFloat { pages.count > 1 ? 48 : 0 }
    public var currentPane: (any ScrollablePane)? { selectedPageID.flatMap { panes[$0] } }
    public var currentList: ListView? { (currentPane as? ListPane)?.list }
    var compositionPaneChanged: (((any ScrollablePane)?) -> Void)?
    var horizontalPagingBegan: (() -> Void)?
    var verticalScrollDriver: ((CGFloat) -> Void)? {
        didSet { panes.values.forEach { $0.setExternalScrollDriver(verticalScrollDriver) } }
    }
    var horizontalGestureRecognizer: UIGestureRecognizer { _ = view; return pan }
    var isPaging: Bool { settling || pan?.state == .began || pan?.state == .changed }

    public init(theme: ListTheme) {
        self.theme = theme
        super.init()
        addSubnode(tabs)
    }

    public override func didLoad() {
        super.didLoad()
        view.clipsToBounds = true
        pan = PagingGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.delegate = self
        view.addGestureRecognizer(pan)
        tabs.selected = { [weak self] index in self?.select(index: index, animated: true) }
    }

    public func apply(state: ItemListState, theme: ListTheme, animated: Bool = true) {
        _ = view
        self.theme = theme
        transitionGeneration += 1
        panes.values.forEach { $0.node.view.layer.removeAllAnimations() }

        pan.isEnabled = false
        pages = state.pages
        if let requested = state.selectedPageID, pages.contains(where: { $0.id == requested }) {
            selectedPageID = requested
        } else if !pages.contains(where: { $0.id == selectedPageID }) {
            selectedPageID = pages.first?.id
        }
        pagePosition = CGFloat(selectedIndex)
        settling = false
        let ids = Set(pages.map(\.id))
        for id in Array(panes.keys) where !ids.contains(id) {
            panes.removeValue(forKey: id)?.node.removeFromSupernode()
            savedOffsets.removeValue(forKey: id)
        }
        savedOffsets = savedOffsets.filter { ids.contains($0.key) }
        tabs.apply(pages: pages, theme: theme)
        tabs.isHidden = pages.count <= 1
        ensureLists(near: selectedIndex)
        for page in pages {
            if let pane = panes[page.id] {
                if let list = (pane as? ListPane)?.list, page.makePane == nil {
                    list.hasPages = pages.count > 1
                    list.theme = theme
                    list.apply(items: page.items, animated: animated)
                }
                page.updatePane?(pane, theme)
            }
        }
        backgroundColor = theme.background
        pan.isEnabled = pages.count > 1
        pruneLists()
        compositionPaneChanged?(currentPane)
        setNeedsLayout()
    }

    public override func layout() {
        super.layout()
        tabs.frame = CGRect(x: 0, y: 0, width: bounds.width, height: tabsHeight)
        placePages()
    }

    private func ensureLists(near index: Int) {
        guard !pages.isEmpty else { return }
        for i in max(0, index - 1)...min(pages.count - 1, index + 1) {
            let page = pages[i]
            guard panes[page.id] == nil else { continue }
            let pane: any ScrollablePane
            if let factory = page.makePane {
                pane = factory(theme)
            } else {
                pane = ListPane(list: ListView(theme: theme))
            }
            if let list = (pane as? ListPane)?.list {
                list.hasPages = pages.count > 1
                list.pagingRecognizer = pan
                list.gestureLocation = { [weak self] source, point in
                    guard let self else { return (point.x, source.bounds.width) }
                    return (source.convert(point, to: self.view).x, self.bounds.width)
                }
            }
            panes[page.id] = pane
            addSubnode(pane.node)
            pane.node.frame = CGRect(x: (CGFloat(i) - pagePosition) * bounds.width, y: tabsHeight,
                                     width: bounds.width, height: max(0, bounds.height - tabsHeight))
            if let list = (pane as? ListPane)?.list, page.makePane == nil {
                list.apply(items: page.items, animated: false)
                list.contentOffset = savedOffsets[page.id] ?? 0
            } else {
                pane.setVerticalOffset(savedOffsets[page.id] ?? 0)
            }
            pane.setExternalScrollDriver(verticalScrollDriver)
            page.updatePane?(pane, theme)
        }

        view.bringSubviewToFront(tabs.view)
    }

    private func pruneLists() {
        let keep = Set(pages.enumerated().filter { abs($0.offset - selectedIndex) <= 1 }.map { $0.element.id })
        for id in Array(panes.keys) where !keep.contains(id) {
            if let pane = panes.removeValue(forKey: id) {
                savedOffsets[id] = max(0, pane.verticalOffset)
                pane.node.removeFromSupernode()
            }
        }
    }

    private func placePages() {
        for (index, page) in pages.enumerated() {
            panes[page.id]?.node.frame = CGRect(x: (CGFloat(index) - pagePosition) * bounds.width, y: tabsHeight,
                                          width: bounds.width, height: max(0, bounds.height - tabsHeight))
        }
        tabs.setPosition(pagePosition)
    }

    private func select(index: Int, animated: Bool) {
        guard pages.indices.contains(index), !settling else { return }
        currentPane?.closeInteractions()
        ensureLists(near: index)
        placePages()
        view.layoutIfNeeded()
        settling = true
        transitionGeneration += 1
        let generation = transitionGeneration
        pagePosition = CGFloat(index)
        ListTransition.animate(animated, changes: { self.placePages() }, completion: { [weak self] _ in
            guard let self, self.transitionGeneration == generation, self.pages.indices.contains(index) else { return }
            self.selectedPageID = self.pages[index].id
            self.settling = false
            self.pruneLists()
            self.tabs.setPosition(self.pagePosition, settled: true)
            self.compositionPaneChanged?(self.currentPane)
            self.selectedPageChanged?(self.pages[index].id)
        })
    }

    public override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === pan, pages.count > 1, !settling else { return false }
        let velocity = pan.velocity(in: view)
        let location = pan.location(in: view)
        let translation = pan.translation(in: view)
        let point = CGPoint(x: location.x - translation.x, y: location.y - translation.y)
        guard abs(velocity.x) > abs(velocity.y), point.y >= tabsHeight else { return false }
        let row = currentList?.row(at: point, from: view) as? RevealableItemNode
        if currentPane?.blocksHorizontalPaging == true {
            return false
        }
        
        return ListGesturePolicy.owner(hasPages: true, startX: point.x, width: bounds.width,
                                       rowHasActions: row?.hasActions ?? false, rowIsOpen: row?.isRevealOpen ?? false) == .paging
    }

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        guard bounds.width > 0 else { return }
        switch gesture.state {
        case .began:
            horizontalPagingBegan?()
            initialPosition = CGFloat(selectedIndex)
            ensureLists(near: selectedIndex)
        case .changed:
            let proposed = initialPosition - gesture.translation(in: view).x / bounds.width
            let clamped = min(CGFloat(pages.count - 1), max(0, proposed))
            pagePosition = clamped + (proposed - clamped) * 0.18
            placePages()
        case .ended, .cancelled, .failed:
            let target = ListGesturePolicy.targetPage(current: selectedIndex, count: pages.count,
                translation: gesture.translation(in: view).x, velocity: gesture.velocity(in: view).x,
                width: bounds.width, cancelled: gesture.state != .ended)
            select(index: target, animated: true)
        default:
            break
        }
    }
}
