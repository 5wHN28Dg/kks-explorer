#!/usr/bin/env python3
"""The Note 9's long GPU frames against the kernel's memory reclaim (decision 0066, "The last frame spikes"):
  reclaim_frames.py RESULTS_DIR [--over 45] [--rule]
RESULTS_DIR is a phone/frames.sh walk with probe=1 and SAMPLE=1 (frames.csv, samp.txt, clock.txt, logcat.txt,
result.txt). Each frame after the first 5 s is put in the 200 ms sample it began in, by how many pages the kernel
scanned to reclaim memory a second there (kswapd's and direct reclaim's together); per band, how many of its frames'
GPU time (Godot's own measure, which lags its frame by one or two) passed --over ms.

The frames' times are the engine's (ms since it started): the engine's start on the phone's boot clock is the log line
"plant: first frame drawn N ms after the engine started" (logcat's epoch time, less N) less the offset between the
phone's epoch and boot clocks (clock.txt: /proc/uptime, then the epoch, read together). Good to about 10 ms.

The frame rule (the user, 2026-10-25; decisions 0057 and 0066): "no frame over 100 ms after the first 5 s" counts the
frames the app causes. Each of the rule's frames (the walk's SPIKE lines: the app's own frame intervals over 100 ms,
as its RESULT's over100 counts them) is excluded as the phone's memory reclaim when a sample (every 0.2-0.3 s) overlapping the
frame (its log time less its length, to its log time) shows the kernel reclaiming: kswapd or direct reclaim scanned at
least one page, or a direct-reclaim stall, between that sample and the one before (samples at most 1 s apart). Every
other frame is the app's, as is any frame the log lost (over100 against the SPIKE lines found), and every frame of a
walk the sampler did not cover. A walk that would pass only by excluding frames is not judged when the kernel
reclaimed in more than 1 % of its sample pairs (from its first frame to its RESULT; the phone was under pressure
through it: walk again), when it is a STRESS=1 walk (or has no state.txt), or when its log has more SPIKE lines than
over100. A walk with no frame excluded is judged as the plain rule.
The frame rules judge normal play only (the user, 2026-10-27): fast-forward may drop frames on a phone. Since then the
app counts the frames it plays in fast-forward apart (app/walk_frames.gd): its RESULT's over100 and its SPIKE lines are
the frames at 1×, and a long frame in fast-forward is a SPIKE_FF line, which is listed here but not judged. A walk
whose RESULT has no ff_frames= is older: any frame of its in fast-forward is judged with the rest (said in the output). The judgement and, for each frame excluded, the sample lines
that show its reclaim go to RESULTS_DIR/rule.txt, kept with the walk (samp.txt, logcat.txt, a trace.pftrace if one
was recorded) as its evidence. No frames.csv needed for this part."""
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
RULE_MS = 100.0
MIN_PAGES = 1          # pages scanned in one sample that make it reclaim (any: decision 0066's bands)
MAX_GAP_S = 1.0        # a sample further from the one before proves nothing
MAX_SHARE = 0.01       # reclaim in more of a walk's samples than this: the walk is not judged (decision 0066)
COL_STALLS = (5, 6)    # allocstall_normal, allocstall_movable
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


def _lines(path):
    with open(path, errors="replace") as f:
        return f.read().splitlines()


def reclaimed(a, b):
    """Whether the kernel reclaimed between samples a and b (None: unknown, a count fell or the gap is too long)."""
    if b[0] - a[0] > MAX_GAP_S or b[0] <= a[0]:
        return None
    d = [b[c] - a[c] for c in (COL_KSWAPD, COL_DIRECT) + COL_STALLS]
    if min(d) < 0:
        return None
    return d[0] + d[1] >= MIN_PAGES or d[2] + d[3] > 0


def _rule_samples(d):
    """samp.txt's rows as numbers and as written, in step; a last line cut short (the sampler stopped mid-write) is
    left out, any other line of the wrong width refused."""
    rows, raw = [], []
    lines = [l for l in _lines(os.path.join(d, "samp.txt")) if l.split()]
    for n, line in enumerate(lines, 1):
        p = line.split()
        if len(p) != COLUMNS:
            if n == len(lines):
                break
            raise SystemExit("samp.txt line %d has %d columns, not %d (phone/frames.sh SAMPLE)" % (n, len(p), COLUMNS))
        try:
            rows.append([float(x) for x in p])
        except ValueError:
            continue
        raw.append(line.strip())
    return rows, raw


