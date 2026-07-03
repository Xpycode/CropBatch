# Project State

> **Size limit: <100 lines.** This is a digest, not an archive.

## Identity
- **Project:** CropBatch
- **One-liner:** macOS app for batch cropping images with consistent settings
- **Started:** December 2025

## Current Position
- **Phase:** development
- **Focus:** Two threads — (1) in-app Help via `HelpMenu` package (content + screenshots done, integration pending); (2) REAL WebP export (plan ready, awaiting Xcode SPM add)
- **Status:** v1.5 features done. Repo reconnected to GitHub. Help content + 6 lean screenshots ready; WebP export found broken (ships but fails), fix plan written for v1.6.
- **Last updated:** 2026-06-02

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
- ~~CropBatch is **not under git**~~ — RESOLVED 2026-05-31: reconnected to `github.com/Xpycode/CropBatch`, history + tags v1.0–v1.4 restored, post-v1.4 work committed & pushed.
- In-app Help: **MarkdownUI local-image resolution unverified** — `![](file.jpg)` won't resolve without an `imageProvider`/`file://` URL in the `HelpMenu` renderer (owned by appHELP). Confirm before shipping or help shows broken-image placeholders.

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
- Wave E: ~~`git init`~~ (done), bump 1.5→1.6, build DMG, notarize, update appcast

### In-app Help (via `HelpMenu` package — appHELP project)
- Content + 6 lean screenshots done (`01_Project/CropBatch/Help/`, 632KB JPEGs, refs wired). Still **untracked** → commit on `feature/in-app-help`
- Verify/add MarkdownUI bundled-image provider so `![](file.jpg)` renders (see Blockers); build + open Help window to confirm
- Wire the `HelpMenu` Swift package into the CropBatch target (the earlier pbxproj edit was broken/discarded) so the Help menu actually opens in-app

### Carryover
- Test all v1.5 features (blur global/override, sidebar tabs, snap sensitivity, undo/redo, flat toolbar)
- Ship v1.5 (version bump, DMG, appcast) if not folding into v1.6

---
*Updated by Claude. Source of truth for project position.*
