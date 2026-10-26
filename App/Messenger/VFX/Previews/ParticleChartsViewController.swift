//
//  ParticleChartsDemoViewController.swift
//  controller
//
//  ParticleChartView demos behind one segmented control: a Telegram-style storage donut,
//  bars that pour between datasets, a scrubbable line chart and one dataset morphing between chart types.
//

import UIKit
import ParticleTypes

final class ParticleChartsDemoViewController: UIViewController {
    private let picker = UISegmentedControl(items: ["Storage", "Bars", "Line", "Morph"])
    private let container = UIView()
    private var scene: ChartScene?

    init() {
        super.init(nibName: nil, bundle: nil)
        title = "Particle Charts"
        overrideUserInterfaceStyle = .dark
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.03, green: 0.03, blue: 0.06, alpha: 1)

        picker.selectedSegmentIndex = 0
        picker.addTarget(self, action: #selector(sceneChanged), for: .valueChanged)
        container.clipsToBounds = true

        for subview in [picker, container] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            picker.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            picker.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            picker.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            container.topAnchor.constraint(equalTo: picker.bottomAnchor, constant: 10),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        sceneChanged()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        scene?.chart.engine?.isPaused = false
        navigationController?.overrideUserInterfaceStyle = .dark
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        scene?.chart.engine?.isPaused = true
        navigationController?.overrideUserInterfaceStyle = .unspecified
    }

    @objc private func sceneChanged() {
        scene?.removeFromSuperview()
        let next: ChartScene
        switch picker.selectedSegmentIndex {
        case 0: next = StorageChartScene()
        case 1: next = BarsChartScene()
        case 2: next = LineChartScene()
        default: next = MorphChartScene()
        }
        next.frame = container.bounds
        next.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(next)
        scene = next
    }


}

// MARK: - Shared

private enum ParticleChartsPalette {
    static let blue = UIColor(red: 0.25, green: 0.52, blue: 1.0, alpha: 1)
    static let orange = UIColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1)
    static let cyan = UIColor(red: 0.35, green: 0.85, blue: 1.0, alpha: 1)
    static let purple = UIColor(red: 0.56, green: 0.42, blue: 1.0, alpha: 1)
    static let pink = UIColor(red: 1.0, green: 0.38, blue: 0.62, alpha: 1)
    static let green = UIColor(red: 0.3, green: 0.92, blue: 0.55, alpha: 1)
    static let yellow = UIColor(red: 1.0, green: 0.84, blue: 0.3, alpha: 1)
    static let red = UIColor(red: 1.0, green: 0.36, blue: 0.4, alpha: 1)
}

/// `color` lightened towards white by `t`, keeping its alpha.
private func lightened(_ color: SIMD4<Float>, _ t: Float) -> SIMD4<Float> {
    let rgb = SIMD3(color.x, color.y, color.z)
    let mixed = rgb + (SIMD3(repeating: 1) - rgb) * min(max(t, 0), 1)
    return SIMD4(mixed.x, mixed.y, mixed.z, color.w)
}

private func makeLabel(
    size: CGFloat,
    weight: UIFont.Weight = .regular,
    alpha: CGFloat = 1,
    alignment: NSTextAlignment = .center
) -> UILabel {
    let label = UILabel()
    label.font = .systemFont(ofSize: size, weight: weight)
    label.textColor = UIColor(white: 1, alpha: alpha)
    label.textAlignment = alignment
    label.adjustsFontSizeToFitWidth = true
    label.minimumScaleFactor = 0.6
    return label
}

/// Crossfades a label to new text.
private func setText(_ text: String, on label: UILabel) {
    guard label.text != text else { return }
    UIView.transition(with: label, duration: 0.25, options: .transitionCrossDissolve) { label.text = text }
}

/// One chart demo: owns a full-size ParticleChartView under its own controls and lays both out
/// with frames whenever its size changes.
private class ChartScene: UIView {
    let chart = ParticleChartView()
    private var laidOutSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(chart)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        chart.frame = bounds
        guard bounds.width > 0, bounds.size != laidOutSize else { return }
        let isFirst = laidOutSize == .zero
        laidOutSize = bounds.size
        layoutScene()
        updateChart(isFirst: isFirst)
    }

    /// Frames of the controls and the chart geometry.
    func layoutScene() {}

    /// Sends the current state to the chart; the first time the particles fly in.
    func updateChart(isFirst: Bool) {}
}

// MARK: - 1. Storage donut

/// How "Clear Selected Cache" makes the ring go away.
private enum ClearEffect: CaseIterable {
    case blackHole, dust, sweep, gravity, nova, steam, rows

    var title: String {
        switch self {
        case .blackHole: "Black Hole"
        case .dust: "Dust"
        case .sweep: "Clock Sweep"
        case .gravity: "Gravity"
        case .nova: "Supernova"
        case .steam: "Steam"
        case .rows: "Back to the List"
        }
    }

    var symbol: String {
        switch self {
        case .blackHole: "hurricane"
        case .dust: "wind"
        case .sweep: "clock.fill"
        case .gravity: "arrow.down.to.line"
        case .nova: "sun.max.fill"
        case .steam: "smoke.fill"
        case .rows: "list.bullet"
        }
    }

    var style: ParticleReleaseStyle {
        switch self {
        case .blackHole: ParticleReleaseBlackHole
        case .dust: ParticleReleaseDust
        case .sweep: ParticleReleaseSweep
        case .gravity: ParticleReleaseGravity
        case .nova: ParticleReleaseNova
        case .steam: ParticleReleaseSteam
        case .rows: ParticleReleaseHome
        }
    }

    /// Seconds of the release timeline.
    var duration: TimeInterval {
        switch self {
        case .gravity, .steam: 2.4
        case .rows: 2.2
        case .nova: 2.0
        case .blackHole: 1.6
        default: 1.8
        }
    }
}

private final class StorageChartScene: ChartScene {
    private struct Item {
        let name: String
        let bytes: Double
        let color: UIColor
    }

