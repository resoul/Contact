import UIKit
import AsyncDisplayKit

public protocol ScrollablePane: AnyObject {
    var node: ASDisplayNode { get }
    var verticalOffset: CGFloat { get }
    var maximumVerticalOffset: CGFloat { get }
    var blocksHorizontalPaging: Bool { get }
    var geometryChanged: (() -> Void)? { get set }
    func setVerticalOffset(_ offset: CGFloat)
    func setExternalScrollDriver(_ driver: ((CGFloat) -> Void)?)
    func stopScrolling()
    func closeInteractions()
}

public extension ScrollablePane {
    var blocksHorizontalPaging: Bool { false }
    func closeInteractions() {}
}
