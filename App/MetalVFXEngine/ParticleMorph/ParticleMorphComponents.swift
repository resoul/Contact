//
//  ParticleMorphComponents.swift
//  controller
//
//  The six ParticleMorphEngine scenarios as drop-in UIKit components.
//

import UIKit
import ParticleTypes

private extension UIColor {
    func mixed(with other: UIColor, _ t: CGFloat) -> UIColor {
        let a = particleSIMD, b = other.particleSIMD
        let m = a + (b - a) * Float(min(max(t, 0), 1))
        return UIColor(red: CGFloat(m.x), green: CGFloat(m.y), blue: CGFloat(m.z), alpha: CGFloat(m.w))
    }
}

private func makeParticles(
    at positions: [SIMD2<Float>],
    targets: [SIMD2<Float>]? = nil,
    colors: [SIMD4<Float>]? = nil,
    color: UIColor = .white,
    size: Float,
    seed: UInt64
) -> [Particle] {
    var random = SeededRandom(seed: seed)
    let fallback = color.particleSIMD
    return positions.indices.map { i in
        Particle(currentPosition: positions[i], targetPosition: targets?[i] ?? positions[i],
                 startPosition: positions[i], velocity: .zero, color: colors?[i] ?? fallback,
                 targetColor: colors?[i] ?? fallback, size: size, seed: random.unit(), stiffness: 1)
    }
}

// MARK: - Module 1: paywall success morph

/// Dissolves a pay button into a vortex of particles that reassemble into a checkmark.
final class PaywallSuccessAnimator {
    let button: UIView
    /// Where the particles are drawn; big enough for the blast. Defaults to the button's superview.
    weak var container: UIView?
    var particleCount = 30_000
    var duration: TimeInterval = 1.8
    var checkmarkSize: CGFloat = 120
    var successColor = UIColor(red: 0.3, green: 1.0, blue: 0.55, alpha: 1)
    /// Checkmark as SVG path data in a 100 × 100 box.
    var checkmarkSVG = "M 16 54 L 40 77 L 86 26"
    private(set) var engine: ParticleMorphEngine?

    init(button: UIView, container: UIView? = nil) {
        self.button = button
        self.container = container ?? button.superview
    }

    /// Call when the server confirms the payment. `onSuccess` runs once the checkmark has formed.
    func trigger(onSuccess: @escaping () -> Void) {
        guard engine == nil, let container,
              let engine = ParticleMorphEngine(mode: ParticleModePaywall, frame: container.bounds) else { return }
        let buttonFrame = button.convert(button.bounds, to: container)

        // State A: the button itself, colors included.
        let source = SVGToParticleConverter.samples(from: SVGToParticleConverter.snapshot(of: button),
                                                    count: particleCount, in: buttonFrame)
        // State B: points along the checkmark's stroke, centered on the button.
        let checkmark = SVGToParticleConverter.path(fromSVG: checkmarkSVG)
        let scale = checkmarkSize / 100
        checkmark.apply(CGAffineTransform(translationX: buttonFrame.midX - checkmarkSize / 2,
                                          y: buttonFrame.midY - checkmarkSize / 2).scaledBy(x: scale, y: scale))
        let lineWidth = 11 * scale
        let targets = SVGToParticleConverter.points(from: checkmark, count: source.count, lineWidth: lineWidth)
        guard !source.isEmpty, targets.count == source.count else { return }
        let buttonArea = buttonFrame.width * buttonFrame.height
        let checkmarkArea = max(SVGToParticleConverter.area(of: checkmark, lineWidth: lineWidth), 1)

        let pointSize: Float = 2.4
        engine.load(makeParticles(at: source.map(\.position), targets: targets, colors: source.map(\.color),
                                  size: pointSize, seed: 11))
        engine.effectBounds = buttonFrame
        // The checkmark packs the same particles into a much smaller area; dim each one so it glows
        // a few times brighter than a solid fill (white-hot core, colored rim) instead of pure white.
        engine.colorB = successColor.withAlphaComponent(min(1, 2.5 * checkmarkArea / buttonArea))
        engine.noiseStrength = 260
        engine.intensity = ParticleMorphEngine.balancedIntensity(count: source.count, area: buttonArea,
                                                                 pointSize: CGFloat(pointSize))
        engine.view.frame = container.bounds
        engine.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(engine.view)
        self.engine = engine

        button.alpha = 0
        engine.animate(.progress, to: 1, duration: duration, timing: .linear) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onSuccess()
        }
    }

    /// Removes the particles and shows the button again.
    func reset() {
        engine?.view.removeFromSuperview()
        engine = nil
        button.alpha = 1
    }
}

