## Maintenance, HSE and contractors in the app (docs/PLANT3D.md §17.11, milestone S2), as a trainee plays them:
## - as an I&C technician: PPE on at the locker for the toolbox talk, then the week's calibration of condenser pressure
##   transmitter 2 (a drift the trainer set): its point locked and tagged by the trainee from the permit form, the
##   job given by the maintenance supervisor, the permit accepted at the transmitter, the calibration worked, done and
##   handed back (the drift put right by the work), the lock removed by its owner, the permit closed by the shift
##   supervisor;
## - as an I&C technician again: a corrective job, CW pump B's discharge valve limit switch, under a permit with its
##   isolation (the breaker and the valve locked by the NPC electrician and field operator): the repair made from the
##   card under the accepted permit, the work's done then repairing nothing;
## - as an HSE officer: the safety walk into the CW pump house, a contractor's shortcut there seen (the stop task given
##   to the trainee), "Take me to them" and "Stop the work": the contractor's task abandoned and put right; the
##   debrief's Safety tab lists it;
## - as a control room operator: an NPC calibration that changes the plant: transmitter 2 isolated on the screens
##   (a padlock and the permit's number, the reading held) and, after the work, reading in line with its partners;
## - a run with acts and PPE saved and put back goes on bit for bit (ui/run_save.gd).
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const SimClock = preload("res://ui/sim_clock.gd")
const RunSave = preload("res://ui/run_save.gd")
const PlantEngine = preload("res://sim/engine.gd")

const CAL := "wo_cond_p2_cal"
const PT2 := "30MAG10CP002"
const LS := "wo_cw_b_ls"
const VALVE_B := "30PAC10AA102"

var _pressed := {}              # a permit form's button pressed for a task step: the step it was pressed at


func run(tree: SceneTree) -> Array:
	var p: Array = []
	p += await _ic_calibration(tree)
	p += await _ic_corrective(tree)
	p += await _hse_stop(tree)
	p += await _operator_sees(tree)
	return p


## The shift_cold scenario from a later clock time, so that the day workers are listed as coming on (a copy).
static func _scenario(ui, sid: String, time: String, extra := {}) -> void:
	var sc: Dictionary = ui.model.scenarios["shift_cold"].duplicate(true)
	sc["id"] = sid
	sc["start"] = {"day": 1, "time": time}
	for k in extra:
		sc["staff"][k] = extra[k]
	ui.model.scenarios[sid] = sc


static func _take(tree: SceneTree, ui, sid: String, label: String) -> String:
	ui.start_shift(sid)
	await tree.process_frame
	var b := App.find_button(ui.crew, label)
	if b == null:
		return "no %s in the Crew panel: %s" % [label, App.texts(ui.crew).left(600)]
	b.pressed.emit()
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	return ""


static func _press(pm, name: String) -> String:
	pm._sig = ""
	pm.refresh()
	var b = pm.body.find_child(name, true, false)
	if b == null or not (b is Button):
		return "no button %s on the form (%s)" % [name, App.texts(pm.body).left(400)]
	if b.disabled:
		return "the form's %s is disabled (%s)" % [name, App.texts(pm.body).left(400)]
	(b as Button).pressed.emit()
	return ""


