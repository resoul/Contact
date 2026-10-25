import UIKit

/// GPU implementation of the procedural fire (`fire_fragment` in Fire.metal).
final class MetalFireView: MetalAnimationView {
    override class var fragmentFunction: String? { "fire_fragment" }

    override var controls: [MetalEffectControl] {
        [.slider(title: "Пламя", range: 0...1, value: progress,
                 format: { "\(Int(($0 * 100).rounded()))%" },
                 onChange: { [weak self] in self?.progress = $0 })]
    }
}
