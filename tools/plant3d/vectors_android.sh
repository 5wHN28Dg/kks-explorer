#!/bin/sh
# The engine's vectors on an Android phone (docs/plant3d/MULTIPLAYER.md §4 and §12, milestone MP2's first step):
# apps/plant3d/sim's run_vectors.gd in an APK of its own (package kks.plant3d.vectors, debuggable, signed with the
# test key: never the plant's or Walkdown's), its digests (every value at every step, the state digest of every 50th
# step) compared with this machine's.
#   tools/plant3d/vectors_android.sh SERIAL LINUX_DIGESTS
# SERIAL: the test phone (the Note 9), attached; the caller holds ~/kks-work/build/vm.lock meanwhile. LINUX_DIGESTS:
# run_vectors.gd's --digests output made here from the same checkout. The APK is installed, run, its digests pulled
# with run-as, and removed again. Prints the phone's VECTORS line and "DIGESTS equal" or the runs whose digests
# differ; exit code 0 only when every vector passed there and every digest is equal.
#   SIGNING=…/plant-test.properties   the test key (default ~/kks-work/build/plant-test-signing/plant-test.properties)
set -eu
SERIAL="$1"; LINUX="$2"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
PKG=kks.plant3d.vectors
PROPS="${SIGNING:-$HOME/kks-work/build/plant-test-signing/plant-test.properties}"
GODOT="${GODOT:-$("$ROOT/tools/plant3d/bench/fetch_godot.sh")}"
ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
JAVA_HOME="${PLANT_JAVA_HOME:-$("$ROOT/tools/plant3d/fetch_jdk.sh")}"
prop() { sed -n "s/^$1=//p" "$PROPS" | head -1; }
KS=$(prop storeFile); case "$KS" in /*) ;; *) KS="$(dirname "$PROPS")/$KS" ;; esac
case "$PKG" in io.github.walkdown*) echo "never a Walkdown package" >&2; exit 2 ;; esac
TMP=$(mktemp -d "${TMPDIR:-/tmp}/vecand.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
P="$TMP/proj"
mkdir -p "$P/v" "$P/data"
cp -r "$ROOT/apps/plant3d/sim" "$P/sim"
rm -f "$P/sim/tests/.gdignore"
cp "$ROOT/ref/vectors/plant3d-v1.json" "$ROOT/ref/vectors/plant3d-v2.json" "$P/v/"
cp -r "$ROOT/data/plant3d/." "$P/data/"
# run_vectors.gd is a SceneTree script, and an APK runs a main scene: a copy of it made a Node that does the same in
# _ready (the options come from the APK's command line, export option command_line/extra_args)
sed -e 's/^extends SceneTree$/extends Node/' -e 's/^func _init() -> void:$/func _ready() -> void:/' \
    -e 's/^\(\t*\)quit(/\1get_tree().quit(/' "$P/sim/tests/run_vectors.gd" > "$P/sim/tests/vec_main.gd"
grep -q '^extends Node$' "$P/sim/tests/vec_main.gd" && grep -q '^func _ready() -> void:$' "$P/sim/tests/vec_main.gd" ||
  { echo "run_vectors.gd's form changed: vectors_android.sh's copy needs a look" >&2; exit 2; }
printf '[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://sim/tests/vec_main.gd" id="1"]\n\n[node name="vec" type="Node"]\nscript = ExtResource("1")\n' > "$P/vec_main.tscn"
cat > "$P/project.godot" <<'EOF'
config_version=5

[application]

config/name="Plant vectors"
run/main_scene="res://vec_main.tscn"
config/features=PackedStringArray("4.7")

[rendering]

textures/vram_compression/import_etc2_astc=true
EOF
cat > "$P/export_presets.cfg" <<EOF
[preset.0]

name="Android"
platform="Android"
runnable=true
export_filter="all_resources"
include_filter="*.json"
exclude_filter=""
export_path="vectors.apk"

[preset.0.options]

gradle_build/use_gradle_build=false
architectures/arm64-v8a=true
architectures/armeabi-v7a=false
command_line/extra_args="-- --vectors=res://v/plant3d-v1.json --vectors2=res://v/plant3d-v2.json --data=res://data --digests=user://digests.json"
keystore/debug="$KS"
keystore/debug_user="$(prop keyAlias)"
keystore/debug_password="$(prop storePassword)"
package/unique_name="$PKG"
package/name="Plant vectors"
package/signed=true
permissions/internet=false
EOF
mkdir -p "$TMP/cfg/godot"
printf '[gd_resource type="EditorSettings" format=3]\n\n[resource]\nexport/android/android_sdk_path = "%s"\nexport/android/java_sdk_path = "%s"\nexport/android/shutdown_adb_on_exit = false\n' \
  "$ANDROID_HOME" "$JAVA_HOME" > "$TMP/cfg/godot/editor_settings-4.7.tres"
export XDG_CONFIG_HOME="$TMP/cfg"
timeout 600 "$GODOT" --headless --path "$P" --import >"$TMP/import.log" 2>&1 || true
timeout 600 "$GODOT" --headless --path "$P" --export-debug Android "$TMP/vectors.apk" >"$TMP/export.log" 2>&1 ||
  { tail -20 "$TMP/export.log"; echo "the vectors APK was not made" >&2; exit 1; }
a() { adb -s "$SERIAL" "$@"; }
a uninstall "$PKG" >/dev/null 2>&1 || true
a install "$TMP/vectors.apk" >/dev/null
a logcat -c
# the screen on through the run (a dozing phone pauses the app's main loop), put back after (the Note 9 has no lock)
STAY=$(a shell settings get global stay_on_while_plugged_in | tr -d '\r')
a shell svc power stayon usb
trap 'a shell settings put global stay_on_while_plugged_in "$STAY" >/dev/null 2>&1; rm -rf "$TMP"' EXIT
a shell input keyevent KEYCODE_WAKEUP; sleep 1; a shell wm dismiss-keyguard
a shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null
# the run ends when the app quits (its VECTORS line in the log)
i=0
until a logcat -d -s godot:I | grep -q "VECTORS passed="; do
  i=$((i + 1)); [ $i -gt 720 ] && { echo "no VECTORS line after an hour" >&2; a uninstall "$PKG" >/dev/null; exit 1; }
  sleep 5
done
a logcat -d -s godot:I | grep -E "VECTORS|FAIL|PROGRAM" | sed 's/^.*godot *: //' | tee "$TMP/out.txt"
sleep 3
a shell run-as "$PKG" cat files/digests.json > "$TMP/phone.json"
a uninstall "$PKG" >/dev/null
grep -q "VECTORS passed=[0-9]* failed=0" "$TMP/out.txt" || { echo "a vector failed on the phone" >&2; exit 1; }
python3 - "$TMP/phone.json" "$LINUX" <<'EOF'
import json, sys
w, l = (json.load(open(p)) for p in sys.argv[1:])
bad = sorted(k for k in set(w) | set(l) if w.get(k) != l.get(k))
n = sum(len(v.get('state', [])) for v in l.values())
print(f'DIGESTS equal: {len(l)} runs, {n} state digests' if not bad else 'DIGESTS differ: ' + ', '.join(bad[:20]))
sys.exit(1 if bad else 0)
EOF
