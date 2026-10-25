import UIKit

public enum ListTransition {
    public static func animate(_ animated: Bool, changes: @escaping () -> Void,
                               completion: ((Bool) -> Void)? = nil) {
        if animated && !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.9,
                           initialSpringVelocity: 0, options: [.beginFromCurrentState, .allowUserInteraction],
                           animations: changes, completion: completion)
        } else {
            UIView.performWithoutAnimation(changes)
            completion?(true)
        }
    }
}
