import UIKit
import MetalKit

/// The demo's Aurora border rendered behind a standard, accessible submit button.
final class AuroraSubmitButton: UIButton {
    private let aurora = AuroraBorderView()

    var isAnimating = false {
        didSet { aurora.isActive = isAnimating }
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.75 : 1 }
    }

    init() {
        super.init(frame: .zero)
        var config = UIButton.Configuration.plain()
        config.title = "Sign In"
        config.baseForegroundColor = .white
        config.contentInsets = NSDirectionalEdgeInsets(top: 24, leading: 28, bottom: 24, trailing: 28)
        configuration = config
        backgroundColor = UIColor(red: 0.025, green: 0.032, blue: 0.049, alpha: 1)
        layer.cornerRadius = 24
        layer.cornerCurve = .continuous
        clipsToBounds = true
        aurora.isUserInteractionEnabled = false
        aurora.isAccessibilityElement = false
        insertSubview(aurora, at: 0)
        heightAnchor.constraint(greaterThanOrEqualToConstant: 76).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("Use init()") }

    override func layoutSubviews() {
        super.layoutSubviews()
        aurora.frame = bounds
        sendSubviewToBack(aurora)
    }
}

private final class AuroraBorderView: MTKView, MTKViewDelegate {
    private var pipeline: MTLRenderPipelineState?
    private var commandQueue: MTLCommandQueue?
    private let framesInFlight = DispatchSemaphore(value: 3)
    private let startTime = CACurrentMediaTime()
    var isActive = false { didSet { updateAnimation() } }

    init() {
        let gpu = MTLCreateSystemDefaultDevice()
        super.init(frame: .zero, device: gpu)
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = true
        isPaused = true
        preferredFramesPerSecond = 60
        clearColor = MTLClearColorMake(0.025, 0.032, 0.049, 1)
        backgroundColor = UIColor(red: 0.025, green: 0.032, blue: 0.049, alpha: 1)
        if let gpu, let library = try? gpu.makeDefaultLibrary(bundle: .main) {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "mascotAuroraVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "mascotAuroraFragment")
            descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
            pipeline = try? gpu.makeRenderPipelineState(descriptor: descriptor)
            commandQueue = gpu.makeCommandQueue()
        }
        delegate = self
        for name in [UIApplication.didBecomeActiveNotification,
                     UIAccessibility.reduceMotionStatusDidChangeNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(updateAnimation), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(suspendAnimation),
                                               name: UIApplication.willResignActiveNotification, object: nil)
    }

    required init(coder: NSCoder) { fatalError("Use init()") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateAnimation()
    }

    @objc private func updateAnimation() {
        let reducedMotion = UIAccessibility.isReduceMotionEnabled
        let visible = isActive && window != nil && UIApplication.shared.applicationState == .active
        enableSetNeedsDisplay = reducedMotion
        isPaused = !visible || reducedMotion || pipeline == nil
        if visible && reducedMotion { setNeedsDisplay() }
    }

    @objc private func suspendAnimation() { isPaused = true }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard bounds.width > 0, bounds.height > 0,
              let pipeline, let commandQueue,
              framesInFlight.wait(timeout: .now()) == .success else { return }
        guard let drawable = currentDrawable, let pass = currentRenderPassDescriptor,
              let command = commandQueue.makeCommandBuffer(),
              let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            framesInFlight.signal()
            return
        }
        let time = UIAccessibility.isReduceMotionEnabled ? 0 : Float(CACurrentMediaTime() - startTime)
        var uniforms = SIMD4<Float>(Float(bounds.width), Float(bounds.height), time, 0.75)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        let semaphore = framesInFlight
        command.addCompletedHandler { _ in semaphore.signal() }
        command.present(drawable)
        command.commit()
    }
}
