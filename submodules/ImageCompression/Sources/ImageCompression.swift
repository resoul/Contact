import Foundation
import UIKit
import ImageIO
import UniformTypeIdentifiers
import MozjpegBinding

public func scaleImageToPixelSize(image: UIImage, size: CGSize) -> UIImage? {
    guard size.width.isFinite, size.height.isFinite, size.width >= 1, size.height >= 1,
          size.width <= 65_500, size.height <= 65_500, size.width * size.height <= 32_000_000 else { return nil }
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    format.preferredRange = .standard
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
        UIColor.white.setFill()
        context.fill(CGRect(origin: .zero, size: size))
        image.draw(in: CGRect(origin: .zero, size: size))
    }
}

public func extractImageExtraScans(_ data: Data) -> [Int] {
    extractJPEGDataScans(data).map(\.intValue)
}

// Matches Telegram: mozjpeg uses fixed quality 72; quality is for the ImageIO fallback.
public func compressImageToJPEG(_ image: UIImage, quality: Float, tempFilePath: String) -> Data? {
    compressJPEGData(image, tempFilePath) ?? systemEncode(image, quality: quality, type: .jpeg)
}

public func compressImageToJPEGXL(_ image: UIImage, quality: Int) -> Data? {
    guard (0...100).contains(quality) else { return nil }
    return compressJPEGXLData(image, Int32(quality))
}

public func decompressImageFromJPEGXL(data: Data) -> UIImage? { decompressJPEGXLData(data) }

public func compressImage(_ image: UIImage, quality: Float) -> Data? {
    systemEncode(image, quality: quality, type: .heic)
}

private func systemEncode(_ image: UIImage, quality: Float, type: UTType) -> Data? {
    guard quality.isFinite, (0...1).contains(quality), image.cgImage != nil,
          let normalized = scaleImageToPixelSize(image: image, size: CGSize(
            width: image.size.width * image.scale, height: image.size.height * image.scale)),
          let cgImage = normalized.cgImage else { return nil }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(destination, cgImage,
        [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    guard CGImageDestinationFinalize(destination), data.length > 0 else { return nil }
    return data as Data
}

public enum MiniThumbnailType { case image, avatar }

public func compressImageMiniThumbnail(_ image: UIImage, type: MiniThumbnailType = .image) -> Data? {
    switch type {
    case .image:
        return compressMiniThumbnail(image, CGSize(width: 40, height: 40))
    case .avatar:
        var result = compressMiniThumbnail(image, CGSize(width: 8, height: 8))
        // Bound the search: tiny flat images may never reach the byte threshold.
        for size in 9...255 {
            guard let candidate = compressMiniThumbnail(image, CGSize(width: size, height: size)),
                  candidate.count < 32 else { break }
            if candidate == result { break }
            result = candidate
        }
        return result
    }
}
