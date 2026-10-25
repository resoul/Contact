//
//  MessageViews.swift
//  controller
//
//  Mini-Telegram message bubbles (text, voice, photos, round video), the cell that holds them, the
//  date pill used as a sticky section header (the floating date) and the pinned-messages bar.
//
//  Bubbles of one sender run together like Telegram's: big corners outside, small ones where they
//  touch, and a tail on the last one; when a new message arrives the tail flows down to it. A
//  bubble can carry a reply quote and an "изм." mark; reactions sit in chips under it.
//

import UIKit

struct Message: Codable {
    enum Kind: Codable {
        case text(String)
        case voice(TimeInterval)
        case photos([DemoPhotos.Scene])
        case round(DemoPhotos.Scene)
        case sticker(String)
        /// The "Unread messages" band, not a message.
        case unreadDivider
    }

    struct Quote: Codable {
        let name: String
        let text: String
    }

    let id: Int
    var storageID = UUID()
    var timestamp = Int64(Date().timeIntervalSince1970 * 1000)
    var kind: Kind
    var outgoing: Bool
    var time: String
    var read = true
    /// Index into MessengerData.pinnedMessages when this message is pinned.
    var pinned: Int?
    var reply: Quote?
    var link: LinkPreview?
    var edited = false
    var reactions: [String] = []
    var channelPost: ChannelPost?

    init(kind: Kind, outgoing: Bool, time: String, read: Bool = true, pinned: Int? = nil, reply: Quote? = nil) {
        id = Int.random(in: 1...Int.max)
        self.kind = kind
        self.outgoing = outgoing
        self.time = time
        self.read = read
        self.pinned = pinned
        self.reply = reply
    }

    var isDivider: Bool {
        if case .unreadDivider = kind { return true }
        return false
    }

    var text: String? {
        if case .text(let text) = kind { return text }
        return nil
    }

    /// One line for quotes and menus.
    var summary: String {
        switch kind {
        case .text(let text): return text
        case .voice: return "🎤 Voice message"
        case .photos(let scenes): return scenes.count == 1 ? "🖼 Photo" : "🖼 Album"
        case .round: return "📹 Video message"
        case .sticker(let sticker): return "\(sticker) Sticker"
        case .unreadDivider: return ""
        }
    }
}

/// Where a bubble sits in a run of messages from the same sender.
struct BubbleStyle: Equatable {
    var outgoing: Bool
    var joinedTop = false
    var joinedBottom = false

    var tail: Bool { !joinedBottom }
}

/// The bubble's outline as a shape layer under its content, so the tail can stick out and the
/// outline can morph when the tail moves on to the next message.
final class BubbleFill {
    let layer = CAShapeLayer()
    var style: BubbleStyle
    var color: UIColor

    init(style: BubbleStyle, color: UIColor) {
        self.style = style
        self.color = color
    }

    func attach(to view: UIView) {
        view.layer.insertSublayer(layer, at: 0)
        view.backgroundColor = .clear
    }

    /// Lays the outline out for `view`'s size; `animated` morphs from the current outline.
    func update(in view: UIView, animated: Bool = false) {
        layer.fillColor = color.resolvedColor(with: view.traitCollection).cgColor
        layer.frame = view.bounds
        let path = Self.path(size: view.bounds.size, style: style)
        if animated, let old = layer.path {
            let morph = CABasicAnimation(keyPath: "path")
            morph.fromValue = old
            morph.toValue = path
            morph.duration = 0.35
            morph.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(morph, forKey: "morph")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.path = path
        CATransaction.commit()
    }

    /// Drawn for an outgoing bubble (tail on the right) and mirrored for incoming ones. Every
    /// variant has the same elements, so a path animation between them is smooth.
    static func path(size: CGSize, style: BubbleStyle) -> CGPath {
        let w = size.width, h = size.height
        let big: CGFloat = min(17, h / 2), small: CGFloat = 6
        let topRight = style.joinedTop ? small : big
        let bottomRight = style.joinedBottom ? small : big
        let path = UIBezierPath()
        path.move(to: CGPoint(x: big, y: 0))
        path.addLine(to: CGPoint(x: w - topRight, y: 0))
        path.addArc(withCenter: CGPoint(x: w - topRight, y: topRight), radius: topRight, startAngle: -.pi / 2, endAngle: 0,
                    clockwise: true)
        if style.tail {
            path.addLine(to: CGPoint(x: w, y: h - 11))
            path.addQuadCurve(to: CGPoint(x: w + 6, y: h), controlPoint: CGPoint(x: w, y: h - 1))
        } else {
            path.addLine(to: CGPoint(x: w, y: h - bottomRight))
            path.addQuadCurve(to: CGPoint(x: w - bottomRight, y: h), controlPoint: CGPoint(x: w, y: h))
        }
        path.addLine(to: CGPoint(x: big, y: h))
        path.addArc(withCenter: CGPoint(x: big, y: h - big), radius: big, startAngle: .pi / 2, endAngle: .pi, clockwise: true)
        path.addLine(to: CGPoint(x: 0, y: big))
        path.addArc(withCenter: CGPoint(x: big, y: big), radius: big, startAngle: .pi, endAngle: .pi * 1.5, clockwise: true)
        path.close()
        if !style.outgoing {
            path.apply(CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -w, y: 0))
        }
        return path.cgPath
    }
}

