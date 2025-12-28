import AppKit
import CoreGraphics
import CoreImage
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

    /// Calculates the target size based on resize settings
    /// - Parameters:
    ///   - originalSize: The original image size
    ///   - settings: Resize settings
    /// - Returns: The target size, or nil if no resize is needed
    static func calculateResizedSize(from originalSize: CGSize, with settings: ResizeSettings) -> CGSize? {
        guard settings.isEnabled else { return nil }

        switch settings.mode {
        case .none:
            return nil

        case .exactSize:
            if settings.maintainAspectRatio {
                let scaleX = CGFloat(settings.width) / originalSize.width
                let scaleY = CGFloat(settings.height) / originalSize.height
                let scale = min(scaleX, scaleY)
                return CGSize(
                    width: originalSize.width * scale,
                    height: originalSize.height * scale
                )
            } else {
                return CGSize(width: settings.width, height: settings.height)
            }

        case .maxWidth:
            guard originalSize.width > CGFloat(settings.width) else { return nil }
            let scale = CGFloat(settings.width) / originalSize.width
            return CGSize(
                width: CGFloat(settings.width),
                height: originalSize.height * scale
            )

        case .maxHeight:
            guard originalSize.height > CGFloat(settings.height) else { return nil }
            let scale = CGFloat(settings.height) / originalSize.height
            return CGSize(
                width: originalSize.width * scale,
                height: CGFloat(settings.height)
            )

        case .percentage:
            let scale = settings.percentage / 100.0
            return CGSize(
                width: originalSize.width * scale,
                height: originalSize.height * scale
            )
        }
    }

    /// Resizes an NSImage to the specified size
    /// - Parameters:
    ///   - image: The source image to resize
    ///   - targetSize: The target size
    /// - Returns: A new resized NSImage
    static func resize(_ image: NSImage, to targetSize: CGSize) -> NSImage {
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1.0
        )
        newImage.unlockFocus()
        return newImage
    }

    // MARK: - Rotation and Flip

    /// Rotates an image by the specified angle
    /// - Parameters:
    ///   - image: The source image
    ///   - angle: Rotation angle (90, 180, or 270 degrees)
    /// - Returns: Rotated image
    static func rotate(_ image: NSImage, by angle: RotationAngle) -> NSImage {
        guard angle != .none else { return image }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }

        let radians = CGFloat(angle.rawValue) * .pi / 180
        let rotatedSize = angle.swapsWidthAndHeight
            ? CGSize(width: image.size.height, height: image.size.width)
            : image.size

        let newImage = NSImage(size: rotatedSize)
        newImage.lockFocus()

        guard let context = NSGraphicsContext.current?.cgContext else {
            newImage.unlockFocus()
            return image
        }

        // Move origin to center, rotate, then draw
        context.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
        context.rotate(by: radians)
        context.translateBy(x: -image.size.width / 2, y: -image.size.height / 2)
        context.draw(cgImage, in: CGRect(origin: .zero, size: image.size))

        newImage.unlockFocus()
        return newImage
    }

    /// Flips an image horizontally and/or vertically
    /// - Parameters:
    ///   - image: The source image
    ///   - horizontal: Flip horizontally
    ///   - vertical: Flip vertically
    /// - Returns: Flipped image
    static func flip(_ image: NSImage, horizontal: Bool, vertical: Bool) -> NSImage {
        guard horizontal || vertical else { return image }

        let newImage = NSImage(size: image.size)
        newImage.lockFocus()

        guard let context = NSGraphicsContext.current else {
            newImage.unlockFocus()
            return image
        }

        context.saveGraphicsState()

        let transform = NSAffineTransform()
        transform.translateX(by: horizontal ? image.size.width : 0,
                             yBy: vertical ? image.size.height : 0)
        transform.scaleX(by: horizontal ? -1 : 1, yBy: vertical ? -1 : 1)
        transform.concat()

        image.draw(at: .zero, from: .zero, operation: .copy, fraction: 1.0)

        context.restoreGraphicsState()
        newImage.unlockFocus()
        return newImage
    }

    /// Applies a complete transform (rotation + flip) to an image
    /// - Parameters:
    ///   - image: The source image
    ///   - transform: The transform to apply
    /// - Returns: Transformed image
    static func applyTransform(_ image: NSImage, transform: ImageTransform) -> NSImage {
        guard !transform.isIdentity else { return image }

        var result = image

        // Apply rotation first
        if transform.rotation != .none {
            result = rotate(result, by: transform.rotation)
        }

        // Then apply flip
        if transform.flipHorizontal || transform.flipVertical {
            result = flip(result, horizontal: transform.flipHorizontal, vertical: transform.flipVertical)
        }

        return result
    }

    /// Applies blur regions to an image
    /// - Parameters:
    ///   - image: The source image
    ///   - regions: Array of blur regions to apply
    /// - Returns: A new image with blur regions applied
    static func applyBlurRegions(_ image: NSImage, regions: [BlurRegion]) -> NSImage {
        guard !regions.isEmpty else { return image }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }

        let ciImage = CIImage(cgImage: cgImage)
        let context = CIContext(options: [.useSoftwareRenderer: false])

        // Create mutable copy to draw on
        let newImage = NSImage(size: image.size)
        newImage.lockFocus()

        // Draw original image first
        image.draw(
            in: NSRect(origin: .zero, size: image.size),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1.0
        )

        // Apply each blur region
        for region in regions {
            // Convert rect to image coordinates (flip Y for CG coordinate system)
            let flippedRect = CGRect(
                x: region.rect.origin.x,
                y: image.size.height - region.rect.origin.y - region.rect.height,
                width: region.rect.width,
                height: region.rect.height
            )

            switch region.style {
            case .blur:
                let radius = region.effectiveBlurRadius
                applyGaussianBlur(to: ciImage, in: flippedRect, radius: radius, context: context, imageSize: image.size)

            case .pixelate:
                let scale = region.effectivePixelateScale(for: flippedRect)
                applyPixelate(to: ciImage, in: flippedRect, scale: scale, context: context, imageSize: image.size)

            case .solidBlack:
                NSColor.black.setFill()
                NSBezierPath(rect: NSRect(
                    x: region.rect.origin.x,
                    y: image.size.height - region.rect.origin.y - region.rect.height,
                    width: region.rect.width,
                    height: region.rect.height
                )).fill()

            case .solidWhite:
                NSColor.white.setFill()
                NSBezierPath(rect: NSRect(
                    x: region.rect.origin.x,
                    y: image.size.height - region.rect.origin.y - region.rect.height,
                    width: region.rect.width,
                    height: region.rect.height
                )).fill()
            }
        }

        newImage.unlockFocus()
        return newImage
    }

    /// Applies gaussian blur to a region
    private static func applyGaussianBlur(to ciImage: CIImage, in rect: CGRect, radius: Double, context: CIContext, imageSize: CGSize) {
        // Crop the region
        let cropped = ciImage.cropped(to: rect)

        // Apply blur with configurable radius
        guard let blurFilter = CIFilter(name: "CIGaussianBlur") else { return }
        blurFilter.setValue(cropped, forKey: kCIInputImageKey)
        blurFilter.setValue(radius, forKey: kCIInputRadiusKey)

        guard let blurred = blurFilter.outputImage else { return }

        // Crop back to original rect (blur extends beyond bounds)
        let clipped = blurred.cropped(to: rect)

        // Render and draw
        guard let cgResult = context.createCGImage(clipped, from: rect) else { return }
        let nsResult = NSImage(cgImage: cgResult, size: rect.size)

        nsResult.draw(
            in: NSRect(origin: CGPoint(x: rect.origin.x, y: rect.origin.y), size: rect.size),
            from: NSRect(origin: .zero, size: rect.size),
            operation: .sourceOver,
            fraction: 1.0
        )
    }

    /// Applies pixelation to a region
    private static func applyPixelate(to ciImage: CIImage, in rect: CGRect, scale: Double, context: CIContext, imageSize: CGSize) {
        // Crop the region
        let cropped = ciImage.cropped(to: rect)

        // Apply pixelate with configurable scale
        guard let pixelateFilter = CIFilter(name: "CIPixellate") else { return }
        pixelateFilter.setValue(cropped, forKey: kCIInputImageKey)
        pixelateFilter.setValue(scale, forKey: kCIInputScaleKey)

        // Center on the region
        let centerVector = CIVector(x: rect.midX, y: rect.midY)
        pixelateFilter.setValue(centerVector, forKey: kCIInputCenterKey)

        guard let pixelated = pixelateFilter.outputImage else { return }

        // Crop back to original rect
        let clipped = pixelated.cropped(to: rect)

        // Render and draw
        guard let cgResult = context.createCGImage(clipped, from: rect) else { return }
        let nsResult = NSImage(cgImage: cgResult, size: rect.size)

        nsResult.draw(
            in: NSRect(origin: CGPoint(x: rect.origin.x, y: rect.origin.y), size: rect.size),
            from: NSRect(origin: .zero, size: rect.size),
            operation: .sourceOver,
            fraction: 1.0
        )
    }

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
        case .heic, .webp:
            // HEIC and WebP require CGImageDestination
            let utType = format == .heic ? UTType.heic : UTType.webP
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                data as CFMutableData,
                utType.identifier as CFString,
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
    ///   - transforms: Dictionary of image transforms keyed by image ID
    ///   - blurRegions: Dictionary of blur regions keyed by image ID
    ///   - progress: Closure called with progress updates (0.0 to 1.0)
    /// - Returns: Array of URLs for successfully cropped images
    @MainActor
    static func batchCrop(
        items: [ImageItem],
        cropSettings: CropSettings,
        exportSettings: ExportSettings,
        transforms: [UUID: ImageTransform] = [:],
        blurRegions: [UUID: ImageBlurData] = [:],
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
            var processedImage = item.originalImage

            // Pipeline order: Transform -> Blur -> Crop -> Resize

            // 1. Apply transform (rotation/flip) FIRST
            if let transform = transforms[item.id], !transform.isIdentity {
                processedImage = applyTransform(processedImage, transform: transform)
            }

            // 2. Apply blur regions (in transformed image coordinates)
            if let imageBlurData = blurRegions[item.id], imageBlurData.hasRegions {
                processedImage = applyBlurRegions(processedImage, regions: imageBlurData.regions)
            }

            // 3. Apply crop
            processedImage = try crop(processedImage, with: cropSettings)

            // 4. Apply resize if enabled
            if let targetSize = calculateResizedSize(from: processedImage.size, with: exportSettings.resizeSettings) {
                processedImage = resize(processedImage, to: targetSize)
            }

            // Get output URL from export settings (with index for batch rename)
            let outputURL = exportSettings.outputURL(for: item.url, index: index)

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

            try save(processedImage, to: outputURL, format: format, quality: exportSettings.quality)
            outputURLs.append(outputURL)

            progress(Double(index + 1) / total)
        }

        return outputURLs
    }
}
