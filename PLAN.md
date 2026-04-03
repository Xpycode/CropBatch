# Execution Plan: v1.4 Bug Fixes

## Goal
Fix blur coordinate bug and corner-radius auto-PNG before v1.4 release.

---

## Wave 1 (parallel — no dependencies between tasks)

### Task 1.1 — Fix blur coordinates: reorder pipeline
**File:** `Services/ImageCropService.swift`

In `processImageThroughPipeline` (line ~883), the current pipeline order is:
```
Blur → Transform → Crop → Corner Mask → Grid → Resize → Watermark
```

Change to:
```
Transform → Crop → Blur → Corner Mask → Grid → Resize → Watermark
```

After crop, blur regions need remapping from original-image space to cropped-image space.
Use the existing `regionsForExport` method:

```swift
// After crop, remap blur regions to post-crop coordinates and apply
if let imageBlurData = blurRegions[item.id], imageBlurData.hasRegions {
    let croppedRegions = imageBlurData.regionsForExport(cropSettings, imageSize: item.originalImage.size)
    processedImage = applyBlurRegions(processedImage, regions: croppedRegions)
}
```

**Important:** The transform must also be accounted for. Currently blur regions are stored
in original-image space (inverse-transformed on storage). The transform needs to be applied
to the blur coordinates before `relativeToCrop`, because `cropSettings` refers to the
transformed image dimensions. Use `region.normalizedRect.applyingTransform(transform)`
before passing to `relativeToCrop`.

Actually — looking more carefully: `regionsForExport` takes `cropSettings` and `imageSize`
(the original image size). The `cropArea` is built from crop pixel values divided by image
dimensions. If the image has been transformed (rotated), `imageSize` must be the
**transformed** size (width/height swapped for 90/270). And the regions must be in
transformed space too (via `applyingTransform`).

So the correct sequence after reordering is:
1. Apply transform to image
2. Crop the transformed image
3. Transform blur regions: `region.normalizedRect.applyingTransform(transform)`
4. Build crop area from `cropSettings` and **transformed** image size
5. Clip and remap each blur region via `relativeToCrop`
6. Apply remapped blur to the cropped image

**Success criteria:**
- [ ] Pipeline order is Transform → Crop → Blur → Corner Mask → Grid → Resize → Watermark
- [ ] Blur appears at correct coordinates in export matching the editor overlay position
- [ ] Blur regions outside crop area are not applied
- [ ] Blur regions partially outside crop area are clipped
- [ ] Blur with no crop (all zeros) works unchanged

---

### Task 1.2 — Corner radius auto-sets PNG format
**Files:** `Views/SidebarComponents/CropControlsView.swift`, `Views/SidebarComponents/ExportFormatView.swift`

When `cornerRadiusEnabled` is toggled ON:
1. Save current format to a `@State` or `@AppStorage` variable
2. Set `appState.exportSettings.format = .png`

When toggled OFF:
1. Restore the saved format

Also: in the format picker, when `cornerRadiusEnabled` is true, disable the picker
and show a caption like "PNG required for corner radius transparency".

The existing small caption at line 67 of CropControlsView ("Exports as PNG for transparency")
can stay, but the format picker itself should visually lock.

**Success criteria:**
- [ ] Enable corner radius → format switches to PNG
- [ ] Disable corner radius → format restores previous selection
- [ ] Format picker disabled/greyed when corner radius is on
- [ ] Output filename preview shows .png extension

---

## Wave 2 (depends on Wave 1 — verification)
- [ ] **2.1** Clean build, zero errors
- [ ] **2.2** Test: blur region placed inside crop area → correct position in export
- [ ] **2.3** Test: blur region at different crop offsets (large top crop, large bottom crop)
- [ ] **2.4** Test: corner radius toggle flips format to PNG and back
- [ ] **2.5** Test: blur + rotation + crop combo

## Definition of Done
- [ ] Blur exports at correct coordinates matching editor overlay
- [ ] Corner radius auto-switches format to PNG
- [ ] Clean build
- [ ] Ready for v1.4 release

---
*Created 2026-04-03. Supersedes production hardening plan (complete).*
