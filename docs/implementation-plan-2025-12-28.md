# CropBatch Feature Implementation Plan

**Date:** 2025-12-28
**Branch:** `future-refinements`
**Status:** Planning Complete

---

## Overview

Implementation plan for three new features:
1. Undo/Redo for crop adjustments
2. Batch rename on export
3. Image rotation (90 CW/CCW, flip H/V)

---

## Feature 1: Undo/Redo for Crop Adjustments

### Current State
Infrastructure already exists in `AppState.swift`:
- `cropHistory: [CropSettings]`
- `cropHistoryIndex: Int`
- `canUndo` / `canRedo` computed properties
- `undo()` / `redo()` / `recordCropChange()` methods

### Tasks

| # | Task | File | Status |
|---|------|------|--------|
| 1.1 | Add Edit menu with Undo/Redo commands | `CropBatchApp.swift` | Pending |
| 1.2 | Add undo/redo toolbar buttons | `ActionButtonsView.swift` | Pending |
| 1.3 | Verify `recordCropChange()` called on handle drag end | `CropEditorView.swift` | Pending |
| 1.4 | Verify `recordCropChange()` called on slider commit | `CropSettingsView.swift` | Pending |

> **Doc check (2025-12-27):** `CropBatchApp.swift` already implements a `CommandGroup(replacing: .undoRedo)` with Cmd+Z / Cmd+Shift+Z. Task 1.1’s scope appears completed, so confirm whether the “Pending” status is stale before duplicating menu items.

### Implementation

```swift
// CropBatchApp.swift - Add to WindowGroup
.commands {
    CommandGroup(replacing: .undoRedo) {
        Button("Undo Crop") { appState.undo() }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!appState.canUndo)
        Button("Redo Crop") { appState.redo() }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!appState.canRedo)
    }
}
```

### Keyboard Shortcuts
| Action | Shortcut |
|--------|----------|
| Undo | Cmd+Z |
| Redo | Cmd+Shift+Z |

---

## Feature 2: Batch Rename on Export

### Current State
- `ExportSettings.suffix` adds text after original filename
- `outputFilename(for:)` returns `{name}{suffix}.{ext}`
- No pattern/index support

### Data Model

```swift
// Add to ExportSettings.swift

enum RenameMode: String, CaseIterable, Identifiable {
    case keepOriginal   // Current behavior: {name}{suffix}.{ext}
    case pattern        // Pattern-based naming

    var id: String { rawValue }
}

struct RenameSettings: Equatable {
    var mode: RenameMode = .keepOriginal
    var pattern: String = "{name}_{index}"
    var startIndex: Int = 1
    var zeroPadding: Int = 2   // 01, 02, ... 99

    static let `default` = RenameSettings()
}
```

### Supported Tokens
| Token | Description | Example |
|-------|-------------|---------|
| `{name}` | Original filename (no extension) | `screenshot` |
| `{index}` | Position in batch (1-based) | `1`, `2`, `3` |
| `{counter}` | startIndex + position | `001`, `002` |
| `{date}` | Current date | `2025-12-28` |
| `{time}` | Current time | `14-30-45` |

### Tasks

| # | Task | File | Status |
|---|------|------|--------|
| 2.1 | Add `RenameMode` enum | `ExportSettings.swift` | Pending |
| 2.2 | Add `RenameSettings` struct | `ExportSettings.swift` | Pending |
| 2.3 | Add `renameSettings` to `ExportSettings` | `ExportSettings.swift` | Pending |
| 2.4 | Update `outputFilename(for:index:)` | `ExportSettings.swift` | Pending |
| 2.5 | Update `batchCrop()` to pass index | `ImageCropService.swift` | Pending |
| 2.6 | Create `RenameSettingsSection` UI | `ExportSettingsView.swift` | Pending |
| 2.7 | Add live filename preview | `ExportSettingsView.swift` | Pending |

> **Doc check (2025-12-27):**
> - The current codebase only exposes `outputFilename(for inputURL: URL)` (no index parameter), so Task 2.4 references a function that has not been introduced yet.
> - `ExportSettingsView` already includes an `OutputPreview` UI that recomputes the filename and warns about overwrites; Task 2.7 should be marked done or clarified if additional previews are required.

### Implementation

```swift
// ExportSettings.swift - Pattern processing
func outputFilename(for inputURL: URL, index: Int = 0, total: Int = 1) -> String {
    guard renameSettings.mode == .pattern else {
        // Current behavior
        let originalName = inputURL.deletingPathExtension().lastPathComponent
        let `extension` = inputURL.pathExtension
        return "\(originalName)\(suffix).\(`extension`)"
    }
    
    let originalName = inputURL.deletingPathExtension().lastPathComponent
    let `extension` = inputURL.pathExtension

    let now = Date()
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    let dateString = dateFormatter.string(from: now)
    dateFormatter.dateFormat = "HH-mm-ss"
    let timeString = dateFormatter.string(from: now)

    let paddedIndex = String(format: "%0\(renameSettings.zeroPadding)d",
                             renameSettings.startIndex + index)

    var result = renameSettings.pattern
    result = result.replacingOccurrences(of: "{name}", with: originalName)
    result = result.replacingOccurrences(of: "{index}", with: "\(index + 1)")
    result = result.replacingOccurrences(of: "{counter}", with: paddedIndex)
    result = result.replacingOccurrences(of: "{date}", with: dateString)
    result = result.replacingOccurrences(of: "{time}", with: timeString)

    return "\(result).\(`extension`)"
}
```

