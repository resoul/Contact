//
//  MTTabBar.swift
//  controller
//
//  Mini-Telegram's tab bar and the account menu that grows out of it.
//
//  The selection is a drop of liquid: its front races to the new tab while its back clings to the
//  old one. The Settings tab shows the current account's avatar; holding it squeezes a menu out of
//  the tab as liquid. With one account it is a short settings menu; with several it is the account
//  list, and you choose by sliding the finger up without letting go.
//

import UIKit

final class MTTabBar: UIView {
    enum Tab: Int, CaseIterable {
        case contacts, calls, chats, settings

        var title: String {
            switch self {
            case .contacts: return "Контакты"
            case .calls: return "Звонки"
            case .chats: return "Чаты"
            case .settings: return "Настройки"
            }
        }

        var symbol: String {
            switch self {
            case .contacts: return "person.crop.circle.fill"
            case .calls: return "phone.fill"
            case .chats: return "bubble.left.and.bubble.right.fill"
            case .settings: return "gearshape.fill"
            }
        }
    }

    static let height: CGFloat = 54

    var onSelect: ((Tab) -> Void)?
    /// The Settings tab is being held: the menu follows this gesture.
    var onSettingsHold: ((UILongPressGestureRecognizer) -> Void)?
    var onSettingsDoubleTap: (() -> Void)?

