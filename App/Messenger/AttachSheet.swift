//
//  AttachSheet.swift
//  controller
//
//  The attach menu: a sheet with the gallery, tabs at the bottom on a liquid indicator, numbered
//  selection that renumbers itself, and a caption + send bar that rises in place of the tabs once
//  something is selected.
//

import UIKit

final class AttachSheet: UIView {
    var onSend: (([DemoPhotos.Scene]) -> Void)?

    private let dim = UIView()
    private let sheet = UIView()
    private let grabber = UIView()
    private let title = Views.label("Gallery", size: 17, weight: .semibold)
    private let closeButton = Views.iconButton("xmark.circle.fill", size: 22, tint: Palette.secondary)
    private let grid = UIScrollView()
    private let placeholder = UIView()
    private let placeholderIcon = UIImageView()
    private let placeholderText = Views.label(size: 15, color: Palette.secondary)
    private let tabs = LiquidSelector(symbols: ["photo.on.rectangle", "doc", "location", "chart.bar.xaxis", "person.crop.circle"],
                                      style: .tabs, liquid: Palette.accent, selectedTint: .white, normalTint: Palette.secondary)
    private let tabTitles = ["Gallery", "File", "Location", "Poll", "Contact"]
    private var tabLabels: [UILabel] = []
    private let sendBar = UIView()
    private let caption = UITextField()
    private let sendButton = UIButton(type: .system)
    private let sendCount = Badge()

    private var cells: [UIImageView] = []
    private var marks: [UILabel] = []
    private var scenes: [DemoPhotos.Scene] = []
    private var selection: [Int] = []
    private var sheetHeight: CGFloat = 0

