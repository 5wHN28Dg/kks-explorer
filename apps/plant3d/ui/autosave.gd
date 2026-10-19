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
var _sig := ""
var _thread: Thread


func setup(u, content_dir: String, save_path := "") -> void:
	ui = u
	path = save_path if save_path != "" else default_path
	content = RunSave.content_hash(content_dir)


## At start: offers a saved run (the plant waits, paused), or arms the saving at once when there is none.
func begin(offer := true) -> void:
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
	return {
		"app": RunSave.app_version(), "content": content, "scenario": ui.clock.scenario,
		"saved_unix": int(Time.get_unix_time_from_system()),
		"engine": RunSave.capture(e, RunSave.engine_fields(e)),
		"clock": {"speed": ui.clock.speed, "ff_want": ui.clock.ff_want, "pause_on_hold": ui.clock.pause_on_hold},
		"procedure": pid, "tracker": td,
		"ui": {"results": ui.results.duplicate(true), "pending": ui._pending.duplicate(true)},
		"player": {"pos": pl.global_position, "yaw": pl.rotation.y, "pitch": pl.pivot.rotation.x,
				"fly": pl.mode == pl.Mode.FLY},
	}


## Why this payload can't be continued here, or "".
func check(p: Dictionary) -> String:
	if p["app"] != RunSave.app_version():
		return "it was saved by another version of the app (%s)" % (p["app"] if p["app"] != "" else "a development build")
	if p["content"] != content:
		return "the plant's content has changed since"
	if not ui.model.scenarios.has(p["scenario"]):
		return "its scenario is not in this plant"
	var fresh = PlantEngine.new(ui.model, p["scenario"])
	var bad := RunSave.check(fresh, RunSave.engine_fields(fresh), p["engine"])
	if bad != "":
		return "the plant's state does not fit this version: " + bad
	var c: Dictionary = p["clock"]
	if c.size() != 3 or typeof(c.get("speed")) != TYPE_INT or not c["speed"] in [0, 1, 2] \
			or typeof(c.get("ff_want")) != TYPE_FLOAT or not is_finite(c["ff_want"]) \
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
		if p["tracker"]["index"] < -1 or p["tracker"]["index"] >= nsteps:
			return "its procedure's progress is damaged"
	elif not p["tracker"].is_empty():
		return "its procedure's progress is damaged"
	var u: Dictionary = p["ui"]
	if u.size() != 2 or typeof(u.get("results")) != TYPE_DICTIONARY or typeof(u.get("pending")) != TYPE_ARRAY:
		return "its panels' state is damaged"
	var pl: Dictionary = p["player"]
	if pl.size() != 4 or typeof(pl.get("pos")) != TYPE_VECTOR3 or not pl["pos"].is_finite() \
			or typeof(pl.get("yaw")) != TYPE_FLOAT or not is_finite(pl["yaw"]) \
			or typeof(pl.get("pitch")) != TYPE_FLOAT or not is_finite(pl["pitch"]) or typeof(pl.get("fly")) != TYPE_BOOL:
		return "the trainee's place is damaged"
	return ""


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
	if p["procedure"] != "":
		ui.start_procedure(p["procedure"], null, false)
		RunSave.apply(ui.tracker, p["tracker"])
		ui.procedure.on_step_changed()
		var at: Array = ui.tracker.current().get("at", [])
		if not at.is_empty() and ui.index.has(at[0]):
			ui.show_me(at[0])
		else:
			ui.pointer.clear()
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
	pl.velocity = Vector3.ZERO
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
	return "%d|%d|%d|%s|%d|%s|%s|%.2f|%.2f|%s" % [e.step_no, e.inputs.size(), ui.clock.speed, str(ui.clock.ff_want), int(ui.clock.pause_on_hold),
			str([tr.index, tr.did.size(), tr.log.size()]) if tr != null else "-", str(pos), pl.rotation.y,
			pl.pivot.rotation.x, str(ui.results.size())]


func _process(delta: float) -> void:
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
