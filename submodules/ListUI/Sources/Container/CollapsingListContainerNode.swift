import UIKit
import AsyncDisplayKit

private final class VerticalDisplayLinkTarget: NSObject {
    weak var owner: CollapsingListContainerNode?
    @objc func tick(_ link: CADisplayLink) { owner?.tick(link) }
}

public final class CollapsingListContainerNode: ASDisplayNode, UIGestureRecognizerDelegate {
    public let header: ASDisplayNode
    public let pager: ListPagerNode
    public let coordinator: VerticalScrollCoordinator
    public var headerProgressChanged: ((CGFloat) -> Void)?
    private var verticalPan: UIPanGestureRecognizer!
    private var previousTranslation: CGFloat = 0
    private weak var activePane: (any ScrollablePane)?
    private var displayLink: CADisplayLink?
    private let displayLinkTarget = VerticalDisplayLinkTarget()
    private var velocity: CGFloat = 0
    private var previousTimestamp: CFTimeInterval?
    private var suspended = false

    public init(header: ASDisplayNode, height: CGFloat, pager: ListPagerNode) {
        self.header = header
        self.pager = pager
        coordinator = VerticalScrollCoordinator(headerHeight: height)
        super.init()
        addSubnode(header)
        addSubnode(pager)
        coordinator.changed = { [weak self] in self?.placeContent() }
        displayLinkTarget.owner = self
        pager.compositionPaneChanged = { [weak self] pane in self?.activate(pane) }
        pager.horizontalPagingBegan = { [weak self] in self?.stopMotion() }
    }

    deinit { displayLink?.invalidate() }

    public override func didLoad() {
        super.didLoad()
        view.clipsToBounds = true
        verticalPan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        verticalPan.maximumNumberOfTouches = 1
        verticalPan.delegate = self
        view.addGestureRecognizer(verticalPan)

        pager.verticalScrollDriver = { [weak self] delta in
            guard let self else { return }
            self.stopMotion()
            self.coordinator.consume(delta)
            self.coordinator.finishBounce()
            UIAccessibility.post(notification: .pageScrolled, argument: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(suspendMotion),
                                               name: UIApplication.willResignActiveNotification, object: nil)
        activate(pager.currentPane)
    }

    public override func layout() {
        super.layout()
        coordinator.viewportHeight = bounds.height
        placeContent()
    }

    public func setHeaderHeight(_ height: CGFloat) {
        stopMotion()
        coordinator.setHeaderHeight(height)
    }

    private func activate(_ pane: (any ScrollablePane)?) {
        if let pane, let activePane, pane === activePane { coordinator.reconcile(); return }
        stopMotion()
        activePane?.geometryChanged = nil
        activePane = pane
        pane?.stopScrolling()
        pane?.geometryChanged = { [weak self] in self?.coordinator.reconcile() }
        pane?.setExternalScrollDriver(pager.verticalScrollDriver)
        coordinator.activate(pane)
    }

    private func placeContent() {
        let stretch = coordinator.topStretch
        header.frame = CGRect(x: 0, y: -coordinator.headerOffset + stretch,
                              width: bounds.width, height: coordinator.headerHeight)
        pager.frame = CGRect(x: 0, y: coordinator.headerHeight - coordinator.headerOffset + stretch,
                             width: bounds.width, height: bounds.height)
        headerProgressChanged?(coordinator.collapseFraction)
    }

    public override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === verticalPan, !suspended, !pager.isPaging else { return false }
        let movement = verticalPan.velocity(in: view)
        return abs(movement.y) > abs(movement.x)
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        stopMotion()
        return true
    }

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view).y
        switch gesture.state {
        case .began:
            stopMotion()
            activePane?.closeInteractions()
            previousTranslation = 0
            coordinator.consume(-translation)
            previousTranslation = translation
        case .changed:
            coordinator.consume(previousTranslation - translation)
            previousTranslation = translation
        case .ended:
            coordinator.consume(previousTranslation - translation)
            startMotion(velocity: -gesture.velocity(in: view).y)
        case .cancelled, .failed:
            startMotion(velocity: 0)
        default:
            break
        }
    }

    private func startMotion(velocity: CGFloat) {
        guard !suspended else { return }
        self.velocity = velocity
        guard abs(velocity) > 5 || coordinator.isBouncing else { return }
        previousTimestamp = nil
        let link = CADisplayLink(target: displayLinkTarget, selector: #selector(VerticalDisplayLinkTarget.tick(_:)))
        let maximum = Float(min(view.window?.screen.maximumFramesPerSecond ?? 60, 120))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: min(30, maximum), maximum: maximum, preferred: maximum)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let dt = CGFloat(min(1.0 / 30, link.timestamp - (previousTimestamp ?? link.timestamp)))
        previousTimestamp = link.timestamp
        guard dt > 0 else { return }
        if coordinator.isBouncing {
            if !coordinator.stepBounce(deltaTime: dt, velocity: &velocity) { stopMotion() }
        } else {
            coordinator.consume(velocity * dt)
            velocity *= pow(0.998, dt * 1000)
            if abs(velocity) < 5 && !coordinator.isBouncing { stopMotion() }
        }
    }

    public func stopMotion() {
        displayLink?.invalidate()
        displayLink = nil
        previousTimestamp = nil
        velocity = 0
        coordinator.finishBounce()
    }

    @objc private func suspendMotion() { stopMotion() }

    public func setSuspended(_ suspended: Bool) {
        self.suspended = suspended
        if suspended { stopMotion(); activePane?.closeInteractions() }
    }

    public override func didExitHierarchy() {
        super.didExitHierarchy()
        stopMotion()
    }
}
