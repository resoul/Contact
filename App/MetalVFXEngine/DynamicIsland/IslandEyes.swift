//
//  IslandEyes.swift
//  controller
//
//  The Dynamic Island grows a face: a liquid brow bulges out under it with two eyes that follow
//  the finger or the text caret, blink now and then, close while a password is typed, squint and
//  shake their head at an error, and smile (^ ^) on success.
//

import UIKit

final class IslandEyes: IslandFluidView {
    private var visible = false
    private var face = IslandSpring(.zero, stiffness: 14, dampingRatio: 0.4)
    private var shake: CGFloat = 0
    private var shakeVelocity: CGFloat = 0
    private var lookTarget: CGPoint?
    private var covered = false
    private var squintUntil: CFTimeInterval = 0
    private var happyUntil: CFTimeInterval = 0
    private var nextBlink: CFTimeInterval = 2
    private var clock: CFTimeInterval = 0
    private let eyes = [EyeView(), EyeView()]
    private let haptic = UINotificationFeedbackGenerator()

    private let faceHalf = CGSize(width: 38, height: 13)

    override init(frame: CGRect) {
        super.init(frame: frame)
        gloss = 0.4
        rimWidth = 9
        isPaused = true
        eyes.forEach { eye in
            eye.alpha = 0
            addSubview(eye)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Public API

    func show() {
        visible = true
        isPaused = false
    }

    func hide() {
        visible = false
        isPaused = false
    }

    /// Where the eyes look, in this view's (window) coordinates; nil looks straight ahead.
    func look(at point: CGPoint?) {
        lookTarget = point
        isPaused = false
    }

    /// Eyes shut while something private (a password) is being typed.
    func cover(_ covered: Bool) {
        self.covered = covered
        isPaused = false
    }

    /// Wrong answer: squint and shake the head.
    func disapprove() {
        squintUntil = clock + 0.9
        shakeVelocity += 900
        haptic.notificationOccurred(.error)
        isPaused = false
    }

    /// Right answer: happy ^ ^ eyes and a little hop.
    func approve() {
        happyUntil = clock + 1.3
        face.velocity.dy -= 160
        haptic.notificationOccurred(.success)
        isPaused = false
    }

    // MARK: Simulation

    override func update(deltaTime: CFTimeInterval) {
        clock += deltaTime
        let dt = CGFloat(deltaTime)
        // face.position: x = horizontal half size, y = vertical half size of the brow.
        face.step(toward: visible ? CGPoint(x: faceHalf.width, y: faceHalf.height) : .zero, deltaTime: deltaTime)
        shakeVelocity += (-700 * shake - 9 * shakeVelocity) * dt
        shake += shakeVelocity * dt

        let half = CGSize(width: max(face.position.x, 0), height: max(face.position.y, 0))
        let center = CGPoint(x: islandMouth.x + shake, y: islandMouth.y - 6 + half.height)
        let open = islandSmoothstep(faceHalf.height * 0.6, faceHalf.height * 0.95, half.height)

        // Blinks at random intervals.
        if clock > nextBlink {
            nextBlink = clock + .random(in: 2.2...4.8)
            eyes.forEach { $0.blink() }
        }
        let mood: EyeView.Mood
        if clock < happyUntil {
            mood = .happy
        } else if covered {
            mood = .closed
        } else if clock < squintUntil {
            mood = .squint
        } else {
            mood = .open
        }
        for (index, eye) in eyes.enumerated() {
            let side: CGFloat = index == 0 ? -1 : 1
            let eyeCenter = CGPoint(x: center.x + side * 15, y: center.y + 1)
            eye.center = eyeCenter
            eye.alpha = visible ? open : 0
            eye.mood = mood
            eye.squintSide = side
            if let lookTarget {
                let dx = lookTarget.x - eyeCenter.x, dy = lookTarget.y - eyeCenter.y
                let length = max(hypot(dx, dy), 1)
                eye.pupilOffset = CGPoint(x: dx / length * min(length / 40, 1) * 2.8,
                                          y: dy / length * min(length / 40, 1) * 2.8)
            } else {
                eye.pupilOffset = CGPoint(x: 0, y: 0.8)
            }
        }

        if half.width > 0.5 {
            shapes = [IslandFluidShape(center: center, halfSize: half, cornerRadius: min(half.height, 13), blend: 10)]
        } else {
            shapes = []
        }
        let still = face.speed < 0.5 && abs(shakeVelocity) < 1 && abs(shake) < 0.2
        if !visible, still, half.width < 0.5 {
            settle()
        }
    }
}

/// One cartoon eye: white ball, black pupil; shut, squinting or happy ^ shapes for moods.
private final class EyeView: UIView {
    enum Mood {
        case open
        case closed
        case squint
        case happy
    }

    var pupilOffset: CGPoint = .zero {
        didSet { setNeedsLayout() }
    }
    var mood = Mood.open {
        didSet { if mood != oldValue { applyMood() } }
    }
    /// -1 for the left eye, 1 for the right: which way a squint tilts.
    var squintSide: CGFloat = 1

    private let ball = CAShapeLayer()
    private let pupil = CAShapeLayer()
    private let arc = CAShapeLayer()
    private let diameter: CGFloat = 13

    override init(frame: CGRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: 13, height: 13))
        isUserInteractionEnabled = false
        ball.path = UIBezierPath(ovalIn: bounds).cgPath
        ball.fillColor = UIColor.white.cgColor
        pupil.path = UIBezierPath(ovalIn: CGRect(x: -3, y: -3, width: 6, height: 6)).cgPath
        pupil.fillColor = UIColor.black.cgColor
        let smile = UIBezierPath()
        smile.move(to: CGPoint(x: 1.5, y: 9))
        smile.addQuadCurve(to: CGPoint(x: 11.5, y: 9), controlPoint: CGPoint(x: 6.5, y: 0.5))
        arc.path = smile.cgPath
        arc.strokeColor = UIColor.white.cgColor
        arc.fillColor = nil
        arc.lineWidth = 2.6
        arc.lineCap = .round
        arc.isHidden = true
        layer.addSublayer(ball)
        ball.addSublayer(pupil)
        layer.addSublayer(arc)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pupil.position = CGPoint(x: diameter / 2 + pupilOffset.x, y: diameter / 2 + pupilOffset.y)
        CATransaction.commit()
    }

    func blink() {
        guard mood == .open else { return }
        let animation = CAKeyframeAnimation(keyPath: "transform.scale.y")
        animation.values = [1, 0.08, 1]
        animation.keyTimes = [0, 0.4, 1]
        animation.duration = 0.17
        ball.add(animation, forKey: "blink")
    }

    private func applyMood() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        switch mood {
        case .open:
            ball.isHidden = false
            arc.isHidden = true
            ball.setAffineTransform(.identity)
        case .closed:
            ball.isHidden = false
            arc.isHidden = true
            ball.setAffineTransform(CGAffineTransform(scaleX: 1.1, y: 0.12))
        case .squint:
            ball.isHidden = false
            arc.isHidden = true
            // Angry: flattened and tilted down toward the nose.
            ball.setAffineTransform(CGAffineTransform(rotationAngle: 0.35 * squintSide).scaledBy(x: 1.05, y: 0.4))
        case .happy:
            ball.isHidden = true
            arc.isHidden = false
        }
        CATransaction.commit()
    }
}
