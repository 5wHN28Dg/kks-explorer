"""Sums up dumpsys SurfaceFlinger --latency output (sf_frames.sh): per presented frame, how many display refreshes it
stayed on the screen. Frames held for three refreshes or more are below 30 fps on a 60 Hz screen (decision 0041:
the rule as the user reads it). Gaps over 250 ms are counted as holes in the polling, not as frames."""
import sys
lines = open(sys.argv[1]).read().split('\n')
period = None; ts = set()
for l in lines:
    p = l.split()
    if len(p) == 1 and p[0].isdigit(): period = int(p[0]); continue
    if len(p) == 3:
        a = int(p[1])
        if 0 < a < 9e18: ts.add(a)
ts = sorted(ts)
gaps = [(b - a) / 1e6 for a, b in zip(ts, ts[1:])]
per = period / 1e6
held = []; holes = 0; holetime = 0
for g in gaps:
    if g > 250: holes += 1; holetime += g; continue
    held.append(round(g / per))
n = len(held)
from collections import Counter
c = Counter(held)
span = (ts[-1] - ts[0]) / 1e9
print(f"refresh {per:.3f} ms; presented frames {len(ts)} over {span:.0f} s; coverage holes {holes} ({holetime/1000:.1f} s)")
for k in sorted(c): print(f"held {k} refreshes: {c[k]} ({100*c[k]/n:.2f} %)")
slow = sum(v for k, v in c.items() if k >= 3)
print(f"frames shown below 30 fps (>=3 refreshes): {slow} of {n} = {100*slow/n:.2f} %; at >=30 fps: {100-100*slow/n:.2f} %")
print(f"longest gap {max(g for g in gaps if g <= 250):.1f} ms; mean frame {sum(g for g in gaps if g<=250)/n:.2f} ms")
