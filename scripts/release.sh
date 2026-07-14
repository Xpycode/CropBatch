#!/usr/bin/env bash
#
# release.sh — build, sign, notarize, staple, package, and Sparkle-sign CropBatch.
#
# CropBatch ships as a Developer ID, non-sandboxed, Hardened-Runtime app that
# auto-updates via Sparkle. Unlike LaunchAway (single Mach-O), CropBatch EMBEDS
# frameworks — Sparkle, SDWebImage(WebPCoder), libwebp — so signing must go
# inside-out. We get that for free by letting `xcodebuild -exportArchive` with a
# developer-id export plist re-sign the whole bundle (frameworks first, app last,
# hardened runtime + secure timestamp, get-task-allow stripped) — the CLI
# equivalent of Organizer → Distribute App → Direct Distribution.
#
# CHAIN: archive → export (Developer ID) → verify → DMG → sign DMG →
#        notarize+staple DMG → spctl verify → Sparkle EdDSA sign (for appcast).
#
# House reference: Directions doc 61_distribution-notarization.md;
# ports LaunchAway/scripts/release.sh (adds embedded-framework export + Sparkle).
#
# Usage:
#   scripts/release.sh                 # full release, version from pbxproj
#   scripts/release.sh 1.6             # override the version string
#   scripts/release.sh --skip-notarize # signed DMG only (dry run, no Apple round-trip)
#
# One-time setup (see doc 61): a Developer ID Application cert in the login
# keychain, and a notarytool credential profile. The account-wide API key works
# for any app, so we reuse the existing "DiskVerdict" profile by default.

set -euo pipefail

# ── Config (override via env) ───────────────────────────────────────────────
APP_NAME="CropBatch"
SCHEME="CropBatch"
TEAM_ID="FDMSRXXN73"
NOTARY_PROFILE="${NOTARY_PROFILE:-DiskVerdict}"   # account-wide key; reused across apps
SIGN_IDENTITY="${SIGN_IDENTITY:-}"                # auto-detected below
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-}"            # Keychain account holding THIS app's Sparkle key.
                                                  # Empty = Sparkle's default 'ed25519' slot. Set it
                                                  # per-app (e.g. SPARKLE_ACCOUNT=cropbatch) so apps
                                                  # stop clobbering one shared slot — the bug that
                                                  # lost the old key. See 05_Docs/sparkle-signing.md.

# ── Paths (repo-root relative) ──────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="$REPO_ROOT/01_Project"
XCODEPROJ="$PROJECT_DIR/$APP_NAME.xcodeproj"
EXPORTS_DIR="$REPO_ROOT/04_Exports"
BUILD_DIR="$EXPORTS_DIR/.build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"

# ── Args ────────────────────────────────────────────────────────────────────
VERSION=""
SKIP_NOTARIZE=0
for arg in "$@"; do
  case "$arg" in
    --skip-notarize) SKIP_NOTARIZE=1 ;;
    -*)              echo "Unknown flag: $arg" >&2; exit 2 ;;
    *)               VERSION="$arg" ;;
  esac
done

b()   { printf '\033[1;36m▸ %s\033[0m\n' "$*"; }
ok()  { printf '\033[1;32m✓ %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# Run a Sparkle tool (generate_keys / sign_update), transparently adding
# --account when SPARKLE_ACCOUNT is set. A function, not an args array, so the
# empty-account case needs no array expansion (safe under `set -u` on bash 3.2).
sparkle_tool() {
  local tool="$1"; shift
  if [[ -n "$SPARKLE_ACCOUNT" ]]; then
    "$tool" --account "$SPARKLE_ACCOUNT" "$@"
  else
    "$tool" "$@"
  fi
}

# ── Preflight ───────────────────────────────────────────────────────────────
b "Preflight checks"
command -v xcodebuild >/dev/null || die "xcodebuild not found (install Xcode)"

# Resolve the signing identity by SHA-1 hash, NOT display name: the cert reads
# "GREGOR MÜLLER" and the raw codesign CLI trips on the non-ASCII "Ü". The hash
# is pure ASCII and accepted by both codesign and xcodebuild.
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning \
    | grep "Developer ID Application" | head -1 | awk '{print $2}')" || true
