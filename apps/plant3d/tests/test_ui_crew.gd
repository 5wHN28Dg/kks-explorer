## The crews in the app (docs/PLANT3D.md §16–§18.7, milestone S1), as a trainee plays them:
## - as a field operator (CW and cooling tower): the role taken at the shift's start, the handover, the round walked
##   place by place with each reading written down from the Crew panel (one wrong on purpose: misread, the others in
##   range), the round's message sent; then a trainer's fault raises an alarm, the NPC control room operator
##   acknowledges it and calls the field operator over the radio, and the trainee checks it at the valve and reports;
## - as a control room operator: the radio panel's request sends an NPC field operator to put the CCW cooler in
##   service; they walk there, make the local op, and the plant changes (the cooler's valve open); the trainee's op
##   at a where it lacks is refused (`where`, §17.1);
## - the crews on screen (markers and map dots) while the run goes on;
## - a run with staff saved and put back goes on bit for bit, the people with it (ui/run_save.gd).
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const SimClock = preload("res://ui/sim_clock.gd")
const RunSave = preload("res://ui/run_save.gd")
const PlantEngine = preload("res://sim/engine.gd")

var _lost_typing := false


func run(tree: SceneTree) -> Array:
	var p: Array = []
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null or not ui.model.scenarios.has("shift_cold"):
		main.free()
		return ["the app or its scenario with the crews (shift_cold) did not start"]
	await _field_operator(tree, ui, p)
	await _ccr_operator(tree, ui, p)
	_save(ui, p)
	main.free()
	return p


## Plays the trainee's current step as a trainee would from the Crew panel; true when something was done.
func _play(ui, readings: Dictionary) -> bool:
	var e = ui.clock.engine
	var sm = e._sm
	var pi: int = e.st_trainee
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
	elif s.has("read"):
		var v: float = e.shown(s["read"], e.cur)
		var typed := v + (5.0 if readings.size() == 1 else 0.0)        # the second reading misread on purpose
		ui.crew.entry.text = "%.3f" % typed
		ui.crew._sig = ""
		ui.crew.refresh()           # the panel rebuilt (a colleague's radio message) while the trainee types
		if ui.crew.entry.text != "%.3f" % typed:
			_lost_typing = true
		App.find_button(ui.crew, "Write down").pressed.emit()
		readings[s["read"]] = typed
		return true
	elif s.has("say"):
		App.find_button(ui.crew, "Send").pressed.emit()
		return true
	elif s.has("choose"):
		ui.clock.engine.pick(0)
		return true
	return false


func _steps(ui, readings: Dictionary, until: Callable, limit: int) -> bool:
	for i in limit:
		if until.call():
			return true
		_play(ui, readings)
		ui.clock.run_steps(10)
	return until.call()