    init(in host: UIView) {
        super.init(frame: host.bounds)
        host.addSubview(self)
        dim.frame = bounds
        dim.backgroundColor = UIColor(white: 0, alpha: 0.35)
        dim.alpha = 0
        dim.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(close)))
        addSubview(dim)

        sheetHeight = bounds.height * 0.64
        sheet.frame = CGRect(x: 0, y: bounds.height, width: bounds.width, height: sheetHeight + 40)
        sheet.backgroundColor = Palette.cell
        sheet.layer.cornerRadius = 16
        sheet.layer.cornerCurve = .continuous
        addSubview(sheet)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(dragged(_:)))
        sheet.addGestureRecognizer(pan)

        grabber.backgroundColor = Palette.muted
        grabber.layer.cornerRadius = 2.5
        grabber.frame = CGRect(x: (bounds.width - 36) / 2, y: 6, width: 36, height: 5)
        sheet.addSubview(grabber)
        title.frame = CGRect(x: 16, y: 16, width: 200, height: 24)
        sheet.addSubview(title)
        closeButton.frame = CGRect(x: bounds.width - 48, y: 10, width: 40, height: 36)
        closeButton.addAction(UIAction { [weak self] _ in self?.close() }, for: .touchUpInside)
        sheet.addSubview(closeButton)

        let bottom = host.safeAreaInsets.bottom
        let tabsHeight: CGFloat = 70 + bottom
        grid.frame = CGRect(x: 0, y: 50, width: bounds.width, height: sheetHeight - 50 - tabsHeight)
        grid.alwaysBounceVertical = true
        sheet.addSubview(grid)
        buildGrid()

        placeholder.frame = grid.frame
        placeholder.alpha = 0
        placeholderIcon.tintColor = Palette.accent
        placeholderIcon.contentMode = .center
        placeholderIcon.frame = CGRect(x: 0, y: placeholder.bounds.height / 2 - 70, width: bounds.width, height: 60)
        placeholder.addSubview(placeholderIcon)
        placeholderText.textAlignment = .center
        placeholderText.numberOfLines = 2
        placeholderText.frame = CGRect(x: 30, y: placeholder.bounds.height / 2 - 4, width: bounds.width - 60, height: 44)
        placeholder.addSubview(placeholderText)
        sheet.addSubview(placeholder)

        let tabsY = sheetHeight - tabsHeight
        tabs.frame = CGRect(x: 12, y: tabsY + 8, width: bounds.width - 24, height: 40)
        tabs.addTarget(self, action: #selector(tabChanged), for: .valueChanged)
        sheet.addSubview(tabs)
        let slot = tabs.bounds.width / CGFloat(tabTitles.count)
        for (index, text) in tabTitles.enumerated() {
            let label = Views.label(text, size: 10, weight: .medium, color: index == 0 ? Palette.accent : Palette.secondary)
            label.textAlignment = .center
            label.frame = CGRect(x: 12 + slot * CGFloat(index), y: tabsY + 50, width: slot, height: 13)
            sheet.addSubview(label)
            tabLabels.append(label)
        }

        sendBar.frame = CGRect(x: 0, y: tabsY, width: bounds.width, height: tabsHeight)
        sendBar.backgroundColor = Palette.cell
        sendBar.alpha = 0
        sendBar.transform = CGAffineTransform(translationX: 0, y: 40)
        sheet.addSubview(sendBar)
        let captionBox = UIView(frame: CGRect(x: 12, y: 10, width: bounds.width - 80, height: 38))
        captionBox.backgroundColor = Palette.fill
        captionBox.layer.cornerRadius = 19
        sendBar.addSubview(captionBox)
        caption.placeholder = "Add a caption…"
        caption.font = .systemFont(ofSize: 16)
        caption.textColor = Palette.text
        caption.frame = captionBox.bounds.insetBy(dx: 14, dy: 0)
        captionBox.addSubview(caption)
        sendButton.frame = CGRect(x: bounds.width - 58, y: 6, width: 46, height: 46)
        sendButton.backgroundColor = Palette.accent
        sendButton.layer.cornerRadius = 23
        sendButton.tintColor = .white
        sendButton.setImage(UIImage(systemName: "arrow.up", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)),
                            for: .normal)
        sendButton.addAction(UIAction { [weak self] _ in self?.send() }, for: .touchUpInside)
        sendBar.addSubview(sendButton)
        sendCount.frame = CGRect(x: bounds.width - 30, y: 0, width: 22, height: 22)
        sendCount.layer.borderWidth = 2
        sendCount.layer.borderColor = UIColor.white.cgColor
        sendBar.addSubview(sendCount)
        sendCount.set(0, animated: false)

        UIView.animate(withDuration: 0.3) { self.dim.alpha = 1 }
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
            self.sheet.frame.origin.y = self.bounds.height - self.sheetHeight
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildGrid() {
        let gap: CGFloat = 2
        let size = (bounds.width - gap * 2) / 3
        let all = DemoPhotos.Scene.allCases
        for index in 0..<24 {
            let cell = UIImageView()
            cell.frame = CGRect(x: CGFloat(index % 3) * (size + gap), y: CGFloat(index / 3) * (size + gap), width: size, height: size)
            cell.clipsToBounds = true
            cell.contentMode = .scaleAspectFill
            cell.isUserInteractionEnabled = true
            grid.addSubview(cell)
            if index == 0 {
                // The live camera tile.
                cell.backgroundColor = UIColor(white: 0.1, alpha: 1)
                let icon = UIImageView(image: UIImage(systemName: "camera.fill",
                                                      withConfiguration: UIImage.SymbolConfiguration(pointSize: 26)))
                icon.tintColor = .white
                icon.contentMode = .center
                icon.frame = cell.bounds
                cell.addSubview(icon)
                scenes.append(.sunset)
                cells.append(cell)
                marks.append(UILabel())
                continue
            }
            let scene = all[index % all.count]
            scenes.append(scene)
            cell.image = DemoPhotos.image(scene, size: CGSize(width: 260, height: 260), seed: UInt64(index * 3 + 1))
            cell.tag = index
            cell.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(photoTapped(_:))))
            let mark = UILabel()
            mark.frame = CGRect(x: size - 30, y: 6, width: 24, height: 24)
            mark.layer.cornerRadius = 12
            mark.layer.borderWidth = 1.5
            mark.layer.borderColor = UIColor.white.cgColor
            mark.backgroundColor = UIColor(white: 0, alpha: 0.15)
            mark.clipsToBounds = true
            mark.font = .systemFont(ofSize: 13, weight: .bold)
            mark.textColor = .white
            mark.textAlignment = .center
            cell.addSubview(mark)
            cells.append(cell)
            marks.append(mark)
        }
        grid.contentSize = CGSize(width: bounds.width, height: CGFloat(8) * (size + gap))
    }

    @objc private func photoTapped(_ gesture: UITapGestureRecognizer) {
        guard let index = gesture.view?.tag else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        if let position = selection.firstIndex(of: index) {
            selection.remove(at: position)
        } else {
            selection.append(index)
        }
        for (cellIndex, mark) in marks.enumerated() where cellIndex > 0 {
            let number = selection.firstIndex(of: cellIndex)
            let text = number.map { "\($0 + 1)" } ?? ""
            let changed = mark.text != text
            mark.text = text
            mark.backgroundColor = number == nil ? UIColor(white: 0, alpha: 0.15) : Palette.accent
            if changed, number != nil { Views.pop(mark, scale: 0.5) }
            let selected = number != nil
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0) {
                self.cells[cellIndex].transform = selected ? CGAffineTransform(scaleX: 0.9, y: 0.9) : .identity
            }
        }
        sendCount.set(selection.count, animated: true)
        let showSend = !selection.isEmpty
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
            self.sendBar.alpha = showSend ? 1 : 0
            self.sendBar.transform = showSend ? .identity : CGAffineTransform(translationX: 0, y: 40)
            self.tabs.alpha = showSend ? 0 : 1
            self.tabLabels.forEach { $0.alpha = showSend ? 0 : 1 }
        }
        title.text = showSend ? "Selected: \(selection.count)" : "Gallery"
    }

    @objc private func tabChanged() {
        let index = tabs.selectedIndex
        for (labelIndex, label) in tabLabels.enumerated() {
            label.textColor = labelIndex == index ? Palette.accent : Palette.secondary
        }
        title.text = tabTitles[index]
        let content: [(String, String)] = [("", ""), ("doc.fill", "Send a file up to 4 GB"),
                                           ("location.circle.fill", "Your location\nor live for 8 hours"),
                                           ("chart.bar.fill", "Poll or quiz\nwith answer choices"),
                                           ("person.crop.circle.fill", "Share a contact from your address book")]
        placeholderIcon.image = UIImage(systemName: content[index].0, withConfiguration: UIImage.SymbolConfiguration(pointSize: 46))
        placeholderText.text = content[index].1
        UIView.animate(withDuration: 0.25) {
            self.grid.alpha = index == 0 ? 1 : 0
            self.placeholder.alpha = index == 0 ? 0 : 1
        }
        if index != 0 { Views.pop(placeholderIcon, scale: 0.6) }
    }

    @objc private func dragged(_ gesture: UIPanGestureRecognizer) {
        let dy = gesture.translation(in: self).y
        let rest = bounds.height - sheetHeight
        switch gesture.state {
        case .changed:
            sheet.frame.origin.y = rest + (dy > 0 ? dy : dy * 0.2)
            dim.alpha = 1 - max(0, dy) / sheetHeight
        case .ended, .cancelled:
            if dy > 120 || gesture.velocity(in: self).y > 800 {
                close()
            } else {
                UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
                    self.sheet.frame.origin.y = rest
                    self.dim.alpha = 1
                }
            }
        default:
            break
        }
    }

    private func send() {
        let chosen = selection.map { scenes[$0] }
        close()
        onSend?(chosen)
    }

    @objc func close() {
        endEditing(true)
        isUserInteractionEnabled = false
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseIn, animations: {
            self.sheet.frame.origin.y = self.bounds.height
            self.dim.alpha = 0
        }, completion: { _ in self.removeFromSuperview() })
    }
}