fi
[[ -n "$SIGN_IDENTITY" ]] || die "No 'Developer ID Application' identity in keychain (doc 61, setup step 1)."
ok "Signing identity: $SIGN_IDENTITY"

if [[ "$SKIP_NOTARIZE" -eq 0 ]]; then
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
    || die "notarytool profile '$NOTARY_PROFILE' not found (doc 61, setup step 2, or set NOTARY_PROFILE)."
  ok "notarytool profile: $NOTARY_PROFILE"
fi

# ── Sparkle signing-key guard (fail BEFORE the expensive build) ──────────────
# Root cause of the 2026 CropBatch update outage: the DMG was Sparkle-signed on a
# Mac whose Keychain held a DIFFERENT app's key, nothing checked it, and the bad
# signature shipped — every installed user's auto-update was rejected as
# "improperly signed". This guard aborts up front unless the Keychain's Sparkle
# key matches the SUPublicEDKey embedded in the app being built.
INFO_PLIST="$PROJECT_DIR/$APP_NAME/Info.plist"
EXPECTED_EDKEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$INFO_PLIST" 2>/dev/null || true)"
[[ -n "$EXPECTED_EDKEY" ]] || die "No SUPublicEDKey in $INFO_PLIST — can't verify the signing key."

SPARKLE_BIN="$(find ~/Library/Developer/Xcode/DerivedData -type d -path '*artifacts/sparkle/Sparkle/bin' 2>/dev/null | head -1)"
[[ -n "$SPARKLE_BIN" ]] || SPARKLE_BIN="$(find ~/ProgrammingProjects -type d -path '*artifacts/sparkle/Sparkle/bin' 2>/dev/null | head -1)"
[[ -n "$SPARKLE_BIN" ]] || die "Sparkle tools not found — build the app once so SPM resolves Sparkle, then retry."
GENERATE_KEYS="$SPARKLE_BIN/generate_keys"
SIGN_UPDATE="$SPARKLE_BIN/sign_update"

ACTUAL_EDKEY="$(sparkle_tool "$GENERATE_KEYS" -p 2>/dev/null || true)"
# generate_keys prints "ERROR: No existing signing key found!" to stdout when the
# account is empty — keep the value only if it looks like an Ed25519 public key
# (32 bytes → 44-char base64), otherwise treat the key as absent.
[[ "$ACTUAL_EDKEY" =~ ^[A-Za-z0-9+/]{43}=$ ]] || ACTUAL_EDKEY=""
[[ -n "$ACTUAL_EDKEY" ]] || die "No Sparkle private key in the Keychain${SPARKLE_ACCOUNT:+ (account '$SPARKLE_ACCOUNT')}. The app trusts $EXPECTED_EDKEY — import it (generate_keys -f <file>) or set SPARKLE_ACCOUNT. See 05_Docs/sparkle-signing.md."
[[ "$ACTUAL_EDKEY" == "$EXPECTED_EDKEY" ]] || die "Sparkle key MISMATCH — refusing to build. Keychain has $ACTUAL_EDKEY but the app embeds $EXPECTED_EDKEY; signing with it would ship an update every installed user rejects. Fix the key (or set SPARKLE_ACCOUNT) first. See 05_Docs/sparkle-signing.md."
ok "Sparkle key matches embedded SUPublicEDKey (${EXPECTED_EDKEY:0:12}…)"

# Version from the pbxproj MARKETING_VERSION unless overridden on the CLI.
if [[ -z "$VERSION" ]]; then
  VERSION="$(sed -nE 's/^[[:space:]]*MARKETING_VERSION = ([^;]+);/\1/p' \
    "$XCODEPROJ/project.pbxproj" | head -1 | tr -d ' ')"
  [[ -n "$VERSION" ]] || die "Could not read MARKETING_VERSION; pass it explicitly: release.sh 1.6"
fi
DMG_PATH="$EXPORTS_DIR/$APP_NAME-$VERSION.dmg"
b "Releasing $APP_NAME $VERSION"

# ── Clean + archive ──────────────────────────────────────────────────────────
b "Archiving (Release, Developer ID, Hardened Runtime)"
rm -rf "$BUILD_DIR"; mkdir -p "$BUILD_DIR"
xcodebuild archive \
  -project "$XCODEPROJ" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  | grep -E '^(===|\*\*|.*(error|warning):|.* BUILD )' || true
