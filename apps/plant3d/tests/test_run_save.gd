## Saved runs (ui/run_save.gd, ui/autosave.gd; the user, 2026-10-19):
## - a run saved after N steps and put back into a fresh engine goes on bit for bit as the run that never stopped
##   (every state field, every value at every step, every event), with inputs queued and an alarm shelved across the
##   save; also an engine with state of a kind it doesn't have yet (tests/fixtures/engine_plus.gd), whose save a plain
##   engine refuses; the fields the save leaves out (the compiled program) never change in a run;
## - the file: another format, a cut, a flipped byte, bytes after the end, a payload that is not a saved run, a file
##   over the size limit, random bytes: each refused with a reason, never applied;
## - the atomic write: a crash while writing (half a .tmp) leaves the previous save; a missing save with a complete
##   .tmp (a rename that could not replace, Windows) loads the .tmp; a failed write leaves the old file;
## - the app: Continue at start puts the plant, the procedure's progress, the operations' results, the alarms' times
##   and the trainee back, and the run goes on as the saved one did; New run replaces the save; a run with a deviation
##   is continued;
## - another build's save (#447): one of other code or content, and the release before's (tests/fixtures/run-0.3.0.save),
##   are made again in this build from their inputs, the file as saved kept aside; a save this build can't continue (a
##   newer version's or format's, damaged, a state that doesn't fit, a scenario this plant hasn't) is refused with its
##   reason and kept aside under the name the offer gives, and a new run starts (the switch on; off, as plant-v0.3.0).
extends RefCounted

const PlantModel = preload("res://sim/plant_model.gd")
const PlantEngine = preload("res://sim/engine.gd")
const Procedure = preload("res://sim/procedure.gd")
const WoSim = preload("res://sim/workorders.gd")
const WoPanel = preload("res://ui/wo_panel.gd")
const RunSave = preload("res://ui/run_save.gd")
const Autosave = preload("res://ui/autosave.gd")
const App = preload("res://tests/ui_app.gd")
const SimClock = preload("res://ui/sim_clock.gd")

const DIR := "user://test-run-save"


func run(tree: SceneTree) -> Array:
	var p: Array = []
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var m = PlantModel.from_dir("res://built/content")
	if m.error != "":
		return ["the model did not load: " + m.error]
	var ran = _round_trip(m, PlantEngine, p)
	_round_trip(m, load("res://tests/fixtures/engine_plus.gd"), p)
	_round_trip_wtp(m, p)
	_round_trip_weather(p)
	_round_trip_lab(p)
	_round_trip_wo(p)
	_round_trip_stores(p)
	if ran != null:
		_compiled_fixed(m, ran, p)
	_file(m, p)
	_atomic(m, p)
	await _app(tree, p)
	Autosave.switch_override = -1
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR.path_join(f)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))
	return p


## The state of an engine as bytes (every field the save keeps, and the values): equal bytes, equal bits.
static func _bytes(e) -> PackedByteArray:
	return var_to_bytes([RunSave.capture(e, RunSave.engine_fields(e)), e.value_array()])


static func _inputs_after(e, k: int) -> void:
	# the same inputs on both sides of the comparison: an operation refused or done, an ack, an un-shelve
	if k == 3:
		e.op("00PGC10AP001", "start")
	elif k == 40:
		e.ack(e._al[1][0])
	elif k == 90:
		e.unshelve(e._al[2][0])


## Returns the uninterrupted engine (or null).
func _round_trip(m, script, p: Array):
	var pr: Dictionary = m.procedures["cold_start"]
	var e = script.new(m, pr["scenario"])
	var mid: String = pr["steps"][pr["steps"].size() / 2]["id"]
	var r := Procedure.run(m, "cold_start", 3600, e, mid)
	if r.error != "":
		p.append("the cold start stopped: " + r.error)
		return null
	# across the save: an alarm shelved (its shelf ends after it), another for longer, inputs queued not yet stepped
	e.shelve(e._al[0][0], 12.3)
	e.shelve(e._al[2][0], 600)
	e.step(5)
	# a fault repaired and pressed again before the save, another repaired by an input still waiting (§7.8)
	e.fault("cw_b_motor")
	e.step(1)
	e.repair("cw_b_motor")
	e.step(1)
	e.fault("cw_b_motor")
	e.fault("cw_a_motor")
	e.step(1)
	e.repair("cw_a_motor")
	e.op("00QFA10AN001", "start")
	e.ack(e._al[0][0])
	var name: String = script.resource_path.get_file()
	var fields := RunSave.engine_fields(e)
	for f in fields:
		if typeof(e.get(f)) == TYPE_OBJECT:
			p.append("%s: the engine's state %s holds an object, which a save can't keep (keep its state in values)" % [name, f])
	for f in ["cur", "prev", "mem", "mstate", "latched", "astate", "shelved", "events", "inputs", "queue", "step_no",
			"faults_done", "faults_fixed"]:
		if not f in fields:
			p.append("%s: the save leaves out the engine's %s" % [name, f])
	if script != PlantEngine:
		for f in ["extra_count", "extra_trace", "extra_seen"]:
			if not f in fields:
				p.append("%s: state added to the engine (%s) is not saved" % [name, f])
	# a copy taken for the worker thread stays as it was while the engine goes on (packed arrays are shared)
	var probe = e.clone()
	var cap := RunSave.capture(probe, fields)
	var cap_bytes := var_to_bytes(cap)
	probe.step(5)
	if var_to_bytes(cap) != cap_bytes:
		p.append("%s: a captured state changes as the engine steps on (the worker thread would save a mix)" % name)
	var path := DIR.path_join("rt.save")
	var err := RunSave.write(path, RunSave.encode(_payload(e)))
	if err != OK:
		p.append("%s: the save was not written (%d)" % [name, err])
		return null
	var got := RunSave.read(path)
	if not got["ok"]:
		p.append("%s: the save did not read back: %s" % [name, got.get("text", "")])
		return null
	var f2 = script.new(m, pr["scenario"])
	var bad := RunSave.check(f2, RunSave.engine_fields(f2), got["payload"]["engine"])
	if bad != "":
		p.append("%s: a fresh engine refuses its own save: %s" % [name, bad])
		return null
	RunSave.apply(f2, got["payload"]["engine"])
	var n_events: int = f2.events.size()
	if _bytes(f2) != _bytes(e):
		p.append("%s: the restored engine is not the saved one" % name)
		return null
	# M more steps on both: the same at every step
	for k in 400:
		_inputs_after(e, k)
		_inputs_after(f2, k)
		e.step()
		f2.step()
		if f2.cur != e.cur:
			p.append("%s: the restored run differs from the uninterrupted one at step %d" % [name, e.step_no])
			return null
	if _bytes(f2) != _bytes(e):
		p.append("%s: after 400 steps the restored run's state differs" % name)
	if f2.events.size() <= n_events + 3:
		p.append("%s: nothing happened after the save (the comparison proves little)" % name)
	if script != PlantEngine:
		# a plain engine (an older app) refuses a save with state it doesn't know
		var plain = PlantEngine.new(m, pr["scenario"])
		if RunSave.check(plain, RunSave.engine_fields(plain), got["payload"]["engine"]) == "":
			p.append("a plain engine took a save with fields it doesn't have")
	return e


