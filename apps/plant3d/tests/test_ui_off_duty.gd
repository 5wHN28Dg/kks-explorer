## The trainee off duty and the debrief per role (docs/PLANT3D.md §21.7, milestone S4c):
## - crew A's CW field operator works the day shift and at 18:00 goes home (walking instead of the bus); off duty,
##   the Crew panel says so, shows the off-duty task (a meal, free time, sleep) and keeps "Sleep to the next shift";
## - the trainee's tasks begun are recorded with when each was given (ui/plant_ui.gd task_given), and the debrief's
##   role tab marks a task begun more than 15 clock minutes after it was given as late;
## - after the jump to the next shift, the role tab lists the slots the jump went past: the off-duty ones (sleep,
##   breakfast) as not made while the trainee slept, the duty's before the shift (the bus, the handover) as covered by
##   the crew on duty.
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const SimClock = preload("res://ui/sim_clock.gd")
const Debrief = preload("res://ui/debrief.gd")


func run(tree: SceneTree) -> Array:
	var p: Array = []
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null or not ui.model.scenarios.has("shift_cold"):
		main.free()
		return ["the app or its scenario with the crews (shift_cold) did not start"]
	ui.player.set_physics_process(false)
	ui.start_shift("shift_cold")
	await tree.process_frame
	# crew A's CW field operator, on the day shift (06:00 to 18:00)
	var b := App.find_button(ui.crew, "Play Field CW, crew A…")
	if b == null:
		var t0 := App.texts(ui.crew).left(300)
		main.free()
		return ["the shift's start offers no crew A CW field operator: %s" % t0]
	b.pressed.emit()
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	var e = ui.clock.engine
	var me: int = e.trainee()
	var sm = e._sm
	var off_task := ""
	for i in 9000:
		var cur = e.sp_cur[me]
		if not e.sp_on[me] and e.step_no > 6000 and cur != null and Debrief._off_task(sm, me, cur["task"]) and not cur["idle"]:
			off_task = cur["task"]
			break
		_play(ui, e, me)
		ui.clock.run_steps(10)
		if i % 8 == 0:
			await tree.process_frame       # (the panels' old rows are freed at a frame's end)
	if off_task == "":
		var cur = e.sp_cur[me]
		var msg := "the trainee never had an off-duty task after the night shift (now %s, on duty %s, the task %s step %s, at %d)" % [
				ui.clock_text(), str(e.sp_on[me]), str(cur["task"]) if cur else "none", str(cur["step"]) if cur else "-", e.sp_pos[me]]
		main.free()
		return [msg]
	ui.crew._sig = ""
	ui.crew.refresh()
	var t := App.texts(ui.crew)
	if not t.contains("off duty"):
		p.append("off duty, the Crew panel does not say so: %s" % t.left(200))
	if not t.contains(sm.tasks[off_task]["title"]):
		p.append("off duty, the Crew panel does not show the off-duty task %s" % off_task)
	if App.find_button(ui.crew, "Sleep to…") == null:
		p.append("off duty, the Crew panel has no \"Sleep to the next shift\"")
	# the tasks begun, with when they were given
	if ui.task_given.is_empty():
		p.append("none of the trainee's tasks begun was recorded with when it was given")
	var key := ""
	for k in ui.task_given:
		var at := int(String(k).get_slice("|", 0))
		if int(ui.task_given[k]) > at:
			p.append("a task given after it was begun: %s at %d" % [k, int(ui.task_given[k])])
		key = k
	# a task begun 20 clock minutes after it was given: late in the role tab
	if key != "":
		var given: Dictionary = ui.task_given.duplicate()
		given[key] = int(String(key).get_slice("|", 0)) - 1200 * 10 / e._ds
		var d := Debrief.collect(e, ui.info, null, ui.inputs.slot, given)
		var late: Array = d["entries"].filter(func(x): return x.kind == "task" and String(x.text).contains("LATE"))
		if late.size() != 1 or d["summary"]["late"] != 1:
			p.append("the role tab does not mark the one task begun late: %s" % str(late).left(300))
		var d0 := Debrief.collect(e, ui.info, null, ui.inputs.slot, ui.task_given)
		for x in d0["entries"]:
			if x.kind == "task" and String(x.text).contains("LATE"):
				p.append("a task begun when given is marked late: %s" % x.text)
	# sleep to the next shift (the jump input, as the button sends it), as soon as the plant allows it (no alarm new to
	# anyone, no permit open, PLANT3D §17.6)
	var n0: int = e.events.size()
	var jumped := false
	for i in 200:
		_play(ui, e, me)
		if e.unacked() > 0:
			ui.inputs.task_ack()
		ui.inputs.jump(ui.crew._next_shift(e))
		ui.clock.run_steps(2)
		for k in range(n0, e.events.size()):
			if e.events[k][1] == "jump" and e.events[k][4] == "done":
				jumped = true
		if jumped:
			break
		ui.clock.run_steps(100)
		if i % 8 == 0:
			await tree.process_frame
	if not jumped:
		var msg := "the jump to the next shift was never allowed: %s" % str(e.events.slice(n0).filter(func(x): return x[1] == "jump")).left(300)
		main.free()
		return p + [msg]
	var d2 := Debrief.collect(e, ui.info, null, ui.inputs.slot, ui.task_given)
	var slept: Array = d2["entries"].filter(func(x): return x.kind == "task" and String(x.text).begins_with("While you slept"))
	if slept.is_empty():
		p.append("the role tab lists none of the slots the jump went past")
	# each in its words: an off-duty slot (a meal, sleep) not made, a duty's (before the shift: the bus, the handover)
	# covered by the crew on duty
	# (a task the trainee had begun and not ended when the jump came: left unfinished)
	var begun := {}
	var not_made := 0
	for k in e.events.size():
		var ev: Array = e.events[k]
		if ev[1] != "task" or ev[2] != sm.people[me]["id"]:
			continue
		var was: int = begun.get(ev[3], 0)
		if ev[4] in ["start", "resumed"]:
			begun[ev[3]] = was + 1
		elif ev[4] in ["done", "abandoned", "skipped", "held"] and was > 0:
			begun[ev[3]] = was - 1
		if k < n0 or ev[4] != "skipped":
			continue
		var title: String = sm.tasks[ev[3]]["title"]
		var want := "left unfinished" if was > 0 else ("not made" if Debrief._off_task(sm, me, ev[3]) else "covered by the crew on duty")
		not_made += 1 if want == "not made" else 0
		if not slept.any(func(x): return String(x.text).contains(title) and String(x.text).ends_with(want)):
			p.append("the role tab does not list the skipped %s as %s" % [ev[3], want])
	if not_made == 0:
		p.append("the jump went past none of the off-duty slots (sleep, breakfast)")
	main.free()
	return p


