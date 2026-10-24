//
//  SkeletonShimmerView.swift
//  controller
//
//  Loading placeholders lit like glass (skeleton_fragment in LiquidUI.metal): instead of a shimmer
//  running in circles, a broad highlight lies across the blocks where the light would fall, and it
//  slides over them as the phone tilts. Give it the placeholder rects in its own coordinates.
//

import UIKit
import Metal

/// Mirrors `SkeletonUniforms` in LiquidUI.metal.
private struct SkeletonUniforms {
    var viewport: SIMD2<Float>
    var scale: Float
    var count: UInt32
    var base: SIMD4<Float>
    var sheen: SIMD4<Float>
    var gravity: SIMD2<Float>
    var time: Float
    var unused: Float = 0
}

/// Mirrors `SkeletonBlock` in LiquidUI.metal.
private struct SkeletonBlock {
    var rect: SIMD4<Float>
    var params: SIMD4<Float>
}

final class SkeletonShimmerView: VFXMetalView {
    /// Placeholder blocks: rect and corner radius, in this view's coordinates.
    var blocks: [(rect: CGRect, radius: CGFloat)] = []
    var baseColor = UIColor.systemGray5
    var sheenColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor.systemGray2 : UIColor.white }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        preferredFramesPerSecond = 60
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func encode(into commandBuffer: MTLCommandBuffer, target: MTLTexture) {
        guard let gpu, !blocks.isEmpty,
              let pipeline = gpu.renderPipeline(vertex: "liquid_ui_vertex", fragment: "skeleton_fragment"),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass(target: target)) else {
            super.encode(into: commandBuffer, target: target)
            return
        }
        let gravity = LiquidUIMotion.shared.gravity
        var uniforms = SkeletonUniforms(
            viewport: SIMD2(Float(target.width), Float(target.height)), scale: Float(contentScaleFactor),
            count: UInt32(blocks.count), base: baseColor.vfxSIMD(with: traitCollection),
            sheen: sheenColor.vfxSIMD(with: traitCollection), gravity: SIMD2(Float(gravity.x), Float(gravity.y)),
            time: Float(time))
        let data = blocks.map {
            SkeletonBlock(rect: SIMD4(Float($0.rect.minX), Float($0.rect.minY), Float($0.rect.width), Float($0.rect.height)),
                          params: SIMD4(Float($0.radius), 0, 0, 0))
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SkeletonUniforms>.stride, index: 0)
        encoder.setFragmentBytes(data, length: MemoryLayout<SkeletonBlock>.stride * data.count, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}
