//
//  PinDropsView.swift
//  controller
//
//  A PIN entry where every digit is a drop of liquid falling into its cell: it lands with a squash
//  and wobbles still. A wrong code splashes the drops, shakes the row and lets them run down out of
//  their cells; a right one pulls them together into a single drop. Drawn by a LiquidCanvasView.
//

import UIKit

final class PinDropsView: UIView {
    let length: Int
    var liquidColor: UIColor = .label {
        didSet { canvas.liquidColor = liquidColor }
    }
    private(set) var count = 0

    private enum State {
        case falling
        case resting
        case leaving
        case running
        case merging
    }

    private struct Drop {
        var position: CGPoint
        var velocityY: CGFloat
        var radius: CGFloat
        var squash: Spring1D
        var state: State
        var stretch: CGFloat = 0
    }

    private struct Splash {
        var position: CGPoint
        var velocity: CGVector
        var radius: CGFloat
    }

    private let canvas = LiquidCanvasView()
    private var cells: [UIView] = []
    private let check = UIImageView(image: UIImage(systemName: "checkmark"))
    private var drops: [Drop?]
    private var splashes: [Splash] = []
    private var shake = Spring1D(0, stiffness: 28, dampingRatio: 0.2)
    private let dropRadius: CGFloat = 10
    private let cellSize: CGFloat = 30
    private let spacing: CGFloat = 26
    /// Where the cells sit; drops fall from above it and run off below it.
    private let rowY: CGFloat = 70
    private let landHaptic = UIImpactFeedbackGenerator(style: .light)
    private let resultHaptic = UINotificationFeedbackGenerator()

