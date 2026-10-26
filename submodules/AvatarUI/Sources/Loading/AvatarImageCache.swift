import UIKit

public final class AvatarImageCache: @unchecked Sendable {
    public static let shared = AvatarImageCache()
    private let images = NSCache<NSString, UIImage>()

    public init() {
        images.totalCostLimit = 32 * 1024 * 1024
        images.countLimit = 200
    }

    func image(for key: String) -> UIImage? { images.object(forKey: key as NSString) }
    func store(_ image: UIImage, for key: String) {
        let cost = (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0)
        images.setObject(image, forKey: key as NSString, cost: cost)
    }
    public func removeAll() { images.removeAllObjects() }
}
