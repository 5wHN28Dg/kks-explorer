## Locks at a shift change and instructor actions (docs/PLANT3D.md §15.1, §15.5, §17.9, §18.7; the user's decisions
## of 2026-10-24), played in the app:
## - as crew A's electrical authorised person coming on at 05:45: the cooling tower fan's permit, issued by the night
##   crew with crew C's electrician's lock on the breaker; the outgoing electrician's unlock alone is refused (the
##   point would be left unprotected); the form offers "Take over the lock" within reach of the breaker; pressed, the
##   incoming lock goes on first, then the outgoing one comes off; the breaker is locked after every step, and both
##   people are in the permit's history; a run saved then is put back with both locks;
## - as crew A's supervisor, nobody taking over: the removal by authority names whose lock it removes; done while
##   the permit is issued, the work is suspended (back to approved) and the form says so;
## - instructor mode: a fault pressed and repaired from the instructor's panel is marked in the debrief, which says at
##   its top (and in its title) that the run used instructor mode; so does the saved run's offer.
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const SimClock = preload("res://ui/sim_clock.gd")
const Debrief = preload("res://ui/debrief.gd")
const RunSave = preload("res://ui/run_save.gd")

const WORK := "wo_ct_fan3"
const FAN := "30PAD10AN003"


static func _press(pm, name: String) -> String:
	var b = pm.body.find_child(name, true, false)
	if b == null or not (b is Button):
		return "no button %s on the form (%s)" % [name, App.texts(pm.body).left(500)]
	if b.disabled:
		return "the form's %s is disabled (%s)" % [name, App.texts(pm.body).left(500)]
	(b as Button).pressed.emit()
	return ""


## Starts shift_cold as the person whose Play button is `call`, paused, the Crew panel closed.
static func _play(tree: SceneTree, main, call: String) -> String:
	var ui = main.ui
	if ui == null or ui.clock == null or not ui.model.scenarios.has("shift_cold"):
		return "the app or its scenario with the crews (shift_cold) did not start"
	ui.start_shift("shift_cold")
	await tree.process_frame
	var play := App.find_button(ui.crew, "Play %s…" % call)
	if play == null:
		return "the shift's start offers no %s (the Crew panel: %s)" % [call, App.texts(ui.crew).left(300)]
	play.pressed.emit()
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	ui.close_crew()
	return ""


## The night crew's permit for the fan, issued, crew C's electrician's lock on its breaker (NPCs' inputs, as their
## step 9 makes them).
static func _issued_by_night(ui) -> Array:
	var p := []
	var e = ui.clock.engine
	for x in [["permit", WORK, "request", "c_sup"], ["permit", WORK, "approve", "c_sup"], ["lock", WORK, 0, "c_eap"],
			["permit", WORK, "issue", "c_sup"]]:
		e.npc_queue.append(x)
		ui.clock.run_steps(1)
		var got := false
		for ev in e.events.slice(-12):
			if ev[0] == e.step_no and ev[1] == x[0] and ev[2] == WORK and ev.size() > 5 and ev[5] == "done":
				got = true
		if not got:
			p.append("the night crew's %s was not made: %s" % [str(x), str(e.events.slice(-4))])
	if e.pstate[e.m.work_ix[WORK]] != 4:
		p.append("the fan's permit is not issued: %d" % e.pstate[e.m.work_ix[WORK]])
	return p


static func _bit(e) -> int:
	return e.lockbits[e._iso[e.m.isolation_ix["iso_ct_fan3"]][4]]


func run(tree: SceneTree) -> Array:
	var p: Array = []
	p += await _handover(tree)
	p += await _nobody(tree)
	p += await _instructor(tree)
	return p