protocol BubbleContent: UIView {
    func fittingSize(maxWidth: CGFloat) -> CGSize
    func flash()
    func setRead(_ read: Bool)
    func setStyle(_ style: BubbleStyle, animated: Bool)
}

extension BubbleContent {
    func flash() {
        let glowView = UIView(frame: bounds)
        glowView.isUserInteractionEnabled = false
        glowView.layer.cornerRadius = min(17, bounds.height / 2)
        glowView.backgroundColor = UIColor(white: 1, alpha: 0.4)
        addSubview(glowView)
        UIView.animate(withDuration: 0.9, delay: 0.25, options: .curveEaseOut, animations: { glowView.alpha = 0 },
                       completion: { _ in glowView.removeFromSuperview() })
        Views.pop(self, scale: 1.04)
    }

    func setRead(_ read: Bool) {}

    func setStyle(_ style: BubbleStyle, animated: Bool) {}

    static func makeMeta(time: String, outgoing: Bool, read: Bool, onMedia: Bool = false) -> (UIView, ChecksView?) {
        let meta = UIView()
        let color = onMedia ? .white : (outgoing ? Palette.outgoingMeta : Palette.secondary)
        let label = Views.label(time, size: 11, color: color)
        label.sizeToFit()
        meta.addSubview(label)
        var width = label.bounds.width
        var checks: ChecksView?
        if outgoing {
            let view = ChecksView()
            view.tint = color
            view.set(read: read, animated: false)
            view.frame = CGRect(x: width + 3, y: (label.bounds.height - 14) / 2, width: 20, height: 14)
            meta.addSubview(view)
            checks = view
            width += 21
        }
        if onMedia {
            meta.backgroundColor = UIColor(white: 0, alpha: 0.4)
            meta.layer.cornerRadius = 9
            label.frame.origin.x = 7
            checks?.frame.origin.x += 7
            width += 14
        }
        meta.bounds = CGRect(x: 0, y: 0, width: width, height: onMedia ? 18 : label.bounds.height)
        label.center.y = meta.bounds.midY
        checks?.center.y = meta.bounds.midY
        return (meta, checks)
    }
}

/// A reply quote inside a bubble: an accent bar, the author and one line of the message.
final class QuoteView: UIView {
    private let bar = UIView()
    private let name = Views.label(size: 14, weight: .semibold, color: Palette.accent)
    private let text = Views.label(size: 14)
    static let height: CGFloat = 40

    init(_ quote: Message.Quote, outgoing: Bool) {
        super.init(frame: .zero)
        let tint = outgoing ? Palette.outgoingMeta : Palette.accent
        backgroundColor = tint.withAlphaComponent(0.12)
        layer.cornerRadius = 6
        clipsToBounds = true
        bar.backgroundColor = tint
        name.textColor = tint
        name.text = quote.name
        text.text = quote.text
        addSubview(bar)
        addSubview(name)
        addSubview(text)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var fittingWidth: CGFloat {
        max(name.intrinsicContentSize.width, text.intrinsicContentSize.width) + 18
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        bar.frame = CGRect(x: 0, y: 0, width: 3, height: bounds.height)
        name.frame = CGRect(x: 10, y: 3, width: bounds.width - 16, height: 17)
        text.frame = CGRect(x: 10, y: 20, width: bounds.width - 16, height: 17)
    }
}

/// A text bubble; the time sits on the last line when it fits there, like Telegram's.
final class MessageBubble: UIView, BubbleContent {
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
            self.fill.update(in: self)
    }

    private let label = UILabel()
    private let meta: UIView
    private let checks: ChecksView?
    private let quote: QuoteView?
    private let linkView: LinkView?
    private let fill: BubbleFill
    private let font = UIFont.systemFont(ofSize: 16)
    private let plain: String
    /// Text written between || and || hides under living ink until wiped.
    private let secret: NSRange?
    private var spoiler: InkSpoilerView?