[[ -d "$ARCHIVE_PATH" ]] || die "Archive failed"
ok "Archived"

# ── Export the .app with a Developer ID export plist ─────────────────────────
b "Exporting Developer ID .app (signs embedded frameworks inside-out)"
EXPORT_PLIST="$BUILD_DIR/ExportOptions.plist"
cat > "$EXPORT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
</dict>
</plist>
PLIST

EXPORT_DIR="$BUILD_DIR/export"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  | grep -E '^(===|\*\*|.*(error|warning):)' || true

APP="$EXPORT_DIR/$APP_NAME.app"
[[ -d "$APP" ]] || die "Export failed — no $APP_NAME.app produced"
ok "Exported $APP"

# ── Verify the exported signature (deep: frameworks + app) ────────────────────
b "Verifying signature (deep)"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -3
if codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q get-task-allow; then
  die "get-task-allow present in exported app — notarization would reject it"
fi
ok "Signed, hardened, no get-task-allow"

# ── Build the DMG (drag-to-Applications layout) ──────────────────────────────
b "Building DMG"
mkdir -p "$EXPORTS_DIR"; rm -f "$DMG_PATH"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGING" \
  -ov -format UDZO "$DMG_PATH" >/dev/null
rm -rf "$STAGING"
ok "DMG: $DMG_PATH"

# ── Sign the DMG with Developer ID ───────────────────────────────────────────
b "Signing DMG"
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
ok "DMG signed"

if [[ "$SKIP_NOTARIZE" -eq 1 ]]; then
  ok "Done (--skip-notarize): signed DMG at $DMG_PATH (NOT notarized)"
  exit 0
fi

# ── Notarize (waits for Apple's verdict) ─────────────────────────────────────
b "Submitting to notarytool (a few minutes)…"
NOUT="$(xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1)"
echo "$NOUT"
NSTATUS="$(printf '%s\n' "$NOUT" | grep -Eo 'status: [A-Za-z]+' | tail -1 | awk '{print $2}')"
if [[ "$NSTATUS" != "Accepted" ]]; then
  SUBID="$(printf '%s\n' "$NOUT" | grep -Eo '  id: [0-9a-f-]+' | head -1 | awk '{print $2}')"
  [[ -n "${SUBID:-}" ]] && xcrun notarytool log "$SUBID" --keychain-profile "$NOTARY_PROFILE" || true
  die "Notarization result: ${NSTATUS:-unknown}"
fi
ok "Notarization accepted"

# ── Staple + Gatekeeper verify ───────────────────────────────────────────────
b "Stapling + Gatekeeper verify"
xcrun stapler staple "$DMG_PATH"
spctl -a -vvv -t open --context context:primary-signature "$DMG_PATH" 2>&1 | head -3 \
  || die "spctl rejected the DMG"
ok "Gatekeeper: accepted / Notarized Developer ID"

# ── Sparkle EdDSA signature (paste into appcast.xml) ─────────────────────────
# SIGN_UPDATE was resolved and its key verified against the app in preflight.
b "Sparkle-signing the DMG"
echo "  (using $SIGN_UPDATE${SPARKLE_ACCOUNT:+, account '$SPARKLE_ACCOUNT'})"
sparkle_tool "$SIGN_UPDATE" "$DMG_PATH"

# Belt-and-suspenders to the preflight guard: prove the signature we just wrote
# actually verifies against the signing key, so a broken sign never reaches the
# appcast. (Ed25519 is deterministic, so this -p signature equals the one above.)
EDSIG="$(sparkle_tool "$SIGN_UPDATE" -p "$DMG_PATH")"
if sparkle_tool "$SIGN_UPDATE" --verify "$DMG_PATH" "$EDSIG" >/dev/null 2>&1; then
  ok "Signature verified against the signing key (embedded ${EXPECTED_EDKEY:0:12}…)"
else
  die "sign_update --verify FAILED for the DMG — do NOT publish this signature."
fi
ok "EdDSA signature above → paste sparkle:edSignature + length into appcast.xml"

echo
ok "Release artifact ready: $DMG_PATH"
ls -lh "$DMG_PATH"