## The realism vectors' weather plant (REALISM.md §2.12) and wear plant (§2.11) saved mid-run, across an hour's draw and
## the instructor's input still queued: put back into a fresh engine, the run goes on bit for bit (the weather's kind
## and stream, the counts' memory); a save whose weather kind is outside weather.json's, or whose stream is 0, is refused.
func _round_trip_weather(p: Array) -> void:
	const JsonStrict = preload("res://sim/json_strict.gd")
	var path := ProjectSettings.globalize_path("res://").path_join("../../ref/vectors/plant3d-realism.json").simplify_path()
	var V: Dictionary = JsonStrict.parse(FileAccess.get_file_as_bytes(path), 1000).value
	for part in ["weather", "wear", "hands"]:
		var m = PlantModel.from_files(V[part]["files"])
		if m.error != "":
			p.append("the realism %s plant did not load: %s" % [part, m.error])
			continue
		var e = PlantEngine.new(m, "s1")
		e.step(525 if part == "hands" else 295)     # (hands: the NPC opening the gauge's cover, REALISM.md §2.13)
		if part == "weather":
			e.weather("dust")
		elif part == "hands":
			e.fault("f_low")
		else:
			e.op("10LAB10AA001", "open")
			e.op("10LAC10AP001", "start")
		var f2 = PlantEngine.new(m, "s1")
		var cap := RunSave.capture(e, RunSave.engine_fields(e))
		var cap0 := cap.duplicate(true)     # (apply hands cap's own arrays to f2, which steps on in them)
		var bad := RunSave.check(f2, RunSave.engine_fields(f2), cap)
		if bad == "":
			bad = Autosave._engine_contents(f2, cap)
		if bad != "":
			p.append("realism %s: a fresh engine refuses its own save: %s" % [part, bad])
			continue
		RunSave.apply(f2, cap)
		for k in 700:
			e.step()
			f2.step()
			if f2.cur != e.cur or f2.digest() != e.digest():
				p.append("realism %s: the restored run differs at step %d" % [part, e.step_no])
				break
		if part == "weather":
			if not e.events.any(func(x): return x[1] == "instructor"):
				p.append("realism weather: the queued instructor's input was not carried")
			for c in [{"wx_kind": 4}, {"wx_kind": -1}, {"wx_s": 0}]:
				var t := cap.duplicate()
				t.merge(c, true)
				if Autosave._engine_contents(f2, t) == "":
					p.append("realism weather: a save with %s was taken" % str(c))
		if part == "hands":
			if not cap0["busy"].has("ic2") or cap0["carried"].is_empty():
				p.append("realism hands: the save has no hand action under way or no tools carried")
			var damaged := [{"busy": {"ic2": ["10LAB10CP501", "open_lid", "sd_flat", null, 1, 0]}},
					{"busy": {"nobody": cap0["busy"].get("ic2")}}, {"carried": {"ic2": ["hammer"]}},
					{"carried": {"ic2": ["dmm", "dmm"]}}, {"tool_n": [[-1]]}, {"cause_s": {"f_low": 0}},
					{"cause_of": {"f_low": "gremlins"}}, {"slip_s": {}}, {"npc_queue": [["slip", "ic2", "ic_job"]]},
					{"npc_queue": [["hand", "x", "y", null, null, "nobody"]]}]
			var more: Dictionary = cap0.duplicate(true)       # a tool made: a count raised
			more["tool_n"][0][0] += 1
			damaged.append({"tool_n": more["tool_n"]})
			for c in damaged:
				var t := cap0.duplicate(true)
				t.merge(c, true)
				if Autosave._engine_contents(f2, t) == "":
					p.append("realism hands: a save with %s was taken" % str(c))


## The realism vectors' lab plant (REALISM.md §2.19) saved with samples queued (its first run's inputs to step 12):
## put back into a fresh engine, the run goes on bit for bit through their results (the queues and the lab streams); a
## save whose queue is damaged, names no node of the content or holds more than 8 samples, or whose stream is 0, is
## refused.
func _round_trip_lab(p: Array) -> void:
	const JsonStrict = preload("res://sim/json_strict.gd")
	var path := ProjectSettings.globalize_path("res://").path_join("../../ref/vectors/plant3d-realism.json").simplify_path()
	var L: Dictionary = JsonStrict.parse(FileAccess.get_file_as_bytes(path), 1000).value["lab"]
	var files: Dictionary = L["files"].duplicate()
	files["scenarios/s1.json"] = L["runs"][0]["scenario"]
	var m = PlantModel.from_files(files)
	if m.error != "":
		p.append("the realism lab plant did not load: %s" % m.error)
		return
	var e = PlantEngine.new(m, "s1")
	var inputs: Array = L["runs"][0]["inputs"]
	var i := 0
	while e.step_no < 12:
		while i < inputs.size() and inputs[i][0] == e.step_no + 1:
			e.apply_input(inputs[i])
			i += 1
		e.step()
	var cap := RunSave.capture(e, RunSave.engine_fields(e))
	var cap0 := cap.duplicate(true)
	if cap0["lab_q"].get("lab_fe", []).is_empty():
		p.append("realism lab: the save has no sample queued")
	var f2 = PlantEngine.new(m, "s1")
	var bad := RunSave.check(f2, RunSave.engine_fields(f2), cap)
	if bad == "":
		bad = Autosave._engine_contents(f2, cap)
	if bad != "":
		p.append("realism lab: a fresh engine refuses its own save: %s" % bad)
		return
	RunSave.apply(f2, cap)
	for k in 700:
		e.step()
		f2.step()
		if f2.cur != e.cur or f2.digest() != e.digest():
			p.append("realism lab: the restored run differs at step %d" % e.step_no)
			break
	if not e.events.any(func(x): return x[1] == "lab"):
		p.append("realism lab: no result came after the save")
	var nine := []
	for k in 9:
		nine.append([1, 1.0])
	for c in [{"lab_q": {"lab_fe": [[1, "x"]], "lab_vis": []}}, {"lab_q": {"lab_fe": []}},
			{"lab_q": {"lab_fe": [], "nothing": []}}, {"lab_q": {"lab_fe": nine, "lab_vis": []}},
			{"lab_q": {"lab_fe": [[1.5, 1.0]], "lab_vis": []}}, {"lab_s": {"lab_fe": 0, "lab_vis": 1}},
			{"lab_s": {"lab_fe": 1}}]:
		var t := cap0.duplicate(true)
		t.merge(c, true)
		if Autosave._engine_contents(f2, t) == "":
			p.append("realism lab: a save with %s was taken" % str(c))


