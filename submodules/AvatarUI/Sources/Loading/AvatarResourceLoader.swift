import Foundation
import UIKit
import ImageIO
import CryptoKit

public actor AvatarResourceLoader {
    public static let shared = AvatarResourceLoader()
    private let cache: AvatarImageCache
    private let directory: URL

    public init(cache: AvatarImageCache = .shared, directory: URL? = nil) {
        self.cache = cache
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AvatarUI", isDirectory: true)
    }

    private func key(_ resource: AvatarResource) -> String {
        let value = "\(resource.id)|\(resource.version)|\(resource.url.absoluteString)"
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public func fileURL(for resource: AvatarResource) async throws -> URL {
        try Task.checkCancellation()
        if resource.url.isFileURL {
            guard FileManager.default.fileExists(atPath: resource.url.path) else { throw URLError(.fileDoesNotExist) }
            return resource.url
        }
        guard ["https", "http"].contains(resource.url.scheme?.lowercased() ?? "") else { throw URLError(.unsupportedURL) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(key(resource)).appendingPathExtension(resource.url.pathExtension)
        if FileManager.default.fileExists(atPath: destination.path) { return destination }
        let (temporary, response) = try await URLSession.shared.download(from: resource.url)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        // Another consumer may have completed the same resource during the await.
        if !FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
        trimDiskCache(keeping: destination)
        return destination
    }

    public func image(for resource: AvatarResource, pixelSize: Int) async throws -> UIImage {
        let size = min(max(1, pixelSize), 2048)
        let cacheKey = "\(key(resource))|\(size)"
        if let image = cache.image(for: cacheKey) { return image }
        let url = try await fileURL(for: resource)
        let decoded = Task.detached(priority: .userInitiated) { () throws -> UIImage in
            try Task.checkCancellation()
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: size,
                    kCGImageSourceShouldCacheImmediately: true,
                  ] as CFDictionary) else { throw URLError(.cannotDecodeContentData) }
            return UIImage(cgImage: image)
        }
        let image = try await withTaskCancellationHandler(operation: { try await decoded.value },
                                                         onCancel: { decoded.cancel() })
        try Task.checkCancellation()
        cache.store(image, for: cacheKey)
        return image
    }

    private func trimDiskCache(keeping current: URL) {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys)) else { return }
        var files = urls.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }
        var total = files.reduce(0) { $0 + $1.1 }
        files.sort { $0.2 < $1.2 }
        for (url, bytes, _) in files where total > 128 * 1024 * 1024 && url != current {
            if (try? FileManager.default.removeItem(at: url)) != nil { total -= bytes }
        }
    }
}
