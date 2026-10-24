//
//  IslandTypingIndicator.swift
//  controller
//
//  "Typing…" as boiling liquid: three drops bubble up and down along the island's lower lip, like
//  the surface of a simmering pot. When the message arrives they run together into one drop that
//  becomes a LiquidIslandToast, carrying straight on from the toast's own first frame.
//

import UIKit

final class IslandTypingIndicator: IslandFluidView {
    private enum Phase {
        case hidden
        case typing
        case merging(CFTimeInterval)
    }

    private struct Bubble {
        var position: IslandSpring
        var radius: CGFloat = 0
    }

    private var phase = Phase.hidden
    private var bubbles = (0..<3).map { _ in Bubble(position: IslandSpring(.zero, stiffness: 18, dampingRatio: 0.5)) }
    private var clock: CGFloat = 0
    private var pendingToast: (title: String, message: String?, symbol: String?)?
    private var onToast: ((LiquidIslandToast) -> Void)?
    private let haptic = UIImpactFeedbackGenerator(style: .soft)

    override init(frame: CGRect) {
        super.init(frame: frame)
        gloss = 0.7
        rimWidth = 6
        isPaused = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isTyping: Bool {
        if case .typing = phase { return true }
        return false
    }

    // MARK: Public API

    func startTyping() {
        guard case .hidden = phase else { return }
        phase = .typing
        for index in bubbles.indices {
            bubbles[index] = Bubble(position: IslandSpring(CGPoint(x: islandMouth.x, y: islandMouth.y - 4),
                                                           stiffness: 18, dampingRatio: 0.5))
        }
        isPaused = false
    }

    /// Stops without a message: the bubbles sink back into the island.
    func stopTyping() {
        guard isTyping else { return }
        pendingToast = nil
        phase = .merging(0)
    }

    /// The message arrived: the bubbles run together into one drop that becomes a toast.
    func deliver(title: String, message: String?, symbol: String?, onToast: ((LiquidIslandToast) -> Void)? = nil) {
        pendingToast = (title, message, symbol)
        self.onToast = onToast
        if isTyping {
            phase = .merging(0)
        } else {
            handOff()
        }
        isPaused = false
    }

    private func handOff() {
        guard let toast = pendingToast, let window else { return }
        pendingToast = nil
        let shown = LiquidIslandToast.show(in: window, title: toast.title, message: toast.message, symbol: toast.symbol)
        if let drop = bubbles.first {
            shown.continueFrom(dropAt: drop.position.position, radius: max(drop.radius, 6))
        }
        onToast?(shown)
    }

    // MARK: Simulation

    override func update(deltaTime: CFTimeInterval) {
        clock += CGFloat(deltaTime)
        let dt = CGFloat(deltaTime)
        let mouth = islandMouth
        switch phase {
        case .hidden:
            settle()
            return
        case .typing:
            for index in bubbles.indices {
                let i = CGFloat(index)
                // Each bubble rises and sinks on its own beat; together they read as a ripple.
                let boil = abs(sin(clock * 5.2 - i * 0.9))
                let target = CGPoint(x: mouth.x + (i - 1) * 15, y: mouth.y + 3 + boil * 11)
                bubbles[index].position.step(toward: target, deltaTime: deltaTime)
                let targetRadius = 4.6 + boil * 1.6
                bubbles[index].radius += (targetRadius - bubbles[index].radius) * min(1, dt * 12)
            }
        case .merging(let t):
            let now = t + deltaTime
            phase = .merging(now)
            let delivering = pendingToast != nil
            // Run together under the middle of the island, then either become a toast or sink back in.
            let target = delivering ? CGPoint(x: mouth.x, y: mouth.y + 20) : CGPoint(x: mouth.x, y: mouth.y - 4)
            for index in bubbles.indices {
                bubbles[index].position.step(toward: target, deltaTime: deltaTime)
                let targetRadius: CGFloat = delivering ? 9 : 2
                bubbles[index].radius += (targetRadius - bubbles[index].radius) * min(1, dt * 8)
            }
            if now > 0.28 {
                haptic.impactOccurred(intensity: 0.6)
                phase = .hidden
                if delivering {
                    handOff()
                }
                settle()
                return
            }
        }
        shapes = bubbles.map { .circle(center: $0.position.position, radius: $0.radius, blend: 9) }
    }
}
