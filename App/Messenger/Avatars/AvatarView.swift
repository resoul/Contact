import UIKit
import AvatarUI

/// UIKit adapter for screens that have not moved their row content to Texture nodes.
final class AvatarView: UIView {
    let avatarNode = AvatarUI.AvatarNode()
    private let dot = UIView()
    var online = false { didSet { dot.isHidden = !online } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        avatarNode.isUserInteractionEnabled = false
        addSubview(avatarNode.view)
        dot.backgroundColor = Palette.online
        dot.layer.borderWidth = 2.5
        dot.isHidden = true
        addSubview(dot)
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func set(_ person: ChannelPerson, size: CGFloat, peerID: Int? = nil) {
        avatarNode.apply(AvatarProvider.descriptor(for: person, peerID: peerID), presentation: .thumbnail)
        avatarNode.setVisible(window != nil)
    }
    func prepareForReuse() { avatarNode.prepareForReuse(); online = false }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        avatarNode.setVisible(window != nil)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        avatarNode.frame = bounds
        let size = bounds.width * 0.27
        dot.frame = CGRect(x: bounds.width - size + 1, y: bounds.height - size + 1, width: size, height: size)
        dot.layer.cornerRadius = size / 2
        dot.layer.borderColor = Palette.background.resolvedColor(with: traitCollection).cgColor
    }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        setNeedsLayout()
    }
}
