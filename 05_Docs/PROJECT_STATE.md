# Project State

> **Size limit: <100 lines.** This is a digest, not an archive.

## Identity
- **Project:** CropBatch
- **One-liner:** macOS app for batch cropping images with consistent settings
- **Started:** December 2025

## Current Position
- **Phase:** polish
- **Focus:** v1.4 release prep (build .dmg, notarize, appcast, GitHub release)
- **Status:** all bugs fixed, clean build, testing complete
- **Last updated:** 2026-04-03

## Progress
```
[###################.] 95% - v1.4 code complete, release prep remaining
```

| Phase | Status | Notes |
|-------|--------|-------|
| Discovery | done | Born from iOS screenshot cropping need |
| Planning | done | Feature set defined, 61+ public downloads |
| Implementation | done | v1.3 shipped, v1.4 code complete |
| Polish | **active** | "Works for me" level — no edge case obsession |

## Tech Stack
- macOS 15.0+ / Swift 6.0 / SwiftUI / Xcode 16+
- Notarized for distribution (not sandboxed)
- Processing pipeline: Transform → Crop → Blur → Corner Mask → Grid Split → Resize → Watermark
- Auto-update: Sparkle 2.8.1
- Logging: os.Logger (CropBatchLogger: ui, export, storage)

## v1.4 Changes (since v1.3)
- Grid Split feature (GUI + CLI)
- ContentView refactor (1,785→258 lines, SidebarComponents/)
- `@MainActor` on all 5 Observable classes (Swift 6 safety)
- FolderWatcher structured concurrency (Task.sleep)
- Watermark load error feedback (inline label)
- Watermark drop `isSecurityScoped: true`
- Image flash fix on thumbnail switch (.resizable() on cache miss path)
- Blur export coordinates fix (pipeline reorder)
- Corner radius auto-switches format to PNG
- Build number 140, Xcode recommended settings upgrade

## Active Decisions
- 2026-04-03: Blur pipeline reorder (Transform → Crop → Blur) — fixes coordinate shift
- 2026-04-03: Corner radius auto-PNG — saves/restores previous format on toggle
- 2026-04-03: Blur UX improvements deferred to v1.5 (live preview, unified tool)
- 2026-03-31: Pipeline deduplication — `processImageThroughPipeline` is single source of truth
- ~Dec 2025: No persistence needed — "use and close" tool

## Blockers
[None]

## Next Actions
- Build .dmg, notarize, sign with sparkle_generate_signature
- Update appcast.xml (sparkle:version="140", sparkle:shortVersionString="1.4")
- Create GitHub release with .dmg
- v1.5 planning: blur live preview, unified crop+blur tool, undo/redo toolbar, keyboard shortcuts popover

---
*Updated by Claude. Source of truth for project position.*
