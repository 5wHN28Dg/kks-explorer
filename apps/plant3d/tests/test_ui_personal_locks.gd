## Personal locks and actions before their step (docs/PLANT3D.md §15.1, §17.8; the user's decisions of 2026-10-23),
## played in the app as the shift supervisor of crew A:
## - CW pump A's permit requested and approved from the form; the electrical authorised person (an NPC, as its step 9
##   would make it) locks its breaker: the form says whose lock it is, offers the supervisor no Remove, only the
##   removal by authority, and that only within reach of the breaker;
## - the removal with a typed reason (kept while the form is rebuilt) goes through: the event names whose lock it was
##   and the reason, and the form's history, the debrief's permits tab and its summary say so;
## - an action of the trainee's made before its task step (the event `early`) is listed in the debrief as a deviation,
##   done out of order, and counted in the summary.
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const SimClock = preload("res://ui/sim_clock.gd")
const Debrief = preload("res://ui/debrief.gd")
const DebriefPanel = preload("res://ui/debrief_panel.gd")

const WORK := "wo_cw_a_motor"
const BREAKER := "30PAC10AP001"
const REASON := "Electrical, crew A went home sick; breaker seen racked out"


static func _press(pm, name: String) -> String:
	var b = pm.body.find_child(name, true, false)
	if b == null or not (b is Button):
		return "no button %s on the form (%s)" % [name, App.texts(pm.body).left(400)]
	if b.disabled:
		return "the form's %s is disabled" % name
	(b as Button).pressed.emit()
	return ""


func run(tree: SceneTree) -> Array:
	var p: Array = []
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null or not ui.model.scenarios.has("shift_cold"):
		main.free()
		return ["the app or its scenario with the crews (shift_cold) did not start"]
	ui.start_shift("shift_cold")
	await tree.process_frame
	var play := App.find_button(ui.crew, "Play Supervisor, crew A…")
	if play == null:
		main.free()
		return ["the shift's start offers no supervisor (the Crew panel: %s)" % App.texts(ui.crew).left(300)]
	play.pressed.emit()
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	var e = ui.clock.engine
	if ui.me() != "a_sup":
		main.free()
		return ["the supervisor's role was not taken: %s" % str(ui.me())]
	ui.close_crew()
	ui.permits.open(WORK)
	var pm = ui.permits
	for a in ["request", "approve"]:
		var err := _press(pm, "do_" + a)
		if err != "":
			p.append(err)
		ui.clock.run_steps(1)
		pm.refresh()
	# the electrical authorised person locks the breaker (an NPC's input, as its step 9 makes it)
	e.npc_queue.append(["lock", WORK, 0, "a_eap"])
	ui.clock.run_steps(1)
	if not e.events.has([e.step_no, "lock", WORK, 0, "a_eap", "done", []]):
		p.append("the NPC's lock was not made: %s" % str(e.events.slice(-5)))
	ui.player.global_position = ui.index.center(BREAKER) + Vector3(0, 0, 3)
	pm._sig = ""
	pm.refresh()
	var t := App.texts(pm.body)
	if not t.contains("LOCKED and tagged by Electrical, crew A") or not t.contains("Only Electrical, crew A removes this lock."):
		p.append("the form does not say whose lock it is: %s" % t.left(600))
	if pm.body.find_child("unlock_0", true, false) != null:
		p.append("the supervisor is offered the electrician's own Remove")
	var go = pm.body.find_child("remove_0", true, false)
	var field = pm.body.find_child("reason_0", true, false)
	if go == null or field == null:
		main.free()
		return p + ["no removal by authority on the form: %s" % t.left(600)]
	# the reason typed is kept when the form is rebuilt
	(field as LineEdit).text = REASON
	(field as LineEdit).text_changed.emit(REASON)
	pm._sig = ""
	pm.refresh()
	field = pm.body.find_child("reason_0", true, false)
	if (field as LineEdit).text != REASON:
		p.append("the reason typed was lost when the form was rebuilt")
	# away from the breaker it is not offered
	ui.go_control_room(false)
	pm._sig = ""
	pm.refresh()
	if not (pm.body.find_child("remove_0", true, false) as Button).disabled:
		p.append("the removal by authority is offered away from the breaker")
	ui.player.global_position = ui.index.center(BREAKER) + Vector3(0, 0, 3)
	pm._sig = ""
	pm.refresh()
	var err := _press(pm, "remove_0")
	if err != "":
		p.append(err)
	ui.clock.run_steps(1)
	pm.refresh()
	var want := [e.step_no, "remove_lock", WORK, 0, "a_sup", "done", [], "a_eap", REASON]
	if not e.events.has(want):
		p.append("the removal was not made: %s" % str(e.events.slice(-5)))
	if e.lockbits[e._iso[e.m.isolation_ix["iso_cw_a"]][4]] != 0:
		p.append("the breaker is still locked")
	t = App.texts(pm.body)
	if not t.contains("Lock removed by authority by Supervisor, crew A") or not t.contains(REASON):
		p.append("the form's history does not record the removal: %s" % t.left(800))
	# an action before its task step, as the engine records it (§17.8): the debrief lists it as out of order
	var task: String = e._sm.tasks.keys()[0]
	e.events.append([e.step_no, "early", "a_sup", task, 1, "permit", e.step_no - 3])
	var d: Dictionary = Debrief.collect(e, ui.info, null)
	var by_auth := []
	var early := []
	for x in d.entries:
		if x.kind == "remove_lock":
			by_auth.append(x)
		elif x.kind == "early":
			early.append(x)
	if by_auth.size() != 1 or not by_auth[0].text.contains(REASON) or not by_auth[0].text.contains("Electrical, crew A") \
			or not DebriefPanel.in_tab(by_auth[0], "permits"):
		p.append("the debrief does not list the removal by authority: %s" % str(by_auth))
	if early.size() != 1 or not early[0].text.contains("step 2: done before its step") or early[0].dev == "" \
			or not DebriefPanel.in_tab(early[0], "deviations"):
		p.append("the debrief does not list the action made before its step: %s" % str(early))
	var lines := "\n".join(Debrief.summary_lines(d))
	if not lines.contains("(1 by authority)") or not lines.contains("Done out of order: 1"):
		p.append("the debrief's summary does not count them: %s" % lines)
	main.free()
	return p
