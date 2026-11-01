extends SceneTree
## The loader's guard for the clock values (docs/plant3d/REALISM.md §2.10), headless:
##   godot --headless --script apps/plant3d/sim/tests/check_world.gd -- VECTORS3
## The realism file's synthetic plant (whose model reads world_hour) loads with its scenario's `world`, and is refused
## without it (the engine would otherwise read a slot that isn't there); a step bench load that can't be read is
## answered as none (StepBench.run then prints its ERROR line), not a crash. Prints "WORLD bad=N"; exit code 0 when N is 0.

const PlantModel = preload("../plant_model.gd")
const JsonStrict = preload("../json_strict.gd")
const StepBench = preload("../../app/step_bench.gd")


func _init() -> void:
	quit(1)
	var path: String = OS.get_cmdline_user_args()[0]
	var V: Dictionary = JsonStrict.parse(FileAccess.get_file_as_bytes(path), 1000).value
	var files: Dictionary = V["staff"]["files"].duplicate()
	var bad := 0
	var m = PlantModel.from_files(files)
	if m.error != "":
		print("FAIL with world: ", m.error)
		bad += 1
	var sc: Dictionary = JsonStrict.parse(files["scenarios/s1.json"].to_utf8_buffer(), 1000).value
	sc.erase("world")
	files["scenarios/s1.json"] = sc
	m = PlantModel.from_files(files)
	if not m.error.contains("world_hour"):
		print("FAIL without world: loaded (error %s)" % m.error)
		bad += 1
	for text in ["[1]", "{\"area\": \"nowhere\", \"values\": []}", "{\"area\": 3}", "not json"]:
		if not StepBench.with_load(V["staff"]["files"], text).is_empty():
			print("FAIL bench load %s: read as a load" % text)
			bad += 1
	print("WORLD bad=%d" % bad)
	if bad == 0:
		quit(0)
