//
//  IslandPullSearch.swift
//  controller
//
//  Spotlight out of the Dynamic Island: pull a scroll view down past its top and liquid flows out of
//  the island, widening into a pill as you pull. Let go past the threshold and it tears off into a
//  search field; let go early, or end editing with the field empty, and it is sucked back in.
//

import UIKit

final class IslandPullSearch: IslandFluidView, UITextFieldDelegate {
    /// Pull distance (points past the top) that opens the search.
    var threshold: CGFloat = 70
    var placeholder = "Search" {
        didSet { applyPlaceholder() }
    }
    /// Called on every edit with the current query ("" when closed).
    var onQueryChange: ((String) -> Void)?

    private enum Phase: Equatable {
        case idle
        case open
        case closing
    }

    private weak var scrollView: UIScrollView?
    private var observation: NSKeyValueObservation?
    private var phase = Phase.idle
    private var phaseTime: CFTimeInterval = 0
    private var pull: CGFloat = 0
    /// Deepest pull of the current drag: the fling back up at release shouldn't cancel the search.
    private var maxPull: CGFloat = 0
    private var pillCenter = IslandSpring(.zero, stiffness: 16, dampingRatio: 0.55)
    private var size = IslandSpring(CGPoint(x: 6, y: 6), stiffness: 17, dampingRatio: 0.45)
    private var recoilTime: CFTimeInterval?
    private var appliedInset: CGFloat = 0
    private var armedHaptic = false

    private let content = UIView()
    private let field = UITextField()
    private let pillHeight: CGFloat = 48
    private let tickHaptic = UIImpactFeedbackGenerator(style: .rigid)
    private let softHaptic = UIImpactFeedbackGenerator(style: .soft)

    override init(frame: CGRect) {
        super.init(frame: frame)
        gloss = 0.5
        rimWidth = 10
        isUserInteractionEnabled = true
        isPaused = true

        let icon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        icon.tintColor = UIColor.white.withAlphaComponent(0.7)
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        icon.setContentHuggingPriority(.required, for: .horizontal)
        applyPlaceholder()
        field.textColor = .white
        field.tintColor = .white
        field.font = .systemFont(ofSize: 17)
        field.returnKeyType = .search
        field.clearButtonMode = .whileEditing
        field.autocorrectionType = .no
        field.delegate = self
        field.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        let row = UIStackView(arrangedSubviews: [icon, field])
        row.spacing = 10
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            row.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            row.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        content.alpha = 0
        addSubview(content)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func applyPlaceholder() {
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder, attributes: [.foregroundColor: UIColor.white.withAlphaComponent(0.45)])
    }

    private var pillWidth: CGFloat {
        min(bounds.width - 32, 360)
    }

    private var restCenter: CGPoint {
        CGPoint(x: island.midX, y: island.maxY + 14 + pillHeight / 2)
    }

    // MARK: Public API