    init(length: Int = 4) {
        self.length = length
        drops = Array(repeating: nil, count: length)
        super.init(frame: .zero)
        canvas.liquidColor = liquidColor
        canvas.gloss = 0.6
        canvas.rimWidth = 6
        canvas.onUpdate = { [weak self] dt in self?.step(dt) }
        cells = (0..<length).map { _ in
            let cell = UIView()
            cell.layer.borderWidth = 2
            cell.layer.borderColor = UIColor.tertiaryLabel.cgColor
            cell.layer.cornerRadius = cellSize / 2
            addSubview(cell)
            return cell
        }
        addSubview(canvas)
        check.tintColor = .systemBackground
        check.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .heavy)
        check.alpha = 0
        addSubview(check)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: CGFloat(length) * cellSize + CGFloat(length - 1) * spacing, height: 160)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        canvas.frame = bounds
        for (index, cell) in cells.enumerated() {
            cell.frame = CGRect(x: cellX(index) - cellSize / 2, y: rowY - cellSize / 2, width: cellSize, height: cellSize)
        }
        check.center = CGPoint(x: bounds.midX, y: rowY)
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        cells.forEach { $0.layer.borderColor = UIColor.tertiaryLabel.cgColor }
    }

    private func cellX(_ index: Int) -> CGFloat {
        let total = CGFloat(length) * cellSize + CGFloat(length - 1) * spacing
        return bounds.midX - total / 2 + cellSize / 2 + CGFloat(index) * (cellSize + spacing)
    }

    // MARK: Public API

    func append() {
        guard count < length else { return }
        drops[count] = Drop(position: CGPoint(x: cellX(count), y: -dropRadius), velocityY: 0, radius: dropRadius,
                            squash: Spring1D(0, stiffness: 22, dampingRatio: 0.3), state: .falling)
        count += 1
        landHaptic.prepare()
        canvas.isPaused = false
    }

    /// The last drop evaporates upward.
    func deleteLast() {
        guard count > 0 else { return }
        count -= 1
        drops[count]?.state = .leaving
        canvas.isPaused = false
    }

    /// Wrong code: splash, shake, and the drops run down out of the cells.
    func reject() {
        resultHaptic.notificationOccurred(.error)
        shake.velocity += 900
        for index in drops.indices {
            guard var drop = drops[index] else { continue }
            for _ in 0..<5 {
                let angle = CGFloat.random(in: -.pi...0)
                let speed = CGFloat.random(in: 120...320)
                splashes.append(Splash(position: drop.position,
                                       velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
                                       radius: .random(in: 2...4)))
            }
            drop.state = .running
            drop.velocityY = 0
            drops[index] = drop
        }
        count = 0
        canvas.isPaused = false
    }

    /// Right code: the drops run together into one, with a check mark on it.
    func accept() {
        resultHaptic.notificationOccurred(.success)
        for index in drops.indices {
            drops[index]?.state = .merging
        }
        UIView.animate(withDuration: 0.3, delay: 0.35, usingSpringWithDamping: 0.6, initialSpringVelocity: 0) {
            self.check.alpha = 1
            self.check.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
        }
        canvas.isPaused = false
    }

    func reset() {
        drops = Array(repeating: nil, count: length)
        splashes.removeAll()
        count = 0
        UIView.animate(withDuration: 0.2) {
            self.check.alpha = 0
            self.check.transform = .identity
        }
        canvas.isPaused = false
    }

    // MARK: Simulation

    private func step(_ dt: CFTimeInterval) {
        let t = CGFloat(dt)
        var moving = false
        for index in drops.indices {
            guard var drop = drops[index] else { continue }
            switch drop.state {
            case .falling:
                drop.velocityY += 2600 * t
                drop.position.y += drop.velocityY * t
                if drop.position.y >= rowY {
                    drop.position.y = rowY
                    drop.squash.velocity = drop.velocityY * 0.012
                    drop.velocityY = 0
                    drop.state = .resting
                    landHaptic.impactOccurred(intensity: 0.7)
                }
                moving = true
            case .resting:
                drop.squash.step(toward: 0, deltaTime: dt)
                if !drop.squash.isSettled(at: 0, tolerance: 0.002) {
                    moving = true
                }
            case .leaving:
                drop.position.y -= 260 * t
                drop.radius = max(0, drop.radius - 40 * t)
                moving = true
            case .running:
                // Runs down out of the cell as a thinning streak.
                drop.velocityY += 900 * t
                drop.position.y += drop.velocityY * t
                drop.stretch = min(drop.stretch + 60 * t, 26)
                drop.radius = max(0, drop.radius - 9 * t)
                moving = true
            case .merging:
                drop.position.x += (bounds.midX - drop.position.x) * min(1, 8 * t)
                drop.radius += (dropRadius * 1.6 - drop.radius) * min(1, 6 * t)
                moving = abs(drop.position.x - bounds.midX) > 0.3 || moving
            }
            drops[index] = drop.radius > 0.5 && drop.position.y < bounds.height + 40 ? drop : nil
        }
        for index in splashes.indices {
            splashes[index].velocity.dy += 1200 * t
            splashes[index].position.x += splashes[index].velocity.dx * t
            splashes[index].position.y += splashes[index].velocity.dy * t
            splashes[index].radius = max(0, splashes[index].radius - 4 * t)
        }
        splashes.removeAll { $0.radius <= 0.3 }
        shake.step(toward: 0, deltaTime: dt)
        transform = CGAffineTransform(translationX: shake.value * 0.04, y: 0)
        if !shake.isSettled(at: 0, tolerance: 0.5) {
            moving = true
        }

        var shapes: [IslandFluidShape] = []
        for drop in drops.compactMap({ $0 }) {
            let s = drop.squash.value
            let half = CGSize(width: drop.radius * (1 + s * 0.45), height: drop.radius * (1 - s * 0.35) + drop.stretch)
            let center = CGPoint(x: drop.position.x, y: drop.position.y + drop.radius * s * 0.35 + drop.stretch * 0.5)
            shapes.append(IslandFluidShape(center: center, halfSize: half, cornerRadius: min(half.width, half.height),
                                           blend: drop.state == .merging ? 22 : 4))
        }
        shapes += splashes.map { .circle(center: $0.position, radius: $0.radius, blend: 2) }
        canvas.shapes = shapes
        if !moving, splashes.isEmpty {
            canvas.renderFrame()
            canvas.isPaused = true
        }
    }
}
