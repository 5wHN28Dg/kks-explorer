## The cold start a trainee performs (docs/plant3d/FIRST-TRAIN.md §4), driven through the interaction layer only:
## the procedure is started from the procedure panel; for each step the trainee goes where the operation is offered
## (the control room for the screens, the equipment for its local controls, by the card's "Go there"), opens the
## equipment's card, types the value where the step asks for one and presses the operation's button; then runs the
## plant with the time bar (fast-forward where it is allowed, 1× otherwise) until the step is done, with "Pause when
## a step is done" ticked. At base load the engine's trace must be the reference's (ref/vectors/plant3d-v1.json
## `train`, made by ref/plant3d.py): the same inputs at the same steps, the same events, the step at which each
## procedure step ended, and the final state to the vector file's precision.
extends RefCounted

const JsonStrict = preload("res://sim/json_strict.gd")
const SimClock = preload("res://ui/sim_clock.gd")
const W = preload("res://ui/widgets.gd")


static func vectors(file := "plant3d-v1.json") -> Dictionary:
	var path := ProjectSettings.globalize_path("res://").path_join("../../ref/vectors/" + file).simplify_path()
	var r := JsonStrict.parse(FileAccess.get_file_as_bytes(path), 1000)
	return r.value if r.ok else {}


static func row_of(card, d: Dictionary) -> Array:
	for row in card._ops:
		var o: Dictionary = row[0]
		if o["kks"] == d["kks"] and o["do"] == d["do"] and o.get("trip") == d.get("trip"):
			return row
	return []


## A visible button that can be pressed (a disabled one is a failure: the trainee couldn't press it).
static func find_button(n: Node, text: String) -> Button:
	for c in n.get_children():
		if c is Button and c.text == text and c.visible:
			assert(not c.disabled, "%s is disabled" % text)
			return c
		var f := find_button(c, text)
		if f:
			return f
	return null


## Waits until the trainee's flight to a part has ended.
static func settle(tree: SceneTree, ui) -> void:
	for i in 600:
		if not ui.player.scripted:
			return
		await tree.process_frame


## The screens' way (tests/test_ui_screens_cold_start.gd): every operation the control room offers is made from its
## screen (ui/mimic.gd): the screen with the equipment, a click on it, its card; the local ones as before.
var via_screens := false

## Another start (tests/test_ui_wtp_start.gd): the vector file and its run, and the operator desk whose screens work
## it ("" the main control room's, by its button). A run whose scenario is not the app's start is begun from the
## procedure panel's "Start from there (the plant restarts)".
var vector_file := "plant3d-v1.json"
var run_key := "train"
var desk := ""


## Opens a code's card from the control room screens as a trainee does: the screens on, the code's screen, a click
## on its symbol. "" when the card is open, else what went wrong.
static func _from_screen(tree: SceneTree, ui, code: String) -> String:
	if not ui.screens_open():
		find_button(ui.root, "Control room").pressed.emit()
	if not ui.screens_open():
		ui.control_room()
	if not ui.screens_open():
		return "the screens did not open in the control room"
	var at = ui.screens.screen_of.get(code)
	if at == null:
		return "%s is on no screen" % code
	var mim = ui.mimic
	mim.show_screen(at[0])
	await tree.process_frame
	mim.select(code)
	await tree.process_frame
	var c: Vector2 = mim.target_centre(code)
	if not Rect2(Vector2.ZERO, mim.canvas.size).has_point(c):
		return "%s is not in view on its screen (%s)" % [code, str(c)]
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = c
		mim._canvas_input(ev)
	return "" if ui.card.visible and ui.card.code == code else "a click on %s did not open its card" % code


