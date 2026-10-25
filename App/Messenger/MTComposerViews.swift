//
//  MTComposerViews.swift
//  controller
//
//  Pieces of the Mini-Telegram composer: link previews (detected in the text, shown as a card
//  that drops onto the input bar and kept in the sent bubble), stickers (emoji cut out with a
//  white outline, suggested when the text is a single emoji), and the emoji panel that replaces
//  the keyboard.
//

import UIKit

// MARK: - Link previews

struct MTLinkPreview: Equatable, Codable {
    let url: String
    let site: String
    let title: String
    let scene: DemoPhotos.Scene

    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// The first link in `text`, with a made-up preview (the demo has no network).
    static func detect(in text: String) -> MTLinkPreview? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = detector?.firstMatch(in: text, options: [], range: range), let url = match.url,
              let host = url.host?.replacingOccurrences(of: "www.", with: "") else { return nil }
        let known: [String: (String, String, DemoPhotos.Scene)] = [
            "telegram.org": ("Telegram", "Telegram — a new era of communication", .aurora),
            "apple.com": ("Apple", "iPhone — new possibilities every day", .city),
            "github.com": ("GitHub", "Where software is built — over 100 million developers", .forest),
            "youtube.com": ("YouTube", "Watch your favorite videos and listen to music", .sunset),
            "figma.com": ("Figma", "Mini-Telegram designs · 24 screens", .bloom),
        ]
        let entry = known.first { host.hasSuffix($0.key) }?.value
        let name = host.split(separator: ".").first.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? host
        return MTLinkPreview(url: url.absoluteString, site: entry?.0 ?? name, title: entry?.1 ?? "Page on \(host)",
                             scene: entry?.2 ?? .ocean)
    }
}

/// The preview card: accent bar, site, title, thumbnail. Used on the input bar and in bubbles.
final class MTLinkView: UIView {
    private let bar = UIView()
    private let site = MTViews.label(size: 14, weight: .semibold, color: MTPalette.accent)
    private let title = MTViews.label(size: 14)
    private let thumb = UIImageView()
    static let height: CGFloat = 56

    init(_ preview: MTLinkPreview, tint: UIColor = MTPalette.accent) {
        super.init(frame: .zero)
        backgroundColor = tint.withAlphaComponent(0.12)
        layer.cornerRadius = 8
        layer.cornerCurve = .continuous
        clipsToBounds = true
        bar.backgroundColor = tint
        site.textColor = tint
        site.text = preview.site
        title.text = preview.title
        title.numberOfLines = 2
        title.font = .systemFont(ofSize: 13)
        thumb.image = DemoPhotos.image(preview.scene, size: CGSize(width: 120, height: 120), seed: 3)
        thumb.contentMode = .scaleAspectFill
        thumb.clipsToBounds = true
        thumb.layer.cornerRadius = 6
        for view in [bar, site, title, thumb] { addSubview(view) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        bar.frame = CGRect(x: 0, y: 0, width: 3, height: bounds.height)
        thumb.frame = CGRect(x: bounds.width - 52, y: 6, width: 44, height: 44)
        site.frame = CGRect(x: 10, y: 5, width: thumb.frame.minX - 16, height: 17)
        title.frame = CGRect(x: 10, y: 22, width: thumb.frame.minX - 16, height: 32)
    }
}

// MARK: - Stickers

enum MTStickers {
    private static let packs: [String: [String]] = [
        "🔥": ["🔥", "😎", "🌶️", "💥", "🚒", "🧯"],
        "❤️": ["❤️", "😍", "🥰", "💘", "💞", "🫶"],
        "😂": ["😂", "🤣", "😹", "😆", "🙃", "😜"],
        "👍": ["👍", "👌", "🤝", "💪", "🙌", "✅"],
        "🎉": ["🎉", "🥳", "🎊", "🍾", "🎈", "🪅"],
        "😢": ["😢", "😭", "🥺", "💔", "😿", "🫂"],
    ]

