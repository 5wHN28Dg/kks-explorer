#!/usr/bin/env bash
# Runs the bench on a phone and pulls what it measured (decision 0041). One command per step; every adb call names
# the phone (-s SERIAL), and nothing but the bench's own package (kks.plant3d.bench) is installed, started, cleared or
# removed. Only on the Note 9 (NOTE9 below) are settings changed; on any other phone (the Honor is the user's own) no
# setting is changed and the bench is removed at the end of every command.
#
#   run_phone.sh SERIAL ladder           the presets below for 3 minutes each, then the first that shows at most 3 %
#                                        of frames below 30 fps on the screen (held for three refreshes or more; the
#                                        rule allows 5 %) and no frame over 100 ms runs the whole 10 minutes
#   run_phone.sh SERIAL walk PRESET [SECONDS]   one walk (default 600 s) with the pre-built plant
#   run_phone.sh SERIAL walkvsync PRESET [SECONDS]   the same with vsync on, as a shipped app (frames wait for the display)
#   run_phone.sh SERIAL load PRESET      load time: the bench's data cleared, then a first start (no shader cache, as
#                                        after an install) and a second one, both with the pre-built plant
#   run_phone.sh SERIAL look PRESET      the 10 look viewpoints as PNGs
#   run_phone.sh SERIAL unplugged PRESET [SECONDS]   starts a walk, waits for the cable to be pulled and put back
#                                        (the final run is measured on battery: charging heats the phone), then
#                                        pulls the result
#   run_phone.sh SERIAL remove           uninstalls the bench
# Results: tools/plant3d/bench/results/SERIAL/ (one folder per run, and summary.tsv). The APK is export/bench.apk
# (build.sh); APK=path overrides it.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
PKG=kks.plant3d.bench
FILES=/storage/emulated/0/Android/data/$PKG/files
NOTE9=285d2a7c153f7ece   # the test phone: the only one whose settings are changed, and the bench may stay on it
# every other phone (the Honor, AFAM026711005741, is the user's own) is treated as someone's phone: no settings
# changed, and the bench removed when the command ends (BENCH_KEEP=1 holds that over to the caller, honor.sh)
BENCH_VERSION=$(sed -n 's/^version\/code=//p' "$HERE/export_presets.cfg")
APK="${APK:-$HERE/export/bench.apk}"
SERIAL="${1:?serial}"; CMD="${2:?command}"; shift 2
OUT="$HERE/results/$SERIAL"
mkdir -p "$OUT"
touch "$HERE/results/.gdignore"   # Godot leaves the folder out of the project (and the APK)
a() { adb -s "$SERIAL" "$@"; }
sh_() { adb -s "$SERIAL" shell "$@" | tr -d '\r'; }
say() { echo "[$(date +%H:%M:%S)] $*"; }

[ "$(a get-state 2>/dev/null)" = device ] || { echo "phone $SERIAL is not attached (adb devices)" >&2; exit 3; }
model=$(sh_ getprop ro.product.model)
say "phone $SERIAL: $model, Android $(sh_ getprop ro.build.version.release)"

# 0 installed, 1 not installed; adb failing (the phone gone) stops the script: never mistaken for "not installed"
installed() {
  local l
  l=$(adb -s "$SERIAL" shell pm list packages "$PKG" | tr -d '\r') || { echo "adb cannot reach $SERIAL" >&2; exit 5; }
  echo "$l" | grep -qx "package:$PKG"
}
install() {
  [ -f "$APK" ] || { echo "no $APK: run build.sh" >&2; exit 2; }
  # an older bench may be there already (the first round's, version 1): install unless this exact APK's version is
  local have
  have=$(sh_ dumpsys package "$PKG" | sed -n 's/.*versionCode=\([0-9]*\).*/\1/p' | head -1)
  if ! installed || [ "$have" != "$BENCH_VERSION" ] || [ "${REINSTALL:-0}" = 1 ]; then
    say "installing $APK"
    # a bench signed with another key (the first round's) is removed first: it is only ever the bench
    a install -r "$APK" >/dev/null 2>&1 || { a uninstall "$PKG" >/dev/null; a install "$APK" >/dev/null; }
    installed || { echo "install failed" >&2; exit 1; }
  fi
}
remove() {
  if [ "$(a get-state 2>/dev/null)" != device ]; then
    echo "!!! CANNOT REACH $SERIAL: the bench ($PKG) may still be installed there; remove it: $0 $SERIAL remove" >&2
    return 1
  fi
  # installed: 0 yes, 1 no, 5 adb failed (in a subshell, so its exit does not end this one): only 1 is "not there"
  local st=0
  (installed) || st=$?
  if [ "$st" = 0 ]; then say "removing $PKG"; a uninstall "$PKG" >/dev/null || true; fi
  st=0
  (installed) || st=$?
  if [ "$st" != 1 ]; then
    echo "!!! could not remove $PKG from $SERIAL (or the phone went away): $0 $SERIAL remove" >&2
    return 1
  fi
}