    init(text: String, outgoing: Bool, time: String, read: Bool, reply: Message.Quote? = nil, edited: Bool = false,
         link: LinkPreview? = nil) {
        (meta, checks) = Self.makeMeta(time: edited ? "edited " + time : time, outgoing: outgoing, read: read)
        quote = reply.map { QuoteView($0, outgoing: outgoing) }
        linkView = link.map { LinkView($0, tint: outgoing ? Palette.outgoingMeta : Palette.accent) }
        fill = BubbleFill(style: BubbleStyle(outgoing: outgoing), color: outgoing ? Palette.outgoing : Palette.incoming)
        (plain, secret) = Self.parseSpoiler(text)
        super.init(frame: .zero)
        fill.attach(to: self)
        label.text = plain
        label.font = font
        label.textColor = Palette.text
        label.numberOfLines = 0
        addSubview(label)
        addSubview(meta)
        if let quote { addSubview(quote) }
        if let linkView { addSubview(linkView) }
        if let secret {
            let spoiler = InkSpoilerView()
            spoiler.inkColor = outgoing ? UIColor(red: 0.2, green: 0.3, blue: 0.6, alpha: 1) : UIColor(white: 0.3, alpha: 1)
            spoiler.configure(text: attributed(), hidden: secret)
            addSubview(spoiler)
            self.spoiler = spoiler
        }

    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var quoteSpace: CGFloat { quote == nil ? 0 : QuoteView.height + 4 }

    private static func parseSpoiler(_ text: String) -> (String, NSRange?) {
        let parts = text.components(separatedBy: "||")
        guard parts.count >= 3 else { return (text, nil) }
        let before = parts[0], secret = parts[1], after = parts[2...].joined(separator: "||")
        return (before + secret + after, NSRange(location: (before as NSString).length, length: (secret as NSString).length))
    }

    private func attributed(highlight query: String? = nil, current: Bool = false) -> NSAttributedString {
        let result = NSMutableAttributedString(string: plain, attributes: [.font: font, .foregroundColor: Palette.text])
        if let query, !query.isEmpty {
            var searchRange = plain.startIndex..<plain.endIndex
            while let found = plain.range(of: query, options: .caseInsensitive, range: searchRange) {
                let color = current ? UIColor(red: 1, green: 0.62, blue: 0.1, alpha: 1) : UIColor(red: 1, green: 0.85, blue: 0.2, alpha: 0.75)
                result.addAttributes([.backgroundColor: color, .foregroundColor: UIColor.black], range: NSRange(found, in: plain))
                searchRange = found.upperBound..<plain.endIndex
            }
        }
        return result
    }

    /// Marks the search query in the text; the current result is marked brighter.
    func highlight(_ query: String?, current: Bool) {
        label.attributedText = attributed(highlight: query, current: current)
    }
    /// The link card sits under the text, above the time.
    private var linkSpace: CGFloat { linkView == nil ? 0 : LinkView.height + 6 }

    private func textSize(_ maxWidth: CGFloat) -> CGSize {
        let rect = ((label.text ?? "") as NSString).boundingRect(with: CGSize(width: maxWidth - 24, height: 2000),
                                                                options: .usesLineFragmentOrigin,
                                                                attributes: [.font: font], context: nil)
        return CGSize(width: ceil(rect.width), height: ceil(rect.height))
    }

    func fittingSize(maxWidth: CGFloat) -> CGSize {
        let text = textSize(maxWidth)
        let metaWidth = meta.bounds.width
        let quoteWidth = min(quote?.fittingWidth ?? 0, maxWidth - 20) + 20
        let singleLine = text.height < font.lineHeight * 1.5
        if linkView != nil {
            return CGSize(width: max(max(text.width, metaWidth) + 24, min(maxWidth, 270)),
                          height: text.height + 15 + 15 + quoteSpace + linkSpace)
        }
        if singleLine, text.width + metaWidth + 10 <= maxWidth - 24 {
            return CGSize(width: max(text.width + metaWidth + 10 + 24, quoteWidth), height: text.height + 15 + quoteSpace)
        }
        return CGSize(width: max(max(text.width, metaWidth) + 24, quoteWidth), height: text.height + 15 + 15 + quoteSpace)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        quote?.frame = CGRect(x: 10, y: 8, width: bounds.width - 20, height: QuoteView.height)
        let text = textSize(bounds.width + 1)
        label.frame = CGRect(x: 12, y: 7 + quoteSpace, width: bounds.width - 24, height: text.height)
        linkView?.frame = CGRect(x: 10, y: label.frame.maxY + 6, width: bounds.width - 20, height: LinkView.height)
        spoiler?.frame = label.frame
        meta.frame.origin = CGPoint(x: bounds.width - 11 - meta.bounds.width, y: bounds.height - 6 - meta.bounds.height)
        if fill.layer.animation(forKey: "morph") == nil { fill.update(in: self) }
    }

    func setRead(_ read: Bool) {
        checks?.set(read: read, animated: true)
    }

    func setStyle(_ style: BubbleStyle, animated: Bool) {
        guard style != fill.style else { return }
        fill.style = style
        fill.update(in: self, animated: animated)
    }
}

/// A voice message: play button, a waveform of liquid (LiquidWaveView) that fills as it plays
/// with a drop riding the playhead, duration.
final class VoiceBubble: UIView, BubbleContent {
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
            self.fill.update(in: self)
    }

