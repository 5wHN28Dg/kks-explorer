#!/usr/bin/env python3
"""The Note 9's long GPU frames against the kernel's memory reclaim (decision 0066, "The last frame spikes"):
  reclaim_frames.py RESULTS_DIR [--over 45]
RESULTS_DIR is a phone/frames.sh walk with probe=1 and SAMPLE=1 (frames.csv, samp.txt, clock.txt, logcat.txt,
result.txt). Each frame after the first 5 s is put in the 200 ms sample it began in, by how many pages the kernel
scanned to reclaim memory a second there (kswapd's and direct reclaim's together); per band, how many of its frames'
GPU time (Godot's own measure, which lags its frame by one or two) passed --over ms.

The frames' times are the engine's (ms since it started): the engine's start on the phone's boot clock is the log line
"plant: first frame drawn N ms after the engine started" (logcat's epoch time, less N) less the offset between the
phone's epoch and boot clocks (clock.txt: /proc/uptime, then the epoch, read together). Good to about 10 ms."""
import argparse
import bisect
import csv
import os
import re
import sys

# samp.txt's columns (phone/frames.sh SAMPLE): uptime, Mali clock, Mali load, then /proc/vmstat's pswpin pswpout
# allocstall_normal allocstall_movable pgscan_kswapd pgscan_direct compact_stall, then MemFree MemAvailable SwapFree
COL_KSWAPD = 7
COL_DIRECT = 8
COLUMNS = 13
BANDS = [(0, 1, "none"), (1, 5000, "under 5,000 pages/s"), (5000, 20000, "5,000-20,000 pages/s"),
         (20000, float("inf"), "20,000 pages/s or more")]


def engine_start(d):
    c = open(os.path.join(d, "clock.txt")).read().split()
    off = float(c[2]) - float(c[0])   # epoch - boot clock
    for line in open(os.path.join(d, "logcat.txt"), errors="replace"):
        m = re.match(r"\s*(\d+\.\d+)\s.*plant: first frame drawn (\d+) ms", line)
        if m:
            return float(m.group(1)) - off - int(m.group(2)) / 1000.0, int(m.group(2))
    raise SystemExit("no 'first frame drawn' line in logcat.txt")


def samples(d):
    out = []
    for n, line in enumerate(open(os.path.join(d, "samp.txt"), errors="replace"), 1):
        p = line.split()
        if not p:
            continue
        if len(p) != COLUMNS:   # (a counter missing from /proc/vmstat would shift every column after it)
            raise SystemExit("samp.txt line %d has %d columns, not %d (phone/frames.sh SAMPLE)" % (n, len(p), COLUMNS))
        try:
            out.append([float(x) for x in p])
        except ValueError:
            pass
    return out


def bands(d, over=45.0):
    """[(band name, frames, frames over `over` ms of GPU)]."""
    if not os.path.exists(os.path.join(d, "frames.csv")):
        raise SystemExit("no frames.csv in %s: walk with probe=1 (WALK_EXTRA) as well as SAMPLE=1" % d)
    eng0, first = engine_start(d)
    s = samples(d)
    times = [x[0] for x in s]
    count = {name: [0, 0] for _, _, name in BANDS}
    for r in csv.DictReader(open(os.path.join(d, "frames.csv"))):
        t_ms = int(r["t_ms"])
        if t_ms < first + 5000:
            continue
        t = eng0 + t_ms / 1000.0
        i = bisect.bisect_right(times, t)
        if i <= 0 or i >= len(s):
            continue
        a, b = s[i - 1], s[i]
        scanned = (b[COL_KSWAPD] + b[COL_DIRECT]) - (a[COL_KSWAPD] + a[COL_DIRECT])
        if scanned < 0:
            continue   # (the kernel sums the online CPUs' counts: a core going offline lowers them; unknown here)
        rate = scanned / max(b[0] - a[0], 1e-6)
        name = next(n for lo, hi, n in BANDS if lo <= rate < hi)
        count[name][0] += 1
        count[name][1] += float(r["gpu_ms"]) > over
    return [(n, count[n][0], count[n][1]) for _, _, n in BANDS]


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("dir")
    ap.add_argument("--over", type=float, default=45.0)
    a = ap.parse_args(argv)
    print("kernel scanning            frames   GPU over %.0f ms" % a.over)
    for name, n, long_ in bands(a.dir, a.over):
        if n:
            print("  %-22s %8d   %5d (%.2f %%)" % (name, n, long_, 100.0 * long_ / n))
    return 0


if __name__ == "__main__":
    sys.exit(main())
