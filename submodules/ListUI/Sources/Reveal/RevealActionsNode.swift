import UIKit

final class RevealActionsView: UIView {
    var selected: ((RevealAction) -> Void)?
    private var buttons: [UIButton] = []
    private var actions: [RevealAction] = []

    func configure(_ actions: [RevealAction]) {
        buttons.forEach { $0.removeFromSuperview() }
        self.actions = actions
        buttons = actions.map { action in
            let button = UIButton(type: .system)
            var config = UIButton.Configuration.plain()
            config.title = action.title
            config.image = UIImage(systemName: action.systemImage)
            config.imagePlacement = .top
            config.imagePadding = 5
            config.baseForegroundColor = .white
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var attributes = attributes
                attributes.font = .systemFont(ofSize: 11, weight: .medium)
                return attributes
            }
            button.configuration = config
            button.backgroundColor = action.color
            button.accessibilityLabel = action.title
            button.addAction(UIAction { [weak self] _ in self?.selected?(action) }, for: .touchUpInside)
            addSubview(button)
            return button
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !buttons.isEmpty else { return }
        let width = bounds.width / CGFloat(buttons.count)
        for (index, button) in buttons.enumerated() {
            button.frame = CGRect(x: CGFloat(index) * width, y: 0, width: width, height: bounds.height)
        }
    }
}
