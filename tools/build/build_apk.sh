#!/usr/bin/env bash
# Builds and verifies the Mildew Android TV APK.  Usage: tools/build/build_apk.sh [debug|release]
# Requires the toolchain from tools/build/setup_container_toolchain.sh (or a real Android SDK).
set -euo pipefail
cd "$(dirname "$0")/../.."
MODE="${1:-debug}"
VERSION=$(grep '^version/name=' export_presets.cfg | head -1 | cut -d'"' -f2)
OUT="build/mildew-${VERSION}-${MODE}.apk"
mkdir -p build
godot --headless --import --path . >/dev/null 2>&1 || true
godot --headless --path . --export-$MODE "Android TV" "$OUT" 2>&1 | grep -E "Signed|ERROR" || true
python3 tools/build/apksigner_v2.py verify --verbose "$OUT"
MANIFEST=$(python3 tools/build/axml_dump.py "$OUT")
LISTING=$(unzip -l "$OUT")
need() { if grep -qF "$2" <<<"$3"; then echo "$1 ok"; else echo "$1 MISSING"; exit 1; fi; }
need "manifest: LEANBACK_LAUNCHER" "android.intent.category.LEANBACK_LAUNCHER" "$MANIFEST"
need "manifest: INTERNET" "android.permission.INTERNET" "$MANIFEST"
need "pack: controller" "assets/controller/index.html" "$LISTING"
need "pack: controller fonts" "assets/controller/assets/fonts/DejaVuSansMono-Bold.ttf" "$LISTING"
need "pack: content" "assets/content/games/studio_rehearsal/questions.json" "$LISTING"
need "pack: hole content" "assets/content/games/hole/core_cp2.json" "$LISTING"
need "pack: hole photos" "belly_button.jpg-" "$LISTING"
need "pack: graham map" "assets/config/graham_cutouts.json" "$LISTING"
need "pack: graham cut-outs" "talk_closed.png-" "$LISTING"
sha256sum "$OUT"
ls -la "$OUT"
