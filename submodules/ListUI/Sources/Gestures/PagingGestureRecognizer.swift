import UIKit

final class PagingGestureRecognizer: UIPanGestureRecognizer {
    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        maximumNumberOfTouches = 1
        cancelsTouchesInView = true
    }
}
