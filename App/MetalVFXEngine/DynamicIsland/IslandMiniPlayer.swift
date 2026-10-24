//
//  IslandMiniPlayer.swift
//  controller
//
//  Picture-in-island: a player (or a call, or any card) is flicked up and drains into the Dynamic
//  Island — its snapshot shrinks and melts into black liquid that the island swallows. The island
//  then lives on as a compact player: spinning artwork on the left, a dancing waveform on the right.
//  Tap it and the liquid pours back out, swelling to the card's frame before the card reappears.
//

import UIKit

final class IslandMiniPlayer: IslandFluidView {
    var onRestore: (() -> Void)?
    var waveColor: UIColor = .systemPink {
        didSet { bars.forEach { $0.backgroundColor = waveColor } }
    }
    var isPlaying = true

    private enum Phase {
        case idle
        case draining(CFTimeInterval)
        case minimized
        case restoring(CFTimeInterval)
    }

    private var phase = Phase.idle
    private weak var card: UIView?
    private var cardFrame: CGRect = .zero
    private var snapshot: UIImageView?
    private var blob = IslandSpring(.zero, stiffness: 15, dampingRatio: 0.6)
    private var blobSize = IslandSpring(.zero, stiffness: 15, dampingRatio: 0.55)
    private var swell = IslandSpring(.zero, stiffness: 14, dampingRatio: 0.42)
    private var recoilTime: CFTimeInterval?
    private var clock: CGFloat = 0

    private let artworkView = UIImageView()
    private var bars: [UIView] = []
    private let gulpHaptic = UIImpactFeedbackGenerator(style: .soft)
    private let tapHaptic = UIImpactFeedbackGenerator(style: .light)

    private let drainDuration: CFTimeInterval = 0.55

    override init(frame: CGRect) {
        super.init(frame: frame)
        gloss = 0.5
        rimWidth = 10
        isUserInteractionEnabled = true
        isPaused = true
        artworkView.contentMode = .scaleAspectFill
        artworkView.clipsToBounds = true
        artworkView.layer.cornerRadius = 12
        artworkView.bounds = CGRect(x: 0, y: 0, width: 24, height: 24)
        artworkView.alpha = 0
        addSubview(artworkView)
        bars = (0..<5).map { _ in
            let bar = UIView()
            bar.backgroundColor = waveColor
            bar.layer.cornerRadius = 1.5
            bar.alpha = 0
            addSubview(bar)
            return bar
        }
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isMinimized: Bool {
        if case .minimized = phase { return true }
        return false
    }

    // MARK: Public API

    /// Drains `card` into the island. The card is hidden (alpha 0) until it is restored.
    func minimize(_ card: UIView, artwork: UIImage?) {
        guard case .idle = phase, let window = card.window else { return }
        if self.window == nil {
            install(in: window)
        }
        self.card = card
        cardFrame = card.convert(card.bounds, to: self)
        artworkView.image = artwork
        let image = UIGraphicsImageRenderer(bounds: card.bounds).image { _ in
            card.drawHierarchy(in: card.bounds, afterScreenUpdates: false)
        }
        let imageView = UIImageView(image: image)
        imageView.frame = cardFrame
        imageView.layer.cornerRadius = card.layer.cornerRadius
        imageView.layer.cornerCurve = .continuous
        imageView.clipsToBounds = true
        insertSubview(imageView, at: 0)
        snapshot = imageView
        card.alpha = 0

        blob = IslandSpring(CGPoint(x: cardFrame.midX, y: cardFrame.midY), stiffness: 11, dampingRatio: 0.75)
        blobSize = IslandSpring(CGPoint(x: cardFrame.width / 2, y: cardFrame.height / 2), stiffness: 11, dampingRatio: 0.8)
        if swell.position == .zero {
            swell.position = CGPoint(x: island.width / 2, y: island.height / 2)
        }
        phase = .draining(0)
        gulpHaptic.prepare()
        isPaused = false
    }

    /// Pours the card back out of the island.
    func restore() {
        guard case .minimized = phase else { return }
        tapHaptic.impactOccurred()
        blob = IslandSpring(CGPoint(x: islandMouth.x, y: islandMouth.y - 4), stiffness: 12, dampingRatio: 0.7)
        blobSize = IslandSpring(CGPoint(x: 10, y: 10), stiffness: 12, dampingRatio: 0.62)
        phase = .restoring(0)
        isPaused = false
    }

    // MARK: Touches

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard isMinimized else { return false }
        let rect = CGRect(x: island.midX - swell.position.x, y: island.minY,
                          width: swell.position.x * 2, height: swell.position.y * 2)
        // The status bar band may keep touches on the island itself; accept taps just below it too.
        return rect.insetBy(dx: -8, dy: -8).inset(by: UIEdgeInsets(top: 0, left: 0, bottom: -22, right: 0)).contains(point)
    }

