//
//  MTInputBar.swift
//  controller
//
//  The Mini-Telegram composer. From the bottom up: the field (grows smoothly line by line, up to
//  five), the reply / edit strip, a link preview card that drops onto the bar when a link is
//  typed, and sticker suggestions when the text is a single emoji. The 😊 button swaps the
//  keyboard for the emoji panel at the same height. Near the length limit a counter appears over
//  the send button; past it the field shakes instead of sending.
//

import UIKit

final class MTInputBar: UIView, UITextViewDelegate {
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
            self.fieldBox.layer.borderColor = MTPalette.separator.resolvedColor(with: self.traitCollection).cgColor
    }

    var onSend: ((String) -> Void)?
    var onSticker: ((String, UIImageView) -> Void)?
    var onAttach: (() -> Void)?
    var onModeToggle: ((Bool) -> Void)?
    var onHold: ((UILongPressGestureRecognizer) -> Void)?
    var onPanelClose: (() -> Void)?
    private(set) var videoMode = false
    /// The preview on the bar, if the link was not dismissed: it goes with the message.
    private(set) var linkPreview: MTLinkPreview?

    static let limit = 200

    private let background = MTViews.barBackground()
    private let attach = MTViews.iconButton("paperclip", size: 21, tint: MTPalette.secondary)
    private let fieldBox = UIView()
    private let textView = UITextView()
    private let placeholder = MTViews.label("Message", size: 16, color: MTPalette.secondary)
    private let emojiButton = UIButton(type: .system)
    private let action = UIImageView()
    private let actionTap = UIButton(type: .custom)
    private let counter = MTViews.label(size: 13, weight: .semibold, color: MTPalette.secondary)

    /// The reply / edit strip above the field.
    private let panel = UIView()
    private let panelIcon = UIImageView()
    private let panelBar = UIView()
    private let panelTitle = MTViews.label(size: 14, weight: .semibold, color: MTPalette.accent)
    private let panelText = MTViews.label(size: 14)
    private let panelClose = MTViews.iconButton("xmark", size: 15, tint: MTPalette.secondary)
    private var panelShown = false
    private var editing = false

    private var linkCard: UIView?
    private var dismissedLink: String?
    private let stickers = MTStickerStrip()
    private var stickersShown = false

    private var emojiPanel: MTEmojiPanel?
    private var keyboardHeight: CGFloat = 336
    private var textHeight: CGFloat = 36
    private var wasOverLimit = false

    private static let panelHeight: CGFloat = 46
    private static let linkHeight: CGFloat = MTLinkView.height + 10
    private static let maxTextHeight: CGFloat = 118

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
        addSubview(background)

        stickers.alpha = 0
        stickers.onPick = { [weak self] sticker, cell in
            guard let self else { return }
            self.onSticker?(sticker, cell)
            self.clearText()
        }
        addSubview(stickers)

        panel.alpha = 0
        panelIcon.tintColor = MTPalette.accent
        panelIcon.contentMode = .center
        panelBar.backgroundColor = MTPalette.accent
        panelBar.layer.cornerRadius = 1.5
        for view in [panelIcon, panelBar, panelTitle, panelText, panelClose] { panel.addSubview(view) }
        panelClose.addAction(UIAction { [weak self] _ in self?.onPanelClose?() }, for: .touchUpInside)
        addSubview(panel)

        attach.addAction(UIAction { [weak self] _ in self?.onAttach?() }, for: .touchUpInside)
        addSubview(attach)
        fieldBox.backgroundColor = MTPalette.background
        fieldBox.layer.cornerRadius = 18
        fieldBox.layer.cornerCurve = .continuous
        fieldBox.layer.borderWidth = 0.5
        fieldBox.layer.borderColor = MTPalette.separator.cgColor
        addSubview(fieldBox)
        textView.accessibilityIdentifier = "contact.composer"
        textView.accessibilityLabel = "Message"
        actionTap.accessibilityIdentifier = "contact.send"
        actionTap.accessibilityLabel = "Voice message"
        textView.font = .systemFont(ofSize: 16)
        textView.textColor = MTPalette.text
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 9, bottom: 8, right: 34)
        textView.delegate = self
        textView.showsVerticalScrollIndicator = false
        fieldBox.addSubview(textView)
        fieldBox.addSubview(placeholder)
        emojiButton.tintColor = MTPalette.secondary
        setEmojiIcon(keyboard: false, animated: false)
        emojiButton.addAction(UIAction { [weak self] _ in self?.toggleEmoji() }, for: .touchUpInside)
        fieldBox.addSubview(emojiButton)

        action.image = UIImage(systemName: "mic", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .regular))
        action.tintColor = MTPalette.secondary
        action.contentMode = .center
        addSubview(action)
        addSubview(actionTap)
        actionTap.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        hold.minimumPressDuration = 0.18
        hold.allowableMovement = 400
        actionTap.addGestureRecognizer(hold)
        counter.textAlignment = .center
        counter.alpha = 0
        addSubview(counter)


        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChange(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Layout

    var includesBottomSafeArea = true

    private var stickersHeight: CGFloat { stickersShown ? MTStickerStrip.height : 0 }
    private var linkHeight: CGFloat { linkCard != nil ? Self.linkHeight : 0 }
    private var panelHeight: CGFloat { panelShown ? Self.panelHeight : 0 }
    private var rowTop: CGFloat { stickersHeight + linkHeight + panelHeight }
    private var rowHeight: CGFloat { textHeight + 16 }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: rowTop + rowHeight
                + (includesBottomSafeArea ? (window?.safeAreaInsets.bottom ?? 0) : 0) * (textView.isFirstResponder ? 0 : 1))
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        invalidateIntrinsicContentSize()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        background.frame = CGRect(x: 0, y: 0, width: width, height: bounds.height + 40)
        stickers.frame = CGRect(x: 0, y: 0, width: width, height: MTStickerStrip.height)
        linkCard?.frame = CGRect(x: 12, y: stickersHeight + 6, width: width - 24, height: MTLinkView.height)
        panel.frame = CGRect(x: 0, y: stickersHeight + linkHeight, width: width, height: Self.panelHeight)
        panelIcon.frame = CGRect(x: 6, y: 0, width: 40, height: Self.panelHeight)
        panelBar.frame = CGRect(x: 50, y: 8, width: 3, height: Self.panelHeight - 16)
        panelTitle.frame = CGRect(x: 60, y: 6, width: width - 110, height: 17)
        panelText.frame = CGRect(x: 60, y: 23, width: width - 110, height: 17)
        panelClose.frame = CGRect(x: width - 46, y: 1, width: 44, height: 44)

        let bottom = rowTop + rowHeight
        attach.frame = CGRect(x: 4, y: bottom - 48, width: 44, height: 44)
        fieldBox.frame = CGRect(x: 50, y: rowTop + 8, width: width - 100, height: textHeight)
        textView.frame = fieldBox.bounds
        placeholder.frame = CGRect(x: 14, y: 0, width: fieldBox.bounds.width - 50, height: 36)
        emojiButton.frame = CGRect(x: fieldBox.bounds.width - 36, y: fieldBox.bounds.height - 36, width: 34, height: 36)
        action.frame = CGRect(x: width - 48, y: bottom - 48, width: 44, height: 44)
        actionTap.frame = action.frame.insetBy(dx: -4, dy: -4)
        counter.frame = CGRect(x: action.frame.midX - 30, y: action.frame.minY - 20, width: 60, height: 18)
    }

    var actionCenter: CGPoint { action.center }

    /// The field's box, where a sent message starts its flight.
    func fieldFrame(in view: UIView) -> CGRect {
        fieldBox.convert(fieldBox.bounds, to: view)
    }

    /// Re-measures, then animates the bar to its new height together with `changes`.
    private func animateLayout(_ changes: @escaping () -> Void = {}) {
        invalidateIntrinsicContentSize()
        UIView.animate(withDuration: 0.38, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0) {
            changes()
            self.layoutIfNeeded()
            self.superview?.layoutIfNeeded()
        }
    }

    // MARK: Text

    private var text: String { textView.text ?? "" }
    private var hasText: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var overLimit: Bool { text.count > Self.limit }

    func textViewDidChange(_ textView: UITextView) {
        textChanged()
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        invalidateIntrinsicContentSize()
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        if textView.inputView != nil {
            textView.inputView = nil
            setEmojiIcon(keyboard: false, animated: true)
        }
        invalidateIntrinsicContentSize()
    }

    private func textChanged() {
        placeholder.isHidden = !text.isEmpty
        updateAction()
        updateCounter()
        var relayout = false

        // The field grows line by line, then scrolls inside.
        let fitting = textView.sizeThatFits(CGSize(width: max(fieldBox.bounds.width, 100), height: .greatestFiniteMagnitude)).height
        let newHeight = min(max(36, ceil(fitting)), Self.maxTextHeight)
        textView.isScrollEnabled = fitting > Self.maxTextHeight
        if newHeight != textHeight {
            textHeight = newHeight
            relayout = true
        }

        // A link drops in as a card; deleting it (or ✕) takes the card away.
        let preview = MTLinkPreview.detect(in: text).flatMap { $0.url == dismissedLink ? nil : $0 }
        if preview != linkPreview {
            linkPreview = preview
            removeLinkCard()
            if let preview { addLinkCard(preview) }
            relayout = true
        }

        // A single emoji suggests stickers.
        if let suggestions = MTStickers.suggestions(for: text) {
            if !stickersShown {
                stickersShown = true
                relayout = true
            }
            stickers.show(suggestions)
        } else if stickersShown {
            stickersShown = false
            stickers.clear()
            relayout = true
        }

        if relayout {
            let stickersVisible = stickersShown
            animateLayout { self.stickers.alpha = stickersVisible ? 1 : 0 }
        }
        if textView.isScrollEnabled {
            textView.scrollRangeToVisible(textView.selectedRange)
        }
    }

    private func clearText() {
        textView.text = ""
        dismissedLink = nil
        textChanged()
    }

    private func addLinkCard(_ preview: MTLinkPreview) {
        let card = MTLinkView(preview)
        card.backgroundColor = MTPalette.fill
        let close = MTViews.iconButton("xmark", size: 12, tint: MTPalette.secondary)
        close.frame = CGRect(x: 0, y: 0, width: 28, height: 28)
        close.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.dismissedLink = self.linkPreview?.url
            self.textChanged()
        }, for: .touchUpInside)
        card.addSubview(close)
        close.autoresizingMask = [.flexibleLeftMargin]
        card.frame = CGRect(x: 12, y: stickersHeight + 6, width: bounds.width - 24, height: MTLinkView.height)
        close.frame.origin = CGPoint(x: card.bounds.width - 30, y: 2)
        insertSubview(card, aboveSubview: background)
        linkCard = card
        // It falls onto the bar with a little tilt and settles.
        card.alpha = 0
        card.transform = CGAffineTransform(translationX: 0, y: -60).rotated(by: -0.08)
        UIView.animate(withDuration: 0.6, delay: 0.05, usingSpringWithDamping: 0.55, initialSpringVelocity: 0.3) {
            card.alpha = 1
            card.transform = .identity
        }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    private func removeLinkCard() {
        guard let card = linkCard else { return }
        linkCard = nil
        UIView.animate(withDuration: 0.3, animations: {
            card.alpha = 0
            card.transform = CGAffineTransform(translationX: 0, y: -40).rotated(by: 0.06)
        }, completion: { _ in card.removeFromSuperview() })
    }

    // MARK: Counter

    private func updateCounter() {
        let left = Self.limit - text.count
        let shown = left <= 30
        counter.text = "\(left)"
        counter.textColor = left < 0 ? MTPalette.red : MTPalette.secondary
        if shown != (counter.alpha > 0.5) {
            UIView.animate(withDuration: 0.25) { self.counter.alpha = shown ? 1 : 0 }
            if shown { MTViews.pop(counter, scale: 0.5) }
        }
        // Crossing the limit: the field shakes once.
        if overLimit, !wasOverLimit { shake() }
        wasOverLimit = overLimit
    }

    private func shake() {
        let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shake.values = [0, -11, 10, -8, 6, -3, 0]
        shake.duration = 0.42
        fieldBox.layer.add(shake, forKey: "shake")
        MTViews.pop(counter, scale: 1.5)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    // MARK: Action button

    private func updateAction() {
        actionTap.accessibilityLabel = hasText ? (editing ? "Save" : "Send") : (videoMode ? "Video message" : "Voice message")
        let symbol = hasText ? (overLimit ? "exclamationmark.circle.fill" : (editing ? "checkmark.circle.fill" : "arrow.up.circle.fill"))
            : (videoMode ? "video" : "mic")
        let image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: hasText ? 30 : 22, weight: .regular))!
        let tint = hasText ? (overLimit ? MTPalette.red : MTPalette.accent) : MTPalette.secondary
        action.tintColor = tint
        guard action.image != image else { return }
        action.setContactSymbol(image, transition: .downUp)
    }

    @objc private func actionTapped() {
        if hasText {
            guard !overLimit else {
                shake()
                return
            }
            onSend?(text)
            clearText()
            return
        }
        videoMode.toggle()
        UISelectionFeedbackGenerator().selectionChanged()
        updateAction()
        onModeToggle?(videoMode)
    }

    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        guard !hasText else { return }
        onHold?(gesture)
    }

    func setRecording(_ recording: Bool) {
        UIView.animate(withDuration: 0.2) {
            self.attach.alpha = recording ? 0 : 1
            self.fieldBox.alpha = recording ? 0 : 1
            self.action.alpha = recording ? 0 : 1
        }
    }

    // MARK: Emoji panel

    private func setEmojiIcon(keyboard: Bool, animated: Bool) {
        let image = UIImage(systemName: keyboard ? "keyboard" : "face.smiling",
                            withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .regular))!
        guard animated, let imageView = emojiButton.imageView else {
            emojiButton.setImage(image, for: .normal)
            return
        }
        imageView.setContactSymbol(image, transition: .offUp)
        emojiButton.setImage(image, for: .normal)
    }

    /// Swaps keyboard ⇄ emoji panel; the panel takes the keyboard's height so nothing jumps.
    private func toggleEmoji() {
        UISelectionFeedbackGenerator().selectionChanged()
        if textView.inputView == nil {
            let bottom = window?.safeAreaInsets.bottom ?? 0
            let panel = emojiPanel ?? MTEmojiPanel(height: keyboardHeight - bottom)
            panel.onEmoji = { [weak self] emoji in
                self?.textView.insertText(emoji)
                self?.textChanged()
            }
            panel.onDelete = { [weak self] in
                self?.textView.deleteBackward()
                self?.textChanged()
            }
            emojiPanel = panel
            textView.inputView = panel
            setEmojiIcon(keyboard: true, animated: true)
        } else {
            textView.inputView = nil
            setEmojiIcon(keyboard: false, animated: true)
        }
        if textView.isFirstResponder {
            textView.reloadInputViews()
        } else {
            textView.becomeFirstResponder()
        }
    }

    @objc private func keyboardWillChange(_ notification: Notification) {
        guard textView.inputView == nil,
              let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              frame.height > 200 else { return }
        keyboardHeight = frame.height
    }

    // MARK: Modes

    func focus() {
        textView.becomeFirstResponder()
    }

    func setText(_ text: String, editing: Bool) {
        self.editing = editing
        textView.text = text
        textChanged()
        if editing { focus() }
    }

    /// The strip slides out of the bar's top edge; the bar grows to make room.
    func showPanel(symbol: String, title: String, text: String) {
        panelIcon.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold))
        panelTitle.text = title
        panelText.text = text
        let wasShown = panelShown
        panelShown = true
        panel.transform = wasShown ? .identity : CGAffineTransform(translationX: 0, y: 24)
        animateLayout {
            self.panel.alpha = 1
            self.panel.transform = .identity
        }
        if wasShown { MTViews.pop(panelIcon, scale: 0.6) }
    }

    func hidePanel() {
        guard panelShown else { return }
        panelShown = false
        animateLayout {
            self.panel.alpha = 0
            self.panel.transform = CGAffineTransform(translationX: 0, y: 24)
        }
    }
}
