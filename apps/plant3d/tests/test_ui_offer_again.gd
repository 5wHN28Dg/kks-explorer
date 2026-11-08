## An offer nobody could take is made again (docs/PLANT3D.md §17.10; the user, 2026-10-24), played in the app as
## crew A's supervisor early on the first day, before the day technicians come on: the cooling tower fan's permit issued from the
## form finds no maintenance supervisor on duty to make its JSA (unassigned, HS1: the issue is refused without it); at
## 07:00, when they come on, one makes it, the permit is issued from the form and a supervisor gives the job (milestone
## S2: a maintenance supervisor gives an issued permit's job).
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const SimClock = preload("res://ui/sim_clock.gd")

const WORK := "wo_ct_fan3"


static func _press(pm, name: String) -> String:
	var b = pm.body.find_child(name, true, false)
	if b == null or not (b is Button):
		return "no button %s on the form (%s)" % [name, App.texts(pm.body).left(500)]
	if b.disabled:
		return "the form's %s is disabled (%s)" % [name, App.texts(pm.body).left(500)]
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
		return ["no supervisor to play: %s" % App.texts(ui.crew).left(300)]
	play.pressed.emit()
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	ui.close_crew()
	var e = ui.clock.engine
	ui.open_permits(WORK)
	var pm = ui.permits
	for a in ["request", "approve"]:
		pm._sig = ""
		pm.refresh()
		var err := _press(pm, "do_" + a)
		if err != "":
			p.append(err)
		ui.clock.run_steps(1)
	e.npc_queue.append(["lock", WORK, 0, "a_eap"])      # the electrician's lock, as their step 9 makes it
	ui.clock.run_steps(2)
	# HS1 (REALISM.md §8.6): the isolated permit's JSA is a maintenance supervisor's, none of whom is on duty before
	# 07:00: theirs is now the offer nobody could take; the issue from the form is refused meanwhile (jsa)
	pm._sig = ""
	pm.refresh()
	if e.pstate[e.m.work_ix[WORK]] != 3:
		p.append("the fan's permit is not isolated: %d" % e.pstate[e.m.work_ix[WORK]])
	var err := _press(pm, "do_issue")
	if err != "":
		p.append(err)
	ui.clock.run_steps(1)
	if e.pstate[e.m.work_ix[WORK]] != 3:
		p.append("the fan's permit was issued without its JSA: %d" % e.pstate[e.m.work_ix[WORK]])
	var unassigned := false
	for ev in e.events:
		if ev[1] == "task" and ev[2] == null and ev[3] == "jsa_permit" and ev[4] == "unassigned":
			unassigned = true
	if not unassigned:
		main.free()
		return p + ["the fan's JSA was not unassigned before the maintenance supervisors came on: %s" % str(e.events.slice(-6))]
	# at 07:00 the offer is made again: a maintenance supervisor makes the JSA and asks the supervisor (the player)
	# to issue it, which they do from the form
	for i in 300:
		if e.jsa_of.has(WORK):
			break
		ui.clock.run_steps(50)
	var made: Array = e.events.filter(func(ev): return ev[1] == "task" and ev[3] == "jsa_permit" and ev[4] == "start")
	if not e.jsa_of.has(WORK) or made.size() != 1 or not String(made[0][2]).begins_with("ms_"):
		main.free()
		return p + ["the JSA's offer was not made again to a maintenance supervisor once: %s" % str(made)]
	pm._sig = ""
	pm.refresh()
	err = _press(pm, "do_issue")
	if err != "":
		p.append(err)
	ui.clock.run_steps(2)
	if e.pstate[e.m.work_ix[WORK]] != 4:
		p.append("the fan's permit was not issued once its JSA was made: %d" % e.pstate[e.m.work_ix[WORK]])
	# run to 07:00, when the maintenance supervisors and technicians come on duty, and on until the supervisor has
	# given the job (the walk to the office's table and the toolbox talk first)
	var want: int = 864000 + (8 * 60) * 600
	while e.clock() < want:
		ui.clock.run_steps(2000)
	var offered := false
	for pi in e._sm.people.size():
		var all: Array = e.sp_queue[pi].duplicate()
		if e.sp_cur[pi] != null:
			all.append(e.sp_cur[pi])
		for inst in all:
			if inst["task"] == "job_ct_fan3":
				offered = true
	for ev in e.events:
		if ev[1] == "task" and ev[3] == "job_ct_fan3" and ev[4] == "start":
			offered = true
	if not offered:
		p.append("the unassigned job was not offered when the technicians came on duty")
	var given: Array = e.events.filter(func(ev): return ev[1] == "task" and ev[3] == "assign_ct_fan3" and ev[4] == "start")
	if given.size() != 1 or not String(given[0][2]).begins_with("ms_"):
		p.append("the job was not given by a maintenance supervisor once: %s" % str(given))
	main.free()
	return p