    private let items = [
        Item(name: "Videos", bytes: 4.5e9, color: ParticleChartsPalette.blue),
        Item(name: "Misc", bytes: 143.2e6, color: ParticleChartsPalette.orange),
        Item(name: "Photos", bytes: 87.7e6, color: ParticleChartsPalette.cyan),
        Item(name: "Stickers", bytes: 7.4e6, color: ParticleChartsPalette.purple),
        Item(name: "Other", bytes: 6.1e6, color: ParticleChartsPalette.pink),
    ]
    /// Even a 0.1% slice gets this much of the ring, or it would be a handful of invisible sparks.
    private let minimumShare = 0.03
    private lazy var enabled = items.map { _ in true }
    /// Particles that write the value in the middle of the ring; the ring gets the rest.
    private let valueParticleCount = 5_000
    private lazy var ringParticleCount = chart.particleCount - valueParticleCount
    private lazy var fullCounts = ParticleChartView.split(ringParticleCount, weights: visualShares(items.map { _ in true }))
    /// Part of a hidden item's particles that leaves; the rest refill the visible slices.
    private let dustFraction = 0.25
    private var selected: Int?
    private var cleared = false
    private var effect = ClearEffect.blackHole

    private let effectPicker = UISegmentedControl(items: ClearEffect.allCases.map { UIImage(systemName: $0.symbol) as Any })
    private let captionLabel = makeLabel(size: 22, weight: .bold)
    private let hintLabel = makeLabel(size: 13, alpha: 0.5)
    private let card = UIView()
    private var rows: [LegendRow] = []
    private let clearButton = UIButton(configuration: .filled())
    private let chargeFill = UIView()
    private let flash = UIView()

    private var donutCenter = CGPoint.zero
    private var outerRadius: CGFloat = 0
    private var innerRadius: CGFloat = 0

    // Hold-to-clear: the charge fills while the button is held and fires the clear at 1.
    private static let chargeTime: CFTimeInterval = 0.9
    private var isHolding = false
    private var charge: CGFloat = 0
    private var chargeFired = false
    private var chargeLink: CADisplayLink?
    private var lastChargeHaptic: CFTimeInterval = 0
    private var lastChargeTick: CFTimeInterval?
    private let chargeHaptics = UIImpactFeedbackGenerator(style: .rigid)

    // The value in the middle counts towards its new value instead of jumping.
    private var shownBytes: Double = 0
    private var counter: (from: Double, to: Double, start: CFTimeInterval, duration: CFTimeInterval)?
    private var counterLink: CADisplayLink?
    private var shownText = ""
    private var lastSelected: Int?

