#!/bin/sh
# Builds Walkdown Plant (decision 0054): checks the content, makes the pre-built plant, runs the tests, exports.
#   apps/plant3d/build.sh                     the content check, the plant (built/) and the tests
#   apps/plant3d/build.sh export [TARGET…]    and the exports, unbaked and unsigned, into export/check/ (CI)
#   tools/plant3d/bench/offscreen.sh apps/plant3d/build.sh release [TARGET…]
#                                             the release exports, shaders baked (needs a rendering device: the
#                                             private display offscreen.sh gives; never --headless, decision 0041)
# TARGETs: android-debug android-release linux windows (default: all). Outputs in apps/plant3d/export/.
# The Android release is signed with the plant's own key (0054: never Walkdown's): its properties file
# (storeFile, storePassword, keyAlias; key password = store password, as Godot requires) is
# $PLANT_SIGNING (default ~/.config/kks-explorer/signing/walkdown-plant.properties). Without it a release APK is
# not made. A debug APK is signed with a debug key (Godot's own or one made here, never published).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
MODE="${1:-}"; [ $# -gt 0 ] && shift
TARGETS="${*:-android-debug android-release linux windows}"
GODOT="${GODOT:-$("$ROOT/tools/plant3d/bench/fetch_godot.sh")}"
T="timeout ${GODOT_TIMEOUT:-600}"   # a script that fails to compile leaves Godot running: never wait for ever

# 1. The content, strictly (Godot's own JSON reader is not strict: PLANT3D.md §1)
(cd "$ROOT" && python3 -c "import sys; from ref import plant3d as P; b = P.check_dir('data/plant3d'); print('content: valid')")

# 2. The parts kit's textures (CC0, pinned by SHA-256, kit/fetch_textures.sh), Godot's import of the project
#    (scripts' class cache, the icon, the textures in their three sizes), then the content build
"$HERE/kit/fetch_textures.sh"
$T "$GODOT" --headless --path "$HERE" --import >"$HERE/.import.log" 2>&1 || { tail -20 "$HERE/.import.log"; exit 1; }
$T "$GODOT" --headless --path "$HERE" --script res://builder/build_plant.gd >"$HERE/.build.log" 2>&1 ||
  { grep -E "^build:|ERROR|SCRIPT" "$HERE/.build.log" | head -40; echo "the content build failed (apps/plant3d/.build.log)" >&2; exit 1; }
grep '^build:' "$HERE/.build.log"
# the built scenes are resources the export must know
$T "$GODOT" --headless --path "$HERE" --import >>"$HERE/.import.log" 2>&1

# 3. The tests (the walking tests need the plant just built)
$T "$GODOT" --headless --fixed-fps 60 --path "$HERE" --script res://tests/run_tests.gd >"$HERE/.test.log" 2>&1 ||
  { grep -vE "^$|Jolt Physics job|jolt_job_system" "$HERE/.test.log" | tail -30; echo "tests failed (apps/plant3d/.test.log)" >&2; exit 1; }
grep -E "^(ok|FAIL)|passed" "$HERE/.test.log"
# a script error inside a test ends that test's function early without a failure of its own: never a pass
if grep -q "SCRIPT ERROR" "$HERE/.test.log"; then
  grep -A2 "SCRIPT ERROR" "$HERE/.test.log" | head -20
  echo "a test hit a script error (apps/plant3d/.test.log)" >&2
  exit 1
fi

[ -n "$MODE" ] || exit 0

# 4. Exports
case "$MODE" in
  export) GPU="--headless" ;;
  release)
    [ -n "${DISPLAY:-}" ] || { echo "build.sh release needs a display: run it under tools/plant3d/bench/offscreen.sh" >&2; exit 2; }
    GPU="--display-driver x11 --rendering-driver vulkan" ;;
  *) echo "unknown mode $MODE (export or release)" >&2; exit 2 ;;
esac
# export mode writes to export/check/: never over a baked, signed release that the phone scripts install
OUTD="$HERE/export"; [ "$MODE" = export ] && OUTD="$HERE/export/check"
mkdir -p "$OUTD/linux" "$OUTD/windows"
# The editor's settings for the export (Android SDK, JDK, debug key) in a folder of the project's own: the user's
# Godot editor settings are left alone.
JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/temurin-25-jdk-amd64}"
ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
CFG="$HERE/.godot/editor-config"
mkdir -p "$CFG/godot"
DEBUG_KS="${XDG_DATA_HOME:-$HOME/.local/share}/godot/keystores/debug.keystore"
if [ ! -f "$DEBUG_KS" ]; then
  DEBUG_KS="$HERE/.godot/debug.keystore"
  [ -f "$DEBUG_KS" ] || "$JAVA_HOME/bin/keytool" -genkeypair -keystore "$DEBUG_KS" -storepass android -keypass android \
    -alias androiddebugkey -dname "CN=Android Debug,O=Android,C=US" -keyalg RSA -keysize 2048 -validity 9999 >/dev/null 2>&1