func _handover(tree: SceneTree) -> Array:
	var main := App.start(tree)
	var why: String = await _play(tree, main, "Electrical, crew A")
	if why != "":
		main.free()
		return [why]
	var ui = main.ui
	var e = ui.clock.engine
	var p := _issued_by_night(ui)
	# the outgoing electrician alone can't take their lock off while the work is issued: never unprotected
	e.npc_queue.append(["unlock", WORK, 0, "c_eap"])
	ui.clock.run_steps(1)
	if not e.events.has([e.step_no, "unlock", WORK, 0, "c_eap", "refused", ["state"]]) or _bit(e) != 1:
		p.append("the outgoing electrician's unlock alone was not refused: %s" % str(e.events.slice(-3)))
	ui.open_permits(WORK)
	var pm = ui.permits
	ui.go_control_room(false)
	pm._sig = ""
	pm.refresh()
	var tk = pm.body.find_child("takeover_0", true, false)
	if tk == null:
		main.free()
		return p + ["no Take over the lock on the form: %s" % App.texts(pm.body).left(600)]
	if not (tk as Button).disabled:
		p.append("Take over the lock is offered away from the breaker")
	ui.player.global_position = ui.index.center(FAN) + Vector3(0, 0, 3)
	pm._sig = ""
	pm.refresh()
	var err := _press(pm, "takeover_0")
	if err != "":
		p.append(err)
	ui.clock.run_steps(1)
	if _bit(e) != 1 or not e.events.has([e.step_no, "lock", WORK, 0, "a_eap", "done", []]):
		p.append("the incoming lock was not made: %s" % str(e.events.slice(-3)))
	if str(e.lockers.get(Vector2i(e.m.isolation_ix["iso_ct_fan3"], 0))) != str(["c_eap", "a_eap"]):
		p.append("the breaker does not hold both locks in order: %s" % str(e.lockers))
	pm._sig = ""
	pm.refresh()
	var t := App.texts(pm.body)
	if not t.contains("LOCKED and tagged by Electrical, crew C, then Electrical, crew A"):
		p.append("the form does not list both locks: %s" % t.left(600))
	# a run saved with the two locks is put back with them
	var saved: Dictionary = ui.autosave.payload()
	why = ui.autosave.check(saved)
	if why != "":
		p.append("a run saved with a handed-over lock was refused: %s" % why)
	var bad: Dictionary = saved.duplicate(true)
	bad["engine"]["lockers"][Vector2i(e.m.isolation_ix["iso_ct_fan3"], 0)] = []
	if ui.autosave.check(bad) == "":
		p.append("a save with an empty list of locks was accepted")
	var dec: Dictionary = RunSave.decode(RunSave.encode(saved))
	if dec.get("ok", false):
		var want: String = str(e.lockers)
		ui.restart("cold_iron", true)
		ui.autosave.restore(dec["payload"])
		e = ui.clock.engine
		if str(e.lockers) != want:
			p.append("the restored locks differ: %s, not %s" % [str(e.lockers), want])
	else:
		p.append("the saved run did not decode")
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	# the outgoing electrician's unlock now goes through: the incoming lock stays, the point never unlocked
	e.npc_queue.append(["unlock", WORK, 0, "c_eap"])
	ui.clock.run_steps(1)
	if not e.events.has([e.step_no, "unlock", WORK, 0, "c_eap", "done", []]) or _bit(e) != 1:
		p.append("the outgoing unlock after the handover was not made, or left the point unlocked: %s"
				% str(e.events.slice(-3)))
	for ev in e.events:
		if ev[1] == "permit" and ev[2] == WORK and ev[3] == "auto" and ev[6] == [2]:
			p.append("the permit went back to approved during the handover: %s" % str(ev))
	ui.open_permits(WORK)
	pm._sig = ""
	pm.refresh()
	t = App.texts(pm.body)
	if not t.contains("LOCKED and tagged by Electrical, crew A") or t.contains("then Electrical"):
		p.append("the form does not show the incoming lock alone: %s" % t.left(600))
	if not (t.contains("Electrical, crew C") and t.contains("Electrical, crew A")):
		p.append("the permit's history does not name both people: %s" % t.left(900))
	main.free()
	return p