    private let play = UIButton(type: .system)
    private let wave: LiquidWaveView
    private let duration: TimeInterval
    private let length = Views.label(size: 12)
    private let meta: UIView
    private let checks: ChecksView?
    private let fill: BubbleFill

    init(duration: TimeInterval, outgoing: Bool, time: String, read: Bool) {
        self.duration = duration
        (meta, checks) = Self.makeMeta(time: time, outgoing: outgoing, read: read)
        fill = BubbleFill(style: BubbleStyle(outgoing: outgoing), color: outgoing ? Palette.outgoing : Palette.incoming)
        var generator = SplitMix(seed: UInt64(duration * 1000) + 7)
        wave = LiquidWaveView(amplitudes: (0..<30).map { _ in 0.15 + generator.next() * 0.85 })
        super.init(frame: .zero)
        fill.attach(to: self)
        let tint = outgoing ? Palette.outgoingMeta : Palette.accent
        play.backgroundColor = tint
        play.tintColor = outgoing ? Palette.outgoing : .white
        play.layer.cornerRadius = 21
        play.setImage(UIImage(systemName: "play.fill"), for: .normal)
        play.addAction(UIAction { [weak self] _ in self?.toggle() }, for: .touchUpInside)
        addSubview(play)
        wave.playedColor = tint
        wave.restColor = tint.withAlphaComponent(0.35)
        wave.onFinish = { [weak self] in
            self?.play.setImage(UIImage(systemName: "play.fill"), for: .normal)
        }
        addSubview(wave)
        length.text = String(format: "0:%02d", Int(duration))
        length.textColor = tint
        addSubview(length)
        addSubview(meta)

    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func fittingSize(maxWidth: CGFloat) -> CGSize {
        CGSize(width: min(maxWidth, 250), height: 60)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        play.frame = CGRect(x: 9, y: 9, width: 42, height: 42)
        wave.frame = CGRect(x: 58, y: 8, width: bounds.width - 68, height: 28)
        length.frame = CGRect(x: 60, y: 38, width: 60, height: 15)
        meta.frame.origin = CGPoint(x: bounds.width - 11 - meta.bounds.width, y: bounds.height - 7 - meta.bounds.height)
        if fill.layer.animation(forKey: "morph") == nil { fill.update(in: self) }
    }

    private func toggle() {
        Views.pop(play, scale: 0.85)
        if wave.isPlaying {
            wave.stop()
            play.setImage(UIImage(systemName: "play.fill"), for: .normal)
        } else {
            wave.play(duration: duration)
            play.setImage(UIImage(systemName: "pause.fill"), for: .normal)
        }
    }

    func setRead(_ read: Bool) {
        checks?.set(read: read, animated: true)
    }

    func setStyle(_ style: BubbleStyle, animated: Bool) {
        guard style != fill.style else { return }
        fill.style = style
        fill.update(in: self, animated: animated)
    }
}

/// An album: one photo, or a grid of two to four.
final class PhotosBubble: UIView, BubbleContent {
    var onTap: ((Int, UIImageView) -> Void)?
    private(set) var images: [UIImageView] = []
    private let meta: UIView

    init(scenes: [DemoPhotos.Scene], outgoing: Bool, time: String, read: Bool) {
        (meta, _) = Self.makeMeta(time: time, outgoing: outgoing, read: read, onMedia: true)
        super.init(frame: .zero)
        backgroundColor = outgoing ? Palette.outgoing : Palette.incoming
        layer.cornerRadius = 17
        layer.cornerCurve = .continuous
        clipsToBounds = true
        for (index, scene) in scenes.prefix(4).enumerated() {
            let image = UIImageView(image: DemoPhotos.image(scene, size: CGSize(width: 300, height: 300), seed: UInt64(index + 11)))
            image.contentMode = .scaleAspectFill
            image.clipsToBounds = true
            image.isUserInteractionEnabled = true
            image.tag = index
            image.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
            addSubview(image)
            images.append(image)
        }
        addSubview(meta)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard let image = gesture.view as? UIImageView else { return }
        onTap?(image.tag, image)
    }

