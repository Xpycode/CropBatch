import Foundation
import CoreGraphics

// MARK: - Normalized Coordinate System
//
// All blur regions are stored in NORMALIZED coordinates (0.0 to 1.0).
// This makes them resolution-independent and zoom-independent.
//
// Coordinate spaces:
// - Normalized: (0,0) = top-left, (1,1) = bottom-right, values 0.0-1.0
// - Pixel: (0,0) = top-left, actual pixel dimensions
// - CGImage: (0,0) = BOTTOM-left (flipped Y!)
// - View: Screen coordinates in the SwiftUI view
//
// RULE: All conversions go through this module. No ad-hoc flipping elsewhere!

/// A rectangle in normalized coordinates (0.0 to 1.0)
struct NormalizedRect: Equatable, Hashable, Codable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(_ cgRect: CGRect) {
        self.x = cgRect.origin.x
        self.y = cgRect.origin.y
        self.width = cgRect.width
        self.height = cgRect.height
    }

    var origin: NormalizedPoint {
        NormalizedPoint(x: x, y: y)
    }

    var size: NormalizedSize {
        NormalizedSize(width: width, height: height)
    }

    var minX: Double { x }
    var minY: Double { y }
    var maxX: Double { x + width }
    var maxY: Double { y + height }
    var midX: Double { x + width / 2 }
    var midY: Double { y + height / 2 }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    /// Clamp all values to valid 0.0-1.0 range
    func clamped() -> NormalizedRect {
        let clampedX = max(0, min(1, x))
        let clampedY = max(0, min(1, y))
        let clampedWidth = max(0, min(1 - clampedX, width))
        let clampedHeight = max(0, min(1 - clampedY, height))
        return NormalizedRect(x: clampedX, y: clampedY, width: clampedWidth, height: clampedHeight)
    }

    /// Check if this rect intersects another
    func intersects(_ other: NormalizedRect) -> Bool {
        cgRect.intersects(other.cgRect)
    }

    /// Get intersection with another rect
    func intersection(_ other: NormalizedRect) -> NormalizedRect? {
        let result = cgRect.intersection(other.cgRect)
        guard !result.isNull && result.width > 0 && result.height > 0 else { return nil }
        return NormalizedRect(result)
    }

    /// Check if this rect fully contains another
    func contains(_ other: NormalizedRect) -> Bool {
        cgRect.contains(other.cgRect)
    }

    /// Check if this rect contains a point
    func contains(_ point: NormalizedPoint) -> Bool {
        cgRect.contains(point.cgPoint)
    }

    /// Offset the rect
    func offsetBy(dx: Double, dy: Double) -> NormalizedRect {
        NormalizedRect(x: x + dx, y: y + dy, width: width, height: height)
    }

    /// Create from pixel coordinates
    static func fromPixels(_ pixelRect: CGRect, imageSize: CGSize) -> NormalizedRect {
        guard imageSize.width > 0 && imageSize.height > 0 else {
            return NormalizedRect(x: 0, y: 0, width: 0, height: 0)
        }
        return NormalizedRect(
            x: pixelRect.origin.x / imageSize.width,
            y: pixelRect.origin.y / imageSize.height,
            width: pixelRect.width / imageSize.width,
            height: pixelRect.height / imageSize.height
        )
    }

    /// Convert to pixel coordinates
    func toPixels(imageSize: CGSize) -> CGRect {
        CGRect(
            x: x * imageSize.width,
            y: y * imageSize.height,
            width: width * imageSize.width,
            height: height * imageSize.height
        )
    }

    /// Convert to CGImage coordinates (flipped Y - bottom-left origin)
    func toCGImageRect(imageSize: CGSize) -> CGRect {
        let pixelRect = toPixels(imageSize: imageSize)
        // CGImage has origin at BOTTOM-LEFT, so we flip Y
        return CGRect(
            x: pixelRect.origin.x,
            y: imageSize.height - pixelRect.origin.y - pixelRect.height,
            width: pixelRect.width,
            height: pixelRect.height
        )
    }

    /// Create from CGImage coordinates (flipped Y)
    static func fromCGImageRect(_ cgImageRect: CGRect, imageSize: CGSize) -> NormalizedRect {
        guard imageSize.width > 0 && imageSize.height > 0 else {
            return NormalizedRect(x: 0, y: 0, width: 0, height: 0)
        }
        // Flip Y back from bottom-left to top-left origin
        let topLeftY = imageSize.height - cgImageRect.origin.y - cgImageRect.height
        let pixelRect = CGRect(
            x: cgImageRect.origin.x,
            y: topLeftY,
            width: cgImageRect.width,
            height: cgImageRect.height
        )
        return fromPixels(pixelRect, imageSize: imageSize)
    }
}

