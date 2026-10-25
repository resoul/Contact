import UIKit

/// The accordion/highlighter treatment from the X community-note prototype.
final class CommunityContextNoteView: UIStackView {
    var onToggle: ((Bool) -> Void)?
    private let toggleButton = UIButton(type: .system)
    private let body = UILabel()
    private var expanded = false

    init(expanded: Bool) {
        super.init(frame: .zero)
        axis = .vertical
        spacing = 10
        isLayoutMarginsRelativeArrangement = true
        layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        layer.borderWidth = 1
        layer.borderColor = UIColor.secondaryLabel.withAlphaComponent(0.3).cgColor
        layer.cornerRadius = 12
        toggleButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        toggleButton.contentHorizontalAlignment = .leading
        toggleButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.setExpanded(!self.expanded)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            self.onToggle?(self.expanded)
            if self.expanded { self.highlight() }
        }, for: .touchUpInside)
        body.font = .systemFont(ofSize: 14)
        body.textColor = .label
        body.numberOfLines = 0
        body.text = "Демонстрационная заметка: дополнительный контекст и ссылки на источники появятся под выбранными постами публичных каналов."
        addArrangedSubview(toggleButton)
        addArrangedSubview(body)
        setExpanded(expanded)
    }
    required init(coder: NSCoder) { fatalError("Use init(expanded:)") }
    func setExpanded(_ value: Bool) {
        expanded = value
        body.isHidden = !value
        toggleButton.setTitle(value ? "👥 Контекст сообщества ⌃" : "👥 Контекст сообщества ⌄", for: .normal)
        toggleButton.accessibilityValue = value ? "Expanded" : "Collapsed"
    }
    private func highlight() {
        layoutIfNeeded()
        let text = body.text ?? ""
        let range = (text as NSString).range(of: "дополнительный контекст")
        guard range.location != NSNotFound else { return }
        let highlighted = NSMutableAttributedString(string: text, attributes: [.font: body.font!, .foregroundColor: UIColor.label])
        highlighted.addAttribute(.backgroundColor, value: UIColor.systemYellow.withAlphaComponent(0.25), range: range)
        UIView.transition(with: body, duration: 0.35, options: .transitionCrossDissolve) { self.body.attributedText = highlighted }
    }
}
