# CropBatch Code Review Fixes - Dependency-Ordered Implementation Plan

**Date:** 2025-12-28
**Source:** Consolidated from 3 code review reports
**Ordering:** Most dependent issues FIRST, least dependent LAST

---

## Dependency Graph

```
TIER 1 (Foundation) ─────────────────────────────────────────────────────────
    │
    ├── 1.1 CGContext Migration ──┬──> 1.2 Coordinate Fixes ──> 1.3 MainActor Removal
    │                             │
    └─────────────────────────────┘
                                  │
TIER 2 (Performance) ─────────────┼───────────────────────────────────────────
                                  │
    ┌─────────────────────────────┴─────────────────────────────┐
    │                             │                             │
    v                             v                             v
2.1 TaskGroup              2.2 Image Cache              2.3 Thumbnail Cache
    (depends 1.3)          (depends 1.1)                (depends 1.1)
    │                             │                             │
    └─────────────────────────────┴─────────────────────────────┘
                                  │
                                  v
                          2.4 Batch Preview Fixes
                          (depends 1.1, 1.2)

TIER 3 (Features) ────────────────────────────────────────────────────────────
    │
    ├── 3.1 Filename Collisions (depends Tier 1)
    ├── 3.2 Export Button Fix (depends core export)
    ├── 3.3 Crop Validation (depends 1.2)
    └── 3.4 Buffer Cache (independent)

TIER 4 (Refactoring) ─────────────────────────────────────────────────────────
    │
    ├── 4.1 Decompose AppState
    └── 4.2 Extract CropEditorView components

TIER 5 (Quality) ─────────────────────────────────────────────────────────────
    │
    ├── 5.1 OSLog migration
    ├── 5.2 Unit tests
    ├── 5.3 Protocol injection
    ├── 5.4 CLI argument parser
    └── 5.5 Remove DispatchQueue.main.async
```

---

## TIER 1: Foundation Layer

> **Priority:** CRITICAL - All other fixes depend on these

### 1.1 Replace lockFocus with CGContext

**File:** `CropBatch/Services/ImageCropService.swift`
**Lines:** 86-98, 107-134, 142-166, 196-259
**Issue:** `NSImage.lockFocus()`/`unlockFocus()` deprecated in macOS 14

**Why First:** All image operations (resize, rotate, flip, blur) use this API. Must migrate before any other image-related fixes.

**Implementation Pattern:**
```swift
static func resize(_ image: NSImage, to targetSize: CGSize) -> NSImage {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return image
    }

    let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: Int(targetSize.width),
        height: Int(targetSize.height),
        bitsPerComponent: cgImage.bitsPerComponent,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: cgImage.bitmapInfo.rawValue
    ) else { return image }

    context.interpolationQuality = .high
    context.draw(cgImage, in: CGRect(origin: .zero, size: targetSize))

    guard let resizedCGImage = context.makeImage() else { return image }
    return NSImage(cgImage: resizedCGImage, size: targetSize)
}
```

**Affected Methods:**
- [ ] `resize()` - line 86-98
- [ ] `rotate()` - line 107-134
- [ ] `flip()` - line 142-166
- [ ] `applyBlurRegions()` - line 196-259

---

### 1.2 Fix Coordinate System Bugs

**Issue:** CoreGraphics uses bottom-left origin; code assumes top-left

**Files and Fixes:**

| File | Lines | Problem | Fix |
|------|-------|---------|-----|
| `ImageCropService.swift` | 332-338 | Crop Y uses `cropTop` | Set Y to `cropBottom` |
| `UIDetector.swift` | 77-109 | Edge detection inverted | Sample row `height-1` for top |

**ImageCropService.swift Fix:**
```swift
// BEFORE (wrong):
let cropRect = CGRect(
    x: settings.cropLeft,
    y: settings.cropTop,  // <-- Incorrect for CG coordinates
    ...
)

// AFTER (correct):
let cropRect = CGRect(
    x: settings.cropLeft,
    y: settings.cropBottom,  // <-- Distance from bottom edge
    width: originalWidth - settings.cropLeft - settings.cropRight,
    height: originalHeight - settings.cropTop - settings.cropBottom
)
```

**UIDetector.swift Fix:**
- Flip context when drawing, OR
- For `.top` edge: sample from row `height - 1`
- For `.bottom` edge: sample from row `0`

