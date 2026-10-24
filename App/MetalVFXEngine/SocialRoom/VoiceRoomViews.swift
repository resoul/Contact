//
//  VoiceRoomViews.swift
//  controller
//
//  Pieces of the voice room:
//  - RoomTile: a speaker (big) or listener (small) tile.
//  - VoiceRimsView: one Metal pass that draws a liquid rim around every tile that has a voice
//    (voice_rims_fragment in SocialRoomFX.metal): it thickens and ripples with the level and glows.
//  - RaisedHand: a ✋ bubble oozing out of a tile's corner on a liquid neck, pulsing until the host
//    lets the person on stage; then it is drawn back in.
//  - RoomCounterChip: icon + rolling count, with reactions floating up out of it.
//

import UIKit
import Metal

final class RoomTile: UIView {
    let person: ChannelPerson
    private let avatar = UIImageView()
    private let backdrop = CAGradientLayer()
    private let nameLabel = UILabel()
    private let speakingIcon = UIImageView(image: UIImage(systemName: "waveform"))
    private let mutedIcon = UIImageView(image: UIImage(systemName: "mic.slash"))
    private(set) var isSpeaker: Bool
    var level: CGFloat = 0 {
        didSet { updateSpeaking() }
    }
    var isMuted = false {
        didSet { mutedIcon.isHidden = !isMuted || !isSpeaker }
    }

    init(person: ChannelPerson, speaker: Bool) {
        self.person = person
        isSpeaker = speaker
        super.init(frame: .zero)
        layer.cornerCurve = .continuous
        clipsToBounds = false
        backdrop.colors = [UIColor(hue: person.hue, saturation: 0.45, brightness: 0.55, alpha: 1).cgColor,
                           UIColor(hue: person.hue + 0.05, saturation: 0.6, brightness: 0.22, alpha: 1).cgColor]
        backdrop.cornerCurve = .continuous
        layer.addSublayer(backdrop)
        avatar.image = ChannelAvatar.image(for: person, size: 120)
        addSubview(avatar)
        nameLabel.text = String(person.name.split(separator: " ").first ?? "")
        nameLabel.textColor = .white
        nameLabel.textAlignment = .center
        addSubview(nameLabel)
        speakingIcon.tintColor = .white
        speakingIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        speakingIcon.isHidden = true
        addSubview(speakingIcon)
        mutedIcon.tintColor = .white
        mutedIcon.backgroundColor = UIColor(white: 1, alpha: 0.15)
        mutedIcon.contentMode = .center
        mutedIcon.layer.cornerRadius = 17
        mutedIcon.clipsToBounds = true
        mutedIcon.isHidden = true
        addSubview(mutedIcon)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var cornerRadius: CGFloat { isSpeaker ? 30 : 24 }

    /// The tile proper (the name sits under small tiles, outside it).
    var tileRect: CGRect {
        isSpeaker ? bounds : CGRect(x: 0, y: 0, width: bounds.width, height: bounds.width)
    }

    func becomeSpeaker() {
        isSpeaker = true
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let tile = tileRect
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop.frame = tile
        backdrop.cornerRadius = cornerRadius
        CATransaction.commit()
        let side = isSpeaker ? min(tile.width, tile.height) * 0.62 : tile.width
        avatar.frame = CGRect(x: tile.midX - side / 2, y: isSpeaker ? tile.midY - side / 2 - 12 : 0, width: side, height: side)
        avatar.layer.cornerRadius = isSpeaker ? side / 2 : cornerRadius
        avatar.layer.cornerCurve = .continuous
        avatar.clipsToBounds = true
        nameLabel.font = .systemFont(ofSize: isSpeaker ? 19 : 14, weight: isSpeaker ? .semibold : .medium)
        nameLabel.sizeToFit()
        let nameY = isSpeaker ? tile.maxY - 34 : tile.maxY + 6
        let iconWidth: CGFloat = speakingIcon.isHidden ? 0 : 20
        nameLabel.frame = CGRect(x: tile.midX - (nameLabel.bounds.width + iconWidth) / 2, y: nameY,
                                 width: nameLabel.bounds.width, height: nameLabel.bounds.height)
        speakingIcon.frame = CGRect(x: nameLabel.frame.maxX + 5, y: nameY + 1, width: 16, height: nameLabel.bounds.height - 2)
        mutedIcon.frame = CGRect(x: tile.maxX - 46, y: 12, width: 34, height: 34)
    }

    private func updateSpeaking() {
        let speaking = level > 0.12
        guard speaking == speakingIcon.isHidden else { return }
        speakingIcon.isHidden = !speaking
        if #available(iOS 17.0, *) {
            if speaking {
                speakingIcon.addSymbolEffect(.variableColor.iterative)
            } else {
                speakingIcon.removeAllSymbolEffects()
            }
        }
        setNeedsLayout()
    }
}