fi
printf '[gd_resource type="EditorSettings" format=3]\n\n[resource]\nexport/android/android_sdk_path = "%s"\nexport/android/java_sdk_path = "%s"\nexport/android/debug_keystore = "%s"\nexport/android/debug_keystore_user = "androiddebugkey"\nexport/android/debug_keystore_pass = "android"\nexport/android/shutdown_adb_on_exit = false\n' \
  "$ANDROID_HOME" "$JAVA_HOME" "$DEBUG_KS" > "$CFG/godot/editor_settings-4.7.tres"
export XDG_CONFIG_HOME="$CFG"

exp() {  # renderer debug|release preset output
  rm -f "$4"   # an earlier export must not pass for this one
  # shellcheck disable=SC2086
  $T "$GODOT" $GPU --rendering-method "$1" --path "$HERE" "--export-$2" "$3" "$4" >>"$HERE/.export.log" 2>&1 ||
    { tail -30 "$HERE/.export.log"; echo "export $3 ($2) failed" >&2; exit 1; }
  [ -s "$4" ] || { tail -30 "$HERE/.export.log"; echo "export $3 ($2) made nothing" >&2; exit 1; }
  ls -l "$4"
}
: > "$HERE/.export.log"
for t in $TARGETS; do
  case "$t" in
    android-debug) exp mobile debug Android "$OUTD/walkdown-plant-debug.apk" ;;
    android-release)
      PROPS="${PLANT_SIGNING:-$HOME/.config/kks-explorer/signing/walkdown-plant.properties}"
      if [ "$MODE" = export ]; then
        # a check, never signed (CI has no key and never gets one): the release build exported unsigned
        exp mobile release "Android unsigned" "$OUTD/walkdown-plant-unsigned.apk"
        continue
      fi
      [ -f "$PROPS" ] || { echo "no signing properties at $PROPS: the release APK needs the plant's key" >&2; exit 2; }
      prop() { sed -n "s/^$1=//p" "$PROPS" | head -1; }
      GODOT_ANDROID_KEYSTORE_RELEASE_PATH=$(prop storeFile)
      case "$GODOT_ANDROID_KEYSTORE_RELEASE_PATH" in /*) ;; *) GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$(dirname "$PROPS")/$GODOT_ANDROID_KEYSTORE_RELEASE_PATH" ;; esac
      GODOT_ANDROID_KEYSTORE_RELEASE_USER=$(prop keyAlias)
      GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=$(prop storePassword)
      export GODOT_ANDROID_KEYSTORE_RELEASE_PATH GODOT_ANDROID_KEYSTORE_RELEASE_USER GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
      exp mobile release Android "$HERE/export/walkdown-plant.apk"
      unset GODOT_ANDROID_KEYSTORE_RELEASE_PATH GODOT_ANDROID_KEYSTORE_RELEASE_USER GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
      # the APK must carry the plant's certificate, not a debug one
      APKSIGNER="$(ls -d "$ANDROID_HOME"/build-tools/* | sort -V | tail -1)/apksigner"
      "$APKSIGNER" verify --print-certs "$HERE/export/walkdown-plant.apk" 2>/dev/null |
        grep -q "Signer #1 certificate DN: CN=Walkdown Plant$" || { echo "walkdown-plant.apk is not signed with the plant's key" >&2; exit 1; }
      ;;
    linux) exp forward_plus release Linux "$OUTD/linux/walkdown-plant.x86_64" ;;
    windows) exp forward_plus release Windows "$OUTD/windows/WalkdownPlant.exe" ;;
    *) echo "unknown target $t" >&2; exit 2 ;;
  esac
done
if [ "$MODE" = release ]; then
  # the baker must have baked (0041: a headless or display-less editor silently bakes nothing)
  grep -qi "shader baker\|baking" "$HERE/.export.log" || echo "warning: the export log does not mention the shader baker; check .export.log" >&2
fi
