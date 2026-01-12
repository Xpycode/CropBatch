# CropBatch Code Review - Consolidated Fixing Plan

**Created**: January 4, 2026
**Based on**: 3 code review reports from 2026-01-04
**Total Issues Identified**: 27 unique issues (17 critical, 10 important)

---

## Executive Summary

Three code reviews identified issues across the CropBatch codebase. This plan consolidates duplicate findings, prioritizes by crash risk and data integrity, and provides a phased implementation approach.

| Phase | Focus Area | Issues | Risk Level |
|-------|-----------|--------|------------|
| Phase 1 | Crash Prevention | 5 | Critical |
| Phase 2 | Data Integrity | 5 | High |
| Phase 3 | Memory & Resources | 5 | Medium |
| Phase 4 | Code Quality | 7 | Low |

---

## Phase 1: Crash Prevention (Critical Priority)

These issues can cause application crashes or undefined behavior. **Fix before any production use.**

### 1.1 FolderWatcher Race Condition & File Descriptor Leak
**Files**: `CropBatch/Services/FolderWatcher.swift`
**Issue IDs**: S2, S3 (Review 3)

**Problems**:
- `fileDescriptor` accessed from multiple threads without synchronization
- If `DispatchSource.makeFileSystemObjectSource` fails after `open()`, file descriptor leaks
- `setCancelHandler` runs on arbitrary queue

**Fix**:
```swift
func startWatching(folder: URL, output: URL) {
    guard !isWatching else { return }

    // ... existing setup ...

    let fd = open(folder.path, O_EVTONLY)
    guard fd >= 0 else {
        errorMessage = "Cannot access folder"
        return
    }

    guard let source = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: fd,
        eventMask: .write,
        queue: .main  // Use main queue for thread safety
    ) else {
        close(fd)  // CRITICAL: Close fd on failure
        errorMessage = "Failed to create file monitor"
        return
    }

    fileDescriptor = fd  // Store only after success
    // ... rest of method
}
```

**Status**: [ ] Not Started

---

### 1.2 ImageCropService Thread Safety
**Files**: `CropBatch/Services/ImageCropService.swift:131-142`
**Issue ID**: S4 (Review 3)

**Problem**: `NSGraphicsContext` used on non-main threads via TaskGroup in `batchCrop()`. NSGraphicsContext is not thread-safe.

**Fix**: Replace NSGraphicsContext with pure CGContext for the `resize()` method:
```swift
static func resize(_ image: NSImage, to targetSize: CGSize) throws -> NSImage {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        throw ImageCropError.failedToGetCGImage
    }

    let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: Int(targetSize.width),
        height: Int(targetSize.height),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw ImageCropError.failedToCreateContext
    }

    context.interpolationQuality = .high
    context.draw(cgImage, in: CGRect(origin: .zero, size: targetSize))

    guard let resizedCGImage = context.makeImage() else {
        throw ImageCropError.failedToResize
    }

    return NSImage(cgImage: resizedCGImage, size: targetSize)
}
```

**Status**: [ ] Not Started

---

### 1.3 Confirmation Dialog State Race
**Files**: `CropBatch/Views/ActionButtonsView.swift:180-201`
**Issue ID**: V4 (Review 3)

**Problem**: Dialog closes → `onChange` clears `pendingExportImages` → button handler Task starts with empty array → export silently fails.

**Fix**: Clear state AFTER export completes, not on dialog dismiss:
```swift
// REMOVE this onChange:
// .onChange(of: showOverwriteDialog) { _, isShowing in
//     if !isShowing { pendingExportImages = [] }  // TOO EARLY!
// }

// INSTEAD, clear in executeExport:
private func executeExport(...) async {
    defer {
        await MainActor.run {
            pendingExportImages = []
            pendingExportDirectory = nil
        }
    }
    // ... export logic ...
}
```

**Status**: [ ] Not Started

---

### 1.4 Export Race Condition
**Files**: `CropBatch/Models/AppState.swift:419-443`
**Issue ID**: M2 (Review 3)

**Problem**: Multiple `@MainActor` async export methods can run concurrently, causing data races on `isProcessing`, `processingProgress`, and `blurRegions`.

