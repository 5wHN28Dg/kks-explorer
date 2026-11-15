## The settings panel (app/hud.gd) on the 900 px canvas, at the desktop's UI scale and the phone's: it fits the canvas
## with its Close always on screen, its body scrolls (the keyboard and gamepad help folded under "Controls", opened
## it overflows), and the keyboard's Tab and the gamepad's D-pad reach every control, each scrolled into view
## (UI-UX-POLICY R1, A1, L2; issue #381). And with Reduced motion on, "Go there" places the trainee at once instead of
## flying the camera (A4; issue #380).
extends RefCounted

const UiApp = preload("res://tests/ui_app.gd")
const SimClock = preload("res://ui/sim_clock.gd")
const W = preload("res://ui/widgets.gd")


func run(tree: SceneTree) -> Array:
	var p: Array = []
	for sc in ["", "1.35"]:
		p += await _settings(tree, sc)
	p += await _go_there(tree)
	return p


func _start(tree: SceneTree, ui_scale: String) -> Node:
	var main: Node = (load("res://app/main.tscn") as PackedScene).instantiate()
	if ui_scale != "":
		main.opts["ui_scale"] = ui_scale       # the phone's scale (as tests/mimic_shots.gd --phone)
	tree.root.add_child(main)
	if main.ui != null and main.ui.clock != null:
		main.ui.clock.set_speed(SimClock.Speed.PAUSED)
	return main


func _settings(tree: SceneTree, ui_scale: String) -> Array:
	var p: Array = []
	var at := "at the phone's scale " if ui_scale != "" else ""
	var main := _start(tree, ui_scale)
	for i in 10:
		await tree.process_frame
	var hud = main.hud
	hud.show_settings(true)
	for i in 3:
		await tree.process_frame
	var canvas: Rect2 = hud.panel.get_viewport_rect()
	var check := func(when: String) -> void:
		var pr: Rect2 = hud.panel.get_global_rect()
		if not canvas.encloses(pr):
			p.append("the settings panel %s(%s) is not inside the %s canvas: %s" % [at, when, str(canvas.size), str(pr)])
		var close: Button = UiApp.find_button(hud.panel, "Close")
		if close == null or not close.is_visible_in_tree() or not canvas.encloses(close.get_global_rect()) \
				or not pr.encloses(close.get_global_rect()):
			p.append("the settings' Close %s(%s) is not on screen: %s" % [at, when, str(close.get_global_rect()) if close else "none"])
		if close != null and close.focus_mode != Control.FOCUS_ALL:
			p.append("the settings' Close takes no keyboard and gamepad focus")
	check.call("folded")
	# the controls' help: folded under its button; opened, it shows (scrolled into view) and the panel still fits
	var cb: Button = hud.controls_btn
	if hud.controls_help.is_visible_in_tree():
		p.append("the keyboard and gamepad help is not folded at first")
	cb.button_pressed = true
	for i in 4:
		await tree.process_frame
	check.call("the controls' help open")
	var view: Rect2 = hud.settings_scroll.get_global_rect()
	var help: Rect2 = hud.controls_help.get_global_rect()
	if not hud.controls_help.is_visible_in_tree() or not view.intersects(help) or help.position.y < view.position.y - 1:
		p.append("opening Controls %sdoes not show the help in view: %s in %s" % [at, str(help), str(view)])
	var body: Control = hud.settings_scroll.get_child(0)
	if body.get_combined_minimum_size().y <= view.size.y:
		p.append("the settings' body %swith the help open fits without scrolling: the scrolling is not tested" % at)
	# every control that takes the focus, reached by Tab (keyboard) and by the D-pad (gamepad), each in view when focused
	var want: Array = []
	for c in hud.settings_box.find_children("*", "BaseButton", true, false):
		if c.is_visible_in_tree():
			want.append(c)
			if c.focus_mode != Control.FOCUS_ALL:
				p.append("%s %s takes no keyboard and gamepad focus" % [c.get_class(), c.text])
	# Tab: one after another, round to About again
	hud.settings_scroll.scroll_vertical = 0
	hud.about_btn.grab_focus()
	await tree.process_frame
	var seen := {}
	var out_of_view := []
	for i in want.size() + 2:
		var fo: Control = hud.get_viewport().gui_get_focus_owner()
		if fo != null and hud.panel.is_ancestor_of(fo):
			seen[fo] = true
			await _in_view(tree, hud, fo, out_of_view)
		var k := InputEventKey.new()
		k.keycode = KEY_TAB
		k.physical_keycode = KEY_TAB
		k.pressed = true
		_press(tree, k)
		await tree.process_frame
	p += _reached("Tab " + at, want, seen, out_of_view)
	# the D-pad: every control reached from About by its four directions, in turn from each control reached
	hud.settings_scroll.scroll_vertical = 0
	seen = {hud.about_btn: true}
	out_of_view = []
	var todo: Array = [hud.about_btn]
	while not todo.is_empty() and hud.panel.visible:
		var from: Control = todo.pop_front()
		for b in [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]:
			from.grab_focus()
			await tree.process_frame
			var j := InputEventJoypadButton.new()
			j.button_index = b
			j.pressed = true
			_press(tree, j)
			await tree.process_frame
			var fo: Control = hud.get_viewport().gui_get_focus_owner()
			if fo != null and hud.panel.is_ancestor_of(fo) and not seen.has(fo):
				seen[fo] = true
				todo.append(fo)
				await _in_view(tree, hud, fo, out_of_view)
	p += _reached("the D-pad " + at, want, seen, out_of_view)
	if not hud.panel.visible:
		p.append("the D-pad or Tab %sclosed the settings" % at)
	cb.button_pressed = false
	hud.show_settings(false)
	main.free()
	await tree.process_frame
	return p


