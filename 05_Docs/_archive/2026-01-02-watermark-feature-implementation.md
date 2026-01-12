# Watermark Feature Implementation

**Date:** 2026-01-02
**Branch:** watermarking
**Status:** Implemented and working

## Overview

Added comprehensive watermark capability to CropBatch, supporting both **image** and **text** watermarks with full styling options. Users can apply watermarks to all images during batch export - useful for photographers, content creators, and anyone needing to brand their images.

## Features Implemented

### Image Watermark
- **Image file support** - Load PNG, JPEG, HEIC, WebP, TIFF as watermark
- **9-position anchor grid** - Place watermark at corners, edges, or center
- **Size controls** - Original size, percentage of image, fixed width, or fixed height
- **Opacity slider** - 10% to 100% transparency
- **Margin control** - Distance from edges in pixels
- **X/Y offset** - Fine-tune position with pixel-precise values
- **Drag-to-position** - Drag watermark directly in preview

### Text Watermark
- **Dynamic variables** - Auto-substituted at export time:
  - `{filename}` - Original filename (without extension)
  - `{index}` - Image number in batch (1, 2, 3...)
  - `{count}` - Total image count
  - `{date}` - Current date (YYYY-MM-DD)
  - `{datetime}` - Date and time (YYYY-MM-DD HH:mm)
  - `{year}`, `{month}`, `{day}` - Individual date components
- **Font styling**:
  - Font family picker (all system fonts)
  - Font size (8-500pt)
  - Bold and italic toggles
  - Color picker with full alpha support
- **Text effects**:
  - **Shadow** - Color, blur radius, X/Y offset
  - **Outline** - Color and stroke width
- **Same positioning** as image watermarks (position, margin, offset, drag)

### UI Components
- `WatermarkSettingsSection` in sidebar with:
  - **Mode picker** - Toggle between Image and Text modes
  - **Image mode**: File picker with drag-and-drop, thumbnail preview
  - **Text mode**: Text input, variable buttons, font controls, color picker, effects
  - Position grid (3x3 buttons)
  - Size controls (image mode only)
  - Opacity slider
  - Margin and X/Y offset fields

### Preview
- `WatermarkPreviewOverlay` shows watermark position in real-time
- Supports both image and text rendering
- Watermark is positioned relative to crop region (accurate to final output)
- Drag gesture updates X/Y offsets with visual feedback
- Text preview shows live styling (font, color, shadow, outline)

## Architecture

### Files Modified/Created

| File | Changes |
|------|---------|
| `Models/WatermarkSettings.swift` | **NEW** - Comprehensive model with mode, position, size, opacity, text styling, effects |
| `Models/ExportSettings.swift` | Added `watermarkSettings` property |
| `Services/ImageCropService.swift` | Added `applyWatermark()`, `applyImageWatermark()`, `applyTextWatermark()` methods |
| `Views/ExportSettingsView.swift` | Added `WatermarkSettingsSection` with mode picker, text controls, effects UI |
| `Views/CropEditorView.swift` | Added `WatermarkPreviewOverlay` supporting both image and text |
| `ContentView.swift` | Added `WatermarkSettingsSection()` to sidebar |

### Model Structure

```swift
// WatermarkSettings.swift
struct WatermarkSettings {
    var isEnabled: Bool
    var mode: WatermarkMode          // .image or .text
    
    // Image mode
    var imageURL: URL?
    var imageData: Data?
    var cachedImage: NSImage?
    
    // Text mode
    var text: String                 // Supports {variables}
    var fontFamily: String
    var fontSize: Double
    var isBold: Bool
    var isItalic: Bool
    var textColor: CodableColor
    var shadow: TextShadowSettings
    var outline: TextOutlineSettings
    
    // Shared
    var position: WatermarkPosition  // 9-position enum
    var opacity: Double
    var sizeMode: WatermarkSizeMode  // For image mode
    var sizeValue: Double
    var margin: Double
    var offsetX: Double
    var offsetY: Double
}
```

### Processing Pipeline

The watermark is applied as step 5 in the export pipeline:

```
Transform -> Blur -> Crop -> Resize -> Watermark -> Save
```

The `applyWatermark()` method routes to the appropriate handler:
```swift
switch settings.mode {
case .image: return applyImageWatermark(image, settings: settings)
case .text:  return applyTextWatermark(image, settings: settings, filename: filename, index: index, count: count)
}
```

### Key Technical Details

#### Dynamic Variable Substitution
Variables are resolved at export time using `TextWatermarkVariable.substitute()`:
```swift
static func substitute(in template: String, filename: String, index: Int, count: Int) -> String {
    var result = template
    result = result.replacingOccurrences(of: "{filename}", with: filename)
    result = result.replacingOccurrences(of: "{index}", with: "\(index)")
    // ... date formatting for {date}, {year}, etc.
    return result
}
```

#### Text Rendering
Text watermarks use `NSAttributedString` with custom attributes:
```swift
func textAttributes(scale: CGFloat) -> [NSAttributedString.Key: Any] {
    var attributes: [NSAttributedString.Key: Any] = [:]
    attributes[.font] = scaledFont
    attributes[.foregroundColor] = textColor.nsColor.withAlphaComponent(opacity)
    if shadow.isEnabled {
        let nsShadow = NSShadow()
        nsShadow.shadowColor = shadow.color.nsColor
        nsShadow.shadowBlurRadius = shadow.blur * scale
        attributes[.shadow] = nsShadow
    }
    if outline.isEnabled {
        attributes[.strokeColor] = outline.color.nsColor
        attributes[.strokeWidth] = -outline.width * scale  // Negative = fill + stroke
    }
    return attributes
}
```

#### CodableColor Wrapper
NSColor isn't Codable, so we use a wrapper:
```swift
struct CodableColor: Codable, Equatable {
    var red, green, blue, alpha: Double
    
    init(_ color: NSColor) { /* extract components */ }
    var nsColor: NSColor { NSColor(red: red, green: green, blue: blue, alpha: alpha) }
}
```

#### Sandbox Security (Image Mode)
- File picker returns security-scoped URLs
- Must call `startAccessingSecurityScopedResource()` before reading
- **Critical:** Store image DATA, not just URL - the security scope is temporary
- `imageData: Data?` property persists across state changes

#### Coordinate Systems
- CGImage uses bottom-left origin (Y=0 at bottom)
- SwiftUI preview uses top-left origin (Y=0 at top)
- `watermarkRect()` flips Y anchor for CGImage coordinates
- Preview overlay uses standard SwiftUI coordinates

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
- [ ] Text outline preview in SwiftUI is approximate (actual render uses NSAttributedString)

### Potential Enhancements
- [x] ~~Text watermark option~~ ✓ Implemented
- [ ] Tiled/repeating watermark pattern
- [ ] Rotation angle for watermark
- [ ] Save/load watermark presets
- [ ] Multi-line text support
- [ ] Text alignment options (left/center/right)

## Testing Notes

### Image Watermark Testing
1. Load a PNG watermark via file picker or drag-and-drop
2. Verify preview shows watermark in correct position
3. Adjust position, size, opacity - preview should update live
4. Drag watermark in preview - X/Y values should update
5. Export images - watermark should appear on all outputs
6. Re-open app - watermark should persist (stored as data)

### Text Watermark Testing
1. Enable watermark, switch to Text mode
2. Enter text with variables: `© {year} - {filename} ({index}/{count})`
3. Test font family picker - verify font changes in preview
4. Test font size slider (8-500pt range)
5. Toggle bold/italic - verify styling in preview
6. Change text color - verify preview updates
7. Enable shadow:
   - Adjust blur radius (0-20)
   - Change shadow color
   - Modify X/Y offset
8. Enable outline:
   - Adjust stroke width (0.5-10)
   - Change outline color
9. Test all 9 positions with text
10. Drag text in preview - verify offset values update
11. Export batch:
    - Verify variables are substituted per-image
    - `{index}` should increment (1, 2, 3...)
    - `{filename}` should match source file
    - `{date}` should show current date
