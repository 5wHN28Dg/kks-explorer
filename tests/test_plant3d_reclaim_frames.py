"""tools/plant3d/bench/reclaim_frames.py: a walk's frames against the kernel's reclaim (decision 0066). A fake results
folder: the engine starts at boot clock 100.0 s (the log's epoch time less the first frame's ms, less clock.txt's
offset); frames after the first 5 s fall in the 200 ms samples they began in, banded by kswapd's pages scanned a
second there; frames in the first 5 s and outside the samples are left out."""
import os, sys, tempfile, unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools', 'plant3d', 'bench'))
import reclaim_frames as R


class ReclaimFramesTest(unittest.TestCase):
    def test_bands(self):
        with tempfile.TemporaryDirectory() as d:
            # epoch = boot + 1,000,000 s; the first frame at engine 10 s, logged at boot 110.0
            open(os.path.join(d, "clock.txt"), "w").write("50.00 40.00\n1000050.000000000\n")
            open(os.path.join(d, "logcat.txt"), "w").write(
                "1000110.000  1  2 I godot   : plant: first frame drawn 10000 ms after the engine started\n")
            # samples every 0.2 s from boot 115.0 to 117.0; kswapd scans 0 until 116.0, then 2,000 pages a sample
            # (10,000 pages/s) to 116.6, then 10,000 a sample (50,000 pages/s)
            rows, k = [], 0
            for i in range(11):
                t = 115.0 + 0.2 * i
                rows.append("%.2f 546000000 90 0 0 0 0 %d 0 0 400000 2000000 900000" % (t, k))
                k += 0 if t < 116.0 - 1e-9 else (2000 if t < 116.6 - 1e-9 else 10000)
            open(os.path.join(d, "samp.txt"), "w").write("\n".join(rows) + "\n")
            # frames (engine ms): 14,900 is in the first 5 s after the first frame (10 s + 5 s), 19,000 after the
            # samples; the rest: 15,100 and 15,500 (no scanning), 16,100 (10,000/s), 16,700 and 16,900 (50,000/s)
            frames = [(14900, 90.0), (15100, 20.0), (15500, 50.0), (16100, 60.0), (16700, 80.0), (16900, 20.0), (19000, 99.0)]
            open(os.path.join(d, "frames.csv"), "w").write("t_ms,frame_ms,gpu_ms\n" + "".join(
                "%d,20,%.1f\n" % f for f in frames))
            got = {n: (a, b) for n, a, b in R.bands(d, 45.0)}
            self.assertEqual(got["none"], (2, 1))
            self.assertEqual(got["5,000-20,000 pages/s"], (1, 1))
            self.assertEqual(got["20,000 pages/s or more"], (2, 1))
            self.assertEqual(got["under 5,000 pages/s"], (0, 0))


if __name__ == "__main__":
    unittest.main()
