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

        // CRITICAL: Use CGImage pixel dimensions, NOT NSImage.size (which is in points)
        // On Retina displays, points ≠ pixels. Using points causes resolution loss.
        let pixelWidth = CGFloat(cgImage.width)
        let pixelHeight = CGFloat(cgImage.height)

        // CRITICAL: CGContext.rotate() uses mathematical convention (positive = CCW)
        // We want positive angles to mean clockwise (user expectation), so negate.
        let radians = -CGFloat(angle.rawValue) * .pi / 180
        let rotatedSize = angle.swapsWidthAndHeight
            ? CGSize(width: pixelHeight, height: pixelWidth)
            : CGSize(width: pixelWidth, height: pixelHeight)

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

        // Move origin to center, rotate, then draw using pixel dimensions
        context.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
        context.rotate(by: radians)
        context.translateBy(x: -pixelWidth / 2, y: -pixelHeight / 2)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

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

        // CRITICAL: Use CGImage pixel dimensions, NOT NSImage.size (which is in points)
        // On Retina displays, points ≠ pixels. Using points causes resolution loss
        // and was the cause of "flip only works after rotation" bug.
        let pixelWidth = CGFloat(cgImage.width)
        let pixelHeight = CGFloat(cgImage.height)
        let pixelSize = CGSize(width: pixelWidth, height: pixelHeight)

        let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(pixelWidth),
            height: Int(pixelHeight),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        // Apply flip transforms using pixel dimensions
        context.translateBy(
            x: horizontal ? pixelWidth : 0,
            y: vertical ? pixelHeight : 0
        )
        context.scaleBy(
            x: horizontal ? -1 : 1,
            y: vertical ? -1 : 1
        )
        context.draw(cgImage, in: CGRect(origin: .zero, size: pixelSize))

        guard let flippedCGImage = context.makeImage() else { return image }
        return NSImage(cgImage: flippedCGImage, size: pixelSize)
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

    // MARK: - Blur Region Pipeline
    //
    // Uses normalized coordinates (0.0-1.0) throughout, converting to CGImage
    // coordinates (bottom-left origin) only at the final render step.
    //
    // Key fixes from previous implementation:
    // 1. Uses clampedToExtent() before blur to prevent edge artifacts
    // 2. Single coordinate conversion path via NormalizedRect
    // 3. GPU-accelerated via CIContext

    /// Applies blur regions to an image using Core Image (thread-safe, GPU-accelerated)
    /// - Parameters:
    ///   - image: The source image (EXIF orientation should already be baked in)
    ///   - regions: Array of blur regions with normalized coordinates
    /// - Returns: A new image with blur regions applied
    static func applyBlurRegions(_ image: NSImage, regions: [BlurRegion]) -> NSImage {
        guard !regions.isEmpty else { return image }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }

        let imageSize = image.size
        let ciImage = CIImage(cgImage: cgImage)
        let ciContext = CIContext(options: [.useSoftwareRenderer: false])

        // Create CGContext for compositing
        let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(imageSize.width),
            height: Int(imageSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        // Draw original image first
        context.draw(cgImage, in: CGRect(origin: .zero, size: imageSize))

        // Apply each blur region
        for region in regions {
            // Convert normalized rect to CGImage coordinates (bottom-left origin)
            let cgImageRect = region.cgImageRect(for: imageSize)

            switch region.style {
            case .blur:
                let radius = region.effectiveBlurRadius
                if let blurredRegion = createBlurredRegion(
                    from: ciImage,
                    in: cgImageRect,
                    radius: radius,
                    ciContext: ciContext
                ) {
                    context.draw(blurredRegion, in: cgImageRect)
                }

            case .pixelate:
                let scale = region.effectivePixelateScale(for: imageSize)
                if let pixelatedRegion = createPixelatedRegion(
                    from: ciImage,
                    in: cgImageRect,
                    scale: scale,
                    ciContext: ciContext
                ) {
                    context.draw(pixelatedRegion, in: cgImageRect)
                }

            case .solidBlack:
                context.setFillColor(CGColor(gray: 0, alpha: 1))
                context.fill(cgImageRect)

            case .solidWhite:
                context.setFillColor(CGColor(gray: 1, alpha: 1))
                context.fill(cgImageRect)
            }
        }

        guard let resultImage = context.makeImage() else { return image }
        return NSImage(cgImage: resultImage, size: imageSize)
    }

    /// Creates a blurred CGImage for a region with proper edge handling
    /// Uses clampedToExtent() to prevent gray/black edge artifacts
    private static func createBlurredRegion(
        from ciImage: CIImage,
        in rect: CGRect,
        radius: Double,
        ciContext: CIContext
    ) -> CGImage? {
        // CRITICAL: Clamp edges BEFORE cropping to prevent gray fringe artifacts
        // The blur filter samples beyond the crop bounds; clampedToExtent() extends
        // edge pixels infinitely to provide clean samples at the borders.
        let clamped = ciImage.clampedToExtent()

        // Expand the crop region by the blur radius to capture edge samples
        let expandedRect = rect.insetBy(dx: -radius * 3, dy: -radius * 3)
        let cropped = clamped.cropped(to: expandedRect)

        guard let blurFilter = CIFilter(name: "CIGaussianBlur") else { return nil }
        blurFilter.setValue(cropped, forKey: kCIInputImageKey)
        blurFilter.setValue(radius, forKey: kCIInputRadiusKey)

        guard let blurred = blurFilter.outputImage else { return nil }

        // Crop back to the original requested rect
        return ciContext.createCGImage(blurred, from: rect)
    }

    /// Creates a pixelated CGImage for a region
    private static func createPixelatedRegion(
        from ciImage: CIImage,
        in rect: CGRect,
        scale: Double,
        ciContext: CIContext
    ) -> CGImage? {
        // Clamp to prevent edge artifacts (pixelate also samples beyond bounds)
        let clamped = ciImage.clampedToExtent()
        let cropped = clamped.cropped(to: rect.insetBy(dx: -scale * 2, dy: -scale * 2))

        guard let pixelateFilter = CIFilter(name: "CIPixellate") else { return nil }
        pixelateFilter.setValue(cropped, forKey: kCIInputImageKey)
        pixelateFilter.setValue(scale, forKey: kCIInputScaleKey)

        let centerVector = CIVector(x: rect.midX, y: rect.midY)
        pixelateFilter.setValue(centerVector, forKey: kCIInputCenterKey)

        guard let pixelated = pixelateFilter.outputImage else { return nil }

        return ciContext.createCGImage(pixelated, from: rect)
    }


    // MARK: - Watermark Overlay
    //
    // Applies image or text watermark overlay at a configurable position,
    // size, and opacity. Uses CGContext for GPU-friendly compositing.

    /// Applies a watermark (image or text) to an NSImage
    /// - Parameters:
    ///   - image: The source image
    ///   - settings: Watermark configuration
    ///   - filename: Original filename (for {filename} variable in text mode)
    ///   - index: Image index in batch (for {index} variable)
    ///   - count: Total image count (for {count} variable)
    /// - Returns: A new image with the watermark applied
    static func applyWatermark(
        _ image: NSImage,
        settings: WatermarkSettings,
        filename: String = "",
        index: Int = 1,
        count: Int = 1
    ) -> NSImage {
        guard settings.isValid else { return image }

        switch settings.mode {
        case .image:
            return applyImageWatermark(image, settings: settings)
        case .text:
            return applyTextWatermark(image, settings: settings, filename: filename, index: index, count: count)
        }
    }

    /// Applies an image watermark overlay
    private static func applyImageWatermark(_ image: NSImage, settings: WatermarkSettings) -> NSImage {
        guard let watermarkImage = settings.loadedImage,
              let watermarkCGImage = watermarkImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let sourceCGImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            return image
        }

        let imageSize = CGSize(width: sourceCGImage.width, height: sourceCGImage.height)

        guard let watermarkRect = settings.watermarkRect(for: imageSize) else {
            return image
        }

        let colorSpace = sourceCGImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(imageSize.width),
            height: Int(imageSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        context.draw(sourceCGImage, in: CGRect(origin: .zero, size: imageSize))
        context.setAlpha(settings.opacity)
        context.draw(watermarkCGImage, in: watermarkRect)

        guard let resultImage = context.makeImage() else { return image }
        return NSImage(cgImage: resultImage, size: imageSize)
    }

    /// Applies a text watermark overlay
    private static func applyTextWatermark(
        _ image: NSImage,
        settings: WatermarkSettings,
        filename: String,
        index: Int,
        count: Int
    ) -> NSImage {
        guard let sourceCGImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return image
        }

        let imageSize = CGSize(width: sourceCGImage.width, height: sourceCGImage.height)

        // Substitute dynamic variables
        let resolvedText = TextWatermarkVariable.substitute(
            in: settings.text,
            filename: filename,
            index: index,
            count: count
        )

        // Calculate text rect
        let textRect = settings.textWatermarkRect(for: imageSize, text: resolvedText)

        // Create NSImage for drawing (NSGraphicsContext is easier for text)
        let resultImage = NSImage(size: imageSize)
        resultImage.lockFocus()

        // Draw source image
        let nsContext = NSGraphicsContext.current!
        let cgContext = nsContext.cgContext

        // Flip context for CGImage (CGImage has origin at bottom-left)
        cgContext.translateBy(x: 0, y: imageSize.height)
        cgContext.scaleBy(x: 1.0, y: -1.0)
        cgContext.draw(sourceCGImage, in: CGRect(origin: .zero, size: imageSize))

        // Reset transform for text drawing
        cgContext.scaleBy(x: 1.0, y: -1.0)
        cgContext.translateBy(x: 0, y: -imageSize.height)

        // Draw text with attributes
        let attributes = settings.textAttributes(scale: 1.0)
        let attrString = NSAttributedString(string: resolvedText, attributes: attributes)

        // Convert rect from CGImage coords (bottom-left origin) to NSView coords (top-left origin)
        let drawRect = CGRect(
            x: textRect.origin.x,
            y: imageSize.height - textRect.origin.y - textRect.height,
            width: textRect.width,
            height: textRect.height
        )

        attrString.draw(in: drawRect)

        resultImage.unlockFocus()
        return resultImage
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
    ///   - transform: Global transform to apply to all images
    ///   - blurRegions: Dictionary of blur regions keyed by image ID
    ///   - progress: Closure called with progress updates (0.0 to 1.0)
    /// - Returns: Array of URLs for successfully cropped images
    static func batchCrop(
        items: [ImageItem],
        cropSettings: CropSettings,
        exportSettings: ExportSettings,
        transform: ImageTransform = .identity,
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
        let itemCount = items.count
        return try await withThrowingTaskGroup(of: (Int, URL).self) { group in
            for (index, item) in items.enumerated() {
                group.addTask {
                    let outputURL = try processSingleImage(
                        item: item,
                        index: index,
                        count: itemCount,
                        cropSettings: cropSettings,
                        exportSettings: exportSettings,
                        transform: transform,
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
        count: Int,
        cropSettings: CropSettings,
        exportSettings: ExportSettings,
        transform: ImageTransform,
        blurRegions: [UUID: ImageBlurData]
    ) throws -> URL {
        var processedImage = item.originalImage

        // Pipeline order: Transform -> Blur -> Crop -> Resize -> Watermark

        // 1. Apply transform (rotation/flip) FIRST
        if !transform.isIdentity {
            processedImage = applyTransform(processedImage, transform: transform)
        }

        // 2. Apply blur regions - MUST transform coordinates to match transformed image
        if let imageBlurData = blurRegions[item.id], imageBlurData.hasRegions {
            // Blur regions are stored in ORIGINAL image coordinates
            // The image has been transformed, so we need to transform the blur coords too
            let transformedRegions = imageBlurData.regions.map { region in
                var transformed = region
                transformed.normalizedRect = region.normalizedRect.applyingTransform(transform)
                return transformed
            }
            processedImage = applyBlurRegions(processedImage, regions: transformedRegions)
        }

        // 3. Apply crop
        processedImage = try crop(processedImage, with: cropSettings)

        // 4. Apply resize if enabled
        if let targetSize = calculateResizedSize(from: processedImage.size, with: exportSettings.resizeSettings) {
            processedImage = resize(processedImage, to: targetSize)
        }

        // 5. Apply watermark if enabled
        if exportSettings.watermarkSettings.isValid {
            let filename = item.url.deletingPathExtension().lastPathComponent
            processedImage = applyWatermark(
                processedImage,
                settings: exportSettings.watermarkSettings,
                filename: filename,
                index: index + 1,  // 1-based for user display
                count: count
            )
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