---

### 1.3 Remove @MainActor from batchCrop

**File:** `CropBatch/Services/ImageCropService.swift`
**Lines:** 424-495
**Issue:** Heavy image processing on UI thread causes freezing

**Implementation:**
```swift
// BEFORE:
@MainActor
static func batchCrop(...) async throws -> [URL] {
    // All processing on main thread
}

// AFTER:
static func batchCrop(...) async throws -> [URL] {
    // Process on background
    for item in items {
        // ... image processing ...

        // Only marshal progress updates to main
        await MainActor.run {
            progress(Double(index) / Double(total))
        }
    }
}
```

---

## TIER 2: Performance Improvements

> **Priority:** HIGH - Significant user experience impact

### 2.1 Implement TaskGroup for Parallel Batch Processing

**Depends on:** 1.3 (MainActor removal)
**File:** `ImageCropService.swift:441`

```swift
try await withThrowingTaskGroup(of: (Int, URL).self) { group in
    for (index, item) in items.enumerated() {
        group.addTask {
            // Process single image
            let outputURL = try await processSingleImage(item, ...)
            return (index, outputURL)
        }
    }

    var results = [(Int, URL)]()
    for try await result in group {
        results.append(result)
        await MainActor.run {
            progress(Double(results.count) / Double(items.count))
        }
    }

    // Sort by original index to maintain order
    return results.sorted { $0.0 < $1.0 }.map { $0.1 }
}
```

---

### 2.2 Cache highQualityScaledImage in CropEditorView

**Depends on:** 1.1 (CGContext migration)
**File:** `CropEditorView.swift:196`

```swift
// Add state variables
@State private var cachedScaledImage: NSImage?
@State private var cachedImageID: UUID?
@State private var cachedTargetSize: CGSize?

// Computed property with caching
private var highQualityScaledImage: NSImage {
    let targetSize = scaledImageSize
    let currentID = appState.activeImage?.id

    if let cached = cachedScaledImage,
       cachedImageID == currentID,
       cachedTargetSize == targetSize {
        return cached
    }

    // Generate new scaled image...
    let newImage = generateScaledImage(targetSize)

    // Cache it (in .task or .onChange)
    return newImage
}

// Invalidation
.onChange(of: scaledImageSize) { _, newSize in
    cachedScaledImage = nil
}
.onChange(of: appState.activeImage?.id) { _, _ in
    cachedScaledImage = nil
}
```

---

### 2.3 Implement Thumbnail Caching with NSCache

**Depends on:** 1.1 (proper image scaling)
**File:** `ThumbnailStripView.swift:291`

```swift
// New file: ThumbnailCache.swift
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSURL, NSImage>()

    init() {
        cache.countLimit = 100
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB
    }

    func thumbnail(for url: URL, size: CGSize) async -> NSImage? {
        let key = url as NSURL

        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard let image = NSImage(contentsOf: url) else { return nil }
        let thumbnail = await generateThumbnail(from: image, size: size)
        cache.setObject(thumbnail, forKey: key)
        return thumbnail
    }

    func invalidate(for url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }
}
```

---

### 2.4 Fix Batch Review Previews

**Depends on:** 1.1, 1.2 (correct transforms and coordinates)
**File:** `BatchReviewView.swift:150-175`

**Issue:** Preview only applies crop, ignores transforms/blur/resize

**Fix:** Reuse full export pipeline for preview generation:
```swift
func generatePreview(for item: ImageItem) async -> NSImage {
    var result = item.originalImage

    // Apply transforms (rotation, flip)
    if let transform = appState.imageTransforms[item.id] {
        result = ImageCropService.rotate(result, degrees: transform.rotation)
        if transform.flipHorizontal {
            result = ImageCropService.flip(result, horizontal: true)
        }
        if transform.flipVertical {
            result = ImageCropService.flip(result, horizontal: false)
        }
    }

    // Apply blur regions
    if let regions = appState.blurRegions[item.id], !regions.isEmpty {
        result = ImageCropService.applyBlurRegions(result, regions: regions)
    }

    // Apply crop
    result = try ImageCropService.crop(result, with: appState.cropSettings)

    // Apply resize if enabled
    if appState.exportSettings.resizeEnabled {
        result = ImageCropService.resize(result, to: targetSize)
    }

    return result
}
```

---

## TIER 3: Feature Fixes

