import UIKit

final class FolderEmptyView: UIView {
    private let stack = UIStackView()
    private let name = Views.label(size: 20, weight: .semibold)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        let icon = Views.label("📂", size: 58)
        let detail = Views.label("There are no chats in this folder yet.", size: 15, color: Palette.secondary)
        for label in [icon, name, detail] {
            label.textAlignment = .center
            label.numberOfLines = 0
            stack.addArrangedSubview(label)
        }
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
        let height = stack.systemLayoutSizeFitting(CGSize(width: width, height: 0),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        stack.frame = CGRect(x: 24, y: max(0, (bounds.height - height) / 2), width: width, height: height)
    }
}
