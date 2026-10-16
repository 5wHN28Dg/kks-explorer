"""Sums up dumpsys SurfaceFlinger --latency output (sf_frames.sh): per presented frame, how many display refreshes it
stayed on the screen. Frames held for three refreshes or more are below 30 fps on a 60 Hz screen (decision 0041:
the rule as the user reads it). Each poll lists the last ~127 frames; a gap between two frames is counted only when
one poll saw both of them, so a gap between polls that do not overlap is a hole in the polling, while a real stall
(however long) inside one poll counts as a slow frame."""
import sys
from collections import Counter

polls, period, cur = [], None, None
for line in open(sys.argv[1]).read().split('\n'):
    p = line.split()
    if len(p) == 1 and p[0].isdigit():      # each poll starts with the refresh period (ns)
        period = int(p[0])
        cur = []
        polls.append(cur)
    elif len(p) == 3 and cur is not None:
        a = int(p[1])                       # actual present time; 0 or INT64_MAX = not presented yet
        if 0 < a < 9e18:
            cur.append(a)
pairs, frames = set(), set()
for poll in polls:
    ts = sorted(set(poll))
    frames.update(ts)
    pairs.update(zip(ts, ts[1:]))
ts = sorted(frames)
per = period / 1e6
held, holes, holetime = [], 0, 0.0
for a, b in zip(ts, ts[1:]):
    g = (b - a) / 1e6
    if (a, b) not in pairs:
        holes += 1
        holetime += g
        continue
    held.append((round(g / per), g))
n = len(held)
c = Counter(k for k, _ in held)
span = (ts[-1] - ts[0]) / 1e9
print(f"refresh {per:.3f} ms; presented frames {len(ts)} over {span:.0f} s; coverage holes {holes} ({holetime/1000:.1f} s)")
for k in sorted(c):
    print(f"held {k} refreshes: {c[k]} ({100*c[k]/n:.2f} %)")
slow = sum(v for k, v in c.items() if k >= 3)
print(f"frames shown below 30 fps (>=3 refreshes): {slow} of {n} = {100*slow/n:.2f} %; at >=30 fps: {100-100*slow/n:.2f} %")
print(f"longest gap {max(g for _, g in held):.1f} ms; mean frame {sum(g for _, g in held)/n:.2f} ms")
