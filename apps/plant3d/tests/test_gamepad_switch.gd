## Gamepad or touch (the user, 2026-10-26: "when I connect a gamepad to the android version the app should hide on
## screen controls and switch to gamepad controls"; app/input_mode.gd, app/hud.gd):
##   mode        a gamepad connecting, or one connected at the start, or its button or a stick pushed past half way
##               makes it the controls in use; stick drift does not; a new touch makes the touch screen the controls
##               again (a finger already down moving does not); the last gamepad disconnecting does too, one of two
##               does not; a key or a mouse button does on a desktop, not on a phone
##   hud         on a touch screen with the settings' Automatic: the sticks, Fly, Use and the flying buttons hide while
##               the gamepad is in use, the bar names its buttons and a line shows them; a touch brings them back,
##               the gamepad hides them again, the last gamepad disconnecting brings them back
##   settings    Always shows the sticks with a gamepad in use, Never hides them without one; the old saved values
##               keep their meaning ("on" Always, "off" Never), unknown ones read as Automatic, a hand-edited bool as
##               its nearest; the settings panel shows the saved choice and says how the three behave; Map and
##               Settings stay in place when Fly and Use hide or come back (the switching tap lands where it began)
##   no stuck    a touch stick held by a thumb when a gamepad press hides it lets its actions go (Godot's
##               VirtualJoystick would keep walking), while a key held for the same action stays pressed; the touch
##               that brings the sticks back reaches them; a key let go after the switch lets its action go
##   focus       panels opened while touching took no focus: when the gamepad becomes the controls the top panel
##               (or the settings panel, or the saved run's offer at the start) takes it, so that the D-pad and A
##               work it at once; the press that switched neither moves that focus on nor does its own job
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const InputMode = preload("res://app/input_mode.gd")
const Player = preload("res://app/player.gd")
const Autosave = preload("res://ui/autosave.gd")
const RunSave = preload("res://ui/run_save.gd")


func run(tree: SceneTree) -> Array:
	var p: Array = mode(tree)
	p.append_array(await offer(tree))
	var main := App.start(tree)
	if main.ui == null or main.ui.clock == null:
		main.free()
		return p + ["the app did not start"]
	await tree.process_frame
	var hud = main.hud
	var touch0 = main.cf.get_value("controls", "touch", null)
	var size0: Vector2i = tree.root.size
	tree.root.size = Vector2i(1280, 720)             # (the headless window is 64 px: the sticks would be outside it)
	hud.touch_screen = true                          # (headless has no touch screen)
	main.cf.set_value("controls", "touch", "auto")
	hud.input.keys_count = true                      # (as on a desktop; the phone's case is in mode())
	if hud.input == null or not hud.input.is_inside_tree() or hud.input.get_parent() != tree.root:
		p.append("the input mode is not under the window's root (it must see events before the panels)")
	p.append_array(hud_switch(main))
	p.append_array(settings(main))
	p.append_array(await no_stuck(tree, main))
	p.append_array(await focus(tree, main))
	Input.joy_connection_changed.emit(41, false)
	Input.joy_connection_changed.emit(42, false)
	hud.touch_screen = DisplayServer.is_touchscreen_available()
	if touch0 == null:
		main.cf.erase_section_key("controls", "touch")
	else:
		main.cf.set_value("controls", "touch", touch0)
	tree.root.size = size0
	var input = hud.input
	main.free()
	await tree.process_frame
	if is_instance_valid(input):
		p.append("the input mode outlived the app")
	return p


## The saved run offered at the start, opened while touching: the gamepad taking over gives Continue the focus.
func offer(tree: SceneTree) -> Array:
	var p: Array = []
	var main := App.start(tree)
	if main.ui == null or main.ui.autosave == null or not main.ui.autosave.save_now():
		main.free()
		return ["the run was not saved for the offer"]
	main.free()
	main = App.start(tree)
	await tree.process_frame
	var ui = main.ui
	if not ui.autosave.offering():
		main.free()
		return ["a saved run was not offered at start"]
	main.hud.touch_screen = true
	await tree.process_frame
	var fo := tree.root.gui_get_focus_owner()
	if fo:
		fo.release_focus()
	Input.joy_connection_changed.emit(43, true)
	fo = tree.root.gui_get_focus_owner()
	if fo == null or not (fo is Button and fo.text == "Continue"):
		p.append("the saved run's offer when the gamepad took over: the focus is on %s, not Continue" % fo)
	Input.joy_connection_changed.emit(43, false)
	App.find_button(ui, "New run").pressed.emit()
	await tree.process_frame
	main.free()
	RunSave.remove(Autosave.default_path)       # (the app saves as it goes: the next start must offer nothing)
	return p


