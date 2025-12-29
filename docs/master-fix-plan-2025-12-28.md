# CropBatch Master Fix Plan

**Generated:** 2025-12-28T23:15:00Z
**Source:** Consolidated from Claude and Codex fix plans
**Reviews Referenced:** 3 code review reports from 2025-12-28

---

## Comparison Summary

| Aspect | Claude Plan | Codex Plan |
|--------|-------------|------------|
| Structure | 5 Tiers (parallel groups) | 8 Sequential Steps |
| Total Issues | 18 | 8 high-level areas |
| Detail Level | Extensive code examples | High-level descriptions |
| First Priority | CGContext migration | Coordinate normalization |
| Apple Docs | Referenced | Explicitly cited (Quartz 2D, Sosumi, swift-argument-parser) |

### Key Ordering Difference

**Claude's approach:** Fix deprecated APIs first → then coordinates → then concurrency
**Codex's approach:** Fix coordinates first → then validation → then concurrency → then deprecated APIs

**Rationale for merge:** Codex's ordering is more pragmatic—fixing coordinate math first ensures all subsequent work operates on correct geometry. Claude's detailed code examples provide the implementation guidance.

---

## Dependency Graph (Merged)

```
PHASE 1 - Geometry Foundation
=============================
[1.1] Coordinate System ──> [1.2] Input Validation ──> [1.3] Pipeline Unification
      (Codex Step 1)            (Codex Step 2)            (Codex Step 3)

PHASE 2 - Export Correctness
============================
[2.1] Filename Collisions ──> [2.2] Format-Only Export Fix
      (Claude 3.1)                 (Claude 3.2)

PHASE 3 - Performance
=====================
[3.1] @MainActor Removal ──> [3.2] TaskGroup Parallel ──> [3.3] CGContext Migration
      (Claude 1.3)               (Claude 2.1)                (Claude 1.1)
            │
            └──> [3.4] Image Caching ──> [3.5] Thumbnail Caching
                      (Claude 2.2)            (Claude 2.3)

PHASE 4 - UI Polish
===================
[4.1] Batch Preview Fixes (Claude 2.4)
[4.2] Buffer Cache (Claude 3.4)
[4.3] Remove DispatchQueue.main.async (Claude 5.5)

PHASE 5 - Architecture
======================
[5.1] Decompose AppState (Claude 4.1)
[5.2] Extract CropEditorView components (Claude 4.2)

PHASE 6 - Quality
=================
[6.1] OSLog migration (Claude 5.1)
[6.2] Unit tests (Claude 5.2)
[6.3] Protocol injection (Claude 5.3)
[6.4] swift-argument-parser CLI (Claude 5.4)
```

---

## PHASE 1: Geometry Foundation

> **Priority:** CRITICAL — All other fixes depend on correct geometry

### 1.1 Normalize Vertical Coordinate Handling

**Files:** `ImageCropService.swift:332-338`, `UIDetector.swift:77-109`
**Issue:** CoreGraphics uses bottom-left origin; code assumes top-left
**Source:** Codex Step 1, Claude 1.2

**Implementation:**

```swift
// ImageCropService.swift - BEFORE (wrong):
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
- For `.top` edge: sample from row `height - 1`
- For `.bottom` edge: sample from row `0`

---

### 1.2 Validate & Clamp User Crop Input

**File:** `CropSettingsView.swift:11-38`, `AppState.swift`
**Issue:** Invalid crop values can exceed image dimensions
**Source:** Codex Step 2, Claude 3.3

```swift
// Add to AppState
func validateAndClampCrop() {
    guard let image = activeImage else { return }
    let maxWidth = Int(image.originalImage.size.width)
    let maxHeight = Int(image.originalImage.size.height)

    cropSettings.cropLeft = min(max(0, cropSettings.cropLeft), maxWidth - cropSettings.cropRight - 1)
    cropSettings.cropRight = min(max(0, cropSettings.cropRight), maxWidth - cropSettings.cropLeft - 1)
    cropSettings.cropTop = min(max(0, cropSettings.cropTop), maxHeight - cropSettings.cropBottom - 1)
    cropSettings.cropBottom = min(max(0, cropSettings.cropBottom), maxHeight - cropSettings.cropTop - 1)
}

