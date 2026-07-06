#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOURCES_DIR="$ROOT_DIR/Resources"
ICON_PNG="$RESOURCES_DIR/WorkMemoryIcon.png"
ICON_ICNS="$RESOURCES_DIR/WorkMemory.icns"
ICONSET_DIR="$ROOT_DIR/.build/icon/WorkMemory.iconset"

cd "$ROOT_DIR"

/usr/bin/env swift "$ROOT_DIR/script/generate_app_icon.swift" >/dev/null

rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

make_icon() {
  local pixels="$1"
  local file_name="$2"
  /usr/bin/sips -z "$pixels" "$pixels" "$ICON_PNG" --out "$ICONSET_DIR/$file_name" >/dev/null
}

make_icon 16 "icon_16x16.png"
make_icon 32 "icon_16x16@2x.png"
make_icon 32 "icon_32x32.png"
make_icon 64 "icon_32x32@2x.png"
make_icon 128 "icon_128x128.png"
make_icon 256 "icon_128x128@2x.png"
make_icon 256 "icon_256x256.png"
make_icon 512 "icon_256x256@2x.png"
make_icon 512 "icon_512x512.png"
make_icon 1024 "icon_512x512@2x.png"

/usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$ICON_ICNS"

echo "$ICON_ICNS"
