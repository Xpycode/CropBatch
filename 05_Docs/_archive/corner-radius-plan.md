# Rounded Corner Crop - Implementation Plan

**Status:** Planned
**Last Updated:** 2026-01-06

## Purpose

Remove macOS window shadows cleanly by masking corners with transparency. When cropping screenshots of windows, the shadows extend beyond the window bounds, and the window corners are rounded (~10px on macOS). This feature allows cropping away the shadow while preserving the rounded corner appearance.

---

## Feature Specification

### Behavior
- PNG output only (corners become transparent)
- Default radius: 10px (matches macOS window corners)
- Auto-clamps radius to `min(radius, width/2, height/2)` to prevent oversized radii
- Preview overlay shows rounded mask shape when enabled

### UI Design (Progressive Disclosure)

Located in Crop Values section:

```
☐ Corner Radius                    ← Feature toggle (off by default)

      ↓ (when checked)

☑ Corner Radius      [ 10 ] px     ← Radius field appears
  ☐ Independent corners            ← Sub-option appears

      ↓ (when independent checked)

☑ Corner Radius      [ 10 ] px
  ☑ Independent corners
    TL [ 10 ]  TR [ 10 ]           ← Four individual fields
    BL [ 10 ]  BR [ 10 ]
```

---

## Implementation Guide

### Core API (macOS 13+)

SwiftUI provides `RectangleCornerRadii` for independent corner values:

```swift
// SwiftUI Path with independent corner radii
let radii = RectangleCornerRadii(
    topLeading: 10,
    bottomLeading: 10,
    bottomTrailing: 10,
    topTrailing: 10
)
let path = Path(roundedRect: rect, cornerRadii: radii, style: .continuous)
let cgPath = path.cgPath  // Convert to CGPath for Core Graphics
```

### New Function: `applyRoundedCornerMask`

Add to `ImageCropService.swift`:

```swift
private static func applyRoundedCornerMask(
    _ image: NSImage,
    radii: RectangleCornerRadii
) -> NSImage {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return image
    }

    let width = cgImage.width
    let height = cgImage.height

    // Create RGBA context with alpha channel
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return image }

    let rect = CGRect(x: 0, y: 0, width: width, height: height)

    // Create rounded rect path and clip
    let path = Path(roundedRect: rect, cornerRadii: radii, style: .continuous)
    context.beginPath()
    context.addPath(path.cgPath)
    context.closePath()
    context.clip()

    // Draw image into clipped context
    context.draw(cgImage, in: rect)

    guard let maskedCGImage = context.makeImage() else { return image }
    return NSImage(cgImage: maskedCGImage, size: image.size)
}
```

### Pipeline Integration

In `processSingleImage()` (~line 800), insert after crop step:

```swift
// After step 3 (crop):
processedImage = try crop(processedImage, with: cropSettings)

// NEW Step 3.5: Apply rounded corner mask
if cropSettings.cornerRadiusEnabled, let radii = cropSettings.effectiveCornerRadii {
    processedImage = applyRoundedCornerMask(processedImage, radii: radii)
}

// Step 4 (resize) continues...
```

**Pipeline order:** Blur → Transform → Crop → **Corner Mask** → Resize → Watermark

### Model Changes

Add to `CropSettings.swift`:

```swift
// Corner radius properties
var cornerRadiusEnabled: Bool = false
var cornerRadius: Int = 10
var independentCorners: Bool = false
var cornerRadiusTL: Int = 10  // top-leading
var cornerRadiusTR: Int = 10  // top-trailing
var cornerRadiusBL: Int = 10  // bottom-leading
var cornerRadiusBR: Int = 10  // bottom-trailing

// Computed property with auto-clamping
var effectiveCornerRadii: RectangleCornerRadii? {
    guard cornerRadiusEnabled else { return nil }

    let maxRadius = min(croppedWidth, croppedHeight) / 2

    if independentCorners {
        return RectangleCornerRadii(
            topLeading: CGFloat(min(cornerRadiusTL, maxRadius)),
            bottomLeading: CGFloat(min(cornerRadiusBL, maxRadius)),
            bottomTrailing: CGFloat(min(cornerRadiusBR, maxRadius)),
            topTrailing: CGFloat(min(cornerRadiusTR, maxRadius))
        )
    } else {
        let clamped = CGFloat(min(cornerRadius, maxRadius))
        return RectangleCornerRadii(
            topLeading: clamped,
            bottomLeading: clamped,
            bottomTrailing: clamped,
            topTrailing: clamped
        )
    }
}
```

---

## Files to Modify

| File | Changes |
|------|---------|
| `CropSettings.swift` | Add corner radius properties + `effectiveCornerRadii` computed property |
| `ImageCropService.swift` | Add `applyRoundedCornerMask()` function, call from pipeline |
| `ExportSettings.swift` | Force PNG format when corners enabled |
| `CropSectionView.swift` | UI controls: checkbox → radius field → independent corners toggle |
| `ImagePreviewOverlay.swift` | Visualize rounded mask shape in preview overlay |

---

## Key Constraints

1. **PNG output required** - JPEG doesn't support transparency; corners would be white/black instead of transparent
2. **Auto-clamp radius** - `min(radius, width/2, height/2)` prevents nonsensical values
3. **Graceful degradation** - SwiftUI Path API handles oversized radii by creating pill/oval shapes naturally

---

## Edge Cases

- **Very small crops:** If cropped dimensions are tiny, radius may auto-clamp to near-zero
- **Radius > half dimension:** Creates pill shape (handled gracefully by Path API)
- **JPEG selected with corners:** UI should either disable corner option or auto-switch to PNG with notice

---

## References

- [RectangleCornerRadii](https://developer.apple.com/documentation/swiftui/rectanglecornerradii) - SwiftUI struct for per-corner values
- [Path(roundedRect:cornerRadii:style:)](https://developer.apple.com/documentation/swiftui/path/init(roundedrect:cornerradii:style:)) - Creates path with uneven corners
- [CGContext](https://developer.apple.com/documentation/coregraphics/cgcontext) - Clipping and drawing operations
- [CGImageAlphaInfo.premultipliedLast](https://developer.apple.com/documentation/coregraphics/cgimagealphainfo/premultipliedlast) - Required for transparency