    func fittingSize(maxWidth: CGFloat) -> CGSize {
        let width = min(maxWidth, 260)
        return CGSize(width: width, height: images.count == 1 ? width * 1.1 : (images.count == 2 ? width / 2 : width))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let gap: CGFloat = 2
        let width = bounds.width, height = bounds.height
        switch images.count {
        case 1:
            images[0].frame = bounds
        case 2:
            images[0].frame = CGRect(x: 0, y: 0, width: (width - gap) / 2, height: height)
            images[1].frame = CGRect(x: (width + gap) / 2, y: 0, width: (width - gap) / 2, height: height)
        case 3:
            images[0].frame = CGRect(x: 0, y: 0, width: width, height: (height - gap) / 2)
            images[1].frame = CGRect(x: 0, y: (height + gap) / 2, width: (width - gap) / 2, height: (height - gap) / 2)
            images[2].frame = CGRect(x: (width + gap) / 2, y: (height + gap) / 2, width: (width - gap) / 2, height: (height - gap) / 2)
        default:
            for (index, image) in images.enumerated() {
                image.frame = CGRect(x: index % 2 == 0 ? 0 : (width + gap) / 2, y: index < 2 ? 0 : (height + gap) / 2,
                                     width: (width - gap) / 2, height: (height - gap) / 2)
            }
        }
        meta.frame.origin = CGPoint(x: width - 8 - meta.bounds.width, y: height - 8 - meta.bounds.height)
    }
}

/// A round video message ("кружочек").
final class RoundBubble: UIView, BubbleContent {
    private let image = UIImageView()
    private let meta: UIView

    init(scene: DemoPhotos.Scene, outgoing: Bool, time: String, read: Bool) {
        (meta, _) = Self.makeMeta(time: time, outgoing: outgoing, read: read, onMedia: true)
        super.init(frame: .zero)
        image.image = DemoPhotos.image(scene, size: CGSize(width: 400, height: 400), seed: 5)
        image.contentMode = .scaleAspectFill
        image.clipsToBounds = true
        addSubview(image)
        addSubview(meta)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func fittingSize(maxWidth: CGFloat) -> CGSize {
        CGSize(width: 210, height: 210)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        image.frame = bounds
        image.layer.cornerRadius = bounds.width / 2
        layer.cornerRadius = bounds.width / 2
        meta.frame.origin = CGPoint(x: bounds.width - 30 - meta.bounds.width, y: bounds.height - 12 - meta.bounds.height)
    }
}

enum Bubbles {
    static func make(_ message: Message) -> BubbleContent? {
        switch message.kind {
        case .text(let text):
            return MessageBubble(text: text, outgoing: message.outgoing, time: message.time, read: message.read,
                                   reply: message.reply, edited: message.edited, link: message.link)
        case .voice(let duration):
            return VoiceBubble(duration: duration, outgoing: message.outgoing, time: message.time, read: message.read)
        case .photos(let scenes):
            return PhotosBubble(scenes: scenes, outgoing: message.outgoing, time: message.time, read: message.read)
        case .round(let scene):
            return RoundBubble(scene: scene, outgoing: message.outgoing, time: message.time, read: message.read)
        case .sticker(let sticker):
            return StickerBubble(sticker: sticker, outgoing: message.outgoing, time: message.time, read: message.read)
        case .unreadDivider:
            return nil
        }
    }

    static func maxWidth(in width: CGFloat) -> CGFloat { width * 0.74 }
}

/// A message row: the bubble, its reaction chips, a checkbox in selection mode, and the reply
/// arrow that grows while the bubble is swiped left.
final class MessageCell: UITableViewCell {
    var onDoubleTap: ((CGPoint) -> Void)?
    var onLongPress: (() -> Void)?
    var onReply: (() -> Void)?
    var onReplySwipe: ((UIView?, CGFloat, Bool) -> Void)?
    var onReaction: ((String) -> Void)?
    var onPhoto: ((Int, UIImageView) -> Void)?

    private(set) var bubble: BubbleContent?
    private(set) var message: Message?
    private var style = BubbleStyle(outgoing: false)
    private var chips: [UIControl] = []
    private let divider = UILabel()
    private let check = UIImageView()
    private let replyIcon = UIImageView()
    private let replyCircle = UIView()
    private var selecting = false
    private var countdown: UIView?
    private var swipe: CGFloat = 0
    private var replyArmed = false

