#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="WorkMemory"
BUNDLE_ID="com.playground.WorkMemory"
MIN_SYSTEM_VERSION="13.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_FILE="$ROOT_DIR/Resources/WorkMemory.icns"
DMG_STAGING_DIR="$DIST_DIR/dmg-staging"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
SIGN_IDENTITY="${WORKMEMORY_SIGN_IDENTITY:-}"
ARM_TRIPLE="arm64-apple-macosx$MIN_SYSTEM_VERSION"
INTEL_TRIPLE="x86_64-apple-macosx$MIN_SYSTEM_VERSION"

cd "$ROOT_DIR"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

"$ROOT_DIR/script/generate_app_icon.sh" >/dev/null
swift build --triple "$ARM_TRIPLE"
swift build --triple "$INTEL_TRIPLE"
ARM_BINARY="$(swift build --show-bin-path --triple "$ARM_TRIPLE")/$APP_NAME"
INTEL_BINARY="$(swift build --show-bin-path --triple "$INTEL_TRIPLE")/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
/usr/bin/lipo -create "$ARM_BINARY" "$INTEL_BINARY" -output "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$ICON_FILE" "$APP_RESOURCES/WorkMemory.icns"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>WorkMemory</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>WorkMemory uses the microphone to turn spoken thoughts into text.</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>WorkMemory uses speech recognition to transcribe quick captures.</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>WorkMemory uses automation to read the current browser tab title and URL when passive capture is enabled.</string>
  <key>NSScreenCaptureUsageDescription</key>
  <string>WorkMemory uses screen capture locally to OCR the active window when local OCR is enabled.</string>
</dict>
</plist>
PLIST

if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null | /usr/bin/awk -F '"' '/Developer ID Application/ { print $2; exit }')"
fi

if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null | /usr/bin/awk -F '"' '/Apple Development/ { print $2; exit }')"
fi

if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="-"
fi

/usr/bin/codesign --force --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP_BUNDLE" >/dev/null
echo "signed with: $SIGN_IDENTITY"
/usr/bin/lipo -info "$APP_BINARY"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

create_dmg() {
  rm -rf "$DMG_STAGING_DIR" "$DMG_PATH"
  mkdir -p "$DMG_STAGING_DIR"
  cp -R "$APP_BUNDLE" "$DMG_STAGING_DIR/"
  ln -s /Applications "$DMG_STAGING_DIR/Applications"
  cat >"$DMG_STAGING_DIR/Install Notes.txt" <<NOTES
WorkMemory install notes

1. Drag WorkMemory.app to Applications.
   This build is universal and supports Apple Silicon and Intel Macs on macOS $MIN_SYSTEM_VERSION or later.
2. On first launch, macOS may ask for permissions:
   - Accessibility: passive text/context capture.
   - Screen Recording: local OCR.
   - Microphone and Speech Recognition: voice capture.
   - Automation: Chrome/Safari page title and URL capture.
3. This local development build is signed with: $SIGN_IDENTITY
   It is not notarized. If macOS blocks it, right-click WorkMemory.app and choose Open.
   For warning-free distribution, sign with a Developer ID certificate and notarize the DMG.
NOTES

  /usr/bin/hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING_DIR" \
    -format UDZO \
    -ov \
    "$DMG_PATH" >/dev/null

  /usr/bin/hdiutil verify "$DMG_PATH" >/dev/null
  echo "$DMG_PATH"
}

case "$MODE" in
  run)
    open_app
    ;;
  --dmg|dmg)
    create_dmg
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--dmg|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
