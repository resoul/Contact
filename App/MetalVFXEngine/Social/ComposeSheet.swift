//
//  ComposeSheet.swift
//  controller
//
//  The composer pouring out of the round "write" button (or a reply button): the button's circle is
//  liquid (LiquidCanvasView), and its four edges spring out to the full sheet at different speeds, so
//  it stretches like jelly on the way. Closing pours it back into where it came from. Inside: the
//  text, the liquid character ring, and characters past the limit marked in red.
//

import UIKit

final class ComposeSheet: UIView, UITextViewDelegate {
    /// Called once the sheet has poured back; `text` is nil when cancelled.
    var onClose: ((String?) -> Void)?

    private let canvas = LiquidCanvasView()
    private let dim = UIView()
    private let content = UIView()
    private let textView = UITextView()
    private let placeholder = UILabel()
    private let postButton = UIButton(type: .system)
    private let ring = CharacterRingView()
    private let source: CGRect
    private var target: CGRect = .zero
    private var top, bottom, left, right, corner: Spring1D
    private var open = true
    private var clock: CFTimeInterval = 0
    private var shownContent = false
    private var result: String?
    private var finished = false

    /// Pours out of `source` (a rect in `host`) into a sheet over `host`.
    init(in host: UIView, from source: CGRect, author: ChannelPerson, replyingTo handle: String?) {
        self.source = source
        top = Spring1D(source.minY, stiffness: 15, dampingRatio: 0.66)
        bottom = Spring1D(source.maxY, stiffness: 12.5, dampingRatio: 0.62)
        left = Spring1D(source.minX, stiffness: 13, dampingRatio: 0.62)
        right = Spring1D(source.maxX, stiffness: 16, dampingRatio: 0.66)
        corner = Spring1D(source.height / 2, stiffness: 13, dampingRatio: 0.8)
        super.init(frame: host.bounds)
        host.addSubview(self)
        let safe = host.safeAreaInsets
        target = CGRect(x: 0, y: safe.top + 6, width: bounds.width, height: bounds.height - safe.top - 6)

        dim.frame = bounds
        dim.backgroundColor = UIColor(white: 0, alpha: 0.5)
        dim.alpha = 0
        addSubview(dim)
        canvas.frame = bounds
        canvas.liquidColor = TimelinePalette.panel
        canvas.gloss = 0.3
        canvas.rimWidth = 10
        canvas.onUpdate = { [weak self] dt in self?.step(dt) }
        addSubview(canvas)
        content.frame = target
        content.alpha = 0
        addSubview(content)
        build(author: author, replyingTo: handle)
        UIView.animate(withDuration: 0.3) { self.dim.alpha = 1 }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build(author: ChannelPerson, replyingTo handle: String?) {
        let cancel = UIButton(type: .system)
        cancel.setTitle("Отмена", for: .normal)
        cancel.titleLabel?.font = .systemFont(ofSize: 16)
        cancel.tintColor = .white
        cancel.addAction(UIAction { [weak self] _ in self?.close(posting: false) }, for: .touchUpInside)

        var config = UIButton.Configuration.filled()
        config.title = handle == nil ? "Опубликовать" : "Ответить"
        config.cornerStyle = .capsule
        config.baseBackgroundColor = TimelinePalette.accent
        config.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16)
        postButton.configuration = config
        postButton.isEnabled = false
        postButton.addAction(UIAction { [weak self] _ in self?.close(posting: true) }, for: .touchUpInside)

        let avatar = UIImageView(image: ChannelAvatar.image(for: author, size: 40))
        let replying = UILabel()
        if let handle {
            let text = NSMutableAttributedString(string: "Ответ ", attributes: [.foregroundColor: TimelinePalette.secondary])
            text.append(NSAttributedString(string: "@\(handle)", attributes: [.foregroundColor: TimelinePalette.accent]))
            replying.attributedText = text
            replying.font = .systemFont(ofSize: 14)
        }
        textView.backgroundColor = .clear
        textView.textColor = .white
        textView.font = .systemFont(ofSize: 19)
        textView.tintColor = TimelinePalette.accent
        textView.delegate = self
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.keyboardAppearance = .dark
        placeholder.text = handle == nil ? "Что происходит?" : "Напишите ответ"
        placeholder.font = .systemFont(ofSize: 19)
        placeholder.textColor = TimelinePalette.secondary

        let tools = UIStackView(arrangedSubviews: ["photo", "gift", "list.bullet", "location"].map { symbol in
            let icon = UIImageView(image: UIImage(systemName: symbol))
            icon.tintColor = TimelinePalette.accent
            icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 17)
            return icon
        })
        tools.spacing = 22
        let separator = UIView()
        separator.backgroundColor = TimelinePalette.separator