/// Mirrors `VoiceRimUniforms` in SocialRoomFX.metal.
private struct VoiceRimUniforms {
    var viewport: SIMD2<Float>
    var scale: Float
    var time: Float
    var count: UInt32
    var unused0: Float = 0
    var unused1: Float = 0
    var unused2: Float = 0
    var colorA: SIMD4<Float>
    var colorB: SIMD4<Float>
}

/// Mirrors `VoiceRim` in SocialRoomFX.metal.
private struct VoiceRim {
    var rect: SIMD4<Float>
    var params: SIMD4<Float>
}

final class VoiceRimsView: VFXMetalView {
    /// Tiles with a voice, in this view's coordinates, asked every frame.
    var rims: (() -> [(rect: CGRect, radius: CGFloat, level: CGFloat)])?
    var onFrame: ((CFTimeInterval) -> Void)?
    private let seeds = (0..<32).map { _ in Float.random(in: 0...6) }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        preferredFramesPerSecond = 60
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func update(deltaTime: CFTimeInterval) {
        onFrame?(deltaTime)
    }

    override func encode(into commandBuffer: MTLCommandBuffer, target: MTLTexture) {
        let list = rims?() ?? []
        guard let gpu, !list.isEmpty,
              let pipeline = gpu.renderPipeline(vertex: "room_vertex", fragment: "voice_rims_fragment"),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass(target: target)) else {
            super.encode(into: commandBuffer, target: target)
            return
        }
        var uniforms = VoiceRimUniforms(viewport: SIMD2(Float(target.width), Float(target.height)),
                                        scale: Float(contentScaleFactor), time: Float(time), count: UInt32(list.count),
                                        colorA: RoomPalette.orange.vfxSIMD(with: traitCollection),
                                        colorB: RoomPalette.pink.vfxSIMD(with: traitCollection))
        let data = list.enumerated().map { index, rim in
            VoiceRim(rect: SIMD4(Float(rim.rect.minX), Float(rim.rect.minY), Float(rim.rect.width), Float(rim.rect.height)),
                     params: SIMD4(Float(rim.radius), Float(rim.level), seeds[index % seeds.count], 0))
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<VoiceRimUniforms>.stride, index: 0)
        encoder.setFragmentBytes(data, length: MemoryLayout<VoiceRim>.stride * data.count, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}

/// A ✋ that oozes out of a tile's top-right corner and pulses there; `lower()` draws it back in.
final class RaisedHand {
    private weak var tile: RoomTile?
    private let emoji = UILabel()
    private var radius = Spring1D(0, stiffness: 13, dampingRatio: 0.45)
    private var raised = true
    private var age: CFTimeInterval = 0
    private(set) var isDone = false

    init(on tile: RoomTile, in host: UIView) {
        self.tile = tile
        emoji.text = "✋"
        emoji.font = .systemFont(ofSize: 15)
        emoji.sizeToFit()
        emoji.alpha = 0
        host.addSubview(emoji)
        radius.velocity = 40
    }

    func lower() {
        raised = false
        age = 0
    }

