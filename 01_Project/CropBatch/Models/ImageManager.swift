import SwiftUI

/// Manages the collection of loaded images and selection state
@Observable
final class ImageManager {
    // MARK: - Image Collection

    var images: [ImageItem] = []
    var selectedImageIDs: Set<UUID> = []
    var activeImageID: UUID?

    // MARK: - Navigation Settings

    var loopNavigation = false  // Wrap around when navigating images

    // MARK: - Computed Properties

    var selectedImages: [ImageItem] {
        images.filter { selectedImageIDs.contains($0.id) }
    }

    /// The image currently being edited in the crop editor
    var activeImage: ImageItem? {
        if let activeID = activeImageID {
            return images.first { $0.id == activeID }
        }
        return images.first
    }

    /// The most common resolution among loaded images
    var majorityResolution: CGSize? {
        guard !images.isEmpty else { return nil }

        var resolutionCounts: [String: (size: CGSize, count: Int)] = [:]
        for image in images {
            let key = "\(Int(image.originalSize.width))x\(Int(image.originalSize.height))"
            if let existing = resolutionCounts[key] {
                resolutionCounts[key] = (existing.size, existing.count + 1)
            } else {
                resolutionCounts[key] = (image.originalSize, 1)
            }
        }

        return resolutionCounts.values.max(by: { $0.count < $1.count })?.size
    }

    /// Images that don't match the majority resolution
    var mismatchedImages: [ImageItem] {
        guard let majority = majorityResolution else { return [] }
        return images.filter { image in
            Int(image.originalSize.width) != Int(majority.width) ||
            Int(image.originalSize.height) != Int(majority.height)
        }
    }

    /// Whether there are resolution mismatches to warn about
    var hasResolutionMismatch: Bool {
        !mismatchedImages.isEmpty
    }

    // MARK: - Memory Warnings

    /// Warning level for memory usage based on image count
    enum MemoryWarningLevel {
        case none
        case warning   // Approaching limit
        case critical  // At or above critical threshold
    }

    /// Current memory warning level based on loaded image count
    var memoryWarningLevel: MemoryWarningLevel {
        if images.count >= Config.Memory.imageCountCriticalThreshold {
            return .critical
        } else if images.count >= Config.Memory.imageCountWarningThreshold {
            return .warning
        }
        return .none
    }

    /// Whether a memory warning should be displayed
    var shouldShowMemoryWarning: Bool {
        memoryWarningLevel != .none
    }

    /// Human-readable memory warning message
    var memoryWarningMessage: String? {
        switch memoryWarningLevel {
        case .none:
            return nil
        case .warning:
            return "You have \(images.count) images loaded. Consider exporting in batches to reduce memory usage."
        case .critical:
            return "⚠️ \(images.count) images loaded. This may cause performance issues or crashes. Export some images and remove them."
        }
    }

    // MARK: - Image Management

    /// Result of adding images, including any auto-detected format
    struct AddImagesResult {
        let addedCount: Int
        let detectedFormat: ExportFormat?
    }

    /// Adds images from URLs and returns the result including any auto-detected format
    /// - Parameter urls: URLs to load images from
    /// - Returns: Result containing added count and detected format (if first import)
    @discardableResult
    func addImages(from urls: [URL]) -> AddImagesResult {
        let wasEmpty = images.isEmpty

        let newImages = urls.compactMap { url -> ImageItem? in
            guard let image = NSImage(contentsOf: url) else { return nil }
            return ImageItem(url: url, originalImage: image)
        }
        images.append(contentsOf: newImages)

        // Set first image as active if none selected
        if activeImageID == nil {
            activeImageID = images.first?.id
        }

        // Auto-detect export format from first imported image
        var detectedFormat: ExportFormat?
        if wasEmpty, let firstImage = newImages.first {
            let ext = firstImage.fileExtension
            detectedFormat = ExportFormat.allCases.first(where: {
                $0.fileExtension == ext || (ext == "jpeg" && $0 == .jpeg)
            })
        }

        return AddImagesResult(addedCount: newImages.count, detectedFormat: detectedFormat)
    }

    /// Shows NSOpenPanel to import images
    /// - Parameter completion: Callback with the detected format (if any) that should be applied to export settings
    @MainActor
    func showImportPanel(completion: @escaping (ExportFormat?) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Import Images"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .bmp]

        panel.begin { [weak self] response in
            guard response == .OK else {
                completion(nil)
                return
            }
            Task { @MainActor in
                guard let self else {
                    completion(nil)
                    return
                }
                let result = self.addImages(from: panel.urls)
                completion(result.detectedFormat)
            }
        }
    }

    func removeImages(ids: Set<UUID>) {
        images.removeAll { ids.contains($0.id) }
        selectedImageIDs.subtract(ids)

        // Reset active image if it was removed
        if let activeID = activeImageID, ids.contains(activeID) {
            activeImageID = images.first?.id
        }
    }

    func clearAll() {
        images.removeAll()
        selectedImageIDs.removeAll()
        activeImageID = nil
    }

    func setActiveImage(_ id: UUID) {
        activeImageID = id
    }

    /// Move an image from one index to another
    func moveImage(from source: IndexSet, to destination: Int) {
        images.move(fromOffsets: source, toOffset: destination)
    }

    /// Reorder image by moving it to a new position
    func reorderImage(id: UUID, toIndex: Int) {
        guard let sourceIndex = images.firstIndex(where: { $0.id == id }) else { return }
        let item = images.remove(at: sourceIndex)
        let adjustedIndex = min(toIndex, images.count)
        images.insert(item, at: adjustedIndex)
    }

    func selectNextImage() {
        guard !images.isEmpty else { return }
        if let currentID = activeImageID,
           let currentIndex = images.firstIndex(where: { $0.id == currentID }) {
            if currentIndex < images.count - 1 {
                activeImageID = images[currentIndex + 1].id
            } else if loopNavigation {
                activeImageID = images.first?.id
            }
        } else {
            activeImageID = images.first?.id
        }
    }

    func selectPreviousImage() {
        guard !images.isEmpty else { return }
        if let currentID = activeImageID,
           let currentIndex = images.firstIndex(where: { $0.id == currentID }) {
            if currentIndex > 0 {
                activeImageID = images[currentIndex - 1].id
            } else if loopNavigation {
                activeImageID = images.last?.id
            }
        } else {
            activeImageID = images.last?.id
        }
    }
}
