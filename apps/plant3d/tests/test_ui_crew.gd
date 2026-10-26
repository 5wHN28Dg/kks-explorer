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


## The Crew panel rebuilt from the engine as it is now, whatever its own signature says (the panel's buttons are
## looked for in it). Only where the step needs the panel: forced every round, it took most of the test's time.
static func _fresh(ui) -> void:
	ui.crew._sig = ""
	ui.crew.refresh()


## Plays the trainee's current step as a trainee would from the Crew panel; true when something was done.
func _play(ui, readings: Dictionary) -> bool:
	var e = ui.clock.engine
	var sm = e._sm
	var pi: int = e.st_trainee
	if e.st_unacked > 0:
		_fresh(ui)                      # (rebuilt every round before: an alarm seen without waiting for the panel's own refresh)
		var seen := App.find_button(ui.crew, "Seen")
		if seen:
			seen.pressed.emit()
	var cur = e.sp_cur[pi]
	if cur == null:
		return false
	ui.crew.refresh()       # every state the panel passes through drawn, as the app does (its signature); forced below
	var s: Dictionary = sm.tasks[cur["task"]]["steps"][cur["step"]]
	if s.has("go") or s.has("meet"):
		var dest = cur["st"].get("dest", cur["st"].get("place"))
		if dest != null and e.st_t_at != dest:
			_fresh(ui)
			var b := App.find_button(ui.crew, "Take me there")
			if b == null:
				return false
			b.pressed.emit()
			ui._place_tick()
			return true
	elif s.has("read"):
		_fresh(ui)
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
	elif s.has("ppe"):
		# the role's PPE put on at the locker before the handover (milestone S2)
		_fresh(ui)
		var b := App.find_button(ui.crew, "Put it on")
		if b == null:
			b = App.find_button(ui.crew, "Take me to a locker")
			if b == null:
				return false
			b.pressed.emit()
			ui._place_tick()
			return true
		b.pressed.emit()
		return true
	elif s.has("say"):
		_fresh(ui)
		App.find_button(ui.crew, "Send").pressed.emit()
		return true
	elif s.has("choose"):
		ui.clock.engine.pick(0)
		return true
	return false


