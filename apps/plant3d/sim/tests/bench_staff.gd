extends SceneTree
## The staff step over the `gate` walk's hour (PLANT3D.md §21.10, §21.14): the scenario `shift_cold` in free mode run
## to 05:40 (4,000 steps), then 6,000 steps (05:40–06:40, the buses and the shift change at the gate) timed, with the
## time of each phase of sim/staff.gd's step() (`prof`).
##   godot --headless --script apps/plant3d/sim/tests/bench_staff.gd [-- --data=PATH --steps=N --scenario=ID]
## Prints "STAFF mean_us=… p50_us=… p99_us=…", "PHASE name=… mean_us=…" per phase and "COUNT runs=… due=… acts=…"
## (the work done, the same on every machine: staff.gd prof_n; tests/test_plant3d_sim.py bounds it).

const PlantModel = preload("../plant_model.gd")


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
	var e = load(get_script().resource_path.get_base_dir().path_join("../engine.gd")).new(m,
			opts.get("scenario", "shift_cold"))
	if e._sm == null:
		print("ERROR no staff")
		return
	e.step(int(opts.get("lead", "4000")))
	var sm = e._sm
	var n := int(opts.get("steps", "6000"))
	var prof: bool = "_staff_prof_on" in e      # (the per-phase timers: not in a build before them)
	if prof:
		e._staff_prof_on = true
	e.timing = true
	e.step(n)
	e.timing = false
	if prof:
		e._staff_prof_on = false
	var st: PackedInt64Array = e.staff_us
	var s := Array(st)
	s.sort()
	var total := 0
	for x in st:
		total += x
	print("STAFF steps=%d mean_us=%.1f p50_us=%d p99_us=%d max_us=%d" % [st.size(), float(total) / st.size(),
			s[s.size() / 2], s[int(s.size() * 0.99)], s[-1]])
	for k in (sm.PROF_NAMES.size() if prof else 0):
		print("PHASE name=%s mean_us=%.1f" % [sm.PROF_NAMES[k], float(e._staff_prof[k]) / n])
	if prof:
		print("COUNT runs=%d due=%d acts=%d" % [e._staff_prof_n["runs"], e._staff_prof_n["due"], e._staff_prof_n["acts"]])
	quit(0)
