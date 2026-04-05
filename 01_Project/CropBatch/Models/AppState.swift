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

/// Main application state that composes specialized managers
/// This class acts as a facade, delegating to focused managers while
/// maintaining backward compatibility with existing views
@MainActor
@Observable
final class AppState {

    // MARK: - Composed Managers

    /// Manages image collection and selection
    let imageManager = ImageManager()

    /// Manages crop settings and undo/redo
    let cropManager = CropManager()

    /// Manages blur regions and transforms
    let blurManager = BlurManager()

    /// Manages snap point detection
    let snapManager = SnapPointsManager()

    // MARK: - Export Settings (kept here as it's tightly coupled with export flow)

    var exportSettings = ExportSettings()
    var selectedPresetID: String? = "png_lossless"
    var showOutputDirectoryPicker = false
    var isProcessing = false
    var processingProgress: Double = 0

    /// Tracks the current export task to prevent concurrent exports
    /// and enable cancellation when a new export is requested
    private var currentExportTask: Task<[URL], Error>?

    // MARK: - View State

    var zoomMode: ZoomMode = .fit
    var showBeforeAfter = false
    var isBlurDrawingEnabled = false

    // MARK: - Initialization

    init() {
        // Managers initialize themselves
    }

    // MARK: - Backward Compatible Properties (delegate to managers)

    // Image Manager delegations
    var images: [ImageItem] {
        get { imageManager.images }
        set { imageManager.images = newValue }
    }

    var selectedImageIDs: Set<UUID> {
        get { imageManager.selectedImageIDs }
        set { imageManager.selectedImageIDs = newValue }
    }

    var activeImageID: UUID? {
        get { imageManager.activeImageID }
        set { imageManager.activeImageID = newValue }
    }

    var loopNavigation: Bool {
        get { imageManager.loopNavigation }
        set { imageManager.loopNavigation = newValue }
    }

    var selectedImages: [ImageItem] { imageManager.selectedImages }
    var activeImage: ImageItem? { imageManager.activeImage }
    var majorityResolution: CGSize? { imageManager.majorityResolution }
    var mismatchedImages: [ImageItem] { imageManager.mismatchedImages }
    var hasResolutionMismatch: Bool { imageManager.hasResolutionMismatch }
    var memoryWarningLevel: ImageManager.MemoryWarningLevel { imageManager.memoryWarningLevel }
    var shouldShowMemoryWarning: Bool { imageManager.shouldShowMemoryWarning }
    var memoryWarningMessage: String? { imageManager.memoryWarningMessage }

    // Crop Manager delegations
    var cropSettings: CropSettings {
        get { cropManager.settings }
        set { cropManager.settings = newValue }
    }

    var edgeLinkMode: EdgeLinkMode {
        get { cropManager.edgeLinkMode }
        set { cropManager.edgeLinkMode = newValue }
    }

    var showAspectRatioGuide: AspectRatioGuide? {
        get { cropManager.showAspectRatioGuide }
        set { cropManager.showAspectRatioGuide = newValue }
    }

    var recentPresetIDs: [UUID] { cropManager.recentPresetIDs }
    var canUndo: Bool { cropManager.canUndo }
    var canRedo: Bool { cropManager.canRedo }

    // Blur Manager delegations
    var blurStyle: BlurRegion.BlurStyle {
        get { blurManager.style }
        set { blurManager.style = newValue }
    }

    var blurIntensity: Double {
        get { blurManager.intensity }
        set { blurManager.intensity = newValue }
    }

    var blurRegions: [UUID: ImageBlurData] {
        blurManager.blurRegionsForExport(imageIDs: images.map(\.id))
    }

    var selectedBlurRegionID: UUID? {
        get { blurManager.selectedRegionID }
        set { blurManager.selectedRegionID = newValue }
    }

    var imageTransform: ImageTransform {
        get { blurManager.transform }
        set { blurManager.transform = newValue }
    }

    var hasAnyBlurRegions: Bool { blurManager.hasAnyRegions }
    var hasAnyTransforms: Bool { blurManager.hasAnyTransforms }

    // Snap Manager delegations
    var snapPointsCache: [UUID: SnapPoints] {
        get { snapManager.cache }
    }