func _field_operator(tree: SceneTree, ui, p: Array) -> void:
	# a field operator alone on the CW round of crew A: the others absent, so the radio's call comes to the trainee
	var sc: Dictionary = ui.model.scenarios["shift_cold"].duplicate(true)
	sc["id"] = "test_crew_cw"
	sc["staff"]["absent"] = ["a_fo_gt", "a_fo_st"]
	ui.model.scenarios["test_crew_cw"] = sc
	ui.start_shift("test_crew_cw")
	await tree.process_frame
	if not ui.crew.visible or App.find_button(ui.crew, "Play Field CW, crew A…") == null:
		p.append("the shift's start offers no role (the Crew panel: %s)" % App.texts(ui.crew).left(300))
		return
	if ui.clock.speed != SimClock.Speed.PAUSED:
		p.append("the plant runs before a role is chosen")
	App.find_button(ui.crew, "Play Field CW, crew A…").pressed.emit()
	var e = ui.clock.engine
	if e.st_trainee == -1 or e._sm.people[e.st_trainee]["id"] != "a_fo_cw":
		p.append("the role was not taken: %s" % str(e.events.slice(0, 4)))
		return
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	var readings := {}
	var me: String = "a_fo_cw"
	var round_done := func():
		for ev in e.events:
			if ev[1] == "say" and ev[2] == me and ev[3] == "round_done":
				return true
		return false
	if not _steps(ui, readings, round_done, 2500):
		var cur = e.sp_cur[e.st_trainee]
		p.append("the CW round was not done by 07:00+ (now %s, the task %s step %s)" % [ui.clock_text(),
				str(cur["task"]) if cur else "none", str(cur["step"]) if cur else ""])
		return
	var reads: Array = e.events.filter(func(ev): return ev[1] == "read" and ev[2] == me)
	var how: Array = reads.map(func(ev): return ev[5])
	if reads.size() != 4 or how.count("misread") != 1 or how.count("ok") != 3:
		p.append("the round's readings: %s (expected 4: three in range, one misread)" % str(reads))
	if not App.texts(ui.crew).contains("misread"):
		ui.crew._sig = ""
		ui.crew.refresh()
		if not App.texts(ui.crew).contains("misread"):
			p.append("the readings sheet does not show the misreading")
	# a trainer's fault: CW pump B's discharge valve actuator; the NPC control room operator answers and calls
	var n0: int = e.events.size()
	ui.fault("cw_b_valve_stuck")
	var called := func():
		for k in range(n0, e.events.size()):
			var ev: Array = e.events[k]
			if ev[1] == "call" and ev[4] == "check_alarm" and ev[2] != me:
				return true
		return false
	_steps(ui, readings, called, 300)
	if not called.call():
		p.append("no NPC called a field operator to check the alarm")
		return
	var acked := false
	for k in range(n0, e.events.size()):
		if e.events[k][1] == "alarm" and e.events[k][2] == "cw_b_v_fault" and e.events[k][3] == "active_ack":
			acked = true
	if not acked:
		p.append("the NPC control room operator did not acknowledge the alarm")
	ui.crew._sig = ""
	ui.crew.refresh()
	if not App.texts(ui.crew).contains("Please check the alarm locally"):
		p.append("the radio panel does not show the call: %s" % App.texts(ui.crew).right(400))
	var checked := func():
		for k in range(n0, e.events.size()):
			var ev: Array = e.events[k]
			if ev[1] == "say" and ev[2] == me and ev[3] == "alarm_checked":
				return true
		return false
	if not _steps(ui, readings, checked, 1500):
		var cur = e.sp_cur[e.st_trainee]
		p.append("the trainee did not check the alarm at the valve (the task %s)" % (str(cur["task"]) if cur else "none"))
	var at: int = -1
	for k in range(n0, e.events.size()):
		if e.events[k][1] == "task" and e.events[k][2] == me and e.events[k][3] == "check_alarm" and e.events[k][4] == "done":
			at = k
	if at == -1:
		p.append("the check_alarm task was not done by the trainee")
	ui.people.update()
	if ui.people.shown < 3:
		p.append("the crews are not on screen (%d markers)" % ui.people.shown)
	if _lost_typing:
		p.append("a reading being typed was erased when the Crew panel rebuilt")
	# sleep to the next shift (a jump, §17.6): the walker is moved to where the placement put the trainee's person
	for k in e._al.size():
		if e.astate[k] in ["active_unack", "cleared_unack"]:
			ui.ack(e._al[k][0], false)
	if e.st_unacked > 0:
		e.task_ack()
	ui.clock.run_steps(2)
	ui.crew._sig = ""
	ui.crew.refresh()
	var sleep := App.find_button(ui.crew, "Sleep to…")
	if sleep == null or sleep.disabled:
		p.append("no sleep to the next shift offered (fast-forward %s: %s)" % [str(e.fast_forward()), ui.clock.ff_blocked()])
	else:
		var j0: int = e.J
		sleep.pressed.emit()
		ui.clock.run_steps(2)
		if e.J == j0:
			p.append("the jump was not made: %s" % str(e.events.slice(e.events.size() - 3)))
		else:
			ui._place_tick()
			var pos: int = e.sp_pos[e.st_trainee]
			ui.clock.run_steps(1)
			if ui._jumps != e.J or e.st_t_at != pos:
				p.append("after the jump the app did not follow the placement (%d, at %d)" % [pos, e.st_t_at])
			# the radio log read again from the start (as after a restore) keeps each line's own time
			var want := ""
			var lines := 0
			for ev in e.events:
				if ev[1] == "jump" and ev[4] == "done":
					break
				if ev[1] == "say" or (ev[1] == "call" and ev[6] == "done"):
					var t: int = (e._S + ev[0] * e._ds + j0) % 864000 / 10
					want = "%02d:%02d  " % [t / 3600, (t / 60) % 60]
					lines += 1
			ui.crew._engine = null
			ui.crew._follow(e)
			if lines == 0 or ui.crew._radio.size() < lines or not ui.crew._radio[lines - 1].begins_with(want):
				p.append("the radio log's last line before the jump does not read %s: %s"
						% [want, str(ui.crew._radio.slice(maxi(lines - 1, 0), lines + 1))])


