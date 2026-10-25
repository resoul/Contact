import UIKit

/// Finger state for Metal effects. `strength` eases in and out for smooth interaction.
struct TouchInput {
    var location: CGPoint = .zero
    var isActive = false
    private(set) var strength: Float = 0

    mutating func track(_ touches: Set<UITouch>, in view: UIView, isActive: Bool) {
        if let touch = touches.first {
            location = touch.location(in: view)
        }
        self.isActive = isActive
    }

    mutating func advance(deltaTime: Double) {
        strength = eased(strength, toward: isActive ? 1 : 0, deltaTime: deltaTime, rate: isActive ? 12 : 3)
    }
}

/// Frame-rate independent exponential easing.
func eased(_ current: Float, toward target: Float, deltaTime: Double, rate: Double = 10) -> Float {
    let k = Float(1 - exp(-deltaTime * rate))
    let next = current + (target - current) * k
    return abs(next - target) < 0.0005 ? target : next
}

