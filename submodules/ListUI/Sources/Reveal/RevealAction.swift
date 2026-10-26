import UIKit

public struct RevealAction {
    public let id: String
    public let title: String
    public let systemImage: String
    public let color: UIColor
    public let isDestructive: Bool
    public let handler: () -> Void

    public init(
        id: String,
        title: String,
        systemImage: String,
        color: UIColor,
        isDestructive: Bool = false,
        handler: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.color = color
        self.isDestructive = isDestructive
        self.handler = handler
    }
}
