import UIKit
import Symbols

// Keep native symbol animations on iOS 17+ and cross-fade on iOS 16.
enum ContactSymbolTransition { case replace, offUp, downUp }

extension UIImageView {
    func setContactSymbol(_ image: UIImage, transition: ContactSymbolTransition = .replace) {
        if #available(iOS 17.0, *) {
            switch transition {
            case .replace: setSymbolImage(image, contentTransition: .replace)
            case .offUp: setSymbolImage(image, contentTransition: .replace.offUp)
            case .downUp: setSymbolImage(image, contentTransition: .replace.downUp)
            }
        } else {
            UIView.transition(with: self, duration: 0.2, options: .transitionCrossDissolve) { self.image = image }
        }
    }
}