## Plays the trainee's current step as a trainee would, from the Crew panel and the permit form (true when something
## was done). The walker is put at a place by "Take me there" (the walk itself is not what is tested here).
func _play(tree: SceneTree, ui, log: Array) -> bool:
	var e = ui.clock.engine
	var sm = e._sm
	var pi: int = e.st_trainee
	if not ui.crew.visible:
		ui.open_crew()
	if e.st_unacked > 0:
		var seen := App.find_button(ui.crew, "Seen")
		if seen:
			seen.pressed.emit()
	var cur = e.sp_cur[pi]
	if cur == null:
		return false
	ui.crew._sig = ""
	ui.crew.refresh()
	var s: Dictionary = sm.tasks[cur["task"]]["steps"][cur["step"]]
	if s.has("go") or s.has("meet"):
		var dest = cur["st"].get("dest", cur["st"].get("place"))
		if dest != null and e.st_t_at != dest:
			var b := App.find_button(ui.crew, "Take me there")
			if b == null:
				return false
			b.pressed.emit()
			ui._place_tick()
			return true
	elif s.has("work"):
		# a work step counts only where it started: back there after a call away (the Crew panel's own button)
		var at = cur["st"].get("place")
		if at != null and e.st_t_at != at:
			var b := App.find_button(ui.crew, "Take me there")
			if b == null:
				log.append("a work step away from its place offers no way back: %s" % App.texts(ui.crew).left(300))
				return false
			b.pressed.emit()
			ui._place_tick()
			return true
	elif s.has("ppe"):
		var b := App.find_button(ui.crew, "Put it on")
		if b == null:
			b = App.find_button(ui.crew, "Take me to a locker")
			if b == null:
				log.append("a ppe step offers neither a locker nor its PPE: %s" % App.texts(ui.crew).left(300))
				return false
			b.pressed.emit()
			ui._place_tick()
			return true
		b.pressed.emit()
		return true
	elif s.has("say"):
		var b := App.find_button(ui.crew, "Send")
		if b:
			b.pressed.emit()
		return true
	elif s.has("choose"):
		e.pick(0)
		return true
	elif s.has("stop"):
		var b := App.find_button(ui.crew, "Stop the work")
		if b == null:
			b = App.find_button(ui.crew, "Take me to them")
			if b == null:
				return false
			b.pressed.emit()
			ui._place_tick()
			return true
		b.pressed.emit()
		return true
	elif s.has("permit") or s.has("lock") or s.has("unlock"):
		var k := "permit" if s.has("permit") else ("lock" if s.has("lock") else "unlock")
		var key := "%d/%d/%s" % [cur["order"], cur["step"], k]
		if _pressed.get(key, -1000) > e.step_no - 50:
			return false            # pressed already: its outcome comes in the next steps
		var w = cur["work"] if s[k]["work"] == "$" else s[k]["work"]
		var pt: int = s[k]["point"] if k != "permit" and typeof(s[k]["point"]) != TYPE_STRING else 0
		if k != "permit":
			# at the point's equipment first (a lock is made within reach of it, PLANT3D §15.6)
			var iso: Dictionary = e.m.isolations[e.m.isolation_ix[e.m.works[e.m.work_ix[w]]["isolation"]]]
			var wp: int = sm.work_at.get(iso["points"][pt]["kks"], -1)
			if wp != -1 and e.st_t_at != wp:
				ui.go_to_place(wp)
				ui._place_tick()
				return true
		ui.open_permits(w)
		var pm = ui.permits
		_pressed[key] = e.step_no
		var err := _press(pm, ("do_" + s[k]["action"]) if k == "permit" else ("%s_%d" % [k, pt]))
		if err != "":
			log.append(err)
			ui.close_permits()
			return false
		if k == "lock":
			await App.lock_checked(tree, pm)
			if not pm.check.is_empty() and pm.check["state"] == "warn":
				_press(pm, "confirm_lock_%d" % pt)
		ui.close_permits()
		return true
	return false


## Runs the clock and plays the trainee until `done` is true or `limit` rounds of 10 steps pass.
func _steps(tree: SceneTree, ui, done: Callable, limit: int, log: Array) -> bool:
	for i in limit:
		if done.call():
			return true
		await _play(tree, ui, log)
		ui.clock.run_steps(10)
		if i % 8 == 0:
			await tree.process_frame       # (the panels' old rows are freed at the frame's end)
	return done.call()


static func _closed(e, wid: String) -> bool:
	return e.pstate[e.m.work_ix[wid]] == 9


static func _has_ev(e, want: Array) -> bool:
	for ev in e.events:
		var ok: bool = ev.size() > want.size()
		for i in want.size():
			if ok and want[i] != null and ev[1 + i] != want[i]:
				ok = false
		if ok:
			return true
	return false


