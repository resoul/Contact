//
//  MTChatThemes.swift
//  controller
//
//  Chat themes: each one is a day and a night wallpaper palette plus the color of your bubbles.
//  The sheet previews a theme live in the chat behind it as you tap through the tiles; "Cancel"
//  puts the old one back. Its sun / moon button turns the chat from day to night through a dusk.
//

import UIKit

struct MTChatTheme {
    let emoji: String
    let name: String
    let day: [UIColor]
    let night: [UIColor]
    let outgoingDay: UIColor
    let outgoingNight: UIColor

    private static func rgb(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1)
    }

    static let all: [MTChatTheme] = [
        MTChatTheme(emoji: "🏠", name: "Classic", day: [0xDBDDBB, 0x6BA587, 0xD5D88D, 0x88B884].map(rgb),
                    night: [0x0F1A24, 0x1B2B3A, 0x0B1320, 0x203347].map(rgb),
                    outgoingDay: rgb(0xE1FAC8), outgoingNight: rgb(0x3361C0)),
        MTChatTheme(emoji: "🐥", name: "Chick", day: [0xF7E48B, 0xF4C46B, 0xFBE9A8, 0xF0B35A].map(rgb),
                    night: [0x2A1E0B, 0x3A2A10, 0x1E1608, 0x47331A].map(rgb),
                    outgoingDay: rgb(0xFFF1B8), outgoingNight: rgb(0xB0791E)),
        MTChatTheme(emoji: "⛄️", name: "Snowman", day: [0xBFD9F5, 0x8FB6E8, 0xD6E8FA, 0x9CC3EC].map(rgb),
                    night: [0x0D1B33, 0x16294A, 0x0A1428, 0x1F3660].map(rgb),
                    outgoingDay: rgb(0xD6ECFF), outgoingNight: rgb(0x2F6FD6)),
        MTChatTheme(emoji: "💎", name: "Crystal", day: [0xC9B6F2, 0x8E7BE0, 0xE1D3FA, 0xA58CEB].map(rgb),
                    night: [0x1A1033, 0x2A1A52, 0x120A26, 0x34206B].map(rgb),
                    outgoingDay: rgb(0xE9DEFF), outgoingNight: rgb(0x6A43D1)),
        MTChatTheme(emoji: "🌷", name: "Tulip", day: [0xF6C3CF, 0xEE8FA8, 0xFADCE3, 0xE9A1B4].map(rgb),
                    night: [0x2B0F1A, 0x42182A, 0x1F0A12, 0x521F35].map(rgb),
                    outgoingDay: rgb(0xFFE0E8), outgoingNight: rgb(0xC23D6C)),
        MTChatTheme(emoji: "🎄", name: "Christmas Tree", day: [0xBFE3C0, 0x6FB57A, 0xD9F0C9, 0x8CC98A].map(rgb),
                    night: [0x0B1F12, 0x12301C, 0x07160C, 0x1A3F25].map(rgb),
                    outgoingDay: rgb(0xD9F7CF), outgoingNight: rgb(0x2E8A4B)),
    ]

    /// The theme the chat uses now; bubble colors read it when they resolve.
    static var current = 0
}

/// The theme picker sheet.
final class MTThemeSheet: UIView {
    var onPreview: ((Int) -> Void)?
    var onNight: ((Bool) -> Void)?
    var onCancel: (() -> Void)?
    var onApply: (() -> Void)?

    private let dim = UIView()
    private let sheet = UIView()
    private let scroll = UIScrollView()
    private var tiles: [UIView] = []
    private let nightButton = UIButton(type: .system)
    private var selected: Int
    private var night: Bool
    private let sheetHeight: CGFloat

