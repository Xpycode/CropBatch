import SwiftUI

/// Manages snap point detection and caching for rectangle snapping
@Observable
final class SnapPointsManager {
    // MARK: - Snap Points Cache

    /// Cached snap points keyed by image ID
    private(set) var cache: [UUID: SnapPoints] = [:]

    /// Whether snap point detection is in progress
    var isDetecting = false

    // MARK: - Settings

    /// Master toggle for snap functionality
    var enabled = true

    /// Pixels threshold for snapping (5-30)
    var threshold: Int = Config.Snap.defaultThreshold

    /// Also snap to image center lines
    var snapToCenter = true

    /// Show all detected edges overlay (debug)
    var showDebug = false

    // MARK: - Snap Point Access

    /// Get snap points for an image (includes center lines if enabled)
    func snapPoints(for imageID: UUID, imageSize: CGSize?) -> SnapPoints {
        var points = cache[imageID] ?? .empty

        // Add center lines if enabled
        if snapToCenter, let size = imageSize {
            let centerX = Int(size.width) / 2
            let centerY = Int(size.height) / 2
            points = points.merged(with: SnapPoints(
                horizontalEdges: [centerY],
                verticalEdges: [centerX]
            ), tolerance: 5)
        }

        return points
    }

    /// Detect snap points for an image
    @MainActor
    func detect(for image: ImageItem) async {
        // Skip if already cached
        if cache[image.id] != nil { return }

        isDetecting = true

        let snapPoints = await RectangleDetector.detect(in: image.originalImage)
        cache[image.id] = snapPoints

        isDetecting = false
    }

    /// Find the nearest snap point for a given edge value
    func snapValue(_ value: Int, for edge: CropEdge, imageID: UUID, imageSize: CGSize?) -> Int? {
        guard enabled else { return nil }
        let snapPoints = self.snapPoints(for: imageID, imageSize: imageSize)

        switch edge {
        case .top, .bottom:
            return snapPoints.nearestHorizontalEdge(to: value, threshold: threshold)
        case .left, .right:
            return snapPoints.nearestVerticalEdge(to: value, threshold: threshold)
        }
    }

    // MARK: - Cache Management

    /// Clear snap points cache for specific images
    func clearCache(for imageIDs: Set<UUID>) {
        for id in imageIDs {
            cache.removeValue(forKey: id)
        }
    }

    /// Clear all cached snap points
    func clearAll() {
        cache.removeAll()
    }
}
