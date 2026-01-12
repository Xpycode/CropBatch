# How to Properly Employ Blur (and Fix the Bugs)

**Date:** 2026-01-04
**Context:** addressing the "Shelved" status of the Blur feature due to coordinate transform bugs.

## 1. The Core Principle: "Blur First, Transform Later"

The historical hurdles with the blur feature stemmed from a "Coordinate Space Mismatch". The previous implementation tried to map blur regions (defined on the original image) onto a rotated/flipped image. This requires complex and error-prone coordinate math (`Original -> View -> Transformed -> Export`).

The **proper** way to employ blur in a non-destructive editor is to anchor the blur to the **source content**, not the screen.

### The Fix: Pipeline Reordering

**Current (Buggy) Pipeline:**
`Original Image` -> `Rotate/Flip` -> `Apply Blur (with complex math)` -> `Crop` -> `Save`

**Recommended (Robust) Pipeline:**
`Original Image` -> `Apply Blur (No math)` -> `Rotate/Flip` -> `Crop` -> `Save`

By applying the blur to the original image *before* any rotation or flip:
1.  We use the stored `NormalizedRect` (0.0-1.0) directly. No `applyingTransform` logic is needed.
2.  The blur naturally rotates *with* the image because it's baked into the pixels before rotation occurs.
3.  This eliminates 100% of the export bugs described in `blur-feature-status.md`.

## 2. The UI Strategy: "Rotate the View, Not the Pixels"

The second hurdle was the UI. The user draws a box on a rotated image, but the system stores it in "original" space.

**Current Approach:**
The app generates a new `NSImage` with rotation applied (baking pixels), then displays it. This forces the `BlurEditorView` to mathematically transform its overlay to match the new pixel data. This is where the "Math appears correct but fails" bug lives.

**Recommended Approach:**
Instead of rotating the *pixels* (`NSImage`) for display, rotate the **SwiftUI View**.

1.  **Keep the Displayed Image Original:** pass the *unrotated* `NSImage` to the editor.
2.  **Keep the Overlay Original:** Render the blur regions using their original 0.0-1.0 coordinates.
3.  **Rotate the Container:**
    ```swift
    ZStack {
        Image(nsImage: originalImage)
        BlurEditorView(regions: regions) // Renders in 0..1 space
    }
    .rotationEffect(currentRotation)
    .scaleEffect(x: isFlipped ? -1 : 1, y: 1)
    ```
4.  **Benefits:**
    *   **Zero Math:** The overlay and image are always in sync because they share the same coordinate space (Original).
    *   **Performance:** No need to generate large rotated `NSImage` bitmaps on the CPU. Core Animation handles the rotation on the GPU.
    *   **Accuracy:** What you see is exactly what you get.

## 3. Implementation Steps

### Step A: Fix `ImageCropService.swift` (Export)
Modify `processSingleImage` to apply blur *before* the transform.

```swift
// 1. Apply blur (Original Space)
if let blurData = blurRegions[item.id] {
    processedImage = applyBlurRegions(processedImage, regions: blurData.regions)
}

// 2. Apply Transform
if !transform.isIdentity {
    processedImage = try applyTransform(processedImage, transform: transform)
}

// 3. Crop...
```

### Step B: Fix `CropEditorView.swift` (Display)
Refactor the view hierarchy to use SwiftUI transforms.

1.  Remove `displayedImage` logic that generates a rotated `NSImage`.
2.  Wrap the Image and Blur Overlay in a container.
3.  Apply `.rotationEffect(transform.rotation.angle)` to the container.
    *   *Note:* You will need to handle the frame size changes for layout (since `rotationEffect` doesn't affect flow layout). Use a `GeometryReader` to swap width/height constraints when rotated 90/270 degrees.

### Step C: Input Handling
When the user draws a new box on the rotated view:
1.  The `DragGesture` coordinates will be in the *local* (rotated) coordinate space of the view if the gesture is attached *inside* the rotation modifier.
2.  This means `(x, y)` from the gesture is *already* in "Original Image Space".
3.  We simply normalize it (`x / width`, `y / height`) and store it.
4.  **Result:** No inverse transform math needed!

## 4. Summary

To properly employ blur, stop fighting the geometry.
*   **Don't transform coordinates.**
*   **Do transform the View.**
*   **Do process the image in logical order (Blur -> Rotate).**
