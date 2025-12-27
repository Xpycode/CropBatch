import AppKit
import CoreGraphics
import UniformTypeIdentifiers

enum ImageCropError: LocalizedError {
    case failedToGetCGImage
    case invalidCropRegion
    case failedToCreateDestination
    case failedToWriteImage
    case wouldOverwriteOriginal(String)

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
        case .wouldOverwriteOriginal(let filename):
            return "Would overwrite original file: \(filename). Please use a different suffix."
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
    ///   - quality: Compression quality (0.0 to 1.0) for JPEG/HEIC
    static func save(_ image: NSImage, to url: URL, format: UTType = .png, quality: Double = 0.9) throws {
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

        // Build properties dictionary for compression
        var properties: [CFString: Any] = [:]
        if format == .jpeg || format == .heic {
            properties[kCGImageDestinationLossyCompressionQuality] = quality
        }

        let cfProperties = properties.isEmpty ? nil : properties as CFDictionary
        CGImageDestinationAddImage(destination, cgImage, cfProperties)

        guard CGImageDestinationFinalize(destination) else {
            throw ImageCropError.failedToWriteImage
        }
    }

    /// Encodes an NSImage to Data in the specified format
    /// - Parameters:
    ///   - image: The image to encode
    ///   - format: Export format
    ///   - quality: Compression quality (0.0 to 1.0) for lossy formats
    /// - Returns: Encoded image data, or nil if encoding fails
    static func encode(_ image: NSImage, format: ExportFormat, quality: Double = 0.9) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)

        switch format {
        case .png:
            return bitmapRep.representation(using: .png, properties: [:])
        case .jpeg:
            return bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: quality])
        case .heic:
            // HEIC requires CGImageDestination
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                data as CFMutableData,
                UTType.heic.identifier as CFString,
                1,
                nil
            ) else { return nil }
            CGImageDestinationAddImage(destination, cgImage, [
                kCGImageDestinationLossyCompressionQuality: quality
            ] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { return nil }
            return data as Data
        case .tiff:
            return bitmapRep.representation(using: .tiff, properties: [:])
        }
    }

    /// Processes multiple images with the same crop and export settings
    /// - Parameters:
    ///   - items: Array of ImageItem to process
    ///   - cropSettings: Crop settings to apply
    ///   - exportSettings: Export format and quality settings
    ///   - progress: Closure called with progress updates (0.0 to 1.0)
    /// - Returns: Array of URLs for successfully cropped images
    @MainActor
    static func batchCrop(
        items: [ImageItem],
        cropSettings: CropSettings,
        exportSettings: ExportSettings,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws -> [URL] {
        var outputURLs: [URL] = []
        let total = Double(items.count)

        // Pre-check: ensure no files would be overwritten
        for item in items {
            if exportSettings.wouldOverwriteOriginal(for: item.url) {
                throw ImageCropError.wouldOverwriteOriginal(item.filename)
            }
        }

        for (index, item) in items.enumerated() {
            let croppedImage = try crop(item.originalImage, with: cropSettings)

            // Get output URL from export settings
            let outputURL = exportSettings.outputURL(for: item.url)

            // Determine the actual format to use
            let format: UTType
            if exportSettings.preserveOriginalFormat {
                let ext = item.url.pathExtension.lowercased()
                format = ExportFormat.allCases.first {
                    $0.fileExtension == ext || (ext == "jpeg" && $0 == .jpeg)
                }?.utType ?? exportSettings.format.utType
            } else {
                format = exportSettings.format.utType
            }

            try save(croppedImage, to: outputURL, format: format, quality: exportSettings.quality)
            outputURLs.append(outputURL)

            progress(Double(index + 1) / total)
        }

        return outputURLs
    }
}
