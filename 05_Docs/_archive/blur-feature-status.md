# Blur/Redact Feature - Implementation Status

**Last Updated:** 2025-12-29
**Status:** SHELVED (UI hidden, code preserved)
**Branch:** `feature/blur-reimplementation`

---

## Current State

The blur tool UI is **hidden** but all code is preserved. The feature works for non-transformed images but has unresolved coordinate issues when images are rotated/flipped.

**To re-enable:** In `ContentView.swift` line ~191, remove the `.filter { $0 != .blur }`:
```swift
ForEach(EditorTool.allCases) { tool in  // Remove filter to show Blur
```

---

## What Works

- Drawing rectangular blur regions on images (at identity transform)
- Four blur styles: Gaussian Blur, Pixelate, Solid Black, Solid White
- Adjustable intensity for blur/pixelate
- Move and resize handles for regions
- Delete button (X) on hover
- Multiple regions per image
- Export with blur applied via Core Image
- Blur regions stored per-image in `ImageBlurData`

---

## Known Issue: Transform Coordinate Mismatch

**Problem:** When the image is rotated (90°/180°/270°) or flipped, blur regions don't follow the image content. The region stays at the same screen position rather than the same content position.

**Root Cause Analysis:**
1. Blur regions are stored in normalized coordinates (0.0-1.0)
2. When displayed, they need to be transformed from original→transformed space
3. When exported, they need to match the transformed image coordinates
4. Despite multiple attempts at transform math, the coordinates don't map correctly

**Approaches Attempted:**

### Attempt 1: Transform in NormalizedGeometry
Added `applyingTransform()` and `applyingInverseTransform()` methods:
```swift
// 90° CW: (x, y) → (1-y, x)
// 270° CW: (x, y) → (y, 1-x)
// 180°: (x, y) → (1-x, 1-y)
```
**Result:** Math appears correct on paper but doesn't work in practice.

### Attempt 2: Fix Export Pipeline
Transform blur coords in `ImageCropService.processAndSave()` before applying:
```swift
let transformedRegions = imageBlurData.regions.map { region in
    var transformed = region
    transformed.normalizedRect = region.normalizedRect.applyingTransform(currentTransform)
    return transformed
}
```
**Result:** Still doesn't align correctly.

### Attempt 3: Remove GeometryReader Offset
Simplified BlurEditorView to use `displayOffset: .zero` since overlay matches image frame.
**Result:** No improvement.

---

## Architecture (Current)

```
Storage: Blur regions in ORIGINAL image normalized coords (0.0-1.0)
   ↓
Display: Apply forward transform → view coords
   ↓
Export: Transform stored coords → apply to transformed image
```

### Key Files

| File | Purpose |
|------|---------|
| `Models/BlurRegion.swift` | Data model with normalized coordinates |
| `Models/NormalizedGeometry.swift` | Coordinate conversion, transform methods |
| `Views/BlurEditorView.swift` | Main editor overlay (~700 lines) |
| `Views/BlurToolView.swift.old` | Old implementation (backup) |
| `Services/ImageCropService.swift` | Export blur via `applyBlurRegions()` |
| `ContentView.swift` | Tool selector (Blur currently filtered out) |

---

## Potential Solutions (Not Yet Tried)

### Option A: Store in Transformed Coords
Instead of storing in original image coords, store in transformed view coords.
- When transform changes, apply delta transform to all regions
- Simpler display (no transform needed)
- Export: coords already match transformed image

### Option B: Per-Render Approach
Don't persist blur regions during editing. Just render them live:
- User draws on transformed view
- Apply blur to live preview using view coords
- On export, capture current transform state and apply

### Option C: Mask-Based Blur
Use `CIFilter.maskedVariableBlur()` instead of per-region cropping:
- Create mask image with white rectangles
- Apply single blur pass using mask
- Simpler coordinate handling (mask drawn in same space as image)

### Option D: Debug with Coordinate Visualization
Add a debug overlay showing:
- Original image bounds
- Transformed bounds
- Blur region coords at each step
- Visual markers at corners

---

## Export Pipeline Order

```
1. Original Image
   ↓
2. Apply Transform (rotation/flip)
   ↓
3. Apply Blur Regions (to transformed image)
   ↓
4. Apply Crop
   ↓
5. Apply Resize
   ↓
6. Save
```

---

## How to Debug Further

1. **Add coordinate logging:**
```swift
print("Original normalized: \(region.normalizedRect)")
print("Transform: \(transform)")
print("Transformed: \(region.normalizedRect.applyingTransform(transform))")
```

2. **Visual debugging:**
```swift
// Draw coordinate markers at (0,0), (0.5,0.5), (1,1) to verify transform
```

3. **Test with identity transform first:**
Verify blur works perfectly at 0° before testing rotations.

---

## Re-enabling Checklist

When ready to fix this feature:

1. [ ] Create test branch from `feature/blur-reimplementation`
2. [ ] Add coordinate debug overlay
3. [ ] Verify identity transform works
4. [ ] Test each rotation (90, 180, 270) separately
5. [ ] Test flips
6. [ ] Test combined transform (rotate + flip)
7. [ ] Verify export matches preview
8. [ ] Remove debug overlay
9. [ ] Merge

---

## Files to Review

All blur-related code is in place and functional except for transform handling:

- `BlurEditorView.swift` - Unified gesture state machine, simplified preview
- `NormalizedGeometry.swift` - Transform methods (may have bugs)
- `ImageCropService.swift:611-620` - Export transform handling
- `ContentView.swift:191` - Tool selector (blur filtered out)
