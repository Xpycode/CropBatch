import Foundation

/// A rectangular region to be blurred/redacted in an image
/// Coordinates are stored in NORMALIZED space (0.0 to 1.0) for resolution independence
struct BlurRegion: Identifiable, Equatable, Hashable {
    let id: UUID
    var normalizedRect: NormalizedRect  // Normalized coordinates (0.0 to 1.0)
    var style: BlurStyle = .blur
    var intensity: Double = 1.0  // 0.0 to 1.0, affects blur radius/pixelate scale

    init(id: UUID = UUID(), normalizedRect: NormalizedRect, style: BlurStyle = .blur, intensity: Double = 1.0) {
        self.id = id
        self.normalizedRect = normalizedRect.clamped()
        self.style = style
        self.intensity = max(0, min(1, intensity))
    }

    /// Convenience initializer from pixel coordinates
    init(id: UUID = UUID(), pixelRect: CGRect, imageSize: CGSize, style: BlurStyle = .blur, intensity: Double = 1.0) {
        self.id = id
        self.normalizedRect = NormalizedRect.fromPixels(pixelRect, imageSize: imageSize).clamped()
        self.style = style
        self.intensity = max(0, min(1, intensity))
    }

    enum BlurStyle: String, CaseIterable, Identifiable, Hashable {
        case blur = "Blur"
        case pixelate = "Pixelate"
        case solidBlack = "Black"
        case solidWhite = "White"

        var id: String { rawValue }

        var requiresImageProcessing: Bool {
            self == .blur || self == .pixelate
        }
    }

    // MARK: - Pixel Coordinate Accessors

    /// Get the rect in pixel coordinates for a given image size
    func pixelRect(for imageSize: CGSize) -> CGRect {
        normalizedRect.toPixels(imageSize: imageSize)
    }

    /// Get the rect in CGImage coordinates (bottom-left origin) for a given image size
    func cgImageRect(for imageSize: CGSize) -> CGRect {
        normalizedRect.toCGImageRect(imageSize: imageSize)
    }

    // MARK: - Blur Parameters

    /// Calculate the effective blur radius based on intensity (0-40 range)
    var effectiveBlurRadius: Double {
        intensity * 40.0
    }

    /// Calculate the effective pixelate scale based on intensity and region size
    func effectivePixelateScale(for imageSize: CGSize) -> Double {
        let pixelRect = self.pixelRect(for: imageSize)
        let baseScale = max(pixelRect.width, pixelRect.height) / 20.0
        return baseScale * (0.3 + intensity * 0.7)  // 30% to 100% of base
    }

    // MARK: - Crop Interaction

    /// Returns the portion of this region that intersects with a crop area
    func clipped(to cropArea: NormalizedRect) -> BlurRegion? {
        guard let clipped = normalizedRect.intersection(cropArea) else { return nil }
        return BlurRegion(id: id, normalizedRect: clipped, style: style, intensity: intensity)
    }

    /// Returns a new region with coordinates transformed for a cropped image
    /// (converts from pre-crop to post-crop normalized coordinates)
    func transformed(to cropArea: NormalizedRect) -> BlurRegion? {
        guard let relativeToCrop = normalizedRect.relativeToCrop(cropArea) else { return nil }
        return BlurRegion(id: id, normalizedRect: relativeToCrop, style: style, intensity: intensity)
    }

    /// Check if region is completely outside the crop area
    func isOutsideCrop(_ cropArea: NormalizedRect) -> Bool {
        !normalizedRect.intersects(cropArea)
    }

    /// Check if region is partially outside the crop area (but still intersects)
    func isPartiallyCropped(_ cropArea: NormalizedRect) -> Bool {
        normalizedRect.intersects(cropArea) && !cropArea.contains(normalizedRect)
    }

    // MARK: - Convenience for CropSettings

    func isOutsideCrop(_ settings: CropSettings, imageSize: CGSize) -> Bool {
        let cropArea = NormalizedRect.cropArea(from: settings, imageSize: imageSize)
        return isOutsideCrop(cropArea)
    }

    func isPartiallyCropped(_ settings: CropSettings, imageSize: CGSize) -> Bool {
        let cropArea = NormalizedRect.cropArea(from: settings, imageSize: imageSize)
        return isPartiallyCropped(cropArea)
    }
}

// MARK: - Per-Image Blur Data

/// Per-image blur regions storage
struct ImageBlurData: Equatable {
    var regions: [BlurRegion] = []

    var hasRegions: Bool {
        !regions.isEmpty
    }

    /// Get regions that will appear in the final cropped image, with coordinates
    /// transformed to the cropped image's coordinate system
    func regionsForExport(_ settings: CropSettings, imageSize: CGSize) -> [BlurRegion] {
        let cropArea = NormalizedRect.cropArea(from: settings, imageSize: imageSize)

        return regions.compactMap { region in
            region.transformed(to: cropArea)
        }
    }

    /// Create a hash of all region data for cache invalidation
    var contentHash: Int {
        var hasher = Hasher()
        for region in regions {
            hasher.combine(region.normalizedRect)
            hasher.combine(region.style)
            hasher.combine(region.intensity)
        }
        return hasher.finalize()
    }
}