    private(set) var selected: Tab = .chats
    private let background = MTViews.barBackground()
    private let hairline = UIView()
    private let canvas = LiquidCanvasView()
    private var icons: [UIImageView] = []
    private var titles: [UILabel] = []
    private var accessibleTabs: [MTTabAccessibilityElement] = []
    private let avatar = UIImageView()
    private let avatarRing = UIView()
    private let badge = MTBadge()
    private var head = Spring1D(2, stiffness: 20, dampingRatio: 0.62)
    private var tail = Spring1D(2, stiffness: 8.5, dampingRatio: 0.85)
    private var lastSettingsTap: CFTimeInterval = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(background)
        hairline.backgroundColor = MTPalette.separator
        addSubview(hairline)
        canvas.liquidColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.2, alpha: 1) : UIColor(white: 0.88, alpha: 1) }
        canvas.gloss = 0.35
        canvas.rimWidth = 5
        canvas.onUpdate = { [weak self] dt in self?.step(dt) }
        addSubview(canvas)
        for tab in Tab.allCases {
            let icon = UIImageView(image: UIImage(systemName: tab.symbol,
                                                  withConfiguration: UIImage.SymbolConfiguration(pointSize: 21, weight: .medium)))
            icon.contentMode = .center
            addSubview(icon)
            icons.append(icon)
            let title = MTViews.label(tab.title, size: 10, weight: .medium)
            title.textAlignment = .center
            addSubview(title)
            titles.append(title)
        }
        for tab in Tab.allCases {
            let element = MTTabAccessibilityElement(accessibilityContainer: self)
            element.accessibilityLabel = tab.title
            element.accessibilityIdentifier = "contact.tab.\(tab.rawValue)"
            element.accessibilityTraits = .button
            element.activate = { [weak self] in
                self?.select(tab)
                self?.onSelect?(tab)
            }
            accessibleTabs.append(element)
        }
        accessibilityElements = accessibleTabs
        // Settings shows the account's avatar instead of the gear.
        icons[Tab.settings.rawValue].isHidden = true
        avatarRing.layer.borderWidth = 2
        avatarRing.layer.borderColor = MTPalette.accent.cgColor
        addSubview(avatarRing)
        avatar.layer.cornerRadius = 13
        avatar.clipsToBounds = true
        addSubview(avatar)
        badge.isUserInteractionEnabled = false
        addSubview(badge)

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        hold.minimumPressDuration = 0.3
        hold.delegate = self
        addGestureRecognizer(hold)
        tint()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var slot: CGFloat { bounds.width / CGFloat(Tab.allCases.count) }

    func itemCenter(_ tab: Tab) -> CGPoint {
        CGPoint(x: slot * (CGFloat(tab.rawValue) + 0.5), y: 25)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        background.frame = bounds
        hairline.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 1 / max(traitCollection.displayScale, 1))
        canvas.frame = bounds.insetBy(dx: -12, dy: -12)
        for tab in Tab.allCases {
            accessibleTabs[tab.rawValue].accessibilityFrameInContainerSpace = CGRect(x: slot * CGFloat(tab.rawValue), y: 0, width: slot, height: Self.height)
            let center = itemCenter(tab)
            icons[tab.rawValue].frame = CGRect(x: center.x - 20, y: 4, width: 40, height: 30)
            titles[tab.rawValue].frame = CGRect(x: center.x - slot / 2, y: 33, width: slot, height: 13)
        }
        let settings = itemCenter(.settings)
        avatar.frame = CGRect(x: settings.x - 13, y: 6, width: 26, height: 26)
        avatarRing.frame = avatar.frame.insetBy(dx: -3, dy: -3)
        avatarRing.layer.cornerRadius = avatarRing.bounds.width / 2
        layoutBadge()
        canvas.isPaused = false
    }

    private func layoutBadge() {
        let chats = itemCenter(.chats)
        badge.frame = CGRect(x: chats.x + 6, y: 1, width: badge.width, height: 20)
        badge.layer.cornerRadius = 10
    }

    func setAvatar(_ person: ChannelPerson, animated: Bool) {
        let image = ChannelAvatar.image(for: person, size: 52)
        guard animated else {
            avatar.image = image
            return
        }
        UIView.transition(with: avatar, duration: 0.45, options: .transitionFlipFromLeft) { self.avatar.image = image }
        MTViews.pop(avatarRing, scale: 1.3)
    }

    func setUnread(_ count: Int, animated: Bool) {
        badge.set(count, animated: animated)
        layoutBadge()
    }

    func select(_ tab: Tab, animated: Bool = true) {
        guard tab != selected else { return }
        selected = tab
        if !animated {
            head.value = CGFloat(tab.rawValue)
            tail.value = head.value
        } else if tab != .settings {
            if #available(iOS 17.0, *) {
                icons[tab.rawValue].addSymbolEffect(.bounce, options: .nonRepeating)
            } else {
                MTViews.pop(icons[tab.rawValue], scale: 0.8)
            }
        } else {
            MTViews.pop(avatar, scale: 0.8)
        }
        UIView.transition(with: self, duration: 0.2, options: .transitionCrossDissolve) { self.tint() }
        canvas.isPaused = false
    }

    private func tint() {
        for tab in Tab.allCases {
            accessibleTabs[tab.rawValue].accessibilityTraits = tab == selected ? [.button, .selected] : .button
            let color = tab == selected ? MTPalette.accent : MTPalette.secondary
            icons[tab.rawValue].tintColor = color
            titles[tab.rawValue].textColor = color
        }
        avatarRing.alpha = selected == .settings ? 1 : 0
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        let index = Int(gesture.location(in: self).x / slot)
        guard let tab = Tab(rawValue: min(max(index, 0), 3)) else { return }
        if tab == .settings {
            let now = CACurrentMediaTime()
            if now - lastSettingsTap < 0.35, selected == .settings {
                lastSettingsTap = 0
                onSettingsDoubleTap?()
                return
            }
            lastSettingsTap = now
        }
        if tab != selected { UISelectionFeedbackGenerator().selectionChanged() }
        select(tab)
        onSelect?(tab)
    }

    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        onSettingsHold?(gesture)
    }

    private func step(_ dt: CFTimeInterval) {
        let target = CGFloat(selected.rawValue)
        head.step(toward: target, deltaTime: dt)
        tail.step(toward: target, deltaTime: dt)
        func center(_ position: CGFloat) -> CGPoint {
            CGPoint(x: slot * (position + 0.5) + 12, y: 26 + 12)
        }
        let a = center(head.value), b = center(tail.value)
        let stretch = abs(a.x - b.x)
        let squeeze = 1 - min(stretch / (slot * 2.5), 0.32)
        let half = CGSize(width: min(slot / 2 - 6, 40), height: 23 * squeeze)
        canvas.shapes = [
            IslandFluidShape(center: a, halfSize: half, cornerRadius: half.height, blend: 0),
            IslandFluidShape(center: b, halfSize: CGSize(width: half.width * 0.8, height: half.height * 0.8),
                             cornerRadius: half.height * 0.8, blend: 18),
        ]
        canvas.spikes = stretch > 2 ? [IslandFluidSpike(base: b, tip: a, baseRadius: half.height * 0.4,
                                                        tipRadius: half.height * 0.7, blend: 6)] : []
        if head.isSettled(at: target, tolerance: 0.001), tail.isSettled(at: target, tolerance: 0.001) {
            canvas.renderFrame()
            canvas.isPaused = true
        }
    }
}