func _steps(tree: SceneTree, ui, readings: Dictionary, until: Callable, limit: int) -> bool:
	for i in limit:
		if until.call():
			return true
		_play(ui, readings)
		ui.clock.run_steps(10)
		if i % 8 == 0:
			await tree.process_frame       # the panels' old rows are freed at a frame's end: with S2's crowd they
			                               # filled 3.5 GB in a loop without frames
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
	if not await _steps(tree, ui, readings, round_done, 2500):
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
	await _steps(tree, ui, readings, called, 300)
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
	if not await _steps(tree, ui, readings, checked, 1500):
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
	# their avatars (milestone A1): one person each, at the marker's place, a built look by role, what they do
	var av = ui.people.avatars
	if av == null:
		p.append("the crews are drawn as avatars (app/people.gd), not capsules")
	else:
		ui.people.drive(1.0 / 60.0)
		if av.people.size() != ui.people.shown or ui.people.capsules.multimesh.instance_count != 0:
			p.append("each person on the map is one avatar, no capsules (%d avatars, %d markers)" % [av.people.size(), ui.people.shown])
		var doing := {}
		for q in av.people:
			if not av.info.looks.has(q.look) or not (q.at is Vector3) or q.at == Vector3.INF:
				p.append("an avatar has a built look and a place (%s)" % str(q))
				break
			doing[q.anim if q.speed == 0.0 else "walking"] = true
		if doing.size() < 2:
			p.append("the crews are seen doing more than one thing (%s)" % str(doing.keys()))
		p.append_array(_on_line(ui, e))
		var sm = e._sm
		for c in [[{"read": "x"}, "inspect"], [{"work": 5, "anim": "write"}, "write"], [{"work": 5}, "use"],
				[{"op": {"where": ["screen"]}}, "type"], [{"say": "m"}, "radio"], [{"meet": {}}, "talk"]]:
			var task_id: String = sm.tasks.keys()[0]
			var saved = e.sp_cur[0]
			var saved_steps = sm.tasks[task_id]["steps"]
			sm.tasks[task_id]["steps"] = [c[0]]
			e.sp_cur[0] = {"task": task_id, "step": 0}
			var got: String = ui.people._anim(e, sm, 0, -1)
			sm.tasks[task_id]["steps"] = saved_steps
			e.sp_cur[0] = saved
			if got != c[1]:
				p.append("a step %s is seen as %s (%s)" % [str(c[0]), c[1], got])
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
	await _steps(tree, ui, {}, done, 1500)
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
	# what each one of the crews is seen doing is worked out once a step (people_view.gd _anim_of): steps later, and on
	# a frame after the first of a step, the same as worked out afresh
	var av = ui.people.avatars
	if av != null:
		var anims := func(): return av.people.map(func(q): return "%s/%s/%s" % [q.at, q.anim, q.speed])
		ui.people.drive(1.0 / 60.0)
		var before: Array = anims.call()
		ui.clock.run_steps(300)
		ui.people.drive(1.0 / 60.0)
		ui.people.drive(1.0 / 60.0)
		var cached: Array = anims.call()
		ui.people._step_n = -1
		ui.people.drive(1.0 / 60.0)
		var fresh: Array = anims.call()
		if cached != fresh:
			p.append("what the crews are seen doing, kept through a step, is not what they do (%s, not %s)" % [cached, fresh])
		if cached == before:
			p.append("300 steps later the crews are all as they were (the check above proves nothing)")
	# the radio's new lines are written into the lines shown, the panel not built again (crew_panel.gd _radio_lines)
	ui.open_crew()
	ui.crew._sig = ""
	ui.crew.refresh()
	var radio_n: int = ui.crew._radio.size()
	var labs: Array = ui.crew._radio_labels.duplicate()
	var sig0: String = ui.crew._sig
	for i in 300:
		ui.clock.run_steps(10)
		ui.crew.refresh()
		if ui.crew._radio.size() > radio_n:
			break
	if ui.crew._radio.size() == radio_n:
		p.append("no new line on the radio in 3000 steps (the check below proves nothing)")
	else:
		var last_line: String = ui.crew._radio[-1]
		if not App.texts(ui.crew).contains(last_line):
			p.append("the radio's newest line is not on the panel: %s" % last_line)
		if labs.size() == ui.crew.RADIO_LINES and ui.crew._sig == sig0 and ui.crew._radio_labels != labs:
			p.append("the panel was built again for a new line on the radio")
	# what the trainee's part shows besides the radio still follows the run: its header's clock, a clock minute later
	ui.clock.run_steps(100)
	ui.crew.refresh()
	if not App.texts(ui.crew).contains(ui.clock_text()):
		p.append("the Crew panel's header does not show the clock a minute later (%s)" % ui.clock_text())


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
	# a reaction on a value's offer kept after its job was abandoned (PLANT3D §17.12): a save with one is taken, one
	# that names another value than its reaction's is refused
	var sm = e._sm
	var ri := -1
	for i in sm.reactions.size():
		if sm.reactions[i]["on"].has("value"):
			ri = i
			break
	if ri == -1:
		p.append("no reaction on a value in shift_cold's staff")
		return
	var r: Dictionary = sm.reactions[ri]
	var v: String = r["on"]["value"]
	var key := "%d|value|%s" % [ri, v]
	var w = r.get("work")
	var kept := [key, key, r["roles"].duplicate(), r["task"], sm.prio_of(r["task"]), w,
			m.works[m.work_ix[w]]["kks"] if w != null else null, null, v]
	var with_kept := data.duplicate(true)
	with_kept["st_pending"] = [kept]
	var f3 = PlantEngine.new(m, "shift_cold")
	var why: String = ui.autosave._engine_contents(f3, with_kept)
	if why != "":
		p.append("a save with a reaction on a value's kept offer was refused: %s" % why)
	else:
		RunSave.apply(f3, bytes_to_var(var_to_bytes(with_kept)))
		f3.step(50)                 # (react() reads it every step: no error)
	# a job whose source or caller names no reaction on a value (an edited save) is abandoned without an offer kept
	for bad_inst in [{"src": "zz|value|nope", "orig": null}, {"src": null, "orig": "x"},
			{"src": "%d|value|no_such_value" % ri, "orig": null}]:
		var n_kept: int = f3.st_pending.size()
		sm.value_again(f3, bad_inst)
		if f3.st_pending.size() != n_kept:
			p.append("a job from no reaction on a value kept an offer: %s" % str(bad_inst))
	var wrong := kept.duplicate()
	wrong[8] = "no_such_value"
	with_kept["st_pending"] = [wrong]
	if ui.autosave._engine_contents(PlantEngine.new(m, "shift_cold"), with_kept) == "":
		p.append("a save whose kept offer names a value its reaction is not on was taken")