## The realism vectors' work order plant (REALISM.md §2.20) saved in the middle of a work order's cycle (its NPC run
## to step 1200: the pump's order in progress under the accepted permit, the gauge's scheduled): put back into a fresh
## engine, the run goes on bit for bit through the NPC's write-up and the order's closing (into the history); a save
## whose state, record, history, number or write-up is damaged or names no work of the content is refused.
func _round_trip_wo(p: Array) -> void:
	const JsonStrict = preload("res://sim/json_strict.gd")
	var path := ProjectSettings.globalize_path("res://").path_join("../../ref/vectors/plant3d-realism.json").simplify_path()
	var W: Dictionary = JsonStrict.parse(FileAccess.get_file_as_bytes(path), 1000).value["wo"]
	var run: Dictionary = W["runs"][2]
	var files: Dictionary = W["files"].duplicate()
	files["scenarios/s1.json"] = run["scenario"]
	var m = PlantModel.from_files(files)
	if m.error != "":
		p.append("the realism work order plant did not load: %s" % m.error)
		return
	var e = PlantEngine.new(m, "s1")
	var inputs: Array = run["inputs"]
	var i := 0
	while e.step_no < 1200:
		while i < inputs.size() and inputs[i][0] == e.step_no + 1:
			e.apply_input(inputs[i])
			i += 1
		e.step()
	var cap := RunSave.capture(e, RunSave.engine_fields(e))
	var cap0 := cap.duplicate(true)
	if cap0["wo"].get("wo_pump") != 4 or not cap0["wo_history"].is_empty():
		p.append("realism wo: the save is not in the middle of the pump's order (%s)" % str(cap0["wo"]))
	var f2 = PlantEngine.new(m, "s1")
	var bad := RunSave.check(f2, RunSave.engine_fields(f2), cap)
	if bad == "":
		bad = Autosave._engine_contents(f2, cap)
	if bad != "":
		p.append("realism wo: a fresh engine refuses its own save: %s" % bad)
		return
	RunSave.apply(f2, cap)
	for k in 500:
		while i < inputs.size() and inputs[i][0] == e.step_no + 1:
			e.apply_input(inputs[i])
			f2.apply_input(inputs[i])
			i += 1
		e.step()
		f2.step()
		if f2.cur != e.cur or f2.digest() != e.digest():
			p.append("realism wo: the restored run differs at step %d" % e.step_no)
			break
	if e.wo_history.size() != 1 or f2.wo_history != e.wo_history:
		p.append("realism wo: the pump's order was not closed after the save (%s)" % str(e.wo_history))
	# the debrief counts the orders raised by the counter: the history keeps only its newest records (§2.21)
	var raised: int = e.wo_count
	e.wo_count = raised + 4096
	var dl := "\n".join(WoPanel.debrief_lines(e, null))
	if not dl.contains("Work orders: %d raised" % (raised + 4096)):
		p.append("realism wo: the debrief does not count orders whose records dropped: %s" % dl)
	e.wo_count = raised
	var rec: Array = cap0["wo_rec"]["wo_pump"]
	var short := rec.slice(0, 9)
	var other := rec.duplicate(true)
	other[9] = "wo_gauge"
	var renumbered := rec.duplicate(true)
	renumbered[0] = "WO-0007"
	var badclock := rec.duplicate(true)
	badclock[1] = [1, 2, 3]
	var full := []          # the run's history at its limit (REALISM.md §2.21) is taken; one more is refused
	for _j in WoSim.RUN_HISTORY:
		full.append(rec.duplicate(true))
	var t_full := cap0.duplicate(true)
	t_full["wo_history"] = full
	if Autosave._engine_contents(f2, t_full) != "":
		p.append("realism wo: a save with a full history was refused: %s" % Autosave._engine_contents(f2, t_full))
	var over := full.duplicate(true)
	over.append(rec.duplicate(true))
	for c in [{"wo": {"wo_pump": 9, "wo_gauge": 3, "wo_valve": 0}}, {"wo": {"wo_pump": 4}},
			{"wo": {"wo_pump": 4, "wo_gauge": 3, "wo_valve": 1}}, {"wo": {"wo_pump": 3, "wo_gauge": 3, "wo_valve": 0}},
			{"wo_rec": {"wo_pump": short}}, {"wo_rec": {"wo_pump": other}}, {"wo_rec": {"wo_fan": rec}},
			{"wo_rec": {"wo_pump": badclock}}, {"wo_no": {"wo_pump": 3}}, {"wo_no": {"wo_fan": "WO-0009"}},
			{"wo_history": [short]}, {"wo_history": over}, {"wo_count": -1}, {"wo_npc_done": [["wo_fan", "mech1"]]},
			{"wo_npc_done": [["wo_pump"]]}, {"wo_count": 0}, {"wo_rec": {"wo_pump": renumbered}},
			{"npc_queue": [["wo"]]}, {"npc_queue": [["wo", "wo_fan", "plan", "a_sup", null]]},
			{"npc_queue": [["wo", "wo_pump", "approve", "a_sup", []]]},
			{"npc_queue": [["wo", "wo_pump", "plan", "nobody", [3]]]},
			{"npc_queue": [["wo", "wo_pump", "plan", "a_sup", 3]]}]:
		var t := cap0.duplicate(true)
		for k in c:             # (a record or number changed among the others; the states replaced whole)
			if k == "wo_rec" or k == "wo_no":
				t[k].merge(c[k], true)
			else:
				t[k] = c[k]
		if Autosave._engine_contents(f2, t) == "":
			p.append("realism wo: a save with %s was taken" % str(c))
	# an NPC's completion without data on a work without codes (its defaults would read the codes)
	var pump: Dictionary = f2.m.works[f2.m.work_ix["wo_pump"]]
	var codes = pump["codes"]
	pump.erase("codes")
	var t2 := cap0.duplicate(true)
	t2["npc_queue"] = [["wo", "wo_pump", "complete", "mech1", null]]
	if Autosave._engine_contents(f2, t2) == "":
		p.append("realism wo: a save with an NPC's completion of a work without codes was taken")
	pump["codes"] = codes


## The realism vectors' stores (REALISM.md §2.23) saved twice: in the middle of a fitting (run 7 at step 40: the range 3
## transmitter taken, the range 4 still issued against the gauge's order, the fitting's busy record naming the work its
## part came from) and with a purchase order pending (run 8 at step 100: the storekeeper's reorder, the packing issued
## against the valve's order). Put back into a fresh engine, each run goes on bit for bit to its end (the fitting done,
## the look-alike refused; the order delivered in the jump's step); a save whose stock, orders, counter, issued parts,
## fitting, NPC issue or order, kept issue or order, or jump input is damaged or names no part or work of the content
## is refused.
func _round_trip_stores(p: Array) -> void:
	const JsonStrict = preload("res://sim/json_strict.gd")
	var path := ProjectSettings.globalize_path("res://").path_join("../../ref/vectors/plant3d-realism.json").simplify_path()
	var S: Dictionary = JsonStrict.parse(FileAccess.get_file_as_bytes(path), 1000).value["stores"]
	var caps := {}
	var f2s := {}
	for at in [[7, 40], [8, 100]]:
		var run: Dictionary = S["runs"][at[0]]
		var files: Dictionary = S["files"].duplicate()
		files["scenarios/s1.json"] = run["scenario"]
		if run["staff"] != null:
			files["staff.json"] = run["staff"]
		for rel in run.get("files", {}):
			if run["files"][rel] == null:
				files.erase(rel)
			else:
				files[rel] = run["files"][rel]
		var m = PlantModel.from_files(files)
		if m.error != "":
			p.append("the realism stores plant did not load: %s" % m.error)
			return
		var e = PlantEngine.new(m, "s1")
		var inputs: Array = run["inputs"]
		var i := 0
		while e.step_no < at[1]:
			while i < inputs.size() and inputs[i][0] == e.step_no + 1:
				e.apply_input(inputs[i])
				i += 1
			e.step()
		var cap := RunSave.capture(e, RunSave.engine_fields(e))
		var f2 = PlantEngine.new(m, "s1")
		var bad := RunSave.check(f2, RunSave.engine_fields(f2), cap)
		if bad == "":
			bad = Autosave._engine_contents(f2, cap)
		if bad != "":
			p.append("realism stores %d: a fresh engine refuses its own save: %s" % [at[0], bad])
			return
		caps[at[0]] = cap.duplicate(true)
		f2s[at[0]] = f2
		RunSave.apply(f2, cap)
		while e.step_no < int(run["until"]):
			while i < inputs.size() and inputs[i][0] == e.step_no + 1:
				e.apply_input(inputs[i])
				f2.apply_input(inputs[i])
				i += 1
			e.step()
			f2.step()
			if f2.cur != e.cur or f2.digest() != e.digest():
				p.append("realism stores %d: the restored run differs at step %d" % [at[0], e.step_no])
				break
		if f2.events.slice(f2.events.size() - 3) != e.events.slice(e.events.size() - 3):
			p.append("realism stores %d: the restored run's last events differ" % at[0])
	if caps.size() != 2:
		return
	var c7: Dictionary = caps[7]
	var c8: Dictionary = caps[8]
	if c7["busy"].get("ic1", []).size() != 7 or c7["sr_issued"] != {"wo_gauge": {"tx_r4": 1}}:
		p.append("realism stores: the save is not in the middle of the fitting (%s, %s)" % [str(c7["busy"]),
				str(c7["sr_issued"])])
	if c8["sr_orders"].size() != 1 or c8["sr_po"] != 1 or c8["sr_issued"] != {"wo_valve": {"packing": 2}}:
		p.append("realism stores: the save has no order pending (%s)" % str(c8["sr_orders"]))
	var b6: Array = c7["busy"]["ic1"].slice(0, 6)
	var bw: Array = c7["busy"]["ic1"].duplicate()
	bw[6] = "wo_nowhere"
	var o: Array = c8["sr_orders"][0]
	var stock: Array = c8["sr_stock"]
	var cases := [
		[7, {"busy": {"ic1": b6}}], [7, {"busy": {"ic1": bw}}],
		[7, {"sr_issued": {"wo_nowhere": {"tx_r4": 1}}}], [7, {"sr_issued": {"wo_gauge": {"gasket": 1}}}],
		[7, {"sr_issued": {"wo_gauge": {"tx_r4": 0}}}], [7, {"sr_issued": {"wo_gauge": {}}}],
		[8, {"sr_stock": stock.slice(1)}], [8, {"sr_stock": [stock[0] + 1] + stock.slice(1)}],
		[8, {"sr_stock": [-1] + stock.slice(1)}], [8, {"sr_due": c8["sr_due"].map(func(x): return 0)}],
		[8, {"sr_orders": []}], [8, {"sr_orders": [[o[0], "gasket", o[2], o[3], o[4], o[5]]]}],
		[8, {"sr_orders": [[o[0], o[1], 0, o[3], o[4], o[5]]]}], [8, {"sr_orders": [["PO-0002", o[1], o[2], o[3], o[4], o[5]]]}],
		[8, {"sr_orders": [[o[0], o[1], o[2], "nobody", o[4], o[5]]]}], [8, {"sr_orders": [[o[0], o[1], o[2], o[3], o[4], o[4]]]}],
		[8, {"sr_orders": [o.slice(0, 5)]}], [8, {"sr_po": -1}], [8, {"sr_po": 0}],
		[8, {"npc_queue": [["issue", "gasket", 1, "wo_valve", "keeper"]]}],
		[8, {"npc_queue": [["issue", "packing", 1, "wo_nowhere", "keeper"]]}],
		[8, {"npc_queue": [["issue", "packing", null, "wo_valve", "keeper"]]}],
		[8, {"npc_queue": [["order", "packing", null, "nobody"]]}], [8, {"npc_queue": [["order", "packing"]]}],
		[8, {"st_kept": [[["order", 3]]] + c8["st_kept"].slice(1)}],
		[8, {"st_kept": [[["issue", 3, "packing"]]] + c8["st_kept"].slice(1)}],
		[8, {"queue": [["jump", "08:00", 1, 2]]}], [8, {"queue": [["issue", "packing", 1]]}]]
	for c in cases:
		var t: Dictionary = caps[c[0]].duplicate(true)
		for k in c[1]:
			t[k] = c[1][k]
		if Autosave._engine_contents(f2s[c[0]], t) == "":
			p.append("realism stores: a save with %s was taken" % str(c[1]))
	for c in [{"npc_queue": [["order", "packing", null, "keeper"]]}, {"npc_queue": [["issue", "packing", 1, null, "keeper"]]},
			{"sr_po": 10000, "sr_orders": [["PO-10000", o[1], o[2], o[3], o[4], o[5]]]},
			{"st_kept": [[["order", 3, "packing"]]] + c8["st_kept"].slice(1)},
			{"queue": [["jump", "08:00", 1]]}]:
		var t: Dictionary = c8.duplicate(true)
		for k in c:
			t[k] = c[k]
		var why: String = Autosave._engine_contents(f2s[8], t)
		if why != "":
			p.append("realism stores: a save with %s was refused: %s" % [str(c), why])


