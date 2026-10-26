extends SceneTree
## The state digest's cost (docs/PLANT3D.md §17.14, docs/plant3d/MULTIPLAYER.md §4: at most 1 ms on the Note 9), on the
## first train with its staff (shift_cold: the train, the WTP, every person), headless:
##   godot --headless --script apps/plant3d/sim/tests/bench_digest.gd [-- --data=PATH --runs=N]
## At five points of the shift (each after the steps to it), N digests each (default 200); prints
## "DIGEST at=STEP people=… instances=… bytes=… median_us=… p95_us=… max_us=…" per point and "DIGEST all median_us=…
## p95_us=…", and "TREE median_us=…" (the digest tree alone, built and encoded: what a frame would pay if the hashing
## went to a worker thread). The app's own measurement on a phone is the same function (app/main.gd: digest=bench).

const PlantModel = preload("../plant_model.gd")
const Bench = preload("../../app/digest_bench.gd")


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
	var lines: PackedStringArray = Bench.run(m, int(opts.get("runs", "200")))
	for l in lines:
		print(l)
	quit(0)


