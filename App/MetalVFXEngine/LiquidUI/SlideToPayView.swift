//
//  SlideToPayView.swift
//  controller
//
//  Slide to pay with a drop of liquid: drag the drop along the track and it leaves a smear of ink
//  behind that slowly shrinks; the label shines with a passing glint. Let go early and the drop
//  slides back as the smear dries up. Reach the end and the drop bursts into splashes, flinches, a check
//  mark appears on it and confetti flies out.
//

import UIKit

final class SlideToPayView: UIView {
    var title = "Slide to pay" {
        didSet { label.text = title; shine.text = title }
    }
    var tint: UIColor = .systemGreen {
        didSet { canvas.liquidColor = tint }
    }
    var onComplete: (() -> Void)?
    private(set) var isComplete = false

    private struct Splash {
        var position: CGPoint
        var velocity: CGVector
        var radius: CGFloat
    }

    private struct Smear {
        var position: CGPoint
        var radius: CGFloat
    }

    private let track = UIView()
    private let label = UILabel()
    private let shine = UILabel()
    private let shineMask = CAGradientLayer()
    private let canvas = LiquidCanvasView()
    private let arrow = UIImageView(image: UIImage(systemName: "chevron.right.2"))
    private let check = UIImageView(image: UIImage(systemName: "checkmark"))
    private let height: CGFloat = 64
    private let margin: CGFloat = 40

    private var knob = Spring1D(0, stiffness: 22, dampingRatio: 0.8)
    private var knobRadius: CGFloat = 24
    private var pop = Spring1D(24, stiffness: 16, dampingRatio: 0.35)
    private var dragging = false
    private var dragX: CGFloat = 0
    private var smears: [Smear] = []
    private var splashes: [Splash] = []
    private var lastSmearX: CGFloat = 0
    private let tick = UISelectionFeedbackGenerator()
    private let impact = UIImpactFeedbackGenerator(style: .heavy)
    private let success = UINotificationFeedbackGenerator()

