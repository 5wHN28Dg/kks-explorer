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
	# what the reference refuses and the loader must too (the step bench's loads are not validated): a staff reaction
	# on a clock value without `world`; a value named like a clock value, with and without `world`; such an ext value
	var base: Dictionary = V["staff"]["files"]
	var plain := base.duplicate()
	var pm: Dictionary = JsonStrict.parse(base["model/a1.json"].to_utf8_buffer(), 1000).value
	var kept: Array = []
	for v in pm["values"]:
		if not (v[0] in ["sun", "night", "day_n", "hour_lag", "day_seen"]):
			kept.append(v)
	pm["values"] = kept
	plain["model/a1.json"] = pm
	plain["scenarios/s1.json"] = sc
	var st: Dictionary = JsonStrict.parse(base["staff.json"].to_utf8_buffer(), 1000).value
	st["reactions"].append({"on": {"value": "world_hour"}, "roles": ["ccr_op"], "task": "answer_alarm"})
	var a := plain.duplicate()
	a["staff.json"] = st
	var b := plain.duplicate()
	var bm: Dictionary = pm.duplicate(true)
	bm["values"].append(["world_hour", {"const": 3}])
	b["model/a1.json"] = bm
	var c := b.duplicate()
	var cs: Dictionary = sc.duplicate(true)
	cs["world"] = {}
	c["scenarios/s1.json"] = cs
	var d := plain.duplicate()
	var pl: Dictionary = JsonStrict.parse(base["plant.json"].to_utf8_buffer(), 1000).value
	pl["ext"] = pl["ext"] + ["world_day"]
	d["plant.json"] = pl
	var ds: Dictionary = cs.duplicate(true)
	ds["init"]["world_day"] = 0
	d["scenarios/s1.json"] = ds
	if PlantModel.from_files(plain).error != "":
		print("FAIL the plain plant without world: ", PlantModel.from_files(plain).error)
		bad += 1
	for case in [["a staff reaction on world_hour without world", a], ["a value named world_hour", b],
			["a value named world_hour with world", c], ["an ext value named world_day", d]]:
		if PlantModel.from_files(case[1]).error == "":
			print("FAIL loaded: ", case[0])
			bad += 1
	# the world's fields are built from the scenario: never saved or sent in a snapshot (ui/run_save.gd saves every
	# engine variable whose name doesn't begin with "_")
	var e = load(get_script().resource_path.get_base_dir().path_join("../engine.gd")).new(PlantModel.from_files(base), "s1")
	for p in e.get_property_list():
		if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE and String(p["name"]).begins_with("world"):
			print("FAIL a saved engine variable: ", p["name"])
			bad += 1
	if [e._world, e._world_seed, e._world_year_day] != [true, 7, 200]:
		print("FAIL the world's fields: ", [e._world, e._world_seed, e._world_year_day])
		bad += 1
	for text in ["[1]", "{\"area\": \"nowhere\", \"values\": []}", "{\"area\": 3}", "not json"]:
		if not StepBench.with_load(V["staff"]["files"], text).is_empty():
			print("FAIL bench load %s: read as a load" % text)
			bad += 1
	print("WORLD bad=%d" % bad)
	if bad == 0:
		quit(0)