def rule(d):
    """The frame rule's judgement of a walk: a dict with `frames` [(ms, t_walk s, "app" | "reclaim", [sample lines])],
    `app`, `reclaim` (counts), `lost` (over100 frames with no SPIKE line, counted as the app's), `share` (the share of
    the walk's sample pairs with reclaim), `stressed` (a STRESS=1 walk, or no state.txt to tell), `extra` (more SPIKE
    lines than over100), `judged` (False when frames were excluded and the share passes MAX_SHARE, the walk was
    stressed or the log has extra SPIKE lines), `sampled` and `passes`."""
    sampled = os.path.exists(os.path.join(d, "samp.txt"))
    s, raw = _rule_samples(d) if sampled else ([], [])
    off = 0.0
    if s:   # (clock.txt is written by SAMPLE=1 walks only)
        c = " ".join(_lines(os.path.join(d, "clock.txt"))).split()
        off = float(c[2]) - float(c[0])
    times = [x[0] for x in s]
    over100 = None
    for line in _lines(os.path.join(d, "result.txt")):
        m = re.search(r"^RESULT .*\bover100=(\d+)", line)
        if m:
            over100 = int(m.group(1))
    if over100 is None:
        raise SystemExit("no RESULT line with over100= in result.txt: the walk did not finish")
    log = _lines(os.path.join(d, "logcat.txt")) if os.path.exists(os.path.join(d, "logcat.txt")) else []
    frames, seen, walk0, walk1 = [], set(), None, None
    ff_spikes, ff_frames = [], None
    for line in _lines(os.path.join(d, "result.txt")):
        m = re.search(r"^RESULT .*\bff_frames=(\d+)", line)
        if m:
            ff_frames = int(m.group(1))
    for line in log:
        m0 = re.match(r"\s*(\d+\.\d+)\s.*plant: (first frame drawn|RESULT )", line)
        if m0:
            t = float(m0.group(1)) - off
            if m0.group(2) == "RESULT ":
                walk1 = t
            elif walk0 is None:
                walk0 = t
        mf = re.match(r"\s*(\d+\.\d+)\s.*plant: SPIKE_FF (\d+\.?\d*) ms at (\d+\.?\d*) s", line)
        if mf and line.strip() not in seen:   # (in fast-forward: not the rule's)
            seen.add(line.strip())
            ff_spikes.append((float(mf.group(2)), float(mf.group(3))))
            continue
        # every SPIKE line is a frame over 100 ms (the app logs one only then; "100.0" is 100.01-100.04 ms)
        m = re.match(r"\s*(\d+\.\d+)\s.*plant: SPIKE (\d+\.?\d*) ms at (\d+\.?\d*) s", line)
        if not m or line.strip() in seen:
            continue
        seen.add(line.strip())
        ms = float(m.group(2))
        end = float(m.group(1)) - off
        start = end - ms / 1000.0
        ev = []
        if s:
            i = max(bisect.bisect_right(times, start), 1)   # the first sample after the frame began
            while i < len(s):
                if reclaimed(s[i - 1], s[i]):
                    ev += [l for l in (raw[i - 1], raw[i]) if not ev or l != ev[-1]]   # (a sample shared by two pairs once)
                if times[i] >= end:
                    break
                i += 1
        frames.append((ms, float(m.group(3)), "reclaim" if ev else "app", ev))
    # the share over the walk itself (from its first frame to its RESULT) and over the pairs that show something
    pairs = [reclaimed(s[i - 1], s[i]) for i in range(1, len(s))
             if (walk0 is None or s[i][0] > walk0) and (walk1 is None or s[i - 1][0] < walk1)]
    known = [p for p in pairs if p is not None]
    share = sum(1 for p in known if p) / len(known) if known else 0.0
    n_rec = sum(1 for f in frames if f[2] == "reclaim")
    lost = max(over100 - len(frames), 0)
    extra = len(frames) > over100
    n_app = len(frames) - n_rec + lost
    st = os.path.join(d, "state.txt")
    stressed = not os.path.exists(st) or any(l.startswith("stress:") for l in _lines(st))
    # the guards matter only to a walk that would pass by excluding frames: with none excluded it is the plain rule
    judged = (share <= MAX_SHARE and not stressed and not extra) or n_rec == 0
    return {"frames": frames, "app": n_app, "reclaim": n_rec, "lost": lost, "share": share, "judged": judged,
            "stressed": stressed, "extra": extra, "sampled": bool(s), "passes": judged and n_app == 0,
            "ff_frames": ff_frames, "ff_spikes": ff_spikes}


