#!/bin/sh
# Builds Walkdown Plant (decision 0054): checks the content, makes the pre-built plant, runs the tests, exports.
#   apps/plant3d/build.sh                     the content check, the plant (built/) and the tests
#   apps/plant3d/build.sh export [TARGET…]    and the exports, unbaked and unsigned, into export/check/ (CI)
#   tools/plant3d/bench/offscreen.sh apps/plant3d/build.sh release [TARGET…]
#                                             the release exports, shaders baked (needs a rendering device: the
#                                             private display offscreen.sh gives; never --headless, decision 0041)
# TARGETs: android-debug android-release linux windows (default: all). Outputs in apps/plant3d/export/.
# The Android release is signed with the plant's own key (0054: never Walkdown's), by apksigner after the export, so
# that Gradle never sees it (0056): its properties file
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

# 2. Godot's import of the project (scripts' class cache, the icon), then the content build
$T "$GODOT" --headless --path "$HERE" --import >"$HERE/.import.log" 2>&1 || { tail -20 "$HERE/.import.log"; exit 1; }
$T "$GODOT" --headless --path "$HERE" --script res://builder/build_plant.gd >"$HERE/.build.log" 2>&1 ||
  { grep -E "^build:|ERROR|SCRIPT" "$HERE/.build.log" | head -40; echo "the content build failed (apps/plant3d/.build.log)" >&2; exit 1; }
grep '^build:' "$HERE/.build.log"
# the behaviour model, scenarios and procedures the app runs (ui/plant_ui.gd reads them with sim/'s strict reader)
mkdir -p "$HERE/built/content"
cp "$ROOT/data/plant3d/plant.json" "$HERE/built/content/"
for d in areas model scenarios procedures; do
  mkdir -p "$HERE/built/content/$d"
  cp "$ROOT/data/plant3d/$d/"*.json "$HERE/built/content/$d/"
done
# the sounds (tools/plant3d/sounds, decision 0055: NumPy and FFmpeg with libvorbis): a release needs them; otherwise
# they are made when the tools are there, and the app is silent without them (ui/sound_player.gd)
PY="${PLANT_PYTHON:-$ROOT/.venv/bin/python}"; [ -x "$PY" ] || PY=python3
if "$PY" -c "import numpy" 2>/dev/null && command -v ffmpeg >/dev/null; then
  "$PY" "$ROOT/tools/plant3d/sounds/make_sounds.py" --out "$HERE/built/sounds" >"$HERE/.sounds.log" 2>&1 ||
    { tail -20 "$HERE/.sounds.log"; echo "the sounds failed (apps/plant3d/.sounds.log)" >&2; exit 1; }
  echo "sounds: $(ls "$HERE/built/sounds" | grep -c '\.ogg$') files"
elif [ "$MODE" = release ]; then
  echo "a release needs the sounds: NumPy and FFmpeg with libvorbis (tools/plant3d/sounds)" >&2; exit 2
else
  echo "sounds: not made (no NumPy or FFmpeg here): the app stays silent"
fi
# the built scenes and sounds are resources the export must know. Godot 4.7.2's headless import sometimes crashes
# on its way out after importing the sound files (signal 11 or an abort, with every file imported, 2026-10-16): a
# second run, which has nothing left to import, must succeed
$T "$GODOT" --headless --path "$HERE" --import >>"$HERE/.import.log" 2>&1 ||
  { echo "the import stopped (Godot crashed on its way out?): once more" >&2
    $T "$GODOT" --headless --path "$HERE" --import >>"$HERE/.import.log" 2>&1 || { tail -20 "$HERE/.import.log"; exit 1; }; }

# 3. The tests (the walking tests need the plant just built)
$T "$GODOT" --headless --fixed-fps 60 --path "$HERE" --script res://tests/run_tests.gd >"$HERE/.test.log" 2>&1 ||
  { grep -vE "^$|Jolt Physics job|jolt_job_system" "$HERE/.test.log" | tail -30; echo "tests failed (apps/plant3d/.test.log)" >&2; exit 1; }
