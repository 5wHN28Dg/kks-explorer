extends SceneTree
## The state digest's cost (docs/PLANT3D.md §17.14, docs/plant3d/MULTIPLAYER.md §4: at most 1 ms on the Note 9), on the
## first train with its staff (shift_cold: the train, the WTP, every person), headless:
##   godot --headless --script apps/plant3d/sim/tests/bench_digest.gd [-- --data=PATH --runs=N]
## At five points of the shift (each after the steps to it), N digests each (default 200); prints
## "DIGEST at=STEP people=… instances=… bytes=… median_us=… p95_us=… max_us=…" per point and "DIGEST all median_us=…
## p95_us=…", and "TREE median_us=…" (the digest tree alone, built and encoded: what a frame would pay if the hashing
## went to a worker thread). The app's own measurement on a phone is the same function (app/main.gd: digest=1).

const PlantModel = preload("../plant_model.gd")
const PlantEngine = preload("../engine.gd")


func _init() -> void:
	quit(1)
	var opts := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			opts[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	var repo := ProjectSettings.globalize_path(get_script().resource_path).get_base_dir().path_join("../../../..")
	var m = PlantModel.from_dir(opts.get("data", repo.simplify_path().path_join("data/plant3d")))
	if m.error != "":
		print("ERROR ", m.error)
		return
	var lines := run(m, int(opts.get("runs", "200")))
	for l in lines:
		print(l)
	quit(0)


## The measurement (also run by the app on a phone): its result lines.
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
