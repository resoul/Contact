import UIKit

/// Small images shared by the folder screens: Telegram's coloured type badges,
/// emoji icons and the folder's own icon.
@MainActor
enum FolderIcons {
    private static var cache: [String: UIImage] = [:]

    static func badge(_ symbol: String, color: UIColor, size: CGFloat = 30) -> UIImage {
        let key = "badge|\(symbol)|\(color.hashValue)|\(size)"
        if let cached = cache[key] { return cached }
        let image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
            color.setFill()
            UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: size, height: size), cornerRadius: size * 0.26).fill()
            let configuration = UIImage.SymbolConfiguration(pointSize: size * 0.5, weight: .semibold)
            guard let glyph = UIImage(systemName: symbol, withConfiguration: configuration)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) else { return }
            glyph.draw(at: CGPoint(x: (size - glyph.size.width) / 2, y: (size - glyph.size.height) / 2))
        }
        cache[key] = image
        return image
    }

    static func emoji(_ emoji: String, size: CGFloat) -> UIImage {
        let key = "emoji|\(emoji)|\(size)"
        if let cached = cache[key] { return cached }
        let text = NSAttributedString(string: emoji, attributes: [.font: UIFont.systemFont(ofSize: size * 0.82)])
        let bounds = text.size()
        let image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
            text.draw(at: CGPoint(x: (size - bounds.width) / 2, y: (size - bounds.height) / 2))
        }
        cache[key] = image
        return image
    }

    /// The folder's emoji, or a folder glyph in its colour.
    static func folder(_ folder: ChatFolder?, size: CGFloat) -> UIImage? {
        if let value = folder?.emoji { return Self.emoji(value, size: size) }
        let configuration = UIImage.SymbolConfiguration(pointSize: size * 0.7, weight: .regular)
        return UIImage(systemName: "folder.fill", withConfiguration: configuration)?
            .withTintColor(folder?.tint ?? Palette.accent, renderingMode: .alwaysOriginal)
    }
}
