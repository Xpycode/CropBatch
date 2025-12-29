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
    case filenameCollision(String)

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
        case .filenameCollision(let filename):
            return "Filename collision detected: \(filename). Multiple images would export to the same file."
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

    /// Resizes an NSImage to the specified size using CGContext (thread-safe)
    /// - Parameters:
    ///   - image: The source image to resize
    ///   - targetSize: The target size in pixels
    /// - Returns: A new resized NSImage
    static func resize(_ image: NSImage, to targetSize: CGSize) -> NSImage {
        // Validate target size
        let targetWidth = Int(targetSize.width)
        let targetHeight = Int(targetSize.height)
        guard targetWidth > 0 && targetHeight > 0 else {
            return image
        }

        // Create a bitmap context at the target size
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        // Set high quality interpolation for good downscaling
        context.interpolationQuality = .high

        // Create NSGraphicsContext from CGContext to draw the NSImage
        // This properly handles all NSImage representations and transforms
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext

        // Draw the NSImage scaled to fit the context
        // CGContext has origin at bottom-left, NSImage.draw also uses bottom-left
        let targetRect = NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
        image.draw(in: targetRect,
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)

        NSGraphicsContext.restoreGraphicsState()

        guard let resizedCGImage = context.makeImage() else { return image }
        return NSImage(cgImage: resizedCGImage, size: targetSize)
    }

    // MARK: - Rotation and Flip

    /// Rotates an image by the specified angle using CGContext (thread-safe)
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

        let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(rotatedSize.width),
            height: Int(rotatedSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        // Move origin to center, rotate, then draw
        context.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
        context.rotate(by: radians)
        context.translateBy(x: -image.size.width / 2, y: -image.size.height / 2)
        context.draw(cgImage, in: CGRect(origin: .zero, size: image.size))

        guard let rotatedCGImage = context.makeImage() else { return image }
        return NSImage(cgImage: rotatedCGImage, size: rotatedSize)
    }

    /// Flips an image horizontally and/or vertically using CGContext (thread-safe)
    /// - Parameters:
    ///   - image: The source image
    ///   - horizontal: Flip horizontally
    ///   - vertical: Flip vertically
    /// - Returns: Flipped image
    static func flip(_ image: NSImage, horizontal: Bool, vertical: Bool) -> NSImage {
        guard horizontal || vertical else { return image }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }

        let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(image.size.width),
            height: Int(image.size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        // Apply flip transforms
        context.translateBy(
            x: horizontal ? image.size.width : 0,
            y: vertical ? image.size.height : 0
        )
        context.scaleBy(
            x: horizontal ? -1 : 1,
            y: vertical ? -1 : 1
        )
        context.draw(cgImage, in: CGRect(origin: .zero, size: image.size))

        guard let flippedCGImage = context.makeImage() else { return image }
        return NSImage(cgImage: flippedCGImage, size: image.size)
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

    /// Applies blur regions to an image using CGContext (thread-safe)
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
        let ciContext = CIContext(options: [.useSoftwareRenderer: false])

        // Create CGContext for drawing
        let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(image.size.width),
            height: Int(image.size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        // Draw original image first
        context.draw(cgImage, in: CGRect(origin: .zero, size: image.size))

        // Apply each blur region
        for region in regions {
            // Convert rect to CG coordinates (origin at bottom-left)
            let flippedRect = CGRect(
                x: region.rect.origin.x,
                y: image.size.height - region.rect.origin.y - region.rect.height,
                width: region.rect.width,
                height: region.rect.height
            )

            switch region.style {
            case .blur:
                let radius = region.effectiveBlurRadius
                if let blurredRegion = createBlurredRegion(from: ciImage, in: flippedRect, radius: radius, ciContext: ciContext) {
                    context.draw(blurredRegion, in: flippedRect)
                }

            case .pixelate:
                let scale = region.effectivePixelateScale(for: flippedRect)
                if let pixelatedRegion = createPixelatedRegion(from: ciImage, in: flippedRect, scale: scale, ciContext: ciContext) {
                    context.draw(pixelatedRegion, in: flippedRect)
                }

            case .solidBlack:
                context.setFillColor(CGColor(gray: 0, alpha: 1))
                context.fill(flippedRect)

            case .solidWhite:
                context.setFillColor(CGColor(gray: 1, alpha: 1))
                context.fill(flippedRect)
            }
        }

        guard let resultImage = context.makeImage() else { return image }
        return NSImage(cgImage: resultImage, size: image.size)
    }

    /// Creates a blurred CGImage for a region
    private static func createBlurredRegion(from ciImage: CIImage, in rect: CGRect, radius: Double, ciContext: CIContext) -> CGImage? {
        let cropped = ciImage.cropped(to: rect)

        guard let blurFilter = CIFilter(name: "CIGaussianBlur") else { return nil }
        blurFilter.setValue(cropped, forKey: kCIInputImageKey)
        blurFilter.setValue(radius, forKey: kCIInputRadiusKey)

        guard let blurred = blurFilter.outputImage else { return nil }

        // Crop back to original rect (blur extends beyond bounds)
        let clipped = blurred.cropped(to: rect)

        return ciContext.createCGImage(clipped, from: rect)
    }

    /// Creates a pixelated CGImage for a region
    private static func createPixelatedRegion(from ciImage: CIImage, in rect: CGRect, scale: Double, ciContext: CIContext) -> CGImage? {
        let cropped = ciImage.cropped(to: rect)

        guard let pixelateFilter = CIFilter(name: "CIPixellate") else { return nil }
        pixelateFilter.setValue(cropped, forKey: kCIInputImageKey)
        pixelateFilter.setValue(scale, forKey: kCIInputScaleKey)

        let centerVector = CIVector(x: rect.midX, y: rect.midY)
        pixelateFilter.setValue(centerVector, forKey: kCIInputCenterKey)

        guard let pixelated = pixelateFilter.outputImage else { return nil }

        let clipped = pixelated.cropped(to: rect)

        return ciContext.createCGImage(clipped, from: rect)
    }

    // ┌─────────────────────────────────────────────────────────────────────┐
    // │  CRITICAL: Image Orientation Handling                              │
    // │                                                                     │
    // │  NSImage.cgImage(forProposedRect:) returns RAW pixel data that     │
    // │  may NOT match the displayed orientation. iPhone screenshots       │
    // │  often have EXIF orientation metadata - the raw CGImage might      │
    // │  be stored rotated/flipped with metadata saying "display it        │
    // │  this way". NSImage handles this for display, but the raw          │
    // │  CGImage doesn't.                                                  │
    // │                                                                     │
    // │  SOLUTION: Draw the NSImage into a new CGContext first. This       │
    // │  "bakes in" any orientation transforms, giving us pixel data       │
    // │  that matches what the user sees. Then crop in standard coords.    │
    // │                                                                     │
    // │  Fixed: 2025-12-29                                                 │
    // └─────────────────────────────────────────────────────────────────────┘
    /// Crops an NSImage according to the provided settings
    /// - Parameters:
    ///   - image: The source image to crop
    ///   - settings: Crop settings specifying pixels to remove from each edge
    /// - Returns: A new cropped NSImage
    static func crop(_ image: NSImage, with settings: CropSettings) throws -> NSImage {
        // First, get a normalized CGImage by drawing the NSImage into a context.
        // This ensures any EXIF orientation is applied and we get pixel data
        // matching the displayed image.
        guard let normalizedCGImage = createNormalizedCGImage(from: image) else {
            throw ImageCropError.failedToGetCGImage
        }

        let originalWidth = normalizedCGImage.width
        let originalHeight = normalizedCGImage.height

        // Calculate crop rectangle in top-left origin coordinates (matching user's view)
        // Then convert to CGImage bottom-left origin for the actual crop
        let cropRect = CGRect(
            x: settings.cropLeft,
            y: settings.cropTop,  // In normalized image, y=0 is TOP (standard image coords)
            width: originalWidth - settings.cropLeft - settings.cropRight,
            height: originalHeight - settings.cropTop - settings.cropBottom
        )

        // Validate crop region
        guard cropRect.width > 0 && cropRect.height > 0 else {
            throw ImageCropError.invalidCropRegion
        }

        guard let croppedCGImage = normalizedCGImage.cropping(to: cropRect) else {
            throw ImageCropError.invalidCropRegion
        }

        return NSImage(cgImage: croppedCGImage, size: NSSize(width: cropRect.width, height: cropRect.height))
    }

    /// Creates a normalized CGImage from an NSImage by drawing it into a bitmap context.
    /// This applies any EXIF orientation transforms so the pixel data matches display.
    private static func createNormalizedCGImage(from image: NSImage) -> CGImage? {
        // Get the actual pixel dimensions
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height

        // Create a bitmap context with standard top-left origin
        let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Draw the NSImage into the context - this applies orientation transforms
        // Note: We use NSGraphicsContext to ensure NSImage draws correctly
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext

        // Draw in the full rect - NSImage will handle any internal orientation
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height),
                   from: .zero,
                   operation: .copy,
                   fraction: 1.0)

        NSGraphicsContext.restoreGraphicsState()

        return context.makeImage()
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
    /// Uses parallel processing with TaskGroup for better performance
    /// - Parameters:
    ///   - items: Array of ImageItem to process
    ///   - cropSettings: Crop settings to apply
    ///   - exportSettings: Export format and quality settings
    ///   - transforms: Dictionary of image transforms keyed by image ID
    ///   - blurRegions: Dictionary of blur regions keyed by image ID
    ///   - progress: Closure called with progress updates (0.0 to 1.0)
    /// - Returns: Array of URLs for successfully cropped images
    static func batchCrop(
        items: [ImageItem],
        cropSettings: CropSettings,
        exportSettings: ExportSettings,
        transforms: [UUID: ImageTransform] = [:],
        blurRegions: [UUID: ImageBlurData] = [:],
        progress: @escaping @MainActor (Double) -> Void
    ) async throws -> [URL] {
        let total = Double(items.count)

        // Pre-check: ensure no files would be overwritten
        for item in items {
            if exportSettings.wouldOverwriteOriginal(for: item.url) {
                throw ImageCropError.wouldOverwriteOriginal(item.filename)
            }
        }

        // Pre-check: ensure no filename collisions in batch
        if let collidingFilename = exportSettings.findBatchCollision(items: items) {
            throw ImageCropError.filenameCollision(collidingFilename)
        }

        // Process images in parallel using TaskGroup
        return try await withThrowingTaskGroup(of: (Int, URL).self) { group in
            for (index, item) in items.enumerated() {
                group.addTask {
                    let outputURL = try processSingleImage(
                        item: item,
                        index: index,
                        cropSettings: cropSettings,
                        exportSettings: exportSettings,
                        transforms: transforms,
                        blurRegions: blurRegions
                    )
                    return (index, outputURL)
                }
            }

            // Collect results and update progress
            var results = [(Int, URL)]()
            for try await result in group {
                results.append(result)
                await MainActor.run {
                    progress(Double(results.count) / total)
                }
            }

            // Sort by original index to maintain order
            return results.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }

    /// Processes a single image through the full pipeline
    private static func processSingleImage(
        item: ImageItem,
        index: Int,
        cropSettings: CropSettings,
        exportSettings: ExportSettings,
        transforms: [UUID: ImageTransform],
        blurRegions: [UUID: ImageBlurData]
    ) throws -> URL {
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
        return outputURL
    }
}