---

## Feature 3: Image Rotation (90 CW/CCW, Flip H/V)

### Design Decision
Store rotation/flip as transform state per image, apply during export (non-destructive editing).

### Data Model

```swift
// New file: CropBatch/Models/ImageTransform.swift

enum RotationAngle: Int, CaseIterable, Identifiable {
    case none = 0
    case cw90 = 90
    case cw180 = 180
    case cw270 = 270

    var id: Int { rawValue }

    var swapsWidthAndHeight: Bool {
        self == .cw90 || self == .cw270
    }

    mutating func rotateCW() {
        self = RotationAngle(rawValue: (rawValue + 90) % 360) ?? .none
    }

    mutating func rotateCCW() {
        self = RotationAngle(rawValue: (rawValue + 270) % 360) ?? .none
    }
}

struct ImageTransform: Equatable {
    var rotation: RotationAngle = .none
    var flipHorizontal: Bool = false
    var flipVertical: Bool = false

    static let identity = ImageTransform()
    var isIdentity: Bool { self == .identity }
}
```

### State Storage

```swift
// AppState.swift - Add alongside blurRegions pattern
var imageTransforms: [UUID: ImageTransform] = [:]

var activeImageTransform: ImageTransform {
    guard let id = activeImageID else { return .identity }
    return imageTransforms[id] ?? .identity
}

func rotateActiveImage(clockwise: Bool) {
    guard let id = activeImageID else { return }
    var transform = imageTransforms[id] ?? .identity
    if clockwise {
        transform.rotation.rotateCW()
    } else {
        transform.rotation.rotateCCW()
    }
    imageTransforms[id] = transform
}

func flipActiveImage(horizontal: Bool) {
    guard let id = activeImageID else { return }
    var transform = imageTransforms[id] ?? .identity
    if horizontal {
        transform.flipHorizontal.toggle()
    } else {
        transform.flipVertical.toggle()
    }
    imageTransforms[id] = transform
}
```

### Tasks

| # | Task | File | Status |
|---|------|------|--------|
| 3.1 | Create `ImageTransform.swift` model | `Models/ImageTransform.swift` | Pending |
| 3.2 | Add `imageTransforms` dictionary | `AppState.swift` | Pending |
| 3.3 | Add rotate/flip methods | `AppState.swift` | Pending |
| 3.4 | Implement `applyTransform()` | `ImageCropService.swift` | Pending |
| 3.5 | Implement `rotate()` method | `ImageCropService.swift` | Pending |
| 3.6 | Implement `flip()` method | `ImageCropService.swift` | Pending |
| 3.7 | Update `batchCrop()` pipeline | `ImageCropService.swift` | Pending |
| 3.8 | Add rotation toolbar buttons | `ActionButtonsView.swift` | Pending |
| 3.9 | Apply transform in preview | `CropEditorView.swift` | Pending |
| 3.10 | Handle dimension swap for crop overlay | `CropEditorView.swift` | Pending |

> **Doc check (2025-12-27):** Task 1.4 earlier mentions “slider commit” in `CropSettingsView`, but that UI only offers text fields and buttons—no sliders to trigger `recordCropChange()`. Clarify what control needs the commit hook before implementation.

### Performance Note
**Recommendation:** For optimal performance, especially with large batches or high-resolution images, the `Accelerate` framework (specifically `vImage`) should be used for rotation and flip operations. The `Core Graphics` and `AppKit` examples below are functionally correct but will be significantly slower. Implementing with `vImage` from the start is highly recommended to ensure a responsive user experience.

### Apple API Implementation

**Rotation using CGAffineTransform:**
```swift
// ImageCropService.swift
static func rotate(_ image: NSImage, by angle: RotationAngle) -> NSImage {
    guard angle != .none else { return image }
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return image
    }

    let radians = CGFloat(angle.rawValue) * .pi / 180
    let rotatedSize = angle.swapsWidthAndHeight
        ? CGSize(width: image.size.height, height: image.size.width)
        : image.size

    let newImage = NSImage(size: rotatedSize)
    newImage.lockFocus()

    let context = NSGraphicsContext.current!.cgContext
    context.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
    context.rotate(by: radians)
    context.translateBy(x: -image.size.width / 2, y: -image.size.height / 2)
    context.draw(cgImage, in: CGRect(origin: .zero, size: image.size))

    newImage.unlockFocus()
    return newImage
}
```

