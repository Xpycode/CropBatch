import Foundation

/// A rectangular region to be blurred/redacted in an image
struct BlurRegion: Identifiable, Equatable {
    let id: UUID
    var rect: CGRect  // In image coordinates (pixels)
    var style: BlurStyle = .blur
    var intensity: Double = 1.0  // 0.0 to 1.0, affects blur radius/pixelate scale

    init(id: UUID = UUID(), rect: CGRect, style: BlurStyle = .blur, intensity: Double = 1.0) {
        self.id = id
        self.rect = rect
        self.style = style
        self.intensity = intensity
    }

    enum BlurStyle: String, CaseIterable, Identifiable {
        case blur = "Blur"
        case pixelate = "Pixelate"
        case solidBlack = "Black"
        case solidWhite = "White"

        var id: String { rawValue }
    }

    /// Calculate the effective blur radius based on intensity (5-40 range)
    var effectiveBlurRadius: Double {
        5.0 + (intensity * 35.0)
    }

    /// Calculate the effective pixelate scale based on intensity and region size
    func effectivePixelateScale(for rect: CGRect) -> Double {
        let baseScale = max(rect.width, rect.height) / 20.0
        return baseScale * (0.3 + intensity * 0.7)  // 30% to 100% of base
    }

    /// Returns the portion of this region that intersects with the crop area
    func clipped(to cropRect: CGRect) -> BlurRegion? {
        let intersection = rect.intersection(cropRect)
        guard !intersection.isNull && intersection.width > 0 && intersection.height > 0 else {
            return nil
        }
        return BlurRegion(id: id, rect: intersection, style: style, intensity: intensity)
    }

    /// Returns a new region with coordinates transformed for a cropped image
    func transformed(byCrop cropSettings: CropSettings) -> BlurRegion {
        let newRect = CGRect(
            x: rect.origin.x - CGFloat(cropSettings.cropLeft),
            y: rect.origin.y - CGFloat(cropSettings.cropTop),
            width: rect.width,
            height: rect.height
        )
        return BlurRegion(id: id, rect: newRect, style: style, intensity: intensity)
    }

    /// Check if region is completely outside the crop area
    func isOutsideCrop(_ cropSettings: CropSettings, imageSize: CGSize) -> Bool {
        let cropRect = CGRect(
            x: CGFloat(cropSettings.cropLeft),
            y: CGFloat(cropSettings.cropTop),
            width: imageSize.width - CGFloat(cropSettings.cropLeft + cropSettings.cropRight),
            height: imageSize.height - CGFloat(cropSettings.cropTop + cropSettings.cropBottom)
        )
        return !rect.intersects(cropRect)
    }

    /// Check if region is partially outside the crop area
    func isPartiallyCropped(_ cropSettings: CropSettings, imageSize: CGSize) -> Bool {
        let cropRect = CGRect(
            x: CGFloat(cropSettings.cropLeft),
            y: CGFloat(cropSettings.cropTop),
            width: imageSize.width - CGFloat(cropSettings.cropLeft + cropSettings.cropRight),
            height: imageSize.height - CGFloat(cropSettings.cropTop + cropSettings.cropBottom)
        )
        return rect.intersects(cropRect) && !cropRect.contains(rect)
    }
}

/// Per-image blur regions storage
struct ImageBlurData: Equatable {
    var regions: [BlurRegion] = []

    var hasRegions: Bool {
        !regions.isEmpty
    }

    /// Get regions that will appear in the final cropped image
    func regionsForCrop(_ cropSettings: CropSettings, imageSize: CGSize) -> [BlurRegion] {
        let cropRect = CGRect(
            x: CGFloat(cropSettings.cropLeft),
            y: CGFloat(cropSettings.cropTop),
            width: imageSize.width - CGFloat(cropSettings.cropLeft + cropSettings.cropRight),
            height: imageSize.height - CGFloat(cropSettings.cropTop + cropSettings.cropBottom)
        )

        return regions.compactMap { region in
            // Clip to crop area, then transform coordinates
            guard let clipped = region.clipped(to: cropRect) else { return nil }
            return clipped.transformed(byCrop: cropSettings)
        }
    }
}
