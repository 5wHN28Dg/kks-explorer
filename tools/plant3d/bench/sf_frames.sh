#!/bin/sh
# What the screen showed (decision 0041): polls Android's SurfaceFlinger for the present times of the bench's
# SurfaceView every second while the bench runs, then sums up how many refreshes each frame stayed on the screen.
# Read-only on the phone. Start it once a walk is running:
#   tools/plant3d/bench/sf_frames.sh SERIAL OUTFILE
set -eu
S="${1:?serial}"; OUT="${2:?output file}"
HERE=$(cd "$(dirname "$0")" && pwd)
: > "$OUT"
L=""
until [ -n "$L" ]; do
  L=$(adb -s "$S" shell dumpsys SurfaceFlinger --list | tr -d '\r' | grep -m1 '^SurfaceView - kks.plant3d.bench' || true)
  [ -n "$L" ] || sleep 1
done
echo "layer: $L"
while adb -s "$S" shell pidof kks.plant3d.bench >/dev/null 2>&1; do
  adb -s "$S" shell dumpsys SurfaceFlinger --latency "\"$L\"" | tr -d '\r' >> "$OUT"
  sleep 1
done
python3 -I "$HERE/sf_frames.py" "$OUT"
