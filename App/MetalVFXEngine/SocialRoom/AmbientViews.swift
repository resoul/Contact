//
//  AmbientViews.swift
//  controller
//
//  Pieces of the ambient feed:
//  - PhotoPalette: a photo's main colours, for the background to take on.
//  - GlassColumnView: the like/comment/save/share column as real glass over the photo
//    (glass_column_fragment in SocialRoomFX.metal): it refracts and blurs the photo under it, sampled
//    straight from the photo's own texture, so it costs nothing per frame — it draws once.
//  - AmbientCard: a post card — photo, glass column, author and caption, tags that pop in when the
//    card comes into focus, double-tap for a liquid heart.
//

import UIKit
import Metal

enum PhotoPalette {
    /// Five colours from the photo's corners and middle, made a little richer for a background.
    static func colors(of image: UIImage) -> [UIColor] {
        let size = 3
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        guard let cg = image.cgImage,
              let context = CGContext(data: &pixels, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [.darkGray] }
        context.interpolationQuality = .medium
        context.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))
        return [0, 2, 4, 6, 8].map { cell in
            let i = cell * 4
            let color = UIColor(red: CGFloat(pixels[i]) / 255, green: CGFloat(pixels[i + 1]) / 255,
                                blue: CGFloat(pixels[i + 2]) / 255, alpha: 1)
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            return UIColor(hue: h, saturation: min(1, s * 1.35 + 0.05), brightness: min(0.82, max(0.3, b * 0.9)), alpha: 1)
        }
    }

    /// Mixes two palettes of the same size.
    static func mix(_ a: [UIColor], _ b: [UIColor], _ t: CGFloat) -> [UIColor] {
        zip(a, b).map { x, y in
            var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
            var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
            x.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
            y.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
            return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, alpha: 1)
        }
    }
}

/// Mirrors `GlassColumnUniforms` in SocialRoomFX.metal.
private struct GlassColumnUniforms {
    var viewport: SIMD2<Float>
    var scale: Float
    var radius: Float
    var glass: SIMD4<Float>
    var image: SIMD4<Float>
    var tint: SIMD4<Float>
    var refraction: Float
    var blur: Float
    var light: SIMD2<Float>
}

final class GlassColumnView: VFXMetalView {
    /// The glass, in this view's coordinates.
    var glassRect: CGRect = .zero {
        didSet { renderFrame() }
    }
    private var photo: MTLTexture?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isPaused = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The photo under the glass, aspect-filled into this view like the image view below it.
    func setPhoto(_ image: UIImage) {
        guard let gpu, bounds.width > 0 else { return }
        let scale: CGFloat = 0.5
        let width = Int(bounds.width * scale), height = Int(bounds.height * scale)
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        UIGraphicsPushContext(context)
        let box = bounds.size, size = image.size
        let s = max(box.width / size.width, box.height / size.height)
        image.draw(in: CGRect(x: (box.width - size.width * s) / 2, y: (box.height - size.height * s) / 2,
                              width: size.width * s, height: size.height * s))
        UIGraphicsPopContext()
        guard let bytes = context.data else { return }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: gpu.pixelFormat, width: width, height: height,
                                                                  mipmapped: true)
        descriptor.usage = .shaderRead
        guard let texture = gpu.device.makeTexture(descriptor: descriptor) else { return }
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: bytes, bytesPerRow: context.bytesPerRow)
        if let buffer = gpu.queue.makeCommandBuffer(), let blit = buffer.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: texture)
            blit.endEncoding()
            buffer.commit()
        }
        photo = texture
        renderFrame()
    }

    override func encode(into commandBuffer: MTLCommandBuffer, target: MTLTexture) {
        guard let gpu, let photo, glassRect.width > 0,
              let pipeline = gpu.renderPipeline(vertex: "room_vertex", fragment: "glass_column_fragment"),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass(target: target)) else {
            super.encode(into: commandBuffer, target: target)
            return
        }
        var uniforms = GlassColumnUniforms(
            viewport: SIMD2(Float(target.width), Float(target.height)), scale: Float(contentScaleFactor), radius: 29,
            glass: SIMD4(Float(glassRect.minX), Float(glassRect.minY), Float(glassRect.width), Float(glassRect.height)),
            image: SIMD4(0, 0, Float(bounds.width), Float(bounds.height)),
            tint: SIMD4(1, 1, 1, 0.12), refraction: 9, blur: 2.4, light: SIMD2(-0.5, -1))
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GlassColumnUniforms>.stride, index: 0)
        encoder.setFragmentTexture(photo, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}

struct AmbientPost {
    let author: ChannelPerson
    let scene: DemoPhotos.Scene
    let caption: String
    let likes: Int
    let comments: Int
    let shares: Int
    let tags: [(String, String)]
}

final class AmbientCard: UIView {
    let post: AmbientPost
    let image: UIImage
    private let photo = UIImageView()
    private let glass = GlassColumnView()
    private let shade = CAGradientLayer()
    private var actions: [(icon: UIImageView, label: UILabel)] = []
    private var tagViews: [UIView] = []
    private var liked = false
    private var likes: Int
    private var photoSize: CGSize = .zero
    private let likesLabel = RollingCounterLabel()