> **Priority:** MEDIUM - Correctness and usability

### 3.1 Add Filename Collision Detection

**Files:** `ExportSettings.swift:144-190`, `ImageCropService.swift:445-492`

```swift
// Pre-export validation
func validateDestinations(items: [ImageItem], settings: ExportSettings) throws {
    var plannedURLs = Set<URL>()

    for (index, item) in items.enumerated() {
        let destURL = settings.destinationURL(for: item, index: index)

        if plannedURLs.contains(destURL) {
            throw ImageCropError.filenameCollision(destURL.lastPathComponent)
        }
        plannedURLs.insert(destURL)
    }
}
```

---

### 3.2 Fix Export Button for Format Conversions

**File:** `AppState.swift:471-479`

```swift
var canExport: Bool {
    // Existing conditions...
    let hasCropChanges = !cropSettings.isDefault
    let hasTransforms = !imageTransforms.isEmpty
    let hasBlurRegions = !blurRegions.values.allSatisfy { $0.isEmpty }
    let hasRename = exportSettings.renameEnabled
    let hasResize = exportSettings.resizeEnabled

    // NEW: Format conversion counts as exportable change
    let hasFormatChange = !exportSettings.preserveOriginalFormat

    return hasCropChanges || hasTransforms || hasBlurRegions ||
           hasRename || hasResize || hasFormatChange
}
```

---

### 3.3 Add Crop Value Validation

**File:** `CropSettingsView.swift:11-38, 124-143`

```swift
// Add validation method to AppState
func validateAndClampCrop() {
    guard let image = activeImage else { return }
    let maxWidth = Int(image.originalImage.size.width)
    let maxHeight = Int(image.originalImage.size.height)

    cropSettings.cropLeft = min(max(0, cropSettings.cropLeft), maxWidth - cropSettings.cropRight - 1)
    cropSettings.cropRight = min(max(0, cropSettings.cropRight), maxWidth - cropSettings.cropLeft - 1)
    cropSettings.cropTop = min(max(0, cropSettings.cropTop), maxHeight - cropSettings.cropBottom - 1)
    cropSettings.cropBottom = min(max(0, cropSettings.cropBottom), maxHeight - cropSettings.cropTop - 1)
}

// Call in text field onChange
.onChange(of: cropSettings.cropLeft) { _, _ in
    appState.validateAndClampCrop()
}
```

---

### 3.4 Cache Buffer Items in ThumbnailStripView

**File:** `ThumbnailStripView.swift`

```swift
// Replace computed properties with cached state
@State private var cachedLeadingBuffer: [ImageItem] = []
@State private var cachedTrailingBuffer: [ImageItem] = []

.onChange(of: images) { _, newImages in
    updateBufferCache(images: newImages)
}

private func updateBufferCache(images: [ImageItem]) {
    // Calculate once, use many times
    cachedLeadingBuffer = calculateLeadingBuffer(images)
    cachedTrailingBuffer = calculateTrailingBuffer(images)
}
```

---

## TIER 4: Refactoring

> **Priority:** LOW - Maintainability improvements

### 4.1 Decompose AppState

**Current:** ~450 lines in single class
**Target:** 4 focused classes, ~100-150 lines each

```
AppState.swift (~450 lines)
    |
    +-- ImageStore.swift
    |   - images: [ImageItem]
    |   - selectedImageIDs: Set<UUID>
    |   - activeImageID: UUID?
    |   - add/remove/select operations
    |
    +-- CropState.swift
    |   - cropSettings: CropSettings
    |   - edgeLinkMode: EdgeLinkMode
    |   - blurRegions: [UUID: [BlurRegion]]
    |   - imageTransforms: [UUID: ImageTransform]
    |   - undo/redo history
    |
    +-- ExportState.swift
    |   - exportSettings: ExportSettings
    |   - isProcessing: Bool
    |   - processingProgress: Double
    |
    +-- UIState.swift
        - zoomMode: ZoomMode
        - currentTool: Tool
        - showBeforeAfter: Bool
```

---

### 4.2 Extract CropEditorView Components

**Current:** 917 lines
**Target:** ~300 lines main file + extracted components

