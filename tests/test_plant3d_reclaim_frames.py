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
            # direct reclaim counts too; a count that drops (a core offline) leaves that sample out
            rows2 = [r.split() for r in rows]
            rows2[2][8] = "2000"   # direct: 2,000 pages between 115.2 and 115.4 (10,000/s) ...
            for r in rows2[3:]:
                r[8] = "2000"
            rows2[7][7] = "0"      # ... and kswapd's count drops between 116.2 and 116.4
            open(os.path.join(d, "samp.txt"), "w").write("\n".join(" ".join(r) for r in rows2) + "\n")
            open(os.path.join(d, "frames.csv"), "a").write("15300,20,10.0\n16300,20,90.0\n")
            got = {n: (a, b) for n, a, b in R.bands(d, 45.0)}
            self.assertEqual(got["5,000-20,000 pages/s"], (2, 1))   # 15,300 (direct) and 16,100; 16,300 left out
            self.assertEqual(got["none"], (2, 1))
            # a missing column is refused, not read shifted
            open(os.path.join(d, "samp.txt"), "w").write("115.00 0 0 0 0 0 0 0 0 0 0 0\n")
            with self.assertRaises(SystemExit):
                R.bands(d, 45.0)


def _walk(d, samples, spikes, over100=None, stress=False, logcat_extra=""):
    """A fake walk: epoch = boot clock + 1,000,000 s; samples [(boot s, kswapd pages, direct pages, stalls)];
    spikes [(boot s it was logged at, ms)]."""
    open(os.path.join(d, "clock.txt"), "w").write("50.00 40.00\n1000050.000000000\n")
    open(os.path.join(d, "samp.txt"), "w").write("".join(
        "%.2f 546000000 90 0 0 %d 0 %d %d 0 400000 2000000 900000\n" % (t, st, k, dr) for t, k, dr, st in samples))
    open(os.path.join(d, "logcat.txt"), "w").write(logcat_extra + "".join(
        "%.3f  1  2 I godot   : plant: SPIKE %.1f ms at %.1f s, at (1, 2, 3)\n" % (1000000 + t, ms, t - 100) for t, ms in spikes))
    open(os.path.join(d, "result.txt"), "w").write(
        "RESULT tier=lean+vis frames=100 max=1ms over100=%d gpu_median=1ms\n" % (len(spikes) if over100 is None else over100))
    open(os.path.join(d, "state.txt"), "w").write("before: x\n" + ("stress: 2 MB/s\n" if stress else ""))


def _quiet(n=600, t0=100.0):
    """n samples 0.2 s apart from t0 with no reclaim."""
    return [(t0 + 0.2 * i, 1000, 0, 0) for i in range(n)]