    init(post: AmbientPost) {
        self.post = post
        likes = post.likes
        image = DemoPhotos.image(post.scene, size: CGSize(width: 480, height: 640), seed: UInt64(post.likes % 97))
        super.init(frame: .zero)
        layer.cornerRadius = 34
        layer.cornerCurve = .continuous
        clipsToBounds = true
        photo.image = image
        photo.contentMode = .scaleAspectFill
        addSubview(photo)
        shade.colors = [UIColor.clear.cgColor, UIColor(white: 0, alpha: 0.65).cgColor]
        shade.locations = [0.55, 1]
        layer.addSublayer(shade)
        addSubview(glass)

        let symbols = [("heart", FeedFormat.count(post.likes)), ("bubble.left", FeedFormat.count(post.comments)),
                       ("bookmark", "save"), ("paperplane", "\(post.shares)")]
        for (symbol, text) in symbols {
            let icon = UIImageView(image: UIImage(systemName: symbol))
            icon.tintColor = .white
            icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
            icon.contentMode = .center
            icon.backgroundColor = UIColor(white: 1, alpha: 0.12)
            icon.layer.cornerRadius = 20
            icon.clipsToBounds = true
            addSubview(icon)
            let label = UILabel()
            label.text = text
            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.textColor = .white
            label.textAlignment = .center
            addSubview(label)
            actions.append((icon, label))
        }
        likesLabel.font = .systemFont(ofSize: 12, weight: .medium)
        likesLabel.setText(FeedFormat.count(likes), animated: false)
        actions[0].label.isHidden = true
        addSubview(likesLabel)

        let avatar = RingAvatar(person: post.author)
        avatar.frame = CGRect(x: 0, y: 0, width: 46, height: 46)
        avatar.tag = 10
        addSubview(avatar)
        let name = UILabel()
        name.text = post.author.name
        name.font = .systemFont(ofSize: 19, weight: .semibold)
        name.textColor = .white
        name.tag = 11
        addSubview(name)
        let caption = UILabel()
        caption.text = post.caption
        caption.font = .systemFont(ofSize: 13)
        caption.textColor = UIColor(white: 1, alpha: 0.8)
        caption.numberOfLines = 2
        caption.tag = 12
        addSubview(caption)
        for (symbol, title) in post.tags {
            let chip = ProfileChip(symbol: symbol, title: title)
            chip.backgroundColor = UIColor(white: 1, alpha: 0.16)
            chip.transform = CGAffineTransform(scaleX: 0.01, y: 0.01)
            chip.alpha = 0
            addSubview(chip)
            tagViews.append(chip)
        }
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        let likeTap = UITapGestureRecognizer(target: self, action: #selector(likeTapped))
        actions[0].icon.isUserInteractionEnabled = true
        actions[0].icon.addGestureRecognizer(likeTap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        photo.frame = bounds
        glass.frame = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shade.frame = bounds
        CATransaction.commit()
        let column = CGRect(x: bounds.width - 70, y: bounds.height * 0.16, width: 58, height: 4 * 74 + 10)
        if glass.glassRect != column {
            glass.glassRect = column
        }
        if photoSize != bounds.size {
            photoSize = bounds.size
            glass.setPhoto(image)
        }
        for (index, action) in actions.enumerated() {
            let y = column.minY + 12 + CGFloat(index) * 74
            action.icon.frame = CGRect(x: column.midX - 20, y: y, width: 40, height: 40)
            action.label.frame = CGRect(x: column.minX, y: y + 44, width: column.width, height: 16)
        }
        let size = likesLabel.intrinsicContentSize
        likesLabel.frame = CGRect(x: column.midX - size.width / 2, y: column.minY + 56, width: size.width, height: size.height)

        let bottom = bounds.height - 22
        let chipsY = bottom - 38
        var x: CGFloat = 18
        for chip in tagViews {
            let w = chip.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width
            chip.bounds = CGRect(x: 0, y: 0, width: w, height: 38)
            chip.center = CGPoint(x: x + w / 2, y: chipsY + 19)
            x += w + 8
        }
        let captionY = chipsY - 46
        viewWithTag(12)?.frame = CGRect(x: 18, y: captionY, width: bounds.width - 110, height: 38)
        viewWithTag(10)?.frame = CGRect(x: 16, y: captionY - 56, width: 46, height: 46)
        viewWithTag(11)?.frame = CGRect(x: 70, y: captionY - 46, width: bounds.width - 150, height: 24)
    }

    /// The card came into focus: its tags pop in one after another.
    func activate(_ on: Bool) {
        for (index, chip) in tagViews.enumerated() {
            UIView.animate(withDuration: on ? 0.5 : 0.2, delay: on ? 0.08 * Double(index) : 0,
                           usingSpringWithDamping: on ? 0.5 : 1, initialSpringVelocity: 0.5) {
                chip.transform = on ? .identity : CGAffineTransform(scaleX: 0.01, y: 0.01)
                chip.alpha = on ? 1 : 0
            }
        }
    }

    @objc private func likeTapped() {
        setLiked(!liked)
    }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        if let host = window?.rootViewController?.view {
            HeartPop.show(at: gesture.location(in: host), in: host, target: nil, arrive: nil)
        }
        if !liked {
            setLiked(true)
        }
    }

    private func setLiked(_ value: Bool) {
        liked = value
        likes += value ? 1 : -1
        likesLabel.setText(FeedFormat.count(likes), animated: true, up: value)
        let icon = actions[0].icon
        icon.image = UIImage(systemName: value ? "heart.fill" : "heart")
        icon.tintColor = value ? UIColor(red: 1, green: 0.3, blue: 0.4, alpha: 1) : .white
        icon.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.4, initialSpringVelocity: 0.8) {
            icon.transform = .identity
        }
        UIImpactFeedbackGenerator(style: value ? .medium : .light).impactOccurred()
        if value, let window {
            IslandConfetti.burst(in: window, from: icon.convert(CGPoint(x: 20, y: 20), to: window), direction: -.pi / 2,
                                 spread: 2 * .pi, particles: 60, sparkShare: 1, sparkColor: UIColor(red: 1, green: 0.3, blue: 0.4, alpha: 1),
                                 speedScale: 0.28)
        }
    }
}
