# Watermark Crop Bounds Constraint

**Date:** 2026-01-02
**Branch:** `watermarking` (merged to `main`)
**Commits:** `da86943`, `1441c0d`

## Summary

Fixed the watermark preview to properly constrain within the crop area bounds, ensuring the preview accurately reflects the exported result.

## Problem

The watermark overlay was rendering outside the crop area:
1. Text/image watermarks could extend beyond the crop rectangle edges
2. Preview didn't match exported output (export applies watermark after cropping)
3. Dragging watermarks allowed positioning partially outside visible area

## Solution

### 1. Clip Overlay to Crop Bounds

Changed the `WatermarkPreviewOverlay` structure to clip content within the crop area:

```swift
// Before: .clipped() applied before overlay (didn't clip overlay content)
Rectangle()
    .fill(.clear)
    .frame(width: cropRect.width, height: cropRect.height)
    .clipped()
    .overlay { ... }

// After: .clipShape() applied after overlay
Color.clear
    .frame(width: cropRect.width, height: cropRect.height)
    .overlay(alignment: .topLeading) { ... }
    .clipShape(Rectangle())  // Clips AFTER overlay
    .position(x: cropRect.midX, y: cropRect.midY)
```

**Key insight:** `.clipped()` only clips the view it's applied to, not subsequent overlays. Using `.clipShape()` after the overlay ensures the entire composited view gets clipped.

### 2. Position Clamping

Added boundary clamping to keep watermarks fully inside the crop area:

```swift
// Preview (CropEditorView.swift)
private func watermarkPosition(for containerSize: CGSize, wmSize: CGSize) -> CGPoint {
    // ... calculate position ...

    // Clamp to keep watermark within bounds
    x = max(0, min(containerSize.width - wmSize.width, x))
    y = max(0, min(containerSize.height - wmSize.height, y))

    return CGPoint(x: x, y: y)
}
```

Same clamping applied to export functions in `WatermarkSettings.swift`:
- `watermarkRect(for:)` - image watermarks
- `textWatermarkRect(for:text:)` - text watermarks

### 3. Fixed Font Scaling Mismatch

The preview text was rendering larger than calculated because of a font size mismatch:

```swift
// Before: Using unscaled font
Text(previewText)
    .font(Font(settings.textFont))  // Original fontSize

// After: Using scaled font to match size calculation
let scaledFont = NSFont(
    descriptor: settings.textFont.fontDescriptor,
    size: settings.fontSize * scale
) ?? settings.textFont

Text(previewText)
    .font(Font(scaledFont))  // Scaled fontSize
```

### 4. Changed from .position() to .offset()

Switched watermark positioning from `.position()` to `.offset()` for proper coordinate handling within the clipped container:

```swift
// Before: .position() positions center point
.position(
    x: cropRect.minX + wmPosition.x + wmSize.width / 2,
    y: cropRect.minY + wmPosition.y + wmSize.height / 2
)

// After: .offset() moves from top-left origin
.offset(x: wmPosition.x, y: wmPosition.y)
```

## Files Modified

| File | Changes |
|------|---------|
| `CropEditorView.swift` | Refactored `WatermarkPreviewOverlay` with clipping and offset positioning |
| `WatermarkSettings.swift` | Added clamping to `watermarkRect()` and `textWatermarkRect()` |

## Testing

1. Enable watermark with text mode
2. Position at any corner (especially bottom-right)
3. Verify watermark stays fully within crop rectangle
4. Drag watermark to edge - should stop at boundary
5. Export and verify watermark position matches preview

## Related

- Previous commit `da86943`: Initial watermark overlay feature
- Export pipeline applies watermark after cropping (step 5 in `processExportItem`)