    /// Effect beats (flash, shake, row updates) scheduled for the running clear.
    private var beats: [DispatchWorkItem] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        effectPicker.selectedSegmentIndex = 0
        effectPicker.addAction(UIAction { [weak self] _ in self?.effectChanged() }, for: .valueChanged)
        card.backgroundColor = UIColor(white: 1, alpha: 0.07)
        card.layer.cornerRadius = 26
        card.layer.cornerCurve = .continuous
        let total = items.reduce(0) { $0 + $1.bytes }
        for (index, item) in items.enumerated() {
            let row = LegendRow(color: item.color, name: item.name,
                                percent: String(format: "%.1f%%", item.bytes / total * 100),
                                value: Self.format(item.bytes))
            row.addAction(UIAction { [weak self] _ in self?.toggle(index) }, for: .touchUpInside)
            rows.append(row)
            card.addSubview(row)
        }
        clearButton.configuration?.cornerStyle = .capsule
        clearButton.configuration?.baseBackgroundColor = ParticleChartsPalette.blue
        clearButton.clipsToBounds = true
        clearButton.addTarget(self, action: #selector(pressDown), for: .touchDown)
        clearButton.addTarget(self, action: #selector(pressUp), for: .touchUpInside)
        clearButton.addTarget(self, action: #selector(pressCancelled), for: [.touchUpOutside, .touchCancel])
        chargeFill.backgroundColor = UIColor(white: 1, alpha: 0.28)
        chargeFill.isUserInteractionEnabled = false
        clearButton.addSubview(chargeFill)
        card.addSubview(clearButton)

        flash.backgroundColor = .white
        flash.isUserInteractionEnabled = false
        flash.alpha = 0
        flash.layer.shadowColor = UIColor(red: 0.6, green: 0.75, blue: 1, alpha: 1).cgColor
        flash.layer.shadowOpacity = 1
        flash.layer.shadowRadius = 24
        flash.layer.shadowOffset = .zero
        for subview in [effectPicker, captionLabel, hintLabel, card, flash] {
            addSubview(subview)
        }
        chart.onTap = { [weak self] point in self?.tap(at: point) }
        chart.releaseStyle = effect.style
        updateHint()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            chargeLink?.invalidate()
            chargeLink = nil
            counterLink?.invalidate()
            counterLink = nil
            beats.forEach { $0.cancel() }
        }
    }

    override func layoutScene() {
        let width = bounds.width
        effectPicker.frame = CGRect(x: 16, y: 6, width: width - 32, height: 32)
        outerRadius = min(width * 0.28, 110)
        innerRadius = outerRadius * 0.6
        donutCenter = CGPoint(x: width / 2, y: effectPicker.frame.maxY + 18 + outerRadius)
        captionLabel.frame = CGRect(x: 16, y: donutCenter.y + outerRadius + 14, width: width - 32, height: 28)
        hintLabel.frame = CGRect(x: 16, y: captionLabel.frame.maxY + 2, width: width - 32, height: 18)
        let rowHeight: CGFloat = 42
        card.frame = CGRect(x: 16, y: hintLabel.frame.maxY + 12, width: width - 32,
                            height: rowHeight * CGFloat(rows.count) + 12 + 50 + 14)
        for (index, row) in rows.enumerated() {
            row.frame = CGRect(x: 0, y: 6 + rowHeight * CGFloat(index), width: card.bounds.width, height: rowHeight)
        }
        clearButton.frame = CGRect(x: 16, y: card.bounds.height - 64, width: card.bounds.width - 32, height: 50)
        clearButton.layer.cornerRadius = 25
        chargeFill.frame = CGRect(x: 0, y: 0, width: 0, height: clearButton.bounds.height)
        flash.bounds = CGRect(x: 0, y: 0, width: 36, height: 36)
        flash.layer.cornerRadius = 18
        flash.center = donutCenter

        // Release geometry: the ring for the hole / nova / sweep, the card's top edge as the ground.
        chart.releaseBounds = CGRect(x: donutCenter.x - outerRadius, y: donutCenter.y - outerRadius,
                                     width: outerRadius * 2, height: outerRadius * 2)
        chart.engine?.floorY = Float(card.frame.minY)
    }

    override func updateChart(isFirst: Bool) {
        let shares = cleared ? items.map { _ in 0.0 } : visualShares(enabled)
        let paths = ChartLayout.donut(center: donutCenter, innerRadius: innerRadius, outerRadius: outerRadius,
                                      shares: shares, pop: items.indices.map { $0 == selected ? 12 : 0 })
        // Hidden items keep only a little of their particles to release; the visible slices share
        // everything else, so the ring stays dense. Segments keep item order, so particles of a hidden
        // slice fly into its neighbors.
        let visible = items.indices.map { !cleared && enabled[$0] }
        var counts = items.indices.map { visible[$0] ? 0 : Int((Double(fullCounts[$0]) * dustFraction).rounded()) }
        if visible.contains(true) {
            let refill = ParticleChartView.split(ringParticleCount - counts.reduce(0, +), weights: shares)
            counts = zip(counts, refill).map { $0 + $1 }
        } else {
            counts = fullCounts
        }
        let center = donutCenter, inner = innerRadius, outer = outerRadius
        var segments = items.indices.map { index in
            let base = items[index].color.particleSIMD
            let alpha: Float = selected == nil || selected == index ? 1 : 0.3
            var segment = ParticleChartSegment(path: paths[index], count: counts[index], color: { point in
                // Slightly lighter towards the outer rim.
                let radius = simd_distance(point, SIMD2(Float(center.x), Float(center.y)))
                var color = lightened(base, 0.3 * (radius - Float(inner)) / Float(outer - inner))
                color.w = alpha
                return color
            }, order: { ChartLayout.clockAngle($0, center: center) })
            segment.releaseTarget = rowValueRect(index)
            return segment
        }

        // The value in the middle: counts to its new total, or jumps when a slice is picked.
        let enabledBytes = items.indices.filter { enabled[$0] }.reduce(0) { $0 + items[$1].bytes }
        let targetBytes = cleared ? 0 : selected.map { items[$0].bytes } ?? enabledBytes
        let tint = selected.map { items[$0].color }
        if isFirst || selected != nil || lastSelected != nil {
            stopCounter()
            shownBytes = targetBytes
        } else if targetBytes != shownBytes {
            let duration = cleared ? effect.duration * 0.6 : (counter == nil && shownBytes == 0 ? 1.0 : 0.6)
            startCounter(to: targetBytes, duration: duration)
        }
        lastSelected = selected
        shownText = Self.format(shownBytes)
        segments += valueSegments(shownText, tint: tint)

        chart.releaseStyle = effect.style
        chart.show(segments, from: isFirst ? CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12) : nil,
                   releaseDuration: effect.duration)

        if cleared {
            setText("Cache Cleared", on: captionLabel)
        } else {
            setText(selected.map { items[$0].name } ?? "Storage Usage", on: captionLabel)
        }
        var title = AttributedString(cleared ? "Restore Cache" : "Hold to Clear  ")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        if !cleared {
            var size = AttributedString(Self.format(enabledBytes))
            size.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
            size.foregroundColor = UIColor(white: 1, alpha: 0.6)
            title += size
        }
        clearButton.configuration?.attributedTitle = title
        clearButton.configuration?.baseBackgroundColor = cleared ? UIColor(white: 1, alpha: 0.15) : ParticleChartsPalette.blue
        for (index, row) in rows.enumerated() {
            row.isOn = enabled[index]
            row.isEnabled = !cleared
            // "Back to the List" empties the rows itself, one by one; other effects just dim them.
            if effect != .rows || !cleared {
                let alpha: CGFloat = cleared ? 0.4 : 1
                UIView.animate(withDuration: 0.3) { row.alpha = alpha }
            }
        }
        updateHint()
    }

    /// The value in the middle of the ring, written by particles: a big number over a small unit
    /// ("4,74" / "GB"). The unit gets finer particles so its small letters stay legible. When the value
    /// changes, the old digits fly apart into the new ones.
    private func valueSegments(_ value: String, tint: UIColor?) -> [ParticleChartSegment] {
        let parts = value.split(separator: " ", maxSplits: 1).map(String.init)
        let number = SVGToParticleConverter.path(forText: parts[0], font: .systemFont(ofSize: 48, weight: .heavy))
        let unit = SVGToParticleConverter.path(forText: parts.count > 1 ? parts[1] : "",
                                               font: .systemFont(ofSize: 17, weight: .heavy))
        let numberBox = number.cgPath.boundingBoxOfPath
        let unitBox = unit.cgPath.boundingBoxOfPath.isNull ? .zero : unit.cgPath.boundingBoxOfPath
        // Fit the number into the hole of the ring, then hang the unit (unscaled) under it.
        let gap: CGFloat = 7
        let scale = min(1, innerRadius * 1.5 / numberBox.width, innerRadius * 0.8 / numberBox.height)
        let blockHeight = numberBox.height * scale + gap + unitBox.height
        let top = donutCenter.y - blockHeight / 2
        number.apply(CGAffineTransform(translationX: donutCenter.x, y: top)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -numberBox.midX, y: -numberBox.minY))
        unit.apply(CGAffineTransform(translationX: donutCenter.x - unitBox.midX,
                                     y: top + numberBox.height * scale + gap - unitBox.minY))

