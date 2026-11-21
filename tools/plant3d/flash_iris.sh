#!/bin/sh
# The lightning's photosensitivity analysis with IRIS (decision 0077; UI-UX-POLICY A10, issue #443): Godot's Movie
# Maker records a night thunderstorm (apps/plant3d/tests/flash_capture.gd --movie), each frame 1/60 s of the player's
# time, and EA's IRIS (its example app, IrisApp, built in user space as decision 0077 says) analyses the video.
#   IRIS_APP=/path/to/IrisApp tools/plant3d/flash_iris.sh OUT_DIR [SPEED SECONDS MODE]...
# MODE: soft (Reduced motion) or x (flashes). Default: 60 60 x, 60 60 soft, 1 120 x, 1 60 soft. Needs a rendering device: the private display offscreen.sh gives.
# Writes OUT_DIR/NAME.avi (about 7 MB a second at 960 x 540), IRIS's Results/NAME.avi/ (result.json, framedata.csv)
# and a line per video: IRIS's overall result, the most luminance and red transitions in any second.
set -eu
HERE=$(cd "$(dirname "$0")/../.." && pwd)
OUT=$(mkdir -p "$1" && cd "$1" && pwd); shift
IRIS="${IRIS_APP:?IRIS_APP: the IrisApp binary (decision 0077)}"
GODOT="${GODOT:-$("$HERE/tools/plant3d/bench/fetch_godot.sh")}"
[ $# -gt 0 ] || set -- 60 60 x 60 60 soft 1 120 x 1 60 soft
[ $(($# % 3)) -eq 0 ] || { echo "flash_iris.sh: give SPEED SECONDS MODE (soft or x) for each video" >&2; exit 2; }
cp "$(dirname "$IRIS")/appsettings.json" "$OUT/"          # IRIS's own defaults, unchanged
while [ $# -ge 3 ]; do
  sp=$1; secs=$2; mode=$3; shift 3
  case "$mode" in soft|x) ;; *) echo "flash_iris.sh: MODE is soft or x, not $mode" >&2; exit 2 ;; esac
  name="storm-${sp}x-${secs}s"; soft=""
  if [ "$mode" = soft ]; then name="$name-soft"; soft="--soft"; fi
  XH_SIZE=960x540@60 "$HERE/tools/plant3d/bench/offscreen.sh" "$GODOT" --resolution 960x540 \
    --write-movie "$OUT/$name.avi" --fixed-fps 60 --path "$HERE/apps/plant3d" --script res://tests/flash_capture.gd -- \
    --out="$OUT/$name.raw" --movie --speed="$sp" --seconds="$secs" ${soft:+"$soft"} \
    > "$OUT/$name.log" 2>&1
  # pattern detection on (IRIS's default turns it off): rain streaks are the one candidate here
  (cd "$OUT" && "$IRIS" -v "$OUT/$name.avi" -j 1 -p 1 > "$OUT/$name.iris.log" 2>&1)
  python3 - "$OUT/Results/$name.avi" <<'PY'
import csv, json, os, sys
d = sys.argv[1]
j = json.load(open(os.path.join(d, 'result.json')))
r = list(csv.DictReader(open(os.path.join(d, 'framedata.csv'))))
print('%s: %s; most transitions in a second: luminance %d, red %d; failed frames %d, with a warning %d; pattern fail frames %d' % (
    os.path.basename(d), j['OverallResult'], max(int(x['LuminanceTransitions']) for x in r),
    max(int(x['RedTransitions']) for x in r), j['TotalLuminanceIncidents']['TotalFailedFrames']
    + j['TotalRedIncidents']['TotalFailedFrames'], j['TotalLuminanceIncidents']['PassWithWarningFrames'],
    j['PatternFailFrames']))
PY
done
