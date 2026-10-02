#!/usr/bin/env bash
# Reproducible setup of the Mildew build toolchain inside a restricted container
# (no access to dl.google.com / maven / PyPI / npm; GitHub release downloads only).
#
# Installs:
#   * Godot 4.7.2-stable editor (Linux x86_64) -> $TOOLS/godot, symlinked as /usr/local/bin/godot
#   * Godot 4.7.2 export templates (android + linux) -> ~/.local/share/godot/export_templates/4.7.2.stable
#   * A *stub* Android SDK layout whose build-tools/apksigner delegates to tools/build/apksigner_v2.py
#     (APK Signature Scheme v2 signer) and whose platform-tools/adb is a no-op.
#
# On a normal developer machine, install the real Android SDK + JDK 17 instead and point
# Godot's Editor Settings at them; nothing in the project depends on this stub.
set -euo pipefail
GODOT_VERSION="4.7.2"
TOOLS="${TOOLS:-$HOME/mildew-tools}"
case "$(uname -m)" in
  aarch64|arm64) GARCH="arm64" ;;      # e.g. Ubuntu under Termux (proot-distro) on a phone/tablet
  *) GARCH="x86_64" ;;
esac
GBIN="Godot_v${GODOT_VERSION}-stable_linux.${GARCH}"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TPL_DIR="$HOME/.local/share/godot/export_templates/${GODOT_VERSION}.stable"
SDK="$TOOLS/android-sdk"
BASE="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable"

mkdir -p "$TOOLS/godot" "$TPL_DIR" "$SDK/platform-tools" "$SDK/build-tools/35.0.0" "$SDK/platforms/android-35"
if [ ! -x "$TOOLS/godot/$GBIN" ]; then
  curl -fSL -o "$TOOLS/godot/godot.zip" "$BASE/$GBIN.zip"
  (cd "$TOOLS/godot" && unzip -o -q godot.zip && rm godot.zip)
fi
ln -sf "$TOOLS/godot/$GBIN" /usr/local/bin/godot
if [ ! -f "$TPL_DIR/android_release.apk" ]; then
  echo "Downloading export templates (about 1 GB, once)..."
  curl -fSL -o "$TOOLS/templates.tpz" "$BASE/Godot_v${GODOT_VERSION}-stable_export_templates.tpz"
  unzip -o -q -j "$TOOLS/templates.tpz" templates/android_debug.apk templates/android_release.apk \
     templates/android_source.zip templates/version.txt -d "$TPL_DIR"
  unzip -o -q -j "$TOOLS/templates.tpz" templates/linux_debug.x86_64 templates/linux_release.x86_64 -d "$TPL_DIR" || true
  rm "$TOOLS/templates.tpz"
fi
cat > "$SDK/platform-tools/adb" <<'EOS'
#!/bin/sh
echo "adb stub (no Android SDK in build container): $*" >&2
exit 0
EOS
cat > "$SDK/build-tools/35.0.0/apksigner" <<EOS
#!/bin/sh
exec python3 "$REPO/tools/build/apksigner_v2.py" "\$@"
EOS
chmod +x "$SDK/platform-tools/adb" "$SDK/build-tools/35.0.0/apksigner"

# Godot's non-Gradle export ignores show_in_android_tv: add LEANBACK_LAUNCHER to the templates.
for k in debug release; do
  [ -f "$TPL_DIR/android_$k.apk.orig" ] || cp "$TPL_DIR/android_$k.apk" "$TPL_DIR/android_$k.apk.orig"
  python3 "$REPO/tools/build/patch_tv_template.py" "$TPL_DIR/android_$k.apk.orig" "$TPL_DIR/android_$k.apk"
done

# Generate editor settings once, then point them at the stub SDK.
godot --headless --editor --quit --path "$REPO" >/dev/null 2>&1 || true
ES="$(ls "$HOME"/.config/godot/editor_settings-4*.tres | head -1)"
sed -i "s#^export/android/android_sdk_path = .*#export/android/android_sdk_path = \"$SDK\"#" "$ES"
grep -q '^export/android/android_sdk_path' "$ES" || echo "export/android/android_sdk_path = \"$SDK\"" >> "$ES"
# Debug keystore (Godot needs one to sign debug exports). Created once with the JDK's keytool.
KS="$HOME/.local/share/godot/keystores/debug.keystore"
if [ ! -f "$KS" ]; then
  mkdir -p "$(dirname "$KS")"
  keytool -genkeypair -v -keystore "$KS" -storetype PKCS12 -storepass android -keypass android \
    -alias androiddebugkey -dname "CN=Android Debug,O=Android,C=US" -keyalg RSA -keysize 2048 -validity 10000 >/dev/null
fi
setting() { grep -q "^$1 = " "$ES" && sed -i "s#^$1 = .*#$1 = $2#" "$ES" || echo "$1 = $2" >> "$ES"; }
setting export/android/debug_keystore "\"$KS\""
setting export/android/debug_keystore_user "\"androiddebugkey\""
setting export/android/debug_keystore_pass "\"android\""
JH="${JAVA_HOME:-$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")}"
setting export/android/java_sdk_path "\"$JH\""
echo "Toolchain ready: $(godot --version)"
