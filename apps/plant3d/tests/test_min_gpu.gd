## The minimum GPU's message (decision 0076, app/min_gpu.gd): with the Compatibility renderer on a desktop the app
## shows it before the plant loads, and the plant loads only after Continue anyway; on a phone, on Forward+ or Mobile,
## for a measurement, or once "Don't show this again" was chosen, it is not shown. Godot's rendering method and the
## device kind are mocked (MinGpu.renderer_override, phone_override): the tests run headless.
extends RefCounted

const MinGpu = preload("res://app/min_gpu.gd")
const Quality = preload("res://app/quality.gd")
const UiApp = preload("res://tests/ui_app.gd")
const SimClock = preload("res://ui/sim_clock.gd")
const W = preload("res://ui/widgets.gd")


func run(tree: SceneTree) -> Array:
	var p: Array = []
	var saved := Quality.settings()
	var had: bool = saved.has_section_key(MinGpu.SECTION, MinGpu.KEY_OFF)
	var was = saved.get_value(MinGpu.SECTION, MinGpu.KEY_OFF, false)
	_forget()
	await _switched_off(tree, p)
	MinGpu.switch_override = 1     # (the owner's check: the message on)
	_when(p)
	await _shown_then_continue(tree, p)
	await _not_again(tree, p)
	_forget()
	await _not_shown(tree, p, "gl_compatibility", 1, "on a phone")
	await _not_shown(tree, p, "forward_plus", 0, "with Forward+")
	await _not_shown(tree, p, "mobile", 0, "with the Mobile renderer")
	await _quit_and_escape(tree, p)
	await _scroll_by_keys(tree, p)
	await _touch(tree, p)
	MinGpu.renderer_override = ""
	MinGpu.phone_override = -1
	MinGpu.switch_override = -1
	_forget()
	if had:
		var cf := Quality.settings()
		cf.set_value(MinGpu.SECTION, MinGpu.KEY_OFF, was)
		Quality.save(cf)
	return p


func _forget() -> void:
	var cf := Quality.settings()
	if cf.has_section_key(MinGpu.SECTION, MinGpu.KEY_OFF):
		cf.erase_section_key(MinGpu.SECTION, MinGpu.KEY_OFF)
		Quality.save(cf)


## Switched off (the project's setting, until the owner's check): no message on a desktop on Compatibility, the plant
## loads at once, as before the change.
func _switched_off(tree: SceneTree, p: Array) -> void:
	if bool(ProjectSettings.get_setting("walkdown/min_gpu_message", true)):
		p.append("the message is switched on in project.godot before the owner's check")
	MinGpu.switch_override = -1
	MinGpu.renderer_override = "gl_compatibility"
	MinGpu.phone_override = 0
	if MinGpu.wanted(ConfigFile.new(), {}):
		p.append("the message is due while switched off")
	var main: Node = UiApp.start(tree)
	if main.get_node_or_null("min_gpu") != null or main.ui == null:
		p.append("switched off, the start is not as before (a message, or the plant not loaded at once)")
	await tree.process_frame
	main.free()


## The rule alone.
func _when(p: Array) -> void:
	var cf := ConfigFile.new()
	var cases := [
		["gl_compatibility", 0, {}, true, "a desktop on Compatibility"],
		["gl_compatibility", 1, {}, false, "a phone on Compatibility"],
		["forward_plus", 0, {}, false, "a desktop on Forward+"],
		["mobile", 0, {}, false, "a desktop on the Mobile renderer"],
		["gl_compatibility", 0, {"walk": "frames"}, false, "a measured walk"],
		["gl_compatibility", 0, {"shot": "a@0,0,0,0,0"}, false, "a shot"],
	]
	for c in cases:
		MinGpu.renderer_override = c[0]
		MinGpu.phone_override = c[1]
		if MinGpu.wanted(cf, c[2]) != c[3]:
			p.append("the message is %s for %s" % ["not due" if c[3] else "due", c[4]])
	MinGpu.renderer_override = "gl_compatibility"
	MinGpu.phone_override = 0
	cf.set_value(MinGpu.SECTION, MinGpu.KEY_OFF, true)
	if MinGpu.wanted(cf, {}):
		p.append("the message is due although \"Don't show this again\" is in the settings")
	# without the mock, the headless tests have no display: never shown
	MinGpu.renderer_override = ""
	if MinGpu.wanted(ConfigFile.new(), {}):
		p.append("the message is due on a headless start")