# 50 % brightness, auto-brightness off, for the measured runs (wiki 3D-plant, measurement rules); put back after.
# Not on the Honor: the user's phone keeps its settings (its brightness is written down with each run instead).
bright_mode=""; bright_level=""
brightness_50() {
  [ "$SERIAL" = "$NOTE9" ] || return 0
  bright_mode=$(sh_ settings get system screen_brightness_mode)
  bright_level=$(sh_ settings get system screen_brightness)
  sh_ settings put system screen_brightness_mode 0
  sh_ settings put system screen_brightness 128
}
brightness_back() {
  [ -n "$bright_level" ] || return 0
  sh_ settings put system screen_brightness_mode "$bright_mode"
  sh_ settings put system screen_brightness "$bright_level"
  bright_level=""
}

state() {  # battery level, temperature, plugged, thermal status, brightness
  local b; b=$(sh_ dumpsys battery)
  local lvl tmp ac usb th br
  lvl=$(echo "$b" | sed -n 's/^ *level: //p' | head -1)
  tmp=$(echo "$b" | sed -n 's/^ *temperature: //p' | head -1)
  ac=$(echo "$b" | sed -n 's/^ *AC powered: //p' | head -1)
  usb=$(echo "$b" | sed -n 's/^ *USB powered: //p' | head -1)
  th=$(sh_ dumpsys thermalservice 2>/dev/null | sed -n 's/^Thermal Status: //p' | head -1)
  br=$(sh_ settings get system screen_brightness)
  echo "battery=${lvl}% temp=$((tmp / 10)).$((tmp % 10))C ac=$ac usb=$usb thermal=${th:-?} brightness=$br"
}

cleanup() {
  brightness_back || true
  if [ "$SERIAL" != "$NOTE9" ] && [ "${BENCH_KEEP:-0}" != 1 ]; then remove || true; fi
}
trap cleanup EXIT

activity() { sh_ cmd package resolve-activity --brief "$PKG" | tail -1; }

# run NAME PRESET SECONDS PREBUILT LOOK [WAIT_UNPLUG]: one start of the bench; prints the RESULT line
run() {
  local name=$1 preset=$2 seconds=$3 prebuilt=$4 look=$5 unplug=${6:-0}
  local dir; dir="$OUT/$(date +%Y%m%d-%H%M%S)_$name"
  mkdir -p "$dir"
  sh_ am force-stop "$PKG"
  sh_ mkdir -p "$FILES"
  sh_ rm -rf "$FILES/result.txt" "$FILES/look"
  # on battery: the app itself waits (unmeasured) until Android says it is discharging, then 30 s more
  printf 'preset=%s\nseconds=%s\nvariant=cells\nprebuilt=%s\nlook=%s\nwait_battery=%s\nvsync=%s\n' "$preset" "$seconds" "$prebuilt" "$look" "$unplug" "${VSYNC:-0}" > "$dir/preset.txt"
  a push "$dir/preset.txt" "$FILES/preset.txt" >/dev/null
  echo "before: $(state)" > "$dir/state.txt"
  local t0; t0=$(sh_ date +%s)
  say "$name: preset=$preset seconds=$seconds prebuilt=$prebuilt look=$look ($(state))"
  sh_ am start -W -n "$(activity)" > "$dir/am_start.txt"
  local peak=0 deadline=$(( $(date +%s) + seconds + 240 ))
  if [ "$unplug" = 1 ]; then
    say "UNPLUG THE PHONE WHENEVER READY; plug it back in $(( (seconds + 30 + 119) / 60 )) minutes after unplugging (the walk starts 30 s after the phone sees it is on battery)"
    a wait-for-disconnect
    say "unplugged; waiting for it to come back"
    a wait-for-device
    say "plugged in again"
    deadline=$(( $(date +%s) + 240 ))
  fi
  # memory: every second for the first 15 s (the start's pipeline compiles are the peak), then every 20 s
  local i=0 pss
  while [ $i -lt 15 ] && [ "$unplug" != 1 ]; do
    pss=$(sh_ dumpsys meminfo "$PKG" 2>/dev/null | sed -n 's/^ *TOTAL PSS: *\([0-9]*\).*/\1/p; s/^ *TOTAL *\([0-9][0-9]*\) .*/\1/p' | head -1)
    [ -n "$pss" ] && [ "$pss" -gt "$peak" ] && peak=$pss
    sleep 1; i=$((i + 1))
  done
  while ! sh_ ls "$FILES/result.txt" >/dev/null 2>&1; do
    [ "$(date +%s)" -lt "$deadline" ] || { say "$name: no result in time"; break; }
    sh_ pidof "$PKG" >/dev/null 2>&1 || { say "$name: the bench has ended"; break; }
    pss=$(sh_ dumpsys meminfo "$PKG" 2>/dev/null | sed -n 's/^ *TOTAL PSS: *\([0-9]*\).*/\1/p; s/^ *TOTAL *\([0-9][0-9]*\) .*/\1/p' | head -1)
    [ -n "$pss" ] && [ "$pss" -gt "$peak" ] && peak=$pss
    sleep 20
  done
  echo "after: $(state)" >> "$dir/state.txt"
  [ "$unplug" = 1 ] && echo "memory: not sampled (adb is off while on battery)" >> "$dir/state.txt" ||
    echo "peak_pss_sampled=$((peak / 1024))MB" >> "$dir/state.txt"
  a pull "$FILES/result.txt" "$dir/" >/dev/null 2>&1 || true
  [ "$look" = 1 ] && a pull "$FILES/look" "$dir/" >/dev/null 2>&1 || true
  # the start and the first frame, both from the phone's log: time to the first walkable frame
  a logcat -d -v epoch -T "$t0.000" > "$dir/logcat.txt" 2>/dev/null || true
  # the same lines are in the log, should the app not have been able to write its file
  [ -s "$dir/result.txt" ] || sed -n 's/.*bench: //p' "$dir/logcat.txt" > "$dir/result.txt"
  local start first
  # (a look run walks no frames and logs no first frame: an empty answer, not an error)
  start=$(grep -m1 -E "START u0 .*$PKG" "$dir/logcat.txt" | awk '{print $1}' || true)
  first=$(grep -m1 "bench: first frame" "$dir/logcat.txt" | awk '{print $1}' || true)
  [ -n "$start" ] && [ -n "$first" ] && echo "start_to_first_frame=$(echo "$first - $start" | bc)s" >> "$dir/state.txt"
  sh_ am force-stop "$PKG"
  cat "$dir/state.txt"
  grep -E 'RESULT|SPLIT|PER_MINUTE|first frame|loaded|built' "$dir/result.txt" 2>/dev/null || say "$name: no result.txt (see $dir/logcat.txt)"
  local r; r=$(grep RESULT "$dir/result.txt" 2>/dev/null || true)
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date +%F_%T)" "$model" "$name" "$(tr '\n' ' ' < "$dir/state.txt")" "$r" "$dir" >> "$OUT/summary.tsv"
  LAST_OVER100=$(echo "$r" | sed -n 's/.* over100=\([0-9]*\) .*/\1/p')
  # frames held for three refreshes or more (below 30 fps on the 60 Hz screen: the rule as the user reads it)
  LAST_SLOW=$(sed -n 's/^CADENCE .* longer=\([0-9.]*\)%.*/\1/p' "$dir/result.txt" 2>/dev/null | head -1)
}

