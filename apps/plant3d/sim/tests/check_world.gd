extends SceneTree
## The loader's guard for the clock values (docs/plant3d/REALISM.md §2.10), headless:
##   godot --headless --script apps/plant3d/sim/tests/check_world.gd -- VECTORS3
## The realism file's synthetic plant (whose model reads world_hour) loads with its scenario's `world`, and is refused
## without it (the engine would otherwise read a slot that isn't there); a step bench load that can't be read is
## answered as none (StepBench.run then prints its ERROR line), not a crash. The same for the weather's kind (world_wx:
## a scenario with world.weather) and what the weather and the wear need of the content (REALISM.md §2.2, §5.1: the
## weather plant and the wear plant of the file load, and are refused when broken). Prints "WORLD bad=N"; exit code 0
## when N is 0.

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
	bad += _weather_and_wear(V)
	for text in ["[1]", "{\"area\": \"nowhere\", \"values\": []}", "{\"area\": 3}", "not json",
			"{\"area\": \"a1\", \"values\": [], \"weather\": [1]}",
			"{\"area\": \"a1\", \"values\": [], \"weather\": {}, \"ext\": [1]}"]:
		if not StepBench.with_load(V["staff"]["files"], text).is_empty():
			print("FAIL bench load %s: read as a load" % text)
			bad += 1
	print("WORLD bad=%d" % bad)
	if bad == 0:
		quit(0)


static func _js(t) -> Dictionary:
	return JsonStrict.parse(t.to_utf8_buffer(), 1000).value if typeof(t) == TYPE_STRING else t.duplicate(true)


## The weather's and the wear's guards (REALISM.md §2.2, §5.1): the loader refuses what the engine can't run.
static func _weather_and_wear(V: Dictionary) -> int:
	var bad := 0
	var wf: Dictionary = V["weather"]["files"]
	if PlantModel.from_files(wf).error != "":
		print("FAIL the weather plant: ", PlantModel.from_files(wf).error)
		bad += 1
	var cases := []
	var sc := _js(wf["scenarios/s1.json"])
	sc["world"].erase("weather")
	var f1 := wf.duplicate()
	f1["scenarios/s1.json"] = sc
	cases.append(["the model reading world_wx without world.weather", f1, "world_wx"])
	var f2 := wf.duplicate()
	var m2 := _js(wf["model/a1.json"])
	m2["values"].append(["world_wx", {"const": 1}])
	f2["model/a1.json"] = m2
	cases.append(["a value named world_wx", f2, "world_wx"])
	var f3 := wf.duplicate()
	f3.erase("weather.json")
	cases.append(["world.weather without weather.json", f3, "weather.json"])
	var f4 := wf.duplicate()
	var s4 := _js(wf["scenarios/s1.json"])
	s4["world"]["weather"] = {"fixed": "snow"}
	f4["scenarios/s1.json"] = s4
	cases.append(["fixed weather of no kind", f4, "snow"])
	var f5 := wf.duplicate()
	var w5 := _js(wf["weather.json"])
	w5["values"][1]["id"] = "dust"
	f5["weather.json"] = w5
	cases.append(["a driven value that is not an ext value", f5, "dust"])
	var f6 := wf.duplicate()
	var p6 := _js(wf["plant.json"])
	p6["ext"].append("world_wx")
	f6["plant.json"] = p6
	cases.append(["an ext value named world_wx", f6, "world_wx"])
	var w8 := _js(wf["weather.json"])
	w8["kinds"][1]["targets"].erase("dust_mg")
	var f8 := wf.duplicate()
	f8["weather.json"] = w8
	cases.append(["a kind without a driven value's table", f8, "no table"])
	var w9 := _js(wf["weather.json"])
	w9["seasons"][0]["hourly"].append(["fog", "clear", 1])
	var f9 := wf.duplicate()
	f9["weather.json"] = w9
	cases.append(["an hourly row of no kind", f9, "kinds weather.json lacks"])
	var w10 := _js(wf["weather.json"])
	w10["seasons"][0]["days"] = [122, 300]
	var f10 := wf.duplicate()
	f10["weather.json"] = w10
	cases.append(["a day in no season", f10, "in no season"])
	var w11 := _js(wf["weather.json"])
	w11["seasons"][0]["hourly"][9][2] = 0
	var f11 := wf.duplicate()
	f11["weather.json"] = w11
	cases.append(["a kind with no way on", f11, "no way on"])
	var s12 := _js(wf["scenarios/s1.json"])
	s12["world"]["weather"] = {"script": [[1, "06:00", "hot"]]}
	var f12 := wf.duplicate()
	f12["scenarios/s1.json"] = s12
	cases.append(["a script starting after the scenario", f12, "after the scenario's start"])
	var s13 := _js(wf["scenarios/s1.json"])
	s13["world"]["weather"] = {"script": [[1, "05:00"]]}
	var f13 := wf.duplicate()
	f13["scenarios/s1.json"] = s13
	cases.append(["a script entry of two items", f13, "can't read"])
	var af: Dictionary = V["wear"]["files"]
	if PlantModel.from_files(af).error != "":
		print("FAIL the wear plant: ", PlantModel.from_files(af).error)
		bad += 1
	var f7 := af.duplicate()
	var m7 := _js(af["model/a1.json"])
	for w in m7["works"]:
		if w["id"] == "wo_pump":
			w["renews"] = ["brg_life"]
	f7["model/a1.json"] = m7
	cases.append(["a work renewing a draw", f7, "brg_life"])
	for c in cases:
		var err: String = PlantModel.from_files(c[1]).error
		if not err.contains(c[2]):
			print("FAIL %s: %s" % [c[0], "loaded" if err == "" else err])
			bad += 1
	return bad
