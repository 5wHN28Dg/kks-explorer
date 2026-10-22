## Saved runs (the user, 2026-10-19; the file: ui/run_save.gd, apps/plant3d/README.md "Saved runs"): the whole run
## is saved to user:// every few seconds of real time while it changes, and at once when the app goes to the
## background, loses the focus or is closed, so that it continues after Android has killed the app. At start, a
## saved run is offered: Continue or New run (a save that can't be continued says why, and a new run starts).
##
## Off the frame: a periodic save copies the state on the main thread (about 0.1 ms on a laptop, so about half a
## millisecond on the Note 9: tests/bench_save.gd) and encodes and writes it on a worker thread. The save on going to
## the background is made on the main thread at once (the app may be stopped right after). While the offer is up,
## the plant waits paused behind it and nothing can be walked or worked: nothing is saved until the trainee chooses.
extends Node

const RunSave = preload("res://ui/run_save.gd")
const PlantEngine = preload("res://sim/engine.gd")
const SimClock = preload("res://ui/sim_clock.gd")
const Tracker = preload("res://ui/procedure_tracker.gd")
const W = preload("res://ui/widgets.gd")

const INTERVAL := 5.0           # seconds of real time between saves while the run changes

static var default_path := "user://run.save"   # tests/run_tests.gd points it elsewhere

var ui                          # ui/plant_ui.gd
var path := ""
var content := ""               # the content's hash (RunSave.content_hash)
var armed := false              # saving; not before the trainee has chosen Continue or New run
var offer_panel: PanelContainer
var _offer_layer: CanvasLayer   # over everything: the plant can't be walked or worked until the trainee chooses
var last_error := ""            # why the last load was refused ("" when it was not)
var saves := 0                  # saves written (tests)
var capture_us := 0             # the main thread's part of the last periodic save
var _t := 0.0
var _lt := 0.0
var _sig := ""
var _thread: Thread


func setup(u, content_dir: String, save_path := "") -> void:
	ui = u
	path = save_path if save_path != "" else default_path
	content = RunSave.content_hash(content_dir)


## At start: offers a saved run (the plant waits, paused), or arms the saving at once when there is none.
func begin(offer := true) -> void:
	if other_window():
		# a second window (a link opened on a desktop starts one): its run is kept apart, the first one's is untouched
		path = path.get_base_dir().path_join("run-second.save")
		offer = false
		ui.toast("Walkdown Plant is open in another window: this window's run is saved apart and not offered again.", 8.0)
	_claim()
	if not offer:
		armed = true
		return
	var r := RunSave.read(path)
	if not r["ok"] and r["why"] == "missing":
		armed = true
		return
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	var why := ""
	if r["ok"]:
		why = check(r["payload"])
	else:
		why = r["text"]
	_show_offer(r["payload"] if r["ok"] and why == "" else {}, why)


## Another instance of the app saves to this path now: its pid is in path.lock, it runs, and it renewed the lock
## lately (a pid alone can be reused). Android runs one instance only: never there.
func other_window() -> bool:
	if OS.has_feature("mobile"):
		return false
	var lp := path + ".lock"
	if not FileAccess.file_exists(lp):
		return false
	var pid := FileAccess.get_file_as_string(lp).strip_edges().to_int()
	var age := Time.get_unix_time_from_system() - FileAccess.get_modified_time(lp)
	return pid > 0 and pid != OS.get_process_id() and age < 3.0 * INTERVAL and OS.is_process_running(pid)


func _claim() -> void:
	if OS.has_feature("mobile"):
		return
	var f := FileAccess.open(path + ".lock", FileAccess.WRITE)
	if f != null:
		f.store_string(str(OS.get_process_id()))


func _release() -> void:
	var lp := path + ".lock"
	if FileAccess.file_exists(lp) and FileAccess.get_file_as_string(lp).strip_edges().to_int() == OS.get_process_id():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(lp))


func offering() -> bool:
	return offer_panel != null


# ------------------------------------------------------------------ what is saved

