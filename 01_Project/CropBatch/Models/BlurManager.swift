import SwiftUI

/// Per-image blur override when global regions don't apply
enum ImageBlurOverride: Equatable {
    case optedOut
    case custom([BlurRegion])
}

/// Manages blur regions and image transforms
@MainActor
@Observable
final class BlurManager {
    // MARK: - Global Blur Regions

    /// Blur regions shared across all images by default
    var globalRegions: [BlurRegion] = []

    /// Per-image overrides: opted out or custom regions
    var imageOverrides: [UUID: ImageBlurOverride] = [:]

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

    /// Get blur regions for a specific image (respects overrides)
    func regionsForImage(_ imageID: UUID) -> [BlurRegion] {
        switch imageOverrides[imageID] {
        case .optedOut:
            return []
        case .custom(let regions):
            return regions
        case nil:
            return globalRegions
        }
    }

    /// Import per-image regions as overrides (migration/undo path)
    func setRegions(_ newValue: [UUID: ImageBlurData]) {
        for (imageID, data) in newValue {
            if data.regions.isEmpty {
                imageOverrides.removeValue(forKey: imageID)
            } else {
                imageOverrides[imageID] = .custom(data.regions)
            }
        }
    }

    /// Build blur regions dict for a set of images (for export)
    func blurRegionsForExport(imageIDs: [UUID]) -> [UUID: ImageBlurData] {
        var result: [UUID: ImageBlurData] = [:]
        for id in imageIDs {
            let regions = regionsForImage(id)
            if !regions.isEmpty {
                result[id] = ImageBlurData(regions: regions)
            }
        }
        return result
    }

    /// Add a blur region (global by default, or to custom override)
    func addRegion(_ region: BlurRegion, to imageID: UUID) {
        switch imageOverrides[imageID] {
        case .custom(var regions):
            regions.append(region)
            imageOverrides[imageID] = .custom(regions)
        case .optedOut:
            // Can't add to opted-out image
            break
        case nil:
            // Add to global regions
            globalRegions.append(region)
        }
    }

    /// Remove a blur region
    func removeRegion(_ regionID: UUID, from imageID: UUID) {
        switch imageOverrides[imageID] {
        case .custom(var regions):
            regions.removeAll { $0.id == regionID }
            imageOverrides[imageID] = .custom(regions)
        case .optedOut:
            break
        case nil:
            globalRegions.removeAll { $0.id == regionID }
        }
        if selectedRegionID == regionID {
            selectedRegionID = nil
        }
    }

    /// Clear all blur regions for an image
    func clearRegions(for imageID: UUID) {
        switch imageOverrides[imageID] {
        case .custom:
            imageOverrides[imageID] = .custom([])
        case .optedOut:
            break
        case nil:
            globalRegions.removeAll()
        }
        selectedRegionID = nil
    }

    /// Clear blur regions for multiple images
    func clearRegions(for imageIDs: Set<UUID>) {
        for id in imageIDs {
            imageOverrides.removeValue(forKey: id)
        }
    }

    /// Check if any regions exist (global or custom)
    var hasAnyRegions: Bool {
        if !globalRegions.isEmpty { return true }
        return imageOverrides.values.contains { override in
            if case .custom(let regions) = override, !regions.isEmpty {
                return true
            }
            return false
        }
    }

    /// Get the currently selected blur region
    func selectedRegion(for imageID: UUID) -> BlurRegion? {
        guard let regionID = selectedRegionID else { return nil }
        return regionsForImage(imageID).first { $0.id == regionID }
    }

    /// Select a blur region for editing
    func selectRegion(_ regionID: UUID?) {
        selectedRegionID = regionID
    }

    /// Update a blur region's properties
    func updateRegion(_ regionID: UUID, in imageID: UUID, normalizedRect: NormalizedRect? = nil, style: BlurRegion.BlurStyle? = nil, intensity: Double? = nil) {
        switch imageOverrides[imageID] {
        case .custom(var regions):
            guard let index = regions.firstIndex(where: { $0.id == regionID }) else { return }
            if let normalizedRect { regions[index].normalizedRect = normalizedRect.clamped() }
            if let style { regions[index].style = style }
            if let intensity { regions[index].intensity = intensity }
            imageOverrides[imageID] = .custom(regions)
        case .optedOut:
            break
        case nil:
            guard let index = globalRegions.firstIndex(where: { $0.id == regionID }) else { return }
            if let normalizedRect { globalRegions[index].normalizedRect = normalizedRect.clamped() }
            if let style { globalRegions[index].style = style }
            if let intensity { globalRegions[index].intensity = intensity }
        }
    }

    // MARK: - Per-Image Override Management

    /// Toggle opt-out for an image
    func toggleOptOut(_ imageID: UUID) {
        if case .optedOut = imageOverrides[imageID] {
            imageOverrides.removeValue(forKey: imageID)
        } else {
            imageOverrides[imageID] = .optedOut
            if let selectedRegionID, regionsForImage(imageID).first(where: { $0.id == selectedRegionID }) == nil {
                self.selectedRegionID = nil
            }
        }
    }

    /// Create a per-image custom copy of global regions
    func customizeImage(_ imageID: UUID) {
        guard imageOverrides[imageID] == nil else { return }
        imageOverrides[imageID] = .custom(globalRegions.map { region in
            BlurRegion(normalizedRect: region.normalizedRect, style: region.style, intensity: region.intensity)
        })
    }

    /// Check if image is opted out
    func isOptedOut(_ imageID: UUID) -> Bool {
        if case .optedOut = imageOverrides[imageID] { return true }
        return false
    }

    /// Check if image has custom regions
    func hasCustomRegions(_ imageID: UUID) -> Bool {
        if case .custom = imageOverrides[imageID] { return true }
        return false
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

    var hasAnyTransforms: Bool {
        !transform.isIdentity
    }

    func rotate(clockwise: Bool) {
        if clockwise {
            transform.rotation.rotateCW()
        } else {
            transform.rotation.rotateCCW()
        }
    }

    func flip(horizontal: Bool) {
        if horizontal {
            transform.flipHorizontal.toggle()
        } else {
            transform.flipVertical.toggle()
        }
    }

    func resetTransform() {
        transform = .identity
    }

    func effectiveSize(for originalSize: CGSize) -> CGSize {
        transform.transformedSize(originalSize)
    }

    // MARK: - Cleanup

    func clearAll() {
        globalRegions.removeAll()
        imageOverrides.removeAll()
        selectedRegionID = nil
        transform = .identity
    }
}