## A desktop on Compatibility: the message comes before the plant, with its words; "Don't show this again" ticked and
## Continue anyway pressed, the plant loads and the choice is in the settings.
func _shown_then_continue(tree: SceneTree, p: Array) -> void:
	MinGpu.renderer_override = "gl_compatibility"
	MinGpu.phone_override = 0
	var main: Node = UiApp.start(tree)
	var notice = main.get_node_or_null("min_gpu")
	if notice == null:
		main.free()
		p.append("no message on a desktop on the Compatibility renderer")
		return
	if main.plant != null or main.ui != null:
		p.append("the plant was loaded before the message was answered")
	await tree.process_frame
	await tree.process_frame
	var shown := UiApp.texts(notice)
	for w in ["below what Walkdown Plant needs", "run slowly", "about 12 pictures a second", "support Vulkan",
			"Intel HD Graphics 510", "Continue anyway", "Quit", "Don't show this again"]:
		if not shown.contains(w):
			p.append("the message does not say \"%s\"" % w)
	if tree.root.gui_get_focus_owner() != notice.continue_button:
		p.append("Continue anyway does not have the keyboard and gamepad focus")
	var vs: Vector2 = tree.root.get_visible_rect().size
	for c: Control in [notice.continue_button, notice.quit_button, notice.dont_show]:
		var r: Rect2 = c.get_global_rect()
		if r.size.x < 24.0 or r.size.y < 24.0:
			p.append("%s is smaller than 24 x 24 px (%s)" % [c.name, str(r.size)])
		if not Rect2(Vector2.ZERO, vs).encloses(r):
			p.append("%s is off the window (%s in %s)" % [c.name, str(r), str(vs)])
	# by the mouse, as a user does: a click on the box, then on Continue anyway
	await _click(tree, notice.dont_show)
	if not notice.dont_show.button_pressed:
		p.append("a click on \"Don't show this again\" did not tick it")
	await _click(tree, notice.continue_button, false)
	if main.plant != null:
		p.append("the plant loaded inside the button's handler (the answer is given from the next idle time)")
	await tree.process_frame
	if main.plant == null or main.ui == null:
		p.append("the plant did not load after Continue anyway")
	elif main.ui.clock != null:
		main.ui.clock.set_speed(SimClock.Speed.PAUSED)
	if is_instance_valid(notice) and notice.is_inside_tree():
		p.append("the message stays after Continue anyway")
	if not bool(Quality.settings().get_value(MinGpu.SECTION, MinGpu.KEY_OFF, false)):
		p.append("\"Don't show this again\" was not kept in the settings")
	main.free()


## The next start after "Don't show this again": no message, the plant loads at once.
func _not_again(tree: SceneTree, p: Array) -> void:
	var main: Node = UiApp.start(tree)
	if main.get_node_or_null("min_gpu") != null:
		p.append("the message came again after \"Don't show this again\"")
	if main.ui == null:
		p.append("the plant did not load at once after \"Don't show this again\"")
	await tree.process_frame
	main.free()


func _not_shown(tree: SceneTree, p: Array, method: String, phone: int, what: String) -> void:
	MinGpu.renderer_override = method
	MinGpu.phone_override = phone
	var main: Node = UiApp.start(tree)
	if main.get_node_or_null("min_gpu") != null:
		p.append("the message is shown %s" % what)
	if main.ui == null:
		p.append("the plant did not load at once %s" % what)
	await tree.process_frame
	main.free()


## The message alone: Quit answers false and keeps "Don't show this again" only when ticked; Escape is Continue anyway.
func _quit_and_escape(tree: SceneTree, p: Array) -> void:
	for tick in [false, true]:
		_forget()
		var cf := Quality.settings()
		var n = MinGpu.new(cf)
		tree.root.add_child(n)
		await tree.process_frame
		var got := []
		n.answered.connect(func(go): got.append(go))
		n.dont_show.button_pressed = tick
		n.quit_button.pressed.emit()
		await tree.process_frame
		if got != [false]:
			p.append("Quit did not answer quit (%s)" % str(got))
		if bool(Quality.settings().get_value(MinGpu.SECTION, MinGpu.KEY_OFF, false)) != tick:
			p.append("Quit with the box %s left the setting %s" % ["ticked" if tick else "clear",
					"off" if tick else "on"])
		if is_instance_valid(n):
			n.free()
	_forget()
	var n2 = MinGpu.new(Quality.settings())
	tree.root.add_child(n2)
	await tree.process_frame
	var got2 := []
	n2.answered.connect(func(go): got2.append(go))
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	tree.root.push_input(esc)
	await tree.process_frame
	if got2 != [true]:
		p.append("Escape did not continue (%s)" % str(got2))
	await tree.process_frame
	if is_instance_valid(n2):
		n2.free()
	var n3 = MinGpu.new(Quality.settings())
	tree.root.add_child(n3)
	await tree.process_frame
	var got3 := []
	n3.answered.connect(func(go): got3.append(go))
	var b := InputEventJoypadButton.new()
	b.button_index = JOY_BUTTON_B
	b.pressed = true
	tree.root.push_input(b)
	await tree.process_frame
	if got3 != [true]:
		p.append("gamepad B did not continue (%s)" % str(got3))
	await tree.process_frame
	if is_instance_valid(n3):
		n3.free()
	_forget()