func payload() -> Dictionary:
	var e = ui.clock.engine
	var tr = ui.tracker
	var pl = ui.player
	var pid := ""
	var td := {}
	if tr != null and typeof(tr.proc.get("id")) == TYPE_STRING and ui.model.procedures.has(tr.proc["id"]):
		pid = tr.proc["id"]
		td = RunSave.capture(tr, RunSave.tracker_fields(tr))
	# the last procedure followed, kept for the debrief after it was closed (ui/plant_ui.gd run_tracker)
	var run := {}
	var rt = ui.run_tracker
	if rt != null and typeof(rt.proc.get("id")) == TYPE_STRING and ui.model.procedures.has(rt.proc["id"]):
		run = {"procedure": rt.proc["id"], "same": rt == tr,
				"tracker": {} if rt == tr else RunSave.capture(rt, RunSave.tracker_fields(rt))}
	return {
		"app": RunSave.app_version(), "content": content, "scenario": ui.clock.scenario,
		"saved_unix": int(Time.get_unix_time_from_system()),
		"engine": RunSave.capture(e, RunSave.engine_fields(e)),
		"clock": {"speed": ui.clock.speed, "ff_want": ui.clock.ff_want, "pause_on_hold": ui.clock.pause_on_hold},
		"procedure": pid, "tracker": td, "run": run,
		"ui": {"results": ui.results.duplicate(true), "pending": ui._pending.duplicate(true)},
		"player": {"pos": pl.global_position, "yaw": pl.rotation.y, "pitch": pl.pivot.rotation.x,
				"fly": pl.mode == pl.Mode.FLY},
	}


## Why this payload can't be continued here, or "".
func check(p: Dictionary) -> String:
	if p["app"] != RunSave.app_version():
		return "it was saved by another version of the app (%s)" % p["app"]
	if p["content"] != content:
		return "the plant's content has changed since"
	if not ui.model.scenarios.has(p["scenario"]):
		return "its scenario is not in this plant"
	var fresh = PlantEngine.new(ui.model, p["scenario"])
	var bad := RunSave.check(fresh, RunSave.engine_fields(fresh), p["engine"])
	if bad == "":
		bad = _engine_contents(fresh, p["engine"])
	if bad != "":
		return "the plant's state does not fit this version: " + bad
	var c: Dictionary = p["clock"]
	if c.size() != 3 or typeof(c.get("speed")) != TYPE_INT or not c["speed"] in [0, 1, 2] \
			or typeof(c.get("ff_want")) != TYPE_FLOAT or not (c["ff_want"] >= 1.0 and c["ff_want"] <= SimClock.FF_MAX) \
			or typeof(c.get("pause_on_hold")) != TYPE_BOOL:
		return "its clock is damaged"
	if p["procedure"] != "":
		if not ui.model.procedures.has(p["procedure"]):
			return "its procedure is not in this plant"
		var t = Tracker.new()
		bad = RunSave.check(t, RunSave.tracker_fields(t), p["tracker"])
		if bad != "":
			return "its procedure's progress does not fit this version: " + bad
		var nsteps: int = ui.model.procedures[p["procedure"]].get("steps", []).size()
		if p["tracker"]["index"] < -1 or p["tracker"]["index"] >= nsteps or not _tracker_contents(p["tracker"], p["engine"]):
			return "its procedure's progress is damaged"
	elif not p["tracker"].is_empty():
		return "its procedure's progress is damaged"
	var run: Dictionary = p["run"]
	if not run.is_empty():
		if run.size() != 3 or typeof(run.get("procedure")) != TYPE_STRING or typeof(run.get("same")) != TYPE_BOOL \
				or typeof(run.get("tracker")) != TYPE_DICTIONARY or not ui.model.procedures.has(run["procedure"]):
			return "its debrief's procedure is damaged"
		if run["same"]:
			if run["procedure"] != p["procedure"] or not run["tracker"].is_empty():
				return "its debrief's procedure is damaged"
		else:
			var t2 = Tracker.new()
			bad = RunSave.check(t2, RunSave.tracker_fields(t2), run["tracker"])
			if bad != "" or not _tracker_contents(run["tracker"], p["engine"]) \
					or run["tracker"]["index"] >= ui.model.procedures[run["procedure"]].get("steps", []).size():
				return "its debrief's procedure is damaged"
	var u: Dictionary = p["ui"]
	if u.size() != 2 or typeof(u.get("results")) != TYPE_DICTIONARY or typeof(u.get("pending")) != TYPE_ARRAY \
			or not _ui_contents(u):
		return "its panels' state is damaged"
	var pl: Dictionary = p["player"]
	if pl.size() != 4 or typeof(pl.get("pos")) != TYPE_VECTOR3 or not pl["pos"].is_finite() \
			or typeof(pl.get("yaw")) != TYPE_FLOAT or not is_finite(pl["yaw"]) \
			or typeof(pl.get("pitch")) != TYPE_FLOAT or not is_finite(pl["pitch"]) or typeof(pl.get("fly")) != TYPE_BOOL:
		return "the trainee's place is damaged"
	return ""


