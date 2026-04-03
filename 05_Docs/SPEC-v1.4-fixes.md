# Spec: v1.4 Bug Fixes & Polish

**Created:** 2026-04-03
**Target:** v1.4 (build 140, unreleased)

---

## Overview

Fixes found during v1.4 pre-release testing. Two bugs (one High, one Medium) and several polish items.

---

## Bug 1 — HIGH: Blur region coordinates shifted in export

### Problem
Blur regions render at wrong coordinates in exported images — shifted upward relative to where the user placed them. The shift equals the `cropTop` pixel value.

### Root Cause
Pipeline order in `ImageCropService.processImageThroughPipeline` (line 883):

```
Blur → Transform → Crop → Corner Mask → Grid → Resize → Watermark
```

Blur is applied at **original-image pixel coordinates** (step 1), then crop removes pixels from edges (step 3). A blur region placed at normalized Y=0.3 in a 3000px image is baked at pixel Y=900. After cropping 400px from the top, the blur appears at Y=500 in the output — but the user expected it at Y=0.3 of the *cropped* image (which would be Y≈(3000-400)*0.3 = 780).

The user draws blur regions while viewing the cropped preview, so they expect coordinates relative to the crop area, not the full original image.

### Fix

**Option A (recommended): Reorder pipeline — apply blur after crop**

Change pipeline order to:
```
Transform → Crop → Blur → Corner Mask → Grid → Resize → Watermark
```

This way blur coordinates (stored in original-image space) need to be remapped to post-crop space. The infrastructure already exists:

- `ImageBlurData.regionsForExport(cropSettings, imageSize:)` — `BlurRegion.swift:115-121`
- `NormalizedRect.relativeToCrop(_:)` — `NormalizedGeometry.swift:392-402`
- Clips blur rects to crop area, re-normalizes to cropped coordinate space

In `processImageThroughPipeline`, after crop, call:
```swift
let croppedRegions = imageBlurData.regionsForExport(cropSettings, imageSize: item.originalImage.size)
processedImage = applyBlurRegions(processedImage, regions: croppedRegions)
```

Also need to update the transform handling: currently blur regions stored in original space are inverse-transformed before storage (BlurEditorView line 148). After this change, the transform coordinates need to be applied before `relativeToCrop`, which already happens since regions are stored in original space and transforms apply naturally.

**Option B: Keep order, adjust coordinates before blur**

Remap coordinates in-place before applying blur to account for crop offset. More fragile — requires manual coordinate math instead of using existing `regionsForExport`.

### Files to Modify
- `Services/ImageCropService.swift` — `processImageThroughPipeline` (line 883+): reorder blur step after crop+transform
- Verify: `BlurRegionsCropPreview` (BlurEditorView.swift:536) — crop-mode preview already shows regions relative to transformed space, should remain correct

### Acceptance Criteria
- [ ] Place blur region in crop mode, export — blur appears at same position as the overlay
- [ ] Blur region partially outside crop area — only the visible portion is blurred
- [ ] Blur region fully outside crop area — no blur applied
- [ ] Blur + rotation + crop — coordinates correct
- [ ] Blur without crop (T=0, B=0, L=0, R=0) — unchanged behavior

---

## Bug 2 — MEDIUM: Corner radius doesn't auto-set PNG format

### Problem
Enabling corner radius requires PNG (transparency), but the format picker stays on whatever the user selected (JPEG, HEIC, etc.). The pipeline silently overrides to PNG at export (`ImageCropService.swift:924-925`), but the UI still shows the non-PNG format. This is confusing — the "Output" label shows `.heic` but the file exports as `.png`.

A small caption at the bottom of the corner radius controls says "Exports as PNG for transparency" (`CropControlsView.swift:67`), but it's `.caption2` in `.tertiary` color — easy to miss.

### Fix

When `cornerRadiusEnabled` is toggled ON:
1. Save the user's current format choice (so it can be restored)
2. Switch `exportSettings.format` to `.png`
3. Optionally disable the format picker while corner radius is on (with a caption explaining why)

