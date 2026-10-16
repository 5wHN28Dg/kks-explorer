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


static func vectors() -> Dictionary:
	var path := ProjectSettings.globalize_path("res://").path_join("../../ref/vectors/plant3d-v1.json").simplify_path()
	var r := JsonStrict.parse(FileAccess.get_file_as_bytes(path), 1000)
	return r.value if r.ok else {}


static func row_of(card, d: Dictionary) -> Array:
	for row in card._ops:
		var o: Dictionary = row[0]
		if o["kks"] == d["kks"] and o["do"] == d["do"] and o.get("trip") == d.get("trip"):
			return row
	return []


static func find_button(n: Node, text: String) -> Button:
	for c in n.get_children():
		if c is Button and c.text == text and c.visible:
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


func run(tree: SceneTree) -> Array:
	var p: Array = []
	var V := vectors()
	if V.is_empty():
		return ["cannot read ref/vectors/plant3d-v1.json"]
	var t: Dictionary = V["train"]
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
			if where.has("screen"):
				if not ui.in_control_room():
					find_button(ui.root, "Control room").pressed.emit()
			ui.open_card(d["kks"])
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
			if ui.clock.speed == SimClock.Speed.PAUSED:
				if ui.clock.ff_blocked() == "":
					find_button(ui.root, "Fast").pressed.emit()
				else:
					find_button(ui.root, "1×").pressed.emit()
			elif ui.clock.speed == SimClock.Speed.NORMAL and ui.clock.ff_blocked() == "":
				find_button(ui.root, "Fast").pressed.emit()
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
		print("  cold start through the UI: %d steps of model time (%s), %d operations, %d procedure steps" % [e.step_no,
				ui.clock.clock_text(), e.inputs.size(), ui.tracker.log.size()])
	main.free()
	return p


static func _first_diff(a: Array, b: Array) -> String:
	for i in mini(a.size(), b.size()):
		if var_to_str(a[i]) != var_to_str(b[i]):
			return "item %d: %s, the reference %s" % [i, str(a[i]), str(b[i])]
	return "%d items, the reference %d" % [a.size(), b.size()]