    static let chipHeight: CGFloat = 28

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        divider.text = "Unread messages"
        divider.font = .systemFont(ofSize: 14, weight: .medium)
        divider.textColor = Palette.secondary
        divider.textAlignment = .center
        divider.backgroundColor = Palette.bar
        divider.isHidden = true
        contentView.addSubview(divider)
        check.contentMode = .center
        check.alpha = 0
        contentView.addSubview(check)
        replyCircle.backgroundColor = UIColor(white: 0, alpha: 0.25)
        replyCircle.layer.cornerRadius = 17
        replyIcon.image = UIImage(systemName: "arrowshape.turn.up.left.fill",
                                  withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
        replyIcon.tintColor = .white
        replyIcon.contentMode = .center
        replyCircle.addSubview(replyIcon)
        replyCircle.alpha = 0
        contentView.addSubview(replyCircle)

        let double = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        double.numberOfTapsRequired = 2
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        hold.minimumPressDuration = 0.35
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        // The cell decides (gestureRecognizerShouldBegin): a vertical drag must stay the table's.
        for gesture in [double, hold, pan] {
            gesture.delegate = self
            contentView.addGestureRecognizer(gesture)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ message: Message, style: BubbleStyle, selecting: Bool, selected: Bool) {
        bubble?.removeFromSuperview()
        chips.forEach { $0.removeFromSuperview() }
        chips = []
        self.message = message
        self.style = style
        divider.isHidden = !message.isDivider
        bubble = Bubbles.make(message)
        if let bubble {
            bubble.setStyle(style, animated: false)
            contentView.insertSubview(bubble, belowSubview: replyCircle)
            (bubble as? PhotosBubble)?.onTap = { [weak self] index, image in self?.onPhoto?(index, image) }
        }
        countdown?.removeFromSuperview()
        countdown = nil
        for emoji in message.reactions {
            let chip = UIControl()
            chip.backgroundColor = message.outgoing ? Palette.outgoing : Palette.incoming
            chip.layer.cornerRadius = Self.chipHeight / 2
            let label = Views.label("\(emoji) 1", size: 14, weight: .semibold,
                                      color: message.outgoing ? Palette.outgoingMeta : Palette.accent)
            label.textAlignment = .center
            label.tag = 1
            chip.addSubview(label)
            chip.accessibilityLabel = emoji
            chip.addAction(UIAction { [weak self] _ in self?.onReaction?(emoji) }, for: .touchUpInside)
            contentView.addSubview(chip)
            chips.append(chip)
        }
        swipe = 0
        setSelecting(selecting, selected: selected, animated: false)
        setNeedsLayout()
    }

    func setSelecting(_ selecting: Bool, selected: Bool, animated: Bool) {
        self.selecting = selecting
        check.image = UIImage(systemName: selected ? "checkmark.circle.fill" : "circle",
                              withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .regular))
        check.tintColor = selected ? Palette.accent : UIColor(white: 1, alpha: 0.8)
        let change = {
            self.check.alpha = selecting && self.message?.isDivider == false ? 1 : 0
            self.layoutContent()
        }
        animated ? UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0,
                                  animations: change) : change()
        if animated, selected { Views.pop(check, scale: 0.6) }
    }

    /// Moves the style (and with it the tail) to its new place.
    func setStyle(_ style: BubbleStyle, animated: Bool) {
        self.style = style
        bubble?.setStyle(style, animated: animated)
    }