    /// Stickers for a single-emoji text, or nil when the text is anything else.
    static func suggestions(for text: String) -> [String]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 1, let character = trimmed.first,
              character.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation || $0.value > 0x2600 }) else { return nil }
        let key = packs.keys.first { $0.unicodeScalars.first == character.unicodeScalars.first } ?? trimmed
        return packs[key] ?? [trimmed, trimmed + "✨", "😀", "😎", "🤩", "👀"]
    }

    private static var cache: [String: UIImage] = [:]

    /// The emoji as a die-cut sticker: a thick white outline and a soft shadow.
    static func image(_ sticker: String, size: CGFloat = 150) -> UIImage {
        let key = "\(sticker)|\(size)"
        if let cached = cache[key] { return cached }
        let canvas = CGSize(width: size, height: size)
        let font = UIFont.systemFont(ofSize: size * (sticker.count > 1 ? 0.42 : 0.6))
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let text = sticker as NSString
        let measured = text.size(withAttributes: attributes)
        let origin = CGPoint(x: (size - measured.width) / 2, y: (size - measured.height) / 2)
        let glyphs = UIGraphicsImageRenderer(size: canvas).image { _ in text.draw(at: origin, withAttributes: attributes) }
        let silhouette = UIGraphicsImageRenderer(size: canvas).image { context in
            glyphs.draw(at: .zero)
            context.cgContext.setBlendMode(.sourceIn)
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fill(CGRect(origin: .zero, size: canvas))
        }
        let image = UIGraphicsImageRenderer(size: canvas).image { context in
            let outline = size * 0.04
            context.cgContext.setShadow(offset: CGSize(width: 0, height: size * 0.02), blur: size * 0.05,
                                        color: UIColor(white: 0, alpha: 0.35).cgColor)
            context.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
            for step in 0..<16 {
                let angle = CGFloat(step) / 16 * .pi * 2
                silhouette.draw(at: CGPoint(x: cos(angle) * outline, y: sin(angle) * outline))
            }
            context.cgContext.endTransparencyLayer()
            context.cgContext.setShadow(offset: .zero, blur: 0)
            glyphs.draw(at: .zero)
        }
        cache[key] = image
        return image
    }
}

/// The sticker suggestions strip: stickers pop in one after another, slightly tilted.
final class MTStickerStrip: UIView {
    var onPick: ((String, UIImageView) -> Void)?
    private let scroll = UIScrollView()
    private var cells: [UIImageView] = []
    private(set) var stickers: [String] = []
    static let height: CGFloat = 74

    override init(frame: CGRect) {
        super.init(frame: frame)
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true
        addSubview(scroll)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = bounds
        for (index, cell) in cells.enumerated() {
            cell.bounds = CGRect(x: 0, y: 0, width: 62, height: 62)
            cell.center = CGPoint(x: 12 + 36 + CGFloat(index) * 70, y: bounds.midY)
        }
        scroll.contentSize = CGSize(width: 24 + CGFloat(cells.count) * 70, height: bounds.height)
    }

    func show(_ stickers: [String]) {
        guard stickers != self.stickers else { return }
        self.stickers = stickers
        cells.forEach { $0.removeFromSuperview() }
        cells = stickers.enumerated().map { index, sticker in
            let cell = UIImageView(image: MTStickers.image(sticker, size: 124))
            cell.isUserInteractionEnabled = true
            cell.tag = index
            cell.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
            scroll.addSubview(cell)
            return cell
        }
        setNeedsLayout()
        layoutIfNeeded()
        for (index, cell) in cells.enumerated() {
            let tilt = CGFloat([-0.12, 0.08, -0.05, 0.1, -0.08, 0.06][index % 6])
            cell.transform = CGAffineTransform(translationX: 0, y: 30).scaledBy(x: 0.3, y: 0.3)
            cell.alpha = 0
            UIView.animate(withDuration: 0.5, delay: Double(index) * 0.04, usingSpringWithDamping: 0.55, initialSpringVelocity: 0.4) {
                cell.transform = CGAffineTransform(rotationAngle: tilt)
                cell.alpha = 1
            }
        }
    }

    func clear() {
        stickers = []
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard let cell = gesture.view as? UIImageView else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onPick?(stickers[cell.tag], cell)
    }
}

/// A sticker message: no bubble, just the sticker and a time pill.
final class MTStickerBubble: UIView, MTBubbleContent {
    let image = UIImageView()
    private let meta: UIView
    private let checks: MTChecksView?

    init(sticker: String, outgoing: Bool, time: String, read: Bool) {
        (meta, checks) = Self.makeMeta(time: time, outgoing: outgoing, read: read, onMedia: true)
        super.init(frame: .zero)
        image.image = MTStickers.image(sticker)
        image.contentMode = .scaleAspectFit
        addSubview(image)
        addSubview(meta)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func fittingSize(maxWidth: CGFloat) -> CGSize {
        CGSize(width: 150, height: 150)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        image.frame = bounds
        meta.frame.origin = CGPoint(x: bounds.width - 6 - meta.bounds.width, y: bounds.height - 4 - meta.bounds.height)
    }

    func setRead(_ read: Bool) {
        checks?.set(read: read, animated: true)
    }
}

// MARK: - Emoji panel

/// Shown in place of the keyboard (as the text view's input view), at the keyboard's height.
final class MTEmojiPanel: UIInputView {
    var onEmoji: ((String) -> Void)?
    var onDelete: (() -> Void)?

