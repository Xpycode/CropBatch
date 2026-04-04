# Project State

> **Size limit: <100 lines.** This is a digest, not an archive.

## Identity
- **Project:** CropBatch
- **One-liner:** macOS app for batch cropping images with consistent settings
- **Started:** December 2025

## Current Position
- **Phase:** released
- **Focus:** v1.5 — unified crop/blur tool (plan ready, implementation next)
- **Status:** v1.4 released, v1.5 plan complete
- **Last updated:** 2026-04-03

## Progress
```
[####################] 100% - v1.4 released
```

| Phase | Status | Notes |
|-------|--------|-------|
| Discovery | done | Born from iOS screenshot cropping need |
| Planning | done | Feature set defined, 61+ public downloads |
| Implementation | done | v1.4 shipped |
| Polish | done | "Works for me" level |
| Release | **done** | v1.4 live, Sparkle auto-update works |

## Tech Stack
- macOS 15.0+ / Swift 6.0 / SwiftUI / Xcode 16+
- Notarized for distribution (not sandboxed)
- Processing pipeline: Transform → Crop → Blur → Corner Mask → Grid Split → Resize → Watermark
- Auto-update: Sparkle 2.8.1
- Logging: os.Logger (CropBatchLogger: ui, export, storage)

## v1.4 Release (2026-04-03)
- Grid Split feature (GUI + CLI)
- ContentView refactor (1,785→258 lines)
- @MainActor on all Observable classes
- Blur export coordinates fix (pipeline reorder)
- Corner radius auto-PNG
- ColorPicker fix in watermark settings
- Image flash fix on thumbnail switch
- Watermark error feedback + isSecurityScoped
- FolderWatcher structured concurrency

## Blockers
[None]

## Next Actions (v1.5)
- **[DONE]** Unified crop+blur tool — Waves 1-3 implemented (live preview, no segmented picker, B toggle)
- **[TODO]** Wave 4: Pixelate live preview, cached composite performance
- **[TODO]** Global blur regions — blur should apply to all images by default, with per-image opt-out/override
- Undo/redo toolbar buttons for discoverability
- Keyboard shortcuts as toolbar popover (instead of sidebar section)
- Folder watcher GUI (currently CLI-only)
- Snap-to-edge: consider minimum edge strength filter for natural photos (too noisy on organic images)

---
*Updated by Claude. Source of truth for project position.*
