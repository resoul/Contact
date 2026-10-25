import UIKit

/// GPU implementation: the whole bar, including the boiling lava, the meniscus and the empty track,
/// is computed per pixel in `lava_fragment` (Lava.metal).
final class MetalLavaProgressBarView: MetalAnimationView {
    override class var fragmentFunction: String? { "lava_fragment" }

    override var controls: [MetalEffectControl] {
        [.slider(title: "Заполнение", range: 0...1, value: progress,
                 format: { "\(Int(($0 * 100).rounded()))%" },
                 onChange: { [weak self] in self?.progress = $0 })]
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}