func _ic_calibration(tree: SceneTree) -> Array:
	var p: Array = []
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null or not ui.model.scenarios.has("shift_cold"):
		main.free()
		return ["the app or its scenario with the crews (shift_cold) did not start"]
	ui.player.set_physics_process(false)     # put at places, it stays there (not falling while the clock runs)
	# the trainee is the only I&C technician on site, so the job comes to them whatever they are doing when the
	# supervisor gives it (with the others there it goes to whoever is free: ic1 is still at the lock then)
	_scenario(ui, "test_ic", "06:30", {"absent": ["ic2", "ic3", "ic4"]})
	var why: String = await _take(tree, ui, "test_ic", "Play I&C technician (coming on shift)")
	if why != "":
		main.free()
		return [why]
	var e = ui.clock.engine
	ui.fault("cond_p2_drift")
	ui.clock.run_steps(2)                  # the fault is set in its step; the transmitter reads it in the next
	var drifted: float = e.v("cond_p2") - e.v("cond_p3")
	var log := []
	var done := func(): return _closed(e, CAL)
	if not await _steps(tree, ui, done, 4000, log):
		var cur = e.sp_cur[e.st_trainee]
		var msg := "the calibration's permit was not closed (now %s, state %d, the task %s step %s)" % [
				ui.clock_text(), e.pstate[e.m.work_ix[CAL]], str(cur["task"]) if cur else "none",
				str(cur["step"]) if cur else ""]
		main.free()
		return p + log.slice(0, 3) + [msg]
	p += log.slice(0, 3)
	for want in [["ppe", "helmet", 1], ["lock", CAL, 0, "ic1", "done"], ["permit", CAL, "accept", "ic1", "done"],
			["permit", CAL, "done", "ic1", "done"], ["permit", CAL, "return", "ic1", "done"],
			["unlock", CAL, 0, "ic1", "done"], ["repair", "cond_p2_drift"]]:
		if want[0] == "ppe":
			if not e.inputs.any(func(x): return x[1] == "ppe" and x[2] == "helmet" and x[3] == 1):
				p.append("the trainee's PPE was not put on at the locker")
		elif not _has_ev(e, want):
			p.append("no event like %s" % str(want))
	var who_assigned := ""
	for ev in e.events:
		if ev[1] == "call" and ev[4] == "job_cond_p2_cal":
			who_assigned = ev[2]
	if not who_assigned.begins_with("ms_"):
		p.append("the job was not given by a maintenance supervisor: %s" % who_assigned)
	var now: float = e.v("cond_p2") - e.v("cond_p3")
	if absf(drifted - 1.7) > 0.05 or absf(now - 0.2) > 0.05:
		p.append("transmitter 2 against 3: %.2f with the drift, %.2f after the calibration (expected 1.7, 0.2)" % [drifted,
				now])
	if e.v("cond_p2_drift") != 0.0:
		p.append("the drift was not put right")
	# the debrief's own tab: the trainee's tasks
	ui.open_debrief()
	ui.debrief._tab("role")
	if not App.texts(ui.debrief).contains("Your task done"):
		p.append("the debrief's Your tasks tab lists no task done: %s" % App.texts(ui.debrief).left(300))
	ui.close_debrief()
	main.free()
	return p


func _ic_corrective(tree: SceneTree) -> Array:
	var p: Array = []
	var main := App.start(tree)
	var ui = main.ui
	ui.player.set_physics_process(false)
	_scenario(ui, "test_ic2", "06:30")
	var why: String = await _take(tree, ui, "test_ic2", "Play I&C technician (coming on shift)")
	if why != "":
		main.free()
		return [why]
	var e = ui.clock.engine
	ui.fault("cw_b_ls")
	var log := []
	var wi: int = e.m.work_ix[LS]
	var accepted := func(): return e.pstate[wi] == 5 and e.acceptor.get(LS) == "ic1"
	if not await _steps(tree, ui, accepted, 4000, log):
		var msg := "the trainee never accepted the limit switch's permit (state %d, now %s)" % [e.pstate[wi],
				ui.clock_text()]
		main.free()
		return p + log.slice(0, 3) + [msg]
	# the repair from the card at the valve, under the accepted permit (its isolation in place, §15.5)
	ui.go_to_place(e._sm.work_at[VALVE_B])
	ui._place_tick()
	ui.open_card(VALVE_B)
	await tree.process_frame
	ui.card.refresh()
	var rb = ui.card.find_child("repair_cw_b_ls", true, false)
	if rb == null or not rb.visible or rb.disabled:
		p.append("the card offers no repair under the permit: %s" % App.texts(ui.card).left(400))
	else:
		rb.pressed.emit()
		ui.clock.run_steps(2)
		if e.v("cw_b_ls_fault") != 0.0:
			p.append("the repair under the permit did not put the limit switch right")
	ui.close_card()
	var closed := func(): return _closed(e, LS)
	if not await _steps(tree, ui, closed, 4000, log):
		var cur = e.sp_cur[e.st_trainee]
		p.append("the limit switch's permit was not closed (state %d, now %s, the task %s step %s at %d, queue %s)" % [
				e.pstate[wi], ui.clock_text(), str(cur["task"]) if cur else "none", str(cur["step"]) if cur else "",
				e.st_t_at, str(e.sp_queue[e.st_trainee].map(func(q): return q["task"]))])
	var repairs: Array = e.events.filter(func(ev): return ev[1] == "repair" and ev[2] == "cw_b_ls" and ev.size() == 3)
	if repairs.size() != 1:
		p.append("the limit switch was repaired %d times (expected once: the work's done finds it repaired)" %
				repairs.size())
	var locks: Array = e.events.filter(func(ev): return ev[1] == "lock" and ev[2] == LS and ev[5] == "done").map(
			func(ev): return ev[4])
	if not ("a_eap" in locks and locks.any(func(x): return String(x).contains("_fo_"))):
		p.append("the breaker and the valve were not locked by the electrician and a field operator: %s" % str(locks))
	p += log.slice(0, 3)
	main.free()
	return p


