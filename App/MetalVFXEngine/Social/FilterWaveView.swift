//
//  FilterWaveView.swift
//  controller
//
//  Switching a photo filter with a wave (filter_wave_fragment in SocialFX.metal): the new look
//  washes over the old one from the side of the chosen filter, as a wavy front that bends the
//  picture under its crest and leaves a line of foam. Filters are Core Image, rendered once per pick.
//

import UIKit
import Metal
import CoreImage

/// Mirrors `FilterWaveUniforms` in SocialFX.metal.
private struct FilterWaveUniforms {
    var viewport: SIMD2<Float>
    var progress: Float
    var direction: Float
    var time: Float
    var radius: Float
    var scale: Float
    var unused: Float = 0
}

enum PhotoFilter: String, CaseIterable {
    case original = "Original"
    case warm = "Warm"
    case noir = "Noir"
    case vintage = "Vintage"
    case neon = "Neon"

    private static let context = CIContext()

    func apply(to image: UIImage) -> UIImage {
        guard self != .original, let input = CIImage(image: image) else { return image }
        var output = input
        switch self {
        case .original:
            break
        case .warm:
            output = input.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 4300, y: 0)])
                .applyingFilter("CIVibrance", parameters: ["inputAmount": 0.4])
        case .noir:
            output = input.applyingFilter("CIPhotoEffectNoir")
        case .vintage:
            output = input.applyingFilter("CISepiaTone", parameters: [kCIInputIntensityKey: 0.55])
                .applyingFilter("CIVignette", parameters: [kCIInputIntensityKey: 1.2, kCIInputRadiusKey: 1.6])
        case .neon:
            output = input.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.9, kCIInputContrastKey: 1.15])
                .applyingFilter("CIHueAdjust", parameters: [kCIInputAngleKey: 0.5])
        }
        guard let cg = Self.context.createCGImage(output, from: input.extent) else { return image }
        return UIImage(cgImage: cg)
    }
}

final class FilterWaveView: VFXMetalView {
    var cornerRadius: CGFloat = 0
    private var oldTexture: MTLTexture?
    private var newTexture: MTLTexture?
    private var progress = Spring1D(0, stiffness: 5.5, dampingRatio: 1)
    private var direction: Float = 1
    private var completion: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isPaused = true
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Washes `new` over `old` (both the size of this view), left to right when `forward`.
    func wash(from old: UIImage, to new: UIImage, forward: Bool, completion: @escaping () -> Void) {
        guard let gpu else {
            completion()
            return
        }
        let draw: (UIImage) -> MTLTexture? = { image in
            gpu.makeTexture(size: self.bounds.size, scale: 1) { _ in
                // Aspect fill, like the image view under it.
                let size = image.size, box = self.bounds.size
                let s = max(box.width / size.width, box.height / size.height)
                let w = size.width * s, h = size.height * s
                image.draw(in: CGRect(x: (box.width - w) / 2, y: (box.height - h) / 2, width: w, height: h))
            }
        }
        oldTexture = draw(old)
        newTexture = draw(new)
        direction = forward ? 1 : -1
        progress = Spring1D(0, stiffness: 5.5, dampingRatio: 1)
        self.completion = completion
        isHidden = false
        isPaused = false
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    override func update(deltaTime: CFTimeInterval) {
        progress.step(toward: 1, deltaTime: deltaTime)
        if progress.value > 0.995 {
            isPaused = true
            let done = completion
            completion = nil
            done?()
            DispatchQueue.main.async { self.isHidden = true }
        }
    }

    override func encode(into commandBuffer: MTLCommandBuffer, target: MTLTexture) {
        guard let gpu, let oldTexture, let newTexture,
              let pipeline = gpu.renderPipeline(vertex: "social_vertex", fragment: "filter_wave_fragment"),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass(target: target)) else {
            super.encode(into: commandBuffer, target: target)
            return
        }
        var uniforms = FilterWaveUniforms(viewport: SIMD2(Float(target.width), Float(target.height)),
                                          progress: Float(progress.value), direction: direction, time: Float(time),
                                          radius: Float(cornerRadius), scale: Float(contentScaleFactor))
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(oldTexture, index: 0)
        encoder.setFragmentTexture(newTexture, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FilterWaveUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}
