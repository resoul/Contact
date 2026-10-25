import UIKit
import AsyncDisplayKit

public final class ListPane: ScrollablePane {
    public let list: ListView
    public var node: ASDisplayNode { list }
    public var verticalOffset: CGFloat { list.contentOffset + list.contentInsets.top }
    public var maximumVerticalOffset: CGFloat {
        max(0, list.scrollView.contentSize.height + list.contentInsets.top + list.contentInsets.bottom - list.scrollView.bounds.height)
    }
    public var blocksHorizontalPaging: Bool { list.hasOpenReveal }
    public var geometryChanged: (() -> Void)?

    public init(list: ListView) {
        self.list = list
        list.contentGeometryChanged = { [weak self] in self?.geometryChanged?() }
    }

    public func setVerticalOffset(_ offset: CGFloat) {
        list.setDrivenContentOffset(offset - list.contentInsets.top)
    }

    public func setExternalScrollDriver(_ driver: ((CGFloat) -> Void)?) {
        list.setExternalScrollDriver(driver)
    }

    public func stopScrolling() {
        list.scrollView.setContentOffset(list.scrollView.contentOffset, animated: false)
    }

    public func closeInteractions() { list.closeReveals(animated: false) }
}
