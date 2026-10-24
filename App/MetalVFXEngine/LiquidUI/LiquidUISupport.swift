//
//  LiquidUISupport.swift
//  controller
//
//  Shared pieces for the Liquid UI controls: a 1D spring, and the device tilt that the clay buttons
//  and skeletons light themselves with (with a slow drift when there is no motion sensor).
//

import UIKit
import CoreMotion
import Metal

/// Damped spring on a single value, integrated in small fixed steps so it is stable at any frame rate.
struct Spring1D {
    var value: CGFloat
    var velocity: CGFloat = 0
    /// Angular frequency, 1/s.
    var stiffness: CGFloat
    /// 1 = critically damped, < 1 overshoots and wobbles.
    var dampingRatio: CGFloat

    init(_ value: CGFloat, stiffness: CGFloat, dampingRatio: CGFloat) {
        self.value = value
        self.stiffness = stiffness
        self.dampingRatio = dampingRatio
    }

    mutating func step(toward target: CGFloat, deltaTime: CFTimeInterval) {
        let steps = max(1, Int(ceil(deltaTime / (1.0 / 480))))
        let dt = CGFloat(deltaTime) / CGFloat(steps)
        for _ in 0..<steps {
            velocity += (stiffness * stiffness * (target - value) - 2 * dampingRatio * stiffness * velocity) * dt
            value += velocity * dt
        }
    }

    func isSettled(at target: CGFloat, tolerance: CGFloat = 0.001) -> Bool {
        abs(value - target) < tolerance && abs(velocity) < tolerance * 10
    }
}

/// Which way gravity points in screen space, so lighting can stay put while the phone tilts.
@MainActor
final class LiquidUIMotion {
    static let shared = LiquidUIMotion()

    private let manager = CMMotionManager()
    private let start = CACurrentMediaTime()

    private init() {
        if manager.isDeviceMotionAvailable {
            manager.deviceMotionUpdateInterval = 1.0 / 60
            manager.startDeviceMotionUpdates()
        }
    }

    /// Gravity on the screen plane: x to the right, y down; (0, 1) when the phone stands upright.
    /// Without a motion sensor (the simulator) it sways slowly so the light still moves.
    var gravity: CGPoint {
        if let g = manager.deviceMotion?.gravity {
            return CGPoint(x: g.x, y: -g.y)
        }
        let t = CACurrentMediaTime() - start
        return CGPoint(x: sin(t * 0.7) * 0.45, y: 0.85 + cos(t * 0.5) * 0.1)
    }
}

extension VFXGPU {
    /// A premultiplied BGRA texture drawn with Core Graphics (top-left origin, in points scaled by `scale`).
    func makeTexture(size: CGSize, scale: CGFloat, draw: (CGContext) -> Void) -> MTLTexture? {
        let width = Int((size.width * scale).rounded()), height = Int((size.height * scale).rounded())
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                          | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        UIGraphicsPushContext(context)
        draw(context)
        UIGraphicsPopContext()
        guard let bytes = context.data else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: width,
                                                                  height: height, mipmapped: false)
        descriptor.usage = .shaderRead
        let texture = device.makeTexture(descriptor: descriptor)
        texture?.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                         withBytes: bytes, bytesPerRow: context.bytesPerRow)
        return texture
    }
}
