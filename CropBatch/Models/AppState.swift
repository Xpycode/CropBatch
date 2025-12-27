import SwiftUI
import UniformTypeIdentifiers

@Observable
final class AppState {
    var images: [ImageItem] = []
    var cropSettings = CropSettings()
    var exportSettings = ExportSettings()
    var selectedPresetID: String? = "png_lossless"
    var showFileImporter = false
    var showOutputDirectoryPicker = false
    var isProcessing = false
    var processingProgress: Double = 0
    var selectedImageIDs: Set<UUID> = []
    var activeImageID: UUID?

    /// Currently selected preset (if any)
    var selectedPreset: ExportPreset? {
        ExportPreset.presets.first { $0.id == selectedPresetID }
    }

    /// Apply a preset to export settings
    func applyPreset(_ preset: ExportPreset) {
        selectedPresetID = preset.id
        exportSettings = preset.settings
    }

    /// Called when export settings are manually changed
    func markCustomSettings() {
        selectedPresetID = nil
    }

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

    func addImages(from urls: [URL]) {
        let newImages = urls.compactMap { url -> ImageItem? in
            guard let image = NSImage(contentsOf: url) else { return nil }
            return ImageItem(url: url, originalImage: image)
        }
        images.append(contentsOf: newImages)

        // Set first image as active if none selected
        if activeImageID == nil {
            activeImageID = images.first?.id
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
        cropSettings = CropSettings()
    }

    func setActiveImage(_ id: UUID) {
        activeImageID = id
    }

    func selectNextImage() {
        guard !images.isEmpty else { return }
        if let currentID = activeImageID,
           let currentIndex = images.firstIndex(where: { $0.id == currentID }) {
            let nextIndex = (currentIndex + 1) % images.count
            activeImageID = images[nextIndex].id
        } else {
            activeImageID = images.first?.id
        }
    }

    func selectPreviousImage() {
        guard !images.isEmpty else { return }
        if let currentID = activeImageID,
           let currentIndex = images.firstIndex(where: { $0.id == currentID }) {
            let prevIndex = currentIndex > 0 ? currentIndex - 1 : images.count - 1
            activeImageID = images[prevIndex].id
        } else {
            activeImageID = images.last?.id
        }
    }

    func adjustCrop(edge: CropEdge, delta: Int) {
        guard let activeImage = activeImage else { return }
        let maxWidth = Int(activeImage.originalSize.width)
        let maxHeight = Int(activeImage.originalSize.height)

        switch edge {
        case .top:
            let newValue = cropSettings.cropTop + delta
            cropSettings.cropTop = max(0, min(newValue, maxHeight - cropSettings.cropBottom - 10))
        case .bottom:
            let newValue = cropSettings.cropBottom + delta
            cropSettings.cropBottom = max(0, min(newValue, maxHeight - cropSettings.cropTop - 10))
        case .left:
            let newValue = cropSettings.cropLeft + delta
            cropSettings.cropLeft = max(0, min(newValue, maxWidth - cropSettings.cropRight - 10))
        case .right:
            let newValue = cropSettings.cropRight + delta
            cropSettings.cropRight = max(0, min(newValue, maxWidth - cropSettings.cropLeft - 10))
        }
    }
}

struct ImageItem: Identifiable {
    let id = UUID()
    let url: URL
    let originalImage: NSImage
    let fileSize: Int64  // in bytes
    var isProcessed = false

    init(url: URL, originalImage: NSImage) {
        self.url = url
        self.originalImage = originalImage
        // Get file size from disk
        self.fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }

    var filename: String {
        url.lastPathComponent
    }

    var originalSize: CGSize {
        originalImage.size
    }

    /// Original file extension (lowercase)
    var fileExtension: String {
        url.pathExtension.lowercased()
    }

    /// Whether the original is a lossy format
    var isLossyFormat: Bool {
        ["jpg", "jpeg", "heic"].contains(fileExtension)
    }
}