func _ccr_operator(tree: SceneTree, ui, p: Array) -> void:
	ui.start_shift("shift_cold")
	await tree.process_frame
	var b := App.find_button(ui.crew, "Play Control 1, crew A…")
	if b == null:
		p.append("no control room operator to play: %s" % App.texts(ui.crew).left(300))
		return
	b.pressed.emit()
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	var e = ui.clock.engine
	ui.open_crew()
	ui.crew._sig = ""
	ui.crew.refresh()
	var req := App.find_button(ui.crew, "Call field op: Put the closed cooling water cooler in service")
	if req == null:
		p.append("the radio panel offers no request to a field operator: %s" % App.texts(ui.crew).right(500))
		return
	if e.truth("ccw_cooler"):
		p.append("the CCW cooler is in service before the instruction")
	req.pressed.emit()
	ui.clock.run_steps(1)
	var me: String = "a_ccr1"
	if not e.events.any(func(ev): return ev[1] == "call" and ev[2] == me and ev[4] == "ccw_cooler_in" and ev[6] == "done"):
		p.append("the radio call was not made: %s" % str(e.events.slice(maxi(0, e.events.size() - 5))))
	var done := func(): return e.truth("ccw_cooler")
	_steps(ui, {}, done, 1500)
	if not e.truth("ccw_cooler"):
		p.append("no NPC field operator opened the CCW cooler on the instruction (now %s)" % ui.clock_text())
	else:
		var op = e.events.filter(func(ev): return ev[1] == "op" and ev[2] == "00PGB10AC001" and ev[4] == "done")
		if op.is_empty() or op[0].size() < 8 or op[0][6] != "local" or op[0][7] == me:
			p.append("the cooler was not opened locally by an NPC: %s" % str(op))
	# the trainee's own op at a where the op lacks: the cooler's valves are worked locally only
	var o: Dictionary = {}
	for x in ui.model.ops:
		if x["kks"] == "00PGB10AC001" and x["do"] == "close":
			o = x
	ui.open_screens()
	ui.do_op(o, null)
	ui.clock.run_steps(1)
	var last = e.events.filter(func(ev): return ev[1] == "op" and ev[2] == "00PGB10AC001" and ev.size() == 8 and ev[7] == me)
	if last.is_empty() or last[-1][4] != "refused" or not last[-1][5].has("where"):
		p.append("the trainee's op from the screens on a local-only valve was not refused for its where: %s" % str(last))
	ui.close_screens()
	# the same op from a card in the control room with the screens closed: made from the screens (`screen`)
	ui.go_control_room(false)
	var o2: Dictionary = {}
	for x in ui.model.ops:
		if x["kks"] == "30PAC10AA102" and x["do"] == "close":
			o2 = x
	ui.do_op(o2, null)
	ui.clock.run_steps(1)
	var made = e.events.filter(func(ev): return ev[1] == "op" and ev[2] == "30PAC10AA102" and ev.size() == 8 and ev[7] == me)
	if made.is_empty() or made[-1][6] != "screen":
		p.append("an op from a card in the control room was not made from the screens: %s" % str(made))


## A run with the crews saved and restored: the same at every step after (people, queues, random streams).
func _save(ui, p: Array) -> void:
	var m = ui.model
	var e = PlantEngine.new(m, "shift_cold")
	e.role("a_fo_st")
	e.step(3500)
	e.fault("cw_b_motor")
	e.step(200)
	var fields := RunSave.engine_fields(e)
	for f in ["sp_cur", "sp_queue", "sp_pos", "sp_rng", "st_trainee", "J", "npc_queue"]:
		if not f in fields:
			p.append("the save leaves out the staff's %s" % f)
	var data := RunSave.capture(e, fields)
	var f2 = PlantEngine.new(m, "shift_cold")
	var bad := RunSave.check(f2, RunSave.engine_fields(f2), data)
	if bad != "":
		p.append("a fresh engine refuses a save with staff: " + bad)
		return
	RunSave.apply(f2, bytes_to_var(var_to_bytes(data)))
	for k in 600:
		e.step()
		f2.step()
	if var_to_bytes(e.snapshot()) != var_to_bytes(f2.snapshot()) or var_to_bytes(e.events) != var_to_bytes(f2.events):
		p.append("the restored run with staff differs from the uninterrupted one")
