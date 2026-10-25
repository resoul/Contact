import UIKit

/// User-facing effect settings, independent of the screen that presents them.
enum MetalEffectControl {
    case slider(
        title: String,
        range: ClosedRange<Float>,
        value: Float,
        isLogarithmic: Bool = false,
        format: (Float) -> String,
        onChange: (Float) -> Void
    )
    case segments(items: [String], selected: Int, onChange: (Int) -> Void)
    case button(title: String, action: () -> Void)
}