case "$CMD" in
  ladder)
    install; brightness_50
    # each lever on its own against lean, and the ladder from the most detail down (R9a: vis first, it cuts nothing a
    # trainee needs; then texture size; then LOD bias)
    for p in lean lean+texraw lean+vis lean+tex1k lean+lod; do run "lever_$p" "$p" 180 1 0; sleep 60; done
    # A rung passes its 3 minutes (at most 3 % of frames below 30 fps on the screen, no frame over 100 ms), then must
    # pass the whole 10 minutes too (at most 5 %, no frame over 100 ms): `full`'s hitch came only twice in 10 minutes
    # (2026-10-16), which 3 minutes can miss. A rung that fails either step gives way to the next.
    chosen=""
    for p in full full+vis scaled+vis lean+vis lean+vis+tex1k lean+vis+tex1k+lod lean2+vis+tex1k+lod; do
      run "ladder_$p" "$p" 180 1 0
      if [ -n "$LAST_SLOW" ] && [ "$(echo "$LAST_SLOW <= 3.0" | bc)" = 1 ] && [ "$LAST_OVER100" = 0 ]; then
        say "$p passed 3 minutes; cooling down 5 minutes, then the 10-minute walk"
        sleep 300
        run "walk600_$p" "$p" 600 1 0
        if [ -n "$LAST_SLOW" ] && [ "$(echo "$LAST_SLOW <= 5.0" | bc)" = 1 ] && [ "$LAST_OVER100" = 0 ]; then
          chosen=$p; break
        fi
        say "$p did not hold for 10 minutes"
      fi
      sleep 60
    done
    [ -n "$chosen" ] || { say "no preset met the rule (frames below 30 fps on the screen, frames over 100 ms)"; exit 4; }
    say "chosen: $chosen"
    echo "$chosen" > "$OUT/chosen.txt"
    ;;
  walk) install; brightness_50; run "walk${2:-600}_$1" "$1" "${2:-600}" 1 0 ;;
  walkvsync) install; brightness_50; VSYNC=1 run "walkvsync${2:-600}_$1" "$1" "${2:-600}" 1 0 ;;
  load)
    install; brightness_50
    sh_ pm clear "$PKG" >/dev/null
    run "load_cold_$1" "$1" 20 1 0
    run "load_warm_$1" "$1" 20 1 0
    run "load_script_$1" "$1" 20 0 0
    ;;
  look) install; brightness_50; run "look_$1" "$1" 0 1 1 ;;
  unplugged) install; brightness_50; run "unplugged${2:-600}_$1" "$1" "${2:-600}" 1 0 1 ;;
  remove) remove ;;
  *) echo "unknown command $CMD" >&2; exit 2 ;;
esac
