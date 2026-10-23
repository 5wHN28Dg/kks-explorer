## What a lock would do (docs/PLANT3D.md §15.6, the user's decision of 2026-10-23), from the permit form at vacuum:
## - condenser pressure transmitter 2's lock trips nothing (its vote alone): it is checked and sent with no warning;
## - with it locked, transmitter 3's lock would trip the steam turbine (2 out of 3): the form warns, names the trip and
##   what it moves, the focus on "Don't lock"; nothing is sent until "Lock it anyway";
## - touch ("Don't lock" pressed), gamepad (A on the focused "Don't lock", then A on the lock again) and keyboard (Left
##   to "Lock it anyway", Enter) each answer it; the lock then made trips the steam turbine.
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const Procedure = preload("res://sim/procedure.gd")
const RunSave = preload("res://ui/run_save.gd")

const TX2 := "30MAG10CP002"
const TX3 := "30MAG10CP003"


## The event pressed and released, as a device sends them, into the window (headless Godot has no input device).
static func _push(tree: SceneTree, ev: InputEvent) -> void:
	tree.root.push_input(ev)
	var up: InputEvent = ev.duplicate()
	up.pressed = false
	tree.root.push_input(up)


static func _key(code: Key) -> InputEventKey:
	var k := InputEventKey.new()
	k.pressed = true
	k.physical_keycode = code
	k.keycode = code
	return k


static func _joy(b: JoyButton) -> InputEventJoypadButton:
	var j := InputEventJoypadButton.new()
	j.pressed = true
	j.button_index = b
	return j


static func _focus(ui) -> String:
	var f: Control = ui.get_viewport().gui_get_focus_owner()
	return String(f.name) if f != null else ""


static func _near(ui, code: String) -> void:
	if ui.index.has(code):
		ui.player.global_position = ui.index.center(code) + Vector3(0, 0, 3)


## Opens a work's form and takes its permit to approved.
static func _approved(ui, pm, wid: String) -> Array:
	ui.open_permits(wid)
	for a in ["request", "approve"]:
		pm.refresh()
		var b: Button = pm.body.find_child("do_" + a, true, false)
		if b == null or b.disabled:
			return ["%s: no %s on the form" % [wid, a]]
		b.pressed.emit()
		ui.clock.run_steps(1)
	pm.refresh()
	return []


