#!/usr/bin/env bash
# Links into Walkdown Plant on a phone (docs/PLANT3D.md §6, decision 0056): a walkdown-plant:// link starts the app
# at that equipment's card, and a second link reaches the running app (Android hands it over as a new Intent).
# Only on the Note 9 (the test phone); only io.github.walkdown.plant is installed or started.
#   apps/plant3d/phone/links.sh [APK]      default export/check/walkdown-plant-debug.apk (build.sh export android-debug)
# Prints what the app logged for each link and saves a screenshot of each (results/links/<time>/).
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
PKG=io.github.walkdown.plant
SERIAL=285d2a7c153f7ece
APK="${1:-$HERE/export/check/walkdown-plant-debug.apk}"
OUT="$HERE/results/links/$(date +%Y%m%d-%H%M%S)"
sh_() { adb -s "$SERIAL" shell "$@" | tr -d '\r'; }
[ "$(adb -s "$SERIAL" get-state 2>/dev/null)" = device ] || { echo "the Note 9 is not attached" >&2; exit 3; }
mkdir -p "$OUT"
adb -s "$SERIAL" install -r "$APK" >/dev/null 2>&1 || { adb -s "$SERIAL" uninstall "$PKG" >/dev/null 2>&1 || true; adb -s "$SERIAL" install "$APK" >/dev/null; }
sh_ pm list packages "$PKG" | grep -qx "package:$PKG" || { echo "install failed" >&2; exit 1; }
sh_ am force-stop "$PKG"
sh_ input keyevent KEYCODE_WAKEUP; sleep 1; sh_ wm dismiss-keyguard; sleep 1
t0=$(sh_ date +%s)
link() {  # url name wait
  sh_ am start -a android.intent.action.VIEW -d "$1" > "$OUT/$2.am.txt"
  sleep "$3"
  adb -s "$SERIAL" exec-out screencap -p > "$OUT/$2.png"
}
link "walkdown-plant://kks/30PAC10AP001" cold 40          # the app not running: a cold start with the link
link "walkdown-plant://kks/11LAC10AP002" running 8        # the app running: the new Intent
link "walkdown-plant://procedure/cold_start/cw_a_start" procedure 8
adb -s "$SERIAL" logcat -d -v epoch -T "$t0.000" > "$OUT/logcat.txt" 2>/dev/null || true
sh_ am force-stop "$PKG"
grep -o "plant: link .*" "$OUT/logcat.txt" || echo "no link was logged (see $OUT/logcat.txt)"
echo "results: $OUT"