**Fix**: Add task tracking and cancellation:
```swift
private var currentExportTask: Task<[URL], Error>?

@MainActor
func processAndExport(...) async throws -> [URL] {
    // Cancel any existing export
    currentExportTask?.cancel()

    // Capture settings at start to prevent mid-export changes
    let capturedCropSettings = cropSettings
    let capturedTransform = imageTransform
    let capturedBlurRegions = blurRegions

    let task = Task<[URL], Error> {
        defer {
            Task { @MainActor in self.isProcessing = false }
        }
        try Task.checkCancellation()
        // ... use captured settings ...
    }

    currentExportTask = task
    return try await task.value
}
```

**Status**: [ ] Not Started

---

### 1.5 State Mutation During View Update
**Files**: `CropBatch/Views/CropEditorView.swift:233-245`
**Issue ID**: V3 (Review 3)

**Problem**: Computed property `highQualityScaledImage` spawns Task that mutates `@State` during view body evaluation. Can cause infinite update loops.

**Fix**: Move cache updates to `onChange` modifiers instead of computed property:
```swift
@State private var cacheUpdateTask: Task<Void, Never>?

var body: some View {
    // ... view content ...
    .onChange(of: scaledImageSize) { _, newSize in
        updateImageCache(targetSize: newSize)
    }
    .onDisappear {
        cacheUpdateTask?.cancel()
    }
}

private func updateImageCache(targetSize: CGSize) {
    cacheUpdateTask?.cancel()
    cacheUpdateTask = Task { @MainActor in
        guard !Task.isCancelled else { return }
        // ... cache update logic ...
    }
}
```

**Status**: [ ] Not Started

---

## Phase 2: Data Integrity (High Priority)

These issues cause silent data loss or incorrect processing results.

### 2.1 ImageManager.showImportPanel() - Settings Lost
**Files**: `CropBatch/Models/ImageManager.swift:126-146`
**Issue IDs**: M1 (Review 3), also in Review 2

**Problem**: `inout` parameters are copied to local variables. The async panel callback modifies local copies, but changes never propagate back. Auto-detected export format is silently lost.

**Fix**: Remove inout pattern, use callback:
```swift
// ImageManager.swift
@MainActor
func showImportPanel(completion: @escaping (ExportFormat?) -> Void) {
    let panel = NSOpenPanel()
    // ... panel setup ...

    panel.begin { [weak self] response in
        guard response == .OK else {
            completion(nil)
            return
        }
        Task { @MainActor in
            guard let self else { return }
            let result = self.addImages(from: panel.urls)
            completion(result.detectedFormat)
        }
    }
}

// AppState.swift
@MainActor
func showImportPanel() {
    imageManager.showImportPanel { [weak self] detectedFormat in
        if let format = detectedFormat {
            self?.exportSettings.format = format
            self?.selectedPresetID = nil
        }
    }
}
```

**Status**: [x] Completed - Changed to callback pattern

---

### 2.2 Blur Regions Not Transformed in Rename-on-Conflict Path
**Files**: `CropBatch/Models/AppState.swift:493`
**Issue**: Review 2 (High severity)

**Problem**: The batch export path applies transforms to blur regions, but the per-image rename-on-conflict path does not. Blurred areas drift when transforms are active.

**Fix**: Reuse the same pipeline or apply transform:
```swift
// In the rename-on-conflict path:
let transformedBlurRegions = blurRegions.map { region in
    var transformed = region
    transformed.normalizedRect = region.normalizedRect.applyingTransform(transform)
    return transformed
}
// Use transformedBlurRegions in applyBlurRegions()
```

**Status**: [x] Completed - Applied transform to blur regions in rename-on-conflict path

---

### 2.3 Crop Math Y-Flip Issue
**Files**: `CropBatch/Services/ImageCropService.swift:555`
**Issue**: Review 2 (Medium severity)

**Problem**: Crop math documented as top-left based but sent directly to `CGImage.cropping` without flipping Y. CGImage uses bottom-left origin.

**Fix**: Convert top-left crop to CGImage coordinates:
```swift
// Option A: Direct conversion
let cropY = originalHeight - settings.cropTop - cropHeight

// Option B: Use normalized geometry helpers
let cropRect = NormalizedRect.cropArea(...).toCGImageRect(imageSize: imagePixelSize)
```

**Status**: [x] Completed - Changed y to cropBottom for correct CGImage coords

---

### 2.4 Blur Region Pixel Size Mismatch
**Files**: `CropBatch/Services/ImageCropService.swift:287`
**Issue**: Review 2 (Medium severity)

**Problem**: Blur region rendering uses `NSImage.size` (which can be scaled for Retina) instead of actual pixel dimensions. Blur placement offset on Retina displays.