    /// One frame: returns the liquid for the shared canvas (in `host` coordinates).
    func step(_ dt: CFTimeInterval, in host: UIView) -> (shapes: [IslandFluidShape], spikes: [IslandFluidSpike]) {
        guard let tile, !isDone else { return ([], []) }
        age += dt
        let tileRect = tile.convert(tile.tileRect, to: host)
        let corner = CGPoint(x: tileRect.maxX - 8, y: tileRect.minY + 8)
        let pulse = raised && age > 0.6 ? 1.5 * sin(age * 5) : 0
        radius.step(toward: raised ? 15 + pulse : 0, deltaTime: dt)
        let r = max(radius.value, 0)
        // Oozes out diagonally, still tied to the corner by a neck for a moment.
        let out = min(1, r / 15)
        let center = CGPoint(x: corner.x + 6 * out, y: corner.y - 6 * out)
        emoji.center = center
        emoji.alpha = min(1, max(0, (r - 9) / 5))
        emoji.transform = CGAffineTransform(rotationAngle: raised ? 0.25 * sin(age * 9) * exp(-age * 1.5) : 0)
        if !raised, r < 0.5, age > 0.3 {
            isDone = true
            emoji.removeFromSuperview()
            return ([], [])
        }
        var spikes: [IslandFluidSpike] = []
        if age < 0.7 || !raised {
            spikes.append(IslandFluidSpike(base: CGPoint(x: corner.x - 6, y: corner.y + 6), tip: center,
                                           baseRadius: 6 * out, tipRadius: r * 0.7, blend: 6))
        }
        return ([.circle(center: center, radius: r, blend: 6)], spikes)
    }
}

/// Icon (or avatar) + rolling count, like the room's bottom chips.
final class RoomCounterChip: UIControl {
    private let icon: UIView
    private let counter = RollingCounterLabel()
    private(set) var count: Int

    init(symbol: String? = nil, avatar: ChannelPerson? = nil, count: Int, highlighted: Bool = false) {
        self.count = count
        if let avatar {
            let image = UIImageView(image: ChannelAvatar.image(for: avatar, size: 30))
            icon = image
        } else {
            let image = UIImageView(image: UIImage(systemName: symbol ?? "circle"))
            image.tintColor = .white
            image.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18)
            image.contentMode = .center
            icon = image
        }
        super.init(frame: .zero)
        backgroundColor = highlighted ? RoomPalette.orange : RoomPalette.chip
        layer.cornerCurve = .continuous
        icon.isUserInteractionEnabled = false
        addSubview(icon)
        counter.font = .systemFont(ofSize: 17, weight: .medium)
        counter.setText("\(count)", animated: false)
        addSubview(counter)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        let size = counter.intrinsicContentSize
        let total = 30 + 8 + size.width
        let x = (bounds.width - total) / 2
        icon.frame = CGRect(x: x, y: bounds.midY - 15, width: 30, height: 30)
        icon.layer.cornerRadius = 15
        icon.clipsToBounds = true
        counter.frame = CGRect(x: x + 38, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }

    func setCount(_ value: Int) {
        let up = value >= count
        count = value
        counter.setText("\(value)", animated: true, up: up)
        setNeedsLayout()
    }

    /// An emoji bubble floats up out of the chip.
    func float(_ emoji: String, in host: UIView) {
        let bubble = UILabel()
        bubble.text = emoji
        bubble.font = .systemFont(ofSize: 20)
        bubble.sizeToFit()
        let start = convert(CGPoint(x: bounds.midX, y: 0), to: host)
        bubble.center = start
        host.addSubview(bubble)
        let sway = CGFloat.random(in: -30...30)
        bubble.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.5) {
            bubble.transform = .identity
        }
        UIView.animate(withDuration: 1.6, delay: 0, options: [.curveEaseOut]) {
            bubble.center = CGPoint(x: start.x + sway, y: start.y - 160)
        }
        UIView.animate(withDuration: 0.6, delay: 1.0, options: []) {
            bubble.alpha = 0
        } completion: { _ in
            bubble.removeFromSuperview()
        }
    }
}
