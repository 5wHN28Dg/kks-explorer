#!/usr/bin/env python3
"""The Note 9's GPU work per frame over whole walks, in cycles (decision 0057, "The shadow casters"):
  gpu_cycles.py RESULTS_DIR...
Each RESULTS_DIR is a phone/frames.sh walk with probe=1 and SAMPLE=1 (frames.csv, samp.txt, clock.txt). A frame's GPU
work is its GPU time (Godot's own, frames.csv) times the Mali clock of the 200 ms sample it began in (samp.txt), as in
shadow_ab.py: cycles, which move far less than GPU milliseconds with the phone's DVFS and its thermal limit (the clock
falls from 455 to 338 MHz as it warms). Not at all only for work bound by the GPU's core: memory stalls don't shrink with
the clock, so walks at a lower clock count fewer cycles. Compare walks at similar clocks (the mean clock is printed). The first SKIP s of frames (the start) are left out. Per walk: the frames,
the mean, median and 95th percentile of M cycles a frame, the mean GPU time and the mean clock."""
import argparse
import bisect
import csv
import os
import statistics as st
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import reclaim_frames as R  # noqa: E402  (engine_start: the frames' times on the phone's clock)


def frames(d, skip=5.0):
    """[(gpu_ms, clock_khz, draws)] of each frame after the first `skip` s that has a clock sample."""
    t0, _ = R.engine_start(d)
    with open(os.path.join(d, "samp.txt")) as f:
        samp = [line.split() for line in f]
    samp = [p for p in samp if len(p) >= 3]
    ts = [float(p[0]) for p in samp]
    clocks = [int(p[1]) for p in samp]
    with open(os.path.join(d, "frames.csv")) as f:
        rows = list(csv.DictReader(f))
    if not rows:
        return []
    first = float(rows[0]["t_ms"]) / 1000.0
    out = []
    for r in rows:
        t = float(r["t_ms"]) / 1000.0
        if t - first < skip:
            continue
        i = bisect.bisect(ts, t0 + t) - 1
        if i < 0:
            continue
        c = clocks[i] or (clocks[i - 1] if i > 0 else 0)
        if c:
            out.append((float(r["gpu_ms"]), c, int(r["draws"])))
    return out


def summary(d, skip=5.0):
    fs = frames(d, skip)
    if not fs:
        return "%s: no frames with a clock sample" % d
    mc = sorted(g * c / 1e6 for g, c, _ in fs)   # ms × kHz = cycles; in millions
    p95 = mc[min(len(mc) - 1, int(0.95 * len(mc)))]
    return "%s: %d frames, %.2f M cycles a frame (median %.2f, p95 %.2f), GPU %.2f ms, clock %.0f MHz, draws %d" % (
        os.path.basename(os.path.normpath(d)), len(fs), st.mean(mc), st.median(mc), p95,
        st.mean(g for g, _, _ in fs), st.mean(c for _, c, _ in fs) / 1e3, st.median(n for _, _, n in fs))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("dirs", nargs="+")
    ap.add_argument("--skip", type=float, default=5.0)
    a = ap.parse_args(argv)
    for d in a.dirs:
        print(summary(d, a.skip))


if __name__ == "__main__":
    main()
