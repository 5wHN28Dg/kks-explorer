"""tools/plant3d/bench/pftrace.py: a phone walk's Perfetto trace read without Perfetto's tools (decision 0066, "The last
frame spikes"). A trace written here in Perfetto's wire format (sched switches on two CPUs, atrace prints, fields of
every wire type the reader must skip):
- Swappy's slices give each GPU frame's time ("waiting for GPU completion" to the "GPU completion|0" counter on the
  same thread), however the prints of other threads interleave;
- a named thread's running time inside a frame comes from the switches on every CPU, a run begun before the frame
  counting only from the frame's start, two threads of one name together;
- frames in the trace's first second are left out (the threads' states are not known yet);
- the report names the long frames and the share of their time the named threads ran, against the other frames; a
  trace cut in its last packet is read up to it."""
import io, os, struct, sys, tempfile, unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools', 'plant3d', 'bench'))
import pftrace as P


def varint(n):
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        out.append(b | (0x80 if n else 0))
        if not n:
            return bytes(out)


def field(f, v):
    if isinstance(v, int):
        return varint(f << 3) + varint(v)
    if isinstance(v, str):
        v = v.encode()
    return varint(f << 3 | 2) + varint(len(v)) + v


def fixed(f, v, size):   # wire types 1 and 5 (a field the reader does not use)
    return varint(f << 3 | (1 if size == 8 else 5)) + (struct.pack("<Q", v) if size == 8 else struct.pack("<I", v))


def event(ts, pid, kind, body):
    return field(P.EV_TIMESTAMP, ts) + field(P.EV_PID, pid) + fixed(99, 7, 8) + field(kind, body)


def switch(prev, nxt, comm):
    return field(P.SW_PREV_PID, prev) + fixed(3, 120, 4) + field(P.SW_NEXT_COMM, comm) + field(P.SW_NEXT_PID, nxt)


def run(cpu_events, cpu, t0_ms, t1_ms, tid, comm):
    cpu_events.append(event(t0_ms * MS, 0, P.EV_SCHED_SWITCH, switch(0, tid, comm)))
    cpu_events.append(event(t1_ms * MS, tid, P.EV_SCHED_SWITCH, switch(tid, 0, "swapper/%d" % cpu)))


def bundle(cpu, events):
    return field(P.BUNDLE_CPU, cpu) + b"".join(field(P.BUNDLE_EVENT, e) for e in events)


def packet(body):
    return field(P.PACKET, field(P.TP_FTRACE, body) + fixed(8, 123, 8))


MS = 1000000


def trace():
    cpu0 = [event(10000 * MS, 0, P.EV_SCHED_SWITCH, switch(0, 0, "swapper/0"))]   # the trace starts at 10 s
    cpu1 = [event(10000 * MS, 0, P.EV_SCHED_SWITCH, switch(0, 0, "swapper/1"))]
    prints = []
    # a frame in the first second (10.5 s, 200 ms: left out), then frames from 12 s, 20 ms each with 5 ms between,
    # the third 100 ms: the worker (tid 300) runs from 5 ms before it to 40 ms into it on CPU 0, and another
    # kworker/0:0 (tid 301) 20 ms more on CPU 1; in the fifth, 4 ms of tid 300
    starts = [(10500, 200)]
    t = 12000
    for i in range(5):
        starts.append((t, 100 if i == 2 else 20))
        t += starts[-1][1] + 5
    for n, (t0, ms) in enumerate(starts):
        prints.append(event(t0 * MS, 501, P.EV_PRINT, field(P.PRINT_BUF, "B|500|waiting for GPU completion %d\n" % n)))
        prints.append(event((t0 + 1) * MS, 502, P.EV_PRINT, field(P.PRINT_BUF, "C|500|GPU completion|1\n")))
        prints.append(event((t0 + ms) * MS, 501, P.EV_PRINT, field(P.PRINT_BUF, "C|500|GPU completion|0\n")))
    long0 = starts[3][0]
    run(cpu0, 0, long0 - 5, long0 + 40, 300, "kworker/0:0")
    run(cpu1, 1, long0 + 50, long0 + 70, 301, "kworker/0:0")
    run(cpu1, 1, starts[5][0] + 2, starts[5][0] + 6, 300, "kworker/0:0")
    end = event((t + 100) * MS, 0, P.EV_SCHED_SWITCH, switch(0, 0, "swapper/0"))
    return packet(bundle(0, cpu0 + [end])) + packet(bundle(1, cpu1 + prints))


class PfTraceTest(unittest.TestCase):
    def write(self, data):
        fd, path = tempfile.mkstemp(suffix=".pftrace")
        with os.fdopen(fd, "wb") as f:
            f.write(data)
        self.addCleanup(os.unlink, path)
        return path

    def test_gpu_frames(self):
        prints, spans, switches, cut, t0 = P.read(self.write(trace()), ["kworker/0:0"])
        frames = P.gpu_frames(prints)
        self.assertEqual([round(ms) for _, ms in frames], [200, 20, 20, 100, 20, 20])
        self.assertAlmostEqual(frames[1][0], 12.0, places=6)
        self.assertAlmostEqual(t0, 10.0, places=6)
        self.assertFalse(cut)
        self.assertEqual(switches, 9)

    def test_running(self):
        _, spans, _, _, _ = P.read(self.write(trace()), ["kworker/0:0"])
        busy = P.Busy(spans["kworker/0:0"])
        a = 12.0 + 2 * 0.025   # the long frame's start
        self.assertAlmostEqual(busy(a, a + 0.1), 0.060, places=6)   # 40 ms on CPU 0 (from its start) + 20 on CPU 1
        self.assertAlmostEqual(busy(a, a + 0.03), 0.030, places=6)

    def test_report(self):
        out = io.StringIO()
        self.assertEqual(P.report(self.write(trace()), ["kworker/0:0", "kswapd0"], 45.0, out), 0)
        r = out.getvalue()
        self.assertIn("5 GPU frames, 1 over 45 ms (longest 100.0 ms)", r)   # (not the first second's 200 ms)
        self.assertIn("kworker/0:0    ran  60.0 % of the long frames' time,  5.0 % of the others'", r)
        self.assertIn("kswapd0        ran   0.0 % of the long frames' time,  0.0 % of the others'", r)
        self.assertIn("100.0 ms  kworker/0:0 60.0 ms  kswapd0 0.0 ms", r)

    def test_cut(self):
        data = trace()
        out = io.StringIO()
        self.assertEqual(P.report(self.write(data[:-40]), ["kworker/0:0"], 45.0, out), 0)
        self.assertIn("cut packet", out.getvalue())


if __name__ == "__main__":
    unittest.main()