## The water treatment plant's day work (W3) saved in the middle of its sequences: an RO train being cleaned in place
## (saved just before its first stage ends) and a mixed bed's regenerants being injected (just before its
## displacement), each with the pit's batch and the CIP skid's tank in their states; put back into a fresh engine,
## the run goes on bit for bit through the sequence's next state.
func _round_trip_wtp(m, p: Array) -> void:
	for c in [["ro_cip", "clean_alk", ["00GCB22AT001", "clean"], 2950, "ro_b"],
			["mb_regeneration", "inject", ["00GCF11AT001", "inject"], 3950, "mb_a"]]:
		var pr: Dictionary = m.procedures[c[0]]
		var e = PlantEngine.new(m, pr["scenario"])
		var r := Procedure.run(m, c[0], 3600, e, c[1])
		if r.error != "":
			p.append("%s stopped: %s" % [c[0], r.error])
			continue
		e.op(c[2][0], c[2][1])
		e.step(c[3])
		var state_before: float = e.v(c[4] + "_state")
		var path := DIR.path_join("wtp.save")
		if RunSave.write(path, RunSave.encode(_payload(e))) != OK:
			p.append("%s: the save was not written" % c[0])
			continue
		var got := RunSave.read(path)
		var f2 = PlantEngine.new(m, pr["scenario"])
		if not got["ok"] or RunSave.check(f2, RunSave.engine_fields(f2), got["payload"]["engine"]) != "":
			p.append("%s: the save did not read back or was refused" % c[0])
			continue
		RunSave.apply(f2, got["payload"]["engine"])
		if _bytes(f2) != _bytes(e):
			p.append("%s: the restored engine is not the saved one" % c[0])
			continue
		for k in 200:
			e.step()
			f2.step()
			if f2.cur != e.cur:
				p.append("%s: the restored run differs from the uninterrupted one at step %d" % [c[0], e.step_no])
				break
		if _bytes(f2) != _bytes(e):
			p.append("%s: after 200 steps the restored run's state differs" % c[0])
		if f2.v(c[4] + "_state") == state_before:
			p.append("%s: the sequence did not move on after the save (the comparison proves little)" % c[0])


## The fields a save leaves out are built from the model and the scenario: a run never changes them.
func _compiled_fixed(m, ran, p: Array) -> void:
	var e = PlantEngine.new(m, ran.sc["id"])
	var built := {}
	for prop in e.get_property_list():
		var nm: String = prop["name"]
		if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE and not nm in RunSave.engine_fields(e) and not nm in ["timing", "step_us"]:
			var v = e.get(nm)
			built[nm] = v
	e = ran                     # half the cold start and 400 steps on: the same model, the same scenario
	for nm in built:
		var v = e.get(nm)
		if typeof(v) != typeof(built[nm]) or not (v == built[nm] if typeof(v) != TYPE_OBJECT else is_same(v, built[nm])):
			p.append("the engine's %s changed in a run, but the save leaves it out (state goes in a field not named _…)" % nm)


func _file(m, p: Array) -> void:
	var e = PlantEngine.new(m, "cold_iron")
	e.step(30)
	var good := RunSave.encode(_payload(e))
	if not RunSave.decode(good)["ok"]:
		p.append("a good save is refused: %s" % RunSave.decode(good).get("text"))
	var cases := {}
	var b := good.duplicate()
	b.encode_u32(8, RunSave.FORMAT + 1)
	cases["another format"] = [b, "format"]
	cases["cut short"] = [good.slice(0, good.size() - 7), "corrupt"]
	cases["cut in the header"] = [good.slice(0, 30), "corrupt"]
	b = good.duplicate()
	b[good.size() - 100] ^= 1
	cases["a flipped bit"] = [b, "corrupt"]
	b = good.duplicate()
	b.append(0)
	cases["a byte after the end"] = [b, "corrupt"]
	b = good.duplicate()
	b[0] = 0x58
	cases["another magic"] = [b, "corrupt"]
	cases["a list, not a run"] = [RunSave.encode({"x": 1}).slice(0, 8) + _raw([1, 2, 3]), "corrupt"]
	cases["an unknown part"] = [_with_payload(good, "extra", 1), "corrupt"]
	cases["a part of the wrong kind"] = [_with_payload(good, "engine", []), "corrupt"]
	cases["empty"] = [PackedByteArray(), "corrupt"]
	for c in cases:
		var r := RunSave.decode(cases[c][0])
		if r["ok"] or r["why"] != cases[c][1]:
			p.append("a save %s gives %s, not %s" % [c, str(r.get("why", "ok")), cases[c][1]])
	# random bytes, with and without a valid header and hash around them: refused, never a crash
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in 50:
		var junk := PackedByteArray()
		junk.resize(rng.randi_range(0, 400))
		for i in junk.size():
			junk[i] = rng.randi_range(0, 255)
		if RunSave.decode(junk)["ok"]:
			p.append("random bytes were taken as a save")
			break
		var wrapped := _wrap(junk)
		var r := RunSave.decode(wrapped)
		if r["ok"]:
			p.append("random bytes in a valid frame were taken as a save")
			break
	# a file over the limit is refused before it is read (a sparse file: no disk is used)
	var big := DIR.path_join("big.save")
	var f := FileAccess.open(big, FileAccess.WRITE)
	f.store_buffer(good.slice(0, RunSave.HEAD))
	f.seek(RunSave.MAX_BYTES)
	f.store_8(0)
	f.close()
	var rb := RunSave.read(big)
	if rb["ok"] or rb["why"] != "too_big":
		p.append("a file over %d bytes gives %s" % [RunSave.MAX_BYTES, str(rb.get("why", "ok"))])
	RunSave.remove(big)
	var rm := RunSave.read(DIR.path_join("none.save"))
	if rm["ok"] or rm["why"] != "missing":
		p.append("no save gives %s, not missing" % str(rm.get("why", "ok")))