**Fix**: Base dimensions on CGImage pixel size:
```swift
static func applyBlurRegions(_ image: NSImage, regions: [BlurRegion]) -> NSImage {
    guard let cgImage = image.cgImage(...) else { return image }

    // Use pixel dimensions, not NSImage.size
    let imageWidth = cgImage.width
    let imageHeight = cgImage.height
    let imageSize = CGSize(width: imageWidth, height: imageHeight)

    // Create context with pixel dimensions
    guard let context = CGContext(
        data: nil,
        width: imageWidth,
        height: imageHeight,
        // ...
    ) else { return image }

    // ... rest of blur logic ...
}
```

**Status**: [x] Completed - Now uses CGImage pixel dimensions

---

### 2.5 Export Conflict Check Ignores Rename Pattern
**Files**: `CropBatch/Services/ExportCoordinator.swift:91`
**Issue**: Review 2 (Medium severity)

**Problem**: Existing-file conflict checks always use index 0, ignoring rename pattern indexing. Batch exports with patterns undercount conflicts.

**Fix**: Use `ExportSettings.findExistingFiles(items:)` with proper settings:
```swift
var settings = exportSettings
settings.outputDirectory = .custom(outputDirectory)
let existingFiles = settings.findExistingFiles(items: images)
// Use existingFiles.count for conflict dialog
```

**Status**: [x] Completed - Now uses findExistingFiles with proper indexing

---

## Phase 3: Memory & Resource Management (Medium Priority)

These issues cause gradual degradation over time.

### 3.1 BlurManager.clearRegions() Memory Leak
**Files**: `CropBatch/Models/BlurManager.swift:48-52`
**Issue ID**: M3 (Review 3)

**Problem**: Creates empty `ImageBlurData` entry instead of removing the key.

**Fix**:
```swift
func clearRegions(for imageID: UUID) {
    regions.removeValue(forKey: imageID)  // NOT: regions[imageID] = ImageBlurData()
    selectedRegionID = nil
}
```

**Status**: [x] Completed

---

### 3.2 ThumbnailCache Memory Leak
**Files**: `CropBatch/Services/ThumbnailCache.swift:49`
**Issue ID**: S1 (Review 3)

**Problem**: `inFlight[key] = nil` doesn't actually remove the key from dictionary.

**Fix**:
```swift
inFlight.removeValue(forKey: key)  // NOT: inFlight[key] = nil
```

**Status**: [x] Completed

---

### 3.3 NSCursor Stack Imbalance
**Files**: Multiple views (ContentView, ExportSettingsView, CropEditorView, CropSettingsView)
**Issue ID**: V1 (Review 3)

**Problem**: `NSCursor.push()`/`pop()` calls become unbalanced if view disappears mid-hover.

**Fix**: Create reusable modifier with cleanup:
```swift
struct DraggableCursorModifier: ViewModifier {
    @State private var cursorPushed = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                updateCursor(shouldShow: hovering)
            }
            .onDisappear {
                if cursorPushed {
                    NSCursor.pop()
                    cursorPushed = false
                }
            }
    }
}
```

**Status**: [x] Completed - Created SafeCursorModifier with proper state tracking and cleanup

---

### 3.4 CropEditorView Task Cancellation
**Files**: `CropBatch/Views/CropEditorView.swift:275-280`
**Issue ID**: V2 (Review 3)

**Problem**: Cache update Tasks pile up without cancellation on rapid image switching.

**Fix**: Store and cancel previous task (combined with 1.5 fix):
```swift
@State private var cacheUpdateTask: Task<Void, Never>?

func updateImageCache() {
    cacheUpdateTask?.cancel()
    cacheUpdateTask = Task { ... }
}
```

**Status**: [x] Completed - Already implemented in previous Phase 1 work

---

### 3.5 CIContext Created Per Image
**Files**: `CropBatch/Services/ImageCropService.swift:289`
**Issue ID**: S7 (Review 3)

**Problem**: New CIContext created for every image with blur (expensive).

**Fix**: Use shared instance:
```swift
private let sharedCIContext: CIContext = {
    CIContext(options: [
        .useSoftwareRenderer: false,
        .highQualityDownsample: true
    ])
}()
```

**Status**: [x] Completed

---

## Phase 4: Code Quality & Maintainability (Lower Priority)

Technical debt that impacts long-term maintainability.

### 4.1 CropEditorView Refactoring
**Files**: `CropBatch/Views/CropEditorView.swift` (900+ lines)
**Issue**: Review 1