## What the app indexes with inside the engine's state (the generic check sees only fields, types and lengths): a
## file whose hash matches but whose contents were changed must not break the session. "" when it fits.
func _engine_contents(fresh, d: Dictionary) -> String:
	if d.get("step_no", 0) < 0:
		return "a negative step"
	if d.has("mstate"):
		for mi in d["mstate"].size():
			if d["mstate"][mi] < 0 or d["mstate"][mi] >= fresh._mc[mi][2].size():
				return "a machine in a state it doesn't have"
	if d.has("astate"):
		for s in d["astate"]:
			if not s in ["normal", "active_unack", "active_ack", "cleared_unack"]:
				return "an alarm in a state that doesn't exist"
	if d.has("shelved"):
		for x in d["shelved"]:
			if x < -1:
				return "a shelf that ends before it began"
	for k in ["first_out", "faults_done", "faults_fixed"]:
		if d.has(k):
			for key in d[k]:
				if typeof(key) != TYPE_STRING or (k == "first_out" and typeof(d[k][key]) != TYPE_STRING):
					return "a damaged %s" % k
	if d.has("queue"):
		var sizes := {"op": 5, "ack": 2, "shelve": 3, "unshelve": 2, "fault": 2, "repair": 2, "permit": 4, "lock": 4,
				"unlock": 4}
		for q in d["queue"]:
			if typeof(q) != TYPE_ARRAY or q.is_empty() or not sizes.has(q[0]) or q.size() != sizes[q[0]] \
					or (q[0] in ["fault", "repair"] and typeof(q[1]) != TYPE_STRING):
				return "a damaged input"
	# permits and isolations (PLANT3D §15): states, holders and locks the engine indexes with, and that agree
	if d.has("pstate"):
		for s in d["pstate"]:
			if s < 0 or s > 10:
				return "a permit in a state that doesn't exist"
	if d.has("holder"):
		for h in d["holder"]:
			if h < -1 or h >= fresh._wk.size():
				return "an isolation held by a work that doesn't exist"
	if d.has("lockbits"):
		var want := {}
		for k in fresh._iso.size():
			for pi in fresh._iso[k][1].size():
				var b: int = d["lockbits"][fresh._iso[k][4] + pi]
				if b != 0 and b != 1:
					return "a damaged lock"
				if b == 1:
					want[fresh._iso[k][1][pi][0]] = want.get(fresh._iso[k][1][pi][0], 0) + 1
		if d.has("code_locks") and d["code_locks"] != want:
			return "locks that don't agree"
		# a locked point belongs to a held isolation, and the values conditions read agree with the locks (§15.1)
		for k in fresh._iso.size():
			var c := 0
			for pi in fresh._iso[k][1].size():
				c += int(d["lockbits"][fresh._iso[k][4] + pi])
			if c > 0 and d.has("holder") and d["holder"][k] == -1:
				return "locks that no permit holds"
			if d.has("cur") and (d["cur"][fresh._iso[k][2]] != float(c)
					or d["cur"][fresh._iso[k][3]] != (1.0 if c == fresh._iso[k][1].size() else 0.0)):
				return "locks that don't agree"
	if d.has("pstate") and d.has("cur"):
		for wi in fresh._wk.size():
			if d["cur"][fresh._wk[wi][2]] != float(d["pstate"][wi]):
				return "a permit whose value doesn't agree"
	for k in ["ptw", "acceptor", "lockers"]:
		if d.has(k):
			for key in d[k]:
				if (k != "lockers" and typeof(key) != TYPE_STRING) or (k == "lockers" and typeof(key) != TYPE_VECTOR2I) \
						or (k == "ptw" and typeof(d[k][key]) != TYPE_STRING):
					return "a damaged %s" % k
	if d.get("ptw_count", 0) < 0:
		return "a damaged permit count"
	for k in ["inputs", "events"]:
		if d.has(k):
			for x in d[k]:
				if typeof(x) != TYPE_ARRAY or x.size() < 2 or typeof(x[0]) != TYPE_INT or typeof(x[1]) != TYPE_STRING:
					return "a damaged %s" % k
	return ""


static func _tracker_contents(t: Dictionary, e: Dictionary) -> bool:
	var nev: int = e.get("events", []).size()
	var nin: int = e.get("inputs", []).size()
	if t.get("_seen", 0) < 0 or t.get("_seen", 0) > nev or t.get("_in_seen", 0) < 0 or t.get("_in_seen", 0) > nin \
			or t.get("_begin_inputs", 0) < 0 or t.get("_begin_inputs", 0) > nin:
		return false
	for x in t.get("log", []):
		if typeof(x) != TYPE_ARRAY or x.size() != 2 or typeof(x[0]) != TYPE_STRING or typeof(x[1]) != TYPE_INT:
			return false
	for x in t.get("deviations", []):
		if typeof(x) != TYPE_ARRAY or x.size() != 2 or typeof(x[0]) != TYPE_INT or typeof(x[1]) != TYPE_STRING:
			return false
	for key in t.get("did", {}):
		if typeof(key) != TYPE_STRING:
			return false
	return true