/// A point in normalized coordinates
struct NormalizedPoint: Equatable, Hashable, Codable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }

    func clamped() -> NormalizedPoint {
        NormalizedPoint(x: max(0, min(1, x)), y: max(0, min(1, y)))
    }

    static func fromPixels(_ point: CGPoint, imageSize: CGSize) -> NormalizedPoint {
        guard imageSize.width > 0 && imageSize.height > 0 else {
            return NormalizedPoint(x: 0, y: 0)
        }
        return NormalizedPoint(x: point.x / imageSize.width, y: point.y / imageSize.height)
    }

    func toPixels(imageSize: CGSize) -> CGPoint {
        CGPoint(x: x * imageSize.width, y: y * imageSize.height)
    }
}

/// A size in normalized coordinates
struct NormalizedSize: Equatable, Hashable, Codable {
    var width: Double
    var height: Double

    var cgSize: CGSize {
        CGSize(width: width, height: height)
    }
}

// MARK: - Coordinate Converter

/// Converts between all coordinate spaces for a specific image context
struct CoordinateConverter {
    /// The normalized (EXIF-baked) image size in pixels
    let imageSize: CGSize

    /// The displayed size on screen
    let displayedSize: CGSize

    /// Offset from view origin to displayed image origin
    let displayOffset: CGPoint

    /// Scale factor: displayedSize / imageSize
    var scale: CGFloat {
        guard imageSize.width > 0 else { return 1 }
        return displayedSize.width / imageSize.width
    }

    init(imageSize: CGSize, displayedSize: CGSize, displayOffset: CGPoint = .zero) {
        self.imageSize = imageSize
        self.displayedSize = displayedSize
        self.displayOffset = displayOffset
    }

    // MARK: - View ↔ Normalized

    /// Convert view point to normalized coordinates
    func viewToNormalized(_ viewPoint: CGPoint) -> NormalizedPoint {
        let imagePoint = CGPoint(
            x: (viewPoint.x - displayOffset.x) / scale,
            y: (viewPoint.y - displayOffset.y) / scale
        )
        return NormalizedPoint.fromPixels(imagePoint, imageSize: imageSize)
    }

    /// Convert normalized point to view coordinates
    func normalizedToView(_ normalized: NormalizedPoint) -> CGPoint {
        let pixelPoint = normalized.toPixels(imageSize: imageSize)
        return CGPoint(
            x: displayOffset.x + pixelPoint.x * scale,
            y: displayOffset.y + pixelPoint.y * scale
        )
    }

    /// Convert view rect to normalized rect
    func viewToNormalized(_ viewRect: CGRect) -> NormalizedRect {
        let origin = viewToNormalized(viewRect.origin)
        let oppositeCorner = viewToNormalized(CGPoint(x: viewRect.maxX, y: viewRect.maxY))
        return NormalizedRect(
            x: origin.x,
            y: origin.y,
            width: oppositeCorner.x - origin.x,
            height: oppositeCorner.y - origin.y
        ).clamped()
    }

    /// Convert normalized rect to view rect
    func normalizedToView(_ normalized: NormalizedRect) -> CGRect {
        let origin = normalizedToView(normalized.origin)
        let pixelSize = CGSize(
            width: normalized.width * imageSize.width,
            height: normalized.height * imageSize.height
        )
        return CGRect(
            x: origin.x,
            y: origin.y,
            width: pixelSize.width * scale,
            height: pixelSize.height * scale
        )
    }

    // MARK: - Pixel ↔ Normalized (convenience)

    func pixelToNormalized(_ pixelRect: CGRect) -> NormalizedRect {
        NormalizedRect.fromPixels(pixelRect, imageSize: imageSize)
    }

    func normalizedToPixel(_ normalized: NormalizedRect) -> CGRect {
        normalized.toPixels(imageSize: imageSize)
    }

    // MARK: - CGImage ↔ Normalized (handles Y-flip)

    func cgImageToNormalized(_ cgImageRect: CGRect) -> NormalizedRect {
        NormalizedRect.fromCGImageRect(cgImageRect, imageSize: imageSize)
    }

    func normalizedToCGImage(_ normalized: NormalizedRect) -> CGRect {
        normalized.toCGImageRect(imageSize: imageSize)
    }
}

// MARK: - Transform Support