static func _button(pressed: bool, b := JOY_BUTTON_A, device := 41) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.device = device
	e.button_index = b
	e.pressed = pressed
	return e


static func _axis(axis: int, v: float, device := 41) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.device = device
	e.axis = axis
	e.axis_value = v
	return e


static func _touch(at: Vector2, pressed := true, index := 0) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = at
	e.pressed = pressed
	return e


func mode(tree: SceneTree) -> Array:
	var p: Array = []
	var m := InputMode.new()
	m.scan()
	if m.pad != not Input.get_connected_joypads().is_empty():
		p.append("at the start the gamepad is in use exactly when one is connected")
	m.pads[5] = true                                 # one connected at the start
	m.pad = true
	tree.root.add_child(m)
	var seen: Array = []
	m.changed.connect(func(on): seen.append(on))
	m.note(_touch(Vector2(10, 10)))
	if m.pad or seen != [false]:
		p.append("a touch did not make the touch screen the controls (%s)" % str(seen))
	m.note(_axis(JOY_AXIS_LEFT_X, 0.3))
	m.note(_axis(JOY_AXIS_TRIGGER_RIGHT, 0.2))
	m.note(_button(false))
	if m.pad:
		p.append("stick drift, a resting trigger or a button's release made the gamepad the controls")
	m.note(_axis(JOY_AXIS_LEFT_Y, -0.8))
	if not m.pad:
		p.append("a stick pushed most of the way did not make the gamepad the controls")
	m.note(_touch(Vector2(10, 10), false))
	if not m.pad:
		p.append("a finger lifted (no new touch) took the controls from the gamepad")
	var drag := InputEventScreenDrag.new()
	m.note(drag)
	if not m.pad:
		p.append("a finger already down moving took the controls from the gamepad (only a new touch does)")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	m.keys_count = false
	m.note(key)
	if not m.pad:
		p.append("on a phone a key took the controls from the gamepad")
	m.keys_count = true
	var emulated := InputEventMouseButton.new()
	emulated.device = InputEvent.DEVICE_ID_EMULATION
	emulated.pressed = true
	m.note(emulated)
	if not m.pad:
		p.append("a mouse click made from a touch counted as the mouse")
	m.note(key)
	if m.pad:
		p.append("on a desktop a key did not take the controls from the gamepad")
	m.note(_button(true))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	m.note(click)
	if m.pad:
		p.append("on a desktop a mouse click did not take the controls from the gamepad")
	m.note(_button(true, JOY_BUTTON_DPAD_UP))
	if not m.pad:
		p.append("a D-pad press did not make the gamepad the controls")
	m.note(_touch(Vector2(10, 10)))
	Input.joy_connection_changed.emit(6, true)
	if not m.pad or not m.pads.has(6):
		p.append("a gamepad connecting did not make it the controls")
	Input.joy_connection_changed.emit(6, false)
	if not m.pad:
		p.append("one of two gamepads disconnecting took the controls from the other")
	Input.joy_connection_changed.emit(5, false)
	Input.joy_connection_changed.emit(41, false)     # (the device the presses above came from)
	if m.pad:
		p.append("the last gamepad disconnecting left the gamepad the controls")
	m.free()
	return p


func hud_switch(main) -> Array:
	var p: Array = []
	var hud = main.hud
	hud.input.note(_touch(Vector2(5, 5)))
	hud.refresh()
	if not hud.sticks.all(func(s): return s.visible):
		p.append("Automatic on a touch screen without a gamepad hides the sticks")
	if not hud.fly_btn.visible or not hud.use_btn.visible or hud.pad_hint.visible:
		p.append("without a gamepad Fly and Use show and the gamepad's line does not")
	Input.joy_connection_changed.emit(42, true)
	if hud.sticks.any(func(s): return s.visible) or hud.fly_btn.visible or hud.use_btn.visible:
		p.append("a gamepad connecting left the touch controls shown")
	if not hud.pad_hint.visible or not hud.pad_hint.text.contains("Y fly") or not hud.pad_hint.text.contains("Start settings"):
		p.append("a gamepad connecting did not show its buttons (%s)" % hud.pad_hint.text)
	if not main.ui.wants_focus():
		p.append("with the gamepad in use the panels do not take the focus")
	main.player.mode = Player.Mode.FLY
	hud.refresh()
	if hud.updown.any(func(b): return b.visible) or not hud.pad_hint.text.contains("RB up"):
		p.append("flying with the gamepad: the up and down buttons show, or its line does not name RB and LB")
	main.player.mode = Player.Mode.WALK
	hud.refresh()
	hud.map_btn.get_parent().notification(Container.NOTIFICATION_SORT_CHILDREN)   # (the layout, as at the next frame)
	var rects: Array = [hud.map_btn.get_global_rect(), hud.settings_btn.get_global_rect()]
	hud.input.note(_touch(Vector2(5, 5)))
	if not hud.sticks.all(func(s): return s.visible) or hud.pad_hint.visible:
		p.append("touching the screen with a gamepad connected did not bring the touch controls back")
	hud.map_btn.get_parent().notification(Container.NOTIFICATION_SORT_CHILDREN)   # (the layout, as at the next frame)
	if [hud.map_btn.get_global_rect(), hud.settings_btn.get_global_rect()] != rects:
		p.append("Map or Settings moved when Fly and Use came back: %s, then %s" % [rects,
				[hud.map_btn.get_global_rect(), hud.settings_btn.get_global_rect()]])
	if main.ui.wants_focus():
		p.append("touching again, the panels still take the focus")
	hud.input.note(_axis(JOY_AXIS_RIGHT_X, 0.9, 42))
	if hud.sticks.any(func(s): return s.visible):
		p.append("the gamepad used after a touch left the sticks shown")
	Input.joy_connection_changed.emit(42, false)
	if not hud.sticks.all(func(s): return s.visible) or hud.pad_hint.visible:
		p.append("the last gamepad disconnecting did not bring the touch controls back")
	return p


