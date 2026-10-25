import UIKit

struct ChannelReadingState {
    var sections: [(title: String, messages: [Message])]
    /// Distance from the top resting position, independent of the current header inset.
    var position: CGFloat
    var anchorMessageID: Int?
    var anchorOffset: CGFloat
    var atBottom: Bool
}

/// The avatar and progress ring revealed by pulling past the last post.
final class NextChannelIndicator: UIView {
    static let threshold: CGFloat = 110
    private let ring = CAShapeLayer()
    private let track = CAShapeLayer()
    private let avatar = UIImageView()
    private let label = UILabel()
    private(set) var armed = false
    private var destinationID: Int?

    var avatarRect: CGRect { avatar.convert(avatar.bounds, to: superview) }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        alpha = 0
        for layer in [track, ring] {
            layer.fillColor = UIColor.clear.cgColor
            layer.lineWidth = 3
            layer.lineCap = .round
            self.layer.addSublayer(layer)
        }
        addSubview(avatar)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textAlignment = .center
        label.numberOfLines = 2
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(pull: CGFloat, next: Chat?, feedback: Bool) {
        guard let next else { reset(); return }
        if destinationID != next.id {
            destinationID = next.id
            avatar.image = ChannelAvatar.image(for: next.person, size: 44)
        }
        let ready = pull >= Self.threshold
        if ready != armed, feedback {
            UIImpactFeedbackGenerator(style: ready ? .medium : .light).impactOccurred()
        }
        armed = ready
        let unread = next.unread > 0 ? " · \(next.unread) unread" : ""
        label.text = ready ? "Release — \(next.person.name)" : "Next: \(next.person.name)\(unread)"
        label.textColor = Palette.secondary
        track.strokeColor = Palette.separator.cgColor
        ring.strokeColor = Palette.accent.cgColor
        let progress = min(max(pull / Self.threshold, 0), 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.strokeEnd = progress
        CATransaction.commit()
        alpha = min(1, max(0, pull) / 30)
        avatar.transform = CGAffineTransform(scaleX: 0.6 + 0.4 * progress + (ready ? 0.1 : 0),
                                             y: 0.6 + 0.4 * progress + (ready ? 0.1 : 0))
        setNeedsLayout()
    }

    func reset() {
        armed = false
        alpha = 0
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let center = CGPoint(x: bounds.midX, y: 28)
        let path = UIBezierPath(arcCenter: center, radius: 27, startAngle: -.pi / 2,
                                endAngle: .pi * 1.5, clockwise: true).cgPath
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.path = path
        ring.path = path
        CATransaction.commit()
        avatar.bounds = CGRect(x: 0, y: 0, width: 44, height: 44)
        avatar.center = center
        label.frame = CGRect(x: 12, y: 62, width: bounds.width - 24, height: 36)
    }
}
