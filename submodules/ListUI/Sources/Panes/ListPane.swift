import UIKit
import AsyncDisplayKit

public final class ListPane: ScrollablePane {
    public let list: ListView
    public var node: ASDisplayNode { list }
    public var verticalOffset: CGFloat { list.contentOffset }
    public var maximumVerticalOffset: CGFloat {
        max(0, list.scrollView.contentSize.height - list.scrollView.bounds.height)
    }
    public var blocksHorizontalPaging: Bool { list.hasOpenReveal }
    public var geometryChanged: (() -> Void)?

    public init(list: ListView) {
        self.list = list
        list.contentGeometryChanged = { [weak self] in self?.geometryChanged?() }
    }

    public func setVerticalOffset(_ offset: CGFloat) {
        list.scrollView.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
    }

    public func setExternalScrollDriver(_ driver: ((CGFloat) -> Void)?) {
        list.setExternalScrollDriver(driver)
    }

    public func stopScrolling() {
        list.scrollView.setContentOffset(list.scrollView.contentOffset, animated: false)
    }

    public func closeInteractions() { list.closeReveals(animated: false) }
}
