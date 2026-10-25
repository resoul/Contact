import UIKit

/// The current liquid selector, with a scrollable strip for a runtime-sized folder set.
final class ChatFolderTabsView: UIControl {
    private let scroll = UIScrollView()
    private var selector: LiquidSelector?
    private var buttons: [UIButton] = []
    private var badges: [UILabel] = []
    private var titles: [String] = []
    private var counts: [Int] = []
    private var needsReveal = false
    private(set) var selectedIndex = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        scroll.showsHorizontalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.delaysContentTouches = false
        addSubview(scroll)
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    func apply(titles: [String], counts: [Int], selectedIndex: Int) {
        guard !titles.isEmpty else { return }
        let rebuild = self.titles != titles
        if rebuild {
            self.titles = titles
            selector?.removeFromSuperview()
            buttons.forEach { $0.removeFromSuperview() }
            badges.forEach { $0.removeFromSuperview() }
            let selector = LiquidSelector(titles: titles, style: .segments, liquid: Palette.accent,
                                          selectedTint: .white, normalTint: Palette.secondary)
            selector.isUserInteractionEnabled = false
            selector.accessibilityElementsHidden = true
            scroll.addSubview(selector)
            self.selector = selector
            buttons = titles.enumerated().map { index, title in
                let button = UIButton(type: .custom)
                button.accessibilityLabel = title
                button.accessibilityIdentifier = "contact.folderTab.\(index)"
                button.addAction(UIAction { [weak self] _ in
                    self?.select(index)
                    self?.sendActions(for: .valueChanged)
                }, for: .touchUpInside)
                scroll.addSubview(button)
                return button
            }
            badges = titles.map { _ in
                let badge = UILabel()
                badge.font = .systemFont(ofSize: 10, weight: .bold)
                badge.textColor = .white
                badge.textAlignment = .center
                badge.layer.cornerRadius = 8
                badge.clipsToBounds = true
                badge.isUserInteractionEnabled = false
                scroll.addSubview(badge)
                return badge
            }
        }
        self.counts = counts
        let target = min(max(0, selectedIndex), titles.count - 1)
        needsReveal = needsReveal || rebuild || target != self.selectedIndex
        self.selectedIndex = target
        selector?.select(target, animated: !rebuild)
        for (index, button) in buttons.enumerated() {
            let count = counts.indices.contains(index) ? counts[index] : 0
            button.accessibilityLabel = titles[index] + (count > 0 ? ", \(count) unread chats" : "")
            button.accessibilityTraits = index == target ? [.button, .selected] : [.button]
        }
        setNeedsLayout()
    }

    func select(_ index: Int) {
        guard titles.indices.contains(index) else { return }
        apply(titles: titles, counts: counts, selectedIndex: index)
    }

    func setTransitionProgress(_ position: CGFloat) { selector?.setInteractivePosition(position) }

    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = bounds
        guard !titles.isEmpty else { return }
        let font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        let widest = titles.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let slot = titles.count <= Folder.allCases.count
            ? bounds.width / CGFloat(titles.count)
            : max(bounds.width / CGFloat(titles.count), min(190, max(88, widest + 34)))
        let width = slot * CGFloat(titles.count)
        scroll.contentSize = CGSize(width: width, height: bounds.height)
        selector?.frame = CGRect(x: 0, y: 0, width: width, height: bounds.height)
        for index in titles.indices {
            let frame = CGRect(x: CGFloat(index) * slot, y: 0, width: slot, height: bounds.height)
            buttons[index].frame = frame
            let count = counts.indices.contains(index) ? counts[index] : 0
            let badge = badges[index]
            badge.text = "\(count)"
            badge.isHidden = count == 0
            badge.backgroundColor = index == selectedIndex ? Palette.accent : Palette.muted
            let badgeWidth = max(16, badge.intrinsicContentSize.width + 6)
            let textWidth = min(slot - 32, (titles[index] as NSString).size(withAttributes: [.font: font]).width)
            badge.frame = CGRect(x: min(frame.maxX - badgeWidth, frame.midX + textWidth / 2 + 2), y: 0,
                                 width: badgeWidth, height: 16)
        }
        if needsReveal {
            needsReveal = false
            scroll.scrollRectToVisible(buttons[selectedIndex].frame, animated: !UIAccessibility.isReduceMotionEnabled)
        }
    }
}
