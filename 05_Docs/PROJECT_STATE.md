# Project State

> **Size limit: <100 lines.** This is a digest, not an archive.

## Identity
- **Project:** CropBatch
- **One-liner:** macOS app for batch cropping images with consistent settings
- **Started:** December 2025

## Current Position
- **Phase:** development
- **Focus:** REAL WebP export — plan ready, awaiting Xcode SPM package add
- **Status:** v1.5 features done. WebP export found broken (ships but fails); fix plan written for v1.6.
- **Last updated:** 2026-05-29

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
- WebP export is **broken** — `.webp` case + 2 presets + sidebar button ship, but all writes route through ImageIO/`CGImageDestination`, which cannot encode WebP on macOS (verified: writable = false on 26.5). Plan written to fix via SDWebImageWebPCoder.
- CropBatch is **not under git** — `git init` needed before the WebP change ships.

## Deferred to v2.0
- (none currently)

## v1.5 (merged to main — UI polish on `feature/ui-polish`)
- **[DONE]** Unified crop/blur canvas — live blur preview, no mode switching, z-order crop dimming
- **[DONE]** Pixelate live preview via CIPixellate + BlurPreviewCache (100ms debounce)
- **[DONE]** 3-tab sidebar (Crop / Effects / Export) — replaces 12 flat sections
- **[DONE]** Keyboard shortcuts → toolbar `?` popover
- **[DONE]** Undo/redo toolbar buttons (left side)
- **[DONE]** Global blur regions — apply to all images, per-image skip/customize override
- **[DONE]** Folder Watcher GUI wired into Export tab
- **[DONE]** Snap edge sensitivity slider (Low/Med/High)
- **[DONE]** Flat toolbar buttons — FCPToolbarButtonStyle + .hiddenTitleBar + UIDesignRequiresCompatibility

## Next Actions
### REAL WebP export (v1.6) — plan: `POLISH_PLAN_webp_support.md`
- **User:** add SDWebImageWebPCoder 0.15.0 package in Xcode (File ▸ Add Package Dependencies → CropBatch target) — Wave A
- Wave B: `WebPEncoder.swift` + `lossless` model plumbing; branch `save()` + `encode()`; forward flag from AppState:621 / FolderWatcher:148 / processSingleImage:1019; CLI `webp` case + `--lossless`
- Wave C: Lossless toggle + Quality↔Effort label flip (both UIs); FileSizeEstimator lossless branch
- Wave D: smoke-test all 6 export flows + profile persistence round-trip
- Wave E: `git init`, bump 1.5→1.6, build DMG, notarize, update appcast

### Carryover
- Test all v1.5 features (blur global/override, sidebar tabs, snap sensitivity, undo/redo, flat toolbar)
- Ship v1.5 (version bump, DMG, appcast) if not folding into v1.6

---
*Updated by Claude. Source of truth for project position.*
