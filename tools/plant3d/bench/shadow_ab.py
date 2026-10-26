#!/usr/bin/env python3
"""What each group of the sun's shadow casters costs the Note 9's GPU, from one walk with `shadow_ab=` (app/shadow_ab.gd):
  shadow_ab.py RESULTS_DIR [--settle 0.4]
RESULTS_DIR is a phone/frames.sh walk with probe=1, SAMPLE=1 and WALK_EXTRA="shadow_ab=g1,g2,...\n" (frames.csv, samp.txt,
clock.txt, logcat.txt, walk.txt). Each frame's GPU work is its GPU time (Godot's own, frames.csv) times the Mali clock of the
200 ms sample it began in (samp.txt): cycles, which the clock's changes (the phone's DVFS and thermal limits) do not move.
The walk switches the groups' casting off in turn (state 0: all on; state k: group k off), 2 s each, round and round; the
first --settle s after each switch are left out (Godot's GPU time lags its frame by one or two). For each group: the
median over the rounds of (its window's mean cycles less the mean of the all-on windows just before and after it), so
that the route's own changes cancel; with how many rounds and the all-on windows' own mean."""
import argparse
import bisect
import csv
import os
import statistics as st
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import reclaim_frames as R  # noqa: E402  (engine_start: the frames' times on the phone's clock)


def groups_of(d):
    for line in open(os.path.join(d, "walk.txt")):
        if line.startswith("shadow_ab="):
            return line.strip().split("=", 1)[1].split(",")
    raise SystemExit("walk.txt has no shadow_ab= line")


def windows(d, settle=0.4):
    """[(state, round, [Mcycles of each frame])] in walk order."""
    groups = groups_of(d)
    t0, _ = R.engine_start(d)
    samp = [line.split() for line in open(os.path.join(d, "samp.txt"))]
    samp = [p for p in samp if len(p) >= 3]
    ts = [float(p[0]) for p in samp]
    clocks = [int(p[1]) for p in samp]
    out = []
    n = len(groups) + 1
    switches = 0
    since = None
    cur = None
    for r in csv.DictReader(open(os.path.join(d, "frames.csv"))):
        t = float(r["t_ms"]) / 1000.0
        for ev in (r.get("events") or "").split():
            if ev.startswith("shadow_ab+"):
                switches += int(ev.split("+")[1])
                since = t
                cur = None
        if since is None or t - since < settle:
            continue
        if cur is None:
            cur = (switches % n, switches // n, [])
            out.append(cur)
        i = bisect.bisect(ts, t0 + t) - 1
        if i < 0:
            continue
        c = clocks[i] or (clocks[i - 1] if i > 0 else 0)
        if c:
            cur[2].append(float(r["gpu_ms"]) * c / 1e6)
    return groups, out


def report(d, settle=0.4):
    groups, ws = windows(d, settle)
    lines = ["%s: %d windows of %d states" % (os.path.basename(os.path.normpath(d)), len(ws), len(groups) + 1)]
    base = [st.mean(w[2]) for w in ws if w[0] == 0 and w[2]]
    lines.append("  all on: %.2f Mcycles a frame (mean of %d windows)" % (st.mean(base), len(base)) if base else "  all on: none")
    for k, g in enumerate(groups, 1):
        diffs = []
        for j, w in enumerate(ws):
            if w[0] != k or not w[2]:
                continue
            before = next((x for x in reversed(ws[:j]) if x[0] == 0 and x[2]), None)
            after = next((x for x in ws[j + 1:] if x[0] == 0 and x[2]), None)
            ref = [st.mean(x[2]) for x in (before, after) if x is not None]
            if ref:
                diffs.append(st.mean(w[2]) - st.mean(ref))
        if diffs:
            lines.append("  %-40s off: %+.2f Mcycles a frame (median of %d rounds; mean %+.2f)" % (
                g, st.median(diffs), len(diffs), st.mean(diffs)))
        else:
            lines.append("  %-40s no rounds" % g)
    return "\n".join(lines)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("dirs", nargs="+")
    ap.add_argument("--settle", type=float, default=0.4)
    a = ap.parse_args(argv)
    for d in a.dirs:
        print(report(d, a.settle))


if __name__ == "__main__":
    main()
