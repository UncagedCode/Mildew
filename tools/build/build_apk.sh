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
need "pack: real or mildew" "assets/content/games/real_or_mildew/core_cp3.json" "$LISTING"
need "pack: gtg content" "assets/content/games/guess_the_genitals/core_cp3.json" "$LISTING"
need "pack: gtg photos" "walrus.jpg-" "$LISTING"
need "pack: survey" "assets/content/games/mildew_survey/core_cp4.json" "$LISTING"
need "pack: mouthfeel" "assets/content/games/mouthfeel/core_cp4.json" "$LISTING"
need "pack: interference" "assets/content/interference/private_cp4.json" "$LISTING"
need "pack: police sketch" "assets/content/games/police_sketch/core_cp5.json" "$LISTING"
need "pack: do not press that" "assets/content/games/do_not_press_that/core_cp6.json" "$LISTING"
need "pack: basement" "assets/content/games/basement/core_cp7.json" "$LISTING"
need "pack: adverts" "assets/content/adverts/core_cp8.json" "$LISTING"
need "pack: rooms" "assets/content/world/rooms.json" "$LISTING"
need "pack: cp8 audio" "bang_distant.wav-" "$LISTING"
need "pack: graham map" "assets/config/graham_cutouts.json" "$LISTING"
need "pack: graham cut-outs" "talk_closed.png-" "$LISTING"
need "pack: voice index" "assets/config/graham_voice_index.json" "$LISTING"
need "pack: dev panel" "assets/devpanel/dev.html" "$LISTING"
need "pack: studio textures" "sign_face.png-" "$LISTING"
sha256sum "$OUT"
ls -la "$OUT"
