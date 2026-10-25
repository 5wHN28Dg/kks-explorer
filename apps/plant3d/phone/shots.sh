#!/usr/bin/env bash
# What given views cost on the Note 9's GPU (decision 0066, "Frame spikes"): the real app at a tier, standing at each
# view in turn (app/main.gd `shot`), once per effect switch; each view's draw calls, triangles and GPU time (the median
# of 30 frames) from result.txt, and its PNG. Faster than a walk for an A/B of one heavy view.
#   apps/plant3d/phone/shots.sh 'NAME@x,y,z,yaw,pitch;…' [FX_OFF…]     one run per FX_OFF ("-": none; default "-")
#   APK=path   another APK (default export/walkdown-plant.apk, build.sh release); QUALITY=full (default lean+vis)
# Only on the Note 9, and only io.github.walkdown.plant is installed, started or cleared (the first run is a first
# start: cleared, no pipeline cache; the later ones keep it, as an ordinary start would: give "-" twice to compare
# warm runs only). Names: letters, digits, _ and -. Each run's battery temperature goes in its line.
# Results: apps/plant3d/results/SERIAL/shots-<time>/ (result-<fx>.txt, the PNGs) and the summary on stdout.
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
PKG=io.github.walkdown.plant
SERIAL=285d2a7c153f7ece
SPEC="${1:?shots.sh 'NAME@x,y,z,yaw,pitch;…' [FX_OFF…]}"; shift
VARIANTS=("${@:--}")
APK="${APK:-$HERE/export/walkdown-plant.apk}"
FILES=/storage/emulated/0/Android/data/$PKG/files
OUT="$HERE/results/$SERIAL/shots-$(date +%Y%m%d-%H%M%S)"
sh_() { adb -s "$SERIAL" shell "$@" | tr -d '\r'; }
[ "$(adb -s "$SERIAL" get-state 2>/dev/null)" = device ] || { echo "the Note 9 is not attached" >&2; exit 3; }
[ -f "$APK" ] || { echo "no $APK" >&2; exit 2; }
for v in $(echo "$SPEC" | tr ';' ' '); do
  [[ "${v%%@*}" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "a shot's name: letters, digits, _ and - ($v)" >&2; exit 2; }
done
mkdir -p "$OUT"
: > "$HERE/results/.gdignore"
adb -s "$SERIAL" install -r "$APK" >/dev/null 2>&1 || { adb -s "$SERIAL" uninstall "$PKG" >/dev/null 2>&1 || true; adb -s "$SERIAL" install "$APK" >/dev/null; }
cleanup() {   # (an interrupted run leaves no walk.txt: the next start of the app would take the shots again)
  sh_ rm -f "$FILES/walk.txt" "$FILES/result.txt" || true
  sh_ am force-stop "$PKG" || true
}
trap cleanup EXIT
sh_ am force-stop "$PKG"
sh_ pm clear "$PKG" >/dev/null
act=$(sh_ cmd package resolve-activity --brief "$PKG" | tail -1)
for fx in "${VARIANTS[@]}"; do
  sh_ mkdir -p "$FILES"
  sh_ rm -f "$FILES/result.txt"
  { printf 'shot=%s\nquality=%s\n' "$SPEC" "${QUALITY:-lean+vis}"; [ "$fx" != - ] && printf 'fx_off=%s\n' "$fx"; } > "$OUT/walk.txt"
  adb -s "$SERIAL" push "$OUT/walk.txt" "$FILES/walk.txt" >/dev/null
  sh_ input keyevent KEYCODE_WAKEUP; sleep 1; sh_ wm dismiss-keyguard; sleep 1
  if [ "$(sh_ dumpsys window policy | grep -cE '^ +showing=true' || true)" != 0 ]; then
    echo "the phone is locked: unlock it and run this again" >&2; exit 6
  fi
  temp=$(sh_ dumpsys battery | sed -n 's/^ *temperature: //p' | head -1)
  sh_ am start -W -n "$act" >/dev/null
  deadline=$(( $(date +%s) + 300 ))
  sleep 5
  until sh_ ls "$FILES/result.txt" >/dev/null 2>&1; do
    [ "$(date +%s)" -lt "$deadline" ] || { echo "no result in time ($fx)" >&2; break; }
    sh_ pidof "$PKG" >/dev/null 2>&1 || { sh_ ls "$FILES/result.txt" >/dev/null 2>&1 || echo "the app ended without a result ($fx)" >&2; break; }
    sleep 3
  done
  sleep 2
  adb -s "$SERIAL" pull "$FILES/result.txt" "$OUT/result-$fx.txt" >/dev/null 2>&1 || true
  for p in $(sh_ ls "$FILES" | grep '\.png$' || true); do adb -s "$SERIAL" pull "$FILES/$p" "$OUT/$fx-$p" >/dev/null; sh_ rm -f "$FILES/$p"; done
  sh_ rm -f "$FILES/walk.txt"
  sh_ am force-stop "$PKG"
  echo "fx_off=$fx: $(grep -m1 -o 'tier [^,]*' "$OUT/result-$fx.txt" 2>/dev/null || echo '?'), battery $temp (tenths of a degree)"
  grep -E "^shot [^/]*:" "$OUT/result-$fx.txt" 2>/dev/null | sed 's/^/  /' || echo "  (no shots)"
done
echo "results: $OUT"
