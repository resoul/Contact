import UIKit

/// The application notification has its own interaction states; the VFX toast
/// remains an independent reference demo.
///
/// One card from banner to conversation: the header (avatar, name, close) and the
/// simple reply field never leave it. Pulling down opens the seam between them and
/// reveals the preloaded chat history from its middle outwards, following the finger.
final class MessageNotificationView: IslandFluidView, UITextFieldDelegate, UIGestureRecognizerDelegate {
    var onSend: ((String, @escaping (Bool) -> Void) -> Void)?
    /// Asked once replying starts; the overlay attaches the history before completing.
    var onPrepareChat: ((@escaping (Bool) -> Void) -> Void)?
    var onExpandedChanged: ((Bool) -> Void)?
    var onOpenFullChat: ((String) -> Void)?
    var onDraftChanged: ((String) -> Void)?
    var onWillDismiss: (() -> Void)?
    var onFinish: (() -> Void)?

    private enum State: Equatable { case entering, banner, reply, sending, dismissing }
    private enum History { case none, loading, ready, failed }
    private var state = State.entering
    private var history = History.none
    private let content = UIView()
    private let historyClip = UIView()
    private weak var historyView: UIView?
    private let divider = UIView()
    private let dim = UIView()
    private let avatar = AvatarView()
    private let name = UIButton(type: .system)
    private let message = UILabel()
    private let field = UITextField()
    private let send = UIButton(type: .system)
    private let close = UIButton(type: .system)
    private let hint = UILabel()
    private let grabber = UIView()
    private let haptic = UIImpactFeedbackGenerator(style: .medium)
    private var centerSpring = IslandSpring(.zero, stiffness: 18, dampingRatio: 0.72)
    private var sizeSpring = IslandSpring(CGPoint(x: 7, y: 7), stiffness: 18, dampingRatio: 0.72)
    /// x is 0 for the reply card and 1 for the open conversation.
    private var expansionSpring = IslandSpring(.zero, stiffness: 15, dampingRatio: 0.86)
    private var expanded = false
    private var dragExpansion: CGFloat?
    private var dragStartExpansion: CGFloat = 0
    private var phaseTime: TimeInterval = 0
    private var drag: CGFloat = 0
    private var armed = false
    private var scaleBase = CGSize(width: 1, height: 1)
    private var expiry: DispatchWorkItem?
    private var keyboardTop = CGFloat.greatestFiniteMagnitude
    private let bannerHeight: CGFloat = 86
    private let replyHeight: CGFloat = 184

    var draft: String { field.text ?? "" }
    var acceptsUpdates: Bool { state != .dismissing }
    private var isReplying: Bool { state == .reply || state == .sending }
    private var expansion: CGFloat { min(max(dragExpansion ?? expansionSpring.position.x, 0), 1) }
    private var expansionSettled: Bool {
        dragExpansion == nil && abs(expansionSpring.position.x - (expanded ? 1 : 0)) < 0.001
            && abs(expansionSpring.velocity.dx) < 0.01
    }
    private var cardWidth: CGFloat { min(430, bounds.width - 28) }
    private var cardTop: CGFloat { max(island.maxY + 14, safeAreaInsets.top + 8) }
    private var chatHeight: CGFloat {
        let bottom = min(bounds.height - safeAreaInsets.bottom - 12, keyboardTop - 8)
        return max(replyHeight, bottom - cardTop)
    }
    private var cardHeight: CGFloat {
        isReplying ? replyHeight + (chatHeight - replyHeight) * expansion : bannerHeight
    }
    private var restingCenter: CGPoint { CGPoint(x: bounds.midX, y: cardTop + cardHeight / 2) }
    /// Header and composer sizes of the open conversation; the history gets the rest.
    private let chatHeaderHeight: CGFloat = 66
    private let chatComposerHeight: CGFloat = 62