## A whole payload around an engine's state (the other parts as a save has them, empty).
static func _payload(e, saved_unix := 1) -> Dictionary:
	return {"app": "", "content": "c", "scenario": "cold_iron", "saved_unix": saved_unix,
			"engine": RunSave.capture(e, RunSave.engine_fields(e)), "clock": {}, "procedure": "", "tracker": {},
			"ui": {}, "player": {}, "run": {}}


## A file of the right header and hash around any payload bytes.
static func _wrap(body: PackedByteArray) -> PackedByteArray:
	return RunSave.encode({}).slice(0, 8) + _raw_bytes(body)


static func _raw(v) -> PackedByteArray:
	return _raw_bytes(var_to_bytes(v))


static func _raw_bytes(body: PackedByteArray) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(body)
	var nums := PackedByteArray()
	nums.resize(12)
	nums.encode_u32(0, RunSave.FORMAT)
	nums.encode_u64(4, body.size())
	return nums + ctx.finish() + body


static func _with_payload(good: PackedByteArray, key: String, value) -> PackedByteArray:
	var pl: Dictionary = bytes_to_var(good.slice(RunSave.HEAD))
	pl[key] = value
	return RunSave.encode(pl)


func _atomic(m, p: Array) -> void:
	var path := DIR.path_join("at.save")
	var e = PlantEngine.new(m, "cold_iron")
	var one := RunSave.encode(_payload(e, 1))
	e.step(10)
	var two := RunSave.encode(_payload(e, 2))
	RunSave.write(path, one)
	RunSave.write(path, two)
	for nm in DirAccess.get_files_at(DIR):
		if nm.begins_with("at.save.tmp"):
			p.append("a write left its .tmp behind (%s)" % nm)
	if FileAccess.get_file_as_bytes(path) != two:
		p.append("a second write did not replace the first")
	# killed while writing the next one: half a .tmp; the save read is the last complete one
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	f.store_buffer(one.slice(0, one.size() / 2))
	f.close()
	var r := RunSave.read(path)
	if not r["ok"] or r["payload"]["saved_unix"] != 2:
		p.append("half a .tmp hid the complete save")
	# a write cut short in the middle of path itself (no rename): the .tmp, complete, is taken
	RunSave.write(path + ".tmp", one)       # (a complete .tmp, as a rename that could not replace leaves it)
	FileAccess.open(path, FileAccess.WRITE).store_buffer(two.slice(0, 40))
	r = RunSave.read(path)
	if not r["ok"] or r["payload"]["saved_unix"] != 1:
		p.append("a damaged save with a complete .tmp did not load the .tmp")
	RunSave.remove(path)
	RunSave.write(path + ".tmp", one)
	if not RunSave.read(path)["ok"]:
		p.append("a complete .tmp alone (the save renamed away) was not loaded")
	RunSave.remove(path)
	# an older save and a newer complete .tmp beside it (a rename that failed): the newer is taken
	RunSave.write(path, one)
	RunSave.write(path + ".tmp", two)
	r = RunSave.read(path)
	if not r["ok"] or r["payload"]["saved_unix"] != 2:
		p.append("an older save hid a newer complete .tmp")
	RunSave.remove(path)
	# a failed write (no such folder) returns its error
	if RunSave.write(DIR.path_join("no/such/folder.save"), one) == OK:
		p.append("a write into a missing folder said OK")


