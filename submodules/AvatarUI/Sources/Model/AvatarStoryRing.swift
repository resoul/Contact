import UIKit

/// Stories ring drawn around an avatar. Seen stories come first as thin segments,
/// unseen ones follow with the active gradient, like Telegram's chat list.
public struct AvatarStoryRing: Equatable {
    public var totalCount: Int
    public var unseenCount: Int
    public var unseenColors: [UIColor]
    public var seenColors: [UIColor]
    public var lineWidth: CGFloat
    public var inactiveLineWidth: CGFloat

    public init(
        totalCount: Int,
        unseenCount: Int,
        unseenColors: [UIColor],
        seenColors: [UIColor],
        lineWidth: CGFloat = 2.33,
        inactiveLineWidth: CGFloat = 1.33
    ) {
        self.totalCount = totalCount
        self.unseenCount = unseenCount
        self.unseenColors = unseenColors
        self.seenColors = seenColors
        self.lineWidth = lineWidth
        self.inactiveLineWidth = inactiveLineWidth
    }

    public var hasUnseen: Bool { unseenCount > 0 }
}