    init(chat: Chat, text: String, draft: String) {
        super.init(frame: .zero)
        gloss = 0.4
        isUserInteractionEnabled = true
        accessibilityIdentifier = "contact.messageNotification"
        dim.backgroundColor = .black
        dim.alpha = 0
        addSubview(dim)
        content.backgroundColor = gpu == nil ? .black : .clear
        content.layer.cornerRadius = 28
        content.layer.cornerCurve = .continuous
        content.clipsToBounds = true
        addSubview(content)
        historyClip.clipsToBounds = true
        historyClip.alpha = 0
        divider.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        divider.alpha = 0
        for child in [historyClip, divider, avatar, name, message, field, send, close, hint, grabber] { content.addSubview(child) }
        avatar.set(chat.person, size: 40, peerID: chat.id)
        var nameConfiguration = UIButton.Configuration.plain()
        nameConfiguration.title = chat.person.name
        nameConfiguration.image = UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .semibold))
        nameConfiguration.imagePlacement = .trailing
        nameConfiguration.imagePadding = 5
        nameConfiguration.contentInsets = .zero
        nameConfiguration.baseForegroundColor = .white
        nameConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var result = attributes
            result.font = .systemFont(ofSize: 15, weight: .semibold)
            return result
        }
        name.configuration = nameConfiguration
        name.contentHorizontalAlignment = .leading
        name.titleLabel?.lineBreakMode = .byTruncatingTail
        name.accessibilityLabel = "Open full chat with \(chat.person.name)"
        name.addAction(UIAction { [weak self] _ in self?.openFullChat() }, for: .touchUpInside)
        message.text = text
        message.font = .systemFont(ofSize: 13)
        message.textColor = UIColor.white.withAlphaComponent(0.78)
        message.numberOfLines = 2
        field.text = draft
        field.accessibilityIdentifier = "contact.notificationReply"
        field.accessibilityLabel = "Reply"
        field.attributedPlaceholder = NSAttributedString(string: "Reply…", attributes: [.foregroundColor: UIColor.white.withAlphaComponent(0.5)])
        field.font = .systemFont(ofSize: 16)
        field.textColor = .white
        field.tintColor = .white
        field.backgroundColor = UIColor.white.withAlphaComponent(0.13)
        field.layer.cornerRadius = 20
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        field.leftViewMode = .always
        field.returnKeyType = .send
        field.enablesReturnKeyAutomatically = true
        field.delegate = self
        field.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        send.setImage(UIImage(systemName: "arrow.up.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 36)), for: .normal)
        send.tintColor = .white
        send.accessibilityLabel = "Send reply"
        send.addAction(UIAction { [weak self] _ in self?.sendReply() }, for: .touchUpInside)
        close.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)), for: .normal)
        close.tintColor = UIColor.white.withAlphaComponent(0.6)
        close.accessibilityLabel = "Dismiss notification"
        close.addAction(UIAction { [weak self] _ in self?.dismiss() }, for: .touchUpInside)
        hint.font = .systemFont(ofSize: 12, weight: .medium)
        hint.textColor = UIColor.white.withAlphaComponent(0.65)
        hint.textAlignment = .center
        grabber.backgroundColor = UIColor.white.withAlphaComponent(0.35)
        grabber.layer.cornerRadius = 2
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.delegate = self
        content.addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.delegate = self
        addGestureRecognizer(tap)
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Reply", target: self, selector: #selector(accessibleReply)),
            UIAccessibilityCustomAction(name: "Show conversation", target: self, selector: #selector(accessibleExpand)),
            UIAccessibilityCustomAction(name: "Open full chat", target: self, selector: #selector(accessibleOpenFull)),
        ]
        message.accessibilityCustomActions = accessibilityCustomActions
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        updateControls()
    }

    required init?(coder: NSCoder) { fatalError("Use init(chat:text:draft:)") }
    deinit { expiry?.cancel(); NotificationCenter.default.removeObserver(self) }

    func start() {
        layoutIfNeeded()
        centerSpring.position = islandMouth
        scaleBase = CGSize(width: cardWidth, height: bannerHeight)
        content.alpha = 0
        animateChange()
        scheduleExpiry()
        UIAccessibility.post(notification: .announcement, argument: "\(name.currentTitle ?? ""): \(message.text ?? "")")
    }

    func update(text: String) {
        message.text = text
        if state == .banner || state == .entering { scheduleExpiry() }
    }

    /// The chat's history-only view. It keeps the open conversation's size and is
    /// moved, never resized, while the seam opens.
    func attachHistory(_ view: UIView) {
        historyView?.removeFromSuperview()
        historyView = view
        historyClip.addSubview(view)
        history = .ready
        updateControls()
        layoutCard(height: content.bounds.height)
    }

    func dismiss(immediately: Bool = false) {
        if state == .dismissing {
            if immediately { finish() }
            return
        }
        expiry?.cancel()
        onDraftChanged?(draft)
        if expanded { expanded = false; onExpandedChanged?(false) }
        onWillDismiss?()
        state = .dismissing
        phaseTime = 0
        dragExpansion = nil
        scaleBase = content.bounds.size
        content.endEditing(true)
        UIView.animate(withDuration: 0.15) { self.dim.alpha = 0; self.content.alpha = 0 }
        if immediately || UIAccessibility.isReduceMotionEnabled || gpu == nil { finish() }
        else { isPaused = false }
    }

    private func finish() {
        expiry?.cancel()
        isPaused = true
        removeFromSuperview()
        let completed = onFinish
        onFinish = nil
        completed?()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        dim.frame = bounds
        animateChange()
    }

    /// Lays the card out for its current height. The header compacts and the field
    /// sinks to the bottom as `expansion` grows; the history fills the gap between.
    private func layoutCard(height h: CGFloat) {
        let w = content.bounds.width
        let e = expansion
        let headerHeight = bannerHeight - (bannerHeight - chatHeaderHeight) * e
        avatar.frame = CGRect(x: 16, y: 17 - 4 * e, width: 40, height: 40)
        name.frame = CGRect(x: 68, y: 14 + 9 * e, width: w - 112, height: 20)
        message.frame = CGRect(x: 68, y: 36, width: w - 92, height: 34)
        message.alpha = max(0, 1 - e * 2.5)
        close.frame = CGRect(x: w - 40, y: 5 + 8 * e, width: 36, height: 34)
        let fieldGap = (replyHeight - bannerHeight) - ((replyHeight - bannerHeight) - (chatComposerHeight - 6)) * e
        let fieldY = max(headerHeight, h - fieldGap)
        field.frame = CGRect(x: 16, y: fieldY, width: w - 80, height: 42)
        send.frame = CGRect(x: w - 58, y: fieldY - 1, width: 44, height: 44)
        hint.frame = CGRect(x: 12, y: fieldY + 55, width: w - 24, height: 18)
        hint.alpha = max(0, 1 - e * 3)
        grabber.frame = CGRect(x: (w - 32) / 2, y: h - 12, width: 32, height: 4)
        grabber.alpha = max(0, 1 - e * 3)
        divider.frame = CGRect(x: 0, y: headerHeight - 0.5, width: w, height: 0.5)
        divider.alpha = islandSmoothstep(0.1, 0.5, e)

        let clipHeight = max(0, fieldY - 6 - headerHeight)
        historyClip.frame = CGRect(x: 0, y: headerHeight, width: w, height: clipHeight)
        historyClip.alpha = history == .ready ? islandSmoothstep(0, 0.2, e) : 0
        // Centred in the gap, so the opening reveals the history up and down from the seam.
        let finalHeight = max(1, chatHeight - chatHeaderHeight - chatComposerHeight)
        historyView?.frame = CGRect(x: 0, y: (clipHeight - finalHeight) / 2, width: w, height: finalHeight)
        if isReplying, e > 0.001 { dim.alpha = 0.15 + 0.15 * e }
    }

    private func updateControls() {
        let busy = state == .sending
        field.isHidden = !isReplying
        send.isHidden = !isReplying
        hint.isHidden = !isReplying
        field.isEnabled = !busy
        send.isEnabled = !busy && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        close.isEnabled = !busy
        name.isEnabled = !busy
        historyClip.isUserInteractionEnabled = expanded
        if busy { hint.text = "Saving reply…" }
        else if history == .failed { hint.text = "Conversation unavailable · tap name for full chat" }
        else { hint.text = armed ? "Release to show conversation" : "Pull down to show conversation" }
    }

    private func beginReply() {
        guard state == .banner || state == .entering else { return }
        state = .reply
        content.alpha = 1
        expiry?.cancel()
        drag = 0
        updateControls()
        UIView.animate(withDuration: 0.2) { self.dim.alpha = 0.15 }
        field.becomeFirstResponder()
        prepareHistory()
        animateChange()
    }

    private func prepareHistory() {
        guard history == .none || history == .failed, let onPrepareChat else { return }
        history = .loading
        onPrepareChat { [weak self] success in
            guard let self, self.state != .dismissing else { return }
            if !success {
                self.history = .failed
                if self.expanded { self.setExpanded(false, velocity: 0) }
            }
            self.updateControls()
            self.animateChange()
        }
    }

    private func setExpanded(_ value: Bool, velocity: CGFloat) {
        let target = value && history != .failed
        expansionSpring.velocity = CGVector(dx: velocity, dy: 0)
        if expanded != target {
            expanded = target
            if target { haptic.impactOccurred() }
            onExpandedChanged?(target)
        }
        updateControls()
        animateChange()
    }

    @objc private func textChanged() {
        onDraftChanged?(draft)
        send.isEnabled = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool { sendReply(); return false }

    /// Collapsed, a sent reply closes the card; open, the card stays with the conversation.
    private func sendReply() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard state == .reply, !text.isEmpty, let onSend else { return }
        state = .sending
        updateControls()
        onSend(text) { [weak self] success in
            guard let self, self.state == .sending else { return }
            if success {
                self.field.text = ""
                self.onDraftChanged?("")
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                if self.expanded {
                    self.state = .reply
                    self.updateControls()
                } else { self.dismiss() }
            } else { self.restoreReply(error: "Could not save reply. Tap Send to retry.") }
        }
    }

    private func openFullChat() {
        guard state != .sending, state != .dismissing, let onOpenFullChat else { return }
        onOpenFullChat(draft)
    }

    private func restoreReply(error: String) {
        state = .reply
        updateControls()
        hint.text = error
        field.becomeFirstResponder()
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        animateChange()
    }

    @objc private func keyboardChanged(_ notification: Notification) {
        guard let window, let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        keyboardTop = window.convert(frame, from: nil).minY
        if isReplying { animateChange() }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if state == .dismissing { return false }
        return isReplying || content.frame.insetBy(dx: -8, dy: -8).contains(point)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var target = touch.view
        while let view = target, view !== self {
            if view === historyClip { return false }
            if view is UIControl { return gestureRecognizer is UIPanGestureRecognizer && view === name }
            target = view.superview
        }
        return state == .entering || state == .banner || state == .reply
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: self)
        return abs(velocity.y) > abs(velocity.x)
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        if !content.frame.contains(gesture.location(in: self)) { dismiss() }
        else if state == .banner || state == .entering { beginReply() }
    }

    @objc private func accessibleReply() -> Bool { beginReply(); return true }
    @objc private func accessibleExpand() -> Bool {
        beginReply()
        setExpanded(true, velocity: 0)
        return true
    }
    @objc private func accessibleOpenFull() -> Bool { openFullChat(); return true }

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        if state == .reply { panReply(gesture); return }
        guard state == .banner || state == .entering else { return }
        let translation = gesture.translation(in: self).y
        switch gesture.state {
        case .began, .changed:
            expiry?.cancel()
            drag = translation < 0 ? translation : translation * 0.55
            animateChange()
        case .ended:
            let velocity = gesture.velocity(in: self).y
            drag = 0
            if translation < -35 || velocity < -650 { dismiss() }
            else if translation > 30 { beginReply() }
            else { scheduleExpiry(); animateChange() }
        case .cancelled, .failed:
            drag = 0
            scheduleExpiry()
            animateChange()
        default: break
        }
    }

    /// The finger drives `expansion` directly; release springs to the nearer end,
    /// carrying the gesture's velocity into the spring.
    private func panReply(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: self).y
        let distance = max(160, chatHeight - replyHeight)
        switch gesture.state {
        case .began:
            dragStartExpansion = expansion
            dragExpansion = dragStartExpansion
        case .changed:
            var value = dragStartExpansion + translation / distance
            if history == .failed { value = min(value, 0.08) }
            // Collapsed, an upward pull moves the card towards dismissal instead.
            drag = dragStartExpansion < 0.5 && value < 0 ? value * distance : 0
            dragExpansion = min(max(value, 0), 1)
            let nowArmed = value > 0.4 && history != .failed
            if nowArmed != armed {
                armed = nowArmed
                if !expanded { updateControls() }
            }
            animateChange()
        case .ended, .cancelled, .failed:
            let velocity = gesture.velocity(in: self).y
            let value = dragExpansion ?? expansion
            expansionSpring.position.x = value
            dragExpansion = nil
            armed = false
            let dismissing = gesture.state == .ended && dragStartExpansion < 0.5 && value < 0.01
                && (drag < -35 || velocity < -650)
            drag = 0
            if dismissing { dismiss(); return }
            let projected = value + velocity / distance * 0.25
            setExpanded(gesture.state == .ended ? projected > 0.5 : expanded, velocity: velocity / distance)
        default: break
        }
    }

    private func scheduleExpiry() {
        expiry?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        expiry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    private func animateChange() {
        if UIAccessibility.isReduceMotionEnabled || gpu == nil {
            if state == .entering { state = .banner }
            if dragExpansion == nil {
                expansionSpring.position.x = expanded ? 1 : 0
                expansionSpring.velocity = .zero
            }
            var center = restingCenter
            center.y += drag
            centerSpring.position = center
            sizeSpring.position = CGPoint(x: cardWidth / 2, y: cardHeight / 2)
            content.alpha = 1
            drawGeometry(neck: 0)
            renderFrame()
            isPaused = true
        } else { isPaused = false }
    }

    override func update(deltaTime: CFTimeInterval) {
        phaseTime += deltaTime
        if dragExpansion == nil {
            expansionSpring.step(toward: CGPoint(x: expanded ? 1 : 0, y: 0), deltaTime: deltaTime)
        }
        var target = restingCenter
        var half = CGPoint(x: cardWidth / 2, y: cardHeight / 2)
        var neck: CGFloat = 0
        if state == .entering {
            neck = 22 * max(0, 1 - CGFloat(phaseTime) / 0.4)
            content.alpha = min(1, max(0, CGFloat(phaseTime - 0.1) / 0.2))
            if phaseTime > 0.65 { state = .banner }
        } else if state == .dismissing {
            target = islandMouth
            half = CGPoint(x: 7, y: 7)
            neck = centerSpring.position.distance(to: islandMouth) < 65 ? 18 : 0
            if phaseTime > 0.65 { finish(); return }
        }
        target.y += drag
        if !isReplying { half.y += max(0, drag) * 0.12 }
        // While the seam opens, the card is locked to the expansion spring (or the
        // finger) rather than chasing it with a second spring.
        if isReplying && !expansionSettled {
            centerSpring.position = target
            centerSpring.velocity = .zero
            sizeSpring.position = half
            sizeSpring.velocity = .zero
        } else {
            centerSpring.step(toward: target, deltaTime: deltaTime)
            sizeSpring.step(toward: half, deltaTime: deltaTime)
        }
        drawGeometry(neck: neck)
        if state != .entering, state != .dismissing, drag == 0, expansionSettled,
           centerSpring.position.distance(to: target) < 0.2, sizeSpring.position.distance(to: half) < 0.2,
           centerSpring.speed < 1, sizeSpring.speed < 1 { isPaused = true }
    }

    private func drawGeometry(neck: CGFloat) {
        let half = sizeSpring.position
        shapes = [IslandFluidShape(center: centerSpring.position, halfSize: CGSize(width: max(1, half.x), height: max(1, half.y)),
                                   cornerRadius: min(28, half.y), blend: neck)]
        content.center = centerSpring.position
        if state == .entering || state == .dismissing {
            // Growing out of (or back into) the island scales the card as one piece.
            content.bounds = CGRect(origin: .zero, size: scaleBase)
            content.transform = CGAffineTransform(scaleX: max(0.01, half.x * 2 / scaleBase.width),
                                                  y: max(0.01, half.y * 2 / scaleBase.height))
        } else {
            content.transform = .identity
            content.bounds = CGRect(x: 0, y: 0, width: max(1, half.x * 2), height: max(1, half.y * 2))
        }
        layoutCard(height: content.bounds.height)
    }
}
