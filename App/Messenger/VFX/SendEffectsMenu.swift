import UIKit

final class SendEffectsMenu: UIView {
    init(in host: UIView, origin: CGPoint, onPick: @escaping (String) -> Void) {
        super.init(frame: host.bounds)
        backgroundColor = UIColor.black.withAlphaComponent(0.35)
        let panel = UIStackView()
        panel.axis = .vertical
        panel.backgroundColor = Palette.cell
        panel.layer.cornerRadius = 26
        panel.clipsToBounds = true
        let effects = ["🎉", "❤️", "👍", "🔥", "💩", "🤯"]
        panel.frame = CGRect(x: min(bounds.width - 64, max(12, origin.x - 26)),
                             y: max(host.safeAreaInsets.top + 8, origin.y - 312), width: 52, height: 294)
        for (index, effect) in effects.enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(effect, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 30)
            button.accessibilityLabel = "Send with \(effect)"
            button.addAction(UIAction { [weak self] _ in
                self?.removeFromSuperview()
                onPick(effect)
            }, for: .touchUpInside)
            panel.addArrangedSubview(button)
            button.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
            UIView.animate(withDuration: 0.45, delay: 0.03 * Double(index), usingSpringWithDamping: 0.5,
                           initialSpringVelocity: 0.6) { button.transform = .identity }
        }
        panel.distribution = .fillEqually
        let dismiss = UIControl(frame: bounds)
        dismiss.addAction(UIAction { [weak self] _ in self?.removeFromSuperview() }, for: .touchUpInside)
        addSubview(dismiss)
        addSubview(panel)
        host.addSubview(self)
        alpha = 0
        UIView.animate(withDuration: 0.2) { self.alpha = 1 }
    }
    required init?(coder: NSCoder) { fatalError("Use init(in:origin:onPick:)") }
}

enum VFXChatFixtures {
    static let playground = Chat(id: -101, person: ChannelPerson(name: "VFX Playground", hue: 0.55),
                                 kind: .person, message: "Photo stack and message effects", time: "", online: true)
    static func messages() -> [(title: String, messages: [Message])] {
        var album = Message(kind: .photos([.sunset, .bloom, .ocean]), outgoing: false, time: "12:00")
        album.usesPhotoStack = true
        return [("Today", [Message(kind: .text("Tap the stack to spread the photos. Type a message and hold Send to choose an effect."),
                                   outgoing: false, time: "12:00"), album])]
    }
}
