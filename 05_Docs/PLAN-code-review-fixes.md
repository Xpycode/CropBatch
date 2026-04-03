# Implementation Plan: Code Review Fixes

> 3 fixes from code review (2026-03-31). All are contained refactors — no new features, no behavior changes.

## Fix 1: DRY Grid URL Construction

**Problem:** Grid tile URL construction (suffix replacement + corner-radius `.png` coercion) is manually duplicated in 3 places. `ExportSettings.outputURL(for:index:gridRow:gridCol:)` exists but isn't used by the two places that save tiles.

**Duplication locations:**
| # | File | Lines | What it does |
|---|------|-------|-------------|
| 1 | `ExportSettings.swift` | 208–218 | `outputURL(for:index:gridRow:gridCol:)` — canonical method, **unused by save paths** |
| 2 | `ImageCropService.swift` | 986–1007 | Manual suffix + PNG coercion in `processSingleImage` |
| 3 | `AppState.swift` | 594–615 | Manual suffix + PNG coercion in `processAndExportWithRename` |

### Step 1A: Add `applyGridSuffix` helper to ExportSettings

File: `ExportSettings.swift`

**Why a separate helper?** The rename-conflict path in AppState uses a pre-built `renamedURL` (e.g., `photo_1.png`) as its base — it can't re-run the full `outputURL` pipeline or the suffix would double. So we need a lightweight method that just applies grid suffix + extension override to any existing URL.

```swift
/// Applies grid suffix and optional extension override to an existing URL.
/// Used by both the normal and rename-conflict export paths.
func applyGridSuffix(
    to url: URL,
    gridRow: Int? = nil,
    gridCol: Int? = nil,
    forceExtension: String? = nil
) -> URL {
    var result = url

    // Force extension override (e.g., .png for corner radius transparency)
    if let ext = forceExtension {
        let baseName = result.deletingPathExtension().lastPathComponent
        result = result.deletingLastPathComponent()
            .appendingPathComponent(baseName)
            .appendingPathExtension(ext)
    }

    // Append grid position suffix
    if let row = gridRow, let col = gridCol {
        let suffix = gridSettings.namingSuffix
            .replacingOccurrences(of: "{row}", with: "\(row)")
            .replacingOccurrences(of: "{col}", with: "\(col)")
        let baseName = result.deletingPathExtension().lastPathComponent
        let ext = result.pathExtension
        result = result.deletingLastPathComponent()
            .appendingPathComponent("\(baseName)\(suffix)")
            .appendingPathExtension(ext)
    }

    return result
}
```

Then refactor the existing `outputURL(for:index:gridRow:gridCol:)` to delegate:

```swift
func outputURL(for inputURL: URL, index: Int, gridRow: Int, gridCol: Int) -> URL {
    let base = outputURL(for: inputURL, index: index)
    return applyGridSuffix(to: base, gridRow: gridRow, gridCol: gridCol)
}
```

No signature change — `findBatchCollision` and `findExistingFiles` keep working.

### Step 1B: Simplify `processSingleImage` tile loop

File: `ImageCropService.swift` lines 983–1013

**Before** (~30 lines, manual URL construction):
```swift
let gridSettings = exportSettings.gridSettings
var outputURLs: [URL] = []

for tile in tiles {
    var tileOutputURL = exportSettings.outputURL(for: item.url, index: index)
    if cropSettings.cornerRadiusEnabled { /* 5 lines of PNG coercion */ }
    if let gridPos = tile.gridPosition { /* 8 lines of suffix construction */ }
    try save(...)
    outputURLs.append(tileOutputURL)
}
```

**After** (~10 lines):
```swift
var outputURLs: [URL] = []
let forceExt: String? = cropSettings.cornerRadiusEnabled ? "png" : nil

for tile in tiles {
    let baseURL = exportSettings.outputURL(for: item.url, index: index)
    let tileOutputURL = exportSettings.applyGridSuffix(
        to: baseURL,
        gridRow: tile.gridPosition?.row,
        gridCol: tile.gridPosition?.col,
        forceExtension: forceExt
    )
    try save(tile.image, to: tileOutputURL, format: tile.format, quality: exportSettings.quality)
    outputURLs.append(tileOutputURL)
}
return outputURLs
```

Removes `gridSettings` local variable and ~20 lines of manual URL building.

### Step 1C: Simplify `processAndExportWithRename` tile loop

File: `AppState.swift` lines 592–619