static func _ui_contents(u: Dictionary) -> bool:
	for key in u["results"]:
		var r = u["results"][key]
		if typeof(key) != TYPE_STRING or typeof(r) != TYPE_DICTIONARY or typeof(r.get("state")) != TYPE_STRING \
				or typeof(r.get("text")) != TYPE_STRING:
			return false
	for x in u["pending"]:
		if typeof(x) != TYPE_ARRAY or x.size() != 3 or typeof(x[0]) != TYPE_STRING or typeof(x[1]) != TYPE_DICTIONARY \
				or typeof(x[1].get("kks")) != TYPE_STRING or typeof(x[1].get("do")) != TYPE_STRING or typeof(x[2]) != TYPE_INT:
			return false
	return true


## Puts the run back (a payload check() passed): the plant, its clock, the procedure and its progress, the panels'
## record of operations and alarms, and the trainee where they stood, looking where they looked.
func restore(p: Dictionary) -> void:
	ui.restart(p["scenario"], true)
	var e = ui.clock.engine
	RunSave.apply(e, p["engine"])
	ui.sounds.reset_edges()
	ui.alarms.on_events(e.events, 0)
	ui._ev_seen = e.events.size()
	ui.results = p["ui"]["results"]
	ui._pending = p["ui"]["pending"]
	ui.permits.waiting_from(e)
	if p["procedure"] != "":
		ui.start_procedure(p["procedure"], null, false)
		RunSave.apply(ui.tracker, p["tracker"])
		ui.procedure.on_step_changed()
		var at: Array = ui.tracker.current().get("at", [])
		if not at.is_empty() and ui.index.has(at[0]):
			ui.show_me(at[0])
		else:
			ui.pointer.clear()
	var run: Dictionary = p["run"]
	if run.is_empty():
		ui.run_tracker = null
	elif run["same"]:
		ui.run_tracker = ui.tracker
	else:
		var rt = Tracker.new()
		rt.proc = ui.model.procedures[run["procedure"]]
		rt.steps = rt.proc.get("steps", [])
		RunSave.apply(rt, run["tracker"])
		ui.run_tracker = rt
	var c: Dictionary = p["clock"]
	ui.clock.ff_want = c["ff_want"]
	ui.clock.pause_on_hold = c["pause_on_hold"]
	ui.clock.set_speed(c["speed"])
	var pl = ui.player
	var pd: Dictionary = p["player"]
	if ui._flight:
		ui._flight.kill()
	if ui.main.map.active:
		ui.main.toggle_map()
	pl.scripted = false
	pl.set_mode(pl.Mode.FLY)
	pl.global_position = pd["pos"]
	pl.halt()
	pl.set_heading(pd["yaw"], pd["pitch"])
	if not pd["fly"]:
		pl.set_mode(pl.Mode.WALK)
	_sig = _signature()


# ------------------------------------------------------------------ the offer at start

