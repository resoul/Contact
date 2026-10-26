import UIKit
// swiftlint:disable:next duplicate_imports
import UIKit.UIGestureRecognizerSubclass
import Metal

/// Mirrors `RippleStep` in WaterRipple.metal.
private struct RippleStep {
    var damping: Float
    var dropCount: UInt32
}

/// Mirrors `RippleDrop` in WaterRipple.metal.
private struct RippleDrop {
    var position: SIMD2<Float>
    var radius: Float
    var strength: Float
}

/// Mirrors `RippleUniforms` in WaterRipple.metal.
private struct RippleUniforms {
    var viewSize: SIMD2<Float>
    var refraction: Float
    var shine: Float
}

final class WaterRippleOverlay: VFXMetalView {
    /// Grid cell size in points; smaller = finer ripples, more GPU work.
    var cellSize: CGFloat = 2
    /// Energy kept per simulation step.
    var damping: Float = 0.988
    /// Fixed simulation rate, so wave speed does not depend on the display's refresh rate.
    var stepsPerSecond: Double = 240
    var refraction: CGFloat = 12
    var shine: CGFloat = 0.7
    var dropRadius: CGFloat = 9
    var tapStrength: Float = 2.4
    var dragStrength: Float = 0.5
    /// After this long without touches the overlay hides and the live UI shows again.
    var calmDelay: TimeInterval = 3
    /// How often the frozen picture of the UI under the water is refreshed while rippling.
    var snapshotInterval: TimeInterval = 1.0 / 15