// MARK: - Module 2: tab bar icon morph

/// One tab: a symbol and a title. While selected, its icon is drawn by the bar's particles.
final class MorphingTabBarItem: UIView {
    static let iconPointSize: CGFloat = 24

    let symbolName: String
    let accentColor: UIColor
    let iconView = UIImageView()
    let titleLabel = UILabel()
    var onTap: (() -> Void)?

    var isSelected = false {
        didSet { updateAppearance() }
    }

    /// The symbol as an alpha mask, sized like the visible icon.
    var iconImage: UIImage? {
        UIImage(systemName: symbolName,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: Self.iconPointSize, weight: .semibold))
    }

    init(symbolName: String, title: String, accentColor: UIColor) {
        self.symbolName = symbolName
        self.accentColor = accentColor
        super.init(frame: .zero)

        iconView.image = iconImage
        iconView.contentMode = .center
        iconView.tintColor = UIColor(white: 0.55, alpha: 1)
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        titleLabel.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [iconView, titleLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 2
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 30),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func handleTap() {
        onTap?()
    }

    private func updateAppearance() {
        UIView.animate(withDuration: 0.25) {
            self.iconView.alpha = self.isSelected ? 0 : 1
        }
        titleLabel.textColor = isSelected ? accentColor : UIColor(white: 0.55, alpha: 1)
    }

    /// Where the symbol's pixels are, in `view`'s coordinates.
    func iconRect(in view: UIView) -> CGRect {
        let size = iconImage?.size ?? CGSize(width: Self.iconPointSize, height: Self.iconPointSize)
        let frame = iconView.convert(iconView.bounds, to: view)
        return CGRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height)
    }
}

/// A tab bar whose active icon flows as sparks along a Bézier arc into the newly selected icon.
final class MorphingTabBar: UIView {
    let items: [MorphingTabBarItem]
    private(set) var selectedIndex = 0
    var particlesPerIcon = 20_000
    /// Arc height of the toss, in points.
    var arcHeight: Float = 30
    var morphDuration: TimeInterval = 0.7
    var onSelect: ((Int) -> Void)?

    let engine: ParticleMorphEngine?
    private let stack = UIStackView()
    private var loadedSize: CGSize = .zero
    /// The particles may fly this far above the bar.
    private let overflow: CGFloat = 80

    init(items: [MorphingTabBarItem]) {
        self.items = items
        engine = ParticleMorphEngine(mode: ParticleModeTabBar)
        super.init(frame: .zero)
        backgroundColor = UIColor(white: 0.07, alpha: 0.96)
        clipsToBounds = false

        let hairline = UIView()
        hairline.backgroundColor = UIColor(white: 1, alpha: 0.08)
        hairline.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hairline)
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            hairline.topAnchor.constraint(equalTo: topAnchor),
            hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 0.5),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalToConstant: 58),
        ])
        for (index, item) in items.enumerated() {
            item.onTap = { [weak self] in self?.select(index) }
            stack.addArrangedSubview(item)
        }
        items.first?.isSelected = true
        if let engine {
            engine.noiseStrength = 7
            engine.progress = 1
            engine.colorA = items.first?.accentColor ?? .white
            engine.colorB = engine.colorA
            addSubview(engine.view)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let engine else { return }
        engine.view.frame = CGRect(x: 0, y: -overflow, width: bounds.width, height: bounds.height + overflow)
        if bounds.size != loadedSize, bounds.width > 0 {
            loadedSize = bounds.size
            stack.layoutIfNeeded()
            let points = iconPoints(selectedIndex)
            engine.load(makeParticles(at: points, size: 1.6, seed: 21))
            engine.intensity = ParticleMorphEngine.balancedIntensity(count: points.count, area: 26 * 22, pointSize: 1.6) * 0.6
            settle()
        }
    }

    func select(_ index: Int) {
        guard index != selectedIndex, items.indices.contains(index), let engine else { return }
        let from = selectedIndex
        selectedIndex = index
        items.enumerated().forEach { $0.element.isSelected = $0.offset == index }

        // Start from wherever the sparks are now, even if the previous morph is still running.
        engine.colorA = engine.colorA.mixed(with: engine.colorB, CGFloat(engine.progress))
        engine.colorB = items[index].accentColor
        engine.retarget(targets: iconPoints(index), commitCurrentAsStart: true)
        // The arc bends with the direction of travel: up when moving right, down when moving left.
        engine.arcHeight = index > from ? -arcHeight : arcHeight
        engine.progress = 0
        engine.animate(.progress, to: 1, duration: morphDuration, timing: .linear) { [weak self] in
            self?.engine?.isPaused = true   // static icon: no need to simulate until the next switch
        }
        UISelectionFeedbackGenerator().selectionChanged()
        onSelect?(index)
    }

    private func settle() {
        engine?.animate(.progress, to: 1, duration: 0.05) { [weak self] in
            self?.engine?.isPaused = true
        }
    }

    private func iconPoints(_ index: Int) -> [SIMD2<Float>] {
        guard let engine, let image = items[index].iconImage else { return [] }
        let rect = items[index].iconRect(in: engine.view)
        let points = SVGToParticleConverter.samples(from: image, count: particlesPerIcon, in: rect,
                                                    seed: UInt64(index + 1)).map(\.position)
        return points.count == particlesPerIcon ? points : Array(repeating: SIMD2(Float(rect.midX), Float(rect.midY)),
                                                                 count: particlesPerIcon)
    }
}

