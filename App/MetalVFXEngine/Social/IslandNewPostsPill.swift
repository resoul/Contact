//
//  IslandNewPostsPill.swift
//  controller
//
//  "New posts" dripping out of the Dynamic Island: a glossy pill wells up under the island on a
//  neck of liquid, tears off and floats there with the authors' avatars and the count. Tap it and it
//  is swallowed back into the island while the timeline scrolls up to the new posts.
//

import UIKit

final class IslandNewPostsPill: IslandFluidView {
    var onTap: (() -> Void)?

    private let label = UILabel()
    private let avatars = UIStackView()
    private let arrow = UIImageView(image: UIImage(systemName: "arrow.up"))
    private let content = UIStackView()
    private var center2 = IslandSpring(.zero, stiffness: 10, dampingRatio: 0.55)
    private var size = IslandSpring(.zero, stiffness: 12, dampingRatio: 0.5)
    private enum Phase { case hidden, dripping, floating, swallowing }
    private var phase = Phase.hidden
    private var phaseTime: CFTimeInterval = 0
    private var snapTime: CFTimeInterval?
    private let pillSize = CGSize(width: 188, height: 40)

    override init(frame: CGRect) {
        super.init(frame: frame)
        gloss = 0.8
        rimWidth = 8
        isUserInteractionEnabled = true
        isPaused = true
        arrow.tintColor = .white
        arrow.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        avatars.spacing = -8
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .white
        content.addArrangedSubview(arrow)
        content.addArrangedSubview(avatars)
        content.addArrangedSubview(label)
        content.spacing = 7
        content.alignment = .center
        content.alpha = 0
        content.isUserInteractionEnabled = false
        addSubview(content)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Below the navigation bar, so the drip has a way to fall.
    private var restingCenter: CGPoint {
        CGPoint(x: islandMouth.x, y: islandMouth.y + 96)
    }

    /// Only the pill takes touches; the rest of the window passes through.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard phase == .floating || phase == .dripping else { return false }
        let pill = CGRect(x: center2.position.x - pillSize.width / 2, y: center2.position.y - pillSize.height / 2,
                          width: pillSize.width, height: pillSize.height)
        return pill.insetBy(dx: -8, dy: -8).contains(point)
    }

    func show(people: [ChannelPerson], count: Int) {
        avatars.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for person in people.prefix(3) {
            let image = UIImageView(image: ChannelAvatar.image(for: person, size: 22))
            image.layer.borderColor = UIColor.black.cgColor
            image.layer.borderWidth = 1.5
            image.layer.cornerRadius = 11
            image.clipsToBounds = true
            image.widthAnchor.constraint(equalToConstant: 22).isActive = true
            image.heightAnchor.constraint(equalToConstant: 22).isActive = true
            avatars.addArrangedSubview(image)
        }
        label.text = "\(count) новых постов"
        phase = .dripping
        phaseTime = 0
        snapTime = nil
        center2 = IslandSpring(CGPoint(x: islandMouth.x, y: islandMouth.y - 6), stiffness: 10, dampingRatio: 0.55)
        size = IslandSpring(CGPoint(x: 30, y: 16), stiffness: 12, dampingRatio: 0.5)
        isPaused = false
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    @objc private func tapped() {
        guard phase == .floating || phase == .dripping else { return }
        phase = .swallowing
        phaseTime = 0
        isPaused = false
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onTap?()
    }

    override func update(deltaTime: CFTimeInterval) {
        phaseTime += deltaTime
        let mouth = islandMouth
        var newShapes: [IslandFluidShape] = []
        var newSpikes: [IslandFluidSpike] = []
        switch phase {
        case .hidden:
            settle()
            return
        case .dripping, .floating:
            // Wells up first (a fat drop), then stretches into the pill.
            let target = phaseTime < 0.25 ? CGPoint(x: mouth.x, y: mouth.y + 10) : restingCenter
            center2.step(toward: target, deltaTime: deltaTime)
            size.step(toward: phaseTime < 0.25 ? CGPoint(x: 44, y: 30) : CGPoint(x: pillSize.width, y: pillSize.height),
                      deltaTime: deltaTime)
            let gap = center2.position.y - size.position.y / 2 - mouth.y
            if phase == .dripping, gap > 9 {
                phase = .floating
                snapTime = 0
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            if phase == .dripping {
                // The neck to the island, thinning as the pill pulls away.
                newSpikes.append(IslandFluidSpike(base: CGPoint(x: mouth.x, y: mouth.y - 2),
                                                  tip: CGPoint(x: center2.position.x, y: center2.position.y - size.position.y / 2 + 4),
                                                  baseRadius: max(3, 9 - gap), tipRadius: max(2, 7 - gap * 0.6), blend: 8))
            }
        case .swallowing:
            center2.step(toward: CGPoint(x: mouth.x, y: mouth.y - 8), deltaTime: deltaTime)
            size.step(toward: CGPoint(x: 26, y: 14), deltaTime: deltaTime)
            let gap = center2.position.y - size.position.y / 2 - mouth.y
            if gap < 10 {
                newSpikes.append(IslandFluidSpike(base: CGPoint(x: mouth.x, y: mouth.y - 2), tip: center2.position,
                                                  baseRadius: 8, tipRadius: 6, blend: 10))
            }
            if phaseTime > 0.7 {
                phase = .hidden
                content.alpha = 0
                settle()
                return
            }
        }
        if let t = snapTime {
            snapTime = t > 1 ? nil : t + deltaTime
            newShapes.append(recoilBump(t, amplitude: 9))
        }
        let s = size.position
        newShapes.append(IslandFluidShape(center: center2.position, halfSize: CGSize(width: max(s.x, 1) / 2, height: max(s.y, 1) / 2),
                                          cornerRadius: s.y / 2, blend: 8))
        shapes = newShapes
        spikes = newSpikes
        content.sizeToFit()
        content.bounds.size = content.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        content.center = center2.position
        content.alpha = phase == .swallowing ? max(0, 1 - CGFloat(phaseTime) * 6) : islandSmoothstep(0.6, 0.95, s.x / pillSize.width)
        let pinch = min(1, s.x / pillSize.width)
        content.transform = CGAffineTransform(scaleX: 0.8 + 0.2 * pinch, y: 0.8 + 0.2 * pinch)
        // Floating and still: stop the display link until it is tapped.
        if phase == .floating, snapTime == nil, center2.speed < 0.5, size.speed < 0.5 {
            renderFrame()
            isPaused = true
        }
    }
}
