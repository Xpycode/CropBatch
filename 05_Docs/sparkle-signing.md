# Sparkle Signing Key

## Key Info

**Created:** December 2, 2025
**Algorithm:** EdDSA (Ed25519)
**Scope:** Shared across all Xpycode apps (SyncthingStatus, CropBatch)

## Public Key (in Info.plist)

```
o388Mk7QoQjHQ7PBDGrTQ13HkqvO1nyzkfcnmfVumUQ=
```

## Private Key Location

**Primary:** macOS Keychain
- Keychain: `login.keychain-db`
- Service: `https://sparkle-project.org`
- Account: `ed25519`

**Backup:** `~/.sparkle-keys/private-key.txt` (created by this setup)

## How to Restore (if Keychain is lost)

1. Get the private key from backup
2. Run: `/path/to/DerivedData/.../Sparkle/bin/generate_keys -p <private_key>`

Or manually add to Keychain:
```bash
security add-generic-password \
  -s "https://sparkle-project.org" \
  -a "ed25519" \
  -w "<private_key>" \
  -T "" \
  login.keychain
```

## Signing a Release

```bash
# Find sign_update in DerivedData
find ~/Library/Developer/Xcode/DerivedData -name "sign_update" -type f

# Sign your DMG
./sign_update CropBatch-v1.3.dmg

# Output goes in appcast.xml as sparkle:edSignature
```

## What Happens If Key Is Lost

- Users on old versions cannot auto-update
- They must manually download the new version
- New releases can use a new key going forward
- This happened with SyncthingStatus v1.5 → v1.5.1

---
*Don't commit the private key to git. This doc is safe to commit.*
