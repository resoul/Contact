//
//  MagneticButton.swift
//  controller
//
//  Buttons that feel the finger coming: inside a MagneticField, as a finger moves near a
//  MagneticButton its content leans toward it, the button swells a touch, and a soft glare slides
//  over its surface to where the finger is. Moving away, everything springs back. Plain UIKit.
//

import UIKit

final class MagneticButton: UIControl {
    private let surface = UIView()
    private let glare = CAGradientLayer()
    private let content = UIStackView()

    init(title: String, symbol: String, color: UIColor) {
        super.init(frame: .zero)
        surface.backgroundColor = color
        surface.layer.cornerRadius = 20
        surface.layer.cornerCurve = .continuous
        surface.clipsToBounds = true
        surface.isUserInteractionEnabled = false
        glare.type = .radial
        glare.colors = [UIColor.white.withAlphaComponent(0.55).cgColor, UIColor.white.withAlphaComponent(0).cgColor]
        glare.startPoint = CGPoint(x: 0.5, y: 0.5)
        glare.endPoint = CGPoint(x: 1, y: 1)
        glare.opacity = 0
        surface.layer.addSublayer(glare)

        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = .white
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 26, weight: .semibold)
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        content.addArrangedSubview(icon)
        content.addArrangedSubview(label)
        content.axis = .vertical
        content.spacing = 6
        content.alignment = .center
        content.isUserInteractionEnabled = false
        addSubview(surface)
        addSubview(content)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        surface.frame = bounds
        content.bounds = CGRect(origin: .zero, size: content.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize))
        if content.transform == .identity {
            content.center = CGPoint(x: bounds.midX, y: bounds.midY)
        }
    }

    /// `finger` in this button's coordinates, nil when there is none.
    fileprivate func attract(to finger: CGPoint?) {
        guard let finger else {
            UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.45, initialSpringVelocity: 0) {
                self.transform = .identity
                self.content.transform = .identity
            }
            glare.opacity = 0
            return
        }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let dx = finger.x - center.x, dy = finger.y - center.y
        let distance = hypot(dx, dy)
        let reach = max(bounds.width, bounds.height) * 1.1
        let pull = max(0, min(1, 1 - (distance - 10) / reach))
        let strength = pull * pull * (3 - 2 * pull)
        let lean = min(distance, 40) / max(distance, 1) * 0.3 * strength
        UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.transform = CGAffineTransform(translationX: dx * lean * 0.35, y: dy * lean * 0.35)
                .scaledBy(x: 1 + 0.05 * strength, y: 1 + 0.05 * strength)
            self.content.transform = CGAffineTransform(translationX: dx * lean, y: dy * lean)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let size = max(bounds.width, bounds.height) * 1.4
        glare.frame = CGRect(x: finger.x - size / 2, y: finger.y - size / 2, width: size, height: size)
        glare.opacity = Float(strength)
        CATransaction.commit()
    }
}

/// Watches a finger anywhere inside it (without taking the touch) and attracts every
/// MagneticButton among its subviews.
final class MagneticField: UIView, UIGestureRecognizerDelegate {
    private let haptic = UISelectionFeedbackGenerator()
    private weak var nearest: MagneticButton?

    override init(frame: CGRect) {
        super.init(frame: frame)
        let watch = UILongPressGestureRecognizer(target: self, action: #selector(watch(_:)))
        watch.minimumPressDuration = 0
        watch.cancelsTouchesInView = false
        watch.delegate = self
        addGestureRecognizer(watch)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    private var buttons: [MagneticButton] {
        var found: [MagneticButton] = []
        var stack: [UIView] = subviews
        while let view = stack.popLast() {
            if let button = view as? MagneticButton {
                found.append(button)
            }
            stack += view.subviews
        }
        return found
    }

    @objc private func watch(_ gesture: UILongPressGestureRecognizer) {
        let finger = gesture.location(in: self)
        let active = gesture.state == .began || gesture.state == .changed
        var closest: (MagneticButton, CGFloat)?
        for button in buttons {
            button.attract(to: active ? gesture.location(in: button) : nil)
            let frame = button.convert(button.bounds, to: self)
            let distance = hypot(finger.x - frame.midX, finger.y - frame.midY)
            if closest == nil || distance < closest!.1 {
                closest = (button, distance)
            }
        }
        // A tick as the pull hands over from one button to another.
        if active, let closest, closest.1 < 90, closest.0 !== nearest {
            nearest = closest.0
            haptic.selectionChanged()
        } else if !active {
            nearest = nil
        }
    }
}
