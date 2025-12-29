import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

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

/// Editor tool mode
enum EditorTool: String, CaseIterable, Identifiable {
    case crop = "Crop"
    case blur = "Blur"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .crop: return "crop"
        case .blur: return "eye.slash"
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
    var showOutputDirectoryPicker = false
    var isProcessing = false
    var processingProgress: Double = 0
    var selectedImageIDs: Set<UUID> = []
    var activeImageID: UUID?
    var zoomMode: ZoomMode = .fit  // Default to fit view
    var showBeforeAfter = false  // Before/after preview toggle
    var loopNavigation = false  // Wrap around when navigating images
    var recentPresetIDs: [UUID] = []  // Recently used crop presets (max 5)

    // Blur/redact tool
    var currentTool: EditorTool = .crop
    var blurStyle: BlurRegion.BlurStyle = .blur
    var blurIntensity: Double = 1.0  // 0.0 to 1.0
    var blurRegions: [UUID: ImageBlurData] = [:]  // Keyed by image ID
    var selectedBlurRegionID: UUID?  // Currently selected region for editing

    // Image transforms (rotation/flip) - keyed by image ID
    var imageTransforms: [UUID: ImageTransform] = [:]

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

    // Undo/Redo history for crop settings (initialized with default state)
    private var cropHistory: [CropSettings] = [CropSettings()]
    private var cropHistoryIndex: Int = 0
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

    /// Shows NSOpenPanel to import images
    @MainActor
    func showImportPanel() {
        let panel = NSOpenPanel()
        panel.title = "Import Images"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .bmp]

