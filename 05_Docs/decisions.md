# Decisions Log

This file tracks the WHY behind technical and design decisions.

---

## Decisions

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
