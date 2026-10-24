//
//  IslandPocket.swift
//  controller
//
//  "Add to cart" into the Dynamic Island: the view shrinks along an arc, turns into a drop and is
//  swallowed; the island swells into a wider pill with a cart icon and a counter. Tap the pill and
//  the contents pour out into a panel of thumbnails; tap the panel to pour them back in.
//

import UIKit

final class IslandPocket: IslandFluidView {
    /// Symbol shown on the left of the swollen island.
    var symbol = "cart.fill" {
        didSet { icon.image = UIImage(systemName: symbol) }
    }
    private(set) var items: [UIImage] = []

    private struct Flight {
        let imageView: UIImageView
        let start: CGPoint
        let control: CGPoint
        let image: UIImage
        var t: CGFloat = 0
        var position: CGPoint
    }

    private let flightDuration: CGFloat = 0.6
    private var flights: [Flight] = []
    /// Half width / half height of the swollen island.
    private var swell = IslandSpring(.zero, stiffness: 14, dampingRatio: 0.38)
    private var panelOpen = false
    private var panelVisible = false
    private var panelTime: CFTimeInterval = 0
    private var panelCenter = IslandSpring(.zero, stiffness: 15, dampingRatio: 0.55)
    private var panelSize = IslandSpring(CGPoint(x: 8, y: 8), stiffness: 17, dampingRatio: 0.45)
    private var recoilTime: CFTimeInterval?

    private let icon = UIImageView(image: UIImage(systemName: "cart.fill"))
    private let countLabel = UILabel()
    private let panelContent = UIView()
    private let thumbnails = UIStackView()
    private let panelLabel = UILabel()
    private let gulpHaptic = UIImpactFeedbackGenerator(style: .soft)
    private let tapHaptic = UIImpactFeedbackGenerator(style: .light)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true
        gloss = 0.5
        rimWidth = 10
        isPaused = true

