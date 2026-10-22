## Permits to work and isolations (docs/PLANT3D.md §15, milestone P1), worked from the app as a trainee in free mode:
## - the plant at vacuum (the cold start run in the model alone to its vac_hold step, put into the app as a saved run);
## - CW pump B's whole permit from the permit form, each role in turn: request, approve, both points locked and
##   tagged at the equipment (refused from the control room, offered within reach), issued, accepted, work done (the
##   motor's fault repaired), handed back, the locks removed, closed; the history and the debrief list it all;
## - while it is locked: the pump's start refused (the card says why), its screen cell shows the padlock and the
##   permit's number, its card says LOCKED OUT; after: the pump starts again;
## - CCW pump B locked out on standby: when pump A trips, the auto-start's interlock fires and its write is skipped;
## - condenser pressure transmitter 2 isolated: its reading held, its vote tripped (the trip then 1 out of 2, nothing
##   trips at vacuum), its alarms suppressed while the pressure rises after the CW pumps are lost (the others raise);
## - a run saved with a permit open (isolated, an action waiting) is accepted and put back exactly;
## - keyboard and gamepad: T opens the form with the focus in it, the card and the procedures panel reach it.
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const Procedure = preload("res://sim/procedure.gd")
const RunSave = preload("res://ui/run_save.gd")
const Debrief = preload("res://ui/debrief.gd")

const PUMP := "30PAC10AP002"
const VALVE := "30PAC10AA102"
const WORK := "wo_cw_b_motor"


static func _press(panel, name: String) -> String:
	var b = panel.body.find_child(name, true, false)
	if b == null or not (b is Button):
		return "no button %s on the form (%s)" % [name, App.texts(panel.body).left(400)]
	if b.disabled:
		return "the form's %s is disabled" % name
	(b as Button).pressed.emit()
	return ""


static func _button(panel, name: String) -> Button:
	return panel.body.find_child(name, true, false) as Button