    func attach(to scrollView: UIScrollView) {
        detach()
        guard let window = scrollView.window else { return }
        self.scrollView = scrollView
        install(in: window)
        content.bounds = CGRect(x: 0, y: 0, width: pillWidth, height: pillHeight)
        observation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.scrollViewDidScroll() }
        }
        scrollView.panGestureRecognizer.addTarget(self, action: #selector(handleScrollPan(_:)))
    }

    func detach() {
        scrollView?.panGestureRecognizer.removeTarget(self, action: #selector(handleScrollPan(_:)))
        observation = nil
        scrollView = nil
        removeFromSuperview()
    }

    /// Sucks the field back into the island.
    func close() {
        guard phase == .open else { return }
        phase = .closing
        phaseTime = 0
        field.text = ""
        onQueryChange?("")
        if field.isFirstResponder {
            field.resignFirstResponder()
        }
        UIView.animate(withDuration: 0.1) { self.content.alpha = 0 }
        setInset(0)
        softHaptic.prepare()
        isPaused = false
    }

    // MARK: Scroll tracking

    private func scrollViewDidScroll() {
        guard let scrollView else { return }
        pull = max(0, -(scrollView.contentOffset.y + scrollView.adjustedContentInset.top))
        if scrollView.isTracking {
            maxPull = max(maxPull, pull)
        }
        if phase == .idle, pull > 0 {
            isPaused = false
            if pull >= threshold, !armedHaptic {
                armedHaptic = true
                tickHaptic.impactOccurred(intensity: 0.7)
            } else if pull < threshold * 0.8 {
                armedHaptic = false
            }
        }
    }

    @objc private func handleScrollPan(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began {
            maxPull = 0
        }
        guard gesture.state == .ended || gesture.state == .cancelled, phase == .idle else { return }
        if max(pull, maxPull) >= threshold {
            open()
        }
        maxPull = 0
    }

    private func open() {
        phase = .open
        phaseTime = 0
        // Start the pill where the pulled liquid is, so it carries on from there.
        let pulled = pulledShape
        pillCenter.position = pulled.center
        pillCenter.velocity = .zero
        size.position = CGPoint(x: pulled.half.width, y: pulled.half.height)
        size.velocity = .zero
        tickHaptic.impactOccurred()
        field.becomeFirstResponder()
        setInset(pillHeight + 20)
        isPaused = false
    }

    private func setInset(_ inset: CGFloat) {
        guard let scrollView, inset != appliedInset else { return }
        let delta = inset - appliedInset
        appliedInset = inset
        UIView.animate(withDuration: 0.3) {
            scrollView.contentInset.top += delta
        }
    }

    // MARK: Text

    @objc private func textChanged() {
        onQueryChange?(field.text ?? "")
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return false
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        if (textField.text ?? "").isEmpty {
            close()
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard phase == .open else { return false }
        let half = size.position
        return abs(point.x - pillCenter.position.x) <= half.x && abs(point.y - pillCenter.position.y) <= half.y + 4
    }

    // MARK: Simulation

    /// The liquid while pulling: a drop that slides down and widens into a pill.
    private var pulledShape: (center: CGPoint, half: CGSize, blend: CGFloat) {
        let p = min(pull / threshold, 1.25)
        let widen = islandSmoothstep(0.25, 1, p)
        let half = CGSize(width: 9 + (pillWidth / 2 - 9) * widen * 0.85, height: 9 + (pillHeight / 2 - 9) * widen)
        let center = CGPoint(x: islandMouth.x, y: islandMouth.y + 4 + p * (14 + pillHeight / 2))
        return (center, half, 22)
    }

    override func update(deltaTime: CFTimeInterval) {
        phaseTime += deltaTime
        let full = CGPoint(x: pillWidth / 2, y: pillHeight / 2)
        var newShapes: [IslandFluidShape] = []
        switch phase {
        case .idle:
            if pull > 0.5 {
                let pulled = pulledShape
                newShapes.append(IslandFluidShape(center: pulled.center, halfSize: pulled.half,
                                                  cornerRadius: pulled.half.height, blend: pulled.blend))
            }
        case .open:
            pillCenter.step(toward: restCenter, deltaTime: deltaTime)
            size.step(toward: full, deltaTime: deltaTime)
            // The neck tears as the field settles, like the toast.
            let neck = 22 * max(0, 1 - phaseTime / 0.25)
            if neck == 0, phaseTime < 0.3, recoilTime == nil {
                recoilTime = 0
            }
            if size.position.x > full.x * 0.85, content.alpha == 0 {
                UIView.animate(withDuration: 0.18) { self.content.alpha = 1 }
            }
            newShapes.append(IslandFluidShape(center: pillCenter.position,
                                              halfSize: CGSize(width: size.position.x, height: size.position.y),
                                              cornerRadius: min(size.position.y, 24), blend: neck))
        case .closing:
            size.step(toward: CGPoint(x: 10, y: 10), deltaTime: deltaTime)
            pillCenter.step(toward: CGPoint(x: islandMouth.x, y: islandMouth.y + 4), deltaTime: deltaTime)
            let distance = pillCenter.position.distance(to: islandMouth)
            newShapes.append(IslandFluidShape(center: pillCenter.position,
                                              halfSize: CGSize(width: size.position.x, height: size.position.y),
                                              cornerRadius: min(size.position.y, 24), blend: distance < 70 ? 20 : 0))
            if distance < 14, size.position.x < 14 {
                phase = .idle
                recoilTime = 0
                softHaptic.impactOccurred()
                newShapes.removeLast()
            }
        }
        if let t = recoilTime {
            recoilTime = t > 1 ? nil : t + deltaTime
            newShapes.append(recoilBump(t, amplitude: 9))
        }
        shapes = newShapes
        content.center = pillCenter.position
        content.transform = CGAffineTransform(scaleX: max(size.position.x / full.x, 0.01),
                                              y: max(size.position.y / full.y, 0.01))

        if phase == .idle, pull < 0.5, recoilTime == nil {
            settle()
        } else if phase == .open, phaseTime > 1.2, size.speed < 0.5, pillCenter.speed < 0.5 {
            renderFrame()
            isPaused = true
        }
    }
}
