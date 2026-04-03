# Feature Spec: Grid Split

> Split each image into an NxM grid of tiles, saving each tile as a separate file.

## Problem
User needs to split squared images into 3x3 grids (e.g., for Instagram grid posts). CropBatch currently only does edge-based cropping — no tiling/splitting capability.

## Pipeline Placement

```
Blur -> Transform -> Crop -> Corner Mask -> GRID SPLIT -> Resize -> Watermark
```

Grid split happens **after** crop + corner mask but **before** resize and watermark:
- Crop trims unwanted edges first
- Each tile can then be resized independently
- Watermark applies per-tile (if enabled)

## Data Model

```swift
struct GridSettings: Equatable, Codable {
    var isEnabled: Bool = false
    var columns: Int = 2          // 1-10 range
    var rows: Int = 2             // 1-10 range
    var namingSuffix: String = "_{row}_{col}"  // tokens: {row}, {col}
}
```

Lives on `ExportSettings` — it's an export-time operation.
Also added to `ExportSettingsCodable` as `gridSettings: GridSettings?` (optional for backwards-compatible profile persistence, same pattern as `watermarkSettings`).

## Sidebar UI

New collapsible section between **Export Format** and **Quality & Resize**.
Uses same toggle-in-header pattern as Snap and Watermark sections.

```
+-----------------------------------------+
|  > Grid Split                       [ ] |  <- disabled/collapsed
+-----------------------------------------+

+-----------------------------------------+
|  v Grid Split                       [X] |  <- enabled/expanded
| +-------------------------------------+ |
| |                                     | |
| |  Columns   [  3  ] [-] [+]         | |
| |  Rows      [  3  ] [-] [+]         | |
| |                                     | |
| |  +---+---+---+                     | |
| |  |1,1|1,2|1,3|  Preview: 9 tiles   | |
| |  +---+---+---+  Each ~ 333 x 333   | |
| |  |2,1|2,2|2,3|                     | |
| |  +---+---+---+                     | |
| |  |3,1|3,2|3,3|                     | |
| |  +---+---+---+                     | |
| |                                     | |
| |  Naming  [_{row}_{col}        ] v  | |
| |                                     | |
| |  photo_1_1.png  photo_1_2.png  ... | |
| |                                     | |
| +-------------------------------------+ |
+-----------------------------------------+
```

### Section Contents (when enabled)
1. **Columns stepper** — `Stepper("Columns", value: $cols, in: 1...10)`
2. **Rows stepper** — `Stepper("Rows", value: $rows, in: 1...10)`
3. **Mini grid preview** — visual NxM grid showing tile labels
4. **Tile info** — "9 tiles, each ~333 x 333 px" (calculated from `CropSettings.croppedSize(from: imageItem.originalSize)` — use post-crop dimensions, not raw image size)
5. **Naming suffix** — text field with `{row}` and `{col}` tokens
6. **Output preview** — shows example filenames based on first image

### Square Shortcut
When user types a number in columns, offer to match rows (common case: 3x3 for Instagram).

## Canvas Preview Overlay

Dashed lines on the image canvas showing grid divisions:

```
+----------------------------------+
|          :          :            |
|          :          :            |
|          :          :            |
| ..........+..........+.......... |
|          :          :            |
|          :          :            |
|          :          :            |
| ..........+..........+.......... |
|          :          :            |
|          :          :            |
|          :          :            |
+----------------------------------+
```

- Style: dashed lines, yellow or white with slight opacity
- Drawn on top of the crop preview, below crop handles
- Only visible when grid is enabled
- Must set `.allowsHitTesting(false)` — must not intercept crop handle gestures
- Coordinate math: reuse `scale`, `offsetX`, `offsetY` from CropOverlayView
- Grid lines start from inner crop rect, divide by cols/rows
- Implementation: `Path` + `.stroke(style: StrokeStyle(dash: [4, 4]))`

## Naming Convention

**Default:** `{original}_{row}_{col}.ext` (1-indexed)

For `photo.png` split 3x3:
```
photo_1_1.png   photo_1_2.png   photo_1_3.png
photo_2_1.png   photo_2_2.png   photo_2_3.png
photo_3_1.png   photo_3_2.png   photo_3_3.png
```

Integrates with existing rename pattern system:
- If pattern mode: `{name}_{counter}` + grid suffix -> `photo_01_1_1.png`
- If suffix mode: `photo_cropped_1_1.png`

## Non-Even Division Strategy

**Last tile absorbs remainder** (industry standard, most tools do this):

```
1000px / 3 cols = 333, 333, 334
```

All pixels preserved. 1px difference invisible.

Implementation:
```swift
let tileWidth = imageWidth / cols           // integer division
let lastColWidth = imageWidth - (tileWidth * (cols - 1))
// Same for rows
```

## Export Flow Changes (1 -> N)

### Current
```
1 image -> process -> 1 file
```

### With Grid
```
1 image -> process (up to corner mask) -> split into RxC tiles -> per-tile: resize + watermark -> RxC files
```

### Specific Changes