## By touch (a desktop's touch screen): a tap on Continue anyway answers continue (Godot's mouse from touch).
func _touch(tree: SceneTree, p: Array) -> void:
	var n = MinGpu.new(ConfigFile.new())
	tree.root.add_child(n)
	for i in 3:
		await tree.process_frame
	var got := []
	n.answered.connect(func(go): got.append(go))
	var at: Vector2 = n.continue_button.get_global_rect().get_center()
	for down in [true, false]:
		var t := InputEventScreenTouch.new()
		t.index = 0
		t.position = at
		t.pressed = down
		tree.root.push_input(t, true)
	await tree.process_frame
	if got != [true]:
		p.append("a tap on Continue anyway did not continue (%s)" % str(got))
	if is_instance_valid(n):
		n.free()


## At UI size 200 % the words don't all fit: the keyboard reaches them (the scroll takes the focus, and the down arrow
## and Page Down scroll it); at 100 % they fit and the scroll takes no focus.
func _scroll_by_keys(tree: SceneTree, p: Array) -> void:
	var size0: Vector2i = tree.root.size
	tree.root.size = Vector2i(1600, 900)     # (a headless window is square: the 16:9 window a desktop has)
	for f in [1.0, 2.0]:
		W.apply_ui_size(tree.root, f)
		var n = MinGpu.new(ConfigFile.new())
		tree.root.add_child(n)
		for i in 4:
			await tree.process_frame
		var bar: VScrollBar = n.scroll.get_v_scroll_bar()
		var overflows: bool = bar.max_value > n.scroll.size.y + 1.0
		if f == 1.0:
			if overflows or n.scroll.focus_mode != Control.FOCUS_NONE:
				p.append("at 100 %% the words don't fit or the scroll takes the focus (%s, %d)" % [str(overflows), n.scroll.focus_mode])
		else:
			if not overflows or n.scroll.focus_mode != Control.FOCUS_ALL:
				p.append("at 200 %% the words that don't fit can't take the focus (%s, %d)" % [str(overflows), n.scroll.focus_mode])
			else:
				n.scroll.grab_focus()
				await tree.process_frame
				for k in [KEY_DOWN, KEY_PAGEDOWN]:
					var ev := InputEventKey.new()
					ev.keycode = k
					ev.physical_keycode = k
					ev.pressed = true
					tree.root.push_input(ev)
					await tree.process_frame
				if n.scroll.scroll_vertical <= 0:
					p.append("at 200 % the down arrow and Page Down did not scroll the words")
				# at the bottom, the D-pad's down leaves the words for the box (no trap for a gamepad: A1)
				for i in 6:
					_joy(tree, JOY_BUTTON_DPAD_DOWN)
					await tree.process_frame
				var fo := tree.root.gui_get_focus_owner()
				if fo == n.scroll or fo == null:
					p.append("at 200 %% the D-pad's down at the words' end does not leave them (focus %s)" % [fo.name if fo else "none"])
				# up again into the words, then Up and Page Up take them back to the very top
				n.scroll.grab_focus()
				n.scroll.scroll_vertical = 30
				await tree.process_frame
				var up := InputEventKey.new()
				up.keycode = KEY_UP
				up.physical_keycode = KEY_UP
				up.pressed = true
				tree.root.push_input(up)
				await tree.process_frame
				if n.scroll.scroll_vertical != 0 or tree.root.gui_get_focus_owner() != n.scroll:
					p.append("Up a little under the top did not scroll the words to the top (at %d)" % n.scroll.scroll_vertical)
				# the window grows while the words have the focus: they stop scrolling, the focus goes to Continue anyway
				W.apply_ui_size(tree.root, 1.0)
				for i in 3:
					await tree.process_frame
				if tree.root.gui_get_focus_owner() != n.continue_button:
					var fo2 := tree.root.gui_get_focus_owner()
					p.append("after the words stopped scrolling the focus is on %s, not Continue anyway" % [fo2.name if fo2 else "nothing"])
				for c: Control in [n.continue_button, n.quit_button, n.dont_show]:
					if not tree.root.get_visible_rect().encloses(c.get_global_rect()):
						p.append("at 200 %% %s is off the window" % c.name)
		n.free()
	W.apply_ui_size(tree.root, 1.0)
	tree.root.size = size0


func _joy(tree: SceneTree, button: int) -> void:
	for down in [true, false]:
		var b := InputEventJoypadButton.new()
		b.button_index = button
		b.pressed = down
		tree.root.push_input(b)


## A left click at the middle of `c` (press, then release; `wait` false: no frame after the release).
func _click(tree: SceneTree, c: Control, wait := true) -> void:
	var at: Vector2 = c.get_global_rect().get_center()
	for down in [true, false]:
		var b := InputEventMouseButton.new()
		b.button_index = MOUSE_BUTTON_LEFT
		b.position = at
		b.global_position = at
		b.pressed = down
		tree.root.push_input(b, true)          # (in the canvas's coordinates)
	if wait:
		await tree.process_frame
