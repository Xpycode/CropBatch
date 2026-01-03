import SwiftUI

/// Manages blur regions and image transforms
@Observable
final class BlurManager {
    // MARK: - Blur Regions

    /// Blur regions keyed by image ID
    var regions: [UUID: ImageBlurData] = [:]

    /// Currently selected region for editing
    var selectedRegionID: UUID?

    /// Current blur style for new regions
    var style: BlurRegion.BlurStyle = .blur

    /// Current blur intensity for new regions (0.0 to 1.0)
    var intensity: Double = 1.0

    // MARK: - Image Transforms

    /// Global image transform (rotation/flip) - applies to all images
    var transform: ImageTransform = .identity

    // MARK: - Blur Region Management

    /// Get blur regions for a specific image
    func regionsForImage(_ imageID: UUID) -> [BlurRegion] {
        regions[imageID]?.regions ?? []
    }

    /// Add a blur region to an image
    func addRegion(_ region: BlurRegion, to imageID: UUID) {
        if regions[imageID] == nil {
            regions[imageID] = ImageBlurData()
        }
        regions[imageID]?.regions.append(region)
    }

    /// Remove a blur region from an image
    func removeRegion(_ regionID: UUID, from imageID: UUID) {
        regions[imageID]?.regions.removeAll { $0.id == regionID }
        if selectedRegionID == regionID {
            selectedRegionID = nil
        }
    }

    /// Clear all blur regions for an image
    func clearRegions(for imageID: UUID) {
        regions[imageID] = ImageBlurData()
        selectedRegionID = nil
    }

    /// Clear blur regions for multiple images
    func clearRegions(for imageIDs: Set<UUID>) {
        for id in imageIDs {
            regions.removeValue(forKey: id)
        }
    }

    /// Check if any image has blur regions
    var hasAnyRegions: Bool {
        regions.values.contains { $0.hasRegions }
    }

    /// Get the currently selected blur region
    func selectedRegion(for imageID: UUID) -> BlurRegion? {
        guard let regionID = selectedRegionID,
              let data = regions[imageID] else { return nil }
        return data.regions.first { $0.id == regionID }
    }

    /// Select a blur region for editing
    func selectRegion(_ regionID: UUID?) {
        selectedRegionID = regionID
    }

    /// Update a blur region's properties
    func updateRegion(_ regionID: UUID, in imageID: UUID, normalizedRect: NormalizedRect? = nil, style: BlurRegion.BlurStyle? = nil, intensity: Double? = nil) {
        guard var data = regions[imageID],
              let index = data.regions.firstIndex(where: { $0.id == regionID }) else { return }

        if let normalizedRect = normalizedRect {
            data.regions[index].normalizedRect = normalizedRect.clamped()
        }
        if let style = style {
            data.regions[index].style = style
        }
        if let intensity = intensity {
            data.regions[index].intensity = intensity
        }
        regions[imageID] = data
    }

    /// Count of blur regions outside the crop area
    func regionsOutsideCropCount(for imageID: UUID, cropSettings: CropSettings, imageSize: CGSize) -> Int {
        regionsForImage(imageID).filter { $0.isOutsideCrop(cropSettings, imageSize: imageSize) }.count
    }

    /// Count of blur regions partially cropped
    func regionsPartiallyCroppedCount(for imageID: UUID, cropSettings: CropSettings, imageSize: CGSize) -> Int {
        regionsForImage(imageID).filter { $0.isPartiallyCropped(cropSettings, imageSize: imageSize) }.count
    }

    // MARK: - Transform Management

    /// Check if any transform is applied
    var hasAnyTransforms: Bool {
        !transform.isIdentity
    }

    /// Rotate images
    func rotate(clockwise: Bool) {
        if clockwise {
            transform.rotation.rotateCW()
        } else {
            transform.rotation.rotateCCW()
        }
    }

    /// Flip images
    func flip(horizontal: Bool) {
        if horizontal {
            transform.flipHorizontal.toggle()
        } else {
            transform.flipVertical.toggle()
        }
    }

    /// Reset transform
    func resetTransform() {
        transform = .identity
    }

    /// Get the effective size after transform (rotation may swap dimensions)
    func effectiveSize(for originalSize: CGSize) -> CGSize {
        transform.transformedSize(originalSize)
    }

    // MARK: - Cleanup

    /// Clear all state
    func clearAll() {
        regions.removeAll()
        selectedRegionID = nil
        transform = .identity
    }
}