func _nobody(tree: SceneTree) -> Array:
	var main := App.start(tree)
	var why: String = await _play(tree, main, "Supervisor, crew A")
	if why != "":
		main.free()
		return [why]
	var ui = main.ui
	var e = ui.clock.engine
	var p := _issued_by_night(ui)
	ui.open_permits(WORK)
	var pm = ui.permits
	ui.player.global_position = ui.index.center(FAN) + Vector3(0, 0, 3)
	pm._sig = ""
	pm.refresh()
	var t := App.texts(pm.body)
	if not t.contains("Remove Electrical, crew C's lock by authority") or not t.contains("suspends it"):
		p.append("the removal by authority does not name the lock or the suspension: %s" % t.left(700))
	var err := _press(pm, "remove_0_0")
	if err != "":
		p.append(err)
	ui.clock.run_steps(1)
	var wi: int = e.m.work_ix[WORK]
	if not e.events.has([e.step_no, "remove_lock", WORK, 0, "a_sup", "done", [], "c_eap",
			"Whoever locked it has left the site"]):
		p.append("the removal by authority was not made naming its owner: %s" % str(e.events.slice(-3)))
	if e.pstate[wi] != 2 or not e.events.has([e.step_no, "permit", WORK, "auto", null, "done", [2]]):
		p.append("the issued permit was not suspended back to approved: %d" % e.pstate[wi])
	pm._sig = ""
	pm.refresh()
	t = App.texts(pm.body)
	if not t.contains("Lock removed by authority by Supervisor, crew A"):
		p.append("the form's history does not record the removal: %s" % t.left(900))
	main.free()
	return p


func _instructor(tree: SceneTree) -> Array:
	var p := []
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null:
		main.free()
		return ["the app did not start"]
	ui.restart("shift_cold", true)
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	var e = ui.clock.engine
	var d0: Dictionary = Debrief.collect(e, ui.info, null)
	if "\n".join(Debrief.summary_lines(d0)).contains("instructor mode"):
		p.append("a run with no instructor action says it used instructor mode")
	ui.set_instructor(true)
	ui.toggle_trainer()
	var tp = ui.trainer
	tp.refresh()
	var fid: String = ""
	for f in tp.trainer_faults(e):
		if f.has("repair"):
			fid = f["id"]
			break
	var label: String = ""
	for f in tp.trainer_faults(e):
		if f["id"] == fid:
			label = f.get("text", fid)
	var row_btn := func(text: String) -> Button:
		for b in tp.body.find_children("*", "Button", true, false):
			var row = b.get_parent()
			if (b as Button).text == text and row.get_child_count() > 0 and row.get_child(0) is Label \
					and (row.get_child(0) as Label).text == label:
				return b
		return null
	var apply: Button = row_btn.call("Apply")
	if fid == "" or apply == null:
		main.free()
		return ["no trainer fault to press on the instructor's panel: %s" % App.texts(tp.body).left(300)]
	apply.pressed.emit()
	ui.clock.run_steps(1)
	tp._sig = ""
	tp.refresh()
	var rep: Button = row_btn.call("Repair")
	if rep == null:
		p.append("no Repair for the pressed fault: %s" % App.texts(tp.body).left(300))
	else:
		rep.pressed.emit()
		ui.clock.run_steps(1)
	var d: Dictionary = Debrief.collect(e, ui.info, null)
	var marks := []
	var by := []
	for x in d.entries:
		if x.kind == "instructor":
			marks.append(x)
		elif (x.kind == "fault" or x.kind == "repair") and x.text.ends_with("(by the instructor)"):
			by.append(x)
	if marks.size() != 2 or marks[0].dev == "":
		p.append("the debrief does not list both instructor actions: %s" % str(marks))
	if by.size() != 2:
		p.append("the fault and its repair are not marked as the instructor's: %s" % str(d.entries.slice(-6)))
	var lines := Debrief.summary_lines(d)
	if lines.is_empty() or lines[0] != "This run used instructor mode: 2 instructor actions (marked below)":
		p.append("the debrief does not say at its top that the run used instructor mode: %s" % "\n".join(lines))
	if not String(d.title).contains("instructor mode used"):
		p.append("the debrief's title does not say instructor mode was used: %s" % d.title)
	# the saved run's offer says so too
	var saved: Dictionary = ui.autosave.payload()
	ui.autosave._show_offer(saved, "")
	var offer := App.texts(ui.autosave.offer_panel)
	if not offer.contains("This run used instructor mode (2 instructor actions)."):
		p.append("the saved run's offer does not say the run used instructor mode: %s" % offer.left(400))
	main.free()
	return p
