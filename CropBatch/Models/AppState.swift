import SwiftUI
import UniformTypeIdentifiers

/// Zoom modes for the image preview
enum ZoomMode: String, CaseIterable, Identifiable {
    case actualSize = "100%"
    case fit = "Fit"
    case fitWidth = "Fit Width"
    case fitHeight = "Fit Height"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .actualSize: return "1.circle"
        case .fit: return "arrow.up.left.and.arrow.down.right"
        case .fitWidth: return "arrow.left.and.right"
        case .fitHeight: return "arrow.up.and.down"
        }
    }

    var shortcut: String {
        switch self {
        case .actualSize: return "⌘1"
        case .fit: return "⌘2"
        case .fitWidth: return "⌘3"
        case .fitHeight: return "⌘4"
        }
    }
}

@Observable
final class AppState {
    init() {
        loadRecentPresets()
    }

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
    var zoomMode: ZoomMode = .fit  // Default to fit view
    var showBeforeAfter = false  // Before/after preview toggle
    var recentPresetIDs: [UUID] = []  // Recently used crop presets (max 5)

    private let recentPresetsKey = "CropBatch.RecentPresetIDs"

    /// Track a preset as recently used
    func trackRecentPreset(_ presetID: UUID) {
        // Remove if already exists (to move to front)
        recentPresetIDs.removeAll { $0 == presetID }
        // Insert at front
        recentPresetIDs.insert(presetID, at: 0)
        // Keep only last 5
        if recentPresetIDs.count > 5 {
            recentPresetIDs = Array(recentPresetIDs.prefix(5))
        }
        // Persist
        let strings = recentPresetIDs.map { $0.uuidString }
        UserDefaults.standard.set(strings, forKey: recentPresetsKey)
    }

    /// Load recent presets from UserDefaults
    func loadRecentPresets() {
        guard let strings = UserDefaults.standard.stringArray(forKey: recentPresetsKey) else { return }
        recentPresetIDs = strings.compactMap { UUID(uuidString: $0) }
    }
    var edgeLinkMode: EdgeLinkMode = .none  // Linked edge cropping mode
    var showAspectRatioGuide: AspectRatioGuide? = nil  // Aspect ratio guide overlay

    // Undo/Redo history for crop settings
    private var cropHistory: [CropSettings] = []
    private var cropHistoryIndex: Int = -1
    private var isUndoRedoAction = false

    var canUndo: Bool { cropHistoryIndex > 0 }
    var canRedo: Bool { cropHistoryIndex < cropHistory.count - 1 }

    /// Record current crop settings in history
    func recordCropChange() {
        guard !isUndoRedoAction else { return }

        // Remove any redo history
        if cropHistoryIndex < cropHistory.count - 1 {
            cropHistory.removeSubrange((cropHistoryIndex + 1)...)
        }

        cropHistory.append(cropSettings)
        cropHistoryIndex = cropHistory.count - 1

        // Limit history to 50 items
        if cropHistory.count > 50 {
            cropHistory.removeFirst()
            cropHistoryIndex -= 1
        }
    }

    /// Undo last crop change
    func undo() {
        guard canUndo else { return }
        isUndoRedoAction = true
        cropHistoryIndex -= 1
        cropSettings = cropHistory[cropHistoryIndex]
        isUndoRedoAction = false
    }

    /// Redo previously undone crop change
    func redo() {
        guard canRedo else { return }
        isUndoRedoAction = true
        cropHistoryIndex += 1
        cropSettings = cropHistory[cropHistoryIndex]
        isUndoRedoAction = false
    }

    /// Reset all crops
    func resetCropSettings() {
        cropSettings = CropSettings()
        recordCropChange()
    }

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
