import UIKit

/// One shared canvas for the reply drop, rather than a Metal surface in every message cell.
final class MTReplySwipeEffect: UIView {
    private let liquid = LiquidCanvasView()
    private let arrow = UIImageView(image: UIImage(systemName: "arrowshape.turn.up.left.fill"))
    private weak var bubble: UIView?
    private var pull: CGFloat = 0
    private var snapped = false
    private var radius = Spring1D(0, stiffness: 18, dampingRatio: 0.45)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        liquid.liquidColor = UIColor(white: 1, alpha: 0.16)
        liquid.gloss = 0.5
        liquid.rimWidth = 6
        liquid.isPaused = true
        liquid.onUpdate = { [weak self] dt in self?.step(dt) }
        addSubview(liquid)
        arrow.tintColor = .white
        arrow.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        arrow.sizeToFit()
        arrow.alpha = 0
        addSubview(arrow)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        liquid.frame = bounds
    }

    func update(bubble: UIView?, pull: CGFloat, snapped: Bool) {
        if snapped, !self.snapped { radius.velocity += 60 }
        self.bubble = bubble
        self.pull = pull
        self.snapped = snapped
        liquid.isPaused = false
        if UIAccessibility.isReduceMotionEnabled {
            arrow.alpha = snapped ? 1 : 0
        }
    }

    func stop() {
        bubble = nil
        radius = Spring1D(0, stiffness: 18, dampingRatio: 0.45)
        liquid.shapes = []
        liquid.spikes = []
        liquid.renderFrame()
        liquid.isPaused = true
        arrow.alpha = 0
    }

    private func step(_ dt: CFTimeInterval) {
        radius.step(toward: bubble != nil ? (snapped ? 15 : min(pull / 70, 1) * 12) : 0, deltaTime: dt)
        let r = max(radius.value, 0)
        if let bubble {
            let frame = bubble.convert(bubble.bounds, to: self)
            let edge = CGPoint(x: frame.maxX, y: frame.midY)
            let center = CGPoint(x: min(edge.x + 10 + pull * 0.35, bounds.width - 30), y: frame.midY)
            arrow.center = center
            arrow.alpha = snapped ? 1 : 0
            liquid.spikes = !snapped && r > 1 && !UIAccessibility.isReduceMotionEnabled
                ? [IslandFluidSpike(base: CGPoint(x: edge.x - 4, y: edge.y), tip: center,
                                    baseRadius: max(2, 8 - pull / 14), tipRadius: r * 0.6, blend: 5)] : []
        } else {
            liquid.spikes = []
            arrow.alpha = min(1, r / 10)
        }
        liquid.shapes = r > 0.4 ? [.circle(center: arrow.center, radius: r, blend: 0)] : []
        if bubble == nil, r < 0.4 { stop() }
    }
}
