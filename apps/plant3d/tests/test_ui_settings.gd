## The settings panel (app/hud.gd) on the 900 px canvas, at the desktop's UI scale and the phone's: it fits the canvas
## with its Close always on screen, its body scrolls (the keyboard and gamepad help folded under "Controls", opened
## it overflows), and the keyboard's Tab and the gamepad's D-pad reach every control, each scrolled into view
## (UI-UX-POLICY R1, A1, L2; issue #381). And with Reduced motion on, "Go there" places the trainee at once instead of
## flying the camera (A4; issue #380).
extends RefCounted

const UiApp = preload("res://tests/ui_app.gd")
const SimClock = preload("res://ui/sim_clock.gd")
const W = preload("res://ui/widgets.gd")
const Autosave = preload("res://ui/autosave.gd")
const RunSave = preload("res://ui/run_save.gd")


func run(tree: SceneTree) -> Array:
	var p: Array = []
	var size0: Vector2i = tree.root.size
	# the window as a laptop's (a 1600 × 900 canvas) and a phone's (wider: 2000 × 900), at their UI scales: the
	# phone's makes the layer's rows in the panel (instructor, motion, sound, the Workshop) and its bars larger; the
	# HUD's own rows keep their sizes (issue #382). (The headless window is 64 px: the canvas would be square.)
	for w in [[Vector2i(1600, 900), ""], [Vector2i(2400, 1080), "1.35"]]:
		tree.root.size = w[0]
		p += await _settings(tree, w[1])
	tree.root.size = size0
	p += await _go_there(tree)
	return p


