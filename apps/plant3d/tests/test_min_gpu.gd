## The minimum GPU's message (decision 0076, app/min_gpu.gd): with the Compatibility renderer on a desktop the app
## shows it before the plant loads, and the plant loads only after Continue anyway; on a phone, on Forward+ or Mobile,
## for a measurement, or once "Don't show this again" was chosen, it is not shown. Godot's rendering method and the
## device kind are mocked (MinGpu.renderer_override, phone_override): the tests run headless.
extends RefCounted

const MinGpu = preload("res://app/min_gpu.gd")
const Quality = preload("res://app/quality.gd")
const UiApp = preload("res://tests/ui_app.gd")
const SimClock = preload("res://ui/sim_clock.gd")


func run(tree: SceneTree) -> Array:
	var p: Array = []
	var saved := Quality.settings()
	var had: bool = saved.has_section_key(MinGpu.SECTION, MinGpu.KEY_OFF)
	var was = saved.get_value(MinGpu.SECTION, MinGpu.KEY_OFF, false)
	_forget()
	_when(p)
	await _shown_then_continue(tree, p)
	await _not_again(tree, p)
	_forget()
	await _not_shown(tree, p, "gl_compatibility", 1, "on a phone")
	await _not_shown(tree, p, "forward_plus", 0, "with Forward+")
	await _not_shown(tree, p, "mobile", 0, "with the Mobile renderer")
	await _quit_and_escape(tree, p)
	MinGpu.renderer_override = ""
	MinGpu.phone_override = -1
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
	for w in ["below what Walkdown Plant needs", "run slowly", "about 12 pictures a second", "Vulkan or Direct3D 12",
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
	notice.dont_show.button_pressed = true
	notice.continue_button.pressed.emit()
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
		if got != [false]:
			p.append("Quit did not answer quit (%s)" % str(got))
		if bool(Quality.settings().get_value(MinGpu.SECTION, MinGpu.KEY_OFF, false)) != tick:
			p.append("Quit with the box %s left the setting %s" % ["ticked" if tick else "clear",
					"off" if tick else "on"])
		await tree.process_frame
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
	if got2 != [true]:
		p.append("Escape did not continue (%s)" % str(got2))
	await tree.process_frame
	if is_instance_valid(n2):
		n2.free()
	_forget()
