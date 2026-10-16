#!/bin/sh
# Builds the bench from nothing: Godot (pinned), the textures (pinned), their imports per texture tier, the pre-built
# plant scene, and the release exports (Android APK, Linux binary), both with the shader baker on (shaders compiled at
# export, as a shipped app would have them). Decision 0041.
#   tools/plant3d/bench/offscreen.sh tools/plant3d/bench/build.sh   everything (it needs a display: see below)
#   … build.sh --no-export   up to the pre-built scene (enough to run it on this laptop)
# Android release signing comes from GODOT_ANDROID_KEYSTORE_RELEASE_PATH / _USER / _PASSWORD; unset, the Godot debug
# keystore signs it (a bench, never published: the build is still a non-debuggable release build).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
GODOT="${GODOT:-$("$HERE/fetch_godot.sh")}"
"$HERE/fetch_textures.sh" >/dev/null

# Texture tiers: the same source files imported three ways (an import is the per-tier choice, the asset set is one).
#   tex/     2048 px, VRAM-compressed (BPTC/S3TC on desktops, ETC2 on phones) with mipmaps: how 3D textures ship
#   tex1k/   the same, limited to 1024 px (the phone tier's texture size)
#   texraw/  2048 px, lossless, no mipmaps: what the bench used before 2026-10-15, to compare with those numbers
imp() {  # folder size_limit compress_mode mipmaps
  for f in "$HERE/tex/"*.jpg; do
    n=$(basename "$f")
    [ "$1" = tex ] || cp -p "$f" "$HERE/$1/$n"
    normal=0
    case "$n" in *_NormalGL.jpg) normal=1 ;; esac
    want="[remap]

importer=\"texture\"
type=\"CompressedTexture2D\"

[params]

compress/mode=$3
compress/high_quality=false
compress/normal_map=$normal
mipmaps/generate=$4
process/size_limit=$2
detect_3d/compress_to=0
"
    # rewritten only when the settings differ, so Godot keeps what it imported before
    grep -q "^compress/mode=$3\$" "$HERE/$1/$n.import" 2>/dev/null &&
      grep -q "^process/size_limit=$2\$" "$HERE/$1/$n.import" &&
      grep -q "^mipmaps/generate=$4\$" "$HERE/$1/$n.import" || printf '%s' "$want" > "$HERE/$1/$n.import"
  done
}
mkdir -p "$HERE/tex1k" "$HERE/texraw"
imp tex 0 2 true
imp tex1k 1024 2 true
imp texraw 0 0 false
"$GODOT" --headless --path "$HERE" --import >"$HERE/import.log" 2>&1 || { tail -20 "$HERE/import.log"; exit 1; }

# A rendering device is needed from here on: Godot's headless (dummy) renderer keeps no mesh or instance data, so a
# plant saved there loads empty, and the export's shader baker bakes nothing. X11 here; offscreen.sh gives a private
# invisible display.
if [ -n "${DISPLAY:-}" ]; then
  GPU="--display-driver x11 --rendering-driver vulkan"
else
  echo "build.sh needs a display (run it under tools/plant3d/bench/offscreen.sh)" >&2
  exit 2
fi
# the pre-built plant (instanced cells), as the shipped app would carry it
# shellcheck disable=SC2086
"$GODOT" $GPU --path "$HERE" -- --variant=cells --save=res://built/plant.scn | grep '^bench:'
[ -s "$HERE/built/plant.scn" ]
# Godot imports nothing more for it, but it must be known before the export packs it
"$GODOT" --headless --path "$HERE" --import >>"$HERE/import.log" 2>&1

[ "${1:-}" = --no-export ] && exit 0
mkdir -p "$HERE/export"
# The editor's own settings for the export (Android SDK, JDK), in a folder of the bench's own: the user's Godot
# editor settings are left alone.
JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/temurin-25-jdk-amd64}"
ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
CFG="$HERE/.godot/editor-config"
mkdir -p "$CFG/godot"
# shutdown_adb_on_exit off: the editor otherwise stops the adb server when the export ends, cutting off a phone run
# in progress (it did, 2026-10-16)
printf '[gd_resource type="EditorSettings" format=3]\n\n[resource]\nexport/android/android_sdk_path = "%s"\nexport/android/java_sdk_path = "%s"\nexport/android/shutdown_adb_on_exit = false\n' \
  "$ANDROID_HOME" "$JAVA_HOME" > "$CFG/godot/editor_settings-4.7.tres"
export XDG_CONFIG_HOME="$CFG"
if [ -z "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-}" ]; then
  export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="${XDG_DATA_HOME:-$HOME/.local/share}/godot/keystores/debug.keystore"
  export GODOT_ANDROID_KEYSTORE_RELEASE_USER=androiddebugkey GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=android
fi
# The baker compiles for the renderer the editor runs (editor/export/shader_baker_export_plugin.cpp): Mobile for
# the phones, Forward+ for the laptops.
# shellcheck disable=SC2086
"$GODOT" $GPU --rendering-method mobile --path "$HERE" --export-release Android "$HERE/export/bench.apk" >"$HERE/export.log" 2>&1 ||
  { tail -30 "$HERE/export.log"; exit 1; }
# shellcheck disable=SC2086
"$GODOT" $GPU --rendering-method forward_plus --path "$HERE" --export-release Linux "$HERE/export/bench.x86_64" >>"$HERE/export.log" 2>&1 ||
  { tail -30 "$HERE/export.log"; exit 1; }
ls -l "$HERE/export/bench.apk" "$HERE/export/bench.x86_64" "$HERE/export/bench.pck"
