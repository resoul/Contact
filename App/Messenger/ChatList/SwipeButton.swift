import UIKit

final class SwipeButton: UIControl {
    private let icon = UIImageView()
    private let label = Views.label(size: 12, weight: .medium, color: .white)

    init(title: String, symbol: String, color: UIColor) {
        super.init(frame: .zero)
        backgroundColor = color
        clipsToBounds = true
        icon.tintColor = .white
        icon.contentMode = .center
        label.textAlignment = .center
        addSubview(icon)
        addSubview(label)
        set(title: title, symbol: symbol)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func set(title: String, symbol: String) {
        label.text = title
        icon.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold))
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let contentWidth: CGFloat = 76
        let x = (bounds.width - contentWidth) / 2
        icon.frame = CGRect(x: x, y: bounds.midY - 22, width: contentWidth, height: 26)
        label.frame = CGRect(x: x - 4, y: bounds.midY + 6, width: contentWidth + 8, height: 16)
        let visible = min(1, bounds.width / 40)
        icon.alpha = visible
        label.alpha = visible
    }
}