        let counts = ParticleChartView.split(valueParticleCount, weights: [0.76, 0.24])
        let unitSize: Float = 1.1
        let color = tint.map { lightened($0.particleSIMD, 0.35) } ?? SIMD4(0.92, 0.95, 1, 1)
        var numberColor = color, unitColor = color
        numberColor.w = glowAlpha(count: counts[0], area: SVGToParticleConverter.area(of: number), size: chart.pointSize)
        // A touch quieter than the number, like a secondary label.
        unitColor.w = 0.9 * glowAlpha(count: counts[1], area: SVGToParticleConverter.area(of: unit), size: unitSize)
        var numberSegment = ParticleChartSegment(path: number, count: counts[0], color: { _ in numberColor },
                                                 order: { $0.x })
        var unitSegment = ParticleChartSegment(path: unit, count: counts[1], pointSize: unitSize,
                                               color: { _ in unitColor }, order: { $0.x })
        numberSegment.affectsBrightness = false
        unitSegment.affectsBrightness = false
        // Digits snap into place, so a running counter stays readable instead of smearing.
        numberSegment.stiffness = 5
        unitSegment.stiffness = 5
        return [numberSegment, unitSegment]
    }

    /// Brightness per particle that gives text about twice the ring's density of light: glyphs pack
    /// particles far tighter than the ring, and fine particles cover less of the screen each.
    private func glowAlpha(count: Int, area: CGFloat, size: Float) -> Float {
        let ringArea = CGFloat.pi * (outerRadius * outerRadius - innerRadius * innerRadius)
        let ringLight = CGFloat(ringParticleCount) / ringArea * CGFloat(chart.pointSize * chart.pointSize)
        let textLight = CGFloat(count) / max(area, 1) * CGFloat(size * size)
        return Float(min(1, 2.2 * ringLight / textLight))
    }

    /// Where an item's particles land with "Back to the List": around the size on its legend row.
    private func rowValueRect(_ index: Int) -> CGRect {
        let row = rows[index].frame
        return CGRect(x: card.frame.maxX - 84, y: card.frame.minY + row.midY - 7, width: 64, height: 14)
    }

    /// Byte shares of the enabled items, each at least `minimumShare` of the ring.
    private func visualShares(_ mask: [Bool]) -> [Double] {
        let total = items.indices.filter { mask[$0] }.reduce(0) { $0 + items[$1].bytes }
        guard total > 0 else { return items.map { _ in 0 } }
        let raw = items.indices.map { mask[$0] ? max(items[$0].bytes / total, minimumShare) : 0 }
        let sum = raw.reduce(0, +)
        return raw.map { $0 / sum }
    }

    private func updateHint() {
        hintLabel.text = cleared ? "\(effect.title) · tap Restore to bring it back"
            : "\(effect.title) · hold the button to clear"
    }

    private func effectChanged() {
        effect = ClearEffect.allCases[effectPicker.selectedSegmentIndex]
        chart.releaseStyle = effect.style
        UISelectionFeedbackGenerator().selectionChanged()
        updateHint()
    }

    private func toggle(_ index: Int) {
        enabled[index].toggle()
        if !enabled[index], selected == index { selected = nil }
        UISelectionFeedbackGenerator().selectionChanged()
        updateChart(isFirst: false)
    }

    private func tap(at point: CGPoint) {
        guard !cleared else { return }
        let radius = hypot(point.x - donutCenter.x, point.y - donutCenter.y)
        var hit: Int?
        if radius > innerRadius - 8, radius < outerRadius + 20 {
            let angle = Double(ChartLayout.clockAngle(SIMD2(Float(point.x), Float(point.y)), center: donutCenter))
            var start = 0.0
            for (index, share) in visualShares(enabled).enumerated() where share > 0 {
                if angle < start + share * 2 * .pi {
                    hit = index
                    break
                }
                start += share * 2 * .pi
            }
        }
        selected = hit == selected ? nil : hit
        UISelectionFeedbackGenerator().selectionChanged()
        updateChart(isFirst: false)
    }

    // MARK: Clear & restore

    private func clear() {
        guard !cleared else { return }
        let shares = visualShares(enabled)
        cleared = true
        selected = nil
        beats.forEach { $0.cancel() }
        beats = []
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        updateChart(isFirst: false)

        let duration = effect.duration
        switch effect {
        case .blackHole:
            // The last particles cross the horizon: the hole collapses in a flash.
            schedule(at: duration * 0.62) { [weak self] in
                self?.flashCenter()
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1)
            }
        case .nova:
            // The charge-up ends and everything blows outwards.
            schedule(at: duration * 0.3) { [weak self] in
                self?.flashCenter()
                self?.shake()
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1)
            }
        case .gravity:
            schedule(at: 0.55) { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 1) }
        case .rows:
            // Each slice lands in its row in turn (clockwise from 12, as the kernel releases them):
            // the row's size drops to zero as its particles arrive.
            var start = 0.0
            for (index, share) in shares.enumerated() where share > 0 {
                let arrival = ((start + share / 2) * 0.55 + 0.08) * duration + 0.55
                start += share
                schedule(at: arrival) { [weak self] in
                    guard let self else { return }
                    self.rows[index].setValue("0 B")
                    self.rows[index].pulse()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
            schedule(at: duration + 0.6) { [weak self] in
                UIView.animate(withDuration: 0.3) { self?.rows.forEach { $0.alpha = 0.4 } }
            }
        default:
            break
        }
        schedule(at: duration) { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }

    private func restore() {
        guard cleared else { return }
        cleared = false
        beats.forEach { $0.cancel() }
        beats = []
        for (index, row) in rows.enumerated() {
            row.setValue(Self.format(items[index].bytes))
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        updateChart(isFirst: false)
    }

    private func schedule(at delay: TimeInterval, _ work: @escaping () -> Void) {
        let item = DispatchWorkItem(block: work)
        beats.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func flashCenter() {
        flash.center = donutCenter
        flash.transform = CGAffineTransform(scaleX: 0.2, y: 0.2)
        flash.alpha = 1
        UIView.animate(withDuration: 0.5, delay: 0, options: .curveEaseOut) {
            self.flash.transform = CGAffineTransform(scaleX: 3.2, y: 3.2)
            self.flash.alpha = 0
        }
    }

    private func shake() {
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = [0, -9, 8, -6, 4, -2, 0]
        animation.duration = 0.4
        layer.add(animation, forKey: "shake")
    }

    // MARK: Hold to clear

    @objc private func pressDown() {
        chargeFired = false
        guard !cleared else { return }
        isHolding = true
        chargeHaptics.prepare()
        if chargeLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(chargeTick(_:)))
            link.add(to: .main, forMode: .common)
            chargeLink = link
        }
    }

    @objc private func pressUp() {
        if cleared, !chargeFired {
            restore()
        }
        isHolding = false
    }

    @objc private func pressCancelled() {
        isHolding = false
    }

    @objc private func chargeTick(_ link: CADisplayLink) {
        // Real elapsed time, so dropped frames don't make the hold longer.
        let dt = min(link.timestamp - (lastChargeTick ?? link.timestamp), 0.1)
        lastChargeTick = link.timestamp
        if isHolding {
            charge = min(1, charge + dt / Self.chargeTime)
            // A ratchet that speeds up and hardens as the charge grows.
            let interval = 0.11 - 0.07 * charge
            if link.timestamp - lastChargeHaptic > interval {
                lastChargeHaptic = link.timestamp
                chargeHaptics.impactOccurred(intensity: 0.25 + 0.75 * charge)
            }
            if charge >= 1 {
                isHolding = false
                chargeFired = true
                charge = 0
                clear()
            }
        } else {
            charge = max(0, charge - dt / 0.25)
        }
        chart.engine?.charge = Float(charge * charge)
        chargeFill.frame.size.width = clearButton.bounds.width * charge
        if !isHolding, charge == 0 {
            link.invalidate()
            chargeLink = nil
            lastChargeTick = nil
        }
    }

    // MARK: Counter

    private func startCounter(to bytes: Double, duration: CFTimeInterval) {
        counter = (shownBytes, bytes, CACurrentMediaTime(), duration)
        if counterLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(counterTick(_:)))
            // A dozen digit changes a second reads as counting; more just keeps the digits in flight.
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 15, preferred: 12)
            link.add(to: .main, forMode: .common)
            counterLink = link
        }
    }

    private func stopCounter() {
        counter = nil
        counterLink?.invalidate()
        counterLink = nil
    }

    @objc private func counterTick(_ link: CADisplayLink) {
        guard let counter else {
            stopCounter()
            return
        }
        let t = min((CACurrentMediaTime() - counter.start) / counter.duration, 1)
        let eased = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
        shownBytes = counter.from + (counter.to - counter.from) * eased
        if t >= 1 {
            shownBytes = counter.to
            stopCounter()
        }
        let text = Self.format(shownBytes)
        if text != shownText {
            shownText = text
            chart.replaceTail(valueSegments(text, tint: nil))
        }
    }

    private static func format(_ bytes: Double) -> String {
        bytes < 1_000 ? "0 B" : ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

/// A legend row: colored checkmark, name, share, size. Toggles like a checkbox.
private final class LegendRow: UIControl {
    private let check = UIImageView()
    private let valueLabel = UILabel()
    private let color: UIColor

    var isOn = true {
        didSet {
            check.image = UIImage(systemName: isOn ? "checkmark.circle.fill" : "circle")
            check.tintColor = isOn ? color : UIColor(white: 1, alpha: 0.3)
        }
    }

    override var isHighlighted: Bool {
        didSet { backgroundColor = isHighlighted ? UIColor(white: 1, alpha: 0.06) : .clear }
    }

    init(color: UIColor, name: String, percent: String, value: String) {
        self.color = color
        super.init(frame: .zero)
        check.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 22)
        check.contentMode = .center
        let title = UILabel()
        let text = NSMutableAttributedString(string: name + " ", attributes: [.foregroundColor: UIColor.white])
        text.append(NSAttributedString(string: percent, attributes: [.foregroundColor: UIColor(white: 1, alpha: 0.45)]))
        title.attributedText = text
        title.font = .systemFont(ofSize: 17)
        valueLabel.text = value
        valueLabel.font = .systemFont(ofSize: 17)
        valueLabel.textColor = UIColor(white: 1, alpha: 0.5)
        let stack = UIStackView(arrangedSubviews: [check, title, UIView(), valueLabel])
        stack.spacing = 14
        stack.alignment = .center
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            check.widthAnchor.constraint(equalToConstant: 26),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        isOn = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setValue(_ text: String) {
        setText(text, on: valueLabel)
    }

    /// A quick pop of the checkmark and a flash of the size in the row's color.
    func pulse() {
        check.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.45, initialSpringVelocity: 0) {
            self.check.transform = .identity
        }
        valueLabel.textColor = color
        UIView.transition(with: valueLabel, duration: 0.6, options: .transitionCrossDissolve) {
            self.valueLabel.textColor = UIColor(white: 1, alpha: 0.5)
        }
    }
}

