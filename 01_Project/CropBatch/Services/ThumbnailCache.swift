import AppKit

/// Thread-safe cache for thumbnail images using actor isolation
/// Uses in-flight task tracking to prevent duplicate generation for the same URL
actor ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    init() {
        cache.countLimit = Config.Cache.thumbnailCountLimit
        cache.totalCostLimit = Config.Cache.thumbnailSizeLimit
    }

    /// Retrieves or generates a thumbnail for the given URL
    /// - Parameters:
    ///   - url: The source image URL
    ///   - size: Target thumbnail size
    /// - Returns: The thumbnail image, or nil if generation fails
    func thumbnail(for url: URL, size: CGSize) async -> NSImage? {
        // Create a composite key that includes both URL and size
        let key = "\(url.absoluteString)|\(Int(size.width))x\(Int(size.height))"
        let cacheKey = key as NSString

        // Check cache first
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        // Check if already generating this thumbnail
        if let existingTask = inFlight[key] {
            return await existingTask.value
        }

        // Create a new generation task
        let task = Task<NSImage?, Never> {
            guard let image = NSImage(contentsOf: url) else { return nil }
            return await generateThumbnail(from: image, size: size)
        }

        // Track the in-flight task
        inFlight[key] = task

        // Await the result
        let result = await task.value

        // Clean up in-flight tracking
        inFlight.removeValue(forKey: key)

        // Cache the result if successful
        if let thumbnail = result {
            let cost = Int(size.width * size.height * 4) // Approximate bytes
            cache.setObject(thumbnail, forKey: cacheKey, cost: cost)
        }

        return result
    }

    /// Invalidates the cached thumbnail for a specific URL at all sizes
    func invalidate(for url: URL) {
        // Since we use composite keys, we need to remove all size variants
        // For simplicity, clear the entire cache - NSCache handles this efficiently
        // A more sophisticated approach would track keys per URL
        cache.removeAllObjects()
    }

    /// Clears all cached thumbnails
    func clearAll() {
        cache.removeAllObjects()
        inFlight.removeAll()
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