func _show_offer(p: Dictionary, why: String) -> void:
	offer_panel = PanelContainer.new()
	offer_panel.name = "continue"
	offer_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	offer_panel.add_child(v)
	var row := HBoxContainer.new()
	if why == "":
		v.add_child(W.label("Continue the saved run?", 26))
		var sc: Dictionary = ui.model.scenarios[p["scenario"]]
		var lines := ["%s, at %s of plant time." % [sc.get("title", p["scenario"]), W.model_time(p["engine"]["step_no"])]]
		if p["procedure"] != "":
			var pr: Dictionary = ui.model.procedures[p["procedure"]]
			var i: int = p["tracker"]["index"]
			lines.append("%s: %s." % [pr.get("title", p["procedure"]),
					("step %d of %d" % [i + 1, pr["steps"].size()]) if i >= 0 else "finished"])
		lines.append("Saved %s." % Time.get_datetime_string_from_unix_time(p["saved_unix"] + _tz_offset(), true))
		v.add_child(W.label("\n".join(lines), 20, W.DIM))
		v.add_child(row)
		var go := W.button("Continue", func(): _choose(p), 200)
		row.add_child(go)
		row.add_child(W.button("New run", func(): _choose({}), 200))
		if ui.wants_focus():
			go.grab_focus.call_deferred()
	else:
		last_error = why
		v.add_child(W.label("The saved run can't be continued", 26))
		v.add_child(W.label("Because %s. A new run starts; the saved one will be replaced." % why, 20, W.DIM))
		v.add_child(row)
		var nb := W.button("New run", func(): _choose({}), 200)
		row.add_child(nb)
		if ui.wants_focus():
			nb.grab_focus.call_deferred()
	_offer_layer = CanvasLayer.new()
	_offer_layer.layer = 10
	add_child(_offer_layer)
	var block := ColorRect.new()
	block.color = Color(0, 0, 0, 0.45)
	block.set_anchors_preset(Control.PRESET_FULL_RECT)
	block.mouse_filter = Control.MOUSE_FILTER_STOP
	block.theme = ui.root.theme
	_offer_layer.add_child(block)
	block.add_child(offer_panel)
	ui.player.scripted = true           # no walking or looking, and the app's keys wait (app/main.gd, ui/plant_ui.gd)
	ui.player.drive = Vector2.ZERO
	_place_offer()
	ui.root.get_viewport().size_changed.connect(_place_offer)
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _place_offer() -> void:
	if offer_panel == null:
		return
	var vs: Vector2 = ui.root.get_viewport_rect().size
	var w := minf(640.0 * W.scale, vs.x - 32.0)
	offer_panel.size = Vector2(w, 0)
	offer_panel.position = Vector2((vs.x - w) * 0.5, vs.y * 0.3)


static func _tz_offset() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60


func _choose(p: Dictionary) -> void:
	if offer_panel != null:
		ui.root.get_viewport().size_changed.disconnect(_place_offer)
		_offer_layer.queue_free()
		_offer_layer = null
		offer_panel = null
		ui.player.scripted = false
	if p.is_empty():
		RunSave.keep_previous(path)             # the run given up stays as run.save.prev until the next one
		ui.restart(ui.clock.scenario, true)     # afresh (the plant waited at step 0: this is the same start)
		ui.clock.set_speed(SimClock.Speed.NORMAL)
	else:
		restore(p)
		ui.toast("The run continues where it was saved.")
	armed = true
	save_now()


# ------------------------------------------------------------------ saving

func _signature() -> String:
	var e = ui.clock.engine
	var tr = ui.tracker
	var pl = ui.player
	var pos: Vector3 = pl.global_position.snapped(Vector3(0.25, 0.25, 0.25))
	return "%s|%s|%d|%d|%d|%s|%d|%s|%s|%.2f|%.2f|%s" % [ui.clock.scenario, str(tr.proc.get("id", "")) if tr != null else "", e.step_no, e.inputs.size(), ui.clock.speed, str(ui.clock.ff_want), int(ui.clock.pause_on_hold),
			str([tr.index, tr.did.size(), tr.log.size()]) if tr != null else "-", str(pos), pl.rotation.y,
			pl.pivot.rotation.x, str(ui.results.size())]


func _process(delta: float) -> void:
	_lt += delta
	if _lt >= INTERVAL:
		_lt = 0.0
		_claim()                        # renewed (the offer too): another window sees this one is alive
	if not armed or ui.clock == null or ui.clock.engine == null:
		return
	if _thread != null and not _thread.is_alive():
		_finish_thread()
	_t += delta
	if _t < INTERVAL:
		return
	_t = 0.0
	var sig := _signature()
	if sig == _sig or _thread != null:
		return
	_sig = sig
	var t0 := Time.get_ticks_usec()
	var p := payload()
	capture_us = Time.get_ticks_usec() - t0
	_thread = Thread.new()
	_thread.start(_write.bind(p))


func _write(p: Dictionary) -> int:
	return RunSave.write(path, RunSave.encode(p))


func _finish_thread() -> void:
	var err: int = _thread.wait_to_finish()
	_thread = null
	if err == OK:
		saves += 1
	else:
		_sig = ""                       # tried again at the next interval
		push_warning("autosave: the run was not saved (error %d)" % err)


## Saves now, on this thread (going to the background, closing; tests). False when it could not be written.
func save_now() -> bool:
	if not armed or ui.clock == null or ui.clock.engine == null:
		return false
	if _thread != null:
		_finish_thread()
	_sig = _signature()
	_t = 0.0
	var err := RunSave.write(path, RunSave.encode(payload()))
	if err != OK:
		_sig = ""
		push_warning("autosave: the run was not saved (error %d)" % err)
		return false
	saves += 1
	return true


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST, \
				NOTIFICATION_WM_GO_BACK_REQUEST:
			save_now()


func _exit_tree() -> void:
	if _thread != null:
		_finish_thread()
	_release()