// MARK: - 2. Bars

private final class BarsChartScene: ChartScene {
    private struct Dataset {
        let labels: [String]
        let values: [Double]
        let caption: String
    }

    private let datasets: [Dataset] = {
        var random = SeededRandom(seed: 21)
        let month = (1...30).map { day -> Double in
            let weekend = day % 7 == 6 || day % 7 == 0
            return (weekend ? 5.5 : 3.4) + Double(random.unit()) * 2.6
        }
        return [
            Dataset(labels: ["M", "T", "W", "T", "F", "S", "S"],
                    values: [3.2, 4.1, 2.7, 5.3, 4.8, 7.4, 6.1], caption: "Daily Average · This Week"),
            Dataset(labels: (1...30).map { $0 % 7 == 1 ? "\($0)" : "" },
                    values: month, caption: "Daily Average · October"),
            Dataset(labels: ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"],
                    values: [3.9, 4.2, 3.6, 4.4, 4.9, 5.6, 6.2, 5.8, 4.7, 4.3, 4.6, 5.4], caption: "Daily Average · 2026"),
        ]
    }()
    private let rangePicker = UISegmentedControl(items: ["Week", "Month", "Year"])
    private let captionLabel = makeLabel(size: 13, weight: .semibold, alpha: 0.5)
    private let valueLabel = makeLabel(size: 36, weight: .bold)
    private let calloutLabel = makeLabel(size: 13, weight: .bold)
    private let hintLabel = makeLabel(size: 13, alpha: 0.5)
    private let grid = CAShapeLayer()
    private var gridLabels: [UILabel] = []
    private var axisLabels: [UILabel] = []
    private var chartRect = CGRect.zero
    private var barRects: [CGRect] = []
    private var selected: Int?

    private var dataset: Dataset { datasets[rangePicker.selectedSegmentIndex] }