**Problem**: File contains multiple substantial inner types that should be separate files.

**Plan**:
1. Create `Views/EditorComponents/` directory
2. Extract `CropOverlayView` (~45 lines)
3. Extract `CropDimensionsOverlay` (~90 lines)
4. Extract `CropHandlesView` + helpers (~250 lines)
5. Extract `WatermarkPreviewOverlay` (~155 lines)
6. Extract `SnapGuidesView` (~60 lines)
7. Extract `AspectRatioGuideView` (~45 lines)

**Status**: [x] Completed - All components extracted to EditorComponents/

---

### 4.2 Export Profiles Missing Watermark Settings
**Files**: `CropBatch/Models/ExportSettings.swift:340`
**Issue**: Review 2 (Low severity)

**Problem**: Export profiles don't persist watermark settings.

**Fix**: Extend `ExportSettingsCodable` to include `watermarkSettings`.

**Status**: [x] Completed - watermarkSettings already added as optional field (line 348)

---

### 4.3 Transform API Clarity
**Files**: `CropBatch/Models/AppState.swift:335-361`
**Issue ID**: M4 (Review 3)

**Problem**: `transformForImage(_ imageID: UUID)` ignores the `imageID` parameter entirely.

**Fix**: Rename to `globalTransform` and deprecate the misleading method.

**Status**: [x] Completed - Added `globalTransform` property and deprecated `transformForImage`

---

### 4.4 Folder Watcher Overwrite Protection
**Files**: `CropBatch/Services/FolderWatcher.swift:125`
**Issue**: Review 2 (Low severity)

**Problem**: Folder watcher exports don't guard against overwriting originals.

**Fix**: Add overwrite checks using `exportSettings.wouldOverwriteOriginal`.

**Status**: [x] Completed - Safety check added at line 137 with numeric suffix fallback

---

### 4.5 Accessibility Labels
**Files**: Multiple interactive views
**Issue ID**: V7 (Review 3)

**Problem**: Custom controls lack accessibility labels.

**Fix**: Add `accessibilityLabel`, `accessibilityValue`, `accessibilityHint` to all custom controls.

**Status**: [x] Completed - Added to CropEdgeField.dragHandle and DraggableNumberField; existing coverage for EdgeHandle, CornerHandle, BlurRegionOverlay, CropDimensionsOverlay, WatermarkPreviewOverlay

---

### 4.6 CLI Silent Error
**Files**: `CropBatch/Services/CLIHandler.swift:209-210`
**Issue ID**: S8 (Review 3)

**Problem**: `try?` silently ignores directory creation failure.

**Fix**: Handle error explicitly with proper error message.

**Status**: [x] Completed - Error handling with message and exit code at lines 209-214

---

### 4.7 BlurManager.updateRegion() Fragility
**Files**: `CropBatch/Models/BlurManager.swift:79-93`
**Issue ID**: M5 (Review 3)

**Problem**: Copy-mutate-writeback pattern is fragile for maintenance.

**Fix**: Use direct subscript mutation pattern.

**Status**: [x] Completed - Uses direct array mutation via subscript (line 79 comment)

---

## Open Questions (From Reviews)

1. **Should rotation/flip be fully supported in UI?** The blur-transform mismatch (2.2) is currently masked if transforms are disabled.

2. **Are export profiles intended to persist watermark settings?** Or is exclusion intentional?

3. **Per-image transforms?** The API suggests per-image support but implementation is global.

---

## Testing Strategy

The reviews noted no automated tests exist. After fixes are applied:

1. **Unit Tests Needed**:
   - `ImageCropService` coordinate math
   - `ImageCropService` aspect ratio calculations
   - `NormalizedRect` transformations
   - Export filename collision handling

2. **Integration Tests Needed**:
   - Batch export path
   - Rename-on-conflict path
   - Folder watcher path
   - CLI path

3. **Manual Test Scenarios**:
   - Rapid image switching during crop
   - Multiple overlapping exports
   - View disappear during hover/drag
   - Retina display blur placement

---

## Progress Tracking

| Phase | Started | Completed | Verified |
|-------|---------|-----------|----------|
| Phase 1 | [x] | [x] | [x] |
| Phase 2 | [x] | [x] | [ ] |
| Phase 3 | [x] | [x] | [ ] |
| Phase 4 | [x] | [x] | [ ] |

---

*Plan generated from code reviews dated 2026-01-04*
