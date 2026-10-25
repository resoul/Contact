import UIKit
import AsyncDisplayKit

open class ListItemNode: ASDisplayNode {
    public let contentNode = ASDisplayNode()
    public internal(set) var itemID: String?
    var appliedVersion: Int?
    var appliedWidth: CGFloat = 0
    var reuseIdentifier = ""

    public override init() {
        super.init()
        addSubnode(contentNode)
    }

    open override func didLoad() {
        super.didLoad()
        view.clipsToBounds = true
    }

    open override func layout() {
        super.layout()
        contentNode.frame = bounds
    }

    open func prepareForReuse() {
        itemID = nil
        appliedVersion = nil
        appliedWidth = 0
        view.layer.removeAllAnimations()
        view.alpha = 1
    }
}