    private let scroll = UIScrollView()
    private let tabs = LiquidSelector(symbols: ["clock", "face.smiling", "pawprint", "fork.knife", "soccerball", "heart"],
                                      style: .tabs, liquid: MTPalette.accent, selectedTint: .white, normalTint: MTPalette.secondary)
    private let delete = MTViews.iconButton("delete.left", size: 20, tint: MTPalette.secondary)
    private var sections: [(title: String, emoji: [String])] = []
    private var sectionTops: [CGFloat] = []
    private var jumping = false
    static var recent = ["🔥", "❤️", "😂", "👍", "🎉", "😢", "🚀", "✨"]

    init(height: CGFloat) {
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: height), inputViewStyle: .keyboard)
        func range(_ from: UInt32, _ to: UInt32) -> [String] {
            (from...to).compactMap { Unicode.Scalar($0).map { String($0) } }
        }
        sections = [
            ("Frequently Used", Self.recent),
            ("Smileys", range(0x1F600, 0x1F64F)),
            ("Animals", range(0x1F400, 0x1F43C)),
            ("Food", range(0x1F345, 0x1F37F)),
            ("Activities", ["⚽️", "🏀", "🏈", "⚾️", "🎾", "🏐", "🏉", "🎱", "🏓", "🏸", "🥊", "⛳️", "🎯", "🎳", "🎮", "🎲",
                            "🧩", "🎨", "🎬", "🎤", "🎧", "🎸", "🎹", "🥁", "🎻", "🏆", "🥇", "🎪", "🛹", "🚴"]),
            ("Symbols", ["❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "💔", "❣️", "💕", "💞", "💓", "💗", "💖", "💘",
                         "✨", "⭐️", "🌟", "💫", "🔥", "💥", "💯", "✅", "❌", "⚡️", "🎉", "🚀"]),
        ]
        scroll.delegate = self
        scroll.showsVerticalScrollIndicator = false
        addSubview(scroll)
        tabs.addTarget(self, action: #selector(tabChanged), for: .valueChanged)
        addSubview(tabs)
        delete.addAction(UIAction { [weak self] _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            self?.onDelete?()
        }, for: .touchUpInside)
        addSubview(delete)
        tabs.select(1, animated: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var built = false

    override func layoutSubviews() {
        super.layoutSubviews()
        let bottom = safeAreaInsets.bottom
        tabs.frame = CGRect(x: 8, y: bounds.height - bottom - 44, width: bounds.width - 66, height: 36)
        delete.frame = CGRect(x: bounds.width - 54, y: bounds.height - bottom - 46, width: 44, height: 40)
        scroll.frame = CGRect(x: 0, y: 0, width: bounds.width, height: tabs.frame.minY - 4)
        guard !built, bounds.width > 0 else { return }
        built = true
        build()
        scroll.contentOffset.y = sectionTops[1]
    }

    private func build() {
        let columns = 8
        let size = (bounds.width - 16) / CGFloat(columns)
        var y: CGFloat = 4
        for (index, section) in sections.enumerated() {
            sectionTops.append(y)
            let title = MTViews.label(section.title.uppercased(), size: 12, weight: .semibold, color: MTPalette.secondary)
            title.frame = CGRect(x: 12, y: y + 6, width: bounds.width - 24, height: 16)
            scroll.addSubview(title)
            y += 26
            for (position, emoji) in section.emoji.enumerated() {
                let cell = UILabel(frame: CGRect(x: 8 + CGFloat(position % columns) * size, y: y + CGFloat(position / columns) * size,
                                                 width: size, height: size))
                cell.text = emoji
                cell.font = .systemFont(ofSize: 30)
                cell.textAlignment = .center
                cell.isUserInteractionEnabled = true
                cell.tag = index
                cell.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
                scroll.addSubview(cell)
            }
            y += CGFloat((section.emoji.count + columns - 1) / columns) * size + 8
        }
        scroll.contentSize = CGSize(width: bounds.width, height: y)
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard let cell = gesture.view as? UILabel, let emoji = cell.text else { return }
        UIDevice.current.playInputClick()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        cell.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.45, initialSpringVelocity: 0.5) {
            cell.transform = .identity
        }
        onEmoji?(emoji)
    }

    @objc private func tabChanged() {
        guard sectionTops.indices.contains(tabs.selectedIndex) else { return }
        jumping = true
        let target = min(sectionTops[tabs.selectedIndex], max(0, scroll.contentSize.height - scroll.bounds.height))
        UIView.animate(withDuration: 0.35, delay: 0, options: .curveEaseInOut, animations: {
            self.scroll.contentOffset.y = target
        }, completion: { _ in self.jumping = false })
    }
}

extension MTEmojiPanel: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !jumping, !sectionTops.isEmpty else { return }
        // The liquid tab follows the section under the top edge.
        let current = sectionTops.lastIndex { $0 <= scrollView.contentOffset.y + 30 } ?? 0
        if current != tabs.selectedIndex { tabs.select(current) }
    }
}

extension MTEmojiPanel: UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}