**Flip using NSAffineTransform:**
```swift
static func flip(_ image: NSImage, horizontal: Bool, vertical: Bool) -> NSImage {
    guard horizontal || vertical else { return image }

    let newImage = NSImage(size: image.size)
    newImage.lockFocus()

    guard let context = NSGraphicsContext.current else {
        newImage.unlockFocus()
        return image
    }
    
    context.saveGraphicsState()

    let transform = NSAffineTransform()
    transform.translateX(by: horizontal ? image.size.width : 0,
                         yBy: vertical ? image.size.height : 0)
    transform.scaleX(by: horizontal ? -1 : 1, yBy: vertical ? -1 : 1)
    transform.concat()

    image.draw(at: .zero, from: .zero, operation: .copy, fraction: 1.0)
    
    context.restoreGraphicsState()

    newImage.unlockFocus()
    return newImage
}
```

**Combined transform application:**
```swift
static func applyTransform(_ image: NSImage, transform: ImageTransform) -> NSImage {
    guard !transform.isIdentity else { return image }

    var result = image

    // Apply rotation first
    if transform.rotation != .none {
        result = rotate(result, by: transform.rotation)
    }

    // Then apply flip
    if transform.flipHorizontal || transform.flipVertical {
        result = flip(result, horizontal: transform.flipHorizontal, vertical: transform.flipVertical)
    }

    return result
}
```

### Keyboard Shortcuts
| Action | Shortcut |
|--------|----------|
| Rotate CW | Cmd+] |
| Rotate CCW | Cmd+[ |
| Flip Horizontal | Cmd+Option+H |
| Flip Vertical | Cmd+Option+V |

---

## Processing Pipeline Order

```
Original Image
      |
      v
+------------------+
| 1. TRANSFORM     |  <-- Apply rotation/flip FIRST
|    (rotate/flip) |      (changes dimensions!)
+------------------+
      |
      v
+------------------+
| 2. BLUR          |
|    (redact)      |
+------------------+
      |
      v
+------------------+
| 3. CROP          |  <-- Crop relative to
|    (edges)       |      transformed size
+------------------+
      |
      v
+------------------+
| 4. RESIZE        |
|    (scale)       |
+------------------+
      |
      v
+------------------+
| 5. RENAME + SAVE |
|    (export)      |
+------------------+
```

**Updated batchCrop signature:**
```swift
static func batchCrop(
    items: [ImageItem],
    cropSettings: CropSettings,
    exportSettings: ExportSettings,
    transforms: [UUID: ImageTransform] = [:],  // NEW
    blurRegions: [UUID: ImageBlurData] = [:],
    progress: @escaping @MainActor (Double) -> Void
) async throws -> [URL]
```

---

## Files Summary

| File | Action | Features |
|------|--------|----------|
| `Models/ImageTransform.swift` | **CREATE** | Rotation |
| `Models/AppState.swift` | Modify | Rotation, Undo/Redo verification |
| `Models/ExportSettings.swift` | Modify | Batch Rename |
| `Services/ImageCropService.swift` | Modify | Rotation, Batch Rename |
| `Views/ActionButtonsView.swift` | Modify | Undo/Redo buttons, Rotation buttons |
| `Views/CropEditorView.swift` | Modify | Rotation preview |
| `Views/ExportSettingsView.swift` | Modify | Batch Rename UI |
| `CropBatchApp.swift` | Modify | Edit menu commands |

---

## Implementation Order

1. **Undo/Redo** - Quick win, infrastructure exists
2. **Image Rotation** - Core feature, impacts preview
3. **Batch Rename** - Independent, add last

---

## Apple API References

| Feature | Framework | Key APIs |
|---------|-----------|----------|
| Rotation | Core Graphics | `CGContext.rotate(by:)`, `CGAffineTransformMakeRotation` |
| Flip | AppKit | `NSAffineTransform.scaleX(by:yBy:)` |
| High-perf Rotation | Accelerate | `vImageRotate90_ARGB8888` |
| High-perf Flip | Accelerate | `vImageHorizontalReflect_ARGB8888` |
| Undo/Redo | Foundation | `UndoManager` (optional migration) |
| Edit Menu | SwiftUI | `CommandGroup(replacing: .undoRedo)` |

---

## Documentation Sources

- [CGAffineTransform](https://developer.apple.com/documentation/coregraphics/cgaffinetransform)
- [Image Rotation (Accelerate)](https://developer.apple.com/documentation/accelerate/image-rotation)
- [Image Reflection (Accelerate)](https://developer.apple.com/documentation/accelerate/image-reflection)
- [UndoManager](https://developer.apple.com/documentation/foundation/undomanager)
- [SwiftUI Environment undoManager](https://developer.apple.com/documentation/swiftui/environmentvalues/undomanager)
- [NSImage](https://developer.apple.com/documentation/appkit/nsimage)