func run(tree: SceneTree) -> Array:
	var p: Array = []
	var V := vectors(vector_file)
	if V.is_empty():
		return ["cannot read ref/vectors/" + vector_file]
	var t: Dictionary = V[run_key]
	var main: Node = (load("res://app/main.tscn") as PackedScene).instantiate()
	tree.root.add_child(main)
	var ui = main.ui
	if ui == null or ui.clock == null:
		main.free()
		return ["the interaction layer did not start: %s" % (ui.error if ui else "no ui")]
	# before the first frame: the plant stands at step 0, as the reference's run begins
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	if ui.clock.engine.step_no != 0:
		p.append("the plant ran before the test could pause it")
	# model time runs fast for the test (the trace depends on the steps at which the trainee acts, not on how fast
	# the frames come); the cap on the model's share of a core is lifted for the same reason
	Engine.time_scale = 400.0
	ui.clock.max_frame = 30.0
	ui.clock.cpu_share = 1.0
	await tree.process_frame
	# the procedure from its panel
	ui.toggle_procedure()
	var row_btn: Button = null
	var title: String = ui.model.procedures[t["procedure"]]["title"]
	for row in ui.procedure.body.get_children():
		if row is HBoxContainer and row.get_child_count() == 2 and (row.get_child(0) as Label).text.begins_with(title):
			row_btn = row.get_child(1)
	if row_btn == null:
		p.append("the procedure list has no Start for %s" % title)
		main.free()
		Engine.time_scale = 1.0
		return p
	row_btn.pressed.emit()
	if ui.clock.scenario != t["scenario"]:
		# the panel asks first: the plant restarts at the procedure's scenario, still paused at its step 0
		find_button(ui.procedure, "Start from there (the plant restarts)").pressed.emit()
		ui.clock.set_speed(SimClock.Speed.PAUSED)
		if ui.clock.scenario != t["scenario"] or ui.clock.engine.step_no != 0:
			p.append("the plant did not restart at %s, step 0" % t["scenario"])
	if ui.tracker == null or ui.tracker.index != 0:
		main.free()
		Engine.time_scale = 1.0
		return p + ["Start did not begin the procedure at its first step"]
	ui.procedure.pause_box.button_pressed = true
	if not ui.clock.pause_on_hold:
		p.append("ticking \"Pause when a step is done\" did not reach the clock")
	var guard := 0
	while ui.tracker.index >= 0 and p.is_empty():
		var s: Dictionary = ui.tracker.current()
		for d in s.get("do", []):
			var o: Dictionary = ui.model.op_keys[ui.model.op_key(d["kks"], d["do"], d.get("trip"))]
			var where: Array = o.get("where", ["local", "screen"])
			if where.has("screen") and desk != "":
				if not ui.screen_reach(d["kks"]):
					ui.fly_to(desk)            # the desk's own control room (the water treatment plant's)
					await settle(tree, ui)
				if not ui.screen_reach(d["kks"]):
					p.append("step %s: %s is not on the screens at %s (%.1f m from it)" % [s["id"], d["kks"], desk,
							ui.distance_to(desk)])
					break
			elif where.has("screen"):
				if not ui.in_control_room():
					find_button(ui.root, "Control room").pressed.emit()
			if via_screens and where.has("screen"):
				var why := await _from_screen(tree, ui, d["kks"])
				if why != "":
					p.append("step %s: %s" % [s["id"], why])
					break
			else:
				ui.procedure._link("kks:" + d["kks"])      # the code as linked in the step's checklist
			if not ui.card.visible or ui.card.code != d["kks"]:
				p.append("step %s: the step's link did not open the card of %s" % [s["id"], d["kks"]])
				break
			if not where.has("screen"):
				var go := find_button(ui.card, "Go there")
				if go == null:
					p.append("step %s: the card of %s has no Go there" % [s["id"], d["kks"]])
					break
				go.pressed.emit()
				await settle(tree, ui)
				if not ui.near(d["kks"]):
					p.append("step %s: Go there left the trainee %.1f m from %s" % [s["id"], ui.distance_to(d["kks"]), d["kks"]])
					break
				ui.card.refresh()
			var row := row_of(ui.card, d)
			if row.is_empty():
				p.append("step %s: the card of %s has no %s" % [s["id"], d["kks"], d["do"]])
				break
			if (row[1] as Button).disabled:
				p.append("step %s: %s %s is not offered where the trainee stands" % [s["id"], d["kks"], d["do"]])
				break
			if d.has("value"):
				var entry: LineEdit = row[4]
				# what the trainee types: per cent for a 0–1 command, the number itself otherwise
				entry.text = str(int(round(float(d["value"]) * 100.0))) if o["range"] == [0, 1] else str(d["value"])
			(row[1] as Button).pressed.emit()
			var res: Dictionary = ui.op_result(o)
			if res.get("state", "") != "sent":
				p.append("step %s: pressing %s %s did not send it (%s)" % [s["id"], d["kks"], d["do"], str(res)])
		if not p.is_empty():
			break
		# run: fast-forward where allowed, else 1×; the clock pauses itself when the step is done
		var idx: int = ui.tracker.index
		while ui.tracker.index == idx and p.is_empty():
			# as a trainee: Fast when the button can be pressed, else 1×
			var fast: Button = ui._ff_btn
			if ui.clock.speed != SimClock.Speed.FAST and not fast.disabled:
				find_button(ui.root, "Fast").pressed.emit()
			elif ui.clock.speed == SimClock.Speed.PAUSED:
				find_button(ui.root, "1×").pressed.emit()
			await tree.process_frame
			guard += 1
			if guard > 200000:
				p.append("step %s did not end" % s["id"])
		if ui.clock.speed != SimClock.Speed.PAUSED and ui.tracker.index >= 0:
			p.append("the clock did not pause when step %s was done" % s["id"])
		for d in s.get("do", []):
			var res: Dictionary = ui.op_result(ui.model.op_keys[ui.model.op_key(d["kks"], d["do"], d.get("trip"))])
			if res.get("state", "") != "done":
				p.append("step %s: %s %s came back %s" % [s["id"], d["kks"], d["do"], str(res)])
	Engine.time_scale = 1.0
	var e = ui.clock.engine
	if p.is_empty():
		for chk in [["inputs", e.inputs, t["inputs"]], ["events", e.events, t["events"]],
				["the steps' ends", ui.tracker.log, t["steps"]]]:
			if var_to_str(chk[1]) != var_to_str(chk[2]):
				p.append("%s differ from the reference's: %s" % [chk[0], _first_diff(chk[1], chk[2])])
		if e.step_no != int(t["until"]):
			p.append("ended at step %d, the reference at %d" % [e.step_no, t["until"]])
		var want: Dictionary = t["snapshots"][t["snapshots"].size() - 1]
		var got: Dictionary = e.snapshot()
		for k in ["machines", "tripped", "first_out", "alarms", "shelved"]:
			if var_to_str(got[k]) != var_to_str(want[k]):
				p.append("final %s: %s, the reference %s" % [k, str(got[k]), str(want[k])])
		for k in want["values"]:
			var g: float = got["values"].get(k, NAN)
			var w: float = float(want["values"][k])
			if not absf(g - w) <= 6e-10 + 4.5e-16 * absf(w):
				p.append("final value %s = %s, the reference %s" % [k, g, w])
				break
		if not ui.procedure.visible or ui.tracker.index != -1:
			p.append("the procedure panel does not show the procedure as finished")
		p.append_array(_debrief(ui, e, t))
		print("  %s through the UI: %d steps of model time (%s), %d operations, %d procedure steps" % [t["procedure"], e.step_no,
				ui.clock.clock_text(), e.inputs.size(), ui.run_tracker.log.size()])
	main.free()
	return p


