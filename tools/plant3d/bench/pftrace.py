#!/usr/bin/env python3
"""Reads a Perfetto system trace of a phone walk (apps/plant3d/phone/trace.pbtxt) without Perfetto's own tools (a
small protobuf reader, standard library only) and lines each of the app's GPU frames up with the kernel threads
running meanwhile (decision 0066, "The last frame spikes").

  pftrace.py TRACE [--threads kswapd0,kworker/0:0] [--over 45]

Each GPU frame's time is Swappy's: from its "waiting for GPU completion N" slice (the frame handed to the GPU) to the
"GPU completion|0" counter that follows on the same thread (its fence signalled), as Godot's Android frame pacing
writes them through atrace. For every named kernel thread the report gives how much of the long frames (over --over
ms) and of the others it ran; then each long frame with those threads' time in it.
"""
import argparse
import bisect
import collections
import sys

# field numbers: protos/perfetto/trace/trace_packet.proto, ftrace/ftrace_event_bundle.proto, ftrace/ftrace_event.proto,
# ftrace/sched.proto, ftrace/ftrace.proto, ps/process_tree.proto
PACKET = 1
TP_FTRACE = 1
TP_PROCESS_TREE = 2
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


def read(path):
    """The trace's sched switches [(ts_ns, cpu, prev_pid, next_pid, next_comm)], atrace prints [(ts_ns, pid, text)],
    and thread names {tid: name} (process tree, then the switches' comms)."""
    b = open(path, "rb").read()
    switches, prints, names = [], [], {}
    for f, t, span in fields(b):
        if f != PACKET or t != 2:
            continue
        for pf, pt, pv in fields(b, *span):
            if pf == TP_FTRACE and pt == 2:
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
                                m = {k: v for k, _, v in fields(b, *ev)}
                                comm = text(b, m[SW_NEXT_COMM]) if SW_NEXT_COMM in m else ""
                                switches.append((ts, cpu, m.get(SW_PREV_PID, 0), m.get(SW_NEXT_PID, 0), comm))
                            elif ef == EV_PRINT and et == 2:
                                m = {k: v for k, _, v in fields(b, *ev)}
                                if PRINT_BUF in m:
                                    prints.append((ts, pid, text(b, m[PRINT_BUF]).rstrip("\n")))
            elif pf == TP_PROCESS_TREE and pt == 2:
                for qf, qt, qv in fields(b, *pv):
                    if qf == 2 and qt == 2:   # Thread {tid = 1, name = 2, tgid = 3}
                        m = {k: v for k, _, v in fields(b, *qv)}
                        if 2 in m:
                            names[m.get(1, 0)] = text(b, m[2])
    switches.sort()
    prints.sort()
    for ts, cpu, prev, nxt, comm in switches:
        if nxt and nxt not in names and comm:
            names[nxt] = comm
    return switches, prints, names


def gpu_frames(prints):
    """[(start_s, ms)] per frame from Swappy's atrace slices."""
    out, start = [], {}
    for ts, pid, s in prints:
        if s.startswith("B|") and "waiting for GPU completion" in s:
            start[pid] = ts
        elif s.startswith("C|") and s.split("|")[2:4] == ["GPU completion", "0"] and pid in start:
            out.append((start[pid] / 1e9, (ts - start.pop(pid)) / 1e6))
    return out


def running(switches):
    """{tid: [(start_s, end_s)]} for every thread that ran."""
    run, cur = collections.defaultdict(list), {}
    for ts, cpu, prev, nxt, comm in switches:
        t = ts / 1e9
        if cpu in cur:
            s0, tid = cur[cpu]
            run[tid].append((s0, t))
        cur[cpu] = (t, nxt)
    return run


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
    switches, prints, names = read(path)
    frames = gpu_frames(prints)
    run = running(switches)
    if not frames:
        print("no GPU frames (Swappy's atrace slices: the trace needs atrace_categories gfx and atrace_apps)", file=out)
        return 1
    first = switches[0][0] / 1e9 if switches else frames[0][0]
    frames = [f for f in frames if f[0] > first + 1.0]   # (the trace's first second: threads' states unknown)
    long_ = [f for f in frames if f[1] > over]
    print("%d GPU frames, %d over %.0f ms (longest %.1f ms)" % (len(frames), len(long_), over, max(f[1] for f in frames)), file=out)
    busy = {}
    for name in threads:
        tids = [t for t, n in names.items() if n == name]
        busy[name] = [Busy(run[t]) for t in tids if t in run]
        def share(fs):
            tot = sum(ms for _, ms in fs) / 1000.0
            ran = sum(b(a, a + ms / 1000.0) for a, ms in fs for b in busy[name])
            return 100.0 * ran / tot if tot > 0 else 0.0
        print("  %-14s ran %5.1f %% of the long frames' time, %4.1f %% of the others'" % (
            name, share(long_), share([f for f in frames if f[1] <= over])), file=out)
    for a, ms in long_:
        print("  %.3f s  %6.1f ms  " % (a, ms) + "  ".join("%s %.1f ms" % (n, 1000.0 * sum(b(a, a + ms / 1000.0) for b in busy[n])) for n in threads), file=out)
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