func _hse_stop(tree: SceneTree) -> Array:
	var p: Array = []
	var main := App.start(tree)
	var ui = main.ui
	ui.player.set_physics_process(false)
	_scenario(ui, "test_hse", "06:30")
	var why: String = await _take(tree, ui, "test_hse", "Play Safety 2 (coming on shift)")
	if why != "":
		main.free()
		return [why]
	var e = ui.clock.engine
	var log := []
	var stopped := func(): return _has_ev(e, ["stop", "hse2", "con5", "unsafe", "wo_paint_cw", "done"])
	if not await _steps(tree, ui, stopped, 6000, log):
		var cur = e.sp_cur[e.st_trainee]
		var msg := "the HSE officer did not stop the contractor's shortcut (now %s, the task %s)" % [ui.clock_text(),
				str(cur["task"]) if cur else "none"]
		main.free()
		return p + log.slice(0, 3) + [msg]
	p += log.slice(0, 3)
	if not _has_ev(e, ["task", "con5", "con_paint_cw_short", "abandoned"]):
		p.append("the contractor's shortcut was not abandoned when stopped")
	if not _has_ev(e, ["task", "con5", "leave_shortcut", "start"]):
		p.append("the contractor was not given the put-right task")
	if not e.inputs.any(func(x): return x[1] == "zone" and x[2] == "cw_house" and x[3] == "in"):
		p.append("no zone input for the CW pump house")
	# the people's hats: a contractor in the pump house wears theirs on the head (PLANT3D §18.2, §17.11)
	if not ui.people.hat_on(e, e._sm, e._sm.person_ix["con5"]):
		p.append("the contractor in the pump house does not show the hard hat on")
	ui.open_debrief()
	ui.debrief._tab("safety")
	var t := App.texts(ui.debrief)
	if not t.contains("Work stopped by Safety 2") or not t.contains("Unsafe act: Contractor 5"):
		p.append("the debrief's Safety tab: %s" % t.left(500))
	ui.close_debrief()
	_save(ui, p)
	main.free()
	return p


func _operator_sees(tree: SceneTree) -> Array:
	var p: Array = []
	var main := App.start(tree)
	var ui = main.ui
	var why: String = await _take(tree, ui, "shift_cold", "Play Control 1, crew A…")
	if why != "":
		main.free()
		return [why]
	var e = ui.clock.engine
	ui.fault("cond_p2_drift")
	var wi: int = e.m.work_ix[CAL]
	var iso_k: int = e._iso[e.m.isolation_ix["iso_cond_p2"]][4]
	var issued := false
	var was_isolated := false
	for i in 2000:
		ui.clock.run_steps(20)
		if e.lockbits[iso_k] == 1 and not was_isolated:
			was_isolated = true
			# the operator's screen: the transmitter isolated, with its permit's number (PLANT3D §15.1)
			ui.go_control_room(false)
			ui.open_screens(ui.screens.screens[ui.screens.screen_of[PT2][0]]["id"])
			for k in 30:
				await tree.process_frame
			var mk := String(ui.mimic.locks_drawn.get(PT2, ""))
			if not mk.begins_with("ISOLATED PTW-"):
				p.append("the screens do not mark %s isolated with its permit: %s" % [PT2, mk])
			ui.close_screens()
		if e.pstate[wi] >= 4:
			issued = true
		if e.pstate[wi] == 9:
			break
	if not was_isolated:
		p.append("the NPCs never isolated transmitter 2")
	if e.pstate[wi] != 9:
		p.append("the NPCs' calibration did not run to closed (state %d)" % e.pstate[wi])
	elif absf(e.v("cond_p2") - e.v("cond_p3") - 0.2) > 0.05:
		p.append("after the NPCs' calibration transmitter 2 is not in line: %.2f" % (e.v("cond_p2") - e.v("cond_p3")))
	if not issued:
		p.append("the permit was never issued")
	main.free()
	return p


## A run with PPE worn, acts recorded and seen reactions made goes round a save and on bit for bit (and a clone).
func _save(ui, p: Array) -> void:
	var e = ui.clock.engine
	var fields := RunSave.engine_fields(e)
	for f in ["sp_worn", "sp_acts", "sp_zin", "st_made"]:
		if not f in fields:
			p.append("the save leaves out the staff's %s" % f)
	var data := RunSave.capture(e, fields)
	var f2 = PlantEngine.new(ui.model, e.sc)
	var bad := RunSave.check(f2, RunSave.engine_fields(f2), data)
	if bad != "":
		p.append("a fresh engine refuses a save with acts: " + bad)
		return
	RunSave.apply(f2, bytes_to_var(var_to_bytes(data)))
	var c = e.clone()
	for k in 600:
		e.step()
		f2.step()
		c.step()
	if var_to_bytes(e.snapshot()) != var_to_bytes(f2.snapshot()) or var_to_bytes(e.events) != var_to_bytes(f2.events):
		p.append("the restored run with acts differs from the uninterrupted one")
	if var_to_bytes(e.snapshot()) != var_to_bytes(c.snapshot()):
		p.append("a clone with acts went on differently")
