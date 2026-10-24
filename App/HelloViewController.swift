import CPlugin
import ObjCPlugin
import ObjCXXPlugin
import SwiftPlugin
import UIKit

final class HelloViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        let heading = makeLabel("Hello from Bazel!", style: .title1)
        let messages = [
            "\(String(cString: c_plugin_message()))\n17 + 25 = \(c_plugin_add(17, 25))",
            "\(ObjCXXPlugin.cppMessage())\n6 × 7 = \(ObjCXXPlugin.multiply(6, by: 7)) (via Objective-C++)",
            "\(SwiftPlugin.message())\n20 + 22 = \(SwiftPlugin.add(20, 22))",
            "\(ObjCPlugin.message())\n50 − 8 = \(ObjCPlugin.subtract(8, from: 50))",
            "\(ObjCXXPlugin.message())\n−6 × −7 = \(ObjCXXPlugin.multiply(-6, by: -7))",
        ]

        let stack = UIStackView(arrangedSubviews: [heading] + messages.map { makeLabel($0) })
        stack.axis = .vertical
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(stack)

        let safeArea = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: safeArea.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 32),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -32),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -48),
        ])
    }

    private func makeLabel(_ text: String, style: UIFont.TextStyle = .body) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = .black
        label.font = .preferredFont(forTextStyle: style)
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }
}
