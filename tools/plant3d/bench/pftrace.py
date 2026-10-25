#!/usr/bin/env python3
"""Reads a Perfetto system trace of a phone walk (apps/plant3d/phone/trace.pbtxt) without Perfetto's own tools (a
small protobuf reader, standard library only) and lines each of the app's GPU frames up with the kernel threads
running meanwhile (decision 0066, "The last frame spikes").

  pftrace.py TRACE [--threads kswapd0,kworker/0:0] [--over 45]

It maps the file and keeps only Swappy's marks and the named threads' running spans (a 1.2 GB walk's trace: about
1 GB of memory and ten minutes here; run it under a memory cap). A thread is named by the scheduler's comm, so all
threads of one name count together.

Each GPU frame's time is Swappy's: from its "waiting for GPU completion N" slice (the frame handed to the GPU) to the
"GPU completion|0" counter that follows on the same thread (its fence signalled), as Godot's Android frame pacing
writes them through atrace (the time also holds how late that thread wakes after the fence: under a busy CPU it is
longer than the GPU's own work, which Godot's frames.csv measures). For every named kernel thread the report gives how much of the long frames (over --over
ms) and of the others it ran; then each long frame with those threads' time in it.
"""
import argparse
import bisect
import collections
import mmap
import os
import sys

# field numbers: protos/perfetto/trace/trace_packet.proto, ftrace/ftrace_event_bundle.proto, ftrace/ftrace_event.proto,
# ftrace/sched.proto, ftrace/ftrace.proto
PACKET = 1
TP_FTRACE = 1
BUNDLE_CPU = 1
BUNDLE_EVENT = 2
EV_TIMESTAMP = 1
EV_PID = 2
EV_PRINT = 3
EV_SCHED_SWITCH = 4
PRINT_BUF = 2
SW_PREV_PID = 2
SW_NEXT_COMM = 5
SW_NEXT_PID = 6


def varint(b, i):
    r = s = 0
    while True:
        c = b[i]
        i += 1
        r |= (c & 0x7F) << s
        if c < 0x80:
            return r, i
        s += 7


def fields(b, start=0, end=None):
    """(field, wire type, value) of one message; a length-delimited value is its (start, end) in b."""
    i, end = start, len(b) if end is None else end
    while i < end:
        k, i = varint(b, i)
        f, t = k >> 3, k & 7
        if t == 0:
            v, i = varint(b, i)
        elif t == 1:
            v, i = int.from_bytes(b[i:i + 8], "little"), i + 8
        elif t == 2:
            n, i = varint(b, i)
            v, i = (i, i + n), i + n
        elif t == 5:
            v, i = int.from_bytes(b[i:i + 4], "little"), i + 4
        else:
            raise ValueError("wire type %d at byte %d" % (t, i))
        yield f, t, v


def text(b, span):
    return b[span[0]:span[1]].decode("utf-8", "replace")


def read(path, threads=()):
    """One pass over the trace (mapped, not read into memory: a walk's trace is 1-2 GB): Swappy's prints
    [(ts_ns, pid, text)], and for every thread whose name (sched_switch's comm) is in `threads` its running spans
    {name: [(start_s, end_s)]} (threads of one name together, e.g. kworker/0:0 over the trace's life); also how many
    sched switches it held, whether it ended short (a cut last packet) and its first switch's time (s)."""
    wanted = set(threads)
    prints, spans, cur = [], collections.defaultdict(list), {}
    switches = 0
    t0 = None
    cut = False
    with open(path, "rb") as fh:
        b = mmap.mmap(fh.fileno(), 0, access=mmap.ACCESS_READ) if os.path.getsize(path) else b""
        try:
            for f, t, span in fields(b):
                if f != PACKET or t != 2:
                    continue
                for pf, pt, pv in fields(b, *span):
                    if pf != TP_FTRACE or pt != 2:
                        continue
                    cpu = 0
                    for bf, bt, bv in fields(b, *pv):
                        if bf == BUNDLE_CPU and bt == 0:
                            cpu = bv
                        elif bf == BUNDLE_EVENT and bt == 2:
                            ts = pid = 0
                            for ef, et, ev in fields(b, *bv):
                                if ef == EV_TIMESTAMP:
                                    ts = ev
                                elif ef == EV_PID:
                                    pid = ev
                                elif ef == EV_SCHED_SWITCH and et == 2:
                                    switches += 1
                                    t0 = ts / 1e9 if t0 is None else min(t0, ts / 1e9)
                                    m = {k: v for k, _, v in fields(b, *ev)}
                                    comm = text(b, m[SW_NEXT_COMM]) if SW_NEXT_COMM in m else ""
                                    if cpu in cur and cur[cpu][1] in wanted:
                                        spans[cur[cpu][1]].append((cur[cpu][0], ts / 1e9))
                                    cur[cpu] = (ts / 1e9, comm)
                                elif ef == EV_PRINT and et == 2:
                                    m = {k: v for k, _, v in fields(b, *ev)}
                                    if PRINT_BUF in m:
                                        s_ = text(b, m[PRINT_BUF])
                                        if "GPU completion" in s_:
                                            prints.append((ts, pid, s_.rstrip("\n")))
        except (IndexError, ValueError):
            cut = True   # (a trace stopped while writing: what came before is still good)
    prints.sort()
    for v in spans.values():
        v.sort()
    return prints, spans, switches, cut, t0