// MARK: - Module 3: AI voice sphere → text

/// A sphere of particles that pulses with the voice, then snaps into the assistant's answer.
final class VoiceAssistantParticleView: UIView {
    var particleCount = 60_000
    var sphereRadius: CGFloat = 110
    var textFont = UIFont.systemFont(ofSize: 52, weight: .heavy)
    /// How long the particles take to stop oscillating and form the letters.
    var morphDuration: TimeInterval = 0.3
    /// Voice level, 0…1 (e.g. from an AVAudioRecorder meter). Smoothed with a fast attack / slow release.
    var audioVolume: Float = 0

    let engine: ParticleMorphEngine?
    private(set) var isShowingText = false
    private var loadedSize: CGSize = .zero

    override init(frame: CGRect) {
        engine = ParticleMorphEngine(mode: ParticleModeVoice)
        super.init(frame: frame)
        guard let engine else { return }
        engine.colorA = UIColor(red: 0.2, green: 0.45, blue: 1.0, alpha: 1)
        engine.colorB = UIColor(red: 0.35, green: 0.95, blue: 1.0, alpha: 1)
        engine.onFrame = { [weak self] engine, deltaTime in
            guard let self else { return }
            let rate: Float = self.audioVolume > engine.audioVolume ? 25 : 5
            engine.audioVolume += (self.audioVolume - engine.audioVolume) * min(rate * Float(deltaTime), 1)
        }
        addSubview(engine.view)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let engine else { return }
        engine.view.frame = bounds
        engine.effectBounds = CGRect(x: bounds.midX - sphereRadius, y: bounds.midY - sphereRadius,
                                     width: sphereRadius * 2, height: sphereRadius * 2)
        if bounds.size != loadedSize, bounds.width > 0 {
            loadedSize = bounds.size
            let center = SIMD2(Float(bounds.midX), Float(bounds.midY))
            let points = Array(repeating: center, count: particleCount)
            engine.load(makeParticles(at: points, size: 2.2, seed: 31))
            engine.intensity = ParticleMorphEngine.balancedIntensity(count: particleCount,
                                                                     area: .pi * sphereRadius * sphereRadius * 2,
                                                                     pointSize: 2.2) * 0.7
            isShowingText = false
            engine.progress = 0
        }
    }

    /// Back to the listening sphere.
    func showSphere(completion: (() -> Void)? = nil) {
        isShowingText = false
        engine?.animate(.progress, to: 0, duration: morphDuration, timing: .linear, completion: completion)
    }

    /// Lines up the particles into `text` ("\n" for several lines).
    func show(text: String) {
        guard let engine else { return }
        if isShowingText {
            showSphere { [weak self] in self?.show(text: text) }
            return
        }
        let area = bounds.insetBy(dx: 24, dy: 0)
        let box = CGRect(x: area.minX, y: bounds.midY - 110, width: area.width, height: 220)
        let points = SVGToParticleConverter.points(fromText: text, font: textFont, count: particleCount, fitting: box)
        guard points.count == particleCount else { return }
        isShowingText = true
        engine.retarget(targets: points)
        engine.animate(.progress, to: 1, duration: morphDuration, timing: .linear)
    }
}

// MARK: - Module 4: Thanos snap & revert

/// A card that crumbles into dust blown away to the right, and can be blown back together.
/// Put your content inside it like in any UIView. The dust is drawn in the card's superview.
final class DisintegratingCardView: UIView {
    var particleCount = 70_000
    var duration: TimeInterval = 2.2
    var revertDuration: TimeInterval = 1.4
    private(set) var isDisintegrated = false
    private(set) var engine: ParticleMorphEngine?

