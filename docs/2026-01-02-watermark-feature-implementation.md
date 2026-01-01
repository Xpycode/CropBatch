# Watermark Feature Implementation

**Date:** 2026-01-02
**Branch:** watermarking
**Status:** Implemented and working

## Overview

Added PNG image watermark overlay capability to CropBatch, allowing users to apply a watermark to all images during batch export. This was a user-requested feature for photographers.

## Features Implemented

### Core Functionality
- **PNG watermark overlay** - Load any image file (PNG, JPEG, HEIC, WebP, TIFF) as a watermark
- **9-position anchor grid** - Place watermark at corners, edges, or center
- **Size controls** - Original size, percentage of image, fixed width, or fixed height
- **Opacity slider** - 10% to 100% transparency
- **Margin control** - Distance from edges in pixels
- **X/Y offset** - Fine-tune position with pixel-precise values
- **Drag-to-position** - Drag watermark directly in preview

### UI Components
- `WatermarkSettingsSection` in sidebar with:
  - Image picker with drag-and-drop support
  - Thumbnail preview with dimensions
  - Position grid (3x3 buttons)
  - Size mode buttons and slider
  - Opacity slider
  - Margin and X/Y offset fields
  - Reset button for offsets

### Preview
- `WatermarkPreviewOverlay` shows watermark position in real-time
- Watermark is positioned relative to crop region (accurate to final output)
- Drag gesture updates X/Y offsets with visual feedback
- Hand cursor on hover

## Architecture

### Files Modified/Created

| File | Changes |
|------|---------|
| `Models/WatermarkSettings.swift` | **NEW** - Model with position, size, opacity, margin, offsets |
| `Models/ExportSettings.swift` | Added `watermarkSettings` property |
| `Services/ImageCropService.swift` | Added `applyWatermark()` method, integrated into pipeline |
| `Views/ExportSettingsView.swift` | Added `WatermarkSettingsSection` view |
| `Views/CropEditorView.swift` | Added `WatermarkPreviewOverlay` view |
| `ContentView.swift` | Added `WatermarkSettingsSection()` to sidebar |

### Processing Pipeline

The watermark is applied as step 5 in the export pipeline:

```
Transform -> Blur -> Crop -> Resize -> Watermark -> Save
```

This ensures the watermark:
1. Appears at correct size relative to final output
2. Is not affected by crop/resize operations
3. Uses final image dimensions for position calculations

### Key Technical Details

#### Sandbox Security
- File picker returns security-scoped URLs
- Must call `startAccessingSecurityScopedResource()` before reading
- **Critical:** Store image DATA, not just URL - the security scope is temporary
- `imageData: Data?` property persists across state changes

#### Coordinate Systems
- CGImage uses bottom-left origin (Y=0 at bottom)
- SwiftUI preview uses top-left origin (Y=0 at top)
- `watermarkRect()` flips Y anchor for CGImage coordinates
- Preview overlay uses standard SwiftUI coordinates

#### Position Calculation
```swift
// Anchor determines base position (0-1 normalized)
// Margin creates inset from edges
// Offset provides pixel-precise adjustment
let x = margin + (availableWidth - wmSize.width) * anchor.x + offsetX
let y = margin + (availableHeight - wmSize.height) * anchor.y + offsetY
```

## Bug Fixes

### Missing Watermark in Rename Export Path (2026-01-02)

**Symptom:** Watermark was configured correctly but not appearing on exported images.

**Root Cause:** The `processAndExportWithRename` method in `AppState.swift` had a duplicated image processing pipeline for handling file conflicts (when output would overwrite existing files). This manual pipeline was missing the watermark step.

**The Bug:**
```swift
// In processAndExportWithRename(), the conflicting files path had:
// 1. Transform ✓
// 2. Blur ✓
// 3. Crop ✓
// 4. Resize ✓
// 5. Watermark ✗  <-- MISSING!
// 6. Save ✓
```

**The Fix:** Added the missing watermark step after resize:
```swift
// Apply watermark if enabled
if settings.watermarkSettings.isValid {
    processedImage = ImageCropService.applyWatermark(processedImage, settings: settings.watermarkSettings)
}
```

**File:** `CropBatch/Models/AppState.swift` (lines 689-693)

**Lesson Learned:** When duplicating processing logic, all steps must be replicated. Better approach: extract shared logic into a single function to avoid divergence.

---

## Known Issues / TODO

### UI Polish Needed
- [ ] Watermark section takes significant vertical space
- [ ] Consider collapsible section or popover
- [ ] X/Y offset fields could be more compact

### Potential Enhancements
- [ ] Tiled/repeating watermark pattern
- [ ] Text watermark option
- [ ] Rotation angle for watermark
- [ ] Save/load watermark presets

## Testing Notes

1. Load a PNG watermark via file picker or drag-and-drop
2. Verify preview shows watermark in correct position
3. Adjust position, size, opacity - preview should update live
4. Drag watermark in preview - X/Y values should update
5. Export images - watermark should appear on all outputs
6. Re-open app - watermark should persist (stored as data)

## Code Examples

### Applying Watermark (ImageCropService.swift)
```swift
static func applyWatermark(_ image: NSImage, settings: WatermarkSettings) -> NSImage {
    guard settings.isValid,
          let watermarkImage = settings.loadedImage,
          let watermarkCGImage = watermarkImage.cgImage(...) else {
        return image
    }

    // Create context, draw source, then watermark with opacity
    context.draw(sourceCGImage, in: CGRect(origin: .zero, size: imageSize))
    context.setAlpha(settings.opacity)
    context.draw(watermarkCGImage, in: watermarkRect)

    return NSImage(cgImage: context.makeImage()!, size: imageSize)
}
```

### Draggable Preview (CropEditorView.swift)
```swift
Image(nsImage: watermarkImage)
    .gesture(
        DragGesture()
            .onChanged { value in
                let deltaX = value.translation.width / scale
                let deltaY = value.translation.height / scale
                appState.exportSettings.watermarkSettings.offsetX = dragStartOffset.x + deltaX
                appState.exportSettings.watermarkSettings.offsetY = dragStartOffset.y + deltaY
            }
    )
```

## Session Insights

1. **Sandbox file access** - Always use security-scoped resources and store data immediately
2. **State persistence** - Don't rely on cached objects; store serializable data
3. **Coordinate systems** - CGImage (bottom-left) vs SwiftUI (top-left) require careful handling
4. **Preview accuracy** - Position watermark relative to crop region, not full image
5. **UI architecture** - Check where components are actually rendered, not just defined
6. **Avoid code duplication** - The rename export path duplicated the processing pipeline and missed a step. Extract shared logic into reusable functions to prevent such bugs
