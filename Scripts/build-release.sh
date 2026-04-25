#!/usr/bin/env bash
# Build a release-ready ActivityManager.app bundle.
#
#   - Compiles ActivityManager, activity-mcp, and amctl in release mode (arm64).
#   - Assembles ActivityManager.app at build/release/ActivityManager.app with
#     Info.plist, the activity-mcp helper, and any optional icon.
#   - Codesigns + notarizes when DEVELOPER_ID_APP and AC_PROFILE are set;
#     otherwise produces an unsigned build (works locally, fails Gatekeeper).
#   - Wraps the bundle into ActivityManager.zip for upload.
#
# Required env (for a signed/notarized release):
#   DEVELOPER_ID_APP   "Developer ID Application: Your Name (TEAMID)"
#   AC_PROFILE         keychain profile name created with `xcrun notarytool store-credentials`
#
# Usage:
#   ./Scripts/build-release.sh           # local unsigned build
#   ./Scripts/build-release.sh --sign    # codesign + notarize (env required)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build/release"
APP="$BUILD_DIR/ActivityManager.app"
SIGN=0
DMG=0

for arg in "$@"; do
  case "$arg" in
    --sign) SIGN=1 ;;
    --dmg)  DMG=1 ;;
    *) echo "Unknown arg: $arg" >&2; exit 64 ;;
  esac
done

# Project secrets (Apple ID, Team ID, notarization profile) live in a sibling
# private repo. Source them automatically when present so devs don't need to
# remember the env names.
SECRETS_ENV="$ROOT/../../secrets/ai_activity_manager_macos/.env"
if [[ -f "$SECRETS_ENV" ]]; then
  echo "» Sourcing secrets from $SECRETS_ENV"
  set -a
  # shellcheck disable=SC1090
  source "$SECRETS_ENV"
  set +a
fi

echo "» Cleaning $BUILD_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

build_target() {
  local pkg="$1"
  echo "» Building $pkg (release)"
  swift build \
    --package-path "$ROOT/$pkg" \
    -c release \
    --arch arm64
}

build_target "Apps/ActivityManager"
build_target "Apps/activity-mcp"
build_target "Apps/amctl"

bin_path() {
  local pkg="$1"; local target="$2"
  echo "$ROOT/$pkg/.build/arm64-apple-macosx/release/$target"
}

cp "$(bin_path Apps/ActivityManager   ActivityManager)"   "$APP/Contents/MacOS/ActivityManager"
cp "$(bin_path Apps/activity-mcp      activity-mcp)"      "$APP/Contents/MacOS/activity-mcp"
cp "$(bin_path Apps/amctl             amctl)"             "$APP/Contents/MacOS/amctl"

cp "$ROOT/Resources/Info.plist"                "$APP/Contents/Info.plist"

# Optional icon — drop AppIcon.icns into Resources/ to include it.
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null || true
fi

if [[ "$SIGN" -eq 1 ]]; then
  : "${DEVELOPER_ID_APP:?DEVELOPER_ID_APP must be set when --sign is passed}"
  : "${AC_PROFILE:?AC_PROFILE must be set when --sign is passed}"
  echo "» Codesigning with hardened runtime"
  codesign --force --options runtime --timestamp \
    --entitlements "$ROOT/Resources/ActivityManager.entitlements" \
    --sign "$DEVELOPER_ID_APP" \
    "$APP/Contents/MacOS/activity-mcp" \
    "$APP/Contents/MacOS/amctl"
  codesign --force --options runtime --timestamp \
    --entitlements "$ROOT/Resources/ActivityManager.entitlements" \
    --sign "$DEVELOPER_ID_APP" \
    "$APP"

  echo "» Zipping for notarization"
  ditto -c -k --keepParent "$APP" "$BUILD_DIR/ActivityManager.zip"

  echo "» Submitting to notarytool"
  xcrun notarytool submit "$BUILD_DIR/ActivityManager.zip" \
    --keychain-profile "$AC_PROFILE" \
    --wait

  echo "» Stapling ticket"
  xcrun stapler staple "$APP"

  rm -f "$BUILD_DIR/ActivityManager.zip"
  ditto -c -k --keepParent "$APP" "$BUILD_DIR/ActivityManager.zip"
else
  echo "» Skipping codesign (set --sign + DEVELOPER_ID_APP + AC_PROFILE for a release build)"
  ditto -c -k --keepParent "$APP" "$BUILD_DIR/ActivityManager.zip"
fi

if [[ "$DMG" -eq 1 ]]; then
  echo "» Building ActivityManager.dmg"
  STAGING="$BUILD_DIR/dmg-staging"
  rm -rf "$STAGING"
  mkdir -p "$STAGING"
  cp -R "$APP" "$STAGING/"
  ln -s /Applications "$STAGING/Applications"

  # Build a read-write DMG first so we can position icons, then convert to UDZO.
  RW_DMG="$BUILD_DIR/ActivityManager.rw.dmg"
  rm -f "$RW_DMG" "$BUILD_DIR/ActivityManager.dmg"
  hdiutil create \
    -volname "ActivityManager" \
    -srcfolder "$STAGING" \
    -ov -format UDRW \
    -fs HFS+ \
    "$RW_DMG" >/dev/null

  # Auto-mount at /Volumes/ActivityManager so Finder can address the disk by volume name.
  hdiutil attach "$RW_DMG" -quiet
  MOUNT_DIR="/Volumes/ActivityManager"
  # Give the volume a beat to register with Finder.
  for _ in 1 2 3 4 5; do
    [[ -d "$MOUNT_DIR" ]] && break
    sleep 1
  done
  /usr/bin/osascript <<'OSA' || echo "» Finder layout step failed; DMG will still build without positioned icons" >&2
tell application "Finder"
  tell disk "ActivityManager"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 760, 480}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set position of item "ActivityManager.app" of container window to {140, 180}
    set position of item "Applications" of container window to {420, 180}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA
  sync
  hdiutil detach "$MOUNT_DIR" -quiet || hdiutil detach "$MOUNT_DIR" -force -quiet || true

  hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 \
    -o "$BUILD_DIR/ActivityManager.dmg" >/dev/null
  rm -f "$RW_DMG"
  rm -rf "$STAGING"

  if [[ "$SIGN" -eq 1 ]]; then
    echo "» Signing DMG"
    codesign --force --timestamp --sign "$DEVELOPER_ID_APP" "$BUILD_DIR/ActivityManager.dmg"
    echo "» Notarizing DMG"
    xcrun notarytool submit "$BUILD_DIR/ActivityManager.dmg" \
      --keychain-profile "$AC_PROFILE" \
      --wait
    xcrun stapler staple "$BUILD_DIR/ActivityManager.dmg"
  fi
fi

echo
echo "Done."
echo "  Bundle: $APP"
echo "  Zip:    $BUILD_DIR/ActivityManager.zip"
[[ "$DMG" -eq 1 ]] && echo "  DMG:    $BUILD_DIR/ActivityManager.dmg"
