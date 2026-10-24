//
//  LiquidSwitch.swift
//  controller
//
//  A switch whose knob is a drop of liquid. Toggling it, the drop stretches across the track: a new
//  drop swells on the far side while the old one drains into it, the neck between them thins and
//  snaps, and the new drop lands with a jelly wobble. Behind it the track floods with color from
//  the left. Two LiquidCanvasViews: the colored fill under the white knob.
//

import UIKit

final class LiquidSwitch: UIControl {
    var onTint: UIColor = .systemGreen {
        didSet { fill.liquidColor = onTint }
    }
    private(set) var isOn = false

    private let track = UIView()
    private let fill = LiquidCanvasView()
    private let knob = LiquidCanvasView()
    private let size = CGSize(width: 64, height: 36)
    private let knobRadius: CGFloat = 14
    /// Room around the switch for the liquid to bulge into.
    private let margin: CGFloat = 10

    private var flood = Spring1D(0, stiffness: 11, dampingRatio: 0.75)
    private var arriving = IslandSpring(.zero, stiffness: 17, dampingRatio: 0.42)
    private var arrivingRadius: CGFloat = 0
    private var leaving: CGPoint?
    private var leavingRadius: CGFloat = 0
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    override init(frame: CGRect) {
        super.init(frame: frame)
        track.backgroundColor = .systemFill
        track.isUserInteractionEnabled = false
        track.layer.cornerCurve = .continuous
        fill.liquidColor = onTint
        fill.gloss = 0.35
        fill.rimWidth = 8
        knob.liquidColor = UIColor(white: 0.97, alpha: 1)
        knob.gloss = 0.5
        knob.rimWidth = 6
        for view in [track, fill, knob] {
            addSubview(view)
        }
        knob.onUpdate = { [weak self] dt in self?.step(dt) }
        arriving.position = knobCenter(on: false)
        arrivingRadius = knobRadius
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        size
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        track.frame = bounds
        track.layer.cornerRadius = bounds.height / 2
        let canvas = bounds.insetBy(dx: -margin, dy: -margin)
        fill.frame = canvas
        knob.frame = canvas
        rebuild()
    }

    /// Knob center in canvas coordinates.
    private func knobCenter(on: Bool) -> CGPoint {
        let inset = size.height / 2
        return CGPoint(x: margin + (on ? size.width - inset : inset), y: margin + size.height / 2)
    }

    func setOn(_ on: Bool, animated: Bool) {
        guard on != isOn else { return }
        isOn = on
        if animated {
            // The old drop stays behind and drains; a new one is pulled to the other side.
            leaving = arriving.position
            leavingRadius = arrivingRadius
            arriving.position = CGPoint(x: arriving.position.x + (on ? 6 : -6), y: arriving.position.y)
            arriving.velocity = .zero
            arrivingRadius = knobRadius * 0.5
            haptic.impactOccurred()
        } else {
            arriving.position = knobCenter(on: on)
            flood.value = on ? 1 : 0
            leaving = nil
        }
        knob.isPaused = false
        fill.isPaused = false
        rebuild()
    }

    @objc private func tapped() {
        setOn(!isOn, animated: true)
        sendActions(for: .valueChanged)
    }

    // MARK: Simulation

    private func step(_ dt: CFTimeInterval) {
        let target = knobCenter(on: isOn)
        arriving.step(toward: target, deltaTime: dt)
        arrivingRadius += (knobRadius - arrivingRadius) * min(1, CGFloat(dt) * 9)
        if leaving != nil {
            leavingRadius = max(0, leavingRadius - CGFloat(dt) * 60)
            if leavingRadius == 0 {
                leaving = nil
            }
        }
        flood.step(toward: isOn ? 1 : 0, deltaTime: dt)
        rebuild()

        let still = leaving == nil && arriving.speed < 0.5 && arriving.position.distance(to: target) < 0.2
            && flood.isSettled(at: isOn ? 1 : 0)
        if still {
            knob.renderFrame()
            fill.renderFrame()
            knob.isPaused = true
            fill.isPaused = true
        }
    }

    private func rebuild() {
        // Knob: stretched along its motion, so it reads as liquid being pulled.
        let speed = min(abs(arriving.velocity.dx) / 900, 0.35)
        var knobShapes: [IslandFluidShape] = [
            IslandFluidShape(center: arriving.position,
                             halfSize: CGSize(width: arrivingRadius * (1 + speed), height: arrivingRadius * (1 - speed * 0.4)),
                             cornerRadius: arrivingRadius, blend: 0),
        ]
        if let leaving, leavingRadius > 0.5 {
            // The neck between the drops is the smooth union; it snaps as they part.
            knobShapes.append(.circle(center: leaving, radius: leavingRadius, blend: 16))
        }
        knob.shapes = knobShapes

        // Fill: floods in from the left edge; its front is the rounded end of a capsule.
        let f = max(0, min(1.05, flood.value))
        if f > 0.01 {
            let width = max(size.height, size.width * f)
            fill.shapes = [IslandFluidShape(center: CGPoint(x: margin + width / 2, y: margin + size.height / 2),
                                            halfSize: CGSize(width: width / 2, height: size.height / 2 * min(1, 0.6 + f)),
                                            cornerRadius: size.height / 2, blend: 0)]
        } else {
            fill.shapes = []
        }
    }
}