    @objc private func handleTap() {
        restore()
    }

    // MARK: Simulation

    override func update(deltaTime: CFTimeInterval) {
        clock += CGFloat(deltaTime)
        let mouth = islandMouth
        let rest = CGPoint(x: island.width / 2, y: island.height / 2)
        var swellTarget = rest
        var newShapes: [IslandFluidShape] = []

        switch phase {
        case .idle:
            break
        case .draining(let t):
            let now = t + deltaTime
            phase = .draining(now)
            blob.step(toward: CGPoint(x: mouth.x, y: mouth.y - 2), deltaTime: deltaTime)
            blobSize.step(toward: CGPoint(x: 9, y: 9), deltaTime: deltaTime)
            // The snapshot rides on the liquid and melts into it on the way up.
            if let snapshot {
                snapshot.bounds = CGRect(x: 0, y: 0, width: blobSize.position.x * 2, height: blobSize.position.y * 2)
                snapshot.center = blob.position
                snapshot.alpha = 1 - islandSmoothstep(0.15, 0.45, CGFloat(now / drainDuration))
            }
            let half = blobSize.position
            let distance = blob.position.distance(to: mouth)
            newShapes.append(IslandFluidShape(center: blob.position, halfSize: CGSize(width: half.x, height: half.y),
                                              cornerRadius: min(28, min(half.x, half.y)), blend: distance < 90 ? 18 : 0))
            if distance < 10, half.x < 14 {
                snapshot?.removeFromSuperview()
                snapshot = nil
                phase = .minimized
                swell.velocity.dx += 140
                swell.velocity.dy += 60
                recoilTime = 0
                gulpHaptic.impactOccurred()
            }
        case .minimized:
            swellTarget = CGPoint(x: rest.x + 28, y: rest.y + 1)
        case .restoring(let t):
            let now = t + deltaTime
            phase = .restoring(now)
            let target = cardFrame
            blob.step(toward: CGPoint(x: target.midX, y: target.midY), deltaTime: deltaTime)
            blobSize.step(toward: CGPoint(x: target.width / 2, y: target.height / 2), deltaTime: deltaTime)
            let half = blobSize.position
            // Pours out on a neck that tears, like the toast.
            let neck = 22 * max(0, 1 - CGFloat(now) / 0.3)
            newShapes.append(IslandFluidShape(center: blob.position, halfSize: CGSize(width: half.x, height: half.y),
                                              cornerRadius: min(28, min(half.x, half.y)), blend: neck))
            let grown = half.x > target.width / 2 * 0.94 && half.y > target.height / 2 * 0.94
            if grown, let card, card.alpha == 0 {
                UIView.animate(withDuration: 0.2, animations: { card.alpha = 1 })
            }
            if grown, now > 0.6, blobSize.speed < 40 {
                newShapes.removeLast()
                phase = .idle
                let onRestore = onRestore
                DispatchQueue.main.async { onRestore?() }
            }
        }

        swell.step(toward: swellTarget, deltaTime: deltaTime)
        let half = swell.position
        if abs(half.x - rest.x) > 0.3 || abs(half.y - rest.y) > 0.3 {
            newShapes.append(IslandFluidShape(center: CGPoint(x: island.midX, y: island.minY + max(half.y, rest.y)),
                                              halfSize: CGSize(width: max(half.x, rest.x), height: max(half.y, rest.y)),
                                              cornerRadius: max(half.y, rest.y), blend: 0))
        }
        if let t = recoilTime {
            recoilTime = t > 1 ? nil : t + deltaTime
            newShapes.append(recoilBump(t, amplitude: 9))
        }
        shapes = newShapes
        layoutEars(rest: rest)

        if case .idle = phase, swell.speed < 0.5, abs(swell.position.x - rest.x) < 0.3, recoilTime == nil {
            settle()
        }
    }

    /// Artwork on the left ear, waveform on the right; they show once the island has swollen.
    private func layoutEars(rest: CGPoint) {
        let open = islandSmoothstep(rest.x + 12, rest.x + 25, swell.position.x)
        let visible = isMinimized ? open : 0
        let midY = island.minY + swell.position.y
        artworkView.alpha = visible
        artworkView.center = CGPoint(x: island.midX - swell.position.x + 19, y: midY)
        artworkView.transform = isPlaying ? CGAffineTransform(rotationAngle: clock * 0.8) : artworkView.transform
        let right = island.midX + swell.position.x - 14
        for (index, bar) in bars.enumerated() {
            let i = CGFloat(index)
            let level = isPlaying ? 0.35 + 0.65 * abs(sin(clock * (5 + i * 1.3) + i * 1.7)) : 0.25
            let height = 4 + 12 * level
            bar.alpha = visible
            bar.frame = CGRect(x: right - (4 - i) * 4.5 - 3, y: midY - height / 2, width: 3, height: height)
        }
    }
}