func _start(tree: SceneTree, ui_scale: String) -> Node:
	RunSave.remove(Autosave.default_path)      # the run the app before saved: no offer to go on with it (a modal layer)
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
		if pr.size.x > hud.SETTINGS_W * W.scale + 0.5 or absf(pr.get_center().x - canvas.get_center().x) > 1.0:
			p.append("the settings panel %s(%s) is not %d px wide at most and centred: %s" % [at, when, hud.SETTINGS_W * W.scale, str(pr)])
		# below the bars, unless they leave it less than half the canvas (a phone at 150 % with a gamepad's line under
		# the status, issue #382): then it keeps that half, over the bar's lower rows
		var top_ok: float = minf(main.ui.panels_top(), hud.settings_top_min(canvas.size.y))
		if pr.position.y < top_ok - 0.5:
			p.append("the settings panel %s(%s) reaches up over the bars (from %.0f, the bars end at %.0f)" % [at, when,
				pr.position.y, top_ok])
		var close: Button = UiApp.find_button(hud.panel, "Close")
		if close == null or not close.is_visible_in_tree() or not canvas.encloses(close.get_global_rect()) \
				or not pr.encloses(close.get_global_rect()):
			p.append("the settings' Close %s(%s) is not on screen: %s" % [at, when, str(close.get_global_rect()) if close else "none"])
		if close != null and close.focus_mode != Control.FOCUS_ALL:
			p.append("the settings' Close takes no keyboard and gamepad focus")
	check.call("folded")
	var psb = hud.panel.get_theme_stylebox("panel")
	if not (psb is StyleBoxFlat and psb.bg_color.a >= 0.999):
		p.append("the settings panel is not opaque: the panels under it show through (K5)")
	# the controls' help: folded under its button; opened, it shows (scrolled into view) and the panel still fits
	if hud.get("controls_btn") == null or hud.get("settings_scroll") == null:
		p.append("the settings %shave no scrolling body or no folded Controls help" % at)
		hud.show_settings(false)
		main.free()
		await tree.process_frame
		return p
	var cb: Button = hud.controls_btn
	if cb.size.y < 52 * W.scale - 0.5 or cb.get_theme_font_size("font_size") < int(20 * W.scale):
		p.append("the Controls button %sis not the layer's button at its UI scale: %s, font %d" % [at, str(cb.size),
			cb.get_theme_font_size("font_size")])
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
	# over the layer's side panel and over the control room's screens: Close is on top, a click on it closes
	var ui = main.ui
	ui.toggle_alarms()
	await tree.process_frame
	p += await _click_close(tree, hud, at + "over the alarm list")
	# Esc, the gamepad's B and Start close the settings, which are on top, not the alarm list under them
	for how in ["Esc", "B", "Start"]:
		hud.show_settings(true)
		await tree.process_frame
		var ev: InputEvent
		if how == "Esc":
			var k := InputEventKey.new()
			k.keycode = KEY_ESCAPE
			k.physical_keycode = KEY_ESCAPE
			ev = k
		else:
			var j := InputEventJoypadButton.new()
			j.button_index = JOY_BUTTON_B if how == "B" else JOY_BUTTON_START
			ev = j
		ev.pressed = true
		_press(tree, ev)
		await tree.process_frame
		var fo2: Control = hud.get_viewport().gui_get_focus_owner()
		if not hud.panel.visible and ui.alarms.visible and (fo2 == null or not ui.alarms.is_ancestor_of(fo2)):
			p.append("%s %sclosed the settings but the alarm list under them has no focus (%s)" % [how, at,
				fo2.get_path() if fo2 else "none"])
		if hud.panel.visible or not ui.alarms.visible:
			var fo: Control = hud.get_viewport().gui_get_focus_owner()
			p.append("%s %swith the settings over the alarm list: settings %s, alarm list %s (focus %s)" % [how, at,
				"open" if hud.panel.visible else "closed", "open" if ui.alarms.visible else "closed",
				fo.get_path() if fo else "none"])
		hud.show_settings(false)
		if not ui.alarms.visible:
			ui.toggle_alarms()
	ui.close_alarms()
	ui.go_control_room(false)
	ui.open_screens()
	for i in 3:
		await tree.process_frame
	if not ui.screens_open():
		p.append("the screens did not open in the control room (test setup)")
	else:
		p += await _click_close(tree, hud, at + "over the screens")
		ui.close_screens()
	# a toast shows over the settings (it is on a layer above them)
	hud.show_settings(true)
	ui.toast("A notice")
	var tl: CanvasLayer = ui._toast.get_canvas_layer_node()
	if tl == null or tl.layer <= hud.settings_layer.layer or not ui._toast.is_visible_in_tree():
		p.append("a toast %sis drawn under the settings (layer %s, the settings' %d)" % [at, str(tl.layer if tl else null),
			hud.settings_layer.layer])
	hud.show_settings(false)
	# the command line's panels=settings,toasts (a measured walk's)
	ui.open_panel("settings")
	ui.open_panel("toasts")
	var wt: Timer = ui.get_node_or_null("walk_toasts")
	if not hud.panel.visible or wt == null:
		p.append("panels=settings,toasts %sdid not open the settings or start the toasts" % at)
	else:
		wt.timeout.emit()
		if not ui._toast.visible:
			p.append("panels=toasts %sshowed no toast" % at)
		wt.queue_free()
	hud.show_settings(false)
	# opened again: the help folded as at first
	hud.show_settings(true)
	cb.button_pressed = true
	hud.show_settings(false)
	hud.show_settings(true)
	if cb.button_pressed or hud.controls_help.visible:
		p.append("the settings %sopened again keep the Controls help open" % at)
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


## Opens the settings, clicks the middle of Close with the mouse (into the window's input, as a device would): true when the
## settings closed (nothing above the panel took the click).
func _click_close(tree: SceneTree, hud, where: String) -> Array:
	hud.show_settings(true)
	for i in 3:
		await tree.process_frame
	var c: Vector2 = hud.close_btn.get_global_rect().get_center()
	var hovered = null
	for down in [true, false]:
		var m := InputEventMouseButton.new()
		m.button_index = MOUSE_BUTTON_LEFT
		m.pressed = down
		m.position = c
		m.global_position = c
		tree.root.push_input(m, true)          # (in the canvas's coordinates)
		if down:
			hovered = tree.root.gui_get_hovered_control()
		await tree.process_frame
	await tree.process_frame
	if hud.panel.visible:
		hud.show_settings(false)
		return ["a click on the settings' Close %s did not close them: at %s it reached %s" % [where, str(c),
			hovered.get_path() if hovered else "nothing"]]
	return []


func _press(tree: SceneTree, e: InputEvent) -> void:
	tree.root.push_input(e)
	var up: InputEvent = e.duplicate()
	up.pressed = false
	tree.root.push_input(up)