    init(in host: UIView, selected: Int, night: Bool) {
        self.selected = selected
        self.night = night
        sheetHeight = 250 + host.safeAreaInsets.bottom
        super.init(frame: host.bounds)
        host.addSubview(self)
        dim.frame = bounds
        dim.backgroundColor = UIColor(white: 0, alpha: 0.2)
        dim.alpha = 0
        dim.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(cancel)))
        addSubview(dim)
        sheet.frame = CGRect(x: 0, y: bounds.height, width: bounds.width, height: sheetHeight + 30)
        sheet.layer.cornerRadius = 16
        sheet.layer.cornerCurve = .continuous
        sheet.clipsToBounds = true
        let blur = MTViews.barBackground()
        blur.frame = sheet.bounds
        sheet.addSubview(blur)
        addSubview(sheet)

        let title = MTViews.label("Chat Theme", size: 17, weight: .semibold)
        title.textAlignment = .center
        title.frame = CGRect(x: 60, y: 14, width: bounds.width - 120, height: 22)
        sheet.addSubview(title)
        nightButton.frame = CGRect(x: 10, y: 6, width: 44, height: 40)
        nightButton.tintColor = MTPalette.accent
        setNightIcon(animated: false)
        nightButton.addAction(UIAction { [weak self] _ in self?.toggleNight() }, for: .touchUpInside)
        sheet.addSubview(nightButton)
        let close = MTViews.iconButton("xmark.circle.fill", size: 22, tint: MTPalette.secondary)
        close.frame = CGRect(x: bounds.width - 52, y: 6, width: 44, height: 40)
        close.addAction(UIAction { [weak self] _ in self?.cancel() }, for: .touchUpInside)
        sheet.addSubview(close)

        scroll.frame = CGRect(x: 0, y: 50, width: bounds.width, height: 120)
        scroll.showsHorizontalScrollIndicator = false
        sheet.addSubview(scroll)
        for (index, theme) in MTChatTheme.all.enumerated() {
            let tile = makeTile(theme)
            tile.frame = CGRect(x: 14 + CGFloat(index) * 86, y: 8, width: 76, height: 104)
            tile.tag = index
            tile.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tileTapped(_:))))
            scroll.addSubview(tile)
            tiles.append(tile)
        }
        scroll.contentSize = CGSize(width: 28 + CGFloat(tiles.count) * 86, height: 120)
        updateSelection(animated: false)

        let apply = UIButton(type: .system)
        apply.frame = CGRect(x: 16, y: 180, width: bounds.width - 32, height: 50)
        apply.backgroundColor = MTPalette.accent
        apply.layer.cornerRadius = 12
        apply.setTitle("Apply Theme", for: .normal)
        apply.setTitleColor(.white, for: .normal)
        apply.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        apply.addAction(UIAction { [weak self] _ in
            self?.onApply?()
            self?.dismiss()
        }, for: .touchUpInside)
        sheet.addSubview(apply)

        UIView.animate(withDuration: 0.3) { self.dim.alpha = 1 }
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
            self.sheet.frame.origin.y = self.bounds.height - self.sheetHeight
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// A tiny chat: the theme's gradient, two bubbles and its emoji.
    private func makeTile(_ theme: MTChatTheme) -> UIView {
        let tile = UIView()
        tile.layer.cornerRadius = 12
        tile.layer.cornerCurve = .continuous
        tile.clipsToBounds = true
        let gradient = CAGradientLayer()
        gradient.frame = CGRect(x: 0, y: 0, width: 76, height: 104)
        gradient.colors = theme.day.map(\.cgColor)
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)
        gradient.name = "gradient"
        tile.layer.addSublayer(gradient)
        let incoming = UIView(frame: CGRect(x: 8, y: 14, width: 44, height: 14))
        incoming.backgroundColor = .white
        incoming.layer.cornerRadius = 7
        incoming.tag = 101
        tile.addSubview(incoming)
        let outgoing = UIView(frame: CGRect(x: 24, y: 34, width: 44, height: 14))
        outgoing.backgroundColor = theme.outgoingDay
        outgoing.layer.cornerRadius = 7
        outgoing.tag = 102
        tile.addSubview(outgoing)
        let emoji = MTViews.label(theme.emoji, size: 30)
        emoji.textAlignment = .center
        emoji.frame = CGRect(x: 0, y: 56, width: 76, height: 40)
        tile.addSubview(emoji)
        return tile
    }

    private func updateSelection(animated: Bool) {
        for (index, tile) in tiles.enumerated() {
            let on = index == selected
            tile.layer.borderWidth = on ? 3 : 0
            tile.layer.borderColor = MTPalette.accent.cgColor
            let theme = MTChatTheme.all[index]
            (tile.layer.sublayers?.first { $0.name == "gradient" } as? CAGradientLayer)?.colors =
                (night ? theme.night : theme.day).map(\.cgColor)
            tile.viewWithTag(101)?.backgroundColor = night ? UIColor(white: 0.2, alpha: 1) : .white
            tile.viewWithTag(102)?.backgroundColor = night ? theme.outgoingNight : theme.outgoingDay
            if animated, on { MTViews.pop(tile, scale: 0.9) }
        }
    }

    private func setNightIcon(animated: Bool) {
        let image = UIImage(systemName: night ? "sun.max.fill" : "moon.stars.fill",
                            withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold))!
        if animated, let view = nightButton.imageView {
            view.setContactSymbol(image, transition: .offUp)
        }
        nightButton.setImage(image, for: .normal)
    }

    @objc private func tileTapped(_ gesture: UITapGestureRecognizer) {
        guard let index = gesture.view?.tag, index != selected else { return }
        selected = index
        UISelectionFeedbackGenerator().selectionChanged()
        updateSelection(animated: true)
        onPreview?(index)
    }

    private func toggleNight() {
        night.toggle()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        setNightIcon(animated: true)
        UIView.animate(withDuration: 0.4) { self.updateSelection(animated: false) }
        onNight?(night)
    }

    @objc private func cancel() {
        onCancel?()
        dismiss()
    }

    private func dismiss() {
        isUserInteractionEnabled = false
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseIn, animations: {
            self.sheet.frame.origin.y = self.bounds.height
            self.dim.alpha = 0
        }, completion: { _ in self.removeFromSuperview() })
    }
}