    var isDetectingSnapPoints: Bool {
        get { snapManager.isDetecting }
    }

    var snapEnabled: Bool {
        get { snapManager.enabled }
        set { snapManager.enabled = newValue }
    }

    var snapThreshold: Int {
        get { snapManager.threshold }
        set { snapManager.threshold = newValue }
    }

    var snapToCenter: Bool {
        get { snapManager.snapToCenter }
        set { snapManager.snapToCenter = newValue }
    }

    var showSnapDebug: Bool {
        get { snapManager.showDebug }
        set { snapManager.showDebug = newValue }
    }

    var edgeSensitivity: Double {
        get { snapManager.edgeSensitivity }
        set { snapManager.edgeSensitivity = newValue }
    }

    /// Call after sensitivity editing completes to re-detect edges
    func applyEdgeSensitivity() {
        snapManager.invalidateAllCache()
        Task { await detectSnapPointsForActiveImage() }
    }

    // MARK: - Backward Compatible Methods

    // Image methods
    func addImages(from urls: [URL]) {
        let result = imageManager.addImages(from: urls)
        // Apply detected format if available
        if let format = result.detectedFormat {
            exportSettings.format = format
            selectedPresetID = nil  // Mark as custom since we changed the format
        }
    }

    @MainActor
    func showImportPanel() {
        imageManager.showImportPanel { [weak self] detectedFormat in
            guard let self else { return }
            if let format = detectedFormat {
                self.exportSettings.format = format
                self.selectedPresetID = nil  // Mark as custom since we changed the format
            }
        }
    }

    func removeImages(ids: Set<UUID>) {
        imageManager.removeImages(ids: ids)
        blurManager.clearRegions(for: ids)
        snapManager.clearCache(for: ids)
    }

    func clearAll() {
        imageManager.clearAll()
        cropManager.reset()
        blurManager.clearAll()
        snapManager.clearAll()
    }

    func setActiveImage(_ id: UUID) {
        imageManager.setActiveImage(id)
    }

    func moveImage(from source: IndexSet, to destination: Int) {
        imageManager.moveImage(from: source, to: destination)
    }

    func reorderImage(id: UUID, toIndex: Int) {
        imageManager.reorderImage(id: id, toIndex: toIndex)
    }

    func selectNextImage() {
        imageManager.selectNextImage()
    }

    func selectPreviousImage() {
        imageManager.selectPreviousImage()
    }

    // Crop methods
    func recordCropChange() {
        cropManager.recordChange()
    }

    func undo() {
        cropManager.undo()
    }

    func redo() {
        cropManager.redo()
    }

    func resetCropSettings() {
        cropManager.reset()
    }

    func adjustCrop(edge: CropEdge, delta: Int) {
        guard let effectiveSize = activeImageEffectiveSize else { return }
        cropManager.adjustCrop(
            edge: edge,
            delta: delta,
            maxWidth: Int(effectiveSize.width),
            maxHeight: Int(effectiveSize.height)
        )
    }

    func validateAndClampCrop() {
        guard let effectiveSize = activeImageEffectiveSize else { return }
        cropManager.validateAndClamp(
            maxWidth: Int(effectiveSize.width),
            maxHeight: Int(effectiveSize.height)
        )
    }

    func applyCropPreset(_ preset: CropPreset) {
        cropManager.applyPreset(preset)
    }

    func trackRecentPreset(_ presetID: UUID) {
        cropManager.trackRecentPreset(presetID)
    }

    // Blur/Transform methods
    var activeImageBlurRegions: [BlurRegion] {
        guard let id = activeImageID else { return [] }
        return blurManager.regionsForImage(id)
    }

    func addBlurRegion(_ region: BlurRegion) {
        guard let id = activeImageID else { return }
        blurManager.addRegion(region, to: id)
    }

    func removeBlurRegion(_ regionID: UUID) {
        guard let id = activeImageID else { return }
        blurManager.removeRegion(regionID, from: id)
    }

    func clearBlurRegions() {
        guard let id = activeImageID else { return }
        blurManager.clearRegions(for: id)
    }

    /// Reset the active image's override so it uses global blur regions
    func resetBlurForActiveImage() {
        guard let id = activeImageID else { return }
        blurManager.imageOverrides.removeValue(forKey: id)
    }

