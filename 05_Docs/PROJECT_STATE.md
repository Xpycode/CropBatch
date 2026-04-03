# Project State

> **Size limit: <100 lines.** This is a digest, not an archive.

## Identity
- **Project:** CropBatch
- **One-liner:** macOS app for batch cropping images with consistent settings
- **Started:** December 2025

## Current Position
- **Phase:** polish
- **Focus:** Production hardening (PLAN.md Wave 1+2) → manual test → v1.4 release
- **Status:** clean build, zero errors — fix plan ready
- **Last updated:** 2026-04-03

## Progress
```
[##################..] 85% - Grid Split + quality fixes done
```

| Phase | Status | Notes |
|-------|--------|-------|
| Discovery | done | Born from iOS screenshot cropping need |
| Planning | done | Feature set defined, 61+ public downloads |
| Implementation | done | v1.2 shipped |
| Polish | **active** | "Works for me" level — no edge case obsession |

## Tech Stack
- macOS 15.0+ / Swift 6.0 / SwiftUI / Xcode 16+
- Notarized for distribution (not sandboxed)
- Processing pipeline: Blur → Transform → Crop → Corner Mask → Grid Split → Resize → Watermark
- Auto-update: Sparkle 2.8.1
- Logging: os.Logger (CropBatchLogger: ui, export, storage)

## Active Decisions
- 2026-04-03: Production review (pre-v1.4): 1 High + 3 Medium issues, ThumbnailCache TOCTOU dismissed as false positive (actor prevents race). Fix plan in PLAN.md.
- 2026-04-03: Watermark load error → inline label preferred over alert (lower friction for retry)
- 2026-04-03: ExportSettingsView file size (1,484 lines) deferred — "works for me" policy
- 2026-03-31: Pipeline deduplication — `processImageThroughPipeline` is single source of truth
- 2026-03-31: ContentView split — 1,785→258 lines, views in SidebarComponents/
- 2026-01-12: v1.2 released (corner radius, blur intensity, Sparkle auto-update)
- ~Dec 2025: No persistence needed — "use and close" tool
- ~Dec 2025: No Mac App Store yet (setup complexity)

## Blockers
[None]

## Next Actions
- **Wave 1:** Add `@MainActor` to 5 Observable classes + fix FolderWatcher asyncAfter + fix drop handler security scope (see PLAN.md)
- **Wave 2:** Watermark load failure — inline error label in UI
- Wire up test target in Xcode (File > New > Target > Unit Testing Bundle → CropBatchTests/)
- Manual test grid split end-to-end (GUI: enable 3×3, export, verify 9 tiles; CLI: --grid-rows 3 --grid-cols 3)
- v1.4 release prep (version bump, appcast, notarize)

---
*Updated by Claude. Source of truth for project position.*
