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
b "Sparkle-signing the DMG"
SIGN_UPDATE="$(find ~/Library/Developer/Xcode/DerivedData -name sign_update -type f 2>/dev/null \
  | grep -iE 'artifacts/sparkle/Sparkle/bin/sign_update$' | head -1)"
[[ -z "$SIGN_UPDATE" ]] && SIGN_UPDATE="$(find ~/ProgrammingProjects -name sign_update -type f 2>/dev/null \
  | grep -iE 'artifacts/sparkle/Sparkle/bin/sign_update$' | head -1)"
if [[ -n "$SIGN_UPDATE" ]]; then
  echo "  (using $SIGN_UPDATE)"
  "$SIGN_UPDATE" "$DMG_PATH"
  ok "EdDSA signature above → paste sparkle:edSignature + length into appcast.xml"
else
  printf '\033[1;33m! sign_update not found — build the app once so Sparkle resolves, or run it manually.\033[0m\n'
fi

echo
ok "Release artifact ready: $DMG_PATH"
ls -lh "$DMG_PATH"
