//
//  ReactionPickerOverlay.swift
//  controller
//
//  The reaction picker oozing out of a long-pressed post: a drop of liquid wells up at the finger,
//  stretches into a bar of emoji above it (LiquidCanvasView), and a trash bubble hangs off it on a
//  strand. Slide the finger along the bar: emoji grow toward it like a dock and the liquid bulges up
//  under the one in reach. Let go on an emoji to pick it, on the trash to delete the post; let go
//  anywhere else and the bar stays open for a tap.
//  The ⌄ at the end of the bar is an accordion: tap it (or rest the finger on it) and the liquid
//  pours down into a grid of more reactions, which pop in row by row; ⌃ folds it back up.
//  Also here: ReactionFlight, which carries the picked emoji in a liquid drop into its chip, and
//  HeartPop for double taps.
//

import UIKit
import Metal

final class ReactionPickerOverlay: UIView {
    enum Choice {
        /// The emoji and where its label is in `host` coordinates.
        case emoji(String, CGPoint)
        case delete
        case dismissed
    }

    var onChoice: ((Choice) -> Void)?
    private var postActions: UIStackView?

    func addPostActions(_ actions: [(String, () -> Void)]) {
        postActions?.removeFromSuperview()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.backgroundColor = ChannelPalette.bubble
        stack.layer.cornerRadius = 14
        stack.clipsToBounds = true
        let height = CGFloat(actions.count) * 44
        let below = collapsedFrame.maxY + 72
        let y = below + height <= bounds.height - safeAreaInsets.bottom - 20
            ? below : max(safeAreaInsets.top + 10, collapsedFrame.minY - height - 12)
        stack.frame = CGRect(x: 20, y: y, width: bounds.width - 40, height: height)
        for (title, action) in actions {
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 16)
            button.addAction(UIAction { [weak self] _ in
                self?.close(with: .dismissed)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: action)
            }, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
        stack.distribution = .fillEqually
        addSubview(stack)
        postActions = stack
        gestureRecognizers?.compactMap { $0 as? UITapGestureRecognizer }.forEach { $0.cancelsTouchesInView = false }
    }

    /// The quick row, then the accordion's grid.
    private let emojis: [String]
    private let quickCount: Int
    private let dim = UIView()
    private let preview: UIView?
    private let canvas = LiquidCanvasView()
    private var labels: [UILabel] = []
    private let moreButton = UIView()
    private let chevron = UIImageView(image: UIImage(systemName: "chevron.down"))
    private let trashIcon = UIImageView(image: UIImage(systemName: "trash.fill"))
    private let touchPoint: CGPoint
    private let collapsedFrame: CGRect
    private let expandedFrame: CGRect
    private let trashCenter: CGPoint

    // The panel's four edges ride their own springs: it wells up out of the finger, and when the
    // accordion opens the bottom edge lags behind and overshoots like poured jelly.
    private var top: Spring1D
    private var bottom: Spring1D
    private var left: Spring1D
    private var right: Spring1D
    private var trashRadius = Spring1D(0, stiffness: 13, dampingRatio: 0.5)
    private var scales: [Spring1D] = []
    private var lifts: [Spring1D] = []
    private var moreScale = Spring1D(0, stiffness: 16, dampingRatio: 0.5)
    private var chevronTurn = Spring1D(0, stiffness: 14, dampingRatio: 0.55)
    private var bulge = Spring1D(0, stiffness: 18, dampingRatio: 0.5)
    private var bulgeX: CGFloat = 0
    private var clock: CFTimeInterval = 0
    private var expanded = false
    private var expandTime: CFTimeInterval = 0
    private var finger: CGPoint?
    private var selected: Int?
    private var moreSelected = false
    private var moreHover: CFTimeInterval = 0
    private var trashSelected = false
    private var closing = false
    private var closeTime: CFTimeInterval = 0
    private var picked: Int?
    private let selection = UISelectionFeedbackGenerator()

    private let slot: CGFloat
    private let rowHeight: CGFloat = 54
    /// Columns of the bar: the quick emoji plus the ⌄ button. The grid uses the same columns.
    private var columns: Int { quickCount + 1 }

