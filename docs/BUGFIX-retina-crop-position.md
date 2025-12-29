# Critical Fix: Retina Crop Position Bug

**Date Fixed:** 2025-12-29
**Commit:** `2393b92`
**Location:** `CropBatch/Models/AppState.swift` → `ImageItem.originalSize`

---

## The Bug

Crop preview showed the correct area, but exported images were cropped at the **wrong position** — shifted significantly from what was shown in the UI.

## Root Cause

**NSImage.size vs CGImage dimensions:**

| Property | Returns | Example (Retina 2x) |
|----------|---------|---------------------|
| `NSImage.size` | Points (display units) | 589×1278 |
| `CGImage.width/height` | Pixels (actual data) | 1178×2556 |

The UI overlay (`CropEditorView`, `CropOverlayView`) used `image.originalSize` which returned **points**.
The crop service (`ImageCropService.crop()`) used `cgImage.width/height` which are **pixels**.

When user set L=150 based on the preview (589px wide), the crop service applied L=150 to the actual 1178px-wide image — cropping at **half** the expected position.

## The Fix

Changed `ImageItem.originalSize` to return CGImage pixel dimensions:

```swift
var originalSize: CGSize {
    guard let cgImage = originalImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return originalImage.size
    }
    return CGSize(width: cgImage.width, height: cgImage.height)
}
```

## Why This Must Not Be Reverted

The entire app coordinate system now works in **pixels**:
- UI displays pixel dimensions
- Crop values are in pixels
- Preview overlay uses pixels
- Export crop uses pixels

**If you change `originalSize` back to `originalImage.size`, the bug will return on any Retina screenshot or image with scale factor ≠ 1.**

## Warning Comment in Code

A prominent box comment was added at the fix location to prevent accidental changes:

```
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
```

## Testing

To verify the fix works:
1. Load a Retina screenshot (2x or 3x scale)
2. Set crop values using the preview handles
3. Export the image
4. The cropped region should exactly match the preview overlay