    func disintegrate(completion: (() -> Void)? = nil) {
        guard !isDisintegrated else { return }
        isDisintegrated = true
        if let engine {   // reversing right now: just turn the wind around again
            engine.animate(.progress, to: 1, duration: duration * Double(1 - engine.progress), timing: .linear,
                           completion: completion)
            return
        }
        guard let container = superview,
              let engine = ParticleMorphEngine(mode: ParticleModeThanos, frame: container.bounds) else { return }
        let frame = convert(bounds, to: container)
        let samples = SVGToParticleConverter.samples(from: SVGToParticleConverter.snapshot(of: self),
                                                     count: particleCount, in: frame, distribution: .grid)
        // Grid cells are `spacing` apart; squares slightly larger than a cell leave no seams.
        let spacing = Float((frame.width * frame.height / CGFloat(max(particleCount, 1))).squareRoot())
        engine.load(makeParticles(at: samples.map(\.position), colors: samples.map(\.color), size: spacing * 1.15, seed: 41))
        engine.style = .solid
        engine.effectBounds = frame
        engine.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.insertSubview(engine.view, aboveSubview: self)
        self.engine = engine

        alpha = 0
        engine.animate(.progress, to: 1, duration: duration, timing: .linear) {
            engine.isPaused = true
            completion?()
        }
    }

    /// Undo: the wind reverses and the dust flies back into the card.
    func revert(completion: (() -> Void)? = nil) {
        guard isDisintegrated, let engine else { return }
        isDisintegrated = false
        engine.animate(.progress, to: 0, duration: revertDuration * Double(max(engine.progress, 0.3)),
                       timing: .easeOut) { [weak self] in
            guard let self else { return }
            self.alpha = 1
            self.engine?.view.removeFromSuperview()
            self.engine = nil
            completion?()
        }
    }
}

// MARK: - Module 5: magnetic badge

/// A badge made of particles: the finger pushes them away, and they spring back when released.
final class MagneticBadgeView: UIView {
    var particleCount = 40_000
    var badgeSize: CGFloat = 260
    var badgeImage: UIImage = MagneticBadgeView.makeVIPBadge(size: 260)

    let engine: ParticleMorphEngine?
    private var loadedSize: CGSize = .zero

    override init(frame: CGRect) {
        engine = ParticleMorphEngine(mode: ParticleModeBadge)
        super.init(frame: frame)
        isMultipleTouchEnabled = false
        guard let engine else { return }
        engine.touchRadius = 85
        engine.touchPower = 9000
        addSubview(engine.view)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let engine else { return }
        engine.view.frame = bounds
        guard bounds.size != loadedSize, bounds.width > 0 else { return }
        loadedSize = bounds.size
        let rect = CGRect(x: bounds.midX - badgeSize / 2, y: bounds.midY - badgeSize / 2, width: badgeSize, height: badgeSize)
        engine.effectBounds = rect
        let samples = SVGToParticleConverter.samples(from: badgeImage, count: particleCount, in: rect)
        engine.load(makeParticles(at: samples.map(\.position), colors: samples.map(\.color), size: 1.8, seed: 51))
        engine.intensity = ParticleMorphEngine.balancedIntensity(count: samples.count, area: badgeSize * badgeSize * 0.42,
                                                                 pointSize: 1.8)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        engine?.touchPosition = touches.first?.location(in: self)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        engine?.touchPosition = touches.first?.location(in: self)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        engine?.touchPosition = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        engine?.touchPosition = nil
    }

    /// Gold ring, crown and "VIP" on a transparent background (only drawn pixels become particles).
    static func makeVIPBadge(size: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 2
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { context in
            let cg = context.cgContext
            let bounds = CGRect(x: 0, y: 0, width: size, height: size)
            let gold = [UIColor(red: 1.0, green: 0.86, blue: 0.45, alpha: 1).cgColor,
                        UIColor(red: 0.95, green: 0.55, blue: 0.15, alpha: 1).cgColor,
                        UIColor(red: 1.0, green: 0.35, blue: 0.55, alpha: 1).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: gold as CFArray,
                                      locations: [0, 0.55, 1])!

            // Outer ring with a gradient.
            let ring = UIBezierPath(ovalIn: bounds.insetBy(dx: size * 0.04, dy: size * 0.04))
            cg.saveGState()
            cg.addPath(ring.cgPath.copy(strokingWithWidth: size * 0.055, lineCap: .round, lineJoin: .round, miterLimit: 1))
            cg.clip()
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size, y: size), options: [])
            cg.restoreGState()

            // Dotted inner ring.
            let dots = UIBezierPath(ovalIn: bounds.insetBy(dx: size * 0.12, dy: size * 0.12))
            dots.lineWidth = size * 0.012
            dots.setLineDash([size * 0.004, size * 0.03], count: 2, phase: 0)
            dots.lineCapStyle = .round
            UIColor(red: 1.0, green: 0.8, blue: 0.5, alpha: 0.9).setStroke()
            dots.stroke()