extension NormalizedPoint {
    /// Apply a transform to convert from ORIGINAL image coords to TRANSFORMED view coords
    /// Use this when displaying a blur region that was stored in original coords
    func applyingTransform(_ transform: ImageTransform) -> NormalizedPoint {
        var result = self

        // Apply rotation first (transforms are applied: rotation then flip)
        switch transform.rotation {
        case .none:
            break
        case .cw90:
            // 90° CW: (x, y) → (1-y, x)
            result = NormalizedPoint(x: 1 - result.y, y: result.x)
        case .cw180:
            // 180°: (x, y) → (1-x, 1-y)
            result = NormalizedPoint(x: 1 - result.x, y: 1 - result.y)
        case .cw270:
            // 270° CW (90° CCW): (x, y) → (y, 1-x)
            result = NormalizedPoint(x: result.y, y: 1 - result.x)
        }

        // Apply flips
        if transform.flipHorizontal {
            result = NormalizedPoint(x: 1 - result.x, y: result.y)
        }
        if transform.flipVertical {
            result = NormalizedPoint(x: result.x, y: 1 - result.y)
        }

        return result
    }

    /// Apply inverse transform to convert from TRANSFORMED view coords to ORIGINAL image coords
    /// Use this when storing a blur region drawn on a transformed view
    func applyingInverseTransform(_ transform: ImageTransform) -> NormalizedPoint {
        var result = self

        // Inverse: undo flips first (reverse order of forward transform)
        if transform.flipVertical {
            result = NormalizedPoint(x: result.x, y: 1 - result.y)
        }
        if transform.flipHorizontal {
            result = NormalizedPoint(x: 1 - result.x, y: result.y)
        }

        // Inverse rotation
        switch transform.rotation {
        case .none:
            break
        case .cw90:
            // Inverse of 90° CW is 270° CW: (x, y) → (y, 1-x)
            result = NormalizedPoint(x: result.y, y: 1 - result.x)
        case .cw180:
            // Inverse of 180° is 180°: (x, y) → (1-x, 1-y)
            result = NormalizedPoint(x: 1 - result.x, y: 1 - result.y)
        case .cw270:
            // Inverse of 270° CW is 90° CW: (x, y) → (1-y, x)
            result = NormalizedPoint(x: 1 - result.y, y: result.x)
        }

        return result
    }
}

extension NormalizedRect {
    /// Apply a transform to convert from ORIGINAL image coords to TRANSFORMED view coords
    func applyingTransform(_ transform: ImageTransform) -> NormalizedRect {
        // Transform the two corner points
        let topLeft = origin.applyingTransform(transform)
        let bottomRight = NormalizedPoint(x: maxX, y: maxY).applyingTransform(transform)

        // Reconstruct rect (handle negative dimensions after rotation)
        let minX = min(topLeft.x, bottomRight.x)
        let minY = min(topLeft.y, bottomRight.y)
        let maxX = max(topLeft.x, bottomRight.x)
        let maxY = max(topLeft.y, bottomRight.y)

        return NormalizedRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Apply inverse transform to convert from TRANSFORMED view coords to ORIGINAL image coords
    func applyingInverseTransform(_ transform: ImageTransform) -> NormalizedRect {
        // Transform the two corner points
        let topLeft = origin.applyingInverseTransform(transform)
        let bottomRight = NormalizedPoint(x: maxX, y: maxY).applyingInverseTransform(transform)

        // Reconstruct rect (handle negative dimensions after rotation)
        let minX = min(topLeft.x, bottomRight.x)
        let minY = min(topLeft.y, bottomRight.y)
        let maxX = max(topLeft.x, bottomRight.x)
        let maxY = max(topLeft.y, bottomRight.y)

        return NormalizedRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

// MARK: - Crop Settings Integration

extension NormalizedRect {
    /// Create a normalized rect representing the crop area
    static func cropArea(from settings: CropSettings, imageSize: CGSize) -> NormalizedRect {
        let pixelRect = CGRect(
            x: CGFloat(settings.cropLeft),
            y: CGFloat(settings.cropTop),
            width: imageSize.width - CGFloat(settings.cropLeft + settings.cropRight),
            height: imageSize.height - CGFloat(settings.cropTop + settings.cropBottom)
        )
        return fromPixels(pixelRect, imageSize: imageSize)
    }

    /// Transform this rect to be relative to a crop area
    /// (i.e., convert from pre-crop to post-crop coordinates)
    func relativeToCrop(_ cropArea: NormalizedRect) -> NormalizedRect? {
        guard let clipped = intersection(cropArea) else { return nil }
        guard cropArea.width > 0 && cropArea.height > 0 else { return nil }

        return NormalizedRect(
            x: (clipped.x - cropArea.x) / cropArea.width,
            y: (clipped.y - cropArea.y) / cropArea.height,
            width: clipped.width / cropArea.width,
            height: clipped.height / cropArea.height
        )
    }
}