```
CropEditorView.swift (917 lines)
    |
    +-- CropOverlayView.swift
    |   - Dimmed overlay regions
    |   - Crop rectangle stroke
    |
    +-- CropHandlesView.swift
    |   - Edge handles (4)
    |   - Corner handles (4)
    |   - Handle drag gestures
    |
    +-- AspectRatioGuideView.swift
    |   - Rule of thirds grid
    |   - Golden ratio overlay
    |
    +-- CropHandleComponents.swift
        - EdgeHandle struct
        - CornerHandle struct
        - PixelLabel struct
```

---

## TIER 5: Quality Improvements

> **Priority:** OPTIONAL - Best practices

### 5.1 Replace print() with OSLog

**Files:** `CropBatchApp.swift:290`, `ExportSettings.swift:340`, `PresetManager.swift:84`

```swift
import os

private let logger = Logger(subsystem: "com.app.CropBatch", category: "Export")

// Replace:
print("Error: \(error)")

// With:
logger.error("Export failed: \(error.localizedDescription)")
```

---

### 5.2 Add Unit Tests

**Testable Components:**
- [ ] `ImageCropService` - crop, resize, rotate, flip
- [ ] `FileSizeEstimator` - estimation accuracy
- [ ] `CropSettings` - linked edge calculations
- [ ] `RenameSettings` - pattern substitution

---

### 5.3 Convert Singletons to Protocols

**Files:** `PresetManager.swift`, `FolderWatcher.swift`, `ExportProfileManager.swift`

```swift
protocol PresetManaging {
    var allPresets: [CropPreset] { get }
    func savePreset(name: String, settings: CropSettings, icon: String)
    func deletePreset(_ preset: CropPreset)
}

// Inject via Environment
extension EnvironmentValues {
    @Entry var presetManager: PresetManaging = PresetManager.shared
}
```

---

### 5.4 Adopt swift-argument-parser for CLI

**File:** `CLIHandler.swift`

```swift
import ArgumentParser

struct CropBatchCLI: ParsableCommand {
    @Argument(help: "Input image files")
    var inputs: [String]

    @Option(name: .shortAndLong, help: "Output directory")
    var output: String?

    @Option(name: .long, help: "Pixels to crop from top")
    var cropTop: Int = 0

    // ... etc
}
```

---

### 5.5 Remove DispatchQueue.main.async

**File:** `CropEditorView.swift:307`

```swift
// BEFORE:
private func updateViewSize(_ size: CGSize) {
    DispatchQueue.main.async {
        if viewSize != size {
            viewSize = size
        }
    }
}

// AFTER:
private func updateViewSize(_ size: CGSize) {
    if viewSize != size {
        viewSize = size
    }
}
```

---

## Implementation Sequence

```
PHASE 1 - Foundation
====================
[1.1] ──> [1.2] ──> [1.3]
  |         |         |
  v         v         v
CGContext  Coords   MainActor

PHASE 2 - Performance
=====================
        ┌─────┴─────┐
        v           v
      [2.1]       [2.2]
     TaskGroup   ImgCache
        │           │
        │     ┌─────┘
        v     v
      [2.3] [2.4]
    ThumbCache Preview

PHASE 3 - Features (parallelizable)
===================================
[3.1] [3.2] [3.3] [3.4]
  |     |     |     |
  v     v     v     v
Collision Export Validate Buffer

PHASE 4 - Refactoring (parallelizable)
======================================
[4.1]         [4.2]
  |             |
  v             v
AppState    CropEditor
decompose    extract

PHASE 5 - Quality (any order)
=============================
[5.1] [5.2] [5.3] [5.4] [5.5]
```

---

## Summary Statistics

| Tier | Issues | Files Affected | Priority |
|------|--------|----------------|----------|
| 1 | 3 | 2 | CRITICAL |
| 2 | 4 | 4 | HIGH |
| 3 | 4 | 4 | MEDIUM |
| 4 | 2 | 2 | LOW |
| 5 | 5 | 6 | OPTIONAL |
| **Total** | **18** | **~12 unique** | |

---

## Source Code Review Reports

This plan consolidates issues from:
1. `docs/code-review-2025-12-28-214330Z.md` - 7 critical/major issues
2. `docs/code-review-report-2025-12-28.md` - 4 main issues
3. `docs/code-review-2025-12-28-224520.md` - 14 total issues (detailed report)

---

**Generated:** 2025-12-28
**Tools Used:** Claude Opus 4.5, Zen MCP (Gemini 2.5 Pro), Apple Documentation MCPs