            // Crown.
            let crown = UIImage(systemName: "crown.fill",
                                withConfiguration: UIImage.SymbolConfiguration(pointSize: size * 0.26, weight: .bold))?
                .withTintColor(UIColor(red: 1.0, green: 0.78, blue: 0.3, alpha: 1), renderingMode: .alwaysOriginal)
            if let crown {
                crown.draw(at: CGPoint(x: (size - crown.size.width) / 2, y: size * 0.22))
            }

            // "VIP".
            let font = UIFont.systemFont(ofSize: size * 0.2, weight: .black)
            let text = NSAttributedString(string: "VIP", attributes: [
                .font: font,
                .foregroundColor: UIColor(red: 1.0, green: 0.95, blue: 0.85, alpha: 1),
                .kern: size * 0.01,
            ])
            let textSize = text.size()
            text.draw(at: CGPoint(x: (size - textSize.width) / 2, y: size * 0.52))
        }
    }
}

// MARK: - Module 6: morphing progress loader

/// "0%" → "50%" → "100%" drawn by particles, which then collapse into the content card.
final class MorphingProgressLoaderView: UIView {
    var particleCount = 50_000
    var cardSize = CGSize(width: 320, height: 190)
    var cardColor = UIColor(red: 0.36, green: 0.3, blue: 0.95, alpha: 1)
    /// Shown in the card's place once loading has finished.
    let contentView = UIView()

    let engine: ParticleMorphEngine?
    private(set) var progress: Float = 0
    private var loadedSize: CGSize = .zero

    override init(frame: CGRect) {
        engine = ParticleMorphEngine(mode: ParticleModeLoader)
        super.init(frame: frame)
        contentView.alpha = 0
        addSubview(contentView)
        guard let engine else { return }
        engine.colorA = UIColor(red: 0.3, green: 0.9, blue: 1.0, alpha: 1)
        engine.noiseStrength = 14
        addSubview(engine.view)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var cardFrame: CGRect {
        CGRect(x: bounds.midX - cardSize.width / 2, y: bounds.midY - cardSize.height / 2,
               width: cardSize.width, height: cardSize.height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentView.frame = cardFrame
        guard let engine else { return }
        engine.view.frame = bounds
        guard bounds.size != loadedSize, bounds.width > 0 else { return }
        loadedSize = bounds.size

        let font = UIFont.systemFont(ofSize: 120, weight: .heavy)
        let box = CGRect(x: 20, y: bounds.midY - 90, width: bounds.width - 40, height: 180)
        let frames = ["0%", "50%", "100%"].enumerated().map { index, text in
            SVGToParticleConverter.points(fromText: text, font: font, count: particleCount, fitting: box, seed: UInt64(index + 1))
        }
        let card = SVGToParticleConverter.points(from: UIBezierPath(roundedRect: cardFrame, cornerRadius: 24),
                                                 count: particleCount, seed: 9)
        guard frames.allSatisfy({ $0.count == particleCount }), card.count == particleCount else { return }
        engine.load(makeParticles(at: frames[0], size: 2.0, seed: 61))
        engine.setKeyframes(frames + [card])
        engine.colorB = cardColor
        engine.intensity = ParticleMorphEngine.balancedIntensity(count: particleCount,
                                                                 area: cardSize.width * cardSize.height, pointSize: 2) * 1.2
    }

    /// Loading progress 0…1; the particles morph continuously towards it.
    func setProgress(_ value: Float, animated: Bool = true) {
        progress = min(max(value, 0), 1)
        engine?.animate(.progress, to: progress, duration: animated ? 0.35 : 0.001, timing: .easeOut)
    }

    /// Completes the bar and collapses the particles into the card, then reveals `contentView`.
    func finish(completion: (() -> Void)? = nil) {
        guard let engine else { return }
        setProgress(1)
        engine.animate(.stage, to: 1, duration: 1.3, timing: .easeInOut) { [weak self] in
            guard let self else { return }
            UIView.animate(withDuration: 0.35, animations: {
                self.contentView.alpha = 1
                self.engine?.view.alpha = 0
            }, completion: { _ in
                self.engine?.isPaused = true
                completion?()
            })
        }
    }

    func reset() {
        guard let engine else { return }
        engine.cancelAnimations()
        engine.isPaused = false
        engine.view.alpha = 1
        contentView.alpha = 0
        engine.stage = 0
        setProgress(0, animated: true)
    }
}
