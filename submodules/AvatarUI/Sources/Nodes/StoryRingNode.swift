import UIKit
import AsyncDisplayKit

/// Segmented ring around an avatar. Two gradients are masked by shape layers, so a
/// row costs four layers and no per-frame work.
public final class StoryRingNode: ASDisplayNode {
    private let seenGradient = CAGradientLayer()
    private let unseenGradient = CAGradientLayer()
    private let seenMask = CAShapeLayer()
    private let unseenMask = CAShapeLayer()
    private var ring: AvatarStoryRing?
    private var avatarCornerRadius: CGFloat?
    private var animateNextLayout = false
    private let maxSegments = 30
    private let spacing: CGFloat = 3

    public override init() {
        super.init()
        isUserInteractionEnabled = false
    }

    public override func didLoad() {
        super.didLoad()
        for (gradient, mask) in [(seenGradient, seenMask), (unseenGradient, unseenMask)] {
            gradient.startPoint = CGPoint(x: 0.5, y: 0)
            gradient.endPoint = CGPoint(x: 0.5, y: 1)
            mask.fillColor = nil
            mask.strokeColor = UIColor.black.cgColor
            mask.lineCap = .round
            gradient.mask = mask
            layer.addSublayer(gradient)
        }
    }

    /// `cornerRadius` follows the avatar's clip; nil means a circle.
    func update(_ ring: AvatarStoryRing, cornerRadius: CGFloat?, animated: Bool) {
        guard self.ring != ring || avatarCornerRadius != cornerRadius else { return }
        self.ring = ring
        avatarCornerRadius = cornerRadius
        animateNextLayout = animated
        setNeedsLayout()
    }

    public override func layout() {
        super.layout()
        guard let ring, bounds.width > 0 else { return }
        let animated = animateNextLayout && !UIAccessibility.isReduceMotionEnabled
        animateNextLayout = false
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        CATransaction.setAnimationDuration(0.25)
        let traits = view.traitCollection
        for gradient in [seenGradient, unseenGradient] { gradient.frame = bounds }
        seenMask.frame = bounds
        unseenMask.frame = bounds
        seenGradient.colors = ring.seenColors.map { $0.resolvedColor(with: traits).cgColor }
        unseenGradient.colors = ring.unseenColors.map { $0.resolvedColor(with: traits).cgColor }
        seenMask.lineWidth = ring.inactiveLineWidth
        unseenMask.lineWidth = ring.lineWidth

        let (seen, unseen) = paths(for: ring)
        seenMask.path = seen
        unseenMask.path = unseen
        CATransaction.commit()
    }

    private func paths(for ring: AvatarStoryRing) -> (seen: CGPath, unseen: CGPath) {
        let seen = CGMutablePath()
        let unseen = CGMutablePath()
        let inset = ring.lineWidth / 2
        let half = min(bounds.width, bounds.height) / 2
        // Rounded-rect avatars get one continuous outline: segments on corners read poorly.
        if let avatarCornerRadius, avatarCornerRadius < half - 0.5 {
            let rect = bounds.insetBy(dx: inset, dy: inset)
            let outline = CGPath(roundedRect: rect, cornerWidth: max(avatarCornerRadius, 0), cornerHeight: max(avatarCornerRadius, 0), transform: nil)
            (ring.hasUnseen ? unseen : seen).addPath(outline)
            return (seen, unseen)
        }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = half - inset
        let count = min(max(ring.totalCount, 1), maxSegments)
        let seenCount = count - min(max(ring.unseenCount, 0), count)
        guard count > 1 else {
            (ring.hasUnseen ? unseen : seen).addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                                                  width: radius * 2, height: radius * 2))
            return (seen, unseen)
        }
        let segment = 2 * CGFloat.pi / CGFloat(count)
        // Round caps extend each arc by half the line width, so the gap accounts for them.
        let gap = min((spacing + ring.lineWidth) / radius, segment * 0.5)
        for index in 0..<count {
            let start = -CGFloat.pi / 2 + segment * CGFloat(index) + gap / 2
            let path = index < seenCount ? seen : unseen
            path.move(to: CGPoint(x: center.x + radius * cos(start), y: center.y + radius * sin(start)))
            path.addArc(center: center, radius: radius, startAngle: start, endAngle: start + segment - gap, clockwise: false)
        }
        return (seen, unseen)
    }
}
