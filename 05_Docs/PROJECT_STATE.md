# Project State

> **Size limit: <100 lines.** This is a digest, not an archive.

## Identity
- **Project:** CropBatch
- **One-liner:** macOS app for batch cropping images with consistent settings
- **Started:** December 2025

## Current Position
- **Phase:** released (v1.6 out, **auto-update needs a key rotation** — old signing key is lost)
- **Focus:** Prepare the release containing the verified crop fix on the M1 Max. Check its notarization credentials and test Sparkle key rotation.
- **Status:** v1.6 remains the published download. A verified local cropping build is available on the M4 Pro.
- **Current handoff:** [M1 Max release pickup and local build details](sessions/2026-11-25.md#resume).
- **Last updated:** 2026-11-25

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
| Release | **done** | v1.6 live (2026-07-03); manual download available; auto-update requires key rotation |

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
- **v1.6 auto-update — Sparkle signing key LOST; needs key rotation** (updated 2026-07-14).
  **What:** CropBatch trusts `SUPublicEDKey = o388Mk7…` ("Group A", shared with ScreenshotFromVideos/
  QuickMotion/AspectRatioUnifier). The private half is on **neither Mac** (M4 Pro `ed25519` slot empty;
  M1 Max slot holds Group B `eH6jo…`), the backup file is gone, and it was never in Strongbox → **lost**.
  **Tried (2026-07-14):** exhausted keychain/backup-file/Time-Machine/Syncthing-`.stversions`/git-history
  on the M4 Pro — all dry; user confirmed no external backup.
  **Mitigated:** bad v1.6 `<item>` pulled from the live appcast (`d31b68a`) → v1.4 users stop erroring;
  `release.sh` now guards key-match + `--verify` (`368f3d4`); custody docs written.
  **Next:** rotate to a dedicated CropBatch key, back it up to Strongbox, and test an update signed with the same Developer ID as the installed release. Keep manual download instructions available for unverified or unsupported upgrades. See [key rotation](sparkle-signing.md#key-rotation-required-for-the-next-cropbatch-release).
  Registry: `~/ProgrammingProjects/1-macOS/SPARKLE-KEY-REGISTRY.md`.
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

## Recent
- 2026-11-25: Verified the selected crop against eight originals and preserved a runnable local build. Release preparation continues on the M1 Max.
- 2026-09-25: Reconciled checkout, fixed reversed crop exports, passed 38 tests, closed both GitHub issues.

## Next Actions
### Next-session enhancements
- Review current shared Appearance, Help and Feedback implementations in sibling apps before adopting them.
- Assess proper toolbar buttons using Penumbra as the reference; scope and plan before implementation.
- Actionable follow-ups are tracked in [TASKS.md](TASKS.md).

### Crop edge bugs — fixed on main 2026-09-25
- GitHub #1 and #2 reproduced on current main: top/bottom crop exports were reversed.
- Corrected CGImage crop origin on `fix/crop-top-bottom`; three pixel-content regression tests
  fail before the fix and pass afterward. Full suite: 38 tests passed. CLI exports verified.
- Fix committed and pushed to main (`76b63f8`); GitHub #1/#2 closed with apology and next-release notice.
- Debug build verified and left open at user request; published v1.6 does not contain this fix.

### v1.6 ship (WebP) — DONE & SHIPPED 2026-07-03
- Wave E complete: merged, bumped 1.5→1.6, corner-radius→WebP relaxation, DMG built,
  notarized+stapled, EdDSA-signed, GitHub release + appcast published. `scripts/release.sh` automates it.

### In-app Help (via `HelpMenu` package — appHELP project)
- Content + screenshots preserved on `feature/in-app-help`; assess against current shared Help implementation before integrating.
- Verify/add MarkdownUI bundled-image provider so `![](file.jpg)` renders (see Blockers); build + open Help window to confirm
- Wire the `HelpMenu` Swift package into the CropBatch target (the earlier pbxproj edit was broken/discarded) so the Help menu actually opens in-app

### Carryover
- Test all v1.5 features (blur global/override, sidebar tabs, snap sensitivity, undo/redo, flat toolbar)
- Next release must include the crop fix and resolve Sparkle key custody first.

---
*Updated by Claude. Source of truth for project position.*
