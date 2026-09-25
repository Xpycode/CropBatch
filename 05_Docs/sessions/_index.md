# Session History

## Active Project
CropBatch — macOS batch image cropping app

## Current Status
→ See [PROJECT_STATE.md](../PROJECT_STATE.md)

## Sessions

| Date | Focus | Outcome | Log |
|------|-------|---------|-----|
| 2026-09-25 | Reconcile Git and fix crop issues | Fixed top/bottom reversal; 38 tests pass; pushed main; closed #1/#2 with apology and next-release notice. Appearance, Help, Feedback and Penumbra-style toolbar queued. | [2026-09-25](2026-09-25.md) |
| 2026-07-14a | Unblock v1.6 auto-update (M4 Pro) | Found the "re-sign on M4 Pro" plan invalid — Group A signing key (`o388Mk7…`) is LOST (not on either Mac, no backup, not in Strongbox; user confirmed). Mitigated live appcast: pulled the wrong-key v1.6 entry so v1.4 users stop erroring (`d31b68a`). Hardened `release.sh` with a pre-build key-match guard + `--verify` + per-app `SPARKLE_ACCOUNT` (`368f3d4`); corrected `sparkle-signing.md`; wrote portfolio `SPARKLE-KEY-REGISTRY.md`. Path forward: rotate CropBatch to a new per-app key. | [2026-07-14-a](2026-07-14-a.md) |
| 2026-07-03c | Ship v1.6 (Wave E) + corner-radius→WebP relaxation | v1.6 built/notarized/released; corner radius now allows PNG *or* WebP via new `ExportFormat.supportsTransparency` (6 sites, single source of truth); 35 tests green incl. lossy-WebP alpha guard; wrote `scripts/release.sh`. **BLOCKER:** appcast signed with wrong Sparkle key (M1 Max keychain held another app's key `eH6jo…`; app expects `o388Mk7…`) → 1.4 users get "improperly signed" on update. DMG is fine; only appcast sig wrong. Re-sign from M4 Pro (likely holds the key), swap `edSignature`, push. No re-notarize | [2026-07-03-c](2026-07-03-c.md) |
| 2026-07-03b | Finish REAL WebP export (v1.6 Waves A–D) + code review round | WebP works: lossy via SDWebImageWebPCoder, lossless bit-exact via direct libwebp (coder's lossless is YUV-degraded, #116). pbxproj SPM + missing test target hand-restored, 31 tests green. Review fixes: watermark race, notification auth, corner-radius state, 10 dead views deleted. Undo/redo dim when disabled. Merged+pushed; Wave E (ship) remains | [2026-07-03-b](2026-07-03-b.md) |
| 2026-07-03a | Reconcile git — Syncthing-stripped repo (no `.git`) | Bootstrapped repo, recovered history + tags v1.0–v1.4; on-disk was strictly ahead of origin. Split drift: docs → main (`ff0b65b`), whole in-app Help WIP → `feature/in-app-help` (`53a4890`, known-broken pbxproj) — both pushed | [2026-07-03-a](2026-07-03-a.md) |
| 2026-06-02a | In-app Help screenshots (lean) + wire into markdown | 6 JPEGs @632KB from existing README shots, refs added; MarkdownUI image-provider wiring still to verify | [2026-06-02-a](2026-06-02-a.md) |
| 2026-05-31a | Reconnect to git/GitHub, clean up duplicate docs | Local folder was not a repo; reconnected to history+tags, post-v1.4 work committed & pushed, build verified | [2026-05-31-a](2026-05-31-a.md) |
| 2026-05-29a | REAL WebP export plan (adapt SFV approach) | WebP found broken-not-missing; 3-agent recon; CB-specific plan written | [2026-05-29-a](2026-05-29-a.md) |
| 2026-04-05c | Flat toolbar buttons — SUCCESS | UIDesignRequiresCompatibility in Info.plist was the missing key. Cookbook updated. | [2026-04-05-c](2026-04-05-c.md) |
| 2026-04-05b | Flat toolbar buttons migration (5 approaches) | All failed — missing Info.plist key (discovered in 2026-04-05-c) | [2026-04-05-b](2026-04-05-b.md) |
| 2026-04-05a | Code review + UI polish (toolbar investigation) | 4 code review fixes, blur drag fix, sidebar tab centered, toolbar migration blocked by layout bug | [2026-04-05-a](2026-04-05-a.md) |
| 2026-04-04b | v1.5 sidebar reorg + remaining features | 6 waves: 3-tab sidebar, shortcuts popover, undo/redo, global blur, folder watcher, snap sensitivity | [2026-04-04-b](2026-04-04-b.md) |
| 2026-04-04a | v1.5 implementation: unified crop/blur tool | All 4 waves done, pixelate live preview, performance cache, intensity fix | [2026-04-04-a](2026-04-04-a.md) |
| 2026-04-03c | v1.5 planning: unified crop/blur tool | Research complete, 4-wave plan ready, toggle+B activation confirmed | [2026-04-03-c](2026-04-03-c.md) |
| 2026-04-03b | v1.4 release: hardening, bug fixes, ship | 8 commits, 4 bugs fixed, v1.4 released, Sparkle update verified | [2026-04-03-b](2026-04-03-b.md) |
| 2026-04-03a | Production review + fix plan pre-v1.4 | 4 issues, plan written, ThumbnailCache false positive dismissed | [2026-04-03-a](2026-04-03-a.md) |
| 2026-04-01a | Code review + implementation plan for fixes | 3 issues found, plan ready | [2026-04-01-a](2026-04-01-a.md) |
| 2026-03-29b | Grid Split + production review + quality fixes | Clean build, zero errors | [2026-03-29-b](2026-03-29-b.md) |
| 2026-03-29a | Grid Split feature spec + research | Spec ready | [2026-03-29-a](2026-03-29-a.md) |
| 2026-02-05b | Fix Sparkle update error (sandbox blocking network) | v1.3 rebuild | [2026-02-05-b](2026-02-05-b.md) |

---
*One log per session. Link from here.*