    private weak var hostView: UIView?
    private let observer = TouchObserverGestureRecognizer()
    private let snapshotter = VFXSnapshotter()
    private var snapshot: MTLTexture?
    private var fields: [MTLTexture] = []
    private var currentIndex = 1
    private var needsClear = true
    private var pendingDrops: [RippleDrop] = []
    private var stepAccumulator: Double = 0
    private var stepsThisFrame = 0
    private var lastActivity: CFTimeInterval = 0
    private var lastSnapshot: CFTimeInterval = -1
    private var lastTrailPoint: CGPoint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isHidden = true
        isPaused = true
        observer.onTouch = { [weak self] point, phase in self?.handleTouch(at: point, phase: phase) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Lays the water over `host` (as a sibling right above it) and starts listening to its touches.
    func attach(to host: UIView) {
        guard let container = host.superview else { return }
        detach()
        hostView = host
        frame = host.frame
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.insertSubview(self, aboveSubview: host)
        host.addGestureRecognizer(observer)
    }

    func detach() {
        hostView?.removeGestureRecognizer(observer)
        hostView = nil
        removeFromSuperview()
    }

    /// Drops a ripple at `point` (in the host's coordinates).
    func addRipple(at point: CGPoint, strength: Float? = nil) {
        activate()
        // Scroll views report touches in content coordinates; the water lies over the visible frame.
        let origin = hostView?.bounds.origin ?? .zero
        let cell = SIMD2(Float((point.x - origin.x) / cellSize), Float((point.y - origin.y) / cellSize))
        pendingDrops.append(RippleDrop(position: cell, radius: Float(dropRadius / cellSize),
                                       strength: strength ?? tapStrength))
        lastActivity = time
    }

    private func handleTouch(at point: CGPoint, phase: UITouch.Phase) {
        switch phase {
        case .began:
            addRipple(at: point)
            lastTrailPoint = point
        case .moved:
            // A wake behind the finger: small drops every few points.
            if let last = lastTrailPoint, hypot(point.x - last.x, point.y - last.y) < 6 { return }
            addRipple(at: point, strength: dragStrength)
            lastTrailPoint = point
        default:
            lastTrailPoint = nil
        }
    }

    private func activate() {
        guard isHidden || isPaused, let host = hostView else { return }
        // Freeze the current UI under the water before the overlay covers it.
        snapshot = snapshotter.snapshot(host, region: host.bounds, scale: contentScaleFactor)
        lastSnapshot = time
        needsClear = true
        isHidden = false
        isPaused = false
    }

    override func drawableSizeDidChange(_ size: CGSize) {
        guard let gpu, bounds.width > 0 else { return }
        let width = Int(ceil(bounds.width / cellSize)), height = Int(ceil(bounds.height / cellSize))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r16Float, width: width,
                                                                  height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .shared
        fields = (0..<3).compactMap { _ in gpu.device.makeTexture(descriptor: descriptor) }
        needsClear = true
    }

    override func update(deltaTime: CFTimeInterval) {
        if !isHidden, time - lastActivity > calmDelay {
            isHidden = true
            isPaused = true
            return
        }
        stepAccumulator = min(stepAccumulator + deltaTime * stepsPerSecond, 6)
        stepsThisFrame = Int(stepAccumulator)
        stepAccumulator -= Double(stepsThisFrame)
        // Keep the frozen UI reasonably fresh (switches toggled, text typed under the water).
        if let host = hostView, time - lastSnapshot >= snapshotInterval {
            snapshot = snapshotter.snapshot(host, region: host.bounds, scale: contentScaleFactor)
            lastSnapshot = time
        }
    }

    override func encode(into commandBuffer: MTLCommandBuffer, target: MTLTexture) {
        guard let gpu, fields.count == 3, let snapshot,
              let stepPipeline = gpu.computePipeline("ripple_step"),
              let renderPipeline = gpu.renderPipeline(vertex: "ripple_vertex", fragment: "ripple_fragment") else {
            super.encode(into: commandBuffer, target: target)
            return
        }
        if needsClear {
            needsClear = false
            let zeros = [UInt16](repeating: 0, count: fields[0].width * fields[0].height)
            for field in fields {
                field.replace(region: MTLRegionMake2D(0, 0, field.width, field.height), mipmapLevel: 0,
                              withBytes: zeros, bytesPerRow: field.width * 2)
            }
        }

        if stepsThisFrame > 0, let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.setComputePipelineState(stepPipeline)
            let threads = MTLSize(width: 16, height: 16, depth: 1)
            let groups = MTLSize(width: (fields[0].width + 15) / 16, height: (fields[0].height + 15) / 16, depth: 1)
            for step in 0..<stepsThisFrame {
                let previous = fields[(currentIndex + 2) % 3]
                let current = fields[currentIndex]
                let next = fields[(currentIndex + 1) % 3]
                var drops = step == 0 ? pendingDrops : []
                var params = RippleStep(damping: damping, dropCount: UInt32(drops.count))
                if drops.isEmpty {
                    drops = [RippleDrop(position: .zero, radius: 0, strength: 0)]   // the buffer must be bound
                }
                encoder.setTexture(previous, index: 0)
                encoder.setTexture(current, index: 1)
                encoder.setTexture(next, index: 2)
                encoder.setBytes(&params, length: MemoryLayout<RippleStep>.stride, index: 0)
                encoder.setBytes(drops, length: MemoryLayout<RippleDrop>.stride * drops.count, index: 1)
                encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threads)
                currentIndex = (currentIndex + 1) % 3
            }
            encoder.endEncoding()
            pendingDrops.removeAll()
        }

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass(target: target)) else { return }
        var uniforms = RippleUniforms(viewSize: SIMD2(Float(bounds.width), Float(bounds.height)),
                                      refraction: Float(refraction), shine: Float(shine))
        encoder.setRenderPipelineState(renderPipeline)
        encoder.setFragmentTexture(snapshot, index: 0)
        encoder.setFragmentTexture(fields[currentIndex], index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<RippleUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}

/// Watches touches on a view without ever recognizing, cancelling or delaying them,
/// so buttons, switches and scrolling underneath keep working normally.
final class TouchObserverGestureRecognizer: UIGestureRecognizer {
    var onTouch: ((CGPoint, UITouch.Phase) -> Void)?

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        touches.forEach { onTouch?($0.location(in: view), .began) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        touches.forEach { onTouch?($0.location(in: view), .moved) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        touches.forEach { onTouch?($0.location(in: view), .ended) }
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        touches.forEach { onTouch?($0.location(in: view), .cancelled) }
        state = .failed
    }
}