def gpu_frames(prints):
    """[(start_s, ms)] per frame from Swappy's atrace slices."""
    out, start = [], {}
    for ts, pid, s in prints:
        if s.startswith("B|") and "waiting for GPU completion" in s:
            start[pid] = ts
        elif s.startswith("C|") and s.split("|")[2:4] == ["GPU completion", "0"] and pid in start:
            out.append((start[pid] / 1e9, (ts - start.pop(pid)) / 1e6))
    return out


class Busy:
    def __init__(self, spans):
        self.spans = spans
        self.starts = [s for s, _ in spans]

    def __call__(self, a, b):
        """Seconds the thread ran within [a, b)."""
        i = max(0, bisect.bisect_left(self.starts, a) - 1)
        t = 0.0
        while i < len(self.spans) and self.spans[i][0] < b:
            s0, s1 = self.spans[i]
            if s1 > a:
                t += min(s1, b) - max(s0, a)
            i += 1
        return t


def report(path, threads, over, out=sys.stdout):
    prints, spans, switches, cut, t0 = read(path, threads)
    if cut:
        print("the trace ends in a cut packet: read up to it", file=out)
    if not switches:
        print("no sched switches in the trace (a newer Perfetto's compact_sched is not read here)", file=out)
    frames = gpu_frames(prints)
    if not frames:
        print("no GPU frames (Swappy's atrace slices: the trace needs atrace_categories gfx and atrace_apps)", file=out)
        return 1
    first = t0 if t0 is not None else frames[0][0]
    frames = [f for f in frames if f[0] > first + 1.0]   # (the trace's first second: threads' states unknown)
    if not frames:
        print("no GPU frames after the trace's first second", file=out)
        return 1
    long_ = [f for f in frames if f[1] > over]
    print("%d GPU frames, %d over %.0f ms (longest %.1f ms)" % (len(frames), len(long_), over, max(f[1] for f in frames)), file=out)
    busy = {n: Busy(spans.get(n, [])) for n in threads}
    def share(name, fs):
        tot = sum(ms for _, ms in fs) / 1000.0
        return 100.0 * sum(busy[name](a, a + ms / 1000.0) for a, ms in fs) / tot if tot > 0 else 0.0
    for name in threads:
        print("  %-14s ran %5.1f %% of the long frames' time, %4.1f %% of the others'" % (
            name, share(name, long_), share(name, [f for f in frames if f[1] <= over])), file=out)
    for a, ms in long_:
        print("  %.3f s  %6.1f ms  " % (a, ms) + "  ".join("%s %.1f ms" % (n, 1000.0 * busy[n](a, a + ms / 1000.0)) for n in threads), file=out)
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("trace")
    ap.add_argument("--threads", default="kswapd0,kworker/0:0")
    ap.add_argument("--over", type=float, default=45.0)
    a = ap.parse_args(argv)
    return report(a.trace, [t for t in a.threads.split(",") if t], a.over)


if __name__ == "__main__":
    sys.exit(main())
