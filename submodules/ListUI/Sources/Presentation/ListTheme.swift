import UIKit

public struct ListTheme: Equatable {
    public var background: UIColor
    public var rowBackground: UIColor
    public var primary: UIColor
    public var secondary: UIColor
    public var separator: UIColor
    public var accent: UIColor

    public init(background: UIColor = .systemGroupedBackground, rowBackground: UIColor = .systemBackground,
                primary: UIColor = .label, secondary: UIColor = .secondaryLabel,
                separator: UIColor = .separator, accent: UIColor = .systemBlue) {
        self.background = background
        self.rowBackground = rowBackground
        self.primary = primary
        self.secondary = secondary
        self.separator = separator
        self.accent = accent
    }

    public func resolved(for traits: UITraitCollection) -> ListTheme {
        ListTheme(background: background.resolvedColor(with: traits), rowBackground: rowBackground.resolvedColor(with: traits),
                  primary: primary.resolvedColor(with: traits), secondary: secondary.resolvedColor(with: traits),
                  separator: separator.resolvedColor(with: traits), accent: accent.resolvedColor(with: traits))
    }
}