    /// `bubble` is the pressed post (snapshotted so it stays above the dim), `point` the finger, both in
    /// `host`. `emojis` is the quick row; `more` fills the accordion.
    init(in host: UIView, bubble: UIView, at point: CGPoint, emojis: [String], more: [String]) {
        let slot = min(CGFloat(44), (host.bounds.width - 30) / CGFloat(emojis.count + 1))
        self.slot = slot
        self.emojis = emojis + more
        quickCount = emojis.count
        touchPoint = point
        preview = bubble.snapshotView(afterScreenUpdates: false)
        let safe = host.safeAreaInsets
        let width = CGFloat(emojis.count + 1) * slot + 10
        let x = min(max(point.x, width / 2 + 10), host.bounds.width - width / 2 - 10)
        let y = max(point.y - 86, safe.top + 70)
        collapsedFrame = CGRect(x: x - width / 2, y: y - rowHeight / 2, width: width, height: rowHeight)
        // The accordion opens downward, or moves up if the grid would run off the screen.
        let rows = ceil(CGFloat(more.count) / CGFloat(emojis.count + 1))
        let expandedHeight = rowHeight + 6 + rows * slot + 8
        let maxY = host.bounds.height - safe.bottom - 12
        let expandedTop = max(safe.top + 8, min(collapsedFrame.minY, maxY - expandedHeight))
        expandedFrame = CGRect(x: collapsedFrame.minX, y: expandedTop, width: width, height: expandedHeight)
        trashCenter = CGPoint(x: collapsedFrame.minX + 26, y: collapsedFrame.maxY + 34)
        top = Spring1D(point.y - 8, stiffness: 15, dampingRatio: 0.62)
        bottom = Spring1D(point.y + 8, stiffness: 11, dampingRatio: 0.5)
        left = Spring1D(point.x - 8, stiffness: 11, dampingRatio: 0.58)
        right = Spring1D(point.x + 8, stiffness: 10.5, dampingRatio: 0.55)
        super.init(frame: host.bounds)
        host.addSubview(self)

        dim.backgroundColor = UIColor(white: 0, alpha: 0.45)
        dim.frame = bounds
        dim.alpha = 0
        addSubview(dim)
        if let preview {
            preview.frame = bubble.convert(bubble.bounds, to: self)
            addSubview(preview)
        }
        canvas.frame = bounds
        canvas.liquidColor = ChannelPalette.picker
        canvas.gloss = 0.45
        canvas.rimWidth = 8
        canvas.onUpdate = { [weak self] dt in self?.step(dt) }
        addSubview(canvas)

        for (index, emoji) in self.emojis.enumerated() {
            let label = UILabel()
            label.text = emoji
            label.isAccessibilityElement = true
            label.accessibilityTraits = .button
            label.accessibilityIdentifier = "contact.channel.picker.\(emoji)"
            label.font = .systemFont(ofSize: index < quickCount ? 30 : 27)
            label.sizeToFit()
            label.alpha = 0
            addSubview(label)
            labels.append(label)
            scales.append(Spring1D(0, stiffness: 16, dampingRatio: 0.5))
            lifts.append(Spring1D(0, stiffness: 18, dampingRatio: 0.6))
        }
        moreButton.backgroundColor = UIColor(white: 1, alpha: 0.12)
        moreButton.bounds = CGRect(x: 0, y: 0, width: 30, height: 30)
        moreButton.layer.cornerRadius = 15
        moreButton.isUserInteractionEnabled = false
        moreButton.isAccessibilityElement = true
        moreButton.accessibilityTraits = .button
        moreButton.accessibilityLabel = "More reactions"
        moreButton.accessibilityIdentifier = "contact.channel.picker.more"
        chevron.tintColor = .white
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        chevron.sizeToFit()
        chevron.center = CGPoint(x: 15, y: 15)
        moreButton.addSubview(chevron)
        moreButton.alpha = 0
        addSubview(moreButton)
        trashIcon.tintColor = UIColor(red: 1, green: 0.38, blue: 0.38, alpha: 1)
        trashIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        trashIcon.sizeToFit()
        trashIcon.center = trashCenter
        trashIcon.alpha = 0
        trashIcon.isAccessibilityElement = true
        trashIcon.accessibilityTraits = .button
        trashIcon.accessibilityLabel = "Delete post"
        trashIcon.accessibilityIdentifier = "contact.channel.picker.delete"
        addSubview(trashIcon)

        finger = point
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        UIView.animate(withDuration: 0.25) { self.dim.alpha = 1 }
        preview.map { p in
            UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.3) {
                p.transform = CGAffineTransform(scaleX: 1.02, y: 1.02)
            }
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        selection.prepare()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Where item `index` sits right now: the quick row rides the panel's top edge, the grid hangs below it.
    private func itemCenter(_ index: Int) -> CGPoint {
        let left = collapsedFrame.minX + 5
        let rowY = top.value + min(rowHeight / 2, max(bottom.value - top.value, 0) / 2)
        if index < quickCount {
            return CGPoint(x: left + slot * (CGFloat(index) + 0.5), y: rowY)
        }
        let k = index - quickCount
        let row = k / columns, column = k % columns
        return CGPoint(x: left + slot * (CGFloat(column) + 0.5),
                       y: top.value + rowHeight + 6 + slot * (CGFloat(row) + 0.5))
    }

    private var moreCenter: CGPoint {
        CGPoint(x: collapsedFrame.minX + 5 + slot * (CGFloat(quickCount) + 0.5),
                y: top.value + min(rowHeight / 2, max(bottom.value - top.value, 0) / 2))
    }

    // MARK: Finger

    func move(to point: CGPoint) {
        guard !closing else { return }
        finger = point
        var nearest: Int?
        if expanded {
            var best: CGFloat = 30
            for index in emojis.indices where scales[index].value > 0.5 {
                let distance = point.distance(to: itemCenter(index))
                if distance < best {
                    best = distance
                    nearest = index
                }
            }
        } else if point.y > collapsedFrame.midY - 70, point.y < collapsedFrame.midY + 60 {
            var best = slot * 0.75
            for index in 0..<quickCount {
                let distance = abs(point.x - itemCenter(index).x)
                if distance < best {
                    best = distance
                    nearest = index
                }
            }
        }
        let onMore = nearest == nil && abs(point.x - moreCenter.x) < slot * 0.6
            && abs(point.y - moreCenter.y) < (expanded ? 26 : 60)
        let onTrash = !expanded && point.distance(to: trashCenter) < 30
        if nearest != selected || onTrash != trashSelected || onMore != moreSelected {
            if nearest != nil || onTrash || onMore {
                selection.selectionChanged()
            }
            selected = nearest
            trashSelected = onTrash
            moreSelected = onMore
            moreHover = 0
        }
    }

    /// The finger lifted: pick what is under it, or stay open for a tap.
    func release() {
        if let selected {
            pick(selected)
        } else if trashSelected {
            close(with: .delete)
        } else if moreSelected {
            moreSelected = false
            setExpanded(!expanded)
        }
        finger = nil
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        if postActions?.frame.contains(point) == true { return }
        if let index = labels.indices.first(where: { scales[$0].value > 0.5 && labels[$0].frame.insetBy(dx: -6, dy: -6).contains(point) }) {
            pick(index)
        } else if moreButton.frame.insetBy(dx: -10, dy: -10).contains(point) {
            setExpanded(!expanded)
        } else if !expanded, point.distance(to: trashCenter) < 30 {
            close(with: .delete)
        } else if expanded, panelRect.contains(point) {
            return
        } else {
            close(with: .dismissed)
        }
    }

    private var panelRect: CGRect {
        CGRect(x: left.value, y: top.value, width: max(right.value - left.value, 0), height: max(bottom.value - top.value, 0))
    }

    private func setExpanded(_ open: Bool) {
        postActions?.isHidden = open
        guard !closing, open != expanded else { return }
        expanded = open
        moreButton.accessibilityLabel = open ? "Collapse reactions" : "More reactions"
        expandTime = 0
        selected = nil
        // The jelly kick: the bottom edge is flung so it overshoots and wobbles.
        bottom.velocity += open ? 300 : -200
        UIImpactFeedbackGenerator(style: open ? .medium : .soft).impactOccurred()
    }

    private func pick(_ index: Int) {
        picked = index
        let label = labels[index]
        let point = label.superview?.convert(label.center, to: superview) ?? label.center
        label.alpha = 0
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        close(with: .emoji(emojis[index], point))
    }

    private func close(with choice: Choice) {
        guard !closing else { return }
        closing = true
        closeTime = 0
        finger = nil
        selected = nil
        UIView.animate(withDuration: 0.3, delay: 0.05) {
            self.dim.alpha = 0
            self.preview?.alpha = 0
            self.preview?.transform = .identity
        }
        onChoice?(choice)
    }

    // MARK: Simulation

    private func step(_ dt: CFTimeInterval) {
        clock += dt
        expandTime += dt
        // Resting on ⌄ while dragging opens the accordion too.
        if moreSelected, finger != nil {
            moreHover += dt
            if moreHover > 0.35 {
                moreHover = -10
                setExpanded(!expanded)
            }
        }

        let goal: CGRect
        if closing {
            let point = picked.map(itemCenter) ?? CGPoint(x: collapsedFrame.midX, y: top.value + 20)
            goal = CGRect(origin: point, size: .zero)
        } else {
            goal = expanded ? expandedFrame : collapsedFrame
        }
        top.step(toward: goal.minY, deltaTime: dt)
        bottom.step(toward: goal.maxY, deltaTime: dt)
        left.step(toward: goal.minX, deltaTime: dt)
        right.step(toward: goal.maxX, deltaTime: dt)
        trashRadius.step(toward: closing || expanded || clock < 0.12 ? 0 : 22, deltaTime: dt)
        chevronTurn.step(toward: expanded ? 1 : 0, deltaTime: dt)

        let rect = panelRect
        var bulgeTarget: CGFloat = 0
        for index in labels.indices {
            let center = itemCenter(index)
            let isGrid = index >= quickCount
            // Each emoji pops in once the liquid has spread under it; the grid also waits its turn.
            var covered = !closing && clock > 0.08 && center.x > rect.minX + 8 && center.x < rect.maxX - 8
                && center.y < rect.maxY - 10
            if isGrid {
                let k = index - quickCount
                covered = covered && expanded && expandTime > 0.06 + Double(k / columns) * 0.045 + Double(k % columns) * 0.012
            }
            var scaleTarget: CGFloat = covered ? 1 : 0
            var liftTarget: CGFloat = 0
            if covered, let finger {
                // Dock magnification toward the finger: along the bar, or around it in the grid.
                let falloff: CGFloat
                if expanded {
                    falloff = exp(-pow(finger.distance(to: center) / 34, 2))
                } else if !isGrid, finger.y > collapsedFrame.midY - 80, finger.y < collapsedFrame.midY + 70 {
                    falloff = exp(-pow((finger.x - center.x) / 40, 2))
                } else {
                    falloff = 0
                }
                scaleTarget += (expanded ? 0.55 : 0.7) * falloff
                liftTarget = (expanded ? 10 : 16) * falloff
            }
            if index == selected, !isGrid {
                bulgeTarget = 1
                bulgeX = center.x
            }
            scales[index].step(toward: scaleTarget, deltaTime: dt)
            lifts[index].step(toward: liftTarget, deltaTime: dt)
            let label = labels[index]
            label.center = CGPoint(x: center.x, y: center.y - lifts[index].value)
            let s = max(scales[index].value, 0.001)
            label.transform = CGAffineTransform(scaleX: s, y: s)
            if index != picked {
                // Closing, the emoji vanish at once rather than hang outside the shrinking liquid.
                let fade = closing ? max(0, 1 - CGFloat(closeTime) / 0.1) : 1
                label.alpha = min(1, max(0, s * 3)) * fade
            }
        }
        // The accordion button.
        let moreCovered = !closing && clock > 0.12 && moreCenter.x < rect.maxX - 8
        moreScale.step(toward: moreCovered ? (moreSelected ? 1.25 : 1) : 0, deltaTime: dt)
        let m = max(moreScale.value, 0.001)
        moreButton.center = moreCenter
        moreButton.transform = CGAffineTransform(scaleX: m, y: m)
        moreButton.alpha = min(1, max(0, m * 3)) * (closing ? max(0, 1 - CGFloat(closeTime) / 0.1) : 1)
        chevron.transform = CGAffineTransform(rotationAngle: .pi * chevronTurn.value)

        bulge.step(toward: closing ? 0 : bulgeTarget, deltaTime: dt)
        trashIcon.alpha = min(1, max(0, (trashRadius.value - 10) / 8))
        trashIcon.transform = trashSelected ? CGAffineTransform(scaleX: 1.3, y: 1.3) : .identity

        var shapes: [IslandFluidShape] = []
        var spikes: [IslandFluidSpike] = []
        if rect.width > 1, rect.height > 1 {
            shapes.append(IslandFluidShape(center: rect.center, halfSize: CGSize(width: rect.width / 2, height: rect.height / 2),
                                           cornerRadius: min(rowHeight / 2, rect.height / 2), blend: 0))
            // The tail back to the finger while the drop wells up.
            let tail = max(0, 1 - clock / 0.3)
            if tail > 0, !closing {
                spikes.append(IslandFluidSpike(base: touchPoint, tip: rect.center, baseRadius: 10 * tail,
                                               tipRadius: 6, blend: 8))
            }
            if bulge.value > 0.02 {
                shapes.append(.circle(center: CGPoint(x: bulgeX, y: rect.minY + 8 - 10 * bulge.value),
                                      radius: 22 * bulge.value, blend: 12))
            }
        }
        if trashRadius.value > 0.5 {
            let r = trashRadius.value * (trashSelected ? 1.15 : 1)
            shapes.append(.circle(center: trashCenter, radius: r, blend: 0))
            let strandBase = CGPoint(x: trashCenter.x, y: rect.maxY - 4)
            spikes.append(IslandFluidSpike(base: strandBase, tip: trashCenter, baseRadius: 7, tipRadius: 4, blend: 9))
        }
        canvas.shapes = shapes
        canvas.spikes = spikes

        if closing {
            closeTime += dt
            if closeTime > 0.45 {
                canvas.isPaused = true
                removeFromSuperview()
            }
        }
    }
}

// MARK: - Flight

/// Carries an emoji along an arc inside a liquid drop and lands it in its chip, which gulps it.
enum ReactionFlight {
    /// `target` is asked every frame, so the chip can still be moving (reflow, scroll).
    static func fly(
        _ emoji: String,
        from start: CGPoint,
        in host: UIView,
        liquid: FeedLiquidLayer,
        startSize: CGFloat = 30,
        target: @escaping () -> (point: CGPoint, chip: CGRect),
        landed: @escaping () -> Void
    ) {
        let label = UILabel()
        label.text = emoji
        label.font = .systemFont(ofSize: startSize)
        label.sizeToFit()
        label.center = start
        host.addSubview(label)
        host.bringSubviewToFront(liquid)
        host.bringSubviewToFront(label)
        var t: CGFloat = 0
        var landedTime: CGFloat?
        var swell = Spring1D(0, stiffness: 15, dampingRatio: 0.4)
        let duration: CGFloat = 0.6
        let side: CGFloat = Bool.random() ? 1 : -1
        liquid.add { dt in
            t += CGFloat(dt)
            let goal = target()
            if landedTime == nil {
                let u = min(t / duration, 1)
                let e = u < 0.5 ? 2 * u * u : 1 - pow(-2 * u + 2, 2) / 2
                let control = CGPoint(x: (start.x + goal.point.x) / 2 + side * 60, y: min(start.y, goal.point.y) - 90)
                let a = CGPoint.lerp(start, control, e), b = CGPoint.lerp(control, goal.point, e)
                label.center = CGPoint.lerp(a, b, e)
                let s = 1 - (1 - 17 / startSize) * e
                label.transform = CGAffineTransform(rotationAngle: sin(e * .pi * 2) * 0.35 * side).scaledBy(x: s, y: s)
                if u >= 1 {
                    landedTime = t
                    swell.velocity = 9
                    landed()
                    label.removeFromSuperview()
                }
                // The drop around the emoji: big in flight, shrinking as it nears the chip.
                let radius = 24 - 10 * e
                return ([.circle(center: label.center, radius: radius, blend: 0)], [])
            }
            // Landed: the drop melts into the chip, which swells and settles.
            let since = t - (landedTime ?? t)
            swell.step(toward: 0, deltaTime: dt)
            let chip = goal.chip
            let melt = max(0, 1 - since / 0.28)
            guard since < 0.28 else { return nil }
            let grow = 1 + 0.12 * swell.value
            return ([IslandFluidShape(center: chip.center, halfSize: CGSize(width: chip.width / 2 * grow, height: chip.height / 2 * grow),
                                      cornerRadius: chip.height / 2, blend: 0),
                     .circle(center: goal.point, radius: 14 * melt, blend: 10)], [])
        }
    }
}

// MARK: - Heart

/// Mirrors `HeartUniforms` in LiquidUI.metal.
private struct PopHeartUniforms {
    var viewport: SIMD2<Float>
    var scale: Float
    var level: Float
    var center: SIMD2<Float>
    var size: Float
    var slosh: Float
    var color: SIMD4<Float>
    var time: Float
    var stroke: Float
    var unused: SIMD2<Float> = .zero
}

/// A liquid heart that fills up where you double-tapped, pops with sparks, then flies into the ❤️ chip.
final class HeartPop: VFXMetalView {
    private var level = Spring1D(0, stiffness: 11, dampingRatio: 0.6)
    private var pop = Spring1D(0.4, stiffness: 16, dampingRatio: 0.35)
    private var burst = false
    private var flight: (start: CGPoint, target: () -> CGPoint, begin: CFTimeInterval)?
    private var onArrive: (() -> Void)?
    private let color = UIColor(red: 1, green: 0.27, blue: 0.42, alpha: 1)