func settings(main) -> Array:
	var p: Array = []
	var hud = main.hud
	Input.joy_connection_changed.emit(42, true)
	main.cf.set_value("controls", "touch", "on")
	hud.refresh()
	if not hud.sticks.all(func(s): return s.visible) or not hud.fly_btn.visible:
		p.append("touch controls Always: hidden with a gamepad in use")
	Input.joy_connection_changed.emit(42, false)
	main.cf.set_value("controls", "touch", "off")
	hud.refresh()
	if hud.sticks.any(func(s): return s.visible):
		p.append("touch controls Never: the sticks show")
	for c in [["on", "on"], ["off", "off"], ["auto", "auto"], [true, "on"], [false, "off"], ["sometimes", "auto"], [3, "auto"]]:
		main.cf.set_value("controls", "touch", c[0])
		if hud.touch_setting() != c[1]:
			p.append("a saved touch setting %s reads as %s, not %s" % [str(c[0]), hud.touch_setting(), c[1]])
		hud.show_settings(true)
		if hud.touch_opt.selected != hud.TOUCH.find(c[1]):
			p.append("the settings show item %d for a saved %s" % [hud.touch_opt.selected, str(c[0])])
		hud.show_settings(false)
	var note: Label = hud.panel.find_child("touch_note", true, false)
	if note == null or not (note.text.contains("Automatic:") and note.text.contains("Always:") and note.text.contains("Never:")
			and note.text.contains("gamepad")):
		p.append("the settings do not say how Automatic, Always and Never behave with a gamepad")
	hud.show_settings(true)
	hud.touch_opt.select(1)
	hud.touch_opt.item_selected.emit(1)
	if main.cf.get_value("controls", "touch") != "on":
		p.append("choosing Always saved %s" % str(main.cf.get_value("controls", "touch")))
	hud.show_settings(false)
	main.cf.set_value("controls", "touch", "auto")
	hud.refresh()
	return p