func run(tree: SceneTree) -> Array:
	var p: Array = []
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null:
		main.free()
		return ["the interaction layer did not start"]
	await tree.process_frame
	# the plant at vacuum, as test_ui_permits
	var r := Procedure.run(ui.model, "cold_start", 3600, null, "cep_mf")
	if r.error != "":
		main.free()
		return ["the cold start stopped: " + r.error]
	var pl: Dictionary = ui.autosave.payload()
	pl["engine"] = RunSave.capture(r.engine, RunSave.engine_fields(r.engine))
	ui.autosave.restore(pl)
	ui.clock.set_speed(App.SimClock.Speed.PAUSED)
	var e = ui.clock.engine
	var pm = ui.permits
	# transmitter 2: nothing to warn about, sent once checked
	p.append_array(_approved(ui, pm, "wo_cond_p2_cal"))
	_near(ui, TX2)
	pm.refresh()
	var lb: Button = pm.body.find_child("lock_0", true, false)
	if lb == null or lb.disabled:
		main.free()
		return p + ["transmitter 2's form offers no lock: %s" % App.texts(pm.body).left(300)]
	lb.pressed.emit()
	pm.refresh()
	var checking: Button = pm.body.find_child("lock_0", true, false)
	if pm.check.is_empty() or checking == null or not checking.text.contains("Checking") or not checking.disabled:
		p.append("while it is checked the lock button does not say so: %s" % (checking.text if checking else "none"))
	if not await App.lock_checked(tree, pm) or not pm.check.is_empty():
		p.append("transmitter 2's lock was not sent at once (it trips nothing): %s" % str(pm.check.get("answer", "")))
	ui.clock.run_steps(2)
	if not e.code_locks.has(TX2):
		p.append("transmitter 2 is not locked")
	# transmitter 3: the lock would trip the steam turbine
	p.append_array(_approved(ui, pm, "wo_cond_p3_cal"))
	_near(ui, TX3)
	pm.refresh()
	var n_in: int = e.inputs.size()
	# touch: the lock pressed, the warning, "Don't lock" pressed: nothing sent
	(pm.body.find_child("lock_0", true, false) as Button).pressed.emit()
	if not await App.lock_checked(tree, pm) or pm.check.get("state", "") != "warn":
		main.free()
		return p + ["transmitter 3's lock brought no warning: %s" % str(pm.check)]
	var a: Dictionary = pm.check["answer"]
	if a.get("trips", []) != ["st_trip_cond_p", "gen3_trip_prot"] or a.get("alarms", []) != ["gt1_runback"]:
		p.append("the warning's answer is %s" % str(a))
	await tree.process_frame
	var warn: Label = pm.body.find_child("warn_0", true, false)
	var st_name: String = ui.info.name_of("30MAA10")
	if warn == null or not warn.text.contains("Condenser pressure high-high") or not warn.text.contains("GT 1 runback") \
			or (st_name != "" and not warn.text.contains(st_name)):
		p.append("the warning does not name the trip, what it moves (%s) and the alarm: %s" % [st_name,
				warn.text if warn else "none"])
	if _focus(ui) != "cancel_lock_0":
		p.append("the warning's focus is on %s, not Don't lock" % _focus(ui))
	(pm.body.find_child("cancel_lock_0", true, false) as Button).pressed.emit()
	if not pm.check.is_empty() or e.inputs.size() != n_in:
		p.append("Don't lock (touch) sent something or left the warning: %s" % str(pm.check))
	await tree.process_frame
	if _focus(ui) != "lock_0":
		p.append("after Don't lock the focus is on %s, not the lock" % _focus(ui))
	# gamepad: A on the lock (focused), the warning, A on Don't lock
	_push(tree, _joy(JOY_BUTTON_A))
	if pm.check.is_empty():
		p.append("the gamepad's A on the focused lock asked nothing")
	elif not await App.lock_checked(tree, pm) or pm.check.get("state", "") != "warn":
		p.append("the gamepad's lock brought no warning")
	await tree.process_frame
	if _focus(ui) != "cancel_lock_0":
		p.append("the gamepad's warning has the focus on %s" % _focus(ui))
	_push(tree, _joy(JOY_BUTTON_A))
	if not pm.check.is_empty() or e.inputs.size() != n_in:
		p.append("the gamepad's A on Don't lock sent something or left the warning")
	await tree.process_frame
	# keyboard: Enter on the lock, the warning, Left to "Lock it anyway", Enter: the lock sent
	_push(tree, _key(KEY_ENTER))
	if not await App.lock_checked(tree, pm) or pm.check.get("state", "") != "warn":
		p.append("Enter on the lock brought no warning")
	await tree.process_frame
	_push(tree, _key(KEY_LEFT))
	if _focus(ui) != "confirm_lock_0":
		p.append("Left from Don't lock went to %s, not Lock it anyway" % _focus(ui))
	_push(tree, _key(KEY_ENTER))
	if not pm.check.is_empty() or e.inputs.size() != n_in + 1 or e.inputs[-1].slice(1) != ["lock", "wo_cond_p3_cal", 0, null]:
		p.append("Lock it anyway did not send the lock: %s" % str(e.inputs.slice(n_in)))
	# the lock made, the steam turbine trips (its trip, as the warning said)
	ui.clock.run_steps(100)
	if not e.code_locks.has(TX3):
		p.append("transmitter 3 is not locked")
	if not e.events.any(func(ev): return ev[1] == "trip" and ev[2] == "st_trip_cond_p"):
		p.append("the steam turbine did not trip after the lock")
	main.free()
	return p