    /// Toggle blur opt-out for the active image
    func toggleBlurOptOut() {
        guard let id = activeImageID else { return }
        blurManager.toggleOptOut(id)
    }

    /// Create per-image custom blur regions for the active image
    func customizeBlurForActiveImage() {
        guard let id = activeImageID else { return }
        blurManager.customizeImage(id)
    }

    /// Whether the active image is opted out of blur
    var isActiveImageBlurOptedOut: Bool {
        guard let id = activeImageID else { return false }
        return blurManager.isOptedOut(id)
    }

    /// Whether the active image has custom blur regions
    var activeImageHasCustomBlur: Bool {
        guard let id = activeImageID else { return false }
        return blurManager.hasCustomRegions(id)
    }

    func blurRegionsForImage(_ imageID: UUID) -> [BlurRegion] {
        blurManager.regionsForImage(imageID)
    }

    func selectBlurRegion(_ regionID: UUID?) {
        blurManager.selectRegion(regionID)
    }

    var selectedBlurRegion: BlurRegion? {
        guard let id = activeImageID else { return nil }
        return blurManager.selectedRegion(for: id)
    }

    func updateBlurRegion(_ regionID: UUID, normalizedRect: NormalizedRect? = nil, style: BlurRegion.BlurStyle? = nil, intensity: Double? = nil) {
        guard let imageID = activeImageID else { return }
        blurManager.updateRegion(regionID, in: imageID, normalizedRect: normalizedRect, style: style, intensity: intensity)
    }

    var blurRegionsOutsideCropCount: Int {
        guard let image = activeImage else { return 0 }
        return blurManager.regionsOutsideCropCount(for: image.id, cropSettings: cropSettings, imageSize: image.originalSize)
    }

    var blurRegionsPartiallyCroppedCount: Int {
        guard let image = activeImage else { return 0 }
        return blurManager.regionsPartiallyCroppedCount(for: image.id, cropSettings: cropSettings, imageSize: image.originalSize)
    }

    var activeImageTransform: ImageTransform {
        blurManager.transform
    }

    func rotateActiveImage(clockwise: Bool) {
        blurManager.rotate(clockwise: clockwise)
        validateAndClampCrop()
    }

    func flipActiveImage(horizontal: Bool) {
        blurManager.flip(horizontal: horizontal)
    }

    func resetActiveImageTransform() {
        blurManager.resetTransform()
        validateAndClampCrop()
    }

    /// The global transform applied to all images
    /// (Currently transforms are batch-applied, not per-image)
    var globalTransform: ImageTransform {
        blurManager.transform
    }

    /// Deprecated: Use `globalTransform` instead.
    /// The imageID parameter was misleading as transforms apply globally.
    @available(*, deprecated, message: "Use globalTransform instead - transforms apply to all images globally")
    func transformForImage(_ imageID: UUID) -> ImageTransform {
        globalTransform
    }

    /// Returns the effective image size after applying current transform
    var activeImageEffectiveSize: CGSize? {
        guard let image = activeImage else { return nil }
        return blurManager.effectiveSize(for: image.originalSize)
    }

    // Snap methods
    var activeSnapPoints: SnapPoints {
        guard let id = activeImageID else { return .empty }
        return snapManager.snapPoints(for: id, imageSize: activeImage?.originalImage.size)
    }

    @MainActor
    func detectSnapPointsForActiveImage() async {
        guard let image = activeImage else { return }
        await snapManager.detect(for: image)
    }

    func clearSnapPointsCache(for imageIDs: Set<UUID>? = nil) {
        if let ids = imageIDs {
            snapManager.clearCache(for: ids)
        } else {
            snapManager.clearAll()
        }
    }

    func snapValue(_ value: Int, for edge: CropEdge, threshold: Int = 15) -> Int? {
        guard let id = activeImageID else { return nil }
        return snapManager.snapValue(value, for: edge, imageID: id, imageSize: activeImage?.originalImage.size)
    }

    // MARK: - Export Settings

    var selectedPreset: ExportPreset? {
        ExportPreset.presets.first { $0.id == selectedPresetID }
    }