// Wire up in CropSettingsView
.onChange(of: cropSettings.cropLeft) { _, _ in
    appState.validateAndClampCrop()
}
```

---

### 1.3 Unify Preview & Export Pipelines

**File:** `BatchReviewView.swift:150-175`
**Issue:** Preview only applies crop, ignores transforms/blur/resize
**Source:** Codex Step 3, Claude 2.4

```swift
func generatePreview(for item: ImageItem) async -> NSImage {
    var result = item.originalImage

    // 1. Apply transforms (rotation, flip)
    if let transform = appState.imageTransforms[item.id] {
        result = ImageCropService.rotate(result, degrees: transform.rotation)
        if transform.flipHorizontal {
            result = ImageCropService.flip(result, horizontal: true)
        }
        if transform.flipVertical {
            result = ImageCropService.flip(result, horizontal: false)
        }
    }

    // 2. Apply blur regions
    if let regions = appState.blurRegions[item.id], !regions.isEmpty {
        result = ImageCropService.applyBlurRegions(result, regions: regions)
    }

    // 3. Apply crop
    result = try ImageCropService.crop(result, with: appState.cropSettings)

    // 4. Apply resize if enabled
    if appState.exportSettings.resizeEnabled {
        result = ImageCropService.resize(result, to: targetSize)
    }

    return result
}
```

---

## PHASE 2: Export Correctness

> **Priority:** HIGH — Prevents data loss and user confusion

### 2.1 Add Filename Collision Detection

**Files:** `ExportSettings.swift:144-190`, `ImageCropService.swift:445-492`
**Source:** Codex Step 4, Claude 3.1

```swift
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

### 2.2 Fix Export Button for Format Conversions

**File:** `AppState.swift:471-479`
**Source:** Codex Step 4, Claude 3.2

```swift
var canExport: Bool {
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

## PHASE 3: Performance

> **Priority:** HIGH — Significant UX impact

### 3.1 Remove @MainActor from batchCrop

**File:** `ImageCropService.swift:424-495`
**Source:** Codex Step 5, Claude 1.3

```swift
// BEFORE:
@MainActor
static func batchCrop(...) async throws -> [URL] { ... }