class FrameRuleTest(unittest.TestCase):
    def test_fast_forward_not_judged(self):
        """The frame rules judge normal play only (the user, 2026-10-27): a SPIKE_FF line (a frame over 100 ms in
        fast-forward, app/walk_frames.gd) is listed but neither the app's nor excluded; the output says the frames at
        1x are judged. A walk whose RESULT has no ff_frames= is from before: said so."""
        with tempfile.TemporaryDirectory() as d:
            ff = ("%.3f  1  2 I godot   : plant: SPEED fast-forward at 40.0 s, uptime 1 ms\n" % 1000140.0 +
                  "%.3f  1  2 I godot   : plant: SPIKE_FF 180.0 ms at 45.0 s, at (1, 2, 3)\n" % 1000145.0 +
                  "%.3f  1  2 I godot   : plant: SPEED normal at 50.0 s, uptime 2 ms\n" % 1000150.0)
            _walk(d, _quiet(), [], over100=0, logcat_extra=ff)
            t = R.rule_text(d)   # (a RESULT of before: no ff_frames=)
            self.assertIn("judged: every frame after the first 5 s (a walk from before", t)
            with open(os.path.join(d, "result.txt"), "w") as f:
                f.write("FASTFORWARD frames=600 over100=2 max=180.0ms: not judged\n"
                        "RESULT tier=lean+vis frames=100 max=1ms over100=0 ff_frames=600 gpu_median=1ms\n")
            r = R.rule(d)
            self.assertEqual((r["app"], r["reclaim"], r["lost"]), (0, 0, 0))
            self.assertTrue(r["passes"])
            self.assertEqual(r["ff_spikes"], [(180.0, 45.0)])
            t = R.rule_text(d)
            self.assertIn("PASSES", t)
            self.assertIn("judged: the frames played at 1x only", t)
            # (the FASTFORWARD line's count: one of its two SPIKE_FF lines was lost from the log)
            self.assertIn("600 frames in fast-forward left out, 2 of them over 100 ms", t)
            self.assertIn("180.0 ms at 45.0 s: in fast-forward, not judged", t)
            # a walk in fast-forward throughout (speed=fast): no frame at 1x, nothing judged, so it doesn't pass
            with open(os.path.join(d, "result.txt"), "w") as f:
                f.write("FASTFORWARD frames=600 over100=2 max=180.0ms: not judged\n"
                        "RESULT tier=lean+vis renderer=mobile walk=frames frames=0 over100=0 ff_frames=600 stuck=0\n")
            r = R.rule(d)
            self.assertFalse(r["passes"])
            self.assertFalse(r["judged"])
            t = R.rule_text(d)
            self.assertIn("NOT JUDGED", t)
            self.assertIn("no frame at 1x (every frame in fast-forward): nothing to judge", t)

    def test_reclaim_excluded_and_app_counted(self):
        with tempfile.TemporaryDirectory() as d:
            s = _quiet()
            # kswapd scans 3 pages between 150.0 and 150.2 (all later counts higher by 3)
            s = [(t, k + (3 if t > 150.1 else 0), dr, st) for t, k, dr, st in s]
            # a 120 ms frame logged at 150.1 (from 149.98: overlaps the reclaiming sample), one of 105 ms at 160.0
            # (quiet)
            _walk(d, s, [(150.1, 120.0), (160.0, 105.0)], over100=2)
            r = R.rule(d)
            self.assertEqual([(f[0], f[2]) for f in r["frames"]], [(120.0, "reclaim"), (105.0, "app")])
            self.assertEqual((r["app"], r["reclaim"], r["lost"]), (1, 1, 0))
            self.assertFalse(r["passes"])
            self.assertTrue(r["judged"])
            self.assertEqual(len(r["frames"][0][3]), 2)   # the two sample lines that show it
            self.assertTrue(r["frames"][0][3][1].startswith("150.20 "))
            t = R.rule_text(d)
            self.assertIn("FAILS", t)
            self.assertIn("150.20 546000000", t)
            # main() writes the judgement beside the walk
            R.main([d, "--rule"])
            self.assertIn("excluded as the kernel's memory reclaim: 1", open(os.path.join(d, "rule.txt")).read())

    def test_frame_just_before_reclaim_is_the_apps(self):
        with tempfile.TemporaryDirectory() as d:
            s = [(t, k + (3 if t > 150.1 else 0), dr, st) for t, k, dr, st in _quiet()]
            # logged at 149.99 (149.87-149.99): inside the quiet sample 149.8-150.0 only
            _walk(d, s, [(149.99, 120.0)])
            self.assertEqual(R.rule(d)["app"], 1)

    def test_direct_reclaim_and_stalls(self):
        with tempfile.TemporaryDirectory() as d:
            s = [(t, k, dr + (5 if t > 150.1 else 0), st) for t, k, dr, st in _quiet()]
            s = [(t, k, dr, st + (1 if t > 160.1 else 0)) for t, k, dr, st in s]
            _walk(d, s, [(150.1, 120.0), (160.1, 130.0)])
            r = R.rule(d)
            self.assertEqual((r["app"], r["reclaim"]), (0, 2))
            self.assertTrue(r["passes"])

    def test_lost_spikes_counted_as_the_apps(self):
        with tempfile.TemporaryDirectory() as d:
            s = [(t, k + (3 if t > 150.1 else 0), dr, st) for t, k, dr, st in _quiet()]
            _walk(d, s, [(150.1, 120.0)], over100=3)
            r = R.rule(d)
            self.assertEqual((r["app"], r["reclaim"], r["lost"]), (2, 1, 2))
            self.assertFalse(r["passes"])

    def test_no_proof_no_exclusion(self):
        with tempfile.TemporaryDirectory() as d:
            # a 2 s gap in the samples around the frame, with pages scanned across it: proves nothing
            s = [x for x in _quiet() if not 149.0 < x[0] < 151.0]
            s = [(t, k + (3 if t > 150 else 0), dr, st) for t, k, dr, st in s]
            # a counter that falls (a core offline) proves nothing either
            s = [(t, k - (500 if t > 160.1 else 0), dr + (9 if t > 160.1 else 0), st) for t, k, dr, st in s]
            # a frame after the last sample
            _walk(d, s, [(150.1, 120.0), (160.1, 110.0), (500.0, 101.0)])
            r = R.rule(d)
            self.assertEqual((r["app"], r["reclaim"]), (3, 0))
            # without samp.txt (and clock.txt: a walk without SAMPLE=1) every frame is the app's
            os.remove(os.path.join(d, "samp.txt"))
            os.remove(os.path.join(d, "clock.txt"))
            r = R.rule(d)
            self.assertEqual((r["app"], r["sampled"]), (3, False))
            self.assertIn("no samp.txt", R.rule_text(d))

    def test_walks_under_pressure_not_judged(self):
        with tempfile.TemporaryDirectory() as d:
            # reclaim in 7 of 599 sample pairs (1.2 %) and a frame excluded by it (logged at 110.15): not judged
            s = [(t, k + 2 * sum(1 for j in range(7) if t > 110.1 + j), dr, st) for t, k, dr, st in _quiet()]
            _walk(d, s, [(110.15, 120.0)])
            r = R.rule(d)
            self.assertEqual(r["reclaim"], 1)
            self.assertFalse(r["judged"])
            self.assertFalse(r["passes"])
            self.assertIn("NOT JUDGED", R.rule_text(d))
            # the same walk with no frame over 100 ms: the plain rule, passes
            _walk(d, s, [])
            self.assertTrue(R.rule(d)["passes"])
            # 5 of 599 (0.8 %): judged, passes
            s = [(t, k + 2 * sum(1 for j in range(5) if t > 110.1 + j), dr, st) for t, k, dr, st in _quiet()]
            _walk(d, s, [(110.15, 120.0)])
            self.assertTrue(R.rule(d)["passes"])
            # a STRESS=1 walk never passes by exclusion, nor one without state.txt
            _walk(d, s, [(110.15, 120.0)], stress=True)
            r = R.rule(d)
            self.assertFalse(r["passes"])
            self.assertIn("STRESS=1", R.rule_text(d))
            _walk(d, s, [(110.15, 120.0)])
            os.remove(os.path.join(d, "state.txt"))
            self.assertFalse(R.rule(d)["passes"])

    def test_share_counts_known_pairs_in_the_walk(self):
        with tempfile.TemporaryDirectory() as d:
            # 7 reclaiming pairs among 300 known ones in the walk (2.3 %), diluted by 300 samples 1.5 s apart: still
            # not judged; samples before the first frame (loading) left out of the share
            s = [(100.0 + 0.2 * i, 1000, 0, 0) for i in range(300)]
            s = [(t, k + 2 * sum(1 for j in range(7) if t > 110.1 + j), dr, st) for t, k, dr, st in s]
            k = s[-1][1]
            s += [(160.0 + 1.5 * i, k, 0, 0) for i in range(1, 300)]
            _walk(d, s, [(110.15, 120.0)])
            self.assertFalse(R.rule(d)["judged"])
            # with the walk's first frame logged at 120.0, the reclaim before it (loading) does not count
            first = "%.3f  1  2 I godot   : plant: first frame drawn 9000 ms after the engine started\n" % (1000000 + 120.0)
            s2 = [(t, k2 + (50 if t > 150.1 else 0), dr, st) for t, k2, dr, st in s]
            _walk(d, s2, [(150.15, 120.0)], logcat_extra=first)
            r = R.rule(d)
            self.assertEqual(r["reclaim"], 1)
            self.assertTrue(r["passes"])

    def test_log_oddities(self):
        with tempfile.TemporaryDirectory() as d:
            s = [(t, k + (3 if t > 150.1 else 0), dr, st) for t, k, dr, st in _quiet()]
            # a duplicated line counts once; a "100.0" line is a frame over 100 ms
            _walk(d, s, [(150.1, 120.0), (150.1, 120.0), (160.0, 100.0)], over100=2)
            r = R.rule(d)
            self.assertEqual([(f[0], f[2]) for f in r["frames"]], [(120.0, "reclaim"), (100.0, "app")])
            self.assertEqual((r["app"], r["lost"]), (1, 0))
            # more SPIKE lines than over100 (another run's log): an exclusion is not trusted
            _walk(d, s, [(150.1, 120.0), (160.0, 105.0)], over100=1)
            r = R.rule(d)
            self.assertFalse(r["judged"])
            self.assertFalse(r["passes"])
            # no logcat.txt: every over100 frame lost, the app's
            os.remove(os.path.join(d, "logcat.txt"))
            r = R.rule(d)
            self.assertEqual((r["app"], r["lost"]), (1, 1))

    def test_samp_oddities(self):
        with tempfile.TemporaryDirectory() as d:
            s = [(t, k + (3 if t > 150.1 else 0), dr, st) for t, k, dr, st in _quiet()]
            _walk(d, s, [(150.1, 120.0)])
            lines = open(os.path.join(d, "samp.txt")).read().splitlines()
            # a non-numeric line early on: the evidence printed stays in step with the samples
            lines[3] = " ".join(["x"] * 13)
            # a last line cut short (the sampler stopped mid-write): left out
            open(os.path.join(d, "samp.txt"), "w").write("\n".join(lines) + "\n115.00 0 0\n")
            r = R.rule(d)
            self.assertEqual(r["reclaim"], 1)
            self.assertTrue(r["frames"][0][3][0].startswith("150.00 "))
            self.assertTrue(r["frames"][0][3][1].startswith("150.20 "))
            # no rule.txt without --rule
            R.main([d])
            self.assertFalse(os.path.exists(os.path.join(d, "rule.txt")))

    def test_unfinished_walk_refused(self):
        with tempfile.TemporaryDirectory() as d:
            _walk(d, _quiet(), [])
            open(os.path.join(d, "result.txt"), "w").write("loaded the plant\n")
            with self.assertRaises(SystemExit):
                R.rule(d)