func _app(tree: SceneTree, p: Array) -> void:
	var path: String = Autosave.default_path
	RunSave.remove(path)
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null or ui.autosave == null:
		main.free()
		p.append("the app did not start with its autosave")
		return
	if ui.autosave.offer_panel != null or not ui.autosave.armed:
		p.append("without a saved run the app offered one, or did not save")
	# a run: the cold start's procedure, its first operations, the plant run for a while, the trainee somewhere else
	ui.start_procedure("cold_start", null, false)
	ui.go_control_room()
	ui.open_card("00QFA10AN001")
	ui.do_op({"kks": "00QFA10AN001", "do": "start"}, null)
	ui.clock.run_steps(1)
	App.run_until(ui, "ia_p_norm", 20000)
	ui.clock.run_steps(30)
	ui.do_op({"kks": "00PGC10AP001", "do": "start"}, null)     # sent, not yet stepped: pending across the save
	ui.player.set_mode(ui.player.Mode.FLY)
	ui.player.global_position = Vector3(12.0, 9.0, -7.0)
	ui.player.set_heading(1.25, -0.3)
	ui.clock.pause_on_hold = true
	await tree.process_frame
	if not ui.autosave.save_now():
		p.append("the run was not saved")
	var saved_tr: Dictionary = RunSave.capture(ui.tracker, RunSave.tracker_fields(ui.tracker))
	var saved_since: Dictionary = ui.alarms.since.duplicate()
	var saved_results: Dictionary = ui.results.duplicate(true)
	var saved_step: int = ui.clock.engine.step_no
	# the uninterrupted run, 300 steps on (or to a procedure step's end)
	var want_ran: int = ui.clock.run_steps(300)
	var want := _bytes(ui.clock.engine)
	var want_tr: int = ui.tracker.index
	var want_ui := var_to_bytes([ui.results, ui._pending, ui.alarms.since, ui.tracker.deviations, ui.tracker.log])
	main.free()
	# started again: Continue
	main = App.start(tree)
	ui = main.ui
	var cont := App.find_button(ui, "Continue")
	if cont == null:
		p.append("a saved run was not offered at start: %s" % App.texts(ui).left(300))
		main.free()
		return
	if ui.autosave.armed:
		p.append("the app saved before the trainee chose (the saved run would be lost)")
	if not ui.player.scripted or ui.clock.speed != SimClock.Speed.PAUSED:
		p.append("the plant can be walked or runs behind the offer")
	if not App.texts(ui.autosave.offer_panel).contains("Cold start"):
		p.append("the offer does not name the run: %s" % App.texts(ui.autosave.offer_panel))
	cont.pressed.emit()
	await tree.process_frame
	var e = ui.clock.engine
	if e.step_no != saved_step:
		p.append("Continue put the plant at step %d, not %d" % [e.step_no, saved_step])
	if ui.tracker == null or RunSave.capture(ui.tracker, RunSave.tracker_fields(ui.tracker)) != saved_tr:
		p.append("Continue did not put the procedure's progress back")
	if ui.alarms.since != saved_since or ui.results != saved_results:
		p.append("Continue did not put the alarms' times or the operations' results back")
	if not ui.clock.pause_on_hold or ui.clock.speed != SimClock.Speed.PAUSED:
		p.append("Continue did not put the clock back (paused, pause when a step is done)")
	if ui.player.global_position.distance_to(Vector3(12.0, 9.0, -7.0)) > 0.01 or absf(ui.player.rotation.y - 1.25) > 1e-6 \
			or absf(ui.player.pivot.rotation.x + 0.3) > 1e-6 or ui.player.mode != ui.player.Mode.FLY:
		p.append("Continue did not put the trainee back: %s" % str(ui.player.global_position))
	if not ui.autosave.armed or ui.autosave.offer_panel != null:
		p.append("after Continue the offer stayed or the saving did not start")
	if ui.clock.run_steps(300) != want_ran:
		p.append("the continued run ran another number of steps than the uninterrupted one")
	if var_to_bytes([ui.results, ui._pending, ui.alarms.since, ui.tracker.deviations, ui.tracker.log]) != want_ui:
		p.append("after Continue the operations' results, alarm times or procedure log differ from the uninterrupted run")
	if _bytes(ui.clock.engine) != want:
		p.append("the continued run differs from the one that never stopped")
	if ui.tracker.index != want_tr:
		p.append("the continued procedure is at step %d, the uninterrupted one at %d" % [ui.tracker.index, want_tr])
	# the periodic save: copied at this step, encoded and written on the worker thread while the plant goes on
	var at_step: int = ui.clock.engine.step_no
	var want_state := var_to_bytes(RunSave.capture(ui.clock.engine, RunSave.engine_fields(ui.clock.engine)))
	ui.autosave._t = Autosave.INTERVAL
	ui.autosave._process(0.0)
	if ui.autosave._thread == null:
		p.append("the periodic save did not start")
	ui.clock.run_steps(50)
	for i in 300:
		if ui.autosave._thread == null:
			break
		await tree.process_frame
	var rp := RunSave.read(path)
	if not rp["ok"] or rp["payload"]["engine"]["step_no"] != at_step \
			or var_to_bytes(rp["payload"]["engine"]) != want_state:
		p.append("the periodic save is not the state of the step it was taken at")
	# going to the background saves at once
	ui.clock.run_steps(7)
	for what in [Node.NOTIFICATION_APPLICATION_PAUSED, Node.NOTIFICATION_WM_CLOSE_REQUEST,
			Node.NOTIFICATION_APPLICATION_FOCUS_OUT, Node.NOTIFICATION_WM_GO_BACK_REQUEST]:
		ui.clock.run_steps(7)
		ui.autosave.notification(what)
		rp = RunSave.read(path)
		if not rp["ok"] or rp["payload"]["engine"]["step_no"] != ui.clock.engine.step_no:
			p.append("notification %d (background, close, focus out, Back) did not save the run" % what)
	# a procedure stopped: kept for the debrief, and so after a restore
	if ui.run_tracker != ui.tracker:
		p.append("after Continue the debrief does not follow the restored procedure")
	ui.stop_procedure()
	var want_log := var_to_bytes([ui.run_tracker.log, ui.run_tracker.deviations, ui.run_tracker.index])
	ui.autosave.save_now()
	rp = RunSave.read(path)
	var why: String = ui.autosave.check(rp["payload"]) if rp["ok"] else rp["text"]
	if why != "" or rp["payload"]["run"].get("same", true):
		p.append("a stopped procedure kept for the debrief was not saved: %s" % why)
	else:
		ui.autosave.restore(rp["payload"])
		if ui.tracker != null or ui.run_tracker == null \
				or var_to_bytes([ui.run_tracker.log, ui.run_tracker.deviations, ui.run_tracker.index]) != want_log:
			p.append("a stopped procedure kept for the debrief did not come back")
	main.free()
	# New run: a fresh plant, and the save replaced
	main = App.start(tree)
	ui = main.ui
	var nb := App.find_button(ui, "New run")
	if nb == null:
		p.append("no New run at start")
	else:
		ui.clock.engine.step(3)            # (as if something had run behind the offer: New run starts afresh)
		nb.pressed.emit()
		var r := RunSave.read(path)
		if ui.clock.engine.step_no != 0 or not r["ok"] or r["payload"]["engine"]["step_no"] != 0:
			p.append("New run did not start afresh and replace the save")
	# a save of other content, then a damaged one: refused with the reason, a new run starts
	var pl: Dictionary = ui.autosave.payload()
	main.free()
	# switched off (ui/autosave.gd carries(), until the owner's check): as plant-v0.3.0, a save of another build, of
	# other content or a damaged one is refused with its reason and a new run starts
	Autosave.switch_override = 0
	for c in [["content", "content has changed"], ["app", "another version of the app"],
			["contents", "a machine in a state it doesn't have"], ["damaged", "cut short"]]:
		if c[0] == "contents":
			var q := pl.duplicate(true)
			q["engine"]["mstate"][0] = 99         # under a matching hash
			RunSave.write(path, RunSave.encode(q))
		elif c[0] == "content":
			var q := pl.duplicate(true)
			q["content"] = "0".repeat(64)
			RunSave.write(path, RunSave.encode(q))
		elif c[0] == "app":
			var q := pl.duplicate(true)
			q["app"] = "0.0.1+0123456789abcdef"
			RunSave.write(path, RunSave.encode(q))
		else:
			var b := FileAccess.get_file_as_bytes(path)
			FileAccess.open(path, FileAccess.WRITE).store_buffer(b.slice(0, b.size() - 3))
		main = App.start(tree)
		ui = main.ui
		var txt := App.texts(ui)
		if App.find_button(ui, "Continue") != null or not txt.contains("can't be continued") or not txt.contains(c[1]):
			p.append("a save (%s) was not refused with its reason: %s" % [c[0], txt.left(300)])
		var nb2 := App.find_button(ui, "New run")
		if nb2 == null:
			p.append("a refused save offers no New run")
		else:
			nb2.pressed.emit()
			if not ui.autosave.armed or ui.clock.engine.step_no != 0:
				p.append("after a refused save the new run did not start")
		main.free()
	Autosave.switch_override = 1
	# a save this build can't continue: refused with the reason, kept aside under the name the offer gives (#447), a new
	# run starts
	for c in [["newer", "newer version of the app (99.0.0)"],
			["contents", "a machine in a state it doesn't have"], ["damaged", "cut short"],
			["format", "save format 7"]]:
		if c[0] == "contents":
			var q := pl.duplicate(true)
			q["engine"]["mstate"][0] = 99         # under a matching hash
			RunSave.write(path, RunSave.encode(q))
		elif c[0] == "newer":
			var q := pl.duplicate(true)
			q["app"] = "99.0.0+0123456789abcdef"
			RunSave.write(path, RunSave.encode(q))
		elif c[0] == "format":
			var b := RunSave.encode(pl)
			b.encode_u32(8, 7)
			RunSave.write(path, b)
		else:
			var b := FileAccess.get_file_as_bytes(path)
			FileAccess.open(path, FileAccess.WRITE).store_buffer(b.slice(0, b.size() - 3))
		var as_saved := FileAccess.get_file_as_bytes(path)
		main = App.start(tree)
		ui = main.ui
		var txt := App.texts(ui)
		var kept: String = ui.autosave.kept
		if App.find_button(ui, "Continue") != null or not txt.contains("can't be continued") or not txt.contains(c[1]) \
				or kept == "" or not txt.contains("kept on this device as %s" % kept):
			p.append("a save (%s) was not refused with its reason and the name it is kept under: %s" % [c[0], txt.left(400)])
		var nb2 := App.find_button(ui, "New run")
		if nb2 == null:
			p.append("a refused save offers no New run")
		else:
			nb2.pressed.emit()
			if not ui.autosave.armed or ui.clock.engine.step_no != 0:
				p.append("after a refused save the new run did not start")
			var kp := path.get_base_dir().path_join(kept)
			if kept == "" or FileAccess.get_file_as_bytes(kp) != as_saved:
				p.append("a refused save (%s) was not kept aside as it was (%s)" % [c[0], kept])
			DirAccess.remove_absolute(ProjectSettings.globalize_path(kp))
		main.free()
	await _other_build(tree, pl, p)
	await _old_release(tree, p)
	_remap(p)
	Autosave.switch_override = -1
	await _deviation(tree, p)
	if not FileAccess.file_exists(path + ".prev"):
		p.append("New run did not keep the run it replaced")
	# a second window while another one saves to the run: it offers nothing and saves apart
	var other := OS.create_process("sleep", ["60"])
	FileAccess.open(path + ".lock", FileAccess.WRITE).store_string(str(other))
	main = App.start(tree)
	ui = main.ui
	if App.find_button(ui, "Continue") != null or App.find_button(ui, "New run") != null \
			or not ui.autosave.path.ends_with("run-second.save") or not ui.autosave.armed:
		p.append("a second window offered the run or saves over the first one's (%s)" % ui.autosave.path)
	main.free()
	OS.kill(other)
	if FileAccess.get_file_as_string(path + ".lock") != str(other):
		p.append("the second window took the first one's lock")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".lock"))
	RunSave.remove(path)
	RunSave.remove(path.get_base_dir().path_join("run-second.save"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".prev"))