        panel.begin { [weak self] response in
            guard response == .OK else { return }
            let urls = panel.urls
            Task { @MainActor in
                self?.addImages(from: urls)
            }
        }
    }

    func removeImages(ids: Set<UUID>) {
        images.removeAll { ids.contains($0.id) }
        selectedImageIDs.subtract(ids)

        // Clean up blur regions and transforms for removed images
        for id in ids {
            blurRegions.removeValue(forKey: id)
            imageTransforms.removeValue(forKey: id)
        }

        // Reset active image if it was removed
        if let activeID = activeImageID, ids.contains(activeID) {
            activeImageID = images.first?.id
            selectedBlurRegionID = nil
        }
    }

    func clearAll() {
        images.removeAll()
        selectedImageIDs.removeAll()
        activeImageID = nil
        cropSettings = CropSettings()
        blurRegions.removeAll()
        selectedBlurRegionID = nil
        imageTransforms.removeAll()
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

    /// Validates and clamps crop values to ensure they don't exceed image dimensions
    /// Call this after any direct crop value changes to prevent invalid states
    func validateAndClampCrop() {
        guard let image = activeImage else { return }
        let maxWidth = Int(image.originalSize.width)
        let maxHeight = Int(image.originalSize.height)

        // Clamp each edge, ensuring at least 1 pixel remains after cropping
        cropSettings.cropLeft = min(max(0, cropSettings.cropLeft), maxWidth - cropSettings.cropRight - 1)
        cropSettings.cropRight = min(max(0, cropSettings.cropRight), maxWidth - cropSettings.cropLeft - 1)
        cropSettings.cropTop = min(max(0, cropSettings.cropTop), maxHeight - cropSettings.cropBottom - 1)
        cropSettings.cropBottom = min(max(0, cropSettings.cropBottom), maxHeight - cropSettings.cropTop - 1)
    }

    // MARK: - Blur Regions

    /// Get blur regions for the active image
    var activeImageBlurRegions: [BlurRegion] {
        guard let id = activeImageID else { return [] }
        return blurRegions[id]?.regions ?? []
    }

    /// Add a blur region to the active image
    func addBlurRegion(_ region: BlurRegion) {
        guard let id = activeImageID else { return }
        if blurRegions[id] == nil {
            blurRegions[id] = ImageBlurData()
        }
        blurRegions[id]?.regions.append(region)
    }

    /// Remove a blur region from the active image
    func removeBlurRegion(_ regionID: UUID) {
        guard let id = activeImageID else { return }
        blurRegions[id]?.regions.removeAll { $0.id == regionID }
    }

    /// Clear all blur regions for the active image
    func clearBlurRegions() {
        guard let id = activeImageID else { return }
        blurRegions[id] = ImageBlurData()
        selectedBlurRegionID = nil
    }

    /// Check if any image has blur regions
    var hasAnyBlurRegions: Bool {
        blurRegions.values.contains { $0.hasRegions }
    }

    /// Get blur regions for a specific image
    func blurRegionsForImage(_ imageID: UUID) -> [BlurRegion] {
        blurRegions[imageID]?.regions ?? []
    }

    /// Select a blur region for editing
    func selectBlurRegion(_ regionID: UUID?) {
        selectedBlurRegionID = regionID
    }

    /// Get the currently selected blur region
    var selectedBlurRegion: BlurRegion? {
        guard let id = activeImageID,
              let regionID = selectedBlurRegionID,
              let data = blurRegions[id] else { return nil }
        return data.regions.first { $0.id == regionID }
    }

    /// Update a blur region's properties
    func updateBlurRegion(_ regionID: UUID, rect: CGRect? = nil, style: BlurRegion.BlurStyle? = nil, intensity: Double? = nil) {
        guard let imageID = activeImageID,
              var data = blurRegions[imageID],
              let index = data.regions.firstIndex(where: { $0.id == regionID }) else { return }

        if let rect = rect {
            data.regions[index].rect = rect
        }
        if let style = style {
            data.regions[index].style = style
        }
        if let intensity = intensity {
            data.regions[index].intensity = intensity
        }
        blurRegions[imageID] = data
    }

    /// Count of blur regions that will be outside the crop area
    var blurRegionsOutsideCropCount: Int {
        guard let image = activeImage else { return 0 }
        return activeImageBlurRegions.filter { $0.isOutsideCrop(cropSettings, imageSize: image.originalSize) }.count
    }

    /// Count of blur regions that will be partially cropped
    var blurRegionsPartiallyCroppedCount: Int {
        guard let image = activeImage else { return 0 }
        return activeImageBlurRegions.filter { $0.isPartiallyCropped(cropSettings, imageSize: image.originalSize) }.count
    }

    // MARK: - Image Transforms

    /// Get transform for the active image
    var activeImageTransform: ImageTransform {
        guard let id = activeImageID else { return .identity }
        return imageTransforms[id] ?? .identity
    }

    /// Check if any image has a transform applied
    var hasAnyTransforms: Bool {
        imageTransforms.values.contains { !$0.isIdentity }
    }

    /// Rotate the active image
    func rotateActiveImage(clockwise: Bool) {
        guard let id = activeImageID else { return }
        var transform = imageTransforms[id] ?? .identity
        if clockwise {
            transform.rotation.rotateCW()
        } else {
            transform.rotation.rotateCCW()
        }
        imageTransforms[id] = transform
    }

    /// Flip the active image
    func flipActiveImage(horizontal: Bool) {
        guard let id = activeImageID else { return }
        var transform = imageTransforms[id] ?? .identity
        if horizontal {
            transform.flipHorizontal.toggle()
        } else {
            transform.flipVertical.toggle()
        }
        imageTransforms[id] = transform
    }

    /// Reset transform for the active image
    func resetActiveImageTransform() {
        guard let id = activeImageID else { return }
        imageTransforms.removeValue(forKey: id)
    }

    /// Get transform for a specific image
    func transformForImage(_ imageID: UUID) -> ImageTransform {
        imageTransforms[imageID] ?? .identity
    }

    // MARK: - Export

    /// Whether export is possible (has images and something to do)
    var canExport: Bool {
        !images.isEmpty &&
        !isProcessing &&
        (cropSettings.hasAnyCrop ||
         hasAnyBlurRegions ||
         hasAnyTransforms ||
         exportSettings.resizeSettings.isEnabled ||
         exportSettings.renameSettings.mode == .pattern ||
         !exportSettings.preserveOriginalFormat)  // Format conversion counts as exportable change
    }

    /// Process and export images to the specified directory
    /// - Parameters:
    ///   - imagesToExport: Images to process (uses selected or all if nil)
    ///   - outputDirectory: Destination directory
    /// - Returns: Array of exported file URLs
    @MainActor
    func processAndExport(images imagesToExport: [ImageItem]? = nil, to outputDirectory: URL) async throws -> [URL] {
        let images = imagesToExport ?? (selectedImageIDs.isEmpty ? self.images : selectedImages)

        isProcessing = true
        processingProgress = 0

        defer {
            isProcessing = false
        }

        var settings = exportSettings
        settings.outputDirectory = .custom(outputDirectory)

        let results = try await ImageCropService.batchCrop(
            items: images,
            cropSettings: cropSettings,
            exportSettings: settings,
            transforms: imageTransforms,
            blurRegions: blurRegions
        ) { [weak self] progress in
            self?.processingProgress = progress
        }

        return results
    }

    /// Send system notification for completed export
    func sendExportNotification(count: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Export Complete"
        content.body = "\(count) image\(count == 1 ? "" : "s") exported successfully"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    /// Apply a crop preset with undo support
    func applyCropPreset(_ preset: CropPreset) {
        cropSettings = preset.cropSettings
        trackRecentPreset(preset.id)
        recordCropChange()
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

    // ┌─────────────────────────────────────────────────────────────────────┐
    // │  CRITICAL FIX - DO NOT CHANGE WITHOUT UNDERSTANDING THE BUG        │
    // │                                                                     │
    // │  NSImage.size returns POINTS (display units)                        │
    // │  CGImage.width/height returns PIXELS (actual image data)            │
    // │                                                                     │
    // │  On Retina displays, a screenshot might be:                         │
    // │    NSImage.size = 589×1278 (points)                                 │
    // │    CGImage size = 1178×2556 (pixels, 2x scale)                      │
    // │                                                                     │
    // │  If you use NSImage.size here, the crop preview will show one       │
    // │  thing but the export will crop at the WRONG POSITION because       │
    // │  ImageCropService.crop() works with CGImage pixel coordinates.      │
    // │                                                                     │
    // │  Fixed: 2025-12-29 - The app must work in PIXELS consistently.      │
    // └─────────────────────────────────────────────────────────────────────┘
    /// Returns the actual pixel dimensions (not points) for accurate cropping
    var originalSize: CGSize {
        guard let cgImage = originalImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return originalImage.size
        }
        return CGSize(width: cgImage.width, height: cgImage.height)
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