**Before** (~25 lines):
```swift
let gridSettings = capturedExportSettings.gridSettings
for tile in tiles {
    var tileURL = renamedURL
    if capturedCropSettings.cornerRadiusEnabled { /* 5 lines */ }
    if let gridPos = tile.gridPosition { /* 8 lines */ }
    try ImageCropService.save(...)
    results.append(...)
}
```

**After** (~10 lines):
```swift
let forceExt: String? = capturedCropSettings.cornerRadiusEnabled ? "png" : nil
for tile in tiles {
    let tileURL = capturedExportSettings.applyGridSuffix(
        to: renamedURL,
        gridRow: tile.gridPosition?.row,
        gridCol: tile.gridPosition?.col,
        forceExtension: forceExt
    )
    try ImageCropService.save(tile.image, to: tileURL, format: tile.format,
                              quality: capturedExportSettings.quality)
    results.append(tileURL)
}
```

### Step 1D: Add test for `forceExtension`

File: `ExportSettingsTests.swift`

```swift
func testApplyGridSuffixWithForceExtension() {
    var settings = ExportSettings()
    settings.format = .jpeg
    settings.gridSettings.namingSuffix = "_{row}_{col}"

    let baseURL = URL(fileURLWithPath: "/tmp/photo_cropped.jpg")
    let result = settings.applyGridSuffix(to: baseURL, gridRow: 1, gridCol: 2, forceExtension: "png")

    XCTAssertEqual(result.lastPathComponent, "photo_cropped_1_2.png")
}

func testApplyGridSuffixNoGrid() {
    var settings = ExportSettings()
    let baseURL = URL(fileURLWithPath: "/tmp/photo_cropped.jpg")
    let result = settings.applyGridSuffix(to: baseURL)

    XCTAssertEqual(result, baseURL)  // unchanged
}
```

---

## Fix 2: Simplify Result Index Tracking

**Problem:** `AppState.processAndExportWithRename()` line 574 appends `(0, url)` for all non-conflicting results. The sort on line 628 is broken because all non-conflicting items share index 0.

**Analysis:** The return type is `[URL]`. `batchCrop` already returns URLs in original-image order. Conflicting images are processed sequentially in enumeration order. The sort adds no value and the index tuple is unnecessary overhead.

### Step 2A: Simplify to `[URL]`

File: `AppState.swift`

Change line 554:
```swift
// Before:
var results: [(index: Int, url: URL)] = []

// After:
var results: [URL] = []
```

Change lines 572–575 (non-conflicting):
```swift
// Before:
for url in batchResults {
    results.append((0, url))
}

// After:
results.append(contentsOf: batchResults)
```

Change line 619 (conflicting, inside tile loop — adjusted by Fix 1C):
```swift
// Before:
results.append((originalIndex, tileURL))

// After:
results.append(tileURL)
```

Change line 628:
```swift
// Before:
return results.sorted { $0.index < $1.index }.map { $0.url }

// After:
return results
```

---

## Fix 3: Delete Dead Code

**Problem:** `SidebarComponents/_Unused/` contains 4 files from the ContentView extraction that are not referenced.

### Step 3A: Delete

```bash
rm -rf 01_Project/CropBatch/Views/SidebarComponents/_Unused/
```

Verify not in `project.pbxproj`:
```bash
grep -c "_Unused" 01_Project/CropBatch.xcodeproj/project.pbxproj
# Expected: 0
```

---

## Execution

All 3 fixes are independent — can run in parallel.

| Fix | Files Modified | Net Change | Risk |
|-----|---------------|-----------|------|
| 1 | ExportSettings.swift, ImageCropService.swift, AppState.swift, ExportSettingsTests.swift | -35, +30 | Low |
| 2 | AppState.swift | -6, +3 | Trivial |
| 3 | (delete 4 files) | -4 files | None |

**Single commit:** `Refactor: DRY grid URL construction, fix result ordering, remove dead code`

## Verification Checklist

- [ ] `xcodebuild build` — clean build, zero errors
- [ ] Unit tests pass (all existing + 2 new)
- [ ] Manual: enable 3×3 grid, export 2 images → 18 tiles, correct names
- [ ] Manual: grid + corner radius + JPEG source → all tiles `.png`
- [ ] Manual: grid + file conflict → renamed tiles have correct suffix
- [ ] Verify `_Unused/` not in build or git status

---
*Plan created 2026-03-31. Status: ready for execution.*
