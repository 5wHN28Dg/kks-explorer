## Discussions in the app (docs/plant3d/REALISM.md §6.3.1, milestone DC3), text only:
## - the first train's discussions.json read by the engine (five, each with its lead's task);
## - a trainee control room operator in the control room when the shift supervisor's fan 7 alarm meeting starts
##   there: they take part (mode open); the crew panel shows the discussion (the positions, the opening lines, the
##   point's options with their evidence and the time it ends at); the operator's pick taken as theirs, the agreement
##   reached and its outcome task given to the lead; the lines in the radio log; the panel kept with the agreement
##   until closed;
## - the debrief's list: the discussion, who took which option, the outcome;
## - a saved run's discussions checked against the content; a session carries the input as three texts.
## The engine's own rules are the vectors' (plant3d-realism.json, part discuss); here the app's side.
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const SimClock = preload("res://ui/sim_clock.gd")
const Debrief = preload("res://ui/debrief.gd")
const Discussions = preload("res://ui/discussions.gd")
const InputCheck = preload("res://net/input_check.gd")

const DID := "ct_fan7_alarm"
const FAULT := "ct_fan7_chatter"


func run(tree: SceneTree) -> Array:
	var p: Array = []
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null or not ui.model.scenarios.has("shift_cold"):
		main.free()
		return ["the app or its scenario with the crews (shift_cold) did not start"]
	ui.player.set_physics_process(false)
	var sc: Dictionary = ui.model.scenarios["shift_cold"].duplicate(true)
	sc["id"] = "test_discuss"
	sc["start"] = {"day": 1, "time": "08:00"}
	ui.model.scenarios["test_discuss"] = sc
	ui.start_shift("test_discuss")
	await tree.process_frame
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	var e = ui.clock.engine
	var sm = e._sm
	if sm == null or sm.discuss == null or sm.discuss["list"].size() != 5:
		main.free()
		return ["the first train's discussions.json was not read: %s" % str(sm.discuss if sm != null else null)]
	for d in sm.discuss["list"]:
		if not sm.tasks.has("dsc_" + d["id"]):
			p.append("discussion %s has no lead's task" % d["id"])
	# an operator on duty plays; they go to a free desk in the control room
	var op := -1
	for pi in sm.people.size():
		if sm.people[pi]["role"] == "ccr_op" and e.sp_on[pi]:
			op = pi
			break
	if op == -1:
		main.free()
		return p + ["no control room operator on duty at 08:00"]
	ui.take_role(sm.people[op]["id"])
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	if e.trainee() != op:
		main.free()
		return p + ["the operator was not taken"]
	var desk := ""
	for i in sm.rooms["control_room"]:
		if sm.kind[i] == "desk" and not e.st_holder.has(i):
			desk = sm.places[i]["id"]
			break
	if e.sp_pos[op] == -1 or not sm.rooms["control_room"].has(e.sp_pos[op]):
		ui.inputs.send(["arrive", desk if desk != "" else sm.places[sm.door["control_room"]]["id"]])
	ui.inputs.send(["fault", FAULT])
	var di: int = sm.discuss["ix"][DID]
	for _i in 2000:
		ui.clock.run_steps(10)
		if not e.dsc[di].is_empty():
			break
	if e.dsc[di].is_empty():
		main.free()
		return p + ["the fan 7 meeting never started (%s)" % ui.clock_text()]
	var x: Dictionary = e.dsc[di]
	if x["mode"] != 1 or not x["parts"].has(op):
		p.append("the operator in the control room should take part, mode open: %s" % str(x))
	ui.crew.refresh()
	await tree.process_frame
	# a rebuild of the crew panel for something else keeps the discussion's part as it was (the Note 9's frames)
	var kept = ui.crew._disc_node
	ui.crew._sig = ""
	ui.crew.refresh()
	if kept == null or ui.crew._disc_node != kept or not kept.is_inside_tree():
		p.append("the discussion's part was built again by an unrelated rebuild")
	# the panel is built in parts: a change found by its own timer builds only the parts it touched, one a frame
	# (the Note 9: a whole rebuild took 35 to 55 ms of scripts there, frames over 100 ms)
	var crew = ui.crew
	var parts: Dictionary = crew.get("_parts") if crew.get("_parts") != null else {}
	var task_label = parts["task"].get_child(0) if parts.has("task") and parts["task"].get_child_count() > 0 else null
	var n0: int = crew.get("built_parts") if crew.get("built_parts") != null else 0
	if crew.get("_part_keys") != null:
		crew._part_keys["disc"] = "stale"
		crew._part_keys["day"] = "stale"
	crew._sig = "stale"
	if crew.has_method("_build_part"):
		crew.refresh(true)
	else:
		crew.refresh()
	var built0: int = crew.get("built_parts") if crew.get("built_parts") != null else -1
	if built0 != n0 + 1 or crew.get("_pending") != ["day"] or crew._disc_node == kept:
		p.append("a change of two parts found by the timer should build the first now, the other next: %d %s" % [
				built0 - n0, str(crew.get("_pending"))])
	if task_label == null or not is_instance_valid(task_label) or not task_label.is_inside_tree():
		p.append("the task's part was built again though its key had not changed")
	await tree.process_frame
	await tree.process_frame
	var built1: int = crew.get("built_parts") if crew.get("built_parts") != null else -1
	if built1 != n0 + 2 or crew.get("_pending") != []:
		p.append("the other part should be built in the next frame: %d %s" % [built1 - n0, str(crew.get("_pending"))])
	var txt: String = App.texts(ui.crew)
	var d: Dictionary = sm.discuss["list"][di]
	for want in ["Discussion: " + d["title"], d["positions"][0]["claim"], d["turns"][0]["text"], "until ",
			"Standard [ISA182]"]:
		if not txt.contains(want):
			p.append("the crew panel should show «%s»: %s" % [want, txt.left(1200)])
	var b = ui.crew.find_child("disc_now", true, false)
	if b == null or not b is Button:
		main.free()
		return p + ["no option button for «now»: %s" % txt.left(800)]
	b.emit_signal("pressed")
	ui.clock.run_steps(2)
	var mine: Array = e.events.filter(func(v): return v[1] == "discuss")
	if mine.size() != 1 or mine[0].slice(2) != [sm.people[op]["id"], DID, "limit", "now", "done", []]:
		p.append("the operator's pick should be done: %s" % str(mine))
	var ag: Array = e.events.filter(func(v): return v[1] == "discussion" and v[3] == "agreed")
	var want_task = null
	for a in d["agreements"]:
		var ok := true
		for t in a["when"]:
			if (t.has("point") and t["option"] != "now") or (t.has("value") and e.truth(t["value"]) != t["is"]):
				ok = false
		if ok:
			want_task = a["outcome"].get("task")
			break
	if ag.size() != 1 or ag[0][5] != want_task:
		p.append("the agreement on «now» should give %s: %s" % [str(want_task), str(ag)])
	# the radio log carries the lines, the agreement's outcome too
	ui.crew.refresh()
	await tree.process_frame
	var radio := "\n".join(ui.crew._radio)
	var a_text: String = d["agreements"][ag[0][4] if not ag.is_empty() else 0]["outcome"]["text"]
	for want in [d["turns"][0]["text"], "Agreed: " + a_text]:
		if not radio.contains(want):
			p.append("the radio log should carry «%s»: %s" % [want, radio.right(800)])
	# the ended discussion stays on the panel while the operator is in the room, until closed
	txt = App.texts(ui.crew)
	if not txt.contains(a_text):
		p.append("the panel should show the agreement's outcome: %s" % txt.left(800))
	var close = ui.crew.find_child("disc_close", true, false)
	if close == null:
		p.append("no Close on the ended discussion")
	else:
		close.emit_signal("pressed")
		await tree.process_frame
		if App.texts(ui.crew).contains("Discussion: " + d["title"]):
			p.append("the closed discussion is still on the panel: %s %s" % [str(ui.crew._disc_closed), App.texts(ui.crew).left(600)])
	# the debrief's list
	var lines: PackedStringArray = Discussions.debrief_lines(sm, Discussions.review(e))
	var all := "\n".join(lines)
	if lines.size() < 2 or not lines[0].begins_with("Discussions: ") or not all.contains(d["title"]) \
			or not all.contains(sm.people[op]["call"]) or not all.contains(a_text):
		p.append("the debrief should list the discussion, the operator's pick and the outcome: %s" % all)
	var dsum: Dictionary = Debrief.collect(e, ui.info, null)
	if not "\n".join(Debrief.summary_lines(dsum)).contains(d["title"]):
		p.append("the debrief's summary should carry the discussions")
	p += _saves(ui)
	p += _forms()
	p += _shown_prefers_own()
	p += _bad_events(ui)
	main.free()
	return p


