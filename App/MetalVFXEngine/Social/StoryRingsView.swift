//
//  StoryRingsView.swift
//  controller
//
//  The stories row: avatars in rings that are alive — the gradient flows around each ring and its
//  thickness ripples like a liquid band (story_rings_fragment in SocialFX.metal). All rings are drawn
//  by one Metal view behind the avatars, at 30 fps, rather than a view per ring. Watched stories get a
//  thin grey ring. Tapping an avatar presses its ring in and reports it.
//

import UIKit
import Metal

/// Mirrors `StoryRingUniforms` in SocialFX.metal.
private struct StoryRingUniforms {
    var viewport: SIMD2<Float>
    var scale: Float
    var time: Float
    var count: UInt32
    var width: Float
    var unused: SIMD2<Float> = .zero
}

/// Mirrors `StoryRing` in SocialFX.metal.
private struct StoryRing {
    var ring: SIMD4<Float>
    var extra: SIMD4<Float>
}

struct StoryUser {
    let person: ChannelPerson
    let photos: [DemoPhotos.Scene]
    var seen = false
}

final class StoryRingsView: UIView {
    private(set) var users: [StoryUser]
    var onOpen: ((Int) -> Void)?

    private let scroll = UIScrollView()
    private let canvas = StoryRingCanvas()
    private var avatars: [UIImageView] = []
    private let avatarSize: CGFloat = 62
    private let spacing: CGFloat = 84

    init(users: [StoryUser]) {
        self.users = users
        super.init(frame: .zero)
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true
        addSubview(scroll)
        scroll.addSubview(canvas)
        canvas.owner = self
        for (index, user) in users.enumerated() {
            let avatar = UIImageView(image: ChannelAvatar.image(for: user.person, size: avatarSize))
            avatar.isUserInteractionEnabled = true
            avatar.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
            avatar.tag = index
            scroll.addSubview(avatar)
            avatars.append(avatar)
            let name = UILabel()
            name.text = index == 0 ? "Ваша история" : String(user.person.name.split(separator: " ").first ?? "")
            name.font = .systemFont(ofSize: 11)
            name.textColor = .white
            name.textAlignment = .center
            name.tag = 1000 + index
            scroll.addSubview(name)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 110)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scroll.frame = bounds
        let width = CGFloat(users.count) * spacing + 12
        scroll.contentSize = CGSize(width: width, height: bounds.height)
        canvas.frame = CGRect(x: 0, y: 0, width: width, height: bounds.height)
        for (index, avatar) in avatars.enumerated() {
            let center = ringCenter(index)
            avatar.bounds = CGRect(x: 0, y: 0, width: avatarSize, height: avatarSize)
            avatar.center = center
            if let name = scroll.viewWithTag(1000 + index) as? UILabel {
                name.frame = CGRect(x: center.x - spacing / 2, y: center.y + 42, width: spacing, height: 16)
            }
        }
    }

    fileprivate func ringCenter(_ index: Int) -> CGPoint {
        CGPoint(x: 12 + spacing * (CGFloat(index) + 0.5), y: 46)
    }

    /// Where user `index`'s avatar is now, in `view`.
    func avatarFrame(_ index: Int, in view: UIView) -> CGRect {
        avatars[index].convert(avatars[index].bounds, to: view)
    }

    func markSeen(_ index: Int) {
        users[index].seen = true
        canvas.seenTarget[index] = 1
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard let index = gesture.view?.tag else { return }
        canvas.press[index].velocity += 14
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let avatar = avatars[index]
        UIView.animate(withDuration: 0.12, animations: {
            avatar.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }, completion: { _ in
            UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.5) {
                avatar.transform = .identity
            }
        })
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak self] in self?.onOpen?(index) }
    }

    fileprivate var count: Int { users.count }
}

private final class StoryRingCanvas: VFXMetalView {
    weak var owner: StoryRingsView? {
        didSet {
            let count = owner?.count ?? 0
            press = Array(repeating: Spring1D(0, stiffness: 18, dampingRatio: 0.35), count: count)
            seen = owner?.users.map { $0.seen ? 1 : 0 } ?? []
            seenTarget = seen
        }
    }
    var press: [Spring1D] = []
    var seen: [CGFloat] = []
    var seenTarget: [CGFloat] = []
    private let seeds = (0..<64).map { _ in Float.random(in: 0...6) }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        preferredFramesPerSecond = 30
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func update(deltaTime: CFTimeInterval) {
        for index in press.indices {
            press[index].step(toward: 0, deltaTime: deltaTime)
            seen[index] += (seenTarget[index] - seen[index]) * min(1, CGFloat(deltaTime) * 4)
        }
    }

    override func encode(into commandBuffer: MTLCommandBuffer, target: MTLTexture) {
        guard let gpu, let owner,
              let pipeline = gpu.renderPipeline(vertex: "social_vertex", fragment: "story_rings_fragment"),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass(target: target)) else {
            super.encode(into: commandBuffer, target: target)
            return
        }
        let rings = (0..<owner.count).map { index -> StoryRing in
            let center = owner.ringCenter(index)
            return StoryRing(ring: SIMD4(Float(center.x), Float(center.y), 36, Float(seen[index])),
                             extra: SIMD4(Float(max(press[index].value, 0)), seeds[index % seeds.count], 0, 0))
        }
        var uniforms = StoryRingUniforms(viewport: SIMD2(Float(target.width), Float(target.height)),
                                         scale: Float(contentScaleFactor), time: Float(time), count: UInt32(rings.count),
                                         width: 3.2)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<StoryRingUniforms>.stride, index: 0)
        encoder.setFragmentBytes(rings, length: MemoryLayout<StoryRing>.stride * max(rings.count, 1), index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}