func run(tree: SceneTree) -> Array:
	var p: Array = []
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null:
		main.free()
		return ["the interaction layer did not start"]
	await tree.process_frame
	# the plant at vacuum: the cold start to its vac_hold step, in the model alone, then put into the app
	var r := Procedure.run(ui.model, "cold_start", 3600, null, "cep_mf")
	if r.error != "":
		main.free()
		return ["the cold start stopped: " + r.error]
	var pl: Dictionary = ui.autosave.payload()
	pl["engine"] = RunSave.capture(r.engine, RunSave.engine_fields(r.engine))
	var why: String = ui.autosave.check(pl)
	if why != "":
		main.free()
		return ["the plant at vacuum was refused as a run: " + why]
	ui.autosave.restore(pl)
	ui.clock.set_speed(App.SimClock.Speed.PAUSED)
	var e = ui.clock.engine
	if e.truth("cw_b_run") or not e.truth("st_cond_trip_clear") or e.v("cond_p") > 12.0:
		p.append("the plant is not at vacuum with CW pump B stopped (cond_p %.1f)" % e.v("cond_p"))
	# keyboard: T opens the permits with the focus in the list
	ui.go_control_room(false)
	var t := InputEventAction.new()
	t.action = "permits"
	t.pressed = true
	ui._unhandled_input(t)
	var pm = ui.permits
	if not pm.visible:
		p.append("T did not open the permits")
	await tree.process_frame
	var fo: Control = ui.get_viewport().gui_get_focus_owner()
	if fo == null or not pm.is_ancestor_of(fo):
		p.append("the permits took no focus (keyboard and gamepad reach nothing)")
	var err := _press(pm, "open_" + WORK)
	if err != "":
		main.free()
		return p + [err]
	pm.refresh()
	# the form: request and approve, each as its role
	var req := _button(pm, "do_request")
	if req == null or not req.text.contains("as the maintenance supervisor"):
		p.append("the form's request names no role: %s" % (req.text if req else "none"))
	for a in ["request", "approve"]:
		err = _press(pm, "do_" + a)
		if err != "":
			p.append(err)
		ui.clock.run_steps(1)
		pm.refresh()
	if e.pstate[e.m.work_ix[WORK]] != 2 or e.ptw.get(WORK, "") != "PTW-0001":
		p.append("after request and approve the permit is %d, %s" % [e.pstate[e.m.work_ix[WORK]], e.ptw.get(WORK, "")])
	if not App.texts(pm).contains("PTW-0001") or not App.texts(pm).contains("Permit: Approved"):
		p.append("the form does not show the approved permit PTW-0001")
	# locks at the equipment only: from the control room they are not offered
	var lk := _button(pm, "lock_0")
	if lk == null or not lk.disabled or not App.texts(pm).contains("At the equipment only"):
		p.append("the pump's lock is offered from the control room")
	for k in 2:
		var code: String = [PUMP, VALVE][k]
		ui.player.global_position = ui.index.center(code) + Vector3(0, 0, 3)
		pm.refresh()
		err = _press(pm, "lock_%d" % k)
		if err != "":
			p.append("beside %s: %s" % [code, err])
		ui.clock.run_steps(1)
		pm.refresh()
	if e.pstate[e.m.work_ix[WORK]] != 3 or e.v("iso_cw_b_complete") != 1.0:
		p.append("with both points locked the permit is %d (complete %s)" % [e.pstate[e.m.work_ix[WORK]],
				e.v("iso_cw_b_complete")])
	# locked: the start refused (the card says why), the card and the screen show the lock
	ui.go_control_room(false)
	ui.open_card(PUMP)
	if not App.texts(ui.card).contains("LOCKED OUT PTW-0001"):
		p.append("the pump's card does not say it is locked out: %s" % App.texts(ui.card).left(300))
	var row := App.op_row(ui.card, PUMP, "start")
	if row.is_empty():
		p.append("the pump's card has no start")
	else:
		(row[1] as Button).pressed.emit()
		ui.clock.run_steps(1)
		var res: Dictionary = ui.op_result(row[0])
		if res.get("state", "") != "refused" or not String(res.get("text", "")).contains("Locked out for work"):
			p.append("the locked pump's start came back %s" % str(res))
		if e.truth("cw_b_cmd"):
			p.append("the locked pump was started")
	ui.close_card()
	ui.open_screens(ui.screens.screens[ui.screens.screen_of[PUMP][0]]["id"])
	for k in 30:
		await tree.process_frame
	if ui.mimic.locks_drawn.get(PUMP, "") != "LOCKED OUT PTW-0001":
		p.append("the screen drew the locked pump as %s" % ui.mimic.locks_drawn.get(PUMP, "nothing"))
	ui.close_screens()
	# the work: issued, accepted, the motor's fault (pressed before) repaired by the work's done, handed back
	ui.fault("cw_b_motor")              # a fault while locked: applied, its write skipped (the pump is locked)
	ui.clock.run_steps(1)
	ui.open_permits(WORK)
	for a in ["issue", "accept", "done", "return"]:
		err = _press(pm, "do_" + a)
		if err != "":
			p.append(err)
		ui.clock.run_steps(1)
		pm.refresh()
	if e.pstate[e.m.work_ix[WORK]] != 7:
		p.append("after issue, accept, done and return the permit is %d" % e.pstate[e.m.work_ix[WORK]])
	# the locks off, at the equipment; the permit de-isolated by itself, then closed
	for k in 2:
		var code: String = [PUMP, VALVE][k]
		ui.player.global_position = ui.index.center(code) + Vector3(0, 0, 3)
		pm.refresh()
		err = _press(pm, "unlock_%d" % k)
		if err != "":
			p.append("beside %s: %s" % [code, err])
		ui.clock.run_steps(1)
		pm.refresh()
	err = _press(pm, "do_close")
	if err != "":
		p.append(err)
	ui.clock.run_steps(1)
	pm.refresh()
	if e.pstate[e.m.work_ix[WORK]] != 9 or e.code_locks.has(PUMP):
		p.append("the permit did not close with its locks off (%d)" % e.pstate[e.m.work_ix[WORK]])
	var hist: String = App.texts(pm)
	for want in ["requested (PTW-0001)", "approved", "Locked and tagged: 30PAC10AP002", "issued", "accepted",
			"work done", "handed back", "Lock removed: 30PAC10AA102", "de-isolated", "closed"]:
		if not hist.contains(want):
			p.append("the permit's history does not say %s" % want)
	# the pump starts again: its valve to the start position, then the start
	ui.go_control_room(false)
	ui.do_op({"kks": VALVE, "do": "set"}, 0.15)
	ui.clock.run_steps(1)
	if not App.run_until(ui, "cw_b_vstart", 2000):
		p.append("the valve did not come to its start position")
	ui.do_op({"kks": PUMP, "do": "start"}, null)
	ui.clock.run_steps(5)
	if not e.truth("cw_b_run"):
		p.append("after the permit closed the pump does not start (the fault repaired? %s)" % e.v("cw_b_fault"))
	# CCW pump B locked out on standby: pump A trips, the auto-start's write is skipped
	ui.open_permits("wo_ccw_b_motor")
	for a in ["request", "approve"]:
		_press(pm, "do_" + a)
		ui.clock.run_steps(1)
		pm.refresh()
	ui.player.global_position = ui.index.center("00PGC10AP002") + Vector3(0, 0, 3)
	pm.refresh()
	err = _press(pm, "lock_0")
	if err != "":
		p.append("CCW pump B: " + err)
	ui.clock.run_steps(1)
	ui.fault("ccw_a_motor")
	ui.clock.run_steps(30)
	if not e.events.any(func(ev): return ev[1] == "interlock" and ev[2] == "ccw_b_auto"):
		p.append("CCW pump A's trip did not fire the standby's auto-start")
	if e.truth("ccw_b_cmd"):
		p.append("the auto-start started the locked-out CCW pump B")
	# condenser pressure transmitter 2 isolated: held, voting tripped, its alarms suppressed
	ui.open_permits("wo_cond_p2_cal")
	for a in ["request", "approve"]:
		_press(pm, "do_" + a)
		ui.clock.run_steps(1)
		pm.refresh()
	ui.player.global_position = ui.index.center("30MAG10CP002") + Vector3(0, 0, 3) if ui.index.has("30MAG10CP002") \
			else ui.player.global_position
	pm.refresh()
	err = _press(pm, "lock_0")
	if err != "":
		p.append("transmitter 2: " + err)
	ui.clock.run_steps(2)
	if e.v("cond_p2_vote") != 1.0 or e.v("cond_hh_v") != 1.0 or e.truth("st_trip_cond_p_latched"):
		p.append("the isolated transmitter does not vote tripped alone (vote %s, votes %s)" % [e.v("cond_p2_vote"),
				e.v("cond_hh_v")])
	var held: float = e.v("cond_p2")
	ui.fault("cw_ab_fail")
	if not App.run_until(ui, "cond_p1_h", 3000):
		p.append("the condenser pressure did not rise after the CW pumps were lost")
	ui.clock.run_steps(100)
	var k2: int = e._al_ix["cond_p2_h"]
	var k1: int = e._al_ix["cond_p1_h"]
	if e.astate[k1] == "normal" or e.astate[k2] != "normal" or not e.alarm_suppressed(k2):
		p.append("with transmitter 2 isolated: alarm 1 %s, alarm 2 %s (suppressed %s)" % [e.astate[k1], e.astate[k2],
				e.alarm_suppressed(k2)])
	if e.v("cond_p2") != held or e.v("cond_p2_tx") <= held:
		p.append("the isolated transmitter's reading moved (%s, held %s, process %s)" % [e.v("cond_p2"), held,
				e.v("cond_p2_tx")])
	ui.open_screens(ui.screens.screens[ui.screens.screen_of["30MAG10CP002"][0]]["id"])
	for k in 30:
		await tree.process_frame
	if not String(ui.mimic.locks_drawn.get("30MAG10CP002", "")).begins_with("ISOLATED PTW-"):
		p.append("the screen drew the isolated transmitter as %s" % ui.mimic.locks_drawn.get("30MAG10CP002", "nothing"))
	ui.close_screens()
	# a run saved with a permit open (CCW pump B isolated, its issue waiting) is accepted and put back as it was
	ui.open_permits("wo_ccw_b_motor")
	err = _press(pm, "do_issue")
	if err != "":
		p.append(err)
	var saved: Dictionary = ui.autosave.payload()
	why = ui.autosave.check(saved)
	if why != "":
		p.append("a run saved with a permit open was refused: %s" % why)
	var dec: Dictionary = RunSave.decode(RunSave.encode(saved))
	if not dec.get("ok", false):
		p.append("the saved run did not decode")
	else:
		var want := [e.pstate.duplicate(), e.lockbits.duplicate(), e.ptw.duplicate(), e.code_locks.duplicate(),
				e.holder.duplicate(), e.queue.duplicate(true)]
		ui.restart("cold_iron", true)
		ui.autosave.restore(dec["payload"])
		var e2 = ui.clock.engine
		var got := [e2.pstate, e2.lockbits, e2.ptw, e2.code_locks, e2.holder, e2.queue]
		if str(got) != str(want):
			p.append("the restored permits differ: %s, not %s" % [str(got).left(300), str(want).left(300)])
		ui.clock.run_steps(1)
		if e2.pstate[e2.m.work_ix["wo_ccw_b_motor"]] != 4:
			p.append("the issue waiting across the save did not take effect (%d)" % e2.pstate[e2.m.work_ix["wo_ccw_b_motor"]])
		# a tampered save whose locks don't agree is refused
		var bad: Dictionary = dec["payload"].duplicate(true)
		bad["engine"]["code_locks"] = {}
		if ui.autosave.check(bad) == "":
			p.append("a save whose locks don't agree was accepted")
		e = e2
	# the debrief lists the permits and the locks
	var d: Dictionary = Debrief.collect(e, ui.info, null)
	var texts: Array = d.entries.map(func(x): return x.text)
	for want in ["Permit CW pump B motor: bearing replacement: requested (PTW-0001)", "Locked and tagged: 30PAC10AP002",
			"Lock removed: 30PAC10AP002", "Permit CW pump B motor: bearing replacement: closed"]:
		if not texts.any(func(x): return String(x).contains(want)):
			p.append("the debrief does not list %s" % want)
	if not "\n".join(Debrief.summary_lines(d)).contains("Permits to work: 3"):
		p.append("the debrief's summary does not count the permits: %s" % "\n".join(Debrief.summary_lines(d)))
	# gamepad: the card and the procedures panel reach the form
	ui.open_card(PUMP)
	var cb: Button = ui.card.body.find_child("permit_" + WORK, true, false)
	if cb == null or cb.focus_mode != Control.FOCUS_ALL:
		p.append("the pump's card has no focusable permit button")
	else:
		cb.pressed.emit()
		if not pm.visible or pm.work != WORK:
			p.append("the card's permit button did not open the form")
	ui.close_permits()
	ui.toggle_procedure()
	var pb: Button = ui.procedure.body.find_child("permits", true, false)
	if pb == null:
		p.append("the procedures panel has no way to the permits")
	main.free()
	return p