def rule_text(d):
    r = rule(d)
    out = ["The frame rule (no frame over %.0f ms after the first 5 s that the app causes; decisions 0057, 0066): %s"
           % (RULE_MS, "PASSES" if r["passes"] else ("NOT JUDGED" if not r["judged"] else "FAILS")),
           "  frames over %.0f ms the app caused: %d%s" % (RULE_MS, r["app"],
               " (%d of them lost from the log)" % r["lost"] if r["lost"] else ""),
           "  frames over %.0f ms excluded as the kernel's memory reclaim: %d" % (RULE_MS, r["reclaim"]),
           "  samples with reclaim: %.2f %% of the walk%s" % (100.0 * r["share"],
               "" if r["share"] <= MAX_SHARE else " (more than %.0f %%: the phone was under pressure through it, walk again)"
               % (100 * MAX_SHARE))]
    if r["ff_frames"] is None:
        out.append("  judged: every frame after the first 5 s (a walk from before the app counted fast-forward apart: "
                   "any frame of it in fast-forward is judged too)")
    else:
        out.append("  judged: the frames played at 1x only (the rules judge normal play; the user, 2026-10-27): %d frames "
                   "in fast-forward left out, %d of them over %.0f ms" % (r["ff_frames"], len(r["ff_spikes"]), RULE_MS))
    if r["stressed"]:
        out.append("  a STRESS=1 walk (memory pressure made on purpose), or no state.txt to tell: not judged")
    if r["extra"]:
        out.append("  more SPIKE lines in the log than the RESULT's over100: not judged (another run's log?)")
    if not r["sampled"]:
        out.append("  no samp.txt (walk with SAMPLE=1): no frame can be excluded")
    for ms, t, why, ev in r["frames"]:
        out.append("  %.1f ms at %.1f s: %s" % (ms, t, "the app's" if why == "app" else "inside reclaim, samples:"))
        out += ["      " + l for l in ev]
    for ms, t in r["ff_spikes"]:
        out.append("  %.1f ms at %.1f s: in fast-forward, not judged" % (ms, t))
    out.append("  evidence: %s (samp.txt, logcat.txt%s)" % (os.path.abspath(d),
               ", trace.pftrace" if os.path.exists(os.path.join(d, "trace.pftrace")) else ""))
    out.append("  judged by tools/plant3d/bench/reclaim_frames.py: reclaim = at least %d page(s) scanned or a stall in a "
               "sample pair overlapping the frame, pairs at most %.1f s apart; walks with reclaim in more than %.0f %% "
               "of their pairs not judged" % (MIN_PAGES, MAX_GAP_S, 100 * MAX_SHARE))
    return "\n".join(out) + "\n"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("dir")
    ap.add_argument("--over", type=float, default=45.0)
    ap.add_argument("--rule", action="store_true", help="only the frame rule's judgement, also written to rule.txt")
    a = ap.parse_args(argv)
    t = rule_text(a.dir)
    if a.rule:
        with open(os.path.join(a.dir, "rule.txt"), "w") as f:
            f.write(t)
    print(t, end="")
    if a.rule or not os.path.exists(os.path.join(a.dir, "frames.csv")) or not os.path.exists(os.path.join(a.dir, "samp.txt")):
        return 0
    print("kernel scanning            frames   GPU over %.0f ms" % a.over)
    for name, n, long_ in bands(a.dir, a.over):
        if n:
            print("  %-22s %8d   %5d (%.2f %%)" % (name, n, long_, 100.0 * long_ / n))
    return 0


if __name__ == "__main__":
    sys.exit(main())