        for view in [cancel, postButton, avatar, replying, textView, placeholder, tools, ring, separator] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            cancel.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            cancel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            postButton.centerYAnchor.constraint(equalTo: cancel.centerYAnchor),
            postButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            replying.topAnchor.constraint(equalTo: cancel.bottomAnchor, constant: 14),
            replying.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 66),
            avatar.topAnchor.constraint(equalTo: replying.bottomAnchor, constant: 8),
            avatar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            avatar.widthAnchor.constraint(equalToConstant: 40),
            avatar.heightAnchor.constraint(equalToConstant: 40),
            textView.topAnchor.constraint(equalTo: avatar.topAnchor, constant: 8),
            textView.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 10),
            textView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            textView.bottomAnchor.constraint(equalTo: separator.topAnchor, constant: -10),
            placeholder.topAnchor.constraint(equalTo: textView.topAnchor),
            placeholder.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            separator.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),
            separator.bottomAnchor.constraint(equalTo: tools.topAnchor, constant: -12),
            tools.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            tools.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor, constant: -14),
            ring.centerYAnchor.constraint(equalTo: tools.centerYAnchor, constant: 13),
            ring.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            ring.widthAnchor.constraint(equalToConstant: 44),
            ring.heightAnchor.constraint(equalToConstant: 70),
        ])
    }

    // MARK: Text

    func textViewDidChange(_ textView: UITextView) {
        let count = textView.text.count
        placeholder.isHidden = count > 0
        ring.setCount(count)
        postButton.isEnabled = count > 0 && count <= ring.limit
        // Characters past the limit get a red wash, like on X.
        let selection = textView.selectedRange
        let attributed = NSMutableAttributedString(string: textView.text,
                                                   attributes: [.font: UIFont.systemFont(ofSize: 19), .foregroundColor: UIColor.white])
        if count > ring.limit {
            let start = String(textView.text.prefix(ring.limit)).utf16.count
            attributed.addAttribute(.backgroundColor, value: UIColor(red: 0.96, green: 0.13, blue: 0.18, alpha: 0.35),
                                    range: NSRange(location: start, length: textView.text.utf16.count - start))
        }
        textView.attributedText = attributed
        textView.selectedRange = selection
    }

    // MARK: Pouring

    private func close(posting: Bool) {
        guard open else { return }
        open = false
        clock = 0
        result = posting ? textView.text : nil
        textView.resignFirstResponder()
        UIView.animate(withDuration: 0.18) { self.content.alpha = 0 }
        UIView.animate(withDuration: 0.4, delay: 0.15) { self.dim.alpha = 0 }
        UIImpactFeedbackGenerator(style: posting ? .medium : .soft).impactOccurred()
        canvas.isPaused = false
    }

    private func step(_ dt: CFTimeInterval) {
        clock += dt
        let goal = open ? target : source
        if open || clock > 0.12 {
            top.step(toward: goal.minY, deltaTime: dt)
            bottom.step(toward: goal.maxY, deltaTime: dt)
            left.step(toward: goal.minX, deltaTime: dt)
            right.step(toward: goal.maxX, deltaTime: dt)
            corner.step(toward: open ? 30 : source.height / 2, deltaTime: dt)
        }
        let rect = CGRect(x: left.value, y: top.value, width: max(right.value - left.value, 1),
                          height: max(bottom.value - top.value, 1))
        canvas.shapes = [IslandFluidShape(center: rect.center, halfSize: CGSize(width: rect.width / 2, height: rect.height / 2),
                                          cornerRadius: corner.value, blend: 0)]
        let remaining = max(abs(top.value - goal.minY), abs(bottom.value - goal.maxY), abs(left.value - goal.minX),
                            abs(right.value - goal.maxX))
        if open, !shownContent, clock > 0.2, remaining < 40 {
            shownContent = true
            UIView.animate(withDuration: 0.25) { self.content.alpha = 1 }
            textView.becomeFirstResponder()
        }
        if open, shownContent, remaining < 0.3, top.isSettled(at: goal.minY, tolerance: 0.3) {
            canvas.renderFrame()
            canvas.isPaused = true
        }
        if !open, !finished, clock > 0.3, remaining < 6 {
            // Back in the button's shape: melt into the real button.
            finished = true
            UIView.animate(withDuration: 0.15) {
                self.canvas.alpha = 0
            } completion: { _ in
                self.canvas.isPaused = true
                self.onClose?(self.result)
                self.removeFromSuperview()
            }
        }
    }
}
