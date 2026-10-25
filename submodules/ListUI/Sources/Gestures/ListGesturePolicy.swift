import Foundation

public enum ListGesturePolicy {
    public enum Owner: Equatable { case paging, reveal, none }

    public static func edgeWidth(for width: CGFloat) -> CGFloat {
        max(22, min(80, width / 6))
    }

    public static func owner(hasPages: Bool, startX: CGFloat, width: CGFloat,
                             rowHasActions: Bool, rowIsOpen: Bool) -> Owner {
        if rowIsOpen { return .reveal }
        if !hasPages { return rowHasActions ? .reveal : .none }
        let edge = edgeWidth(for: width)
        if startX < edge || startX > width - edge {
            return rowHasActions ? .reveal : .none
        }
        return .paging
    }

    public static func targetPage(current: Int, count: Int, translation: CGFloat,
                                  velocity: CGFloat, width: CGFloat, cancelled: Bool) -> Int {
        guard !cancelled, width > 0, count > 0 else { return current }
        let direction: Int
        if abs(velocity) > 350 {
            direction = velocity < 0 ? 1 : -1
        } else if abs(translation) > width * 0.28 {
            direction = translation < 0 ? 1 : -1
        } else {
            direction = 0
        }
        return min(count - 1, max(0, current + direction))
    }
}