grep -E "^(ok|FAIL)|passed" "$HERE/.test.log"

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
case "$TARGETS" in
  *android*)
    # The Android exports are Gradle builds (the intent filter for walkdown-plant:// links, decision 0056): Godot's
    # template from the export templates (checked by SHA-512 when fetched), the Gradle it downloads pinned by
    # SHA-256, run by a JDK 17 (Gradle 8.11 doesn't run on 25), small and without a daemon left behind.
    JAVA_HOME="${PLANT_JAVA_HOME:-$("$ROOT/tools/plant3d/fetch_jdk.sh")}"
    TV=$("$GODOT" --version | sed 's/^\([0-9.]*\.stable\).*/\1/')
    TZIP="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/$TV/android_source.zip"
    if [ "$(cat "$HERE/android/.build_version" 2>/dev/null)" != "$TV" ]; then
      [ -f "$TZIP" ] || { echo "no $TZIP: GODOT_TEMPLATES must include android_source.zip" >&2; exit 2; }
      rm -rf "$HERE/android"
      mkdir -p "$HERE/android/build"
      unzip -q "$TZIP" -d "$HERE/android/build"
      printf '%s' "$TV" > "$HERE/android/.build_version"
      : > "$HERE/android/build/.gdignore"
    fi
    W="$HERE/android/build/gradle/wrapper/gradle-wrapper.properties"
    grep -q 'gradle-8.11.1-bin.zip$' "$W" || { echo "the template's Gradle is not 8.11.1: pin its checksum here first" >&2; exit 2; }
    grep -q '^distributionSha256Sum=' "$W" ||
      echo 'distributionSha256Sum=f397b287023acdba1e9f6fc5ea72d22dd63669d59ed4a289a29b1a76eee151c6' >> "$W"
    # Gradle's dependency verification: every artifact the build downloads must match the SHA-256 recorded in
    # android-gradle-verification.xml (made once with PLANT_GRADLE_WRITE_VERIFICATION=1, then reviewed and committed)
    GW="$HERE/android/build/gradlew"
    grep -q PLANT_GRADLE_EXTRA "$GW" ||
      sed -i 's|^APP_ARGS=`save "\$@"`|[ -n "${PLANT_GRADLE_EXTRA:-}" ] \&\& set -- "$@" $PLANT_GRADLE_EXTRA\nAPP_ARGS=`save "$@"`|' "$GW"
    grep -q PLANT_GRADLE_EXTRA "$GW" || { echo "could not add the verification option to the template's gradlew" >&2; exit 2; }
    VM="$HERE/android/build/gradle/verification-metadata.xml"
    if [ -n "${PLANT_GRADLE_WRITE_VERIFICATION:-}" ]; then
      rm -f "$VM"
      export PLANT_GRADLE_EXTRA="--write-verification-metadata sha256"
    else
      cp "$HERE/android-gradle-verification.xml" "$VM"
    fi
    GP="$HERE/android/build/gradle.properties"
    sed -i 's/^org.gradle.jvmargs=.*/org.gradle.jvmargs=-Xmx2g/' "$GP"
    grep -q '^org.gradle.daemon=' "$GP" || printf 'org.gradle.daemon=false\norg.gradle.workers.max=2\n' >> "$GP"
    ;;
esac
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
  case "$4" in *.apk)
    # the export plugin's intent filter must be in the APK (a plugin that didn't run leaves no link handler)
    "$(ls -d "$ANDROID_HOME"/build-tools/* | grep -v -- '-rc' | sort -V | tail -1)/aapt2" dump xmltree "$4" --file AndroidManifest.xml |
      grep -q 'android:scheme(0x01010027)="walkdown-plant"' || { echo "$4 has no walkdown-plant:// intent filter" >&2; exit 1; } ;;
  esac
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
      KS=$(prop storeFile)
      case "$KS" in /*) ;; *) KS="$(dirname "$PROPS")/$KS" ;; esac
      # Gradle and the build dependencies it downloads never see the key (decision 0056): the release is exported
      # unsigned, then aligned and signed here with the SDK's own tools
      exp mobile release "Android unsigned" "$HERE/export/walkdown-plant-unsigned.apk"
      BT="$(ls -d "$ANDROID_HOME"/build-tools/* | grep -v -- '-rc' | sort -V | tail -1)"
      rm -f "$HERE/export/walkdown-plant.apk" "$HERE/export/walkdown-plant-aligned.apk"
      "$BT/zipalign" -P 16 -f 4 "$HERE/export/walkdown-plant-unsigned.apk" "$HERE/export/walkdown-plant-aligned.apk"
      PLANT_KS_PASS=$(prop storePassword) "$BT/apksigner" sign --ks "$KS" --ks-key-alias "$(prop keyAlias)" \
        --ks-pass env:PLANT_KS_PASS --key-pass env:PLANT_KS_PASS --out "$HERE/export/walkdown-plant.apk" \
        "$HERE/export/walkdown-plant-aligned.apk"
      rm -f "$HERE/export/walkdown-plant-aligned.apk" "$HERE/export/walkdown-plant-unsigned.apk" "$HERE/export/walkdown-plant.apk.idsig"
      ls -l "$HERE/export/walkdown-plant.apk"
      # the APK must carry the plant's certificate, not a debug one
      APKSIGNER="$(ls -d "$ANDROID_HOME"/build-tools/* | grep -v -- '-rc' | sort -V | tail -1)/apksigner"
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