When toggled OFF:
1. Restore the saved format

### Files to Modify
- `Views/SidebarComponents/CropControlsView.swift` — add `onChange(of: cornerRadiusEnabled)` to switch format
- `Views/SidebarComponents/ExportFormatView.swift` or wherever `FormatPicker` is used — disable picker when corner radius is on
- Optionally: `Models/CropSettings.swift` — store `previousFormat` for restore

### Acceptance Criteria
- [ ] Enable corner radius → format picker switches to PNG
- [ ] Disable corner radius → format picker restores previous selection
- [ ] Corner radius ON: format picker shows PNG, visually indicates it's locked
- [ ] Output filename preview shows `.png` extension when corner radius is on

---

## Polish Items (lower priority, not blocking v1.4)

These were noted during testing. Can be deferred to v1.5 if time is tight.

### P1: Blur preview should show actual blur effect in crop mode

**Current:** `BlurRegionsCropPreview` (BlurEditorView.swift:536) renders colored semi-transparent rectangles with dashed borders — position indicators only, not actual blur.

**Desired:** Show a real-time blurred preview so the user can see the effect without exporting. This requires applying `CIFilter` blur to the visible image region in the overlay.

**Complexity:** Medium-high. Need to extract the image area under each blur region, apply CIFilter, and render as an overlay. Performance concern with large images.

### P2: Unify blur into crop workflow

**Current:** Crop and Blur are separate tools in a segmented picker. The user must switch modes — can't draw blur regions while seeing crop handles.

**Desired:** Blur as an always-available option within the crop tool, perhaps as a toolbar button or modifier key (hold B to draw blur, release to return to crop). The blur regions preview already appears in crop mode — just needs interactive drawing.

**Complexity:** Medium. The gesture systems (crop drag vs blur draw) need to coexist. Could use a modifier key or a floating toolbar button.

### P3: Undo/redo toolbar buttons

**Current:** Undo/redo works via Cmd+Z / Cmd+Shift+Z but has no visible toolbar buttons.

**Desired:** Add undo/redo buttons to the toolbar for discoverability.

**Complexity:** Low. Add two `ToolbarItem`s with undo/redo actions.

### P4: Keyboard shortcuts as toolbar overlay

**Current:** Keyboard shortcuts are in a collapsible sidebar section at the bottom.

**Desired:** A toolbar button (e.g., keyboard icon) that shows a floating overlay/popover with all shortcuts. Dismisses on click outside.

**Complexity:** Low. Popover or sheet triggered from toolbar button.

### P5: Grid Split sidebar position

**Current position:** Between Format and Quality & Resize. This matches pipeline order (crop → format → grid → resize → watermark).

**Assessment:** Current position is correct. No change needed.

### P6: Folder watcher GUI

**Current:** CLI-only feature. No GUI toggle exists.

**Desired:** Optional — add a menu item or sidebar section to watch a folder for new images.

**Complexity:** Medium. Need folder picker, start/stop toggle, status indicator.

---

## Implementation Plan

### Wave 1 — Bug fixes (blocking v1.4)
- [ ] **1.1** Fix blur coordinate pipeline — reorder blur after crop, use `regionsForExport`
- [ ] **1.2** Fix corner radius auto-PNG — toggle format on enable/disable
- [ ] **1.3** Clean build
- [ ] **1.4** Test: blur + crop + export at various crop offsets
- [ ] **1.5** Test: corner radius toggle switches format correctly

### Wave 2 — Polish (defer to v1.5 if needed)
- [ ] **2.1** Undo/redo toolbar buttons
- [ ] **2.2** Keyboard shortcuts popover

### Deferred
- Blur live preview in crop mode (P1)
- Unified crop+blur tool (P2)
- Folder watcher GUI (P6)

---

*Source: v1.4 pre-release testing session 2026-04-03b*
