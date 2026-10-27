## The harness's single engine (docs/plant3d/MULTIPLAYER.md §12): a fresh session run of the scenario fed the host's
## commits, as every player was, to the given step; its digests and events are what every player's must be.
##   godot --headless --path apps/plant3d --script res://net/tests/replay.gd -- --data=DIR --scenario=ID
##     --host=HOST_OUT.json --to=STEP --out=FILE
extends SceneTree

const PlantModel = preload("res://sim/plant_model.gd")
const PlantEngine = preload("res://sim/engine.gd")
const InputCheck = preload("res://net/input_check.gd")
const JsonStrict = preload("res://sim/json_strict.gd")


func _init() -> void:
	var opts := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			opts[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	var model = PlantModel.from_dir(opts["data"])
	var host = JSON.parse_string(FileAccess.get_file_as_string(opts["host"]))
	var e = PlantEngine.new(model, opts["scenario"], true)
	var at := {}
	for c in host["commits"]:
		at[int(c[0])] = c[2]
	var to := int(opts["to"])
	var digests := {}
	while e.step_no < to:
		var s: int = e.step_no + 1
		for x in at.get(s, []):
			var item = InputCheck.parse(String(x[2]).to_utf8_buffer())
			if item != null:
				e.apply_input([s] + item + [int(x[0])])
		e.step()
		if e.step_no % 50 == 0:
			digests[str(e.step_no)] = e.digest().hex_encode()
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(var_to_bytes(e.events))
	var f := FileAccess.open(opts["out"], FileAccess.WRITE)
	f.store_string(JSON.stringify({"step": e.step_no, "digests": digests, "events": e.events.size(),
			"events_sha": h.finish().hex_encode(), "digest": e.digest().hex_encode()}))
	f.close()
	quit(0)