**ImageCropService.swift:**
- New method: `splitIntoGrid(image: CGImage, rows: Int, cols: Int) -> [(row: Int, col: Int, image: CGImage)]`
- `processSingleImage()` returns `[URL]` array when grid enabled (currently returns single `URL`)
- Each tile goes through resize + watermark independently
- ⚠️ Text watermark uses `NSImage.lockFocus` (not thread-safe) — tiles with text watermark must be processed sequentially, not in parallel TaskGroup. Alternative: refactor watermark to use CGContext.

**ExportSettings.swift:**
- `outputURL()` extended to accept optional `(row, col)` for grid suffix
- `findExistingFiles()` checks all tile filenames
- `findBatchCollision()` accounts for tile names across images

**ExportCoordinator.swift:**
- Progress = completed tiles / (total images x rows x cols)
- BatchReviewView shows: "3 images x 9 tiles = 27 files"

**AppState.swift:**
- `processAndExport()` handles 1->N result arrays (gets grid for free via `batchCrop`)
- ⚠️ `processAndExportWithRename()` has an **inlined pipeline** (does NOT call `processSingleImage`) — grid split must be manually added here between corner mask and resize steps
- `processAndExportInPlace()` — grid + save-in-place is invalid (can't overwrite 1 file with N tiles). Disable grid when save-in-place is active.
- `canExport` gate must include `exportSettings.gridSettings.isEnabled`
- Settings snapshot includes grid settings

## Edge Cases

| Case | Handling |
|------|----------|
| 1x1 grid | Same as disabled — no-op, skip split step |
| Grid + corner radius | Corner tiles get rounded corners, interior tiles are rectangular. Note: could look odd — add subtle UI hint |
| Very small tiles (<50px) | Show warning: "Tiles will be very small (NxN px)" |
| Grid + watermark | Watermark applied per-tile after split. ⚠️ Text watermark not thread-safe — process tiles sequentially |
| Grid + resize | Resize applied per-tile after split |
| Grid + save-in-place | Invalid — disable grid when save-in-place is active (can't overwrite 1 original with N tiles) |
| Grid + corner radius + non-PNG source | All tile URLs must be coerced to .png (existing corner-radius format coercion applied per-tile) |
| Non-square images | Works fine — rows/cols independent |
| 1 column, 3 rows | Horizontal strips — valid use case |

## Implementation Waves

| Wave | Scope | Files | Effort |
|------|-------|-------|--------|
| 1 | GridSettings model + sidebar UI section + canExport gate + ExportSettingsCodable | ExportSettings.swift, ContentView.swift, AppState.swift | Small |
| 2 | Grid split logic in processing pipeline | ImageCropService.swift | Medium |
| 3 | Export flow: 1->N naming, conflict detection, progress, inlined pipeline fix | ExportCoordinator.swift, AppState.swift, ExportSettings.swift | Medium |
| 4 | Canvas preview overlay (grid lines on image) | New GridOverlayView.swift (peer of CropOverlayView.swift in Views/EditorComponents/) | Small |
| 5 | Polish: BatchReview tile count, edge case warnings, square shortcut, disable grid for save-in-place | Various | Small |

## Research Notes

### Industry Patterns (from ImageMagick, Photoshop, GIMP, online tools)
- **Rows x Columns** is the dominant input mode (not pixel-size-based)
- **Last tile absorbs remainder** is the standard for non-even divisions
- **Overlap** (shared pixels between tiles) exists but is niche — skip for v1
- **Output as ZIP** common in web tools — not needed for desktop app

### Naming Conventions Across Tools
- GIMP: `prefix_row_col.ext` (0-indexed)
- Photoshop: `slice_01.ext` (sequential)
- ImageMagick: positional metadata in image
- **Our choice:** `{name}_{row}_{col}.ext` (1-indexed) — clearest, sorts well in Finder

## Review Notes (2026-03-29)

Issues found during codebase cross-reference and resolved in this spec:

1. **`processAndExportWithRename` inlined pipeline** — This method in AppState.swift reimplements the processing pipeline without calling `processSingleImage`. Grid split must be manually added there. (Wave 3)
2. **`processAndExportInPlace` incompatibility** — Can't overwrite 1 original with N tiles. Grid disabled for save-in-place. (Wave 5)
3. **Text watermark thread safety** — `NSImage.lockFocus` is not thread-safe. Tiles with text watermark must be processed sequentially. (Wave 2/3)
4. **Format coercion for corner radius** — Per-tile URL extension must be coerced to .png when corner radius is active. (Wave 3)
5. **`canExport` gate** — Must include grid enabled state. (Wave 1)
6. **`ExportSettingsCodable` persistence** — GridSettings added as optional field for profile compatibility. (Wave 1)
7. **Canvas overlay file reference** — Corrected from `CropCanvasView.swift` to `CropOverlayView.swift` / new `GridOverlayView.swift`. (Wave 4)
8. **Tile size source** — Uses `CropSettings.croppedSize(from:)` for accurate post-crop dimensions. (Wave 1 UI)

---
*Spec created 2026-03-29. Reviewed and updated 2026-03-29. Status: ready for implementation.*