## A saved run's discussions are checked against the content (ui/autosave.gd, sim/discuss.gd contents).
func _saves(ui) -> Array:
	var p: Array = []
	var pl: Dictionary = ui.autosave.payload()
	var why: String = ui.autosave.check(pl)
	if why != "":
		return ["a run with a discussion was refused: " + why]
	var good: Array = pl["engine"]["dsc"]
	var di := -1
	for k in good.size():
		if not good[k].is_empty():
			di = k
	if di == -1:
		return ["the saved run has no discussion"]
	var bads := [[], good + [{}], [1]]
	for change in [{"lead": 9999}, {"mode": 2}, {"agreed": 99}, {"parts": PackedInt32Array([0])},
			{"opt": PackedInt32Array([7])}, {"count": 0}, {"point": 9}, {"by": [0]}]:
		var g: Array = good.duplicate(true)
		g[di].merge(change, true)
		bads.append(g)
	# a lead (and first participant) not of the lead's role, a participant twice: each would wait on the other
	var op: int = ui.my_person()
	var g1: Array = good.duplicate(true)
	g1[di]["lead"] = op
	g1[di]["parts"][0] = op
	bads.append(g1)
	var g2: Array = good.duplicate(true)
	g2[di]["parts"][1] = g2[di]["parts"][2]
	bads.append(g2)
	for bad in bads:
		var d: Dictionary = pl.duplicate(true)
		d["engine"]["dsc"] = bad
		if ui.autosave.check(d) == "":
			p.append("a save with the discussions %s was accepted" % str(bad))
	return p


