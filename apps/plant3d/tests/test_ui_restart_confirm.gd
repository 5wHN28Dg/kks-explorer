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
	var keep0: Button = tp.body.find_child("keep_run", true, false)
	ui.clock.run_steps(600)              # the plant goes on while asked: the time lost said grows with it
	await _wait_ms(tree, 650)
	tp.refresh()
	await tree.process_frame
	go = tp.body.find_child("confirm_restart", true, false)
	if go == null or go.disabled:
		p.append("Restart is still not pressable after half a second")
	if tp.body.find_child("keep_run", true, false) != keep0:
		p.append("arming Restart rebuilt the panel (a press under way on Keep the run would be lost)")
	q = tp.body.find_child("restart_question", true, false)
	if q == null or not q.text.contains(W.model_time(ui.clock.engine.step_no)):
		p.append("the question's plant time did not follow the plant (%s): %s" % [W.model_time(ui.clock.engine.step_no), q.text if q else ""])
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
	# 5. gamepad: A on Restart in it asks, A again keeps the run; then Escape closes the panel, which keeps the run and drops the
	# question (reopened, none)
	var first2: String = ui.clock.scenario
	if not tp.visible:
		ui.toggle_trainer()
		await tree.process_frame
	var other2 := ""
	for id in ui.info.m.scenarios:
		if id != first2 and other2 == "":
			other2 = id
	var rb2: Button = tp.body.find_child("restart_" + other2, true, false)
	rb2.grab_focus()
	_joy(tree, JOY_BUTTON_A)         # (the first press of a pad makes it the controls, and does nothing else)
	await tree.process_frame
	if tp.body.find_child("restart_question", true, false) == null:
		(tp.body.find_child("restart_" + other2, true, false) as Button).grab_focus()
		_joy(tree, JOY_BUTTON_A)
		await tree.process_frame
	if tp.body.find_child("restart_question", true, false) == null or _focus(ui) != "keep_run":
		p.append("gamepad A on Restart in it did not ask with Keep the run focused (focus %s)" % _focus(ui))
	_joy(tree, JOY_BUTTON_A)
	await tree.process_frame
	if tp.body.find_child("restart_question", true, false) != null or ui.clock.scenario != first2:
		p.append("gamepad A on Keep the run did not keep the run")
	(tp.body.find_child("restart_" + other2, true, false) as Button).pressed.emit()
	await tree.process_frame
	_key(tree, KEY_ESCAPE)
	await tree.process_frame
	if tp.visible or ui.clock.scenario != first2:
		p.append("Escape while asked did not close the panel and keep the run (visible %s, %s)" % [tp.visible, ui.clock.scenario])
	ui.toggle_trainer()
	await tree.process_frame
	if tp.body.find_child("restart_question", true, false) != null:
		p.append("the question came back when the panel was opened again")
	# 6. touch: a tap on Restart in it asks, and takes no focus (no panel takes it on touch)
	main.hud.touch_screen = true
	var fo: Control = ui.get_viewport().gui_get_focus_owner()
	if fo != null:
		fo.release_focus()
	(tp.body.find_child("restart_" + other2, true, false) as Button).pressed.emit()   # (a tap)
	await tree.process_frame
	if tp.body.find_child("restart_question", true, false) == null:
		p.append("a tap on Restart in it asked nothing")
	if _focus(ui) == "keep_run":
		p.append("on touch the question took the focus (no other panel does)")
	main.hud.touch_screen = false
	# 7. in a session: refused as before, with no question
	var fake := GDScript.new()
	fake.source_code = "extends RefCounted\nfunc active() -> bool:\n\treturn true\n"
	fake.reload()
	var was = ui.session
	ui.session = fake.new()
	tp.asking = ""
	ui._toast.visible = false
	tp.ask_restart(other2)
	var refused: bool = ui._toast.visible and ui._toast.text.begins_with("Not while a session is open")
	ui.session = was
	if not refused or tp.asking != "" or ui.clock.scenario != first2:
		p.append("in a session Restart in it was not refused as before (asking %s)" % tp.asking)
	main.free()
	return p


static func _joy(tree: SceneTree, b: JoyButton) -> void:
	var j := InputEventJoypadButton.new()
	j.pressed = true
	j.button_index = b
	tree.root.push_input(j)
	var up: InputEventJoypadButton = j.duplicate()
	up.pressed = false
	tree.root.push_input(up)