    /// A ring next to the bubble that drains until the message evaporates at `deadline`.
    func showCountdown(until deadline: Date, total: TimeInterval) {
        countdown?.removeFromSuperview()
        let ring = UIView(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
        ring.isUserInteractionEnabled = false
        let track = CAShapeLayer()
        track.path = UIBezierPath(ovalIn: ring.bounds.insetBy(dx: 2, dy: 2)).cgPath
        track.fillColor = UIColor(white: 0, alpha: 0.3).cgColor
        track.strokeColor = UIColor(white: 1, alpha: 0.25).cgColor
        track.lineWidth = 2
        ring.layer.addSublayer(track)
        let arc = CAShapeLayer()
        arc.path = UIBezierPath(arcCenter: CGPoint(x: 12, y: 12), radius: 10, startAngle: -.pi / 2, endAngle: .pi * 1.5,
                                clockwise: true).cgPath
        arc.fillColor = UIColor.clear.cgColor
        arc.strokeColor = UIColor.white.cgColor
        arc.lineWidth = 2
        arc.lineCap = .round
        ring.layer.addSublayer(arc)
        let flame = UILabel(frame: ring.bounds)
        flame.text = "🔥"
        flame.font = .systemFont(ofSize: 10)
        flame.textAlignment = .center
        ring.addSubview(flame)
        let left = max(0, deadline.timeIntervalSinceNow)
        let drain = CABasicAnimation(keyPath: "strokeEnd")
        drain.fromValue = left / total
        drain.toValue = 0
        drain.duration = left
        drain.fillMode = .forwards
        drain.isRemovedOnCompletion = false
        arc.add(drain, forKey: "drain")
        contentView.addSubview(ring)
        countdown = ring
        setNeedsLayout()
        Views.pop(ring, scale: 0.3)
    }

    /// The unread band lights up once when the chat opens on it.
    func pulseDivider() {
        UIView.animate(withDuration: 0.3, animations: {
            self.divider.backgroundColor = Palette.accent.withAlphaComponent(0.35)
            self.divider.textColor = Palette.text
        }, completion: { _ in
            UIView.animate(withDuration: 0.9, delay: 0.3) {
                self.divider.backgroundColor = Palette.bar
                self.divider.textColor = Palette.secondary
            }
        })
    }

    func chip(for emoji: String) -> UIView? {
        chips.first { $0.accessibilityLabel == emoji }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutContent()
    }

    private func layoutContent() {
        let width = contentView.bounds.width
        divider.frame = CGRect(x: 0, y: 6, width: width, height: 28)
        check.frame = CGRect(x: 6, y: (contentView.bounds.height - 30) / 2, width: 30, height: 30)
        guard let bubble, let message else { return }
        let size = bubble.fittingSize(maxWidth: Bubbles.maxWidth(in: width))
        let shift: CGFloat = selecting && !message.outgoing ? 36 : 0
        let x = message.outgoing ? width - 14 - size.width : 14 + shift
        let top = Self.topPadding(style)
        bubble.frame = CGRect(x: x + swipe, y: top, width: size.width, height: size.height)
        var chipX = message.outgoing ? bubble.frame.maxX : bubble.frame.minX
        for chip in chips {
            let label = chip.viewWithTag(1) as! UILabel
            let chipWidth = label.intrinsicContentSize.width + 20
            if message.outgoing { chipX -= chipWidth }
            chip.frame = CGRect(x: chipX, y: bubble.frame.maxY + 4, width: chipWidth, height: Self.chipHeight)
            label.frame = chip.bounds
            chipX += message.outgoing ? -6 : chipWidth + 6
        }
        if let countdown {
            countdown.center = CGPoint(x: message.outgoing ? bubble.frame.minX - 18 : bubble.frame.maxX + 18, y: bubble.frame.maxY - 14)
        }
        let reveal = min(-swipe / 60, 1)
        replyCircle.frame = CGRect(x: width - 46, y: bubble.frame.midY - 17, width: 34, height: 34)
        replyIcon.frame = replyCircle.bounds
        replyCircle.alpha = onReplySwipe == nil ? reveal : 0
        replyCircle.transform = CGAffineTransform(scaleX: 0.4 + 0.6 * reveal, y: 0.4 + 0.6 * reveal)
    }

    static func topPadding(_ style: BubbleStyle) -> CGFloat {
        style.joinedTop ? 1 : 5
    }

    static func height(_ message: Message, style: BubbleStyle, width: CGFloat) -> CGFloat {
        guard let bubble = Bubbles.make(message) else { return 40 }
        let reactions: CGFloat = message.reactions.isEmpty ? 0 : chipHeight + 4
        return topPadding(style) + bubble.fittingSize(maxWidth: Bubbles.maxWidth(in: width)).height + reactions + 1
    }

    // MARK: Gestures

    override func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        // Also asked about the table's own gestures: only judge ours.
        guard gesture.view === contentView else { return true }
        guard !selecting, let bubble, message?.isDivider == false else { return false }
        if let pan = gesture as? UIPanGestureRecognizer {
            let velocity = pan.velocity(in: self)
            return velocity.x < 0 && abs(velocity.x) > abs(velocity.y) * 1.4
        }
        return bubble.frame.insetBy(dx: -6, dy: -4).contains(gesture.location(in: contentView))
    }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        onDoubleTap?(gesture.location(in: self))
    }

    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onLongPress?()
    }

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            onReplySwipe?(bubble, 0, false)
        case .changed:
            let dx = min(0, gesture.translation(in: self).x)
            // Free up to the arrow, then heavier.
            swipe = dx > -70 ? dx : -70 + (dx + 70) * 0.3
            let armed = swipe <= -70
            if armed != replyArmed {
                replyArmed = armed
                if armed {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Views.pop(replyIcon, scale: 1.4)
                }
            }
            layoutContent()
            onReplySwipe?(bubble, -swipe, armed)
        case .ended, .cancelled:
            if replyArmed, gesture.state == .ended { onReply?() }
            onReplySwipe?(nil, 0, false)
            replyArmed = false
            swipe = 0
            UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0) {
                self.layoutContent()
            }
        default:
            break
        }
    }
}

