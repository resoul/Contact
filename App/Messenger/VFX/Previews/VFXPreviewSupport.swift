//
//  TrickDemoSupport.swift
//  controller
//
//  Shared bits for the Telegram / Instagram / X trick demos: a dark page with a hint pill, simple
//  chat bubbles and chat-list rows, emoji rendered to images (for particle emitters), and a few
//  palettes.
//

import UIKit

enum TrickPalette {
    static let telegramBackground = UIColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 1)
    static let telegramPanel = UIColor(red: 0.12, green: 0.13, blue: 0.17, alpha: 1)
    static let telegramBlue = UIColor(red: 0.2, green: 0.56, blue: 0.98, alpha: 1)
    static let outgoing = UIColor(red: 0.27, green: 0.45, blue: 0.95, alpha: 1)
    static let incoming = UIColor(red: 0.16, green: 0.17, blue: 0.22, alpha: 1)
    static let secondary = UIColor(white: 1, alpha: 0.5)
    static let gold = UIColor(red: 1.0, green: 0.78, blue: 0.25, alpha: 1)
}

class TrickPage: UIViewController {
    let hint = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = TrickPalette.telegramBackground
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.overrideUserInterfaceStyle = .dark
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.navigationBar.overrideUserInterfaceStyle = .unspecified
    }

    /// A pill with how to use the demo, fading out after a few seconds.
    func showHint(_ text: String, bottom: CGFloat = 110) {
        hint.text = text
        hint.font = .systemFont(ofSize: 13, weight: .semibold)
        hint.textColor = .white
        hint.textAlignment = .center
        hint.numberOfLines = 0
        hint.backgroundColor = UIColor(white: 0, alpha: 0.55)
        hint.layer.cornerRadius = 15
        hint.clipsToBounds = true
        hint.isUserInteractionEnabled = false
        let size = hint.sizeThatFits(CGSize(width: view.bounds.width - 70, height: 200))
        hint.bounds = CGRect(x: 0, y: 0, width: size.width + 28, height: size.height + 14)
        hint.center = CGPoint(x: view.bounds.midX, y: view.bounds.height - view.safeAreaInsets.bottom - bottom)
        hint.alpha = 0
        view.addSubview(hint)
        UIView.animate(withDuration: 0.4) { self.hint.alpha = 1 }
        UIView.animate(withDuration: 0.6, delay: 4.5) { self.hint.alpha = 0 }
    }
}

enum TrickViews {
    /// A chat bubble with text.
    static func bubble(_ text: String, outgoing: Bool, width: CGFloat = 260) -> UIView {
        let bubble = UIView()
        bubble.backgroundColor = outgoing ? TrickPalette.outgoing : TrickPalette.incoming
        bubble.layer.cornerRadius = 18
        bubble.layer.cornerCurve = .continuous
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 16)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 9),
            label.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -9),
            label.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -14),
            label.widthAnchor.constraint(lessThanOrEqualToConstant: width - 28),
        ])
        return bubble
    }

    /// A full-width row holding `bubble` on the right (outgoing) or the left.
    static func row(_ bubble: UIView, outgoing: Bool) -> UIView {
        let row = UIView()
        bubble.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(bubble)
        NSLayoutConstraint.activate([
            bubble.topAnchor.constraint(equalTo: row.topAnchor, constant: 3),
            bubble.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -3),
            outgoing ? bubble.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -12)
                : bubble.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 12),
        ])
        return row
    }

    /// A chat-list row: avatar, name, last message, time and an unread badge.
    static func chatRow(_ person: ChannelPerson, message: String, time: String, unread: Int = 0) -> UIView {
        let row = UIView()
        let avatar = UIImageView(image: ChannelAvatar.image(for: person, size: 56))
        let name = UILabel()
        name.text = person.name
        name.font = .systemFont(ofSize: 16, weight: .semibold)
        name.textColor = .white
        let text = UILabel()
        text.text = message
        text.font = .systemFont(ofSize: 15)
        text.textColor = TrickPalette.secondary
        text.numberOfLines = 2
        let clock = UILabel()
        clock.text = time
        clock.font = .systemFont(ofSize: 13)
        clock.textColor = TrickPalette.secondary
        let badge = UILabel()
        badge.text = "\(unread)"
        badge.font = .systemFont(ofSize: 13, weight: .semibold)
        badge.textColor = .white
        badge.textAlignment = .center
        badge.backgroundColor = TrickPalette.telegramBlue
        badge.layer.cornerRadius = 11
        badge.clipsToBounds = true
        badge.isHidden = unread == 0
        for view in [avatar, name, text, clock, badge] {
            view.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(view)
        }
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 76),
            avatar.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14),
            avatar.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            avatar.widthAnchor.constraint(equalToConstant: 56),
            avatar.heightAnchor.constraint(equalToConstant: 56),
            name.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 12),
            name.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
            clock.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14),
            clock.centerYAnchor.constraint(equalTo: name.centerYAnchor),
            name.trailingAnchor.constraint(lessThanOrEqualTo: clock.leadingAnchor, constant: -8),
            text.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            text.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 2),
            text.trailingAnchor.constraint(equalTo: badge.leadingAnchor, constant: -10),
            badge.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14),
            badge.centerYAnchor.constraint(equalTo: text.centerYAnchor),
            badge.heightAnchor.constraint(equalToConstant: 22),
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 22),
        ])
        return row
    }

    private static var emojiCache: [String: UIImage] = [:]

    /// An emoji drawn into an image, for CAEmitterCell contents.
    static func emojiImage(_ emoji: String, size: CGFloat = 64) -> UIImage {
        let key = "\(emoji)|\(size)"
        if let cached = emojiCache[key] { return cached }
        let image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
            let text = emoji as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: size * 0.8)]
            let measured = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: (size - measured.width) / 2, y: (size - measured.height) / 2), withAttributes: attributes)
        }
        emojiCache[key] = image
        return image
    }

    /// Emoji flying out of `point` in `host` for `duration` seconds.
    static func emojiBurst(_ emoji: String, in host: UIView, at point: CGPoint, count: Float = 60, duration: TimeInterval = 0.5,
                           velocity: CGFloat = 420) {
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = point
        emitter.emitterShape = .point
        emitter.frame = host.bounds
        let cell = CAEmitterCell()
        cell.contents = emojiImage(emoji).cgImage
        cell.birthRate = count / Float(duration)
        cell.lifetime = 2.4
        cell.velocity = velocity
        cell.velocityRange = velocity * 0.6
        cell.emissionRange = .pi * 2
        cell.yAcceleration = 520
        cell.scale = 0.42
        cell.scaleRange = 0.2
        cell.scaleSpeed = -0.08
        cell.spin = 0
        cell.spinRange = 4
        cell.alphaSpeed = -0.35
        emitter.emitterCells = [cell]
        host.layer.addSublayer(emitter)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { emitter.birthRate = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 2.6) { emitter.removeFromSuperlayer() }
    }
}
