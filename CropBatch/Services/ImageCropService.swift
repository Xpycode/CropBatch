import AppKit
import CoreGraphics
import UniformTypeIdentifiers

enum ImageCropError: LocalizedError {
    case failedToGetCGImage
    case invalidCropRegion
    case failedToCreateDestination
    case failedToWriteImage

    var errorDescription: String? {
        switch self {
        case .failedToGetCGImage:
            return "Failed to convert image to bitmap format"
        case .invalidCropRegion:
            return "Crop region is larger than the image"
        case .failedToCreateDestination:
            return "Failed to create output file"
        case .failedToWriteImage:
            return "Failed to write cropped image"
        }
    }
}

struct ImageCropService {

    /// Crops an NSImage according to the provided settings
    /// - Parameters:
    ///   - image: The source image to crop
    ///   - settings: Crop settings specifying pixels to remove from each edge
    /// - Returns: A new cropped NSImage
    static func crop(_ image: NSImage, with settings: CropSettings) throws -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ImageCropError.failedToGetCGImage
        }

        let originalWidth = cgImage.width
        let originalHeight = cgImage.height

        // Calculate crop rectangle (CGImage origin is bottom-left, but cropping uses top-left)
        let cropRect = CGRect(
            x: settings.cropLeft,
            y: settings.cropTop,  // Top in image coordinates
            width: originalWidth - settings.cropLeft - settings.cropRight,
            height: originalHeight - settings.cropTop - settings.cropBottom
        )

        // Validate crop region
        guard cropRect.width > 0 && cropRect.height > 0 else {
            throw ImageCropError.invalidCropRegion
        }

        guard let croppedCGImage = cgImage.cropping(to: cropRect) else {
            throw ImageCropError.invalidCropRegion
        }

        return NSImage(cgImage: croppedCGImage, size: NSSize(width: cropRect.width, height: cropRect.height))
    }

    /// Saves an NSImage to a file URL
    /// - Parameters:
    ///   - image: The image to save
    ///   - url: Destination file URL
    ///   - format: Image format (png, jpeg, etc.)
    static func save(_ image: NSImage, to url: URL, format: UTType = .png) throws {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ImageCropError.failedToGetCGImage
        }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            format.identifier as CFString,
            1,
            nil
        ) else {
            throw ImageCropError.failedToCreateDestination
        }

        CGImageDestinationAddImage(destination, cgImage, nil)

        guard CGImageDestinationFinalize(destination) else {
            throw ImageCropError.failedToWriteImage
        }
    }

    /// Processes multiple images with the same crop settings
    /// - Parameters:
    ///   - items: Array of ImageItem to process
    ///   - settings: Crop settings to apply
    ///   - outputDirectory: Directory to save cropped images
    ///   - progress: Closure called with progress updates (0.0 to 1.0)
    /// - Returns: Array of URLs for successfully cropped images
    @MainActor
    static func batchCrop(
        items: [ImageItem],
        settings: CropSettings,
        outputDirectory: URL,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws -> [URL] {
        var outputURLs: [URL] = []
        let total = Double(items.count)

        for (index, item) in items.enumerated() {
            let croppedImage = try crop(item.originalImage, with: settings)

            // Determine output format based on original file extension
            let originalExtension = item.url.pathExtension.lowercased()
            let outputFormat: UTType = originalExtension == "jpg" || originalExtension == "jpeg" ? .jpeg : .png

            let outputFilename = "cropped_\(item.filename)"
            let outputURL = outputDirectory.appendingPathComponent(outputFilename)

            try save(croppedImage, to: outputURL, format: outputFormat)
            outputURLs.append(outputURL)

            progress(Double(index + 1) / total)
        }

        return outputURLs
    }
}
