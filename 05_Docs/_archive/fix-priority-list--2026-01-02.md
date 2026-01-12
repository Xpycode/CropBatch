# CropBatch Fix Priority List

**Created:** 2026-01-02
**Source:** Code review session (see `code-review--2026-01-02--00-45--.md`)
**Status:** ✅ ALL ITEMS COMPLETED (2026-01-03)

---

## Summary of Completed Fixes

| Priority | Issue | Status | Commit/Details |
|----------|-------|--------|----------------|
| P0 | ThumbnailCache Race Condition | ✅ Done | Converted to actor with in-flight tracking |
| P1 | FolderWatcher Thread Safety | ✅ Done | Uses `Task { @MainActor in ... }` |
| P1 | Refactor AppState | ✅ Done | Split into ImageManager, CropManager, BlurManager, SnapPointsManager |
| P1 | Duplicate Export Logic | ✅ Done | Extracted to ExportCoordinator |
| P2 | Extract Magic Numbers | ✅ Done | Created Config.swift |
| P2 | PresetManager Error Handling | ✅ Done | Added lastError property |
| P2 | Memory Usage Warning | ✅ Done | Added memoryWarningLevel to ImageManager |
| P3 | Accessibility Labels | ✅ Done | Added to EdgeHandle, BlurRegionOverlay, WatermarkPreviewOverlay |
| P3 | Standardize Error Propagation | ✅ Done | All ImageCropService methods now throw |
| P3 | TODO Markers | ✅ Done | Added SHELVED markers throughout |

---

## Architecture After Refactoring

```
AppState (Facade - ~550 lines)
├── imageManager: ImageManager      - Image collection & selection
├── cropManager: CropManager        - Crop settings & undo/redo
├── blurManager: BlurManager        - Blur regions & transforms
└── snapManager: SnapPointsManager  - Snap point detection

Services/
├── ThumbnailCache (actor)          - Thread-safe thumbnail caching
├── ExportCoordinator               - Export flow coordination
├── PresetManager                   - Preset persistence with error reporting
└── FolderWatcher                   - File system monitoring (MainActor-safe)
```

---

## P0 - Critical ✅ COMPLETED

### 1. ThumbnailCache Race Condition
**File:** `CropBatch/Services/ThumbnailCache.swift`
**Status:** ✅ Fixed

Converted to actor with in-flight task tracking:
```swift
actor ThumbnailCache {
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    func thumbnail(for url: URL, size: CGSize) async -> NSImage? {
        if let existingTask = inFlight[key] {
            return await existingTask.value  // Coalesce concurrent requests
        }
        // ...
    }
}
```

---

## P1 - High ✅ COMPLETED

### 2. FolderWatcher Thread Safety
**File:** `CropBatch/Services/FolderWatcher.swift:49`
**Status:** ✅ Fixed

Event handlers now explicitly dispatch to MainActor:
```swift
source.setEventHandler { [weak self] in
    Task { @MainActor in
        self?.checkForNewFiles()
    }
}
```

### 3. Refactor AppState
**Files:** `CropBatch/Models/`
**Status:** ✅ Fixed

Split into focused managers:
- `ImageManager.swift` - Image collection, selection, memory warnings
- `CropManager.swift` - Crop settings, undo/redo, presets
- `BlurManager.swift` - Blur regions, transforms
- `SnapPointsManager.swift` - Snap point detection and caching

AppState now acts as a facade with backward-compatible properties.

### 4. Duplicate Export Logic
**File:** `CropBatch/Services/ExportCoordinator.swift`
**Status:** ✅ Fixed

Extracted to ExportCoordinator with View extension for sheets/alerts.

---

## P2 - Medium ✅ COMPLETED

### 5. Extract Magic Numbers
**File:** `CropBatch/Config.swift`
**Status:** ✅ Fixed

```swift
enum Config {
    enum History { static let maxUndoSteps = 50 }
    enum Blur { static let minimumRegionSize = 0.02 }
    enum Cache {
        static let thumbnailCountLimit = 100
        static let thumbnailSizeLimit = 50 * 1024 * 1024
    }
    enum Snap { static let defaultThreshold = 15 }
    enum Presets { static let recentLimit = 5 }
    enum Memory {
        static let imageCountWarningThreshold = 50
        static let imageCountCriticalThreshold = 100
    }
}
```

### 6. Silent Error Handling in PresetManager
**File:** `CropBatch/Services/PresetManager.swift`
**Status:** ✅ Fixed

Added `lastError` property and `clearError()` method.

### 7. Memory Usage Warning
**File:** `CropBatch/Models/ImageManager.swift`
**Status:** ✅ Fixed

```swift
enum MemoryWarningLevel { case none, warning, critical }

var memoryWarningLevel: MemoryWarningLevel {
    if images.count >= Config.Memory.imageCountCriticalThreshold { return .critical }
    else if images.count >= Config.Memory.imageCountWarningThreshold { return .warning }
    return .none
}
```

---

## P3 - Low ✅ COMPLETED

### 8. Accessibility Labels
**Files:** `CropEditorView.swift`, `BlurEditorView.swift`
**Status:** ✅ Fixed

Added to EdgeHandle, corner handles, BlurRegionOverlay, WatermarkPreviewOverlay.

### 9. Standardize Error Propagation
**File:** `CropBatch/Services/ImageCropService.swift`
**Status:** ✅ Fixed

All methods now throw: `resize()`, `rotate()`, `applyTransform()`.

### 10. TODO Markers for Shelved Features
**Files:** `ContentView.swift`, `CropBatchApp.swift`
**Status:** ✅ Fixed

Added `// TODO: [SHELVED]` markers for blur tool and rotation menu.

---

## Shelved Features (Separate Track)

### Blur Tool
**Issue:** Transform coordinate mismatch when images are rotated/flipped
**Documentation:** `docs/blur-feature-status.md`
**To Re-enable:** Remove `.filter { $0 != .blur }` in `ContentView.swift:~241`

### Rotation/Flip Menu
**Issue:** Breaks crop state
**Location:** `CropBatchApp.swift:131-162` (wrapped in `#if false`)

---

## Verification

Build tested successfully:
```bash
xcodebuild -scheme CropBatch -configuration Debug build
# ** BUILD SUCCEEDED **
```
