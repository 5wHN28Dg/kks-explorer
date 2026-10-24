## An offer nobody could take is made again (docs/PLANT3D.md §17.10; the user, 2026-10-24), played in the app as
## crew A's supervisor at 05:30, before the day technicians come on: the cooling tower fan's permit issued from the
## form finds no mechanical technician on duty (its job unassigned); at 07:00, when they come on, the job is offered.
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
	pm._sig = ""
	pm.refresh()
	if e.pstate[e.m.work_ix[WORK]] == 3:     # (the night supervisor may issue it first: the same either way)
		var err := _press(pm, "do_issue")
		if err != "":
			p.append(err)
	for i in 200:
		ui.clock.run_steps(5)
		if e.pstate[e.m.work_ix[WORK]] == 4:
			break
	var unassigned := false
	for ev in e.events:
		if ev[1] == "task" and ev[2] == null and ev[3] == "job_ct_fan3" and ev[4] == "unassigned":
			unassigned = true
	if not unassigned:
		main.free()
		return p + ["the fan's job was not unassigned before the technicians came on: %s" % str(e.events.slice(-6))]
	# run to 07:00 and a little after: the mechanical technicians come on duty
	var want: int = 864000 + (7 * 60 + 5) * 600
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
	main.free()
	return p
