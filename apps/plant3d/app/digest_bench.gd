## The state digest's cost (docs/PLANT3D.md §17.14, docs/plant3d/MULTIPLAYER.md §4: at most 1 ms on the Note 9) on
## the first train with its staff, measured where it runs: sim/tests/bench_digest.gd on a desktop, the app's
## `digest=bench` option on a phone (app/main.gd; the result in digest.txt in its files folder).
extends RefCounted

const PlantEngine = preload("../sim/engine.gd")


## The measurement: its result lines.
static func run(m, runs: int) -> PackedStringArray:
	var out := PackedStringArray()
	var e = PlantEngine.new(m, "shift_cold")
	var all := PackedInt64Array()
	var tree := PackedInt64Array()
	for at in [0, 3000, 12000, 30000, 60000]:
		e.step(at - e.step_no)
		var t := PackedInt64Array()
		var size := 0
		for k in runs:
			var t0 := Time.get_ticks_usec()
			e.digest()
			var t1 := Time.get_ticks_usec()
			t.append(t1 - t0)
			if k % 4 == 0:
				var t2 := Time.get_ticks_usec()
				size = var_to_bytes(e.digest_tree()).size() + e.n * 8
				tree.append(Time.get_ticks_usec() - t2)
		all.append_array(t)
		var inst := 0
		for pi in e.sp_cur.size():
			inst += e.sp_queue[pi].size() + e.sp_held[pi].size() + (1 if e.sp_cur[pi] != null else 0)
		out.append("DIGEST at=%d people=%d instances=%d bytes=%d %s" % [e.step_no, e.sp_cur.size(), inst, size,
				_stats(t)])
	out.append("DIGEST all " + _stats(all))
	out.append("TREE " + _stats(tree))
	return out


static func _stats(t: PackedInt64Array) -> String:
	var s := t.duplicate()
	s.sort()
	return "median_us=%d p95_us=%d max_us=%d" % [s[s.size() / 2], s[mini(s.size() - 1, s.size() * 95 / 100)],
			s[s.size() - 1]]