func no_stuck(tree: SceneTree, main) -> Array:
	var p: Array = []
	var hud = main.hud
	hud.input.note(_touch(Vector2(5, 5)))
	hud.refresh()
	var stick: VirtualJoystick = hud.sticks[0]
	var at := stick.get_global_rect().get_center()
	# a thumb on the move stick, pushed forward; W held as well
	Input.parse_input_event(_touch(at))
	await tree.process_frame
	await tree.process_frame
	var d := InputEventScreenDrag.new()
	d.position = at - Vector2(0, 200)
	d.relative = Vector2(0, -1)
	Input.parse_input_event(d)
	await tree.process_frame
	await tree.process_frame
	if Input.get_action_strength("move_forward") <= 0.0:
		p.append("the touch stick dragged forward does not press move_forward (the test's touch missed it?)")
	Input.parse_input_event(_button(true, JOY_BUTTON_Y))     # a gamepad press, the thumb still down
	Input.parse_input_event(_button(false, JOY_BUTTON_Y))
	await tree.process_frame
	if stick.visible:
		p.append("a gamepad press left the touch stick shown")
	if Input.is_action_pressed("move_forward"):
		p.append("the touch stick hidden under a thumb still presses move_forward: the walker walks on")
	await tree.process_frame
	if Input.is_action_pressed("move_forward"):
		p.append("the hidden touch stick pressed move_forward again a frame later")
	Input.parse_input_event(_touch(at - Vector2(0, 200), false))
	await tree.process_frame
	if main.player.mode == Player.Mode.FLY:
		main.player.toggle_fly()                     # (Y flew)
	# a key held for the same action when the gamepad hides the stick: it stays pressed
	Input.parse_input_event(_touch(at))
	await tree.process_frame
	if not stick.visible:
		p.append("the touch did not bring the sticks back")
	Input.parse_input_event(d)
	await tree.process_frame
	await tree.process_frame
	if Input.get_action_strength("move_forward") <= 0.0:
		p.append("the touch that brought the sticks back (and its drag) did not reach the stick")
	var w := InputEventKey.new()
	w.physical_keycode = KEY_W
	w.pressed = true
	Input.parse_input_event(w)
	Input.parse_input_event(_axis(JOY_AXIS_TRIGGER_LEFT, 0.9))
	await tree.process_frame
	if stick.visible:
		p.append("a trigger pulled left the touch stick shown")
	if not Input.is_action_pressed("move_forward"):
		p.append("W held while the gamepad hid the touch stick was let go too")
	w.pressed = false
	Input.parse_input_event(w)
	Input.parse_input_event(_axis(JOY_AXIS_TRIGGER_LEFT, 0.0))
	Input.parse_input_event(_touch(at - Vector2(0, 200), false))
	await tree.process_frame
	if Input.is_action_pressed("move_forward"):
		p.append("move_forward still pressed after W and the thumb let go")
	# no thumb, W held when a gamepad press hides the sticks, then W let go: the walker stops
	Input.parse_input_event(_touch(Vector2(5, 5)))
	Input.parse_input_event(_touch(Vector2(5, 5), false))
	w.pressed = true
	Input.parse_input_event(w)
	Input.parse_input_event(_button(true, JOY_BUTTON_RIGHT_SHOULDER))
	Input.parse_input_event(_button(false, JOY_BUTTON_RIGHT_SHOULDER))
	await tree.process_frame
	w.pressed = false
	Input.parse_input_event(w)
	await tree.process_frame
	if Input.is_action_pressed("move_forward"):
		p.append("W let go after the gamepad hid the sticks: move_forward stays pressed")
	# a flying button held when the gamepad takes over
	main.player.mode = Player.Mode.FLY
	hud.input.note(_touch(Vector2(5, 5)))
	hud.refresh()
	var up: Button = hud.updown[0]
	up.button_down.emit()
	if not Input.is_action_pressed("up"):
		p.append("the Up button does not press up")
	hud.input.note(_button(true, JOY_BUTTON_START))
	if up.visible or Input.is_action_pressed("up"):
		p.append("the Up button held when the gamepad took over keeps up pressed")
	main.player.mode = Player.Mode.WALK
	Input.joy_connection_changed.emit(41, false)
	hud.refresh()
	return p


func focus(tree: SceneTree, main) -> Array:
	var p: Array = []
	var hud = main.hud
	var ui = main.ui
	var vp: Viewport = tree.root
	for which in ["alarms", "procedure", "crew", "settings"]:
		hud.input.note(_touch(Vector2(5, 5)))
		var fo := vp.gui_get_focus_owner()
		if fo:
			fo.release_focus()
		var box: Control
		match which:
			"alarms":
				ui.toggle_alarms(); box = ui.alarms
			"procedure":
				ui.toggle_procedure(); box = ui.procedure
			"crew":
				ui.toggle_crew(); box = ui.crew
			"settings":
				hud.show_settings(true); box = hud.panel
		await tree.process_frame
		fo = vp.gui_get_focus_owner()
		if fo:
			fo.release_focus()                       # (as a touch device leaves it)
		var speed0 = ui.clock.speed
		Input.parse_input_event(_button(true, JOY_BUTTON_DPAD_DOWN))      # (D-pad down: ui_down, and pause)
		Input.parse_input_event(_button(false, JOY_BUTTON_DPAD_DOWN))
		await tree.process_frame
		fo = vp.gui_get_focus_owner()
		if fo == null or not box.is_ancestor_of(fo):
			p.append("%s open when the gamepad took over: the focus is on %s, not in the panel" % [which, fo])
		elif which == "alarms" and fo != ui.alarms._tabs[ui.alarms.tab]:
			p.append("the press that switched moved the alarm list's focus on, to %s" % fo)
		elif which == "settings" and fo != hud.about_btn:
			p.append("the press that switched moved the settings' focus on, to %s" % fo)
		if ui.clock.speed != speed0:
			p.append("the D-pad press that switched (with %s open) also paused or ran the plant" % which)
		if which == "settings":
			hud.show_settings(false)
		else:
			ui.close_top()
		Input.joy_connection_changed.emit(41, false)
	return p
