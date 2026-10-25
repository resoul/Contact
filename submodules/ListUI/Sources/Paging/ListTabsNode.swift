import UIKit
import AsyncDisplayKit

public final class ListTabsNode: ASDisplayNode {
    public var selected: ((Int) -> Void)?
    private let scroll = UIScrollView()
    private let indicator = UIView()
    private var buttons: [UIButton] = []
    private var pagePosition: CGFloat = 0
    private var theme = ListTheme()

    public override init() { super.init() }

    public override func didLoad() {
        super.didLoad()
        scroll.showsHorizontalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        view.addSubview(scroll)
        indicator.layer.cornerRadius = 1.5
        scroll.addSubview(indicator)
    }

    func apply(pages: [ListPage], theme: ListTheme) {
        _ = view
        self.theme = theme
        buttons.forEach { $0.removeFromSuperview() }
        buttons = pages.enumerated().map { index, page in
            let button = UIButton(type: .system)
            button.setTitle(page.title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
            button.accessibilityIdentifier = "listui.tab.\(page.id)"
            button.addAction(UIAction { [weak self] _ in self?.selected?(index) }, for: .touchUpInside)
            scroll.addSubview(button)
            return button
        }
        indicator.backgroundColor = theme.accent
        setNeedsLayout()
    }

    public override func layout() {
        super.layout()
        scroll.frame = bounds
        let intrinsicWidths = buttons.map { max(72, $0.sizeThatFits(CGSize(width: 1000, height: 44)).width + 36) }
        let total = intrinsicWidths.reduce(0, +)
        let extra = buttons.isEmpty ? 0 : max(0, bounds.width - total) / CGFloat(buttons.count)
        var x: CGFloat = 0
        for (index, button) in buttons.enumerated() {
            let width = intrinsicWidths[index] + extra
            button.frame = CGRect(x: x, y: 0, width: width, height: bounds.height)
            x += width
        }
        scroll.contentSize = CGSize(width: x, height: bounds.height)
        updateIndicator()
    }

    func setPosition(_ pagePosition: CGFloat, settled: Bool = false) {
        self.pagePosition = pagePosition
        updateIndicator()
        if settled, !buttons.isEmpty {
            let index = min(buttons.count - 1, max(0, Int(pagePosition.rounded())))
            scroll.scrollRectToVisible(buttons[index].frame, animated: !UIAccessibility.isReduceMotionEnabled)
        }
    }

    private func updateIndicator() {
        guard !buttons.isEmpty else { return }
        let clamped = min(CGFloat(buttons.count - 1), max(0, pagePosition))
        let left = Int(clamped), right = min(buttons.count - 1, left + 1)
        let fraction = clamped - CGFloat(left)
        let a = buttons[left].frame, b = buttons[right].frame
        indicator.frame = CGRect(x: a.minX + (b.minX - a.minX) * fraction + 18,
                                 y: max(0, bounds.height - 3),
                                 width: a.width + (b.width - a.width) * fraction - 36, height: 3)
        for (index, button) in buttons.enumerated() {
            let selected = index == Int(clamped.rounded())
            button.setTitleColor(selected ? theme.accent : theme.secondary, for: .normal)
            button.accessibilityTraits = selected ? [.button, .selected] : [.button]
        }
    }
}