        icon.tintColor = .white
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        countLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .bold)
        countLabel.textColor = .white
        countLabel.textAlignment = .center
        for view in [icon, countLabel] {
            view.alpha = 0
            addSubview(view)
        }

        thumbnails.axis = .horizontal
        thumbnails.spacing = 8
        panelLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        panelLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        let column = UIStackView(arrangedSubviews: [thumbnails, panelLabel])
        column.axis = .vertical
        column.spacing = 8
        column.alignment = .leading
        column.translatesAutoresizingMaskIntoConstraints = false
        panelContent.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: panelContent.leadingAnchor, constant: 20),
            column.centerYAnchor.constraint(equalTo: panelContent.centerYAnchor),
        ])
        panelContent.alpha = 0
        panelContent.isUserInteractionEnabled = false
        addSubview(panelContent)

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func install(in window: UIWindow) {
        super.install(in: window)
        if swell.position == .zero {
            swell.position = CGPoint(x: island.width / 2, y: island.height / 2)
        }
        panelContent.bounds = CGRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
    }

    private var panelWidth: CGFloat { min(bounds.width - 24, 360) }
    private let panelHeight: CGFloat = 104

    // MARK: Public API

    /// Flies a snapshot of `view` into the island and adds it to the pocket.
    func add(_ view: UIView) {
        if window == nil, let window = view.window {
            install(in: window)
        }
        guard let window, view.window === window else { return }
        let frame = view.convert(view.bounds, to: self)
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: false)
        }
        let imageView = UIImageView(image: image)
        imageView.frame = frame
        imageView.layer.cornerRadius = 14
        imageView.layer.cornerCurve = .continuous
        imageView.clipsToBounds = true
        addSubview(imageView)
        let start = CGPoint(x: frame.midX, y: frame.midY)
        let end = islandMouth
        // Up first, then curving over into the island.
        let control = CGPoint(x: start.x + (end.x - start.x) * 0.1, y: end.y + (start.y - end.y) * 0.3)
        flights.append(Flight(imageView: imageView, start: start, control: control, image: image, position: start))
        gulpHaptic.prepare()
        isPaused = false
    }

    /// Empties the pocket: the island shrinks back.
    func empty() {
        items.removeAll()
        panelOpen = false
        updateLabels()
        isPaused = false
    }

    // MARK: Touches

    private var swellRect: CGRect {
        CGRect(x: island.midX - swell.position.x, y: island.minY, width: swell.position.x * 2, height: swell.position.y * 2)
    }

    private var panelRect: CGRect {
        CGRect(x: panelCenter.position.x - panelSize.position.x, y: panelCenter.position.y - panelSize.position.y,
               width: panelSize.position.x * 2, height: panelSize.position.y * 2)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if panelVisible, panelRect.insetBy(dx: -6, dy: -6).contains(point) {
            return true
        }
        // The status bar band may keep touches on the island itself; accept taps just below it too.
        let target = swellRect.insetBy(dx: -8, dy: -8).inset(by: UIEdgeInsets(top: 0, left: 0, bottom: -22, right: 0))
        return !items.isEmpty && target.contains(point)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        toggleContents()
    }

    /// Pours the contents out into the panel, or back into the island.
    func toggleContents() {
        tapHaptic.impactOccurred()
        if panelOpen {
            panelOpen = false
        } else if !items.isEmpty {
            openPanel()
        }
        isPaused = false
    }

    private func openPanel() {
        panelOpen = true
        panelVisible = true
        panelTime = 0
        panelCenter.position = CGPoint(x: islandMouth.x, y: islandMouth.y - 4)
        panelSize.position = CGPoint(x: 8, y: 8)
        panelSize.velocity = .zero
        thumbnails.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for image in items.suffix(5).reversed() {
            let thumb = UIImageView(image: image)
            thumb.contentMode = .scaleAspectFill
            thumb.layer.cornerRadius = 10
            thumb.layer.cornerCurve = .continuous
            thumb.clipsToBounds = true
            thumb.translatesAutoresizingMaskIntoConstraints = false
            thumb.widthAnchor.constraint(equalToConstant: 52).isActive = true
            thumb.heightAnchor.constraint(equalToConstant: 52).isActive = true
            thumbnails.addArrangedSubview(thumb)
        }
        panelLabel.text = items.count == 1 ? "1 item in your cart" : "\(items.count) items in your cart"
    }

    private func updateLabels() {
        countLabel.text = "\(items.count)"
    }

    // MARK: Simulation

    override func update(deltaTime: CFTimeInterval) {
        let dt = CGFloat(deltaTime)
        let mouth = islandMouth

        // Flights: along a quadratic Bézier, the snapshot shrinks and fades as the drop grows.
        for index in flights.indices.reversed() {
            var flight = flights[index]
            flight.t = min(1, flight.t + dt / flightDuration)
            let t = flight.t, u = 1 - t
            let end = CGPoint(x: mouth.x, y: mouth.y - 2)
            flight.position = CGPoint(x: u * u * flight.start.x + 2 * u * t * flight.control.x + t * t * end.x,
                                      y: u * u * flight.start.y + 2 * u * t * flight.control.y + t * t * end.y)
            let shrink = 1 - 0.88 * min(1, t / 0.6)
            flight.imageView.center = flight.position
            flight.imageView.transform = CGAffineTransform(scaleX: shrink, y: shrink)
            flight.imageView.alpha = 1 - islandSmoothstep(0.3, 0.6, t)
            flights[index] = flight
            if t >= 1 {
                flight.imageView.removeFromSuperview()
                flights.remove(at: index)
                items.append(flight.image)
                updateLabels()
                // Gulp: the island swells with a kick.
                swell.velocity.dx += 120
                swell.velocity.dy += 70
                recoilTime = 0
                gulpHaptic.impactOccurred()
            }
        }

        let rest = CGPoint(x: island.width / 2, y: island.height / 2)
        let swellTarget = items.isEmpty ? rest : CGPoint(x: rest.x + 34, y: rest.y + 1.5)
        swell.step(toward: swellTarget, deltaTime: deltaTime)
        let open = max(0, min(1, (swell.position.x - rest.x - 12) / 16))
        icon.alpha = open
        countLabel.alpha = open
        icon.center = CGPoint(x: island.midX - swell.position.x + 20, y: island.minY + swell.position.y)
        countLabel.bounds = CGRect(x: 0, y: 0, width: 30, height: 20)
        countLabel.center = CGPoint(x: island.midX + swell.position.x - 20, y: island.minY + swell.position.y)

        updatePanel(deltaTime: deltaTime)
        if let t = recoilTime {
            recoilTime = t > 1 ? nil : t + deltaTime
        }
        rebuildShapes(rest: rest)

        let settled = flights.isEmpty && recoilTime == nil && swell.speed < 0.5
            && abs(swell.position.x - swellTarget.x) < 0.3 && !panelVisible
        if settled {
            renderFrame()
            isPaused = true
        }
    }

    private func updatePanel(deltaTime: CFTimeInterval) {
        guard panelVisible else { return }
        panelTime += deltaTime
        let mouth = islandMouth
        let full = CGPoint(x: panelWidth / 2, y: panelHeight / 2)
        if panelOpen {
            panelCenter.step(toward: CGPoint(x: mouth.x, y: mouth.y + 14 + full.y), deltaTime: deltaTime)
            panelSize.step(toward: full, deltaTime: deltaTime)
            if panelSize.position.x > full.x * 0.85, panelContent.alpha == 0 {
                UIView.animate(withDuration: 0.18) { self.panelContent.alpha = 1 }
            }
        } else {
            if panelContent.alpha == 1 {
                UIView.animate(withDuration: 0.1) { self.panelContent.alpha = 0 }
            }
            panelSize.step(toward: CGPoint(x: 10, y: 10), deltaTime: deltaTime)
            panelCenter.step(toward: CGPoint(x: mouth.x, y: mouth.y + 4), deltaTime: deltaTime)
            if panelCenter.position.distance(to: mouth) < 14, panelSize.position.x < 14 {
                panelVisible = false
                recoilTime = 0
                gulpHaptic.impactOccurred(intensity: 0.6)
            }
        }
        panelContent.center = panelCenter.position
        panelContent.transform = CGAffineTransform(scaleX: max(panelSize.position.x / full.x, 0.01),
                                                   y: max(panelSize.position.y / full.y, 0.01))
    }

    private func rebuildShapes(rest: CGPoint) {
        var newShapes: [IslandFluidShape] = []
        let half = swell.position
        if abs(half.x - rest.x) > 0.3 || abs(half.y - rest.y) > 0.3 {
            // Anchored at the island's top edge so it only grows sideways and down.
            newShapes.append(IslandFluidShape(center: CGPoint(x: island.midX, y: island.minY + half.y),
                                              halfSize: CGSize(width: max(half.x, rest.x), height: max(half.y, rest.y)),
                                              cornerRadius: max(half.y, rest.y), blend: 0))
        }
        for flight in flights {
            let radius = 11 * islandSmoothstep(0.25, 0.55, flight.t)
            if radius > 0.5 {
                newShapes.append(.circle(center: flight.position, radius: radius, blend: flight.t > 0.8 ? 16 : 2))
            }
        }
        if panelVisible {
            // Pours out of the island on a neck that tears, like the toast; the neck reaches back
            // out when the panel returns.
            let neck: CGFloat
            if panelOpen {
                neck = 22 * max(0, 1 - panelTime / 0.3)
            } else {
                neck = panelCenter.position.distance(to: islandMouth) < 70 ? 20 : 0
            }
            let size = panelSize.position
            newShapes.append(IslandFluidShape(center: panelCenter.position,
                                              halfSize: CGSize(width: max(size.x, 1), height: max(size.y, 1)),
                                              cornerRadius: min(28, min(size.x, size.y)), blend: neck))
        }
        if let t = recoilTime {
            newShapes.append(recoilBump(t, amplitude: 8))
        }
        shapes = newShapes
    }
}