## The end of the procedure: its summary and the debrief (ui/debrief.gd) list what happened, as the reference has it:
## every operation, every step at the model step it ended, nothing outside its step; it stays after the procedure is
## closed (the alarm list's Events).
static func _debrief(ui, e, t: Dictionary) -> Array:
	var p: Array = []
	var shown := ""
	for c in ui.procedure.body.get_children():
		if c is Label:
			shown += c.text + "\n"
	var last := int(t["steps"][t["steps"].size() - 1][1])
	for w in ["Steps: %d of %d done\n" % [t["steps"].size(), t["steps"].size()],
			"Operations: %d done; 0 outside their step" % t["inputs"].size(), "Time: %s of plant time" % W.model_time(last)]:
		if not shown.contains(w):
			p.append("the finished procedure's summary does not say \"%s\": %s" % [w, shown])
	var b := find_button(ui.procedure, "Debrief: every event")
	if b == null:
		return p + ["the finished procedure offers no debrief"]
	b.pressed.emit()
	var d = ui.debrief
	if not d.visible:
		return p + ["the debrief did not open"]
	var ents: Array = d.data["entries"]
	var ops := ents.filter(func(x): return x.kind == "op")
	var steps := ents.filter(func(x): return x.kind == "step")
	if ops.size() != t["inputs"].size() or ops.any(func(x): return x.dev != ""):
		p.append("the debrief lists %d operations (the reference made %d), deviations: %s" % [ops.size(), t["inputs"].size(),
				str(ops.filter(func(x): return x.dev != ""))])
	if steps.size() != t["steps"].size():
		p.append("the debrief lists %d steps done, the reference %d" % [steps.size(), t["steps"].size()])
	else:
		for i in steps.size():
			if steps[i].step != int(t["steps"][i][1]):
				p.append("the debrief has step %d ending at %d, the reference at %s" % [i + 1, steps[i].step, t["steps"][i][1]])
				break
	if ents.size() != t["events"].size() + t["steps"].size() + 1:
		p.append("the debrief has %d rows: %d events, %d steps and its start expected" % [ents.size(), t["events"].size(), t["steps"].size()])
	if d._list.get_child_count() != ents.size():
		p.append("the debrief shows %d rows of %d" % [d._list.get_child_count(), ents.size()])
	ui.stop_procedure()
	ui.close_debrief()
	ui.toggle_alarms()
	find_button(ui.alarms, "Events").pressed.emit()
	if not d.visible or not d.title.text.begins_with("Debrief: " + String(ui.model.procedures[t["procedure"]]["title"])):
		p.append("after the procedure was closed the debrief is not the procedure's: %s" % d.title.text)
	return p


static func _first_diff(a: Array, b: Array) -> String:
	for i in mini(a.size(), b.size()):
		if var_to_str(a[i]) != var_to_str(b[i]):
			return "item %d: %s, the reference %s" % [i, str(a[i]), str(b[i])]
	return "%d items, the reference %d" % [a.size(), b.size()]
