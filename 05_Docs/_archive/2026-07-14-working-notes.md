> Historical working notes, archived 2026-09-25. For current status see PROJECT_STATE.md and sparkle-signing.md.

# WORKING NOTES — CropBatch Sparkle key incident (2026-07-14)

## Task
Unblock CropBatch v1.6 auto-update. PROJECT_STATE said: "on the M4 Pro, re-sign the
v1.6 DMG with the correct Sparkle key, swap edSignature in appcast.xml, push." User is
now on the M4 Pro.

## KEY FINDING — the documented unblock is INVALID
CropBatch's installed users trust `SUPublicEDKey = o388Mk7QoQjHQ7PBDGrTQ13HkqvO1nyzkfcnmfVumUQ=`
(Sparkle "Group A" key, shared with ScreenshotFromVideos / QuickMotion / AspectRatioUnifier
per `~/ProgrammingProjects/1-macOS/SPARKLE-AUDIT-2026-07-03.md` §6).

The **Group A private key is on NEITHER Mac**:
- M4 Pro: keychain account `ed25519` (its designed home) is EMPTY (`generate_keys -p --account ed25519`
  → "No existing signing key found", no auth prompt = genuinely absent). Default readable Sparkle
  slot holds account `penumbra` (a different, unique key).
- M1 Max: default slot holds `eH6jo…` = "Group B" (syncthingStatus/DiskVerdict). That's WHY v1.6
  was mis-signed there.
- Backup file `~/.sparkle-keys/private-key.txt`: deleted on both.
- Time Machine: NOT configured. Syncthing `.stversions`: no key files. Git history: no key files.

=> Local recovery exhausted & empty. The re-sign path CANNOT work until the Group A private key
is found somewhere only the user knows (password manager, M1 Max non-default keychain account,
external/archived backup) — or we rotate to a new key.

## Decisions (user, 2026-07-14)
- Q "how to proceed on key": **Keep investigating first** (before committing to key rotation).
- Q "stop the bleeding": **Yes, pull the v1.6 entry from the live appcast now.**

## Live appcast facts
- SUFeedURL = https://raw.githubusercontent.com/Xpycode/CropBatch/main/appcast.xml (served from `main`).
- origin/main:appcast.xml currently lists v1.6(160, BAD sig g1/8Vl…), v1.4(140, good), v1.3, v1.2.
- Removing the v1.6 <item> makes newest = v1.4(140): v1.4 users see no update (no error); v1.3
  users get correctly-signed v1.4. No one auto-updated to v1.6 (all rejected), so removal strands no one.

## Git state (CAUTION)
- On branch `feature/in-app-help` with 54 uncommitted files (incl. whole Help/ dir deleted, and a
  modified appcast.xml). DO NOT tangle the appcast hotfix into this branch.
- Local `main` is 14 behind origin/main (v1.6 work pushed from M1 Max, never pulled here).
- Plan: isolated `git worktree` from `origin/main` → remove v1.6 <item> → commit → `push origin <wt>:main`.
  Leaves feature/in-app-help untouched.

## Status / next
- [DONE 2026-07-14] Mitigation: pulled v1.6 <item> from live appcast. Commit d31b68a pushed to
  origin/main via isolated worktree (feature/in-app-help untouched). Live feed verified: newest = v1.4.
  Update error for v1.4 users stops on next feed refresh.
- [TRAP] feature/in-app-help working-tree appcast.xml still contains the bad v1.6 entry (uncommitted).
  If that branch is ever merged/committed to main, it RE-INTRODUCES the bad v1.6 entry. Scrub before merge.
- [DONE 2026-07-14] User confirms no Strongbox/other backup of Group A key → CONFIRMED LOST.
- [DONE 2026-07-14] Future-custody hardening (commit 368f3d4 on main):
  * scripts/release.sh: pre-build guard (Keychain key must == embedded SUPublicEDKey, else abort
    before archive) + post-sign `sign_update --verify` + `SPARKLE_ACCOUNT` for per-app accounts.
    Verified: guard correctly dies with clear message (key is absent). bash -n clean.
  * 05_Docs/sparkle-signing.md rewritten: key marked LOST, wrong scope fixed, per-app+Strongbox
    custody + rotation runbook.
  * NEW ~/ProgrammingProjects/1-macOS/SPARKLE-KEY-REGISTRY.md (portfolio-wide, not a git repo).
- [TODO] Key hunt — local recovery EXHAUSTED & empty (keychain/backup/TimeMachine/stversions/git all dry).
  The single default Sparkle keychain slot was almost certainly clobbered by a Group B app's generate_keys.
  Remaining leads need USER: (a) password manager (1Password?) holding the Group A private key;
  (b) M1 Max — check non-default keychain accounts / whether it can still sign as o388Mk7…;
  (c) any external/archived/old-Mac backup. If all dry → key-rotation migration (strands ≤1.6 users,
  one manual download; same as syncthingStatus v1.5→v1.5.1).
- [NOTE] Broader: SPARKLE-AUDIT proposals (canonical key registry, Sparkle 2.8.1→≥2.9.2 CVE bump) are
  portfolio-wide follow-ups, out of scope for this immediate unblock.
