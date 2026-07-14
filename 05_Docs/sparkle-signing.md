# Sparkle Signing Key

> ⚠️ **STATUS 2026-07-14: the original key is LOST.** The private half of the key
> below (`o388Mk7…`) is not in either Mac's Keychain, its backup file was deleted,
> and no copy was ever saved to Strongbox. CropBatch cannot ship a v1.4-compatible
> auto-update again. **Next release must rotate to a NEW key** (see "Key rotation"
> below). Canonical cross-app key custody now lives in the portfolio registry:
> `~/ProgrammingProjects/1-macOS/SPARKLE-KEY-REGISTRY.md`.

## Key info

- **Created:** 2 December 2025
- **Algorithm:** EdDSA (Ed25519)
- **Public key (embedded as `SUPublicEDKey`):** `o388Mk7QoQjHQ7PBDGrTQ13HkqvO1nyzkfcnmfVumUQ=`
- **Scope:** was cloned (not deliberately shared) into **CropBatch, ScreenshotFromVideos,
  QuickMotion, AspectRatioUnifier** — the audit's "Group A". The earlier claim that it was
  "shared with SyncthingStatus" was **wrong**: SyncthingStatus rotated to a different key
  (`eH6jo…`, Group B) after its own Dec-2025 key-loss. See `SPARKLE-AUDIT-2026-07-03.md`.

## What went wrong (so it isn't repeated)

Sparkle's `generate_keys`/`sign_update` default to a **single** Keychain slot (service
`https://sparkle-project.org`, account `ed25519`). Every app that ran `generate_keys` with no
`--account` wrote to that one slot. Running it for a Group B app on the Mac that held Group A
**overwrote** Group A, and the only file backup (`~/.sparkle-keys/private-key.txt`) had been
deleted. The wrong key then silently signed v1.6 on the M1 Max, and every installed user's
update was rejected as "improperly signed".

Two defences are now in place:
1. **Per-app Keychain accounts** — set `SPARKLE_ACCOUNT=<app>` so keys never share one slot.
2. **A release-time guard** in `scripts/release.sh` that aborts unless the Keychain's Sparkle
   key matches the app's embedded `SUPublicEDKey`, plus a post-sign `sign_update --verify`.

## Custody rules (going forward)

- **One key per app**, generated under its own account:
  `generate_keys --account cropbatch`
- **Back up EVERY private key to Strongbox immediately** after generating it — Strongbox is the
  durable source of truth (survives Mac resets, Syncthing stripping `.git`, Keychain clobbering):
  ```bash
  generate_keys --account cropbatch -x ~/Desktop/cropbatch-sparkle-private.txt
  # → paste the file contents into a Strongbox entry, then:
  rm -P ~/Desktop/cropbatch-sparkle-private.txt
  ```
- **Sign via the account** (release.sh does this when `SPARKLE_ACCOUNT` is set):
  `sign_update --account cropbatch CropBatch-<version>.dmg`
- **Restore on a new Mac** (from the Strongbox copy):
  `generate_keys --account cropbatch -f /path/to/cropbatch-sparkle-private.txt`

## Key rotation (required for the next CropBatch release)

Because the old key is unrecoverable, installed users can only be reached by a manual download once:
1. `generate_keys --account cropbatch` → **immediately** export & save to Strongbox (above).
2. Put the new public key in `01_Project/CropBatch/Info.plist` → `SUPublicEDKey`.
3. Register it in `SPARKLE-KEY-REGISTRY.md`.
4. Build + ship the next version (`SPARKLE_ACCOUNT=cropbatch scripts/release.sh`) — the guard now
   passes because Keychain key == embedded key.
5. Add a one-time notice (README + GitHub release notes) telling v1.4/v1.6 users to download the
   new version by hand; after that install, auto-update works again.
   Precedent: SyncthingStatus v1.5 → v1.5.1.

---
*Never commit a private key to git. This doc is safe to commit. The private key lives only in
Strongbox + the release Mac's Keychain.*