12. Verify text styling (font, color, shadow, outline) appears correctly in export

## Code Examples

### Watermark Router (ImageCropService.swift)
```swift
static func applyWatermark(
    _ image: NSImage,
    settings: WatermarkSettings,
    filename: String = "",
    index: Int = 1,
    count: Int = 1
) -> NSImage {
    guard settings.isValid else { return image }
    
    switch settings.mode {
    case .image:
        return applyImageWatermark(image, settings: settings)
    case .text:
        return applyTextWatermark(image, settings: settings, filename: filename, index: index, count: count)
    }
}
```

### Text Watermark Rendering (ImageCropService.swift)
```swift
private static func applyTextWatermark(
    _ image: NSImage,
    settings: WatermarkSettings,
    filename: String,
    index: Int,
    count: Int
) -> NSImage {
    // Substitute dynamic variables
    let resolvedText = TextWatermarkVariable.substitute(
        in: settings.text,
        filename: filename,
        index: index,
        count: count
    )
    
    // Get attributes with font, color, shadow, outline
    let attributes = settings.textAttributes(scale: 1.0)
    let attrString = NSAttributedString(string: resolvedText, attributes: attributes)
    
    // Draw to image context
    let resultImage = NSImage(size: imageSize)
    resultImage.lockFocus()
    // ... draw source image, then text
    attrString.draw(in: drawRect)
    resultImage.unlockFocus()
    
    return resultImage
}
```

### Dynamic Variable Substitution
```swift
enum TextWatermarkVariable: String, CaseIterable {
    case filename = "{filename}"
    case index = "{index}"
    case count = "{count}"
    case date = "{date}"
    case datetime = "{datetime}"
    case year = "{year}"
    case month = "{month}"
    case day = "{day}"
    
    static func substitute(in template: String, filename: String, index: Int, count: Int) -> String {
        var result = template
        result = result.replacingOccurrences(of: "{filename}", with: filename)
        result = result.replacingOccurrences(of: "{index}", with: "\(index)")
        result = result.replacingOccurrences(of: "{count}", with: "\(count)")
        
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        result = result.replacingOccurrences(of: "{date}", with: dateFormatter.string(from: now))
        // ... more date formats
        
        return result
    }
}
```

### Draggable Preview (CropEditorView.swift)
```swift
// Shared drag gesture for both image and text watermarks
private var dragGesture: some Gesture {
    DragGesture()
        .onChanged { value in
            if !isDragging {
                isDragging = true
                dragStartOffset = CGPoint(
                    x: appState.exportSettings.watermarkSettings.offsetX,
                    y: appState.exportSettings.watermarkSettings.offsetY
                )
            }
            let deltaX = value.translation.width / scale
            let deltaY = value.translation.height / scale
            appState.exportSettings.watermarkSettings.offsetX = dragStartOffset.x + deltaX
            appState.exportSettings.watermarkSettings.offsetY = dragStartOffset.y + deltaY
        }
        .onEnded { _ in
            isDragging = false
            appState.markCustomSettings()
        }
}
```

## Session Insights

1. **Sandbox file access** - Always use security-scoped resources and store data immediately
2. **State persistence** - Don't rely on cached objects; store serializable data
3. **Coordinate systems** - CGImage (bottom-left) vs SwiftUI (top-left) require careful handling
4. **Preview accuracy** - Position watermark relative to crop region, not full image
5. **UI architecture** - Check where components are actually rendered, not just defined
6. **Avoid code duplication** - The rename export path duplicated the processing pipeline and missed a step. Extract shared logic into reusable functions to prevent such bugs
7. **NSColor isn't Codable** - Create a `CodableColor` wrapper struct to persist colors in settings
8. **Text rendering differences** - SwiftUI `Text` vs `NSAttributedString.draw()` have subtle differences; effects like outline may render differently in preview vs export
9. **Dynamic context at render time** - Variables like `{filename}` require context passed through the call chain to the render function
10. **Font traits in AppKit** - Use `NSFontManager.shared.font(withFamily:traits:weight:size:)` to apply bold/italic to fonts