    /// Pops a heart at `point` in `host`. With `target`, it then flies there and calls `arrive`.
    static func show(at point: CGPoint, in host: UIView, target: (() -> CGPoint)?, arrive: (() -> Void)?) {
        let heart = HeartPop(frame: CGRect(x: 0, y: 0, width: 110, height: 110))
        heart.center = point
        heart.isUserInteractionEnabled = false
        host.addSubview(heart)
        heart.onArrive = arrive
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.62) { [weak heart] in
            guard let heart else { return }
            if let target {
                heart.flight = (heart.center, target, heart.time)
            } else {
                UIView.animate(withDuration: 0.25) {
                    heart.alpha = 0
                    heart.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
                } completion: { _ in
                    heart.removeFromSuperview()
                }
            }
        }
    }

    override func update(deltaTime: CFTimeInterval) {
        level.step(toward: 1, deltaTime: deltaTime)
        pop.step(toward: 1, deltaTime: deltaTime)
        if !burst, level.value > 0.95 {
            burst = true
            pop.velocity += 5
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            if let window {
                IslandConfetti.burst(in: window, from: convert(CGPoint(x: bounds.midX, y: bounds.midY), to: window),
                                     direction: -.pi / 2, spread: 2 * .pi, particles: 140, sparkShare: 1,
                                     sparkColor: color, speedScale: 0.4)
            }
        }
        var scale = pop.value
        if let flight {
            let u = min(CGFloat((time - flight.begin) / 0.5), 1)
            let e = u * u * (3 - 2 * u)
            let goal = flight.target()
            let control = CGPoint(x: (flight.start.x + goal.x) / 2 - 50, y: min(flight.start.y, goal.y) - 70)
            center = CGPoint.lerp(CGPoint.lerp(flight.start, control, e), CGPoint.lerp(control, goal, e), e)
            scale *= 1 - 0.8 * e
            if u >= 1 {
                self.flight = nil
                onArrive?()
                isPaused = true
                removeFromSuperview()
                return
            }
        }
        transform = CGAffineTransform(scaleX: scale, y: scale)
    }

    override func encode(into commandBuffer: MTLCommandBuffer, target: MTLTexture) {
        guard let gpu, let pipeline = gpu.renderPipeline(vertex: "liquid_ui_vertex", fragment: "heart_fragment"),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass(target: target)) else {
            super.encode(into: commandBuffer, target: target)
            return
        }
        let size = bounds.size
        var uniforms = PopHeartUniforms(
            viewport: SIMD2(Float(target.width), Float(target.height)), scale: Float(contentScaleFactor),
            level: Float(max(0, min(1, level.value))), center: SIMD2(Float(size.width / 2), Float(size.height / 2)),
            size: Float(size.width * 0.62), slosh: Float(level.velocity), color: color.vfxSIMD(with: traitCollection),
            time: Float(time), stroke: 0)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<PopHeartUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}
