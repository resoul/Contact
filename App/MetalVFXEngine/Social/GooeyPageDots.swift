//
//  GooeyPageDots.swift
//  controller
//
//  A carousel's page dots where the current one is a drop of liquid (LiquidCanvasView): as you
//  swipe, its front races ahead to the next dot while its back clings to the old one, stretching it
//  into a capsule, until the back lets go and snaps after it.
//

import UIKit

final class GooeyPageDots: UIView {
    var count: Int {
        didSet { rebuild() }
    }
    var color = PhotoFeedPalette.accent {
        didSet { canvas.liquidColor = color }
    }

    private let canvas = LiquidCanvasView()
    private var dots: [UIView] = []
    private let spacing: CGFloat = 12
    private let radius: CGFloat = 3
    private var target: CGFloat = 0
    private var head = Spring1D(0, stiffness: 30, dampingRatio: 0.55)
    private var tail = Spring1D(0, stiffness: 6.5, dampingRatio: 0.9)

    init(count: Int) {
        self.count = count
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        canvas.liquidColor = color
        canvas.gloss = 0.6
        canvas.rimWidth = 3
        canvas.onUpdate = { [weak self] dt in self?.step(dt) }
        addSubview(canvas)
        rebuild()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: CGFloat(max(count - 1, 0)) * spacing + 20, height: 16)
    }

    private func rebuild() {
        dots.forEach { $0.removeFromSuperview() }
        dots = (0..<count).map { _ in
            let dot = UIView()
            dot.backgroundColor = UIColor(white: 1, alpha: 0.35)
            dot.layer.cornerRadius = radius
            insertSubview(dot, belowSubview: canvas)
            return dot
        }
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    private func x(_ position: CGFloat) -> CGFloat {
        bounds.midX + (position - CGFloat(count - 1) / 2) * spacing
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        canvas.frame = bounds.insetBy(dx: -10, dy: -10)
        for (index, dot) in dots.enumerated() {
            dot.frame = CGRect(x: x(CGFloat(index)) - radius, y: bounds.midY - radius, width: radius * 2, height: radius * 2)
        }
        canvas.isPaused = false
    }

    /// Continuous page position, e.g. contentOffset.x / page width.
    func setProgress(_ progress: CGFloat) {
        target = min(max(progress, 0), CGFloat(count - 1))
        canvas.isPaused = false
    }

    private func step(_ dt: CFTimeInterval) {
        // The front leads (and overshoots a little toward where the finger is heading); the back drags.
        head.step(toward: target, deltaTime: dt)
        tail.step(toward: target, deltaTime: dt)
        let a = CGPoint(x: x(head.value) + 10, y: bounds.midY + 10)
        let b = CGPoint(x: x(tail.value) + 10, y: bounds.midY + 10)
        let stretch = abs(a.x - b.x)
        // Thins as it stretches, like a drop pulled between two points.
        let r = radius + 0.6 - min(stretch / 24, 0.9)
        canvas.shapes = [.circle(center: a, radius: r, blend: 0), .circle(center: b, radius: r * 0.85, blend: 1.5)]
        canvas.spikes = stretch > 1 ? [IslandFluidSpike(base: b, tip: a, baseRadius: r * 0.55, tipRadius: r * 0.8, blend: 1.5)] : []
        if head.isSettled(at: target, tolerance: 0.001), tail.isSettled(at: target, tolerance: 0.001) {
            canvas.renderFrame()
            canvas.isPaused = true
        }
    }
}