## A save of another build of this release (an update with other code or content, #447): offered, and Continue makes
## it again in this build; the file as saved is kept aside.
func _other_build(tree: SceneTree, pl: Dictionary, p: Array) -> void:
	var path: String = Autosave.default_path
	for c in [["app", "0.0.1+0123456789abcdef"], ["content", "0".repeat(64)]]:
		var q := pl.duplicate(true)
		q[c[0]] = c[1]
		RunSave.write(path, RunSave.encode(q))
		var as_saved := FileAccess.get_file_as_bytes(path)
		var main := App.start(tree)
		var ui = main.ui
		var cont := App.find_button(ui, "Continue")
		var kept: String = ui.autosave.kept
		if cont == null or kept == "" or not App.texts(ui).contains("kept as %s" % kept):
			p.append("a save of another build (%s) was not offered with the name it is kept under: %s" % [c[0], App.texts(ui).left(400)])
			main.free()
			continue
		cont.pressed.emit()
		for i in 600:
			if ui.autosave.offer_panel == null:
				break
			await tree.process_frame
		var r := RunSave.read(path)
		var kp := path.get_base_dir().path_join(kept)
		if ui.autosave.offer_panel != null or not ui.autosave.armed or not r["ok"] \
				or r["payload"]["app"] != RunSave.app_version() or r["payload"]["content"] != ui.autosave.content:
			p.append("a save of another build (%s) was not continued in this one: %s" % [c[0], App.texts(ui).left(300)])
		if FileAccess.get_file_as_bytes(kp) != as_saved:
			p.append("a save of another build (%s) was not kept aside as it was" % c[0])
		DirAccess.remove_absolute(ProjectSettings.globalize_path(kp))
		main.free()
	RunSave.remove(path)


