import UIKit

public final class VerticalScrollCoordinator {
    public private(set) var headerOffset: CGFloat = 0
    public private(set) var headerHeight: CGFloat
    public private(set) var paneOffset: CGFloat = 0
    private var rawOverscroll: CGFloat = 0
    private weak var pane: (any ScrollablePane)?
    private var applying = false
    public var changed: (() -> Void)?
    public var viewportHeight: CGFloat = 600
    public var isBouncing: Bool { abs(rawOverscroll) > 0.1 }
    public var topStretch: CGFloat { max(0, -elasticOffset) }
    public var collapseFraction: CGFloat { headerHeight > 0 ? headerOffset / headerHeight : 1 }

    private var elasticOffset: CGFloat {
        let distance = abs(rawOverscroll)
        let dimension = max(1, viewportHeight)
        let amount = dimension * (1 - 1 / (1 + distance * 0.55 / dimension))
        return rawOverscroll < 0 ? -amount : amount
    }

    public init(headerHeight: CGFloat) { self.headerHeight = max(0, headerHeight) }

    public func setHeaderHeight(_ height: CGFloat) {
        let wasCollapsed = headerOffset >= headerHeight - 0.5
        headerHeight = max(0, height)
        headerOffset = wasCollapsed ? headerHeight : min(headerOffset, headerHeight)
        render()
    }

    public func activate(_ next: (any ScrollablePane)?) {
        if let previous = pane, let next, previous === next { reconcile(); return }
        pane?.setVerticalOffset(paneOffset)
        rawOverscroll = 0
        pane = next
        paneOffset = min(max(0, next?.verticalOffset ?? 0), next?.maximumVerticalOffset ?? 0)

        if paneOffset > 0 { headerOffset = headerHeight }
        render()
    }

    public func reconcile() {
        guard !applying else { return }
        paneOffset = min(max(0, (pane?.verticalOffset ?? 0) - max(0, elasticOffset)), pane?.maximumVerticalOffset ?? 0)
        if paneOffset > 0 { headerOffset = headerHeight }
        render()
    }

    public func consume(_ delta: CGFloat) {
        guard delta.isFinite else { return }
        var remaining = delta
        if rawOverscroll * remaining < 0 {
            let repayment = min(abs(rawOverscroll), abs(remaining)) * (remaining > 0 ? 1 : -1)
            rawOverscroll += repayment
            remaining -= repayment
        }
        if abs(rawOverscroll) > 0.01 {
            rawOverscroll += remaining
        } else if remaining >= 0 {
            rawOverscroll = 0
            let headerPart = min(remaining, max(0, headerHeight - headerOffset))
            headerOffset += headerPart
            remaining -= headerPart
            let panePart = min(remaining, max(0, (pane?.maximumVerticalOffset ?? 0) - paneOffset))
            paneOffset += panePart
            remaining -= panePart
            rawOverscroll = remaining
        } else {
            rawOverscroll = 0
            let panePart = min(-remaining, paneOffset)
            paneOffset -= panePart
            remaining += panePart
            let headerPart = min(-remaining, headerOffset)
            headerOffset -= headerPart
            remaining += headerPart
            rawOverscroll = remaining
        }
        render()
    }

    public func stepBounce(deltaTime: CGFloat, velocity: inout CGFloat) -> Bool {
        let previous = rawOverscroll
        velocity += (-rawOverscroll * 180 - velocity * 26) * deltaTime
        rawOverscroll += velocity * deltaTime
        if previous * rawOverscroll <= 0 || abs(rawOverscroll) < 0.5 && abs(velocity) < 5 {
            rawOverscroll = 0
            velocity = 0
        }
        render()
        return isBouncing
    }

    public func finishBounce() {
        rawOverscroll = 0
        render()
    }

    public func scrollToTop() {
        headerOffset = 0
        paneOffset = 0
        rawOverscroll = 0
        render()
    }

    private func render() {
        guard !applying else { return }
        applying = true
        pane?.setVerticalOffset(paneOffset + max(0, elasticOffset))
        changed?()
        applying = false
    }
}
