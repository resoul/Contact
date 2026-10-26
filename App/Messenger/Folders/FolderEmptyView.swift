import UIKit

final class FolderEmptyView: UIView {
    private let stack = UIStackView()
    private let name = Views.label(size: 20, weight: .semibold)
    private let edit = UIButton(type: .system)
    var onEdit: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        let icon = Views.label("📂", size: 58)
        let detail = Views.label("There are no chats in this folder yet.", size: 15, color: Palette.secondary)
        for label in [icon, name, detail] {
            label.textAlignment = .center
            label.numberOfLines = 0
            stack.addArrangedSubview(label)
        }
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Add Chats"
        configuration.image = UIImage(systemName: "plus")
        configuration.imagePadding = 6
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = Palette.accent
        edit.configuration = configuration
        edit.accessibilityIdentifier = "contact.folderAddChats"
        edit.addAction(UIAction { [weak self] _ in self?.onEdit?() }, for: .touchUpInside)
        stack.addArrangedSubview(edit)
        stack.setCustomSpacing(20, after: detail)
        stack.alignment = .center
        stack.axis = .vertical
        stack.spacing = 12
        addSubview(stack)
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func setFolderName(_ title: String) {
        name.text = title
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = max(0, bounds.width - 48)
        // Centred arrangement keeps the button compact; labels still wrap at the full width.
        for case let label as UILabel in stack.arrangedSubviews { label.preferredMaxLayoutWidth = width }
        let height = stack.systemLayoutSizeFitting(CGSize(width: width, height: 0),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        stack.frame = CGRect(x: 24, y: max(0, (bounds.height - height) / 2), width: width, height: height)
    }
}
