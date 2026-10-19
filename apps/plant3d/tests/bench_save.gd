## The cost of saving a run (ui/run_save.gd, ui/autosave.gd), at the end of the first train's cold start run by its
## procedure (the biggest event log a normal run makes) and after hours more at base load:
##   godot --headless --path apps/plant3d --script res://tests/bench_save.gd [-- --base-steps=N]
## Prints "SAVE phase=… events=… bytes=… capture_us=… encode_us=… write_us=… total_us=…": capture is the part done
## on the main thread (ui/autosave.gd encodes and writes on a worker thread), each the median of 9.
extends SceneTree

const PlantModel = preload("res://sim/plant_model.gd")
const Procedure = preload("res://sim/procedure.gd")
const RunSave = preload("res://ui/run_save.gd")


func _init() -> void:
	quit(1)
	var opts := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			opts[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	var m = PlantModel.from_dir("res://built/content")
	if m.error != "":
		print("ERROR ", m.error)
		return
	var r := Procedure.run(m, "cold_start")
	if r.error != "":
		print("ERROR ", r.error)
		return
	var e = r.engine
	_measure("cold_start", e)
	e.step(int(opts.get("base-steps", "36000")))
	_measure("base_load", e)
	quit(0)


func _measure(phase: String, e) -> void:
	var names := RunSave.engine_fields(e)
	var path := OS.get_user_data_dir().path_join("bench-save.save")
	var cap := PackedInt64Array()
	var enc := PackedInt64Array()
	var wr := PackedInt64Array()
	var size := 0
	for i in 9:
		var t0 := Time.get_ticks_usec()
		var state := RunSave.capture(e, names)
		var t1 := Time.get_ticks_usec()
		var b := RunSave.encode({"engine": state})
		var t2 := Time.get_ticks_usec()
		RunSave.write(path, b)
		var t3 := Time.get_ticks_usec()
		cap.append(t1 - t0)
		enc.append(t2 - t1)
		wr.append(t3 - t2)
		size = b.size()
	RunSave.remove(path)
	cap.sort()
	enc.sort()
	wr.sort()
	print("SAVE phase=%s step=%d events=%d bytes=%d capture_us=%d encode_us=%d write_us=%d total_us=%d" % [phase,
			e.step_no, e.events.size(), size, cap[4], enc[4], wr[4], cap[4] + enc[4] + wr[4]])
