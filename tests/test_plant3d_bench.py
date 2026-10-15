"""The 3D plant engine bench (tools/plant3d/bench, decision 0041), run headless with the pinned Godot:
- a walk with the phone tier's levers ends with its RESULT, SPLIT and PER_MINUTE lines in result.txt;
- the visibility-range lever (vis) gives a range only to the parts R9a lets go far away (bolts, motor fins), and never
  fades one before the distance where its smallest feature is still 1 px on the Note 9's screen, counted from the
  farthest corner of its cell (Godot measures a range to the centre of the instance's box);
- an unknown lever is reported, not ignored silently.
Needs the Godot editor (KKS_GODOT, else the path tools/plant3d/bench/fetch_godot.sh installs it to); skipped without.
  .venv/bin/python -m unittest tests.test_plant3d_bench"""
import math, os, re, subprocess, tempfile, unittest

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
BENCH = os.path.join(REPO, 'tools', 'plant3d', 'bench')
GODOT = os.environ.get('KKS_GODOT') or os.path.expanduser('~/.local/kksdev/godot/Godot_v4.7.2-stable_linux.x86_64')

CHECK = r'''extends SceneTree
# Loads the bench scene, lets it build and dress the plant, then checks every visibility range against the rule.
func _initialize() -> void:
	var bench = load("res://main.tscn").instantiate()
	root.add_child(bench)
	await process_frame
	var px := 540.0 / tan(deg_to_rad(35.0))
	var bad := 0
	var parts := {}
	for n in bench.root.get_children():
		var gi := n as GeometryInstance3D
		if gi == null or gi.visibility_range_end <= 0.0: continue
		var part: String = gi.get_meta("part")
		parts[part] = true
		var feature: float = {"bolt": 0.024, "fins": 0.04}.get(part, -1.0)
		var full_until := gi.visibility_range_end - gi.visibility_range_end_margin
		var box: AABB = gi.get_meta("box")
		# a cell's box holds its instances: never empty, never wider than its cell plus a part
		if box.size.x <= 0.0 or box.size.x > 7.0 or box.size.z > 7.0: bad += 1
		var need := feature * px + box.size.length() / 2.0
		if feature < 0.0 or full_until < need - 0.001 or gi.visibility_range_fade_mode != GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF:
			bad += 1
	print("CHECK ranged_parts=", ",".join(PackedStringArray(parts.keys())), " bad=", bad)
	quit()
'''


@unittest.skipUnless(os.access(GODOT, os.X_OK), 'no Godot editor (tools/plant3d/bench/fetch_godot.sh)')
class Plant3dBench(unittest.TestCase):
    def godot(self, *args, timeout=300):
        return subprocess.run([GODOT, '--headless', '--path', BENCH, *args], capture_output=True, text=True,
                              timeout=timeout)

    def test_walk_writes_its_result(self):
        with tempfile.TemporaryDirectory() as out:
            r = self.godot('--', '--seconds=1', '--preset=lean+vis+tex1k+lod', f'--out={out}')
            with open(os.path.join(out, 'result.txt')) as f:
                text = f.read()
        self.assertRegex(text, r'RESULT preset=lean\+vis\+tex1k\+lod variant=cells frames=\d+ median=')
        self.assertIn('SPLIT preset=lean+vis+tex1k+lod', text)
        self.assertIn('PER_MINUTE', text)
        ranged = int(re.search(r'ranged=(\d+)', text).group(1))
        self.assertGreater(ranged, 0, r.stdout)
        self.assertNotIn('unknown lever', text)

    def test_vis_ranges_keep_every_part_to_its_1px_distance(self):
        with tempfile.NamedTemporaryFile('w', suffix='.gd', dir=BENCH, delete=False) as f:
            f.write(CHECK)
            script = f.name
        try:
            r = self.godot('--script', script, '--', '--preset=lean+vis', '--seconds=1')
        finally:
            os.unlink(script)
        m = re.search(r'CHECK ranged_parts=(\S*) bad=(\d+)', r.stdout)
        self.assertTrue(m, r.stdout + r.stderr)
        self.assertEqual(sorted(m.group(1).split(',')), ['bolt', 'fins'])
        self.assertEqual(m.group(2), '0')

    def test_no_ranges_without_the_lever(self):
        with tempfile.TemporaryDirectory() as out:
            self.godot('--', '--seconds=1', '--preset=lean', f'--out={out}')
            with open(os.path.join(out, 'result.txt')) as f:
                self.assertIn(' ranged=0 ', f.read())

    def test_unknown_lever_is_reported(self):
        with tempfile.TemporaryDirectory() as out:
            self.godot('--', '--seconds=1', '--preset=lean+vsi', f'--out={out}')
            with open(os.path.join(out, 'result.txt')) as f:
                self.assertIn('unknown lever vsi', f.read())


if __name__ == '__main__':
    unittest.main()