func _go_there(tree: SceneTree) -> Array:
	var p: Array = []
	var main := _start(tree, "")
	for i in 10:
		await tree.process_frame
	var ui = main.ui
	var code := "10LAC10AP001"
	if not ui.index.has(code):
		main.free()
		return ["%s is not drawn: no Go there to test" % code]
	# reduced motion off: a flight (the camera moves over frames)
	ui._setting("reduced_motion", false)
	ui.player.set_mode(ui.player.Mode.FLY)
	var start: Vector3 = ui.player.global_position + Vector3(0, 30, 0)
	ui.player.global_position = start
	ui.fly_to(code)
	if not ui.player.scripted:
		p.append("Go there without Reduced motion did not fly")
	for i in 300:
		if not ui.player.scripted:
			break
		await tree.process_frame
	var flown: Vector3 = ui.player.global_position
	# back where it began, then with reduced motion on: placed at once, beside the same equipment, nothing scripted
	ui.player.set_mode(ui.player.Mode.FLY)
	ui.player.global_position = start
	ui._setting("reduced_motion", true)
	var called := [false]
	ui.fly_to(code, func(): called[0] = true)
	if ui.player.scripted or ui._flight != null and ui._flight.is_running():
		p.append("Go there with Reduced motion on flies the camera")
	if not called[0]:
		p.append("Go there with Reduced motion on did not call its done at once")
	var d: float = ui.player.global_position.distance_to(flown)
	if d > 1.0:
		p.append("Go there with Reduced motion on placed the trainee %.1f m from where the flight lands" % d)
	ui._setting("reduced_motion", false)
	main.free()
	return p


## Waits for the scroll to follow the focus, then notes `fo` when it is not inside the body's visible part (or the
## canvas, for the title row's buttons).
func _in_view(tree: SceneTree, hud, fo: Control, out: Array) -> void:
	for j in 3:
		await tree.process_frame
	var body: Control = hud.settings_scroll.get_child(0)
	var shown: Rect2 = hud.settings_scroll.get_global_rect() if body.is_ancestor_of(fo) else hud.panel.get_viewport_rect()
	if not shown.grow(1).encloses(fo.get_global_rect()):
		out.append("%s %s" % [fo.get_class(), fo.get("text")])


func _reached(how: String, want: Array, seen: Dictionary, out_of_view: Array) -> Array:
	var p: Array = []
	var missed := want.filter(func(c): return not seen.has(c)).map(func(c): return "%s %s" % [c.get_class(), c.text])
	if not missed.is_empty():
		p.append("%sdoes not reach %s" % [how, ", ".join(missed)])
	if not out_of_view.is_empty():
		p.append("focused by %s, not scrolled into view: %s" % [how, ", ".join(out_of_view)])
	return p


func _press(tree: SceneTree, e: InputEvent) -> void:
	tree.root.push_input(e)
	var up: InputEvent = e.duplicate()
	up.pressed = false
	tree.root.push_input(up)
