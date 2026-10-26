"""tools/plant3d/bench/gpu_cycles.py and shadow_ab.py: the Note 9's GPU work in cycles (decision 0057, "The shadow
casters"). A fake results folder as in test_plant3d_reclaim_frames: the engine starts at boot clock 100.0 s; a frame's
cycles are its GPU time times the Mali clock (kHz, samp.txt's second column) of the 200 ms sample it began in."""
import os, sys, tempfile, unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools', 'plant3d', 'bench'))
import gpu_cycles as G
import shadow_ab as A


def _folder(d, clock_at, t_end):
    """clock.txt and logcat.txt for an engine started at boot 100.0 s; samples every 0.2 s from boot 110.0 to t_end,
    the clock (kHz) clock_at(boot s)."""
    open(os.path.join(d, "clock.txt"), "w").write("50.00 40.00\n1000050.000000000\n")
    open(os.path.join(d, "logcat.txt"), "w").write(
        "1000110.000  1  2 I godot   : plant: first frame drawn 10000 ms after the engine started\n")
    rows, i = [], 0
    while 110.0 + 0.2 * i <= t_end + 1e-9:
        t = 110.0 + 0.2 * i
        rows.append("%.2f %d 90 0 0 0 0 0 0 0 400000 2000000 900000" % (t, clock_at(t)))
        i += 1
    open(os.path.join(d, "samp.txt"), "w").write("\n".join(rows) + "\n")


class GpuCyclesTest(unittest.TestCase):
    def test_cycles(self):
        with tempfile.TemporaryDirectory() as d:
            # 400 MHz to boot 116.0, then 200 MHz (the phone warm)
            _folder(d, lambda t: 400000 if t < 116.0 - 1e-9 else 200000, 117.0)
            # engine ms: 10,000 is the first frame (in the first 5 s: left out); 20 ms at 400 MHz = 8 M cycles,
            # 10 ms at 400 MHz = 4, 20 ms at 200 MHz = 4
            open(os.path.join(d, "frames.csv"), "w").write("t_ms,gpu_ms,draws\n10000,90,500\n15100,20,500\n"
                                                           "15500,10,600\n16100,20,700\n")
            self.assertEqual([(g, c) for g, c, _ in G.frames(d)], [(20.0, 400000), (10.0, 400000), (20.0, 200000)])
            s = G.summary(d)
            self.assertIn("3 frames, 5.33 M cycles a frame (median 4.00, p95 8.00)", s)
            self.assertIn("GPU 16.67 ms, clock 333 MHz, draws 600", s)


class ShadowAbTest(unittest.TestCase):
    def test_groups(self):
        with tempfile.TemporaryDirectory() as d:
            _folder(d, lambda t: 500000, 145.0)
            open(os.path.join(d, "walk.txt"), "w").write("walk=frames\nshadow_ab=kerbs,lamp_+roof_steel\n")
            # a frame every 0.1 s from engine 15.0 s; a switch every 2 s from 16.0: all on (10 M cycles a frame:
            # 20 ms at 500 MHz), kerbs off (9), lamps and steel off (7.5), round and round, four rounds
            cost = {0: 20.0, 1: 18.0, 2: 15.0}
            lines, switches = [], 0
            for k in range(150, 421):
                t = k / 10.0
                ev = ""
                if t >= 16.0 - 1e-9 and abs((t - 16.0) / 2.0 - round((t - 16.0) / 2.0)) < 1e-9:
                    switches += 1
                    ev = "shadow_ab+1"
                lines.append("%d,%.1f,500,%s\n" % (round(t * 1000), cost[switches % 3], ev))
            open(os.path.join(d, "frames.csv"), "w").write("t_ms,gpu_ms,draws,events\n" + "".join(lines))
            r = A.report(d)
            self.assertIn("all on: 10.00 Mcycles a frame", r)
            self.assertRegex(r, r"kerbs +off: -1\.00 Mcycles")
            self.assertRegex(r, r"lamp_\+roof_steel +off: -2\.50 Mcycles")


if __name__ == '__main__':
    unittest.main()
