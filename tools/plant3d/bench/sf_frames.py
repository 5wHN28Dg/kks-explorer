"""Sums up dumpsys SurfaceFlinger --latency output (sf_frames.sh): per presented frame, how many display refreshes it
stayed on the screen. Frames held for three refreshes or more are below 30 fps on a 60 Hz screen (decision 0041:
the rule as the user reads it). Each poll lists the last ~127 frames; a gap between two frames is counted only when
one poll saw both of them, so a gap between polls that do not overlap is a hole in the polling, while a real stall
(however long) inside one poll counts as a slow frame.
  sf_frames.py SF_FILE [--speeds RESULT_FILE]
The frame rules judge normal play only (the user, 2026-10-27): with --speeds, the walk's result.txt (or its log), its
`SPEED fast-forward|normal at T s, uptime U ms` lines (app/main.gd: U is the phone's monotonic clock, the one
SurfaceFlinger stamps its present times with) say when the walk was in fast-forward, and a frame presented from the
start of fast-forward to FF_AFTER_MS after its end is left out (the frames in flight when it stopped carry its work).
A walk with fast-forward whose times are unknown (uptime -1) is not judged. Without --speeds every frame counts."""
import re
import sys
from collections import Counter

FF_AFTER_MS = 100.0   # frames presented this long after fast-forward stopped are still its own


def speeds(path):
    """[(start ms, end ms or None)] of fast-forward on the monotonic clock; None when a fast-forward's time is
    unknown."""
    spans, start, unknown = [], None, False
    for line in open(path, errors="replace"):
        m = re.search(r"SPEED (fast-forward|normal) at [\d.]+ s, uptime (-?\d+) ms", line)
        if not m:
            continue
        up = int(m.group(2))
        if up < 0:
            unknown = True
        if m.group(1) == "fast-forward":
            if start is None:
                start = up
        elif start is not None:
            spans.append((start, up))
            start = None
    if start is not None:
        spans.append((start, None))
    return None if unknown and spans else spans


def summary(sf_path, spans=None):
    """spans: speeds()'s, or None when the walk's speeds are not known (every frame counts)."""
    polls, period, cur = [], None, None
    for line in open(sf_path).read().split('\n'):
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

    def fast(t_ns):
        ms = t_ns / 1e6
        return any(s <= ms and (e is None or ms <= e + FF_AFTER_MS) for s, e in spans or ())

    held, holes, holetime, left_out = [], 0, 0.0, 0
    for a, b in zip(ts, ts[1:]):
        g = (b - a) / 1e6
        if (a, b) not in pairs:
            holes += 1
            holetime += g
            continue
        if fast(b):
            left_out += 1
            continue
        held.append((round(g / per), g))
    n = len(held)
    c = Counter(k for k, _ in held)
    span = (ts[-1] - ts[0]) / 1e9
    out = [f"refresh {per:.3f} ms; presented frames {len(ts)} over {span:.0f} s; coverage holes {holes} ({holetime/1000:.1f} s)"]
    if spans is not None:
        out.append(f"judged: the frames played at 1x only (the frame rules judge normal play; the user, 2026-10-27): " +
                   (f"{left_out} frames in fast-forward left out" if spans else "the walk had no fast-forward"))
    for k in sorted(c):
        out.append(f"held {k} refreshes: {c[k]} ({100*c[k]/n:.2f} %)")
    slow = sum(v for k, v in c.items() if k >= 3)
    out.append(f"frames shown below 30 fps (>=3 refreshes): {slow} of {n} = {100*slow/n:.2f} %; at >=30 fps: {100-100*slow/n:.2f} %")
    out.append(f"longest gap {max(g for _, g in held):.1f} ms; mean frame {sum(g for _, g in held)/n:.2f} ms")
    return "\n".join(out)


def main(argv):
    if len(argv) not in (1, 3) or (len(argv) == 3 and argv[1] != "--speeds"):
        raise SystemExit("usage: sf_frames.py SF_FILE [--speeds RESULT_FILE]")
    spans = None
    if len(argv) == 3:
        spans = speeds(argv[2])
        if spans is None:
            print("NOT JUDGED: the walk fast-forwarded, and its SPEED lines give no time on the phone's clock (uptime -1), "
                  "so its frames in fast-forward cannot be told apart. Every frame, for what it is worth:")
    print(summary(argv[0], spans))


if __name__ == "__main__":
    main(sys.argv[1:])
