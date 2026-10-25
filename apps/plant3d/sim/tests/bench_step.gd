extends SceneTree
## The model's cost (decision 0054 §10 "Model cost"): the time of one 0.1 s step of the whole first train's model,
## over the cold start run by its procedure and then at base load, headless.
##   godot --headless --script apps/plant3d/sim/tests/bench_step.gd [-- --data=PATH --base-steps=N --max-us=US]
## Prints "STEP phase=… steps=N mean_us=… p50_us=… p99_us=… max_us=… ff_max=…x": ff_max is the fast-forward speed one
## core could keep up with at that mean (10 steps per second of model time); "PROGRAM straight-line" or "interpreter"
## (how step 2 ran, engine.gd _gen_fast); "FF_CHECK mean_us=…", the cost of engine.fast_forward(), which the app's
## clock asks after every step at fast-forward. With --max-us, "GATE ok" or "GATE slow" and exit code 1 when the
## batch's mean step is above US (tests/test_plant3d_sim.py: CI).

const PlantModel = preload("../plant_model.gd")
const Procedure = preload("../procedure.gd")

var times := PackedInt64Array()


func _init() -> void:
	quit(1)         # stays the exit code if a script error stops this function
	var opts := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			opts[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	var repo := ProjectSettings.globalize_path(get_script().resource_path).get_base_dir().path_join("../../../..")
	var t0 := Time.get_ticks_usec()
	var m = PlantModel.from_dir(opts.get("data", repo.simplify_path().path_join("data/plant3d")))
	if m.error != "":
		print("ERROR ", m.error)
		return
	var t1 := Time.get_ticks_usec()
	print("LOAD values=%d alarms=%d trips=%d machines=%d us=%d" % [m.values.size(), m.alarms.size(), m.trips.size(),
			m.machines.size(), t1 - t0])
	var e = load(get_script().resource_path.get_base_dir().path_join("../engine.gd")).new(m, "cold_iron")
	print("COMPILE us=%d" % (Time.get_ticks_usec() - t1))
	print("PROGRAM %s" % ("straight-line" if e._fast != null else "interpreter"))
	# the cold start: time every step the procedure makes
	e.timing = true
	var r := Procedure.run(m, "cold_start", 3600, e, null, Callable())
	e.timing = false
	times = e.step_us
	if r.error != "":
		print("ERROR ", r.error)
		return
	_report("cold_start", times)
	# base load: the busiest state (every machine running, every loop closed)
	var n := int(opts.get("base-steps", "6000"))
	var t := PackedInt64Array()
	t.resize(n)
	for k in n:
		var s := Time.get_ticks_usec()
		e.step()
		t[k] = Time.get_ticks_usec() - s
	_report("base_load", t)
	var s2 := Time.get_ticks_usec()
	e.step(n)
	var per := float(Time.get_ticks_usec() - s2) / n
	print("BATCH steps=%d mean_us=%.1f ff_max=%dx" % [n, per, int(1e6 / per / 10.0)])
	var s3 := Time.get_ticks_usec()
	for k in 1000:
		e.fast_forward()
	print("FF_CHECK mean_us=%.1f" % ((Time.get_ticks_usec() - s3) / 1000.0))
	if opts.has("max-us"):
		var gate := float(opts["max-us"])
		print("GATE %s mean_us=%.1f max_us=%.0f" % ["ok" if per <= gate else "slow", per, gate])
		if per > gate:
			return
	_staff(m)
	quit(0)


## The staff step (step 9, PLANT3D.md §18.4: ≤ 0.3 ms per step on the Note 9 at the peak of a shift change): the
## scenario with staff from its start, its own time per step (STAFF phase=…) and the whole step's with it.
func _staff(m) -> void:
	var sid := ""
	for k in m.scenarios:
		if m.scenarios[k].has("staff"):
			sid = k
			break
	if sid == "" or m.staff == null:
		print("STAFF none")
		return
	var e = load(get_script().resource_path.get_base_dir().path_join("../engine.gd")).new(m, sid)
	var sm = e._sm
	var n := 4 * 6000           # four clock hours from the scenario's start (05:30: the shift change at 06:00)
	e.timing = true             # every step's time (step_us) and step 9's own (staff_us)
	e.step(n)
	e.timing = false
	var st: PackedInt64Array = e.staff_us
	var whole: PackedInt64Array = e.step_us
	var peak := PackedInt64Array()
	for k in range(1200, 3600):         # 05:42–06:06 at day_scale 6: the handovers and the duties' change
		peak.append(st[k])
	# the day workers' arrival (milestone S2: about thirty people at the gate, the lockers and the toolbox talk) and the
	# morning's permits, 06:55–07:45
	var day := PackedInt64Array()
	for k in range(8500, 13500):
		day.append(st[k])
	_report("staff_step9", st)
	_report("staff_step9_shift_change", peak)
	_report("staff_step9_day_start", day)
	_report("model_and_staff", whole)
	var ev := 0
	for x in e.events:
		if x[1] in ["task", "move", "say", "call", "duty", "read"]:
			ev += 1
	print("STAFF people=%d events=%d" % [sm.people.size(), ev])


func _report(phase: String, t: PackedInt64Array) -> void:
	if t.is_empty():
		print("STEP phase=%s steps=0" % phase)
		return
	var s := Array(t)
	s.sort()
	var total := 0
	for x in t:
		total += x
	var mean := float(total) / t.size()
	print("STEP phase=%s steps=%d mean_us=%.1f p50_us=%d p99_us=%d max_us=%d ff_max=%dx" % [phase, t.size(), mean,
			s[s.size() / 2], s[int(s.size() * 0.99)], s[-1], int(1e6 / mean / 10.0)])