extension MTTabBar: UIGestureRecognizerDelegate {
    override func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        guard gesture is UILongPressGestureRecognizer else { return true }
        return Int(gesture.location(in: self).x / slot) == Tab.settings.rawValue
    }
}

// MARK: - Account menu

/// A menu squeezed out of a tab as liquid. Rows are chosen by sliding the finger that opened it
/// (release on a row) or by tapping once it is open.
final class MTAccountMenu: UIView {
    struct Item {
        let title: String
        let symbol: String?
        let person: ChannelPerson?
        var checked = false
        var accent = false
    }

    var onPick: ((Int) -> Void)?

    private let items: [Item]
    private let anchor: CGPoint
    private let dim = UIView()
    private let canvas = LiquidCanvasView()
    private let content = UIView()
    private let highlight = UIView()
    private var rows: [UIView] = []
    private var progress = Spring1D(0, stiffness: 15, dampingRatio: 0.68)
    private var target: CGFloat = 1
    private var panel = CGRect.zero
    private var highlighted: Int?
    private var link: CADisplayLink?
    private var closing = false
    private let rowHeight: CGFloat = 50

    /// `anchor` is the held tab's center in `host`'s coordinates.
    init(in host: UIView, anchor: CGPoint, items: [Item]) {
        self.items = items
        self.anchor = anchor
        super.init(frame: host.bounds)
        host.addSubview(self)
        dim.backgroundColor = UIColor(white: 0, alpha: 0.28)
        dim.frame = bounds
        dim.alpha = 0
        addSubview(dim)

        let width: CGFloat = 260
        let height = rowHeight * CGFloat(items.count)
        panel = CGRect(x: bounds.width - width - 10, y: anchor.y - 40 - height, width: width, height: height)
        canvas.frame = bounds
        canvas.liquidColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.16, alpha: 1) : .white }
        canvas.gloss = 0.3
        canvas.rimWidth = 8
        canvas.onUpdate = { [weak self] dt in self?.step(dt) }
        addSubview(canvas)

        content.frame = panel
        content.alpha = 0
        addSubview(content)
        highlight.backgroundColor = MTPalette.fill
        highlight.layer.cornerRadius = 12
        highlight.alpha = 0
        content.addSubview(highlight)
        for (index, item) in items.enumerated() {
            let row = makeRow(item, index: index)
            row.frame = CGRect(x: 0, y: rowHeight * CGFloat(index), width: width, height: rowHeight)
            content.addSubview(row)
            rows.append(row)
        }
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        UIView.animate(withDuration: 0.25) { self.dim.alpha = 1 }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func makeRow(_ item: Item, index: Int) -> UIView {
        let row = UIView()
        let title = MTViews.label(item.title, size: 16, weight: item.person != nil ? .semibold : .regular,
                                  color: item.accent ? MTPalette.accent : MTPalette.text)
        title.frame = CGRect(x: 56, y: 0, width: 160, height: rowHeight)
        row.addSubview(title)
        if let person = item.person {
            let avatar = UIImageView(image: ChannelAvatar.image(for: person, size: 32))
            avatar.frame = CGRect(x: 14, y: (rowHeight - 32) / 2, width: 32, height: 32)
            row.addSubview(avatar)
        } else if let symbol = item.symbol {
            let icon = UIImageView(image: UIImage(systemName: symbol))
            icon.tintColor = item.accent ? MTPalette.accent : MTPalette.text
            icon.contentMode = .center
            icon.frame = CGRect(x: 14, y: 0, width: 32, height: rowHeight)
            row.addSubview(icon)
        }
        if item.checked {
            let check = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
            check.tintColor = MTPalette.accent
            check.frame = CGRect(x: 260 - 40, y: (rowHeight - 24) / 2, width: 24, height: 24)
            row.addSubview(check)
        }
        if index < items.count - 1 {
            let line = UIView()
            line.backgroundColor = MTPalette.separator
            line.frame = CGRect(x: 56, y: rowHeight - 0.5, width: 204, height: 0.5)
            row.addSubview(line)
        }
        return row
    }

    // MARK: Finger tracking

    /// Follows the holding finger (`point` in this view): the row under it lights up.
    func track(_ point: CGPoint) {
        let local = convert(point, to: content)
        var index: Int?
        if content.bounds.insetBy(dx: -20, dy: 0).contains(local), local.y >= 0 {
            index = min(Int(local.y / rowHeight), items.count - 1)
        }
        guard index != highlighted else { return }
        highlighted = index
        if index != nil { UISelectionFeedbackGenerator().selectionChanged() }
        UIView.animate(withDuration: 0.18) {
            if let index {
                self.highlight.alpha = 1
                self.highlight.frame = CGRect(x: 6, y: self.rowHeight * CGFloat(index) + 3, width: self.panel.width - 12,
                                              height: self.rowHeight - 6)
            } else {
                self.highlight.alpha = 0
            }
        }
    }

    /// The holding finger lifted: picks the row under it, or stays open for taps.
    func release() {
        if let highlighted {
            pick(highlighted)
        }
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        let local = gesture.location(in: content)
        if content.bounds.contains(local) {
            pick(min(Int(local.y / rowHeight), items.count - 1))
        } else {
            close()
        }
    }

    private func pick(_ index: Int) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        close()
        onPick?(index)
    }

    func close() {
        guard !closing else { return }
        closing = true
        target = 0
        isUserInteractionEnabled = false
        canvas.isPaused = false
        UIView.animate(withDuration: 0.15) { self.content.alpha = 0 }
        UIView.animate(withDuration: 0.35) { self.dim.alpha = 0 }
    }

    // MARK: Liquid

    private func step(_ dt: CFTimeInterval) {
        progress.step(toward: target, deltaTime: dt)
        let p = max(progress.value, 0)
        // The blob on the tab, and the panel rising out of it.
        let tabBlob = IslandFluidShape.circle(center: anchor, radius: 22 * (1 - p * 0.35), blend: 0)
        let smallHalf = CGSize(width: 20, height: 20)
        let fullHalf = CGSize(width: panel.width / 2, height: panel.height / 2)
        let rise = min(p * 1.15, 1)
        let center = CGPoint(x: anchor.x + (panel.midX - anchor.x) * rise, y: anchor.y + (panel.midY - anchor.y) * rise)
        let half = CGSize(width: smallHalf.width + (fullHalf.width - smallHalf.width) * p,
                          height: smallHalf.height + (fullHalf.height - smallHalf.height) * p)
        let box = IslandFluidShape(center: center, halfSize: half, cornerRadius: min(22, half.height), blend: 34 * (1 - p) + 6)
        // A neck joins them until the panel has torn away.
        let neck = max(0, 1 - p * 1.3)
        canvas.shapes = [tabBlob, box]
        canvas.spikes = neck > 0.02 ? [IslandFluidSpike(base: anchor, tip: CGPoint(x: center.x, y: center.y + half.height * 0.6),
                                                        baseRadius: 16 * neck, tipRadius: 22 * neck, blend: 10)] : []
        content.alpha = closing ? content.alpha : islandSmoothstep(0.55, 0.95, p)
        let scale = 0.92 + 0.08 * min(p, 1)
        content.transform = CGAffineTransform(scaleX: scale, y: scale)
        if closing, progress.value < 0.02 {
            canvas.settle()
            removeFromSuperview()
        } else if !closing, progress.isSettled(at: 1, tolerance: 0.001) {
            canvas.renderFrame()
            canvas.isPaused = true
        }
    }
}

private final class MTTabAccessibilityElement: UIAccessibilityElement {
    var activate: (() -> Void)?
    override func accessibilityActivate() -> Bool {
        activate?()
        return true
    }
}
