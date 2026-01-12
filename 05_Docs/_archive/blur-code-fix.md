# Blur Code Fix Notes

## Blur Research Summary
- History: Blur tool was introduced (`a51f1fd`), then disabled (`73491f2`), and later shelved with UI hidden but code preserved (`7cb72ae`). A doc update (`94e6bff`) captured why it was shelved and the attempted fixes.
- Primary hurdle: blur regions drift when rotation/flip is applied. The stored normalized regions don’t map cleanly between original image coords, transformed display coords, and export coords. Attempts to fix this with `NormalizedGeometry.applyingTransform` and pre-transforming regions before export did not align. See `docs/blur-feature-status.md`.
- Secondary hurdles: transform order and coordinate conventions (top-left vs bottom-left) make it easy to apply the correct math in the wrong space. This risk is amplified by `NSImage.size` vs CGImage pixel size mismatches in blur rendering and export.

## How to Properly Employ Blur (Current Best Path)
1. Ensure a single, authoritative coordinate system: store regions in normalized ORIGINAL image space (0..1) and always convert via `NormalizedGeometry` when moving between view and CGImage.
2. Apply pipeline order consistently: Transform → Blur → Crop → Resize → Watermark → Save. This is documented and assumed by the blur math. See `docs/blur-feature-status.md`.
3. When exporting, transform blur regions to match the transformed image BEFORE applying blur. The logic in `ImageCropService.processSingleImage` does this; mirror it exactly in any other export path (rename-on-conflict, folder watcher, previews).
4. Use CGImage pixel sizes for blur rasterization. In `applyBlurRegions`, derive `imageSize` from `cgImage.width/height` and create the CGContext at pixel dimensions to avoid Retina drift.
5. If transforms remain problematic, consider Option C from the blur status doc: use a mask-based blur (single pass via `CIFilter.maskedVariableBlur()`), which centralizes coordinate handling to the mask render.
