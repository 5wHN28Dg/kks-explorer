extends SceneTree
## The live mirror's resolution in the app (workshop/mirror.gd, WORKSHOP.md §6.5) at every code a JSON file names, for
## tests/test_plant3d_sim.py MirrorSources to hold against the reference's (ref/plant3d_bench.py mirror_sources):
##   godot --headless --script apps/plant3d/sim/tests/mirror_sources.gd -- --codes=IN.json --out=OUT.json
## IN: {part: [code, …]}; OUT: {part: {code: {values, machines, missing}}}. Prints "MIRROR ok" or "FAIL …".
const PlantModel = preload("../plant_model.gd")
const BenchModel = preload("../bench_model.gd")
const Mirror = preload("../../workshop/mirror.gd")


func _init() -> void:
	quit(1)
	var opts := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			opts[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	var repo := ProjectSettings.globalize_path(get_script().resource_path).get_base_dir().path_join("../../../..")
	var data := repo.simplify_path().path_join("data/plant3d")
	var pm = PlantModel.from_dir(data)
	if pm.error != "":
		print("FAIL ", pm.error)
		return
	var codes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(opts.get("codes", "")))
	var out := {}
	for part in codes:
		var w: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(data.path_join("workshop/%s.json" % part)))
		var bm = BenchModel.from_text(FileAccess.get_file_as_string(data.path_join("workshop/bench/%s.json" % part)),
				w["components"].keys())
		if bm.error != "":
			print("FAIL ", bm.error)
			return
		out[part] = {}
		for code in codes[part]:
			out[part][code] = Mirror.resolve(bm, pm, String(code))
	var f := FileAccess.open(opts.get("out", ""), FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "", true, true))
	f.close()
	print("MIRROR ok")
	quit(0)
