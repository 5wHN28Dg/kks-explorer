#!/bin/sh
# What the screen showed (decision 0041): polls Android's SurfaceFlinger for the present times of the bench's
# SurfaceView every second while the bench runs, then sums up how many refreshes each frame stayed on the screen.
# Read-only on the phone. Start it once a walk is running:
#   tools/plant3d/bench/sf_frames.sh SERIAL OUTFILE [PACKAGE]   (PACKAGE: the bench's by default; Walkdown Plant's
#                                                            phone/frames.sh passes io.github.walkdown.plant)
set -eu
S="${1:?serial}"; OUT="${2:?output file}"; PKG="${3:-kks.plant3d.bench}"
HERE=$(cd "$(dirname "$0")" && pwd)
: > "$OUT"
# The bench's SurfaceView layer: "SurfaceView - PKG/ACTIVITY@…#0" on Android 10, "SurfaceView[PKG/…](BLAST)#N" on
# newer Android (not the "Background for -SurfaceView" colour layer). Two minutes at most.
L=""; i=0
until [ -n "$L" ]; do
  L=$(adb -s "$S" shell dumpsys SurfaceFlinger --list | tr -d '\r' | grep -m1 -E "^SurfaceView( - |\\[)$(echo "$PKG" | sed 's/\./\\./g')/" || true)
  [ -n "$L" ] && break
  i=$((i + 1)); [ $i -lt 120 ] || { echo "no SurfaceView layer of $PKG found (is it running, in front?)" >&2; exit 1; }
  sleep 1
done
echo "layer: $L"
while adb -s "$S" shell pidof "$PKG" >/dev/null 2>&1; do
  adb -s "$S" shell dumpsys SurfaceFlinger --latency "\"$L\"" | tr -d '\r' >> "$OUT"
  sleep 1
done
python3 -I "$HERE/sf_frames.py" "$OUT"
