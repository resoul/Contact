import UIKit
import AsyncDisplayKit

open class RevealableItemNode: ListItemNode, UIGestureRecognizerDelegate {
    public private(set) var isRevealOpen = false
    public var leadingActions: [RevealAction] = [] { didSet { updateActions() } }
    public var trailingActions: [RevealAction] = [] { didSet { updateActions() } }
    var allowsReveal: ((CGPoint) -> Bool)?
    var revealBegan: (() -> Void)?
    private let leadingView = RevealActionsView()
    private let trailingView = RevealActionsView()
    private var recognizer: UIPanGestureRecognizer!
    private var pagingRecognizer: UIGestureRecognizer?
    private var offset: CGFloat = 0
    private var initialOffset: CGFloat = 0
    private let actionWidth: CGFloat = 76
    private var fullSwipeArmed = false
    private let feedback = UISelectionFeedbackGenerator()

    var hasActions: Bool { !leadingActions.isEmpty || !trailingActions.isEmpty }
    public override var blocksHorizontalPaging: Bool { isRevealOpen }
    public override func closeInteractions(animated: Bool) { closeReveal(animated: animated) }
    var revealRecognizer: UIPanGestureRecognizer { _ = view; return recognizer }

    open override func didLoad() {
        super.didLoad()
        view.insertSubview(leadingView, at: 0)
        view.insertSubview(trailingView, at: 0)
        leadingView.selected = { [weak self] action in self?.perform(action) }
        trailingView.selected = { [weak self] action in self?.perform(action) }
        recognizer = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = self
        view.addGestureRecognizer(recognizer)
        updateActions()
    }

    func requirePagingFailure(_ recognizer: UIGestureRecognizer?) {
        guard let recognizer, recognizer !== pagingRecognizer else { return }
        revealRecognizer.require(toFail: recognizer)
        pagingRecognizer = recognizer
    }

    private func updateActions() {
        guard isNodeLoaded else { return }
        leadingView.configure(leadingActions)
        trailingView.configure(trailingActions)
        recognizer.isEnabled = hasActions
        view.accessibilityCustomActions = (leadingActions + trailingActions).map { action in
            UIAccessibilityCustomAction(name: action.title) { [weak self] _ in self?.perform(action); return true }
        }
        if !hasActions { closeReveal(animated: false) }
        setNeedsLayout()
    }

    open override func layout() {
        super.layout()
        applyOffset()
    }

    private func applyOffset() {
        contentNode.frame = bounds.offsetBy(dx: offset, dy: 0)
        let leftWidth = max(CGFloat(leadingActions.count) * actionWidth, max(0, offset))
        let rightWidth = max(CGFloat(trailingActions.count) * actionWidth, max(0, -offset))
        leadingView.frame = CGRect(x: 0, y: 0, width: leftWidth, height: bounds.height)
        trailingView.frame = CGRect(x: bounds.width - rightWidth, y: 0, width: rightWidth, height: bounds.height)
        leadingView.isHidden = offset <= 0
        trailingView.isHidden = offset >= 0
    }

    public func closeReveal(animated: Bool) {
        offset = 0
        isRevealOpen = false
        fullSwipeArmed = false
        ListTransition.animate(animated, changes: { self.applyOffset() })
    }

    private func perform(_ action: RevealAction) {
        closeReveal(animated: true)
        action.handler()
    }

    open override func prepareForReuse() {
        closeReveal(animated: false)
        allowsReveal = nil
        revealBegan = nil
        leadingActions = []
        trailingActions = []
        super.prepareForReuse()
    }

    public override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === recognizer else { return true }
        let velocity = recognizer.velocity(in: view)
        let location = recognizer.location(in: view)
        let translation = recognizer.translation(in: view)
        let origin = CGPoint(x: location.x - translation.x, y: location.y - translation.y)
        guard abs(velocity.x) > abs(velocity.y), allowsReveal?(origin) != false else { return false }
        if isRevealOpen { return true }
        return velocity.x > 0 ? !leadingActions.isEmpty : !trailingActions.isEmpty
    }

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            initialOffset = offset
            revealBegan?()
            feedback.prepare()
        case .changed:
            let proposed = initialOffset + gesture.translation(in: view).x
            if proposed > 0 && leadingActions.isEmpty || proposed < 0 && trailingActions.isEmpty {
                offset = proposed * 0.12
            } else {
                offset = proposed
            }
            let armed = abs(offset) > bounds.width * 0.72
            if armed != fullSwipeArmed { feedback.selectionChanged(); fullSwipeArmed = armed }
            isRevealOpen = abs(offset) > 0.5
            applyOffset()
        case .ended:
            let actions = offset > 0 ? leadingActions : trailingActions

            if fullSwipeArmed, let action = actions.last, !action.isDestructive {
                perform(action)
            } else {
                let velocity = gesture.velocity(in: view).x
                let opens = !actions.isEmpty && (abs(offset) > 36 || abs(velocity) > 400 && velocity * offset > 0)
                offset = opens ? (offset > 0 ? 1 : -1) * CGFloat(actions.count) * actionWidth : 0
                isRevealOpen = opens
                fullSwipeArmed = false
                ListTransition.animate(true, changes: { self.applyOffset() })
            }
        case .cancelled, .failed:
            closeReveal(animated: true)
        default:
            break
        }
    }
}
