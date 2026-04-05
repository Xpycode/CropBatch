# Project State

> **Size limit: <100 lines.** This is a digest, not an archive.

## Identity
- **Project:** CropBatch
- **One-liner:** macOS app for batch cropping images with consistent settings
- **Started:** December 2025

## Current Position
- **Phase:** development
- **Focus:** v1.5 feature-complete on `feature/unified-blur-crop` — testing before merge
- **Status:** All v1.5 features implemented (10 waves across 2 sessions)
- **Last updated:** 2026-04-04

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

## v1.5 (on `feature/unified-blur-crop` — testing)
- **[DONE]** Unified crop/blur canvas — live blur preview, no mode switching, z-order crop dimming
- **[DONE]** Pixelate live preview via CIPixellate + BlurPreviewCache (100ms debounce)
- **[DONE]** 3-tab sidebar (Crop / Effects / Export) — replaces 12 flat sections
- **[DONE]** Keyboard shortcuts → toolbar `?` popover
- **[DONE]** Undo/redo toolbar buttons (left side)
- **[DONE]** Global blur regions — apply to all images, per-image skip/customize override
- **[DONE]** Folder Watcher GUI wired into Export tab
- **[DONE]** Snap edge sensitivity slider (Low/Med/High)

## Next Actions
- Test all v1.5 features, commit, merge to main
- Bump version, build DMG, update appcast, release

---
*Updated by Claude. Source of truth for project position.*