## A person a quarter of the way down the HRSG's stair way is drawn on the way's built line (app/staff_ways.gd), walked
## from the end the leg starts at, facing along it, at the line's speed: not on the straight line from its foot to its
## top, which ran up to 30 m above the ground (until 2026-10-26).
func _on_line(ui, e) -> Array:
	var pv = ui.people
	var sm = e._sm
	if pv.ways == null:
		return ["the people view has no built lines (app/staff_ways.gd)"]
	var ia: int = sm.pix["p_h_foot"]
	var ib: int = sm.pix["p_h_30"]
	var key: int = mini(ia, ib) * sm.places.size() + maxi(ia, ib)
	var st: int = sm.ways[key]
	var who := -1
	for pi in sm.people.size():
		if pi != e.st_trainee and e.sp_pos[pi] != -1 and e.sp_leg[pi].is_empty():
			who = pi
			break
	if who == -1:
		return ["nobody standing to put on the stair way"]
	var saved_leg = e.sp_leg[who]
	var done: int = st / 4
	e.sp_leg[who] = [ib, ia, e.step_no - done, e.step_no - done + st]
	pv.drive(0.0)
	var frac: float = clampf(ui.clock.acc / SimClock.STEP, 0.0, 1.0)
	var k := (float(done) + frac) / float(st)
	pv.ways.walk(key, ib, k, st * SimClock.STEP)
	var want: Vector3 = pv.ways.pos
	var chord: Vector3 = pv._at[ib].lerp(pv._at[ia], k)
	var d: Vector3 = pv.ways.dir
	var yaw := atan2(-d.x, -d.z)
	var found := false
	for q in pv.avatars.people:
		if q.at.distance_to(want) < 0.01 and q.speed > 0.0 and absf(q.speed - pv.ways.speed) < 1e-4 and \
				(Vector2(d.x, d.z).length() <= 0.05 or absf(angle_difference(q.yaw, yaw)) < 0.01):
			found = true
	e.sp_leg[who] = saved_leg
	pv.drive(0.0)
	var out: Array = []
	if not found:
		out.append("nobody is drawn at %s a quarter of the way down the HRSG's stair way's line, facing along it (the straight line's point: %s)" % [
				str(want), str(chord)])
	if want.distance_to(chord) < 1.0:
		out.append("the stair way's line is within 1 m of the straight line a quarter of the way (%s, %s)" % [str(want), str(chord)])
	# walked from the other end, the same moment is somewhere else (the leg's start is its first place)
	pv.ways.walk(key, ia, k, st * SimClock.STEP)
	if pv.ways.pos.distance_to(want) < 1.0:
		out.append("the stair way's line walked from either end is at the same place a quarter of the way")
	return out

