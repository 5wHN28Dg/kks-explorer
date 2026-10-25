"""tools/plant3d/bench/pftrace.py: a phone walk's Perfetto trace read without Perfetto's tools (decision 0066, "The last
frame spikes"). A trace written here in Perfetto's wire format (sched switches, atrace prints, a process tree):
- Swappy's slices give each GPU frame's time ("waiting for GPU completion" to the "GPU completion|0" counter on the
  same thread), however the prints of other threads interleave;
- a thread's running time inside a frame comes from the switches on every CPU;
- the report names the long frames and the share of their time a named kernel thread ran, against the other frames."""
import io, os, sys, tempfile, unittest

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


def event(ts, pid, kind, body):
    return field(P.EV_TIMESTAMP, ts) + field(P.EV_PID, pid) + field(kind, body)


def switch(prev, nxt, comm):
    return field(P.SW_PREV_PID, prev) + field(P.SW_NEXT_COMM, comm) + field(P.SW_NEXT_PID, nxt)


def bundle(cpu, events):
    return field(P.BUNDLE_CPU, cpu) + b"".join(field(P.BUNDLE_EVENT, e) for e in events)


def packet(body_field, body):
    return field(P.PACKET, field(body_field, body))


MS = 1000000
T0 = 10 * 1000 * MS   # 10 s


def trace():
    tree = field(2, field(1, 300) + field(2, "kworker/0:0") + field(3, 300))
    cpu0 = [event(T0, 0, P.EV_SCHED_SWITCH, switch(0, 0, "swapper/0"))]
    cpu1 = [event(T0, 0, P.EV_SCHED_SWITCH, switch(0, 0, "swapper/1"))]
    prints = []
    t = T0 + 2000 * MS   # frames from 12 s: 20 ms each, the third 100 ms with the worker running 60 ms of it
    for i in range(5):
        ms = 100 if i == 2 else 20
        prints.append(event(t, 501, P.EV_PRINT, field(P.PRINT_BUF, "B|500|waiting for GPU completion %d\n" % i)))
        prints.append(event(t + MS, 502, P.EV_PRINT, field(P.PRINT_BUF, "C|500|GPU completion|1\n")))  # another thread
        prints.append(event(t + ms * MS, 501, P.EV_PRINT, field(P.PRINT_BUF, "C|500|GPU completion|0\n")))
        if i == 2:
            cpu0.append(event(t + 10 * MS, 0, P.EV_SCHED_SWITCH, switch(0, 300, "kworker/0:0")))
            cpu0.append(event(t + 70 * MS, 300, P.EV_SCHED_SWITCH, switch(300, 0, "swapper/0")))
        if i == 4:   # 5 ms of the worker in a short frame
            cpu1.append(event(t + 2 * MS, 0, P.EV_SCHED_SWITCH, switch(0, 300, "kworker/0:0")))
            cpu1.append(event(t + 7 * MS, 300, P.EV_SCHED_SWITCH, switch(300, 0, "swapper/1")))
        t += ms * MS + 5 * MS
    end = event(t + 100 * MS, 0, P.EV_SCHED_SWITCH, switch(0, 0, "swapper/0"))
    return (packet(P.TP_FTRACE, bundle(0, cpu0 + [end])) + packet(P.TP_FTRACE, bundle(1, cpu1 + prints))
            + field(P.PACKET, field(P.TP_PROCESS_TREE, tree)))


class PfTraceTest(unittest.TestCase):
    def setUp(self):
        fd, self.path = tempfile.mkstemp(suffix=".pftrace")
        with os.fdopen(fd, "wb") as f:
            f.write(trace())

    def tearDown(self):
        os.unlink(self.path)

    def test_gpu_frames(self):
        _, prints, names = P.read(self.path)
        frames = P.gpu_frames(prints)
        self.assertEqual([round(ms) for _, ms in frames], [20, 20, 100, 20, 20])
        self.assertAlmostEqual(frames[0][0], 12.0, places=6)
        self.assertEqual(names[300], "kworker/0:0")

    def test_running(self):
        switches, _, _ = P.read(self.path)
        busy = P.Busy(P.running(switches)[300])
        a = 12.0 + 2 * 0.025   # the third frame's start
        self.assertAlmostEqual(busy(a, a + 0.1), 0.060, places=6)
        self.assertAlmostEqual(busy(a, a + 0.03), 0.020, places=6)

    def test_report(self):
        out = io.StringIO()
        self.assertEqual(P.report(self.path, ["kworker/0:0"], 45.0, out), 0)
        r = out.getvalue()
        self.assertIn("5 GPU frames, 1 over 45 ms (longest 100.0 ms)", r)
        self.assertIn("kworker/0:0    ran  60.0 % of the long frames' time,  6.2 % of the others'", r)
        self.assertIn("100.0 ms  kworker/0:0 60.0 ms", r)


if __name__ == "__main__":
    unittest.main()
