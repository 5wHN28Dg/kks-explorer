#!/usr/bin/env bash
# One frame-time run of Walkdown Plant on a phone (decision 0054 §10, the wiki's measurement rules): the real app
# (the pre-built plant loaded as at every start, the tier it picks for itself), walking the `frames` route
# (app/routes.gd) with its own controls for SECONDS, then what it measured and what the screen showed
# (SurfaceFlinger's present times, tools/plant3d/bench/sf_frames.sh).
#   apps/plant3d/phone/frames.sh [SERIAL] [SECONDS]      default: the Note 9, 600 s
#   APK=path  another APK (default export/walkdown-plant.apk, build.sh release)
#   WALK_EXTRA="procedure=cold_start\npanels=alarms,procedure\nspeed=fast\n"   more options for the walk (app/main.gd)
#   WALK_EXTRA="walk=screens\n"   the control room's screens instead of the walk, each in turn for 10 s (their cost)
# Only io.github.walkdown.plant is installed, started, cleared or removed: never Walkdown (io.github.walkdown), never
# anything else. Only on the Note 9 is a setting changed (50 % brightness, put back after). Any other phone (the Honor
# is the user's own) keeps its settings, the run refuses to start when the plant app is already there (it would
# clear it), and the plant app is removed again at the end.
# Results: apps/plant3d/results/SERIAL/<time>/ (result.txt, sf.txt, state.txt, logcat.txt).
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
PKG=io.github.walkdown.plant
NOTE9=285d2a7c153f7ece
SERIAL="${1:-$NOTE9}"
SECONDS_="${2:-600}"
APK="${APK:-$HERE/export/walkdown-plant.apk}"
FILES=/storage/emulated/0/Android/data/$PKG/files
OUT="$HERE/results/$SERIAL/$(date +%Y%m%d-%H%M%S)"
a() { adb -s "$SERIAL" "$@"; }
sh_() { adb -s "$SERIAL" shell "$@" | tr -d '\r'; }
say() { echo "[$(date +%H:%M:%S)] $*"; }

[ "$(a get-state 2>/dev/null)" = device ] || { echo "phone $SERIAL is not attached (adb devices)" >&2; exit 3; }
[ -f "$APK" ] || { echo "no $APK: run tools/plant3d/bench/offscreen.sh apps/plant3d/build.sh release" >&2; exit 2; }
mkdir -p "$OUT"
model=$(sh_ getprop ro.product.model)
say "phone $SERIAL: $model, Android $(sh_ getprop ro.build.version.release); $APK"

installed() {
  local l
  l=$(adb -s "$SERIAL" shell pm list packages "$PKG" | tr -d '\r') || { echo "adb cannot reach $SERIAL" >&2; exit 5; }
  echo "$l" | grep -qx "package:$PKG"
}
bright_mode=""; bright_level=""
cleanup() {
  if [ -n "$bright_level" ]; then
    sh_ settings put system screen_brightness_mode "$bright_mode" || true
    sh_ settings put system screen_brightness "$bright_level" || true
  fi
  if [ "$SERIAL" != "$NOTE9" ]; then
    say "removing $PKG from $SERIAL"
    a uninstall "$PKG" >/dev/null 2>&1 || true
    if (installed); then echo "!!! $PKG is still on $SERIAL: adb -s $SERIAL uninstall $PKG" >&2; fi
  fi
}

# on someone's own phone, a plant app already there may hold their own progress: never clear or remove it
if [ "$SERIAL" != "$NOTE9" ] && installed; then
  echo "$PKG is already installed on $SERIAL; this run would clear and then remove it. Remove it yourself first if that is fine." >&2
  exit 7
fi
trap cleanup EXIT
# install (an earlier build signed with another key is replaced: it is only ever this app)
a install -r "$APK" >/dev/null 2>&1 || { a uninstall "$PKG" >/dev/null 2>&1 || true; a install "$APK" >/dev/null; }
installed || { echo "install failed" >&2; exit 1; }
if [ "$SERIAL" = "$NOTE9" ]; then
  bright_mode=$(sh_ settings get system screen_brightness_mode)
  bright_level=$(sh_ settings get system screen_brightness)
  sh_ settings put system screen_brightness_mode 0
  sh_ settings put system screen_brightness 128
