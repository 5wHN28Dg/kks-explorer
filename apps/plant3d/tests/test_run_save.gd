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
##   and the trainee back, and the run goes on as the saved one did; New run replaces the save; a save of other
##   content or a damaged one is refused with its reason and a new run starts.
extends RefCounted

const PlantModel = preload("res://sim/plant_model.gd")
const PlantEngine = preload("res://sim/engine.gd")
const Procedure = preload("res://sim/procedure.gd")
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
	if ran != null:
		_compiled_fixed(m, ran, p)
	_file(m, p)
	_atomic(m, p)
	await _app(tree, p)
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
