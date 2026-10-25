import UIKit
import AsyncDisplayKit
import ListUI

/// The existing pinchable gallery participates in ListUI's single vertical scroll.
final class ProfileMediaPane: ASDisplayNode, ScrollablePane {
    var node: ASDisplayNode { self }
    private let grid = MediaGrid(count: 72)
    private(set) var verticalOffset: CGFloat = 0
    var maximumVerticalOffset: CGFloat { max(0, contentHeight + bottomInset - bounds.height) }
    var blocksHorizontalPaging: Bool {
        grid.gestureRecognizers?.contains { $0 is UIPinchGestureRecognizer && ($0.state == .began || $0.state == .changed) } ?? false
    }
    var geometryChanged: (() -> Void)?
    var offsetChanged: (() -> Void)?
    var zoomBegan: (() -> Void)?
    var bottomInset: CGFloat = 0 {
        didSet { if bottomInset != oldValue { geometryChanged?() } }
    }
    var month: Int { grid.month(at: max(0, verticalOffset)) }
    private var contentHeight: CGFloat = 0
    private var previousSize = CGSize.zero
    private var externalScroll: ((CGFloat) -> Void)?

    override init() {
        super.init()
        grid.onHeightChange = { [weak self] in self?.updateGeometry() }
    }

    override func didLoad() {
        super.didLoad()
        view.clipsToBounds = true
        view.backgroundColor = Palette.grouped
        view.addSubview(grid)
        for (index, image) in grid.subviews.enumerated() {
            image.isAccessibilityElement = true
            image.accessibilityLabel = "Photo \(index + 1)"
            image.accessibilityTraits = .image
        }
        grid.gestureRecognizers?.compactMap { $0 as? UIPinchGestureRecognizer }.forEach {
            $0.addTarget(self, action: #selector(pinching(_:)))
        }
        view.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Scroll down") { [weak self] _ in self?.scrollAccessible(1) ?? false },
            UIAccessibilityCustomAction(name: "Scroll up") { [weak self] _ in self?.scrollAccessible(-1) ?? false },
        ]
    }

    override func layout() {
        super.layout()
        updateGeometry()
    }

    private func updateGeometry() {
        guard bounds.width > 0 else { return }
        let height = grid.contentHeight(for: bounds.width)
        let changed = contentHeight != height || previousSize != bounds.size
        contentHeight = height
        previousSize = bounds.size
        placeGrid()
        if changed { geometryChanged?() }
    }

    private func placeGrid() {
        grid.frame = CGRect(x: 0, y: -verticalOffset, width: bounds.width, height: contentHeight)
    }

    func setVerticalOffset(_ offset: CGFloat) {
        guard offset.isFinite else { return }
        let changed = verticalOffset != offset
        verticalOffset = offset
        placeGrid()
        if changed { offsetChanged?() }
    }

    func setExternalScrollDriver(_ driver: ((CGFloat) -> Void)?) { externalScroll = driver }
    func stopScrolling() {} // The container owns all motion; this pane has no native scroller.

    @objc private func pinching(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .began { zoomBegan?() }
    }

    private func scrollAccessible(_ direction: CGFloat) -> Bool {
        guard let externalScroll else { return false }
        externalScroll(direction * bounds.height * 0.8)
        return true
    }
}
