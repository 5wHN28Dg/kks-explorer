## The instructor's "Restart in it" asks first (issue #437; the user's UI-UX policy S1, S2): the run in progress is
## lost, so the row asks, naming the scenario to start, the one running and the plant time lost;
## - nothing restarts until "Restart" is pressed: "Keep the run" (focused, where "Restart in it" was) keeps it;
## - "Restart" is styled destructive and can't be pressed in its first half second (a double press, a held key);
## - by keyboard: Enter on "Restart in it" asks, a second Enter keeps the run; Down to "Restart", Enter restarts;
## - pressed after that, the plant restarts in the scenario, at its start.
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const W = preload("res://ui/widgets.gd")


static func _key(tree: SceneTree, code: Key) -> void:
	var k := InputEventKey.new()
	k.pressed = true
	k.physical_keycode = code
	k.keycode = code
	tree.root.push_input(k)
	var up: InputEventKey = k.duplicate()
	up.pressed = false
	tree.root.push_input(up)


static func _focus(ui) -> String:
	var f: Control = ui.get_viewport().gui_get_focus_owner()
	return String(f.name) if f != null else ""


## Frames until `ms` of real time have passed (the question's guard is in real time).
static func _wait_ms(tree: SceneTree, ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await tree.process_frame


func run(tree: SceneTree) -> Array:
	var p: Array = []
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null:
		main.free()
		return ["the interaction layer did not start"]
	await tree.process_frame
	var first: String = ui.clock.scenario
	var other := ""
	for id in ui.info.m.scenarios:
		if id != first and other == "":
			other = id
	if other == "":
		main.free()
		return ["the content has only one scenario"]
	var title_other: String = ui.info.m.scenarios[other].get("title", other)
	var title_first: String = ui.info.m.scenarios[first].get("title", first)
	ui.clock.run_steps(600)              # a run in progress: a minute of plant time
	var steps: int = ui.clock.engine.step_no
	ui.set_instructor(true)
	ui.toggle_trainer()
	var tp = ui.trainer
	var rb: Button = null                # (found by what it shows: the scenario's row's Restart in it)
	for row in tp.body.get_children():
		if row is HBoxContainer and App.texts(row).contains(title_other):
			rb = App.find_button(row, "Restart in it")
	if rb == null:
		main.free()
		return ["the instructor's panel has no Restart in it for %s" % other]
	# 1. pressed: a question, nothing restarted
	rb.pressed.emit()
	await tree.process_frame
	var q: Label = tp.body.find_child("restart_question", true, false)
	if ui.clock.scenario != first or ui.clock.engine.step_no != steps:
		p.append("Restart in it restarted at once (now %s at step %d)" % [ui.clock.scenario, ui.clock.engine.step_no])
	if q == null:
		var shown := App.texts(tp.body).left(300)
		main.free()
		return p + ["Restart in it asked nothing: %s" % shown]
	for t in [title_other, title_first, W.model_time(steps), "lost"]:
		if not q.text.contains(t):
			p.append("the question does not say %s: %s" % [t, q.text])
	var keep: Button = tp.body.find_child("keep_run", true, false)
	var go: Button = tp.body.find_child("confirm_restart", true, false)
	if keep == null or go == null:
		main.free()
		return p + ["the question has no Keep the run or no Restart"]
	if _focus(ui) != "keep_run":
		p.append("the focus is on %s, not Keep the run (the safe choice)" % _focus(ui))
	if not App.texts(keep.get_parent()).contains(title_other):
		p.append("Keep the run is not in the scenario's row, where Restart in it was")
	var sb = go.get_theme_stylebox("normal")
	if not (sb is StyleBoxFlat and (sb as StyleBoxFlat).bg_color.is_equal_approx(W.DESTRUCTIVE)):
		p.append("Restart is not styled destructive")
	if not go.disabled:
		p.append("Restart can be pressed at once (a double press would restart)")
	go.pressed.emit()                    # (even pressed in its first half second: nothing)
	await tree.process_frame
	if ui.clock.scenario != first or ui.clock.engine.step_no != steps:
		p.append("Restart pressed at once restarted the plant")
	# 2. Keep the run: the question goes, the run stays, the focus back on Restart in it
	keep = tp.body.find_child("keep_run", true, false)
	keep.pressed.emit()
	await tree.process_frame
	if tp.body.find_child("restart_question", true, false) != null:
		p.append("Keep the run left the question")
	if ui.clock.scenario != first or ui.clock.engine.step_no != steps:
		p.append("Keep the run did not keep the run")
	if _focus(ui) != "restart_" + other:
		p.append("after Keep the run the focus is on %s, not Restart in it" % _focus(ui))
	# 3. keyboard: Enter asks; a second Enter (a held key) lands on Keep the run
	_key(tree, KEY_ENTER)
	await tree.process_frame
	await tree.process_frame
	if tp.body.find_child("restart_question", true, false) == null:
		p.append("Enter on Restart in it asked nothing")
	_key(tree, KEY_ENTER)
	await tree.process_frame
	await tree.process_frame
	if ui.clock.scenario != first or tp.body.find_child("restart_question", true, false) != null:
		p.append("a second Enter did not keep the run (scenario %s)" % ui.clock.scenario)
	# 4. asked again, after half a second: Down to Restart, Enter restarts in it, at its start
	_key(tree, KEY_ENTER)
	await tree.process_frame
	await _wait_ms(tree, 650)
	tp.refresh()
	await tree.process_frame
	go = tp.body.find_child("confirm_restart", true, false)
	if go == null or go.disabled:
		p.append("Restart is still not pressable after half a second")
	_key(tree, KEY_DOWN)
	await tree.process_frame
	if _focus(ui) != "confirm_restart":
		p.append("Down from Keep the run went to %s, not Restart" % _focus(ui))
	_key(tree, KEY_ENTER)
	await tree.process_frame
	await tree.process_frame
	if ui.clock.scenario != other or ui.clock.engine.step_no != 0:
		p.append("Restart did not restart in %s (now %s at step %d)" % [other, ui.clock.scenario, ui.clock.engine.step_no])
	if tp.visible and tp.body.find_child("restart_question", true, false) != null:
		p.append("the question stayed after the restart")
	main.free()
	return p
