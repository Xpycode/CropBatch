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

    // Global image transform (rotation/flip) - applies to all images
    var imageTransform: ImageTransform = .identity

    // Snap points for rectangle snapping (keyed by image ID)
    var snapPointsCache: [UUID: SnapPoints] = [:]
    var isDetectingSnapPoints = false
    var snapEnabled = true  // Master toggle for snap functionality

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
        if wasEmpty, let firstImage = newImages.first {
            let ext = firstImage.fileExtension
            if let detectedFormat = ExportFormat.allCases.first(where: {
                $0.fileExtension == ext || (ext == "jpeg" && $0 == .jpeg)
            }) {
                exportSettings.format = detectedFormat
                selectedPresetID = nil  // Mark as custom since we changed the format
            }
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

        // Clean up blur regions and snap points for removed images
        for id in ids {
            blurRegions.removeValue(forKey: id)
            snapPointsCache.removeValue(forKey: id)
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
        snapPointsCache.removeAll()
        selectedBlurRegionID = nil
        imageTransform = .identity
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

    /// Returns the effective image size after applying current transform (rotation may swap dimensions)
    var activeImageEffectiveSize: CGSize? {
        guard let image = activeImage else { return nil }
        return activeImageTransform.transformedSize(image.originalSize)
    }

    func adjustCrop(edge: CropEdge, delta: Int) {
        guard let effectiveSize = activeImageEffectiveSize else { return }
        let maxWidth = Int(effectiveSize.width)
        let maxHeight = Int(effectiveSize.height)

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
    /// Accounts for current transform (rotation) when calculating max dimensions
    func validateAndClampCrop() {
        guard let effectiveSize = activeImageEffectiveSize else { return }
        let maxWidth = Int(effectiveSize.width)
        let maxHeight = Int(effectiveSize.height)

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
    func updateBlurRegion(_ regionID: UUID, normalizedRect: NormalizedRect? = nil, style: BlurRegion.BlurStyle? = nil, intensity: Double? = nil) {
        guard let imageID = activeImageID,
              var data = blurRegions[imageID],
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

    // MARK: - Image Transforms (Global - applies to all images)

    /// Get the global transform (applies to all images)
    var activeImageTransform: ImageTransform {
        imageTransform
    }

    /// Check if transform is applied
    var hasAnyTransforms: Bool {
        !imageTransform.isIdentity
    }

    /// Rotate all images
    func rotateActiveImage(clockwise: Bool) {
        if clockwise {
            imageTransform.rotation.rotateCW()
        } else {
            imageTransform.rotation.rotateCCW()
        }

        // Validate crop values - rotation may swap dimensions making some crop values invalid
        validateAndClampCrop()
    }

    /// Flip all images
    func flipActiveImage(horizontal: Bool) {
        if horizontal {
            imageTransform.flipHorizontal.toggle()
        } else {
            imageTransform.flipVertical.toggle()
        }
    }

    /// Reset transform for all images
    func resetActiveImageTransform() {
        imageTransform = .identity

        // Validate crop values - resetting rotation may change effective dimensions
        validateAndClampCrop()
    }

    /// Get transform for a specific image (returns global transform)
    func transformForImage(_ imageID: UUID) -> ImageTransform {
        imageTransform
    }

    // MARK: - Snap Points (Rectangle Detection)

    /// Get snap points for the active image
    var activeSnapPoints: SnapPoints {
        guard let id = activeImageID else { return .empty }
        return snapPointsCache[id] ?? .empty
    }

    /// Detect snap points for the active image
    @MainActor
    func detectSnapPointsForActiveImage() async {
        guard let image = activeImage else { return }

        // Skip if already cached
        if snapPointsCache[image.id] != nil { return }

        isDetectingSnapPoints = true

        let snapPoints = await RectangleDetector.detect(in: image.originalImage)
        snapPointsCache[image.id] = snapPoints

        isDetectingSnapPoints = false
    }

    /// Clear snap points cache (call when images are removed)
    func clearSnapPointsCache(for imageIDs: Set<UUID>? = nil) {
        if let ids = imageIDs {
            for id in ids {
                snapPointsCache.removeValue(forKey: id)
            }
        } else {
            snapPointsCache.removeAll()
        }
    }

    /// Find the nearest snap point for a given edge value
    func snapValue(_ value: Int, for edge: CropEdge, threshold: Int = 15) -> Int? {
        guard snapEnabled else { return nil }
        let snapPoints = activeSnapPoints

        switch edge {
        case .top, .bottom:
            return snapPoints.nearestHorizontalEdge(to: value, threshold: threshold)
        case .left, .right:
            return snapPoints.nearestVerticalEdge(to: value, threshold: threshold)
        }
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
            transform: imageTransform,
            blurRegions: blurRegions
        ) { [weak self] progress in
            self?.processingProgress = progress
        }

        return results
    }

    /// Process and export images with automatic renaming to avoid overwriting existing files
    /// Existing files are preserved; new exports get _1, _2, etc. suffixes
    /// - Parameters:
    ///   - imagesToExport: Images to process
    ///   - outputDirectory: Destination directory
    /// - Returns: Array of exported file URLs
    @MainActor
    func processAndExportWithRename(images imagesToExport: [ImageItem], to outputDirectory: URL) async throws -> [URL] {
        isProcessing = true
        processingProgress = 0

        defer {
            isProcessing = false
        }

        var settings = exportSettings
        settings.outputDirectory = .custom(outputDirectory)

        // Separate images into conflicting and non-conflicting
        var nonConflicting: [(index: Int, item: ImageItem)] = []
        var conflicting: [(index: Int, item: ImageItem, renamedURL: URL)] = []

        for (index, item) in imagesToExport.enumerated() {
            let plannedURL = settings.outputURL(for: item.url, index: index)
            if FileManager.default.fileExists(atPath: plannedURL.path) {
                let renamedURL = ExportSettings.appendNumericSuffix(to: plannedURL)
                conflicting.append((index, item, renamedURL))
            } else {
                nonConflicting.append((index, item))
            }
        }

        var results: [(index: Int, url: URL)] = []
        let total = Double(imagesToExport.count)

        // Process non-conflicting images in batch (fast path)
        if !nonConflicting.isEmpty {
            let nonConflictingItems = nonConflicting.map { $0.item }
            let batchResults = try await ImageCropService.batchCrop(
                items: nonConflictingItems,
                cropSettings: cropSettings,
                exportSettings: settings,
                transform: imageTransform,
                blurRegions: blurRegions
            ) { [weak self] progress in
                let completed = Double(nonConflicting.count) * progress
                self?.processingProgress = completed / total
            }

            for (i, result) in batchResults.enumerated() {
                results.append((nonConflicting[i].index, result))
            }
        }

        // Process conflicting images one by one to custom locations
        // This preserves existing files
        for (i, (originalIndex, item, renamedURL)) in conflicting.enumerated() {
            // Process single image
            var processedImage = item.originalImage

            // Apply transform if any
            if !imageTransform.isIdentity {
                processedImage = ImageCropService.applyTransform(processedImage, transform: imageTransform)
            }

            // Apply blur regions if any
            if let imageBlurData = blurRegions[item.id], imageBlurData.hasRegions {
                processedImage = ImageCropService.applyBlurRegions(processedImage, regions: imageBlurData.regions)
            }

            // Apply crop
            processedImage = try ImageCropService.crop(processedImage, with: cropSettings)

            // Apply resize if enabled
            if let targetSize = ImageCropService.calculateResizedSize(from: processedImage.size, with: settings.resizeSettings) {
                processedImage = ImageCropService.resize(processedImage, to: targetSize)
            }

            // Determine format
            let format: UTType
            if settings.preserveOriginalFormat {
                let ext = item.url.pathExtension.lowercased()
                format = ExportFormat.allCases.first {
                    $0.fileExtension == ext || (ext == "jpeg" && $0 == .jpeg)
                }?.utType ?? settings.format.utType
            } else {
                format = settings.format.utType
            }

            // Save directly to renamed location (preserving existing file)
            try ImageCropService.save(processedImage, to: renamedURL, format: format, quality: settings.quality)
            results.append((originalIndex, renamedURL))

            // Update progress
            let completed = Double(nonConflicting.count + i + 1)
            processingProgress = completed / total
        }

        // Sort by original index and return URLs
        return results.sorted { $0.index < $1.index }.map { $0.url }
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
