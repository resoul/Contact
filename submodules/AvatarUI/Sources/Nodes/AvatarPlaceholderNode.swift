import UIKit
import AsyncDisplayKit

public final class AvatarPlaceholderNode: ASDisplayNode {
    private let letters = ASTextNode()
    private let gradient = CAGradientLayer()
    private var initials = ""
    private var colors: [UIColor] = [.systemBlue, .systemIndigo]
    private var renderedInitials: String?
    private var renderedFontSize: CGFloat = 0

    public override init() {
        super.init()
        isUserInteractionEnabled = false
        letters.isUserInteractionEnabled = false
        letters.maximumNumberOfLines = 1
        addSubnode(letters)
    }
    public override func didLoad() {
        super.didLoad()
        gradient.startPoint = .zero
        gradient.endPoint = CGPoint(x: 0, y: 1)
        layer.insertSublayer(gradient, at: 0)
    }
    func apply(_ descriptor: AvatarDescriptor) {
        initials = descriptor.initials
        colors = descriptor.colors
        setNeedsLayout()
    }
    public override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        gradient.colors = colors.map { $0.resolvedColor(with: view.traitCollection).cgColor }
        CATransaction.commit()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let fontSize = max(1, min(bounds.width, bounds.height) * 0.4)
        if renderedInitials != initials || renderedFontSize != fontSize {
            renderedInitials = initials
            renderedFontSize = fontSize
            letters.attributedText = NSAttributedString(string: initials, attributes: [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: UIColor.white, .paragraphStyle: paragraph,
            ])
        }
        let size = letters.layoutThatFits(ASSizeRange(min: .zero, max: bounds.size)).size
        letters.frame = CGRect(x: 0, y: (bounds.height - size.height) / 2, width: bounds.width, height: size.height)
    }
}