static func _play(ui, e, me: int) -> void:
	if e.unacked() > 0:
		ui.inputs.task_ack()
	var cur = e.sp_cur[me]
	if cur == null:
		return
	var s: Dictionary = e._sm.tasks[cur["task"]]["steps"][cur["step"]]
	if s.has("ride") or s.has("go") or s.has("meet"):
		ui.crew._sig = ""
		ui.crew.refresh()
		for t in ["Walk instead", "Take me there"]:
			var b := App.find_button(ui.crew, t)
			if b != null:
				b.pressed.emit()
				ui._place_tick()
				return
	elif s.has("read"):
		ui.crew._sig = ""
		ui.crew.refresh()
		if ui.crew.entry != null:
			ui.crew.entry.text = "%.3f" % e.shown(s["read"], e.cur)
			var w := App.find_button(ui.crew, "Write down")
			if w != null:
				w.pressed.emit()
	elif s.has("ppe"):
		ui.crew._sig = ""
		ui.crew.refresh()
		for t in ["Put it on", "Take me to a locker"]:
			var b := App.find_button(ui.crew, t)
			if b != null:
				b.pressed.emit()
				ui._place_tick()
				return
	elif s.has("say"):
		ui.crew._sig = ""
		ui.crew.refresh()
		var b := App.find_button(ui.crew, "Send")
		if b != null:
			b.pressed.emit()
	elif s.has("choose"):
		e.pick(0)