    override init(frame: CGRect) {
        super.init(frame: frame)
        rangePicker.selectedSegmentIndex = 0
        rangePicker.addAction(UIAction { [weak self] _ in
            self?.selected = nil
            self?.updateChart(isFirst: false)
        }, for: .valueChanged)
        hintLabel.text = "Switch the range: particles pour from bar to bar"
        grid.strokeColor = UIColor(white: 1, alpha: 0.12).cgColor
        grid.lineWidth = 1
        grid.lineDashPattern = [3, 4]
        layer.insertSublayer(grid, below: chart.layer)
        gridLabels = (0..<3).map { _ in makeLabel(size: 11, weight: .medium, alpha: 0.4, alignment: .left) }
        calloutLabel.alpha = 0
        for subview in [rangePicker, captionLabel, valueLabel, hintLabel, calloutLabel] + gridLabels {
            addSubview(subview)
        }
        chart.onTap = { [weak self] point in self?.tap(at: point) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutScene() {
        let width = bounds.width
        rangePicker.frame = CGRect(x: 16, y: 12, width: width - 32, height: 32)
        captionLabel.frame = CGRect(x: 20, y: 60, width: width - 40, height: 18)
        valueLabel.frame = CGRect(x: 20, y: 80, width: width - 40, height: 42)
        let top: CGFloat = 170
        let height = min(bounds.height - top - 90 - safeAreaInsets.bottom, 340)
        chartRect = CGRect(x: 20, y: top, width: width - 64, height: max(height, 120))
        hintLabel.frame = CGRect(x: 16, y: chartRect.maxY + 40, width: width - 32, height: 18)
    }

    override func updateChart(isFirst: Bool) {
        let dataset = dataset
        let scaleMax = (dataset.values.max() ?? 1) <= 8 ? 8.0 : 12.0
        let spacing: CGFloat = dataset.values.count > 12 ? 3 : 10
        barRects = ChartLayout.bars(in: chartRect, values: dataset.values, maxValue: scaleMax, spacing: spacing)
        let counts = ParticleChartView.split(chart.particleCount, weights: dataset.values)
        let rect = chartRect
        let low = ParticleChartsPalette.cyan.particleSIMD, high = ParticleChartsPalette.purple.particleSIMD
        let segments = barRects.enumerated().map { index, bar in
            let alpha: Float = selected == nil || selected == index ? 1 : 0.28
            return ParticleChartSegment(path: UIBezierPath(roundedRect: bar, cornerRadius: min(bar.width / 2, 7)),
                                        count: counts[index], color: { point in
                // Teal at the floor, violet up high: tall bars reach the hot end.
                let t = Float((rect.maxY - CGFloat(point.y)) / rect.height)
                var color = low + (high - low) * t
                color.w = alpha
                return color
            }, order: { -$0.y })
        }
        chart.show(segments, from: isFirst ? CGRect(x: rect.minX, y: rect.maxY - 2, width: rect.width, height: 2) : nil)

        // Grid lines at 0, half and the top of the scale.
        let gridPath = UIBezierPath()
        for (index, label) in gridLabels.enumerated() {
            let y = chartRect.maxY - chartRect.height * CGFloat(index) / 2
            gridPath.move(to: CGPoint(x: chartRect.minX, y: y))
            gridPath.addLine(to: CGPoint(x: chartRect.maxX, y: y))
            label.text = "\(Int(scaleMax) * index / 2)h"
            label.frame = CGRect(x: chartRect.maxX + 8, y: y - 8, width: 36, height: 16)
        }
        grid.path = gridPath.cgPath

        axisLabels.forEach { $0.removeFromSuperview() }
        axisLabels = zip(dataset.labels, barRects).map { text, bar in
            let label = makeLabel(size: 12, weight: .medium, alpha: 0.5)
            label.text = text
            label.frame = CGRect(x: bar.midX - 20, y: chartRect.maxY + 8, width: 40, height: 16)
            label.alpha = 0
            addSubview(label)
            return label
        }
        UIView.animate(withDuration: 0.35) { self.axisLabels.forEach { $0.alpha = 1 } }

        let average = dataset.values.reduce(0, +) / Double(dataset.values.count)
        setText(selected.map { Self.format(dataset.values[$0]) } ?? Self.format(average), on: valueLabel)
        setText(selected == nil ? dataset.caption : "Selected", on: captionLabel)
        if let selected {
            let bar = barRects[selected]
            calloutLabel.text = Self.format(dataset.values[selected])
            calloutLabel.frame = CGRect(x: bar.midX - 40, y: bar.minY - 26, width: 80, height: 18)
        }
        UIView.animate(withDuration: 0.25) { self.calloutLabel.alpha = self.selected == nil ? 0 : 1 }
    }

    private func tap(at point: CGPoint) {
        let hit = barRects.firstIndex { bar in
            point.x >= bar.minX - 5 && point.x <= bar.maxX + 5 && point.y >= chartRect.minY - 30 && point.y <= chartRect.maxY + 20
        }
        selected = hit == selected ? nil : hit
        UISelectionFeedbackGenerator().selectionChanged()
        updateChart(isFirst: false)
    }

    private static func format(_ hours: Double) -> String {
        let minutes = Int((hours * 60).rounded())
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}

// MARK: - 3. Line

private final class LineChartScene: ChartScene {
    private struct Range {
        let title: String
        let values: [Double]
    }

    private let ranges: [Range] = {
        func walk(seed: UInt64, drift: Double, volatility: Double) -> [Double] {
            var random = SeededRandom(seed: seed)
            var value = 100.0
            var values: [Double] = []
            for _ in 0..<64 {
                values.append(value)
                value *= 1 + drift + volatility * Double(random.unit() * 2 - 1)
            }
            let scale = 187.42 / values[values.count - 1]   // every range ends at today's price
            return values.map { $0 * scale }
        }
        return [
            Range(title: "1D", values: walk(seed: 3, drift: -0.0006, volatility: 0.005)),
            Range(title: "1W", values: walk(seed: 5, drift: 0.001, volatility: 0.01)),
            Range(title: "1M", values: walk(seed: 9, drift: -0.001, volatility: 0.016)),
            Range(title: "1Y", values: walk(seed: 14, drift: 0.007, volatility: 0.03)),
        ]
    }()
    private lazy var rangePicker = UISegmentedControl(items: ranges.map(\.title))
    private let nameLabel = makeLabel(size: 15, weight: .semibold, alpha: 0.55, alignment: .left)
    private let priceLabel = makeLabel(size: 40, weight: .bold, alignment: .left)
    private let changeLabel = makeLabel(size: 17, weight: .semibold, alignment: .left)
    private let hintLabel = makeLabel(size: 13, alpha: 0.5)
    private let crosshair = UIView()
    private let dot = UIView()
    private let scrubLabel = makeLabel(size: 12, weight: .semibold, alpha: 0.7)
    private var chartRect = CGRect.zero
    private var line: ChartLayout.Line?

    private var values: [Double] { ranges[rangePicker.selectedSegmentIndex].values }

    override init(frame: CGRect) {
        super.init(frame: frame)
        nameLabel.text = "PRTCL · Particle Inc."
        hintLabel.text = "Drag across the chart to scrub"
        rangePicker.selectedSegmentIndex = 1
        rangePicker.addAction(UIAction { [weak self] _ in self?.updateChart(isFirst: false) }, for: .valueChanged)
        crosshair.backgroundColor = UIColor(white: 1, alpha: 0.35)
        dot.backgroundColor = .white
        dot.layer.cornerRadius = 6
        dot.layer.borderWidth = 3
        for view in [crosshair, dot, scrubLabel] {
            view.alpha = 0
        }
        for subview in [nameLabel, priceLabel, changeLabel, rangePicker, hintLabel, crosshair, dot, scrubLabel] {
            addSubview(subview)
        }
        chart.engine?.touchRadius = 34
        chart.engine?.touchPower = 5000
        chart.onTouch = { [weak self] point in self?.scrub(to: point) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutScene() {
        let width = bounds.width
        nameLabel.frame = CGRect(x: 20, y: 12, width: width - 40, height: 20)
        priceLabel.frame = CGRect(x: 20, y: 34, width: width - 40, height: 46)
        changeLabel.frame = CGRect(x: 20, y: 82, width: width - 40, height: 22)
        let top: CGFloat = 150
        let height = min(bounds.height - top - 120 - safeAreaInsets.bottom, 320)
        chartRect = CGRect(x: 12, y: top, width: width - 24, height: max(height, 120))
        rangePicker.frame = CGRect(x: 16, y: chartRect.maxY + 30, width: width - 32, height: 32)
        hintLabel.frame = CGRect(x: 16, y: rangePicker.frame.maxY + 14, width: width - 32, height: 18)
    }

    override func updateChart(isFirst: Bool) {
        let values = values
        let line = ChartLayout.line(values, in: chartRect)
        self.line = line
        let accent = (values.last ?? 0) >= (values.first ?? 0) ? ParticleChartsPalette.green : ParticleChartsPalette.red
        let counts = ParticleChartView.split(chart.particleCount, weights: [0.3, 0.7])
        let floor = Float(chartRect.maxY)
        let base = accent.particleSIMD
        let segments = [
            // The stroke is far denser than the area, so it glows white-hot even when dimmed.
            ParticleChartSegment(path: line.stroke, lineWidth: 3, count: counts[0], color: accent, alpha: 0.45,
                                 order: { $0.x }),
            ParticleChartSegment(path: line.area, count: counts[1], color: { point in
                // Bright right under the curve, fading towards the floor.
                let curve = Float(line.y(at: CGFloat(point.x)))
                let t = min(max((point.y - curve) / max(floor - curve, 1), 0), 1)
                var color = base
                color.w = 0.04 + 0.6 * (1 - t) * (1 - t)
                return color
            }, order: { $0.x }),
        ]
        chart.show(segments, from: isFirst ? CGRect(x: chartRect.minX, y: chartRect.midY, width: chartRect.width, height: 1) : nil)
        dot.layer.borderColor = accent.cgColor
        showPrice(at: values.count - 1)
    }

    private func scrub(to point: CGPoint?) {
        guard let point, let line else {
            UIView.animate(withDuration: 0.2) { [crosshair, dot, scrubLabel] in
                for view in [crosshair, dot, scrubLabel] { view.alpha = 0 }
            }
            showPrice(at: values.count - 1)
            return
        }
        let x = min(max(point.x, chartRect.minX), chartRect.maxX)
        crosshair.frame = CGRect(x: x - 0.5, y: chartRect.minY - 10, width: 1, height: chartRect.height + 10)
        dot.frame = CGRect(x: x - 6, y: line.y(at: x) - 6, width: 12, height: 12)
        let index = Int(((x - chartRect.minX) / chartRect.width * CGFloat(values.count - 1)).rounded())
        scrubLabel.text = timeLabel(at: index)
        scrubLabel.frame = CGRect(x: min(max(x - 50, 4), bounds.width - 104), y: chartRect.minY - 30, width: 100, height: 16)
        for view in [crosshair, dot, scrubLabel] {
            view.alpha = 1
        }
        showPrice(at: index)
    }

    private func showPrice(at index: Int) {
        let values = values
        let price = values[index], first = values[0]
        priceLabel.text = String(format: "$%.2f", price)
        let change = price - first
        changeLabel.text = String(format: "%@%.2f (%.2f%%)", change >= 0 ? "+" : "−", abs(change), abs(change) / first * 100)
        changeLabel.textColor = change >= 0 ? ParticleChartsPalette.green : ParticleChartsPalette.red
    }

    private func timeLabel(at index: Int) -> String {
        let fraction = Double(index) / Double(values.count - 1)
        switch rangePicker.selectedSegmentIndex {
        case 0:
            let minutes = 9 * 60 + 30 + Int(fraction * 390)
            return String(format: "%d:%02d", minutes / 60, minutes % 60)
        case 1:
            return ["Mon", "Tue", "Wed", "Thu", "Fri"][min(Int(fraction * 5), 4)]
        case 2:
            return "Oct \(1 + Int(fraction * 21))"
        default:
            return Calendar.current.shortMonthSymbols[(10 + Int(fraction * 11.99)) % 12]
        }
    }
}

// MARK: - 4. Morph between chart types

private final class MorphChartScene: ChartScene {
    private enum Kind: CaseIterable {
        case donut, bars, treemap, waffle

        var symbol: String {
            switch self {
            case .donut: "chart.pie.fill"
            case .bars: "chart.bar.fill"
            case .treemap: "square.split.2x2.fill"
            case .waffle: "square.grid.3x3.fill"
            }
        }
    }

    private let categories: [(name: String, value: Double, color: UIColor)] = [
        ("Housing", 1450, ParticleChartsPalette.blue),
        ("Food", 620, ParticleChartsPalette.orange),
        ("Travel", 510, ParticleChartsPalette.purple),
        ("Transport", 380, ParticleChartsPalette.cyan),
        ("Fun", 290, ParticleChartsPalette.pink),
        ("Health", 240, ParticleChartsPalette.green),
        ("Other", 180, ParticleChartsPalette.yellow),
    ]
    private lazy var counts = ParticleChartView.split(chart.particleCount, weights: categories.map(\.value))
    private let kindPicker = UISegmentedControl(items: Kind.allCases.map { UIImage(systemName: $0.symbol) as Any })
    private let playButton = UIButton(configuration: .gray())
    private let titleLabel = makeLabel(size: 15, weight: .semibold, alpha: 0.55)
    private let totalLabel = makeLabel(size: 34, weight: .bold)
    private let legend = UIStackView()
    private var chartRect = CGRect.zero
    private var autoplay: Timer?

    private var kind: Kind { Kind.allCases[kindPicker.selectedSegmentIndex] }

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.text = "October Budget"
        totalLabel.text = "$" + Int(categories.reduce(0) { $0 + $1.value }).formatted(.number)
        kindPicker.selectedSegmentIndex = 0
        kindPicker.addAction(UIAction { [weak self] _ in self?.updateChart(isFirst: false) }, for: .valueChanged)
        playButton.configuration?.image = UIImage(systemName: "play.fill")
        playButton.configuration?.cornerStyle = .capsule
        playButton.addAction(UIAction { [weak self] _ in self?.toggleAutoplay() }, for: .touchUpInside)

        legend.axis = .vertical
        legend.spacing = 8
        legend.alignment = .center
        for rowItems in [categories.prefix(4), categories.suffix(3)] {
            let row = UIStackView(arrangedSubviews: rowItems.map { Self.chip($0.name, color: $0.color) })
            row.spacing = 14
            legend.addArrangedSubview(row)
        }
        for subview in [titleLabel, totalLabel, kindPicker, playButton, legend] {
            addSubview(subview)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            autoplay?.invalidate()
            autoplay = nil
        }
    }

    override func layoutScene() {
        let width = bounds.width
        titleLabel.frame = CGRect(x: 16, y: 12, width: width - 32, height: 20)
        totalLabel.frame = CGRect(x: 16, y: 32, width: width - 32, height: 40)
        let side = min(width - 48, bounds.height - 260 - safeAreaInsets.bottom)
        chartRect = CGRect(x: (width - side) / 2, y: 96, width: side, height: side)
        kindPicker.frame = CGRect(x: 16, y: chartRect.maxY + 28, width: width - 32 - 52, height: 36)
        playButton.frame = CGRect(x: width - 16 - 40, y: kindPicker.frame.minY - 2, width: 40, height: 40)
        let legendSize = legend.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        legend.frame = CGRect(x: (width - legendSize.width) / 2, y: kindPicker.frame.maxY + 22,
                              width: legendSize.width, height: legendSize.height)
    }

    override func updateChart(isFirst: Bool) {
        let rect = chartRect
        let values = categories.map(\.value)
        let paths: [UIBezierPath?]
        var order: (SIMD2<Float>) -> Float = { -$0.y }
        switch kind {
        case .donut:
            let center = CGPoint(x: rect.midX, y: rect.midY)
            paths = ChartLayout.donut(center: center, innerRadius: rect.width * 0.27, outerRadius: rect.width * 0.48,
                                      shares: values)
            order = { ChartLayout.clockAngle($0, center: center) }
        case .bars:
            let area = rect.insetBy(dx: 0, dy: rect.height * 0.08)
            paths = ChartLayout.bars(in: area, values: values, maxValue: values.max() ?? 1, spacing: 8)
                .map { UIBezierPath(roundedRect: $0, cornerRadius: 8) }
        case .treemap:
            paths = ChartLayout.treemap(values, in: rect)
                .map { UIBezierPath(roundedRect: $0.insetBy(dx: 3, dy: 3), cornerRadius: 12) }
        case .waffle:
            paths = ChartLayout.waffle(in: rect, columns: 10, rows: 10, weights: values)
        }
        let segments = categories.indices.map { index in
            let base = categories[index].color.particleSIMD
            return ParticleChartSegment(path: paths[index], count: counts[index], color: { point in
                lightened(base, 0.25 * (1 - Float((CGFloat(point.y) - rect.minY) / rect.height)))
            }, order: order)
        }
        chart.show(segments, from: isFirst ? CGRect(x: rect.midX - 4, y: rect.midY - 4, width: 8, height: 8) : nil)
    }

    private func toggleAutoplay() {
        if let autoplay {
            autoplay.invalidate()
            self.autoplay = nil
        } else {
            advance()
            autoplay = Timer.scheduledTimer(withTimeInterval: 2.4, repeats: true) { [weak self] _ in self?.advance() }
        }
        playButton.configuration?.image = UIImage(systemName: autoplay == nil ? "play.fill" : "pause.fill")
    }

    private func advance() {
        kindPicker.selectedSegmentIndex = (kindPicker.selectedSegmentIndex + 1) % Kind.allCases.count
        updateChart(isFirst: false)
    }

    private static func chip(_ name: String, color: UIColor) -> UIView {
        let dot = UIView()
        dot.backgroundColor = color
        dot.layer.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([dot.widthAnchor.constraint(equalToConstant: 8), dot.heightAnchor.constraint(equalToConstant: 8)])
        let label = makeLabel(size: 13, weight: .medium, alpha: 0.75)
        label.text = name
        let stack = UIStackView(arrangedSubviews: [dot, label])
        stack.spacing = 6
        stack.alignment = .center
        return stack
    }
}