## A session carries the pick (MULTIPLAYER.md §3.3): three texts, nothing else.
func _forms() -> Array:
	var p: Array = []
	for x in [[["discuss", DID, "limit", "now"], true], [["discuss", DID, "limit", 1], false],
			[["discuss", DID, "limit"], false], [["discuss", DID, "limit", null], false]]:
		if InputCheck.form_ok(x[0]) != x[1]:
			p.append("the session's check of %s: %s" % [str(x[0]), not x[1]])
	return p


## Two live discussions in one room: the panel shows the one the trainee takes part in, not the first in file order
## they are only in the room of (the blind review's finding).
func _shown_prefers_own() -> Array:
	var tasks := {"a_lead": {"steps": [{"discuss": "a"}]}, "b_lead": {"steps": [{"discuss": "b"}]}}
	var inst := func(t): return {"task": t, "step": 0}
	var mk := func(lead: int, parts: Array):
		return {"count": 1, "lead": lead, "parts": PackedInt32Array(parts), "mode": 1, "start": 1, "point": 0,
				"since": 1, "opt": PackedInt32Array([-1]), "by": PackedInt32Array([-1]), "agreed": -1}
	var sm := {"discuss": {"list": [{"id": "a", "room": "r"}, {"id": "b", "room": "r"}], "ix": {"a": 0, "b": 1}},
			"rooms": {"r": PackedInt32Array([5])}, "tasks": tasks}
	var e := {"_sm": sm, "dsc": [mk.call(0, [0, 1]), mk.call(2, [2, 3])], "sp_pos": PackedInt32Array([5, 5, 5, 5]),
			"sp_cur": [inst.call("a_lead"), null, inst.call("b_lead"), null], "sp_queue": [[], [], [], []],
			"sp_held": [[], [], [], []]}
	var got: int = Discussions.shown(e, 3, {})
	return [] if got == 1 else ["a participant of the second live discussion is shown discussion %d" % got]


## A saved run's events are checked only loosely (ui/autosave.gd): malformed discussion events are passed over by the
## panel's lines and the debrief's list, not a crash.
func _bad_events(ui) -> Array:
	var e = ui.clock.engine
	var sm = e._sm
	var keep: int = e.events.size()
	for ev in [[1, "discussion", DID], [1, "discussion", DID, "agreed", 99, null], [1, "point", DID, "limit"],
			[1, "point", "nope", "limit", "now", null], [1, "discussion", DID, "start", "x", "y", "open"],
			[1, "point", DID, 3, "now", null]]:
		e.events.append(ev)
	var got := Discussions.review(e)
	var lines := Discussions.event_lines(sm, [1, "discussion", DID, "agreed", 99, null], {})
	e.events.resize(keep)
	return [] if got.size() == Discussions.review(e).size() and lines.is_empty() else ["malformed events were read: %s" % str(got)]
