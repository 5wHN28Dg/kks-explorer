#!/usr/bin/env bash
# Launch time of Walkdown Plant on a phone (the wiki's load-time rule: start to the first walkable frame), RUNS times,
# with where the time went: the process start, the engine's, then the app's own stages (app/main.gd `LAUNCH` lines)
# and the first frame, each from logcat's clock; the phone's temperature, free memory and what else ran (top, every
# second while the app starts) next to each run.
#   apps/plant3d/phone/launch.sh [SERIAL] [RUNS] [MODE]     default: the Note 9, 8 runs, first
#   MODE first    as after an install: the APK installed again (install -r, as phone/frames.sh), its data cleared
#                 (no pipeline cache, no settings), started INSTALL_WAIT s after the install (default 5, as frames.sh)
#        second   the data kept (the pipeline cache of the start before): a second start
#   APK=path      another APK (default export/walkdown-plant.apk, build.sh release)
#   GAP=s         seconds between runs (default 20: the phone cools a little, the last app's memory is given back)
# Only io.github.walkdown.plant is installed, started or cleared; only on the Note 9 (on another phone, the Honor, the
# app could be someone's own: refused).
# Results: apps/plant3d/results/SERIAL/launch-<time>/ (summary.tsv, run-N.logcat, run-N.top).
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
PKG=io.github.walkdown.plant
NOTE9=285d2a7c153f7ece
SERIAL="${1:-$NOTE9}"
RUNS="${2:-8}"
MODE="${3:-first}"
APK="${APK:-$HERE/export/walkdown-plant.apk}"
WAIT="${INSTALL_WAIT:-5}"
GAP="${GAP:-20}"
OUT="$HERE/results/$SERIAL/launch-$(date +%Y%m%d-%H%M%S)"
a() { adb -s "$SERIAL" "$@"; }
sh_() { adb -s "$SERIAL" shell "$@" | tr -d '\r'; }
say() { echo "[$(date +%H:%M:%S)] $*"; }

[ "$SERIAL" = "$NOTE9" ] || { echo "launch.sh runs on the Note 9 only (it installs and clears the plant app)" >&2; exit 7; }
[ "$(a get-state 2>/dev/null)" = device ] || { echo "phone $SERIAL is not attached (adb devices)" >&2; exit 3; }
case "$MODE" in first|second) ;; *) echo "MODE: first or second" >&2; exit 2 ;; esac
[ -f "$APK" ] || { echo "no $APK: run tools/plant3d/bench/offscreen.sh apps/plant3d/build.sh release" >&2; exit 2; }
mkdir -p "$OUT"
say "phone $SERIAL: $(sh_ getprop ro.product.model), $MODE start x $RUNS; $APK ($(stat -c %s "$APK") bytes)"
printf 'run\tmode\tcpu_c\tbatt_c\tmem_avail_mb\tplugged\tbig_mhz_median\tproc_start_s\tengine_s\tready_s\tloaded_s\tui_s\tfirst_frame_s\tpipelines\n' > "$OUT/summary.tsv"
act=""
for i in $(seq 1 "$RUNS"); do
  sh_ am force-stop "$PKG"
  if [ "$MODE" = first ]; then
    a install -r "$APK" >/dev/null 2>&1 || { a uninstall "$PKG" >/dev/null 2>&1 || true; a install "$APK" >/dev/null; }
    sh_ pm clear "$PKG" >/dev/null
    sleep "$WAIT"
  elif [ "$i" = 1 ]; then
    sh_ pm list packages "$PKG" | grep -qx "package:$PKG" || a install "$APK" >/dev/null
  fi
  [ -n "$act" ] || act=$(sh_ cmd package resolve-activity --brief "$PKG" | tail -1)
  sh_ input keyevent KEYCODE_WAKEUP; sleep 1; sh_ wm dismiss-keyguard; sleep 1
  cpu=$(sh_ dumpsys thermalservice | sed -n '/Current temperatures/,/cooling/s/.*mValue=\([0-9.]*\), mType=1,.*/\1/p' | head -1)
  b=$(sh_ dumpsys battery)
  batt=$(echo "$b" | sed -n 's/^ *temperature: //p' | head -1)
  plugged=$(echo "$b" | grep -cE '(AC|USB) powered: true' || true)
  avail=$(( $(sh_ cat /proc/meminfo | sed -n 's/^MemAvailable: *\([0-9]*\).*/\1/p') / 1024 ))
  t0=$(sh_ date +%s)
  # what else runs while the app starts: top every second for 30 s
  sh_ top -b -d 1 -n 30 -m 12 > "$OUT/run-$i.top" 2>&1 &
  topp=$!
  # the big cores' clock every half second (the pipelines compile one after another on one big core: a lower clock
  # is a slower start)
  sh_ 'for i in $(seq 1 50); do cat /sys/devices/system/cpu/cpu4/cpufreq/scaling_cur_freq; sleep 0.5; done' > "$OUT/run-$i.freq" 2>&1 &
  freqp=$!
  sh_ am start -n "$act" >/dev/null
  # until the first frame (or 60 s)
  for _ in $(seq 1 60); do
    a logcat -d -v epoch -T "$t0.000" -s godot:I 2>/dev/null | grep -q "plant: first frame" && break
    sleep 1
  done
  sleep 2
  a logcat -d -v epoch -T "$t0.000" > "$OUT/run-$i.logcat" 2>/dev/null || true
  kill "$topp" "$freqp" 2>/dev/null || true; wait "$topp" "$freqp" 2>/dev/null || true
  L="$OUT/run-$i.logcat"
  ts() { grep -m1 -E "$1" "$L" | awk '{print $1}'; }
  start=$(ts "START u0 .*$PKG")
  proc=$(ts "Start proc [0-9]+:$PKG")
  engine=$(ts "Godot Engine v")
  ready=$(ts "plant: LAUNCH ready")
  loaded=$(ts "plant: LAUNCH plant")
  ui=$(ts "plant: LAUNCH ui")
  first=$(ts "plant: first frame")
  pipes=$(grep -m1 "plant: pipelines compiled" "$L" | sed 's/.*compiled: //; s/, /\//g; s/[a-z ]//g')
  d() { [ -n "$start" ] && [ -n "$1" ] && echo "$1 - $start" | bc || echo "-"; }
  # the median clock while the app started (the samples up to its first frame)
  n=$(awk -v s="$start" -v f="$first" 'BEGIN { if (s == "" || f == "") print 0; else print int((f - s) * 2) }')
  mhz=$(head -n "${n:-0}" "$OUT/run-$i.freq" | grep -E '^[0-9]+$' | sort -n | awk '{ a[NR] = $1 } END { print NR ? int(a[int((NR + 1) / 2)] / 1000) : "-" }')
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$i" "$MODE" "$cpu" "$batt" "$avail" "$plugged" "$mhz" \
    "$(d "$proc")" "$(d "$engine")" "$(d "$ready")" "$(d "$loaded")" "$(d "$ui")" "$(d "$first")" "$pipes" >> "$OUT/summary.tsv"
  tail -1 "$OUT/summary.tsv"
  grep "plant: LAUNCH" "$L" | sed 's/.*plant: //' > "$OUT/run-$i.stages" || true
  sh_ am force-stop "$PKG"
  [ "$i" = "$RUNS" ] || sleep "$GAP"
done
column -t "$OUT/summary.tsv"
echo "results: $OUT"