/// The date pill used as a section header. Section headers of a plain table stick to the top,
/// which is exactly Telegram's floating date; the chat fades the stuck one out when scrolling stops.
final class DateHeader: UITableViewHeaderFooterView {
    let pill = UILabel()

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        backgroundConfiguration = .clear()
        pill.font = .systemFont(ofSize: 13, weight: .semibold)
        pill.textColor = .white
        pill.textAlignment = .center
        pill.backgroundColor = UIColor(white: 0, alpha: 0.32)
        pill.clipsToBounds = true
        pill.layer.cornerRadius = 11
        contentView.addSubview(pill)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = pill.intrinsicContentSize.width + 20
        pill.frame = CGRect(x: (bounds.width - width) / 2, y: (bounds.height - 22) / 2, width: width, height: 22)
    }
}

// MARK: - Pinned messages bar

/// Telegram's pinned bar: a segmented line on the left shows which of the pinned messages is
/// shown; the text rolls up or down when it changes.
final class PinnedBar: UIControl {
    private let background = Views.barBackground()
    private let track = UIView()
    private var segments: [UIView] = []
    private let marker = UIView()
    private let title = Views.label(size: 14, weight: .semibold, color: Palette.accent)
    private let clip = UIView()
    private var text = Views.label(size: 14)
    private let pinIcon = UIImageView(image: UIImage(systemName: "pin.fill"))
    private let count: Int
    private(set) var current: Int

    init(count: Int) {
        self.count = count
        current = count - 1
        super.init(frame: .zero)
        addSubview(background)
        for _ in 0..<count {
            let segment = UIView()
            segment.backgroundColor = Palette.accent.withAlphaComponent(0.3)
            segment.layer.cornerRadius = 1
            track.addSubview(segment)
            segments.append(segment)
        }
        marker.backgroundColor = Palette.accent
        marker.layer.cornerRadius = 1
        track.addSubview(marker)
        track.isUserInteractionEnabled = false
        addSubview(track)
        addSubview(title)
        clip.clipsToBounds = true
        clip.isUserInteractionEnabled = false
        clip.addSubview(text)
        addSubview(clip)
        pinIcon.tintColor = Palette.secondary
        addSubview(pinIcon)
        [background, title].forEach { $0.isUserInteractionEnabled = false }
        set(current, animated: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        background.frame = bounds
        track.frame = CGRect(x: 12, y: 7, width: 2, height: bounds.height - 14)
        let gap: CGFloat = 2
        let height = (track.bounds.height - gap * CGFloat(count - 1)) / CGFloat(count)
        for (index, segment) in segments.enumerated() {
            segment.frame = CGRect(x: 0, y: CGFloat(index) * (height + gap), width: 2, height: height)
        }
        marker.frame = segments[current].frame
        title.frame = CGRect(x: 24, y: 6, width: bounds.width - 70, height: 17)
        clip.frame = CGRect(x: 24, y: 23, width: bounds.width - 70, height: 18)
        text.frame = clip.bounds
        pinIcon.frame = CGRect(x: bounds.width - 38, y: (bounds.height - 22) / 2, width: 22, height: 22)
    }

    func set(_ index: Int, animated: Bool) {
        let up = index < current
        let changed = index != current
        current = index
        title.text = "Pinned message #\(index + 1)"
        guard animated, changed else {
            text.text = MessengerData.pinnedMessages[index]
            setNeedsLayout()
            return
        }
        let old = text
        let new = Views.label(MessengerData.pinnedMessages[index], size: 14)
        new.frame = clip.bounds.offsetBy(dx: 0, dy: up ? -18 : 18)
        clip.addSubview(new)
        text = new
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut, animations: {
            old.frame = self.clip.bounds.offsetBy(dx: 0, dy: up ? 18 : -18)
            old.alpha = 0
            new.frame = self.clip.bounds
        }, completion: { _ in old.removeFromSuperview() })
        UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0) {
            self.marker.frame = self.segments[index].frame
        }
    }
}