## The save of the release before (tests/fixtures/run-0.3.0.save, written by plant-v0.3.0's own autosave:
## tools/plant3d/old_saves/): Continue makes the run again in this build (the plant at the saved step with the same
## inputs, the procedure's progress and its deviation, the operation still pending, the trainee where they were) and
## the file as saved is kept aside; the run goes on and is saved as this build's. Then the same save with a scenario
## this plant hasn't: kept aside with its reason, a new run.
func _old_release(tree: SceneTree, p: Array) -> void:
	var path: String = Autosave.default_path
	RunSave.remove(path)
	var fx := FileAccess.get_file_as_bytes("res://tests/fixtures/run-0.3.0.save")
	var d := RunSave.decode(fx)
	if not d["ok"]:
		p.append("the 0.3.0 fixture does not decode: %s" % d.get("text", ""))
		return
	var op: Dictionary = d["payload"]
	if RunSave.version_of(op["app"]) != "0.3.0" or op["engine"]["inputs"].size() != 4 \
			or op["tracker"]["deviations"].size() != 1:
		p.append("the 0.3.0 fixture is not the one described (%s)" % op["app"])
		return
	RunSave.write(path, fx)
	var main := App.start(tree)
	var ui = main.ui
	var txt := App.texts(ui)
	var cont := App.find_button(ui, "Continue")
	var kept: String = ui.autosave.kept
	for i in 3:
		await tree.process_frame
	var vh: float = ui.root.get_viewport_rect().size.y
	if ui.autosave.offer_panel.size.y > vh - 32.0 or ui.autosave.offer_panel.get_global_rect().end.y > vh:
		p.append("the offer is not as tall as its words, or goes past the screen: %s in a window %s high"
				% [str(ui.autosave.offer_panel.get_global_rect()), vh])
	if cont == null or not txt.contains("saved by version 0.3.0") or not txt.contains("kept as %s" % kept) \
			or not kept.contains("0.3.0"):
		p.append("the 0.3.0 save was not offered to continue: %s" % txt.left(400))
		main.free()
		RunSave.remove(path)
		return
	# made again slowly (a small slice a frame): the offer says how far it is and New run keeps the focus Continue had
	Autosave.migrate_budget_us = 1
	cont.grab_focus()
	cont.pressed.emit()
	await tree.process_frame
	var fo = ui.root.get_viewport().gui_get_focus_owner()
	if not App.texts(ui.autosave.offer_panel).contains("Making the run again in this version") \
			or fo == null or not fo is Button or fo.text != "New run":
		p.append("while the 0.3.0 run is made again, the offer shows no progress or New run lacks the focus: %s, focus %s"
				% [App.texts(ui.autosave.offer_panel).left(200), str(fo)])
	Autosave.migrate_budget_us = 20000
	for i in 1200:
		if ui.autosave.offer_panel == null:
			break
		await tree.process_frame
	var e = ui.clock.engine
	if ui.autosave.offer_panel != null or not ui.autosave.armed:
		p.append("the 0.3.0 save was not made again: %s" % (App.texts(ui.autosave.offer_panel) if ui.autosave.offer_panel != null else "").left(400))
		main.free()
		RunSave.remove(path)
		return
	if e.step_no != op["engine"]["step_no"] or var_to_bytes(e.inputs) != var_to_bytes(op["engine"]["inputs"]):
		p.append("the 0.3.0 run made again is at step %d with %d inputs, not %d with %d" % [e.step_no, e.inputs.size(),
				op["engine"]["step_no"], op["engine"]["inputs"].size()])
	var t = ui.tracker
	if t == null or t.proc.get("id") != "cold_start":
		p.append("the 0.3.0 run's procedure did not come back")
	else:
		if t.index != op["tracker"]["index"] or t.log != op["tracker"]["log"]:
			p.append("the 0.3.0 run's procedure is at step %d, not %d" % [t.index, op["tracker"]["index"]])
		var dv: Array = t.deviations
		if dv.size() != 1 or dv[0][1] != op["tracker"]["deviations"][0][1] or dv[0][2] < 0 or dv[0][2] >= e.events.size() \
				or e.events[dv[0][2]][1] != "op" or e.events[dv[0][2]][2] != "30PAR10AA001":
			p.append("the 0.3.0 run's deviation does not point at its operation: %s" % str(dv))
	if ui.player.global_position.distance_to(Vector3(12.0, 9.0, -7.0)) > 0.01 or ui.player.mode != ui.player.Mode.FLY:
		p.append("the 0.3.0 run did not put the trainee back: %s" % str(ui.player.global_position))
	var kp := path.get_base_dir().path_join(kept)
	if FileAccess.get_file_as_bytes(kp) != fx:
		p.append("the 0.3.0 save was not kept aside as it was (%s)" % kept)
	var r := RunSave.read(path)
	if not r["ok"] or r["payload"]["app"] != RunSave.app_version() or ui.autosave.check(r["payload"]) != "":
		p.append("the 0.3.0 run made again was not saved as this build's: %s" % (ui.autosave.check(r["payload"]) if r["ok"] else r["text"]))
	# it goes on: the operation sent before the save is made at the next step
	var n0: int = e.events.size()
	ui.clock.run_steps(5)
	var pending_done := false
	for i in range(n0, e.events.size()):
		if e.events[i].size() > 2 and e.events[i][1] == "op" and e.events[i][2] == "00PGC10AP002":
			pending_done = true
	if not pending_done:
		p.append("the 0.3.0 run's pending operation was not made after it was continued")
	main.free()
	# started again: an ordinary save of this build
	main = App.start(tree)
	ui = main.ui
	if App.find_button(ui, "Continue") == null or ui.autosave.kept != "":
		p.append("the 0.3.0 run made again is not offered as this build's save: %s" % App.texts(ui).left(300))
	main.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(kp))
	# the same save in a scenario this plant hasn't: it can't be made again; kept aside, a new run
	var q := op.duplicate(true)
	q["scenario"] = "no_such_scenario"
	var bad := RunSave.encode(q)
	RunSave.write(path, bad)
	main = App.start(tree)
	ui = main.ui
	txt = App.texts(ui)
	kept = ui.autosave.kept
	if App.find_button(ui, "Continue") != null or not txt.contains("can't be continued") \
			or not txt.contains("scenario is not in this version's plant") or not txt.contains("kept on this device as %s" % kept):
		p.append("a 0.3.0 save that can't be made again was not refused with its reason and name: %s" % txt.left(400))
	var nb := App.find_button(ui, "New run")
	if nb != null:
		nb.pressed.emit()
	kp = path.get_base_dir().path_join(kept)
	r = RunSave.read(path)
	if nb == null or FileAccess.get_file_as_bytes(kp) != bad or not r["ok"] or r["payload"]["engine"]["step_no"] != 0:
		p.append("a 0.3.0 save that can't be made again was not kept aside, or no new run started")
	main.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(kp))
	# saves an offer could not show (it stopped half-built, the plant paused, nothing saved again): a procedure this
	# plant hasn't, a step past its procedure, an event of one item; each refused with its reason and kept aside
	for c in [["procedure", "procedure is not in this version's plant"], ["index", "step is not in this version's procedure"],
			["event", "record of events is damaged"], ["run", "debrief's procedure is not in this version's plant"]]:
		q = op.duplicate(true)
		if c[0] == "procedure":
			q["procedure"] = "no_such_procedure"
		elif c[0] == "index":
			q["tracker"]["index"] = 999
		elif c[0] == "event":
			q["engine"]["events"].append([q["engine"]["step_no"]])
		else:
			q["run"] = {"procedure": "no_such_procedure", "same": false, "tracker": {}}
		RunSave.write(path, RunSave.encode(q))
		main = App.start(tree)
		ui = main.ui
		txt = App.texts(ui)
		if ui.autosave.offer_panel == null or App.find_button(ui, "New run") == null or not txt.contains(c[1]) \
				or not txt.contains("kept on this device as"):
			p.append("a 0.3.0 save with %s that doesn't fit was not refused with its reason: %s" % [c[0], txt.left(300)])
		main.free()
	# a run made again whose state this build refuses (its panels' record damaged): said after Continue, New run focused,
	# the save kept aside at New run
	q = op.duplicate(true)
	q["ui"]["results"] = {"00PGC10AP001": 5}
	bad = RunSave.encode(q)
	RunSave.write(path, bad)
	main = App.start(tree)
	ui = main.ui
	kept = ui.autosave.kept
	cont = App.find_button(ui, "Continue")
	if cont == null:
		p.append("a 0.3.0 save with a damaged panel record was not offered: %s" % App.texts(ui).left(300))
	else:
		cont.grab_focus()
		cont.pressed.emit()
		for i in 600:
			if ui.autosave.migrating == null:
				break
			await tree.process_frame
		await tree.process_frame
		txt = App.texts(ui.autosave.offer_panel) if ui.autosave.offer_panel != null else ""
		fo = ui.root.get_viewport().gui_get_focus_owner()
		if not txt.contains("can't be continued") or not txt.contains("panels' state is damaged") \
				or fo == null or not fo is Button or fo.text != "New run":
			p.append("a 0.3.0 run that can't be put back after it was made again was not said so with New run focused: %s, focus %s"
					% [txt.left(300), str(fo)])
		if fo is Button:
			fo.pressed.emit()
		kp = path.get_base_dir().path_join(kept)
		if FileAccess.get_file_as_bytes(kp) != bad or not ui.autosave.armed:
			p.append("a 0.3.0 run that can't be put back was not kept aside at New run")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(kp))
	main.free()
	# the copy aside fails (a folder stands where the kept file would go): nothing replaced, said in words, Replace it
	# focused; Replace it starts a new run and keeps the save as run.save.prev
	q = op.duplicate(true)
	q["scenario"] = "no_such_scenario"
	bad = RunSave.encode(q)
	RunSave.write(path, bad)
	main = App.start(tree)
	ui = main.ui
	kept = ui.autosave.kept
	kp = path.get_base_dir().path_join(kept)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(kp))
	nb = App.find_button(ui, "New run")
	if nb != null:
		nb.pressed.emit()
	await tree.process_frame
	txt = App.texts(ui.autosave.offer_panel) if ui.autosave.offer_panel != null else ""
	fo = ui.root.get_viewport().gui_get_focus_owner()
	if not txt.contains("could not be kept aside") or not txt.contains("Nothing was replaced") or ui.autosave.armed \
			or FileAccess.get_file_as_bytes(path) != bad or fo == null or not fo is Button or fo.text != "Replace it":
		p.append("a failed copy aside was not said, or something was replaced: %s, focus %s" % [txt.left(300), str(fo)])
	if fo is Button and fo.text == "Replace it":
		fo.pressed.emit()
		r = RunSave.read(path)
		if not ui.autosave.armed or not r["ok"] or r["payload"]["engine"]["step_no"] != 0 \
				or FileAccess.get_file_as_bytes(path + ".prev") != bad:
			p.append("Replace it did not start a new run keeping the save as run.save.prev")
	main.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(kp))
	RunSave.remove(path)


## A run with a deviation in its procedure is saved and offered to continue (it was refused: the check expected a
## deviation of two items, the tracker writes five).
func _deviation(tree: SceneTree, p: Array) -> void:
	var path: String = Autosave.default_path
	RunSave.remove(path)
	var main := App.start(tree)
	var ui = main.ui
	ui.start_procedure("cold_start", null, false)
	ui.go_control_room()
	ui.do_op({"kks": "00PGC10AP001", "do": "start"}, null)    # step 2's, at step 1: a deviation
	ui.clock.run_steps(5)
	var devs: Array = ui.tracker.deviations.duplicate(true)
	if devs.is_empty():
		p.append("the deviation test made no deviation")
	ui.autosave.save_now()
	var r := RunSave.read(path)
	var why: String = ui.autosave.check(r["payload"]) if r["ok"] else r["text"]
	if why != "":
		p.append("a run with a deviation is refused: %s" % why)
	main.free()
	main = App.start(tree)
	ui = main.ui
	var cont := App.find_button(ui, "Continue")
	if cont == null:
		p.append("a run with a deviation was not offered: %s" % App.texts(ui).left(300))
	else:
		cont.pressed.emit()
		await tree.process_frame
		if ui.tracker == null or ui.tracker.deviations != devs:
			p.append("a run with a deviation did not come back with it")
	main.free()
	RunSave.remove(path)


## The event positions a procedure's progress holds, moved to a run made again (ui/run_migrate.gd): by their place
## among their model step's events, a deviation's operation by its rank among the step's operations.
func _remap(p: Array) -> void:
	var Migrate = load("res://ui/run_migrate.gd")
	var old_ev := [[5, "op", "A"], [5, "op", "B"], [6, "x"]]
	var new_ev := [[4, "y"], [5, "alarm"], [5, "op", "A"], [5, "op", "B"], [6, "x"]]
	var t: Dictionary = Migrate.remap_tracker({"_seen": 2, "ev_from": 1, "ev_to": 3, "deviations": [[5, "t", 1, 0, 0]]},
			old_ev, new_ev, 6)
	if t["_seen"] != 4 or t["ev_from"] != 2 or t["ev_to"] != 5 or t["deviations"][0][2] != 3:
		p.append("the procedure's event positions were not moved by their place in their step: %s" % str(t))