    func applyPreset(_ preset: ExportPreset) {
        selectedPresetID = preset.id
        exportSettings = preset.settings
    }

    func markCustomSettings() {
        selectedPresetID = nil
    }

    // MARK: - Export Capability

    var canExport: Bool {
        !images.isEmpty &&
        !isProcessing &&
        (cropSettings.hasAnyCrop ||
         hasAnyBlurRegions ||
         hasAnyTransforms ||
         exportSettings.resizeSettings.isEnabled ||
         exportSettings.renameSettings.mode == .pattern ||
         (exportSettings.gridSettings.isEnabled && (exportSettings.gridSettings.rows > 1 || exportSettings.gridSettings.columns > 1)) ||
         !exportSettings.preserveOriginalFormat)
    }

    // MARK: - Export Operations

    @MainActor
    func processAndExport(images imagesToExport: [ImageItem]? = nil, to outputDirectory: URL) async throws -> [URL] {
        // Cancel any existing export to prevent concurrent operations
        currentExportTask?.cancel()

        let images = imagesToExport ?? (selectedImageIDs.isEmpty ? self.images : selectedImages)

        // Capture settings at start to prevent mid-export changes
        let capturedCropSettings = cropSettings
        let capturedTransform = imageTransform
        let capturedBlurRegions = blurRegions
        var capturedExportSettings = exportSettings
        capturedExportSettings.outputDirectory = .custom(outputDirectory)

        isProcessing = true
        processingProgress = 0

        let task = Task<[URL], Error> { [weak self] in
            defer {
                Task { @MainActor in
                    self?.isProcessing = false
                    self?.currentExportTask = nil
                }
            }

            try Task.checkCancellation()

            let results = try await ImageCropService.batchCrop(
                items: images,
                cropSettings: capturedCropSettings,
                exportSettings: capturedExportSettings,
                transform: capturedTransform,
                blurRegions: capturedBlurRegions
            ) { progress in
                Task { @MainActor in
                    self?.processingProgress = progress
                }
            }

            return results
        }

        currentExportTask = task
        return try await task.value
    }