fi
sh_ am force-stop "$PKG"
sh_ pm clear "$PKG" >/dev/null   # a first start: no shader cache, no saved settings (as after an install)
sh_ mkdir -p "$FILES"
printf 'walk=frames\nseconds=%s\n%b' "$SECONDS_" "${WALK_EXTRA:-}" > "$OUT/walk.txt"
a push "$OUT/walk.txt" "$FILES/walk.txt" >/dev/null
# in front and unlocked, or nothing is drawn (0041)
# (the Note 9 has no screen lock: wake it and dismiss the keyguard; the screen times out normally after)
if [ "$SERIAL" = "$NOTE9" ]; then sh_ input keyevent KEYCODE_WAKEUP; sleep 1; sh_ wm dismiss-keyguard; fi
sleep 1
if [ "$(sh_ dumpsys power | grep -c 'mWakefulness=Awake' || true)" = 0 ] || [ "$(sh_ dumpsys window policy | grep -cE '^ +showing=true' || true)" != 0 ]; then
  echo "the phone is locked or its screen is off: unlock it and run this again" >&2
  exit 6
fi
b=$(sh_ dumpsys battery)
echo "before: battery $(echo "$b" | sed -n 's/^ *level: //p' | head -1)% temperature $(echo "$b" | sed -n 's/^ *temperature: //p' | head -1) (tenths of a degree) brightness $(sh_ settings get system screen_brightness)" > "$OUT/state.txt"
t0=$(sh_ date +%s)
act=$(sh_ cmd package resolve-activity --brief "$PKG" | tail -1)
say "walking $SECONDS_ s (+5 s not measured)"
sh_ am start -W -n "$act" > "$OUT/am_start.txt"
"$HERE/../../tools/plant3d/bench/sf_frames.sh" "$SERIAL" "$OUT/sf.txt" "$PKG" > "$OUT/sf_summary.txt" 2>&1 &
sf=$!
peak=0
deadline=$(( $(date +%s) + SECONDS_ + 240 ))
while ! sh_ ls "$FILES/result.txt" >/dev/null 2>&1; do
  [ "$(date +%s)" -lt "$deadline" ] || { say "no result in time"; break; }
  sh_ pidof "$PKG" >/dev/null 2>&1 || { say "the app has ended"; break; }
  pss=$(sh_ dumpsys meminfo "$PKG" 2>/dev/null | sed -n 's/^ *TOTAL PSS: *\([0-9]*\).*/\1/p; s/^ *TOTAL *\([0-9][0-9]*\) .*/\1/p' | head -1)
  [ -n "$pss" ] && [ "$pss" -gt "$peak" ] && peak=$pss
  sleep 10
done
a pull "$FILES/result.txt" "$OUT/" >/dev/null 2>&1 || true
sh_ rm -f "$FILES/walk.txt"   # a later start by hand is an ordinary start
sleep 3
sh_ am force-stop "$PKG"
wait $sf || true
b=$(sh_ dumpsys battery)
echo "after: battery $(echo "$b" | sed -n 's/^ *level: //p' | head -1)% temperature $(echo "$b" | sed -n 's/^ *temperature: //p' | head -1); thermal $(sh_ dumpsys thermalservice 2>/dev/null | sed -n 's/^Thermal Status: //p' | head -1)" >> "$OUT/state.txt"
echo "peak_pss_sampled=$((peak / 1024))MB" >> "$OUT/state.txt"
a logcat -d -v epoch -T "$t0.000" > "$OUT/logcat.txt" 2>/dev/null || true
[ -s "$OUT/result.txt" ] || sed -n 's/.*plant: //p' "$OUT/logcat.txt" > "$OUT/result.txt"
start=$(grep -m1 -E "START u0 .*$PKG" "$OUT/logcat.txt" | awk '{print $1}' || true)
first=$(grep -m1 "plant: first frame" "$OUT/logcat.txt" | awk '{print $1}' || true)
[ -n "$start" ] && [ -n "$first" ] && echo "start_to_first_frame=$(echo "$first - $start" | bc)s" >> "$OUT/state.txt"
cat "$OUT/state.txt"
grep -E "tier|loaded|first frame|STUCK|SPIKE|CADENCE|RESULT" "$OUT/result.txt" || say "no result.txt (see $OUT/logcat.txt)"
cat "$OUT/sf_summary.txt"
echo "results: $OUT"