// AFTER:
static func batchCrop(...) async throws -> [URL] {
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

### 3.2 Implement TaskGroup for Parallel Batch Processing

**File:** `ImageCropService.swift:441`
**Source:** Codex Step 5, Claude 2.1

```swift
try await withThrowingTaskGroup(of: (Int, URL).self) { group in
    for (index, item) in items.enumerated() {
        group.addTask {
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

    return results.sorted { $0.0 < $1.0 }.map { $0.1 }
}
```

---

### 3.3 Replace lockFocus with CGContext

**File:** `ImageCropService.swift:86-98, 107-134, 142-166, 196-259`
**Issue:** `NSImage.lockFocus()`/`unlockFocus()` deprecated in macOS 14
**Source:** Codex Step 6, Claude 1.1

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

**Methods to update:**
- [ ] `resize()` - line 86-98
- [ ] `rotate()` - line 107-134
- [ ] `flip()` - line 142-166
- [ ] `applyBlurRegions()` - line 196-259

---

### 3.4 Cache highQualityScaledImage in CropEditorView

**File:** `CropEditorView.swift:196`
**Source:** Codex Step 7, Claude 2.2

```swift
@State private var cachedScaledImage: NSImage?
@State private var cachedImageID: UUID?
@State private var cachedTargetSize: CGSize?

private var highQualityScaledImage: NSImage {
    let targetSize = scaledImageSize
    let currentID = appState.activeImage?.id

    if let cached = cachedScaledImage,
       cachedImageID == currentID,
       cachedTargetSize == targetSize {
        return cached
    }

    let newImage = generateScaledImage(targetSize)
    return newImage
}

.onChange(of: scaledImageSize) { _, _ in cachedScaledImage = nil }
.onChange(of: appState.activeImage?.id) { _, _ in cachedScaledImage = nil }
```

---

### 3.5 Implement Thumbnail Caching with NSCache

**File:** New `ThumbnailCache.swift`
**Source:** Claude 2.3

```swift
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSURL, NSImage>()

    init() {
        cache.countLimit = 100
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB
    }

    func thumbnail(for url: URL, size: CGSize) async -> NSImage? {
        let key = url as NSURL
        if let cached = cache.object(forKey: key) { return cached }

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

## PHASE 4: UI Polish

> **Priority:** MEDIUM

### 4.1 Fix Batch Review Previews
See Phase 1.3 implementation.

### 4.2 Cache Buffer Items in ThumbnailStripView

**File:** `ThumbnailStripView.swift`
**Source:** Claude 3.4

```swift
@State private var cachedLeadingBuffer: [ImageItem] = []
@State private var cachedTrailingBuffer: [ImageItem] = []

.onChange(of: images) { _, newImages in
    updateBufferCache(images: newImages)
}
```

### 4.3 Remove DispatchQueue.main.async

**File:** `CropEditorView.swift:307`
**Source:** Claude 5.5

```swift
// BEFORE:
private func updateViewSize(_ size: CGSize) {
    DispatchQueue.main.async {
        if viewSize != size { viewSize = size }
    }
}

// AFTER:
private func updateViewSize(_ size: CGSize) {
    if viewSize != size { viewSize = size }
}
```

---

## PHASE 5: Architecture

> **Priority:** LOW — Maintainability

### 5.1 Decompose AppState

**Current:** ~450 lines
**Target:** 4 focused classes
**Source:** Codex Step 8, Claude 4.1

```
AppState.swift
    ├── ImageStore.swift (~100 lines)
    ├── CropState.swift (~150 lines)
    ├── ExportState.swift (~100 lines)
    └── UIState.swift (~100 lines)
```

### 5.2 Extract CropEditorView Components

**Current:** 917 lines
**Target:** ~300 lines + components
**Source:** Claude 4.2

```
CropEditorView.swift
    ├── CropOverlayView.swift
    ├── CropHandlesView.swift
    ├── AspectRatioGuideView.swift
    └── CropHandleComponents.swift
```

---

## PHASE 6: Quality

> **Priority:** OPTIONAL

### 6.1 Replace print() with OSLog

**Files:** `CropBatchApp.swift:290`, `ExportSettings.swift:340`, `PresetManager.swift:84`

```swift
import os
private let logger = Logger(subsystem: "com.app.CropBatch", category: "Export")
logger.error("Export failed: \(error.localizedDescription)")
```

### 6.2 Add Unit Tests

- [ ] `ImageCropService` - crop, resize, rotate, flip
- [ ] `FileSizeEstimator` - estimation accuracy
- [ ] `CropSettings` - linked edge calculations
- [ ] `RenameSettings` - pattern substitution

### 6.3 Convert Singletons to Protocols

**Files:** `PresetManager.swift`, `FolderWatcher.swift`, `ExportProfileManager.swift`

### 6.4 Adopt swift-argument-parser for CLI

**File:** `CLIHandler.swift`
**Source:** Codex Step 8

```swift
import ArgumentParser

struct CropBatchCLI: ParsableCommand {
    @Argument(help: "Input image files")
    var inputs: [String]

    @Option(name: .shortAndLong, help: "Output directory")
    var output: String?

    @Option(name: .long, help: "Pixels to crop from top")
    var cropTop: Int = 0
}
```

---

## QA Verification Checklist

Run after each phase:

1. **Unit Tests:** Geometry math, validation, pipeline parity
2. **UI Snapshots:** Overlay/preview/export comparisons
3. **Performance:** Timeline traces for batch exports; no main-thread stalls
4. **Regression Matrix:** Rotations, blurs, format changes, rename patterns

---

## Summary Statistics

| Phase | Issues | Priority | Complexity |
|-------|--------|----------|------------|
| 1 - Geometry | 3 | CRITICAL | Medium |
| 2 - Export | 2 | HIGH | Low |
| 3 - Performance | 5 | HIGH | High |
| 4 - UI Polish | 3 | MEDIUM | Low |
| 5 - Architecture | 2 | LOW | High |
| 6 - Quality | 4 | OPTIONAL | Medium |
| **Total** | **19** | | |

---

## Source Documents

- `docs/fix-plan-2025-12-28-claude.md` — Detailed tier-based plan with code examples
- `docs/fix-plan-2025-12-28-codex.md` — Sequential dependency-ordered steps with Apple doc references
- `docs/code-review-2025-12-28-214330Z.md` — 7 critical/major issues
- `docs/code-review-report-2025-12-28.md` — 4 main issues
- `docs/code-review-2025-12-28-224520.md` — 14 detailed issues

**Apple References:** Quartz 2D Programming Guide, Swift Concurrency, swift-argument-parser