    @MainActor
    func processAndExportWithRename(images imagesToExport: [ImageItem], to outputDirectory: URL) async throws -> [URL] {
        // Cancel any existing export to prevent concurrent operations
        currentExportTask?.cancel()

        // Capture settings at start to prevent mid-export changes
        let capturedCropSettings = cropSettings
        let capturedTransform = imageTransform
        let capturedBlurRegions = blurRegions
        var capturedExportSettings = exportSettings
        capturedExportSettings.outputDirectory = .custom(outputDirectory)

        isProcessing = true
        processingProgress = 0

        let task = Task<[URL], Error> { [weak self] in
            defer {
                Task { @MainActor in
                    self?.isProcessing = false
                    self?.currentExportTask = nil
                }
            }

            try Task.checkCancellation()

            // Separate images into conflicting and non-conflicting
            var nonConflicting: [(index: Int, item: ImageItem)] = []
            var conflicting: [(index: Int, item: ImageItem, renamedURL: URL)] = []

            // Use findExistingFiles which is grid-aware (checks all tile URLs per image)
            let existingFiles = capturedExportSettings.findExistingFiles(items: imagesToExport)
            let conflictingIndices = Set(existingFiles.map { $0.index })

            for (index, item) in imagesToExport.enumerated() {
                if conflictingIndices.contains(index) {
                    let baseURL = capturedExportSettings.outputURL(for: item.url, index: index)
                    let renamedURL = ExportSettings.appendNumericSuffix(to: baseURL)
                    conflicting.append((index, item, renamedURL))
                } else {
                    nonConflicting.append((index, item))
                }
            }

            var results: [(index: Int, url: URL)] = []
            let total = Double(imagesToExport.count)

            // Process non-conflicting images in batch (fast path)
            if !nonConflicting.isEmpty {
                try Task.checkCancellation()
                let nonConflictingItems = nonConflicting.map { $0.item }
                let batchResults = try await ImageCropService.batchCrop(
                    items: nonConflictingItems,
                    cropSettings: capturedCropSettings,
                    exportSettings: capturedExportSettings,
                    transform: capturedTransform,
                    blurRegions: capturedBlurRegions
                ) { [weak self] progress in
                    let completed = Double(nonConflicting.count) * progress
                    self?.processingProgress = completed / total
                }

                // batchCrop returns flattened tile URLs (multiple per image when grid is enabled)
                for url in batchResults {
                    results.append((0, url))
                }
            }

            // Process conflicting images one by one to custom locations
            for (i, (originalIndex, item, renamedURL)) in conflicting.enumerated() {
                try Task.checkCancellation()

                let tiles = try ImageCropService.processImageThroughPipeline(
                    item: item,
                    index: originalIndex,
                    count: imagesToExport.count,
                    cropSettings: capturedCropSettings,
                    exportSettings: capturedExportSettings,
                    transform: capturedTransform,
                    blurRegions: capturedBlurRegions
                )

                let gridSettings = capturedExportSettings.gridSettings

                for tile in tiles {
                    var tileURL = renamedURL

                    // Force .png extension when corner radius is enabled
                    if capturedCropSettings.cornerRadiusEnabled {
                        let baseName = tileURL.deletingPathExtension().lastPathComponent
                        tileURL = tileURL.deletingLastPathComponent()
                            .appendingPathComponent(baseName)
                            .appendingPathExtension("png")
                    }

                    // Add grid suffix if this is a grid tile
                    if let gridPos = tile.gridPosition {
                        let suffix = gridSettings.namingSuffix
                            .replacingOccurrences(of: "{row}", with: "\(gridPos.row)")
                            .replacingOccurrences(of: "{col}", with: "\(gridPos.col)")
                        let baseName = tileURL.deletingPathExtension().lastPathComponent
                        let ext = tile.format == .png ? "png" : tileURL.pathExtension
                        tileURL = tileURL.deletingLastPathComponent()
                            .appendingPathComponent("\(baseName)\(suffix)")
                            .appendingPathExtension(ext)
                    }

                    try ImageCropService.save(tile.image, to: tileURL, format: tile.format,
                                              quality: capturedExportSettings.quality)
                    results.append((originalIndex, tileURL))
                }

                let completed = Double(nonConflicting.count + i + 1)
                Task { @MainActor in
                    self?.processingProgress = completed / total
                }
            }

            return results.sorted { $0.index < $1.index }.map { $0.url }
        }

        currentExportTask = task
        return try await task.value
    }

    /// Export images by overwriting original files ("Save in Place")
    @MainActor
    func processAndExportInPlace(images imagesToExport: [ImageItem]) async throws -> [URL] {
        // Cancel any existing export to prevent concurrent operations
        currentExportTask?.cancel()

        // Capture settings at start to prevent mid-export changes
        let capturedCropSettings = cropSettings
        let capturedTransform = imageTransform
        let capturedBlurRegions = blurRegions
        var capturedExportSettings = exportSettings
        capturedExportSettings.outputDirectory = .overwriteOriginal

        isProcessing = true
        processingProgress = 0

        let task = Task<[URL], Error> { [weak self] in
            defer {
                Task { @MainActor in
                    self?.isProcessing = false
                    self?.currentExportTask = nil
                }
            }

            try Task.checkCancellation()

            let results = try await ImageCropService.batchCrop(
                items: imagesToExport,
                cropSettings: capturedCropSettings,
                exportSettings: capturedExportSettings,
                transform: capturedTransform,
                blurRegions: capturedBlurRegions
            ) { progress in
                Task { @MainActor in
                    self?.processingProgress = progress
                }
            }

            return results
        }

        currentExportTask = task
        return try await task.value
    }

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
}

// MARK: - ImageItem (unchanged)

struct ImageItem: Identifiable {
    let id = UUID()
    let url: URL
    let originalImage: NSImage
    let fileSize: Int64
    var isProcessed = false

    init(url: URL, originalImage: NSImage) {
        self.url = url
        self.originalImage = originalImage
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
    var originalSize: CGSize {
        guard let cgImage = originalImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return originalImage.size
        }
        return CGSize(width: cgImage.width, height: cgImage.height)
    }

    var fileExtension: String {
        url.pathExtension.lowercased()
    }

    var isLossyFormat: Bool {
        ["jpg", "jpeg", "heic"].contains(fileExtension)
    }
}