    override init(frame: CGRect) {
        super.init(frame: frame)
        track.backgroundColor = UIColor.label.withAlphaComponent(0.9)
        track.layer.cornerCurve = .continuous
        for (view, alpha) in [(label, 0.35), (shine, 1.0)] {
            view.text = title
            view.textAlignment = .center
            view.font = .systemFont(ofSize: 17, weight: .semibold)
            view.textColor = UIColor.systemBackground.withAlphaComponent(alpha)
        }
        // The glint: a soft bright band sweeping across the label, through a gradient mask.
        shineMask.colors = [UIColor.clear.cgColor, UIColor.white.cgColor, UIColor.clear.cgColor]
        shineMask.startPoint = CGPoint(x: 0, y: 0.5)
        shineMask.endPoint = CGPoint(x: 1, y: 0.5)
        shineMask.locations = [0, 0.5, 1]
        shine.layer.mask = shineMask
        canvas.liquidColor = tint
        canvas.gloss = 0.7
        canvas.rimWidth = 9
        arrow.tintColor = .white
        arrow.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 17, weight: .bold)
        check.tintColor = .white
        check.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 24, weight: .heavy)
        check.alpha = 0
        for view in [track, label, shine, canvas, arrow, check] {
            addSubview(view)
        }
        canvas.onUpdate = { [weak self] dt in self?.step(dt) }
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:))))
        startShine()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        track.frame = bounds
        track.layer.cornerRadius = bounds.height / 2
        label.frame = bounds.insetBy(dx: height, dy: 0)
        shine.frame = label.frame
        shineMask.frame = CGRect(x: -shine.bounds.width, y: 0, width: shine.bounds.width * 0.6, height: shine.bounds.height)
        canvas.frame = bounds.insetBy(dx: -margin, dy: -margin)
        rebuild()
    }

    private func startShine() {
        let sweep = CABasicAnimation(keyPath: "position.x")
        sweep.fromValue = -120
        sweep.toValue = 520
        sweep.duration = 2.2
        sweep.repeatCount = .infinity
        shineMask.add(sweep, forKey: "shine")
    }

    /// Resets to the start, for paying again.
    func reset() {
        isComplete = false
        knob.value = 0
        knob.velocity = 0
        knobRadius = 24
        smears.removeAll()
        splashes.removeAll()
        UIView.animate(withDuration: 0.25) {
            self.check.alpha = 0
            self.arrow.alpha = 1
            self.label.alpha = 1
            self.shine.alpha = 1
        }
        canvas.isPaused = false
    }

    // MARK: Geometry

    private var travel: CGFloat {
        max(bounds.width - height, 1)
    }

    /// Knob center in canvas coordinates for a 0…1 position.
    private func knobPoint(_ x: CGFloat) -> CGPoint {
        CGPoint(x: margin + height / 2 + x * travel, y: margin + height / 2)
    }

    // MARK: Touches

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard !isComplete else { return }
        switch gesture.state {
        case .began:
            dragging = true
            tick.prepare()
        case .changed:
            dragX = max(0, min(1, gesture.translation(in: self).x / travel))
            if dragX >= 0.98 {
                complete()
            }
        default:
            dragging = false
        }
        canvas.isPaused = false
    }

    private func complete() {
        guard !isComplete else { return }
        isComplete = true
        dragging = false
        knob.value = 1
        impact.impactOccurred()
        // The drop bursts: splashes fly out of it.
        let center = knobPoint(1)
        splashes = (0..<14).map { i in
            let angle = CGFloat(i) / 14 * 2 * .pi + .random(in: -0.2...0.2)
            let speed = CGFloat.random(in: 160...420)
            return Splash(position: center, velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed - 120),
                          radius: .random(in: 3...7))
        }
        UIView.animate(withDuration: 0.15) {
            self.arrow.alpha = 0
            self.label.alpha = 0
            self.shine.alpha = 0
        }
        check.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
        UIView.animate(withDuration: 0.35, delay: 0.15, usingSpringWithDamping: 0.5, initialSpringVelocity: 0) {
            self.check.alpha = 1
            self.check.transform = .identity
        }
        // The drop flinches as it bursts, then swells back under the check mark.
        pop = Spring1D(24, stiffness: 16, dampingRatio: 0.35)
        pop.velocity = -260
        success.notificationOccurred(.success)
        if let window {
            let origin = convert(CGPoint(x: bounds.maxX - height / 2, y: bounds.midY), to: window)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                IslandConfetti.burst(in: window, from: origin)
            }
        }
        let onComplete = onComplete
        DispatchQueue.main.async { onComplete?() }
    }

    // MARK: Simulation

    private func step(_ dt: CFTimeInterval) {
        let t = CGFloat(dt)
        if dragging {
            knob.value = dragX
            knob.velocity = 0
        } else if !isComplete {
            knob.step(toward: 0, deltaTime: dt)
        }
        // Lay ink behind the drop while it moves forward; the smear slowly dries up.
        let x = knob.value
        if x - lastSmearX > 0.025, !isComplete {
            smears.append(Smear(position: knobPoint(x), radius: .random(in: 13...19)))
            lastSmearX = x
        }
        if x < lastSmearX - 0.05 {
            lastSmearX = x
        }
        for i in smears.indices {
            smears[i].radius -= t * (dragging ? 9 : 40)
        }
        smears.removeAll { $0.radius <= 0.5 }

        if isComplete {
            pop.step(toward: 24, deltaTime: dt)
            knobRadius = max(0, pop.value)
            for i in splashes.indices {
                splashes[i].velocity.dy += 900 * t
                splashes[i].position.x += splashes[i].velocity.dx * t
                splashes[i].position.y += splashes[i].velocity.dy * t
                splashes[i].radius = max(0, splashes[i].radius - t * 6)
            }
            splashes.removeAll { $0.radius <= 0.3 }
        }
        rebuild()

        let still = !dragging && smears.isEmpty && splashes.isEmpty
            && (isComplete ? pop.isSettled(at: 24, tolerance: 0.01) : knob.isSettled(at: 0))
        if still {
            canvas.renderFrame()
            canvas.isPaused = true
        }
    }

    private func rebuild() {
        let center = knobPoint(knob.value)
        var shapes: [IslandFluidShape] = smears.map { .circle(center: $0.position, radius: $0.radius, blend: 10) }
        if knobRadius > 0.5 {
            shapes.append(.circle(center: center, radius: knobRadius, blend: 12))
        }
        shapes += splashes.map { .circle(center: $0.position, radius: $0.radius, blend: 2) }
        canvas.shapes = shapes
        arrow.center = CGPoint(x: center.x - margin, y: center.y - margin)
        check.center = CGPoint(x: bounds.maxX - height / 2, y: bounds.midY)
    }
}
