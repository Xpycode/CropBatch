# Project State

> **Size limit: <100 lines.** This is a digest, not an archive.

## Identity
- **Project:** CropBatch
- **One-liner:** macOS app for batch cropping images with consistent settings
- **Started:** December 2025

## Current Position
- **Phase:** development
- **Focus:** v1.6 ship prep (WebP done — version bump, DMG, notarize remain); in-app Help via `HelpMenu` package still pending
- **Status:** REAL WebP export **implemented & verified** on `feature/webp-real-support` (lossy via SDWebImageWebPCoder, lossless bit-exact via direct libwebp — see decisions.md 2026-07-03). CropBatchTests target restored, 31 tests green. Code-review fixes applied (watermark thread safety, notification auth, corner-radius format restore, dead views deleted).
- **Last updated:** 2026-07-03

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
- ~~WebP export is **broken**~~ — RESOLVED 2026-07-03 on `feature/webp-real-support`: lossy via SDWebImageWebPCoder 0.15.0, lossless via direct libwebp (`use_argb=1`, bit-exact — the coder's own lossless is YUV-degraded, issue #116). All 6 flows + CLI `--format webp --lossless` verified.
- ~~CropBatch is **not under git**~~ — RESOLVED 2026-05-31: reconnected to `github.com/Xpycode/CropBatch`, history + tags v1.0–v1.4 restored, post-v1.4 work committed & pushed.
- **Rotate/flip inconsistency:** menu commands shelved (`#if false`, "breaks crop state") but sidebar `TransformRowView` exposes the same actions unguarded. Decide: fix + re-enable menu, or gate both.
- **Export profiles orphaned:** `ExportProfileManager` + saved-profile persistence survive, but the v1.5 3-tab sidebar dropped all preset/profile UI — feature is unreachable. Re-surface or remove.
- In-app Help: **MarkdownUI local-image resolution unverified** — `![](file.jpg)` won't resolve without an `imageProvider`/`file://` URL in the `HelpMenu` renderer (owned by appHELP). Confirm before shipping or help shows broken-image placeholders.
- In-app Help: **pbxproj package linkage is a broken hand-edit** on `feature/in-app-help` (placeholder UUIDs, fragile `../../../appHELP` relativePath). Redo via Xcode *Add Package Dependencies* before trusting it — do not merge to main as-is.

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
### v1.6 ship (WebP) — Waves A–D DONE 2026-07-03 (`feature/webp-real-support`)
- Wave E only: merge to main, bump 1.5→1.6 (150→160), build DMG, notarize, re-sign appcast
- Optional: relax corner-radius PNG force to also allow WebP-lossless (alpha now supported)

### In-app Help (via `HelpMenu` package — appHELP project)
- Content + 6 lean screenshots done (`01_Project/CropBatch/Help/`, 632KB JPEGs, refs wired). Still **untracked** → commit on `feature/in-app-help`
- Verify/add MarkdownUI bundled-image provider so `![](file.jpg)` renders (see Blockers); build + open Help window to confirm
- Wire the `HelpMenu` Swift package into the CropBatch target (the earlier pbxproj edit was broken/discarded) so the Help menu actually opens in-app

### Carryover
- Test all v1.5 features (blur global/override, sidebar tabs, snap sensitivity, undo/redo, flat toolbar)
- Ship v1.5 (version bump, DMG, appcast) if not folding into v1.6

---
*Updated by Claude. Source of truth for project position.*
