## Day-shift jobs overnight and re-issued permits (docs/PLANT3D.md §17.10; the user's decisions of 2026-10-24),
## played in the app as crew A's supervisor:
## - condenser pressure transmitter 3's calibration (not on Monday's list: transmitter 2's is, at 07:40, and is closed
##   by the afternoon), issued late in the day: the I&C technician (a day worker) is
##   still on the job at 16:00; it is held, they go home with their lock on, the permit stays as it was (not
##   suspended or cancelled), nobody removes the lock by authority, and the form says the lock stays on overnight;
## - the same with two technicians (the user, 2026-10-25): one isolates, the other's job is held; the first one's
##   lock stays on overnight too;
## - the cooling tower fan's job suspended mid-work by a removal by authority: isolated and issued again, it is
##   offered to a technician again.
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const SimClock = preload("res://ui/sim_clock.gd")

const CAL := "wo_cond_p3_cal"
const PT3 := "30MAG10CP003"
const FAN_WORK := "wo_ct_fan3"
const FAN := "30PAD10AN003"


static func _press(pm, name: String) -> String:
	var b = pm.body.find_child(name, true, false)
	if b == null or not (b is Button):
		return "no button %s on the form (%s)" % [name, App.texts(pm.body).left(500)]
	if b.disabled:
		return "the form's %s is disabled (%s)" % [name, App.texts(pm.body).left(500)]
	(b as Button).pressed.emit()
	return ""


static func _start(tree: SceneTree, main) -> String:
	var ui = main.ui
	if ui == null or ui.clock == null or not ui.model.scenarios.has("shift_cold"):
		return "the app or its scenario with the crews (shift_cold) did not start"
	ui.start_shift("shift_cold")
	await tree.process_frame
	var play := App.find_button(ui.crew, "Play Supervisor, crew A…")
	if play == null:
		return "no supervisor to play (the Crew panel: %s)" % App.texts(ui.crew).left(300)
	play.pressed.emit()
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	ui.close_crew()
	return ""


## Runs until the clock reaches HH:MM of day 1 (tenths of a clock second, §16.1).
static func _until(ui, hh: int, mm: int) -> void:
	var e = ui.clock.engine
	var want: int = (864000 + (hh * 60 + mm) * 600)
	while e.clock() < want:
		ui.clock.run_steps(mini(2000, maxi(1, (want - e.clock()) / e._ds)))


static func _form(ui, wid: String, actions: Array) -> Array:
	var p := []
	ui.open_permits(wid)
	var pm = ui.permits
	for a in actions:
		pm._sig = ""
		pm.refresh()
		var err := _press(pm, "do_" + a)
		if err != "":
			p.append(err)
		ui.clock.run_steps(1)
	return p


func run(tree: SceneTree) -> Array:
	var p: Array = []
	p += await _overnight(tree)
	p += await _colleague(tree)
	p += await _reoffered(tree)
	return p


func _overnight(tree: SceneTree) -> Array:
	var main := App.start(tree)
	var why: String = await _start(tree, main)
	if why != "":
		main.free()
		return [why]
	var ui = main.ui
	var e = ui.clock.engine
	_until(ui, 15, 40)
	var p := _form(ui, CAL, ["request", "approve"])
	# the I&C technician locks the transmitter's root valve (an NPC's input, as its step 9 makes it)
	e.npc_queue.append(["lock", CAL, 0, "ic1"])
	ui.clock.run_steps(2)
	p += _form(ui, CAL, ["issue"])
	var wi: int = e.m.work_ix[CAL]
	if e.pstate[wi] != 4:
		main.free()
		return p + ["the calibration's permit was not issued: %d" % e.pstate[wi]]
	_until(ui, 16, 40)
	var held := false
	var removal := false
	for ev in e.events:
		if ev[1] == "task" and ev[2] == "ic1" and ev[3] == "job_cond_p3_cal" and ev[4] == "held":
			held = true
		if ev[1] == "remove_lock" or (ev[1] == "task" and ev[3] == "remove_left_locks"):
			removal = true
	var ic: int = e._sm.person_ix["ic1"]
	if not held:
		p.append("the technician's unfinished job was not held at the end of their duty")
	if e.sp_pos[ic] != -1:
		p.append("the technician did not go home")
	if removal:
		p.append("a day worker's lock left on overnight was removed by authority")
	if e.pstate[wi] != 4 and e.pstate[wi] != 5:
		p.append("the permit did not stay as it was overnight: %d" % e.pstate[wi])
	if e.lockbits[e._iso[e.m.isolation_ix["iso_cond_p3"]][4]] != 1:
		p.append("the transmitter is no longer isolated")
	ui.open_permits(CAL)
	var pm = ui.permits
	pm._sig = ""
	pm.refresh()
	var t := App.texts(pm.body)
	if not t.contains("I&C technician's lock stays on until its job is done"):
		p.append("the form does not say the lock stays on overnight: %s" % t.left(700))
	main.free()
	return p


