//
//  ScrollDownButton.swift
//  controller
//
//  The round "scroll to bottom" button. Its unread badge is a drop of liquid: the first unread one
//  drips out of the middle of the button into the corner, later ones make it swell while the count
//  rolls, and reading them all pulls the drop back in. While a finger moves nearby (scrolling) the
//  button leans toward it a little, as if magnetized. The glass under it is drawn by
//  ChannelGlassView: read `glassFrame` and `glassOpacity` each frame.
//

import UIKit

final class ScrollDownButton: UIControl {
    private let icon = UIImageView(image: UIImage(systemName: "chevron.down"))
    private let canvas = LiquidCanvasView()
    private let badgeLabel = RollingCounterLabel()
    private let room: CGFloat = 24
    private(set) var unread = 0
    private(set) var isShown = false

    private var badge = IslandSpring(.zero, stiffness: 12, dampingRatio: 0.5)
    private var badgeRadius = Spring1D(0, stiffness: 14, dampingRatio: 0.45)
    private var swell = Spring1D(0, stiffness: 16, dampingRatio: 0.35)
    private var lean = IslandSpring(.zero, stiffness: 9, dampingRatio: 0.55)
    private var leanTarget = CGPoint.zero
    private var visible = Spring1D(0, stiffness: 13, dampingRatio: 0.62)

    override init(frame: CGRect) {
        super.init(frame: frame)
        icon.tintColor = .white
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        icon.isUserInteractionEnabled = false
        addSubview(icon)
        canvas.liquidColor = ChannelPalette.accent
        canvas.gloss = 0.6
        canvas.rimWidth = 5
        canvas.isUserInteractionEnabled = false
        canvas.onUpdate = { [weak self] dt in self?.step(dt) }
        addSubview(canvas)
        badgeLabel.font = .systemFont(ofSize: 12, weight: .bold)
        badgeLabel.textColor = .white
        badgeLabel.alpha = 0
        addSubview(badgeLabel)
        alpha = 0
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        icon.center = CGPoint(x: bounds.midX, y: bounds.midY + 1)
        canvas.frame = bounds.insetBy(dx: -room, dy: -room)
        if badgeRadius.value < 0.5 {
            badge.position = CGPoint(x: bounds.midX, y: bounds.midY)
        }
    }

    private var corner: CGPoint {
        CGPoint(x: bounds.maxX - 6, y: bounds.minY + 4)
    }

    private func wake() {
        canvas.isPaused = false
    }

    func setShown(_ shown: Bool) {
        guard shown != isShown else { return }
        isShown = shown
        wake()
    }

    func setUnread(_ count: Int) {
        guard count != unread else { return }
        let grew = count > unread
        if unread == 0, count > 0 {
            // Drips out of the middle of the button.
            badge.position = CGPoint(x: bounds.midX, y: bounds.midY)
            badge.velocity = .zero
        } else if grew {
            swell.velocity += 8
        }
        unread = count
        badgeLabel.setText(count > 99 ? "99+" : "\(count)", animated: true, up: grew)
        if count > 0 {
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
        }
        wake()
    }

    /// A finger nearby (in the superview's coordinates), or nil once it lifts.
    func attract(to point: CGPoint?) {
        guard let point, isShown else {
            leanTarget = .zero
            wake()
            return
        }
        let delta = CGPoint(x: point.x - center.x, y: point.y - center.y)
        let distance = hypot(delta.x, delta.y)
        let pull = max(0, 1 - distance / 140) * 9
        leanTarget = distance > 1 ? CGPoint(x: delta.x / distance * pull, y: delta.y / distance * pull) : .zero
        wake()
    }

    /// Where the glass circle under the button is right now, in the superview.
    var glassFrame: CGRect {
        let s = max(visible.value, 0)
        let c = CGPoint(x: center.x + lean.position.x, y: center.y + lean.position.y)
        return CGRect(x: c.x - bounds.width / 2 * s, y: c.y - bounds.height / 2 * s, width: bounds.width * s, height: bounds.height * s)
    }

    var glassOpacity: CGFloat {
        min(1, max(0, visible.value * 1.4))
    }

    private func step(_ dt: CFTimeInterval) {
        visible.step(toward: isShown ? 1 : 0, deltaTime: dt)
        lean.step(toward: leanTarget, deltaTime: dt)
        let s = max(visible.value, 0.001)
        transform = CGAffineTransform(translationX: lean.position.x, y: lean.position.y).scaledBy(x: s, y: s)
        alpha = min(1, max(0, visible.value * 1.4))
        isUserInteractionEnabled = isShown

        let mid = CGPoint(x: bounds.midX, y: bounds.midY)
        badge.step(toward: unread > 0 ? corner : mid, deltaTime: dt)
        badgeRadius.step(toward: unread > 0 ? 10 : 0, deltaTime: dt)
        swell.step(toward: 0, deltaTime: dt)
        let r = max(badgeRadius.value, 0) * (1 + 0.18 * swell.value)
        let labelWidth = badgeLabel.intrinsicContentSize.width
        let halfWidth = max(r, unread > 9 ? labelWidth / 2 + 5 : r)
        var shapes: [IslandFluidShape] = []
        var spikes: [IslandFluidSpike] = []
        if r > 0.4 {
            let c = CGPoint(x: badge.position.x + room, y: badge.position.y + room)
            shapes.append(IslandFluidShape(center: c, halfSize: CGSize(width: halfWidth, height: r), cornerRadius: r, blend: 0))
            // While it is still leaving the middle, a strand ties it to where it came from.
            let fromMiddle = badge.position.distance(to: mid)
            let toCorner = badge.position.distance(to: corner)
            if toCorner > 3, fromMiddle > 3 {
                let m = CGPoint(x: mid.x + room, y: mid.y + room)
                let thickness = max(1.5, 5 - fromMiddle / 6)
                shapes.append(.circle(center: m, radius: max(0, 7 - fromMiddle / 3), blend: 6))
                spikes.append(IslandFluidSpike(base: m, tip: c, baseRadius: thickness, tipRadius: thickness + 1, blend: 6))
            }
        }
        canvas.shapes = shapes
        canvas.spikes = spikes
        let size = badgeLabel.intrinsicContentSize
        badgeLabel.frame = CGRect(x: badge.position.x - size.width / 2, y: badge.position.y - size.height / 2,
                                  width: size.width, height: size.height)
        badgeLabel.alpha = min(1, max(0, (r - 6) / 4))

        let settled = visible.isSettled(at: isShown ? 1 : 0, tolerance: 0.002) && lean.speed < 0.5
            && lean.position.distance(to: leanTarget) < 0.2 && badgeRadius.isSettled(at: unread > 0 ? 10 : 0, tolerance: 0.02)
            && swell.isSettled(at: 0, tolerance: 0.01) && badge.speed < 0.5
        if settled {
            canvas.renderFrame()
            canvas.isPaused = true
        }
    }
}
