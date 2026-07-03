# Decisions Log

This file tracks the WHY behind technical and design decisions.

---

## Decisions

### 2026-07-03 - REAL WebP export: SDWebImageWebPCoder (lossy) + direct libwebp (lossless)
**Context:** WebP export shipped broken — ImageIO/CGImageDestination cannot encode WebP on macOS; every write failed since the option appeared.
**Decision:** Lossy WebP via SDWebImageWebPCoder 0.15.0 (SPM, ~2-4 MB binary growth). Lossless WebP bypasses the coder and calls the libwebp C API directly with `picture.use_argb = 1`.
**Rationale:** The coder hardcodes `use_argb = 0` (YUV420) even for lossless — pixels get chroma-subsampled *before* the "lossless" VP8L encode (upstream issue #116). Verified with cwebp/dwebp reference tools: coder path had maxDelta 59 vs source; direct path is 0-diff bit-exact at ~50% of PNG size.
**Consequences:** One extra product dependency (libwebp, already transitive). Quality slider doubles as compression effort in lossless mode (label flips to "Effort"). Coder NOT registered with SDImageCodersManager (encode-only, one call site). sRGB conversion before lossy encode keeps color consistent with PNG/JPEG paths. `method=6` hardcoded as tunable constant in WebPEncoder.

### 2026-07-03 - Hand-authored pbxproj fragments for remote SPM packages
**Context:** WebP plan assumed SPM adds require Xcode GUI; the earlier hand-edit failure was a *local* package (fragile relativePath).
**Decision:** Remote SPM packages (SDWebImageWebPCoder, libwebp) and the missing CropBatchTests target were hand-authored in pbxproj, mirroring the existing Sparkle fragments; validated via `xcodebuild -resolvePackageDependencies` + full test run.
**Rationale:** Remote refs are just URL+version — no path to break. UUIDs are arbitrary 24-hex, uniqueness is the only requirement.
**Consequences:** Test target restored (was silently lost in a project regen — test files existed on disk but never ran). 31 tests green.

### 2026-07-03 - Watermark images decoded per-call for thread safety
**Context:** `batchCrop`'s TaskGroup called `WatermarkSettings.loadedImage` concurrently; every settings copy shared one `cachedImage` NSImage reference (NSImage is not thread-safe).
**Decision:** `loadedImage` decodes a fresh NSImage from `imageData` on every call; `cachedImage` is main-thread-only for view previews.
**Rationale:** Small decode cost per image vs. intermittent crash/torn-watermark risk under concurrency.
**Consequences:** Watermark PNG decoded ~2× per exported image — negligible against the full pipeline.

### 2026-01-06 - Corner Radius PNG Constraint
**Context:** Adding rounded corner cropping for macOS window screenshots
**Decision:** Force PNG format when corner radius is enabled
**Rationale:** JPEG doesn't support transparency - corners would appear white/black instead of transparent
**Consequences:** Users can't export JPEG with rounded corners, but this is the only correct behavior

---

### 2026-01-06 - Image Processing Pipeline Order
**Context:** Multiple image transformations need to be applied in correct sequence
**Decision:** Blur → Transform → Crop → Corner Mask → Resize → Watermark
**Rationale:** Each step depends on the previous; corner mask must come after crop but before resize to work on final pixel dimensions
**Consequences:** Adding new processing steps requires careful placement in pipeline

---

### 2026-01-02 - Watermark Position System
**Context:** Need flexible watermark positioning
**Decision:** 9-position anchor grid + margin + X/Y offset + drag-to-position
**Rationale:** Covers common use cases (corners, center) while allowing pixel-precise adjustments
**Consequences:** More complex UI but covers all positioning needs

---

### 2025-12 - Platform Requirements
**Context:** Setting baseline platform support
**Decision:** macOS 15.0+, Swift 6.0, Xcode 16+
**Rationale:** Use latest Swift concurrency features, SwiftUI improvements
**Consequences:** Limits user base to recent macOS versions

---
*Add decisions as they are made. Future-you will thank present-you.*