## Two technicians (the user, 2026-10-25): ic2 isolates the transmitter, the job goes to ic1 and is held at 16:00;
## ic2 goes home with their lock on and it stays (no removal by authority, none offered to the supervisor), and the
## permit form says so.
func _colleague(tree: SceneTree) -> Array:
	var main := App.start(tree)
	var why: String = await _start(tree, main)
	if why != "":
		main.free()
		return [why]
	var ui = main.ui
	var e = ui.clock.engine
	_until(ui, 15, 40)
	var p := _form(ui, CAL, ["request", "approve"])
	e.npc_queue.append(["lock", CAL, 0, "ic2"])      # the isolating technician's lock, as their step 9 makes it
	ui.clock.run_steps(2)
	p += _form(ui, CAL, ["issue"])
	var wi: int = e.m.work_ix[CAL]
	if e.pstate[wi] != 4:
		main.free()
		return p + ["the calibration's permit was not issued: %d" % e.pstate[wi]]
	_until(ui, 16, 40)
	var holder := ""
	for ev in e.events:
		if ev[1] == "task" and ev[3] == "job_cond_p3_cal" and ev[4] == "held":
			holder = str(ev[2])
		if ev[1] == "remove_lock" or (ev[1] == "task" and ev[3] == "remove_left_locks"):
			p.append("the colleague's lock was removed by authority (or its removal given): %s" % str(ev))
	var me: int = e.st_trainee
	for inst in e.sp_queue[me] + ([e.sp_cur[me]] if e.sp_cur[me] != null else []):
		if inst["task"] == "remove_left_locks":
			p.append("the supervisor was asked to remove the colleague's lock")
	if holder == "" or holder == "ic2":
		p.append("the job was not held by the other technician: %s" % holder)
	if e.sp_pos[e._sm.person_ix["ic2"]] != -1:
		p.append("the isolating technician did not go home")
	if e.lockbits[e._iso[e.m.isolation_ix["iso_cond_p3"]][4]] != 1:
		p.append("the transmitter is no longer isolated")
	if e.pstate[wi] != 5:
		p.append("the permit did not stay accepted overnight: %d" % e.pstate[wi])
	ui.open_permits(CAL)
	var pm = ui.permits
	pm._sig = ""
	pm.refresh()
	var t := App.texts(pm.body)
	if not t.contains("I&C technician 2's lock stays on until its job is done"):
		p.append("the form does not say the colleague's lock stays on overnight: %s" % t.left(700))
	main.free()
	return p


func _reoffered(tree: SceneTree) -> Array:
	var main := App.start(tree)
	var why: String = await _start(tree, main)
	if why != "":
		main.free()
		return [why]
	var ui = main.ui
	var e = ui.clock.engine
	_until(ui, 7, 20)
	var p := _form(ui, FAN_WORK, ["request", "approve"])
	e.npc_queue.append(["lock", FAN_WORK, 0, "a_eap"])
	ui.clock.run_steps(2)
	p += _form(ui, FAN_WORK, ["issue"])
	var wi: int = e.m.work_ix[FAN_WORK]
	var accepted := false
	for i in 400:
		ui.clock.run_steps(50)
		if e.pstate[wi] == 5:
			accepted = true
			break
	if not accepted:
		main.free()
		return p + ["the technician never accepted the fan's permit: %d" % e.pstate[wi]]
	# the breaker's lock removed by authority mid-work: the work suspended
	ui.open_permits(FAN_WORK)
	var pm = ui.permits
	ui.player.global_position = ui.index.center(FAN) + Vector3(0, 0, 3)
	pm._sig = ""
	pm.refresh()
	var err := _press(pm, "remove_0_0")
	if err != "":
		p.append(err)
	ui.clock.run_steps(1)
	if e.pstate[wi] != 2:
		p.append("the fan's permit was not suspended: %d" % e.pstate[wi])
	# isolated and issued again
	e.npc_queue.append(["lock", FAN_WORK, 0, "a_eap"])
	ui.clock.run_steps(2)
	var reissued: int = e.step_no
	p += _form(ui, FAN_WORK, ["issue"])
	ui.clock.run_steps(20)
	var again := false              # a new instance of the job, given after the re-issue (queued or started)
	for pi in e._sm.people.size():
		var all: Array = e.sp_queue[pi].duplicate()
		if e.sp_cur[pi] != null:
			all.append(e.sp_cur[pi])
		for inst in all:
			if inst["task"] == "job_ct_fan3" and inst["made"] >= reissued:
				again = true
	if not again:
		p.append("the suspended job was not offered again when the permit was re-issued: %s"
				% str(e.events.slice(-8)))
	main.free()
	return p