class FramesShTest(unittest.TestCase):
    def test_sample_walks_are_judged(self):
        """phone/frames.sh judges every SAMPLE=1 walk after its samples are pulled (rule.txt beside the walk)."""
        sh = open(os.path.join(ROOT, "apps", "plant3d", "phone", "frames.sh")).read()
        pull = sh.index('a pull "$SAMPLE_F" "$OUT/samp.txt"')
        judge = sh.index('reclaim_frames.py" --rule "$OUT"')
        self.assertLess(pull, judge)
        self.assertLess(judge, sh.index('if [ -n "$stress_on" ]'))   # inside the sampler's part of cleanup

    def test_screen_counted_at_1x(self):
        """The frame rules judge normal play only (the user, 2026-10-27): phone/frames.sh counts what the screen
        showed again with the result's SPEED lines (sf_frames.py --speeds) once result.txt is final, into
        sf_summary.txt, before it prints it."""
        sh = open(os.path.join(ROOT, "apps", "plant3d", "phone", "frames.sh")).read()
        final = sh.index('[ -s "$OUT/result.txt" ] || sed')
        count = sh.index('sf_frames.py" "$OUT/sf.txt" --speeds "$OUT/result.txt"')
        self.assertLess(sh.index("wait $sf"), count)
        self.assertLess(final, count)
        self.assertLess(count, sh.index('cat "$OUT/sf_summary.txt"'))
        self.assertIn('mv "$OUT/sf_summary.new" "$OUT/sf_summary.txt"', sh)


if __name__ == "__main__":
    unittest.main()
