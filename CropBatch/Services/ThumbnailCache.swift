import AppKit

/// Thread-safe cache for thumbnail images using NSCache
/// NSCache is thread-safe internally, so we mark this as @unchecked Sendable
final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSURL, NSImage>()

    init() {
        cache.countLimit = 100
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB
    }

    /// Retrieves or generates a thumbnail for the given URL
    /// - Parameters:
    ///   - url: The source image URL
    ///   - size: Target thumbnail size
    /// - Returns: The thumbnail image, or nil if generation fails
    func thumbnail(for url: URL, size: CGSize) async -> NSImage? {
        let key = url as NSURL

        // Check cache first
        if let cached = cache.object(forKey: key) {
            return cached
        }

        // Generate thumbnail
        guard let image = NSImage(contentsOf: url) else { return nil }
        let thumbnail = await generateThumbnail(from: image, size: size)

        // Cache the result with estimated cost
        let cost = Int(size.width * size.height * 4) // Approximate bytes
        cache.setObject(thumbnail, forKey: key, cost: cost)

        return thumbnail
    }

    /// Invalidates the cached thumbnail for a specific URL
    func invalidate(for url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }

    /// Clears all cached thumbnails
    func clearAll() {
        cache.removeAllObjects()
    }

    /// Generates a thumbnail using high-quality CGContext scaling
    private func generateThumbnail(from image: NSImage, size: CGSize) async -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }

        // Calculate aspect-fit size
        let aspectRatio = image.size.width / image.size.height
        let targetSize: CGSize
        if aspectRatio > size.width / size.height {
            targetSize = CGSize(width: size.width, height: size.width / aspectRatio)
        } else {
            targetSize = CGSize(width: size.height * aspectRatio, height: size.height)
        }

        let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(targetSize.width),
            height: Int(targetSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(origin: .zero, size: targetSize))

        guard let thumbnailCGImage = context.makeImage() else { return image }
        return NSImage(cgImage: thumbnailCGImage, size: targetSize)
    }
}
