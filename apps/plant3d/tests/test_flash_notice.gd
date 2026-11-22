## The photosensitivity notice (issue #443, the rulebook's GM8.3; app/flash_notice.gd): switched on, it comes once at
## the first start, before the plant loads, says what flashes and how to stop it, and has "No lightning flashes" on it;
## closed by Continue, Escape, gamepad B or a tap it is kept as seen and never comes at a start again; it opens again
## from the settings ("About flashing light"), where its box changes the setting at once, and About carries its words.
## Switched off (until the owner's check) the start, the settings and About are as before. The tests run headless:
## the notice is asked for with FlashNotice.display_override.
extends RefCounted

const FlashNotice = preload("res://app/flash_notice.gd")
const Quality = preload("res://app/quality.gd")
const About = preload("res://app/about.gd")
const UiApp = preload("res://tests/ui_app.gd")
const SimClock = preload("res://ui/sim_clock.gd")
const W = preload("res://ui/widgets.gd")

const KEYS := ["flash_notice_seen", "no_flashes", "reduced_motion"]


func run(tree: SceneTree) -> Array:
	var p: Array = []
	var cf0 := Quality.settings()
	var kept := {}
	for k in KEYS:
		if cf0.has_section_key("ui", k):
			kept[k] = cf0.get_value("ui", k)
	_forget()
	await _switched_off(tree, p)
	FlashNotice.switch_override = 1     # (the owner's check: the notice on)
	_when(p)
	FlashNotice.display_override = 1
	await _first_start(tree, p)
	await _not_again(tree, p)
	await _keys_pad_touch(tree, p)
	await _with_reduced_motion(tree, p)
	await _large_ui(tree, p)
	await _from_settings(tree, p)
	FlashNotice.switch_override = -1
	FlashNotice.display_override = -1
	_forget()
	var cf := Quality.settings()
	for k in kept:
		cf.set_value("ui", k, kept[k])
	Quality.save(cf)
	return p


func _forget() -> void:
	var cf := Quality.settings()
	for k in KEYS:
		if cf.has_section_key("ui", k):
			cf.erase_section_key("ui", k)
	Quality.save(cf)


## Switched off: no notice at the start, the plant loads at once; no "About flashing light" in the settings, nothing
## about it in About.
func _switched_off(tree: SceneTree, p: Array) -> void:
	if bool(ProjectSettings.get_setting("walkdown/flash_notice", true)):
		p.append("the notice is switched on in project.godot before the owner's check")
	FlashNotice.switch_override = -1
	FlashNotice.display_override = 1
	if FlashNotice.wanted(ConfigFile.new(), {}):
		p.append("the notice is due while switched off")
	var main: Node = UiApp.start(tree)
	if main.get_node_or_null("flash_notice") != null or main.ui == null:
		p.append("switched off, the start is not as before (a notice, or the plant not loaded at once)")
	else:
		main.hud.show_settings(true)
		await tree.process_frame
		if main.ui.flash_notice_btn != null or UiApp.find_button(main.hud.panel, "About flashing light") != null:
			p.append("switched off, the settings have \"About flashing light\"")
		main.hud.show_settings(false)
	for s in About.sections():
		if s[0] == FlashNotice.TITLE:
			p.append("switched off, About has the flashing light section")
	await tree.process_frame
	main.free()
	FlashNotice.display_override = -1


## The rule alone.
func _when(p: Array) -> void:
	FlashNotice.display_override = 1
	if not FlashNotice.wanted(ConfigFile.new(), {}):
		p.append("the notice is not due at a first start")
	var odd := ConfigFile.new()           # a file edited by hand: never a script error, the notice as at a first start
	odd.set_value("ui", "flash_notice_seen", "yes")
	if not FlashNotice.wanted(odd, {}):
		p.append("an odd seen value hides the notice")
	var seen := ConfigFile.new()
	seen.set_value("ui", "flash_notice_seen", true)
	if FlashNotice.wanted(seen, {}):
		p.append("the notice is due again after it was seen")
	for o in [{"walk": "frames"}, {"shot": "a@0,0,0,0,0"}, {"mp": "CODE@127.0.0.1"}, {"probe": "1"}]:
		if FlashNotice.wanted(ConfigFile.new(), o):
			p.append("the notice is due for a scripted start (%s)" % str(o))
	FlashNotice.display_override = -1
	if FlashNotice.wanted(ConfigFile.new(), {}):
		p.append("the notice is due on a headless start")


## The first start: the notice before the plant, its words, the focus on Continue with the words for a screen reader;
## a click on the box turns "No lightning flashes" on, Continue loads the plant with it on and keeps the notice seen.
func _first_start(tree: SceneTree, p: Array) -> void:
	var main: Node = UiApp.start(tree)
	var n = main.get_node_or_null("flash_notice")
	if n == null:
		main.free()
		p.append("no notice at the first start")
		return
	if main.plant != null or main.ui != null:
		p.append("the plant was loaded before the notice was closed")
	await tree.process_frame
	await tree.process_frame
	var shown := UiApp.texts(n)
	for w in ["Flashing light", "thunderstorm", "lightning flash", "at most once every 2 seconds", "also in fast-forward",
			"If flashing light can affect you", "No lightning flashes", "glows softly", "Reduced motion", "Settings",
			"Continue"]:
		if not shown.contains(w):
			p.append("the notice does not say \"%s\"" % w)
	if tree.root.gui_get_focus_owner() != n.continue_button:
		p.append("Continue does not have the keyboard and gamepad focus")
	var said: String = n.continue_button.accessibility_description
	if not (said.begins_with("Flashing light.") and said.contains("No lightning flashes") and said.contains("2 seconds")):
		p.append("a screen reader is not told the notice with the focused button (\"%s\")" % said)
	if n.no_flashes.button_pressed or n.no_flashes.disabled:
		p.append("the box is ticked or not changeable at a first start")
	var vs: Vector2 = tree.root.get_visible_rect().size
	for c: Control in [n.continue_button, n.no_flashes]:
		var r: Rect2 = c.get_global_rect()
		if r.size.x < 24.0 or r.size.y < 24.0:
			p.append("%s is smaller than 24 x 24 px (%s)" % [c.name, str(r.size)])
		if not Rect2(Vector2.ZERO, vs).encloses(r):
			p.append("%s is off the window (%s in %s)" % [c.name, str(r), str(vs)])
	# Tab goes round the notice's own controls
	_key(tree, KEY_TAB)
	await tree.process_frame
	if tree.root.gui_get_focus_owner() != n.no_flashes:
		p.append("Tab from Continue does not go to the box")
	await _click(tree, n.no_flashes)
	if not n.no_flashes.button_pressed:
		p.append("a click on the box did not tick it")
	if not bool(Quality.settings().get_value("ui", "no_flashes", false)):
		p.append("the box did not turn \"No lightning flashes\" on in the settings")
	if bool(Quality.settings().get_value("ui", "flash_notice_seen", false)):
		p.append("the notice is kept as seen before it was closed")
	await _click(tree, n.continue_button, false)
	if main.plant != null:
		p.append("the plant loaded inside the button's handler")
	await tree.process_frame
	if main.plant == null or main.ui == null:
		p.append("the plant did not load after Continue")
	else:
		if main.ui.clock != null:
			main.ui.clock.set_speed(SimClock.Speed.PAUSED)
		if not bool(main.ui.bindings.no_flashes):
			p.append("the plant started without \"No lightning flashes\" after the box was ticked")
	if is_instance_valid(n) and n.is_inside_tree():
		p.append("the notice stays after Continue")
	if not bool(Quality.settings().get_value("ui", "flash_notice_seen", false)):
		p.append("the notice was not kept as seen")
	main.free()


## The next start: no notice, the plant at once, "No lightning flashes" as it was left.
func _not_again(tree: SceneTree, p: Array) -> void:
	var main: Node = UiApp.start(tree)
	if main.get_node_or_null("flash_notice") != null:
		p.append("the notice came again at the next start")
	if main.ui == null:
		p.append("the plant did not load at once at the next start")
	await tree.process_frame
	main.free()
	_forget()


## The notice alone: Escape and gamepad B close it (kept as seen, the box as it was); gamepad A ticks the box with the
## focus and presses Continue; a tap on Continue closes it.
func _keys_pad_touch(tree: SceneTree, p: Array) -> void:
	for how in ["escape", "pad_b"]:
		_forget()
		var n = FlashNotice.new(Quality.settings())
		tree.root.add_child(n)
		await tree.process_frame
		var got := []
		n.closed.connect(func(): got.append(true))
		if how == "escape":
			_key(tree, KEY_ESCAPE)
		else:
			_joy(tree, JOY_BUTTON_B)
		await tree.process_frame
		await tree.process_frame
		if got != [true]:
			p.append("%s did not close the notice" % how)
		if not bool(Quality.settings().get_value("ui", "flash_notice_seen", false)):
			p.append("closed by %s, the notice was not kept as seen" % how)
		if bool(Quality.settings().get_value("ui", "no_flashes", false)):
			p.append("closed by %s, \"No lightning flashes\" was turned on" % how)
		if is_instance_valid(n):
			n.free()
	_forget()
	var n2 = FlashNotice.new(Quality.settings())
	tree.root.add_child(n2)
	await tree.process_frame
	var got2 := []
	n2.closed.connect(func(): got2.append(true))
	n2.no_flashes.grab_focus()
	_joy(tree, JOY_BUTTON_A)
	await tree.process_frame
	if not n2.no_flashes.button_pressed or not bool(Quality.settings().get_value("ui", "no_flashes", false)):
		p.append("gamepad A on the box did not tick it")
	_joy(tree, JOY_BUTTON_DPAD_DOWN)
	await tree.process_frame
	if tree.root.gui_get_focus_owner() != n2.continue_button:
		p.append("the D-pad's down from the box does not go to Continue")
	_joy(tree, JOY_BUTTON_A)
	await tree.process_frame
	await tree.process_frame
	if got2 != [true]:
		p.append("gamepad A on Continue did not close the notice (%s)" % str(got2))
	if is_instance_valid(n2):
		n2.free()
	_forget()
	var n3 = FlashNotice.new(Quality.settings())
	tree.root.add_child(n3)
	for i in 3:
		await tree.process_frame
	var got3 := []
	n3.closed.connect(func(): got3.append(true))
	var at: Vector2 = n3.continue_button.get_global_rect().get_center()
	for down in [true, false]:
		var t := InputEventScreenTouch.new()
		t.index = 0
		t.position = at
		t.pressed = down
		tree.root.push_input(t, true)
	await tree.process_frame
	await tree.process_frame
	if got3 != [true]:
		p.append("a tap on Continue did not close the notice (%s)" % str(got3))
	if is_instance_valid(n3):
		n3.free()
	_forget()


## With Reduced motion on, the box shows "No lightning flashes" on, not changeable, and says why.
func _with_reduced_motion(tree: SceneTree, p: Array) -> void:
	var cf := ConfigFile.new()
	cf.set_value("ui", "reduced_motion", true)
	var n = FlashNotice.new(cf)
	tree.root.add_child(n)
	await tree.process_frame
	if not n.no_flashes.button_pressed or not n.no_flashes.disabled or not n.no_flashes.text.contains("(on with Reduced motion)"):
		p.append("with Reduced motion on, the box is not shown on and fixed (%s, %s, \"%s\")" % [
				n.no_flashes.button_pressed, n.no_flashes.disabled, n.no_flashes.text])
	n.free()


## At UI size 200 % on a phone-shaped window the box and the button stay on screen, the words scroll and the keyboard
## reaches them.
func _large_ui(tree: SceneTree, p: Array) -> void:
	var size0: Vector2i = tree.root.size
	tree.root.size = Vector2i(960, 420)
	W.apply_ui_size(tree.root, 2.0)
	var n = FlashNotice.new(ConfigFile.new())
	tree.root.add_child(n)
	for i in 4:
		await tree.process_frame
	var vr: Rect2 = tree.root.get_visible_rect()
	for c: Control in [n.continue_button, n.no_flashes]:
		if not vr.encloses(c.get_global_rect()):
			p.append("at 200 %% %s is off the window (%s in %s)" % [c.name, str(c.get_global_rect()), str(vr)])
	var bar: VScrollBar = n.scroll.get_v_scroll_bar()
	# (a short window at 200 %: the words must scroll, so the keyboard's way to them is checked, never skipped)
	if bar.max_value <= n.scroll.size.y + 1.0:
		p.append("at 200 %% on a %s window the words fit: the scrolling is not checked" % str(tree.root.size))
	elif n.scroll.focus_mode != Control.FOCUS_ALL:
		p.append("at 200 % the words that don't fit can't take the focus")
	else:
		n.scroll.grab_focus()
		await tree.process_frame
		_key(tree, KEY_PAGEDOWN)
		await tree.process_frame
		if n.scroll.scroll_vertical <= 0:
			p.append("at 200 % Page Down did not scroll the words")
	n.free()
	W.apply_ui_size(tree.root, 1.0)
	tree.root.size = size0


## From the settings: "About flashing light" opens the notice over them with Close; its box turns "No lightning
## flashes" on at once (the plant's setting and the settings' own row); Close gives the focus back to the button.
## About has the words.
func _from_settings(tree: SceneTree, p: Array) -> void:
	var cf := Quality.settings()
	cf.set_value("ui", "flash_notice_seen", true)
	Quality.save(cf)
	var main: Node = UiApp.start(tree)
	if main.ui == null:
		p.append("the plant did not load with the notice seen")
		main.free()
		return
	main.hud.show_settings(true)
	await tree.process_frame
	var b: Button = main.ui.flash_notice_btn
	if b == null or not b.is_visible_in_tree():
		p.append("the settings have no \"About flashing light\"")
		main.free()
		return
	b.grab_focus()
	b.pressed.emit()
	await tree.process_frame
	var n = main.ui.flash_notice
	if not is_instance_valid(n) or not n.is_inside_tree():
		p.append("\"About flashing light\" did not open the notice")
		main.free()
		return
	await tree.process_frame
	if not UiApp.texts(n).contains("Both are also in the settings under this note."):
		p.append("from the settings the notice still sends the user to Settings")
	if n.continue_button.text != "Close":
		p.append("from the settings the notice's button is \"%s\", not Close" % n.continue_button.text)
	if tree.root.gui_get_focus_owner() != n.continue_button:
		p.append("from the settings the notice's Close does not have the focus")
	if n.layer <= preload("res://app/hud.gd").SETTINGS_LAYER:
		p.append("the notice is not over the settings")
	n.no_flashes.button_pressed = true
	await tree.process_frame
	if not bool(main.ui.bindings.no_flashes):
		p.append("the notice's box did not turn \"No lightning flashes\" on at once")
	var row: CheckBox = main.hud.panel.find_child("setting_no_flashes", true, false)
	if row == null or not row.button_pressed:
		p.append("the settings' own row does not show \"No lightning flashes\" on after the notice's box")
	# gamepad B closes the notice only, not the settings under it
	_joy(tree, JOY_BUTTON_B)
	await tree.process_frame
	await tree.process_frame
	if is_instance_valid(n) and n.is_inside_tree():
		p.append("gamepad B did not close the notice opened from the settings")
	if not main.hud.panel.visible:
		p.append("gamepad B on the notice closed the settings under it too")
	if tree.root.gui_get_focus_owner() != b:
		var fo := tree.root.gui_get_focus_owner()
		p.append("after the notice, the focus is on %s, not \"About flashing light\"" % [fo.name if fo else "nothing"])
	# Escape and gamepad Start close it too, and only it (Start would close the settings: the blind review of #518)
	for how in ["escape", "start"]:
		b.grab_focus()
		b.pressed.emit()
		await tree.process_frame
		await tree.process_frame
		var n2 = main.ui.flash_notice
		if not is_instance_valid(n2) or not n2.is_inside_tree():
			p.append("\"About flashing light\" did not open the notice again (before %s)" % how)
			break
		if how == "escape":
			_key(tree, KEY_ESCAPE)
		else:
			_joy(tree, JOY_BUTTON_START)
		await tree.process_frame
		await tree.process_frame
		if is_instance_valid(n2) and n2.is_inside_tree():
			p.append("%s did not close the notice opened from the settings" % how)
		if not main.hud.panel.visible:
			p.append("%s on the notice closed the settings under it too" % how)
		if tree.root.gui_get_focus_owner() != b:
			p.append("after %s the focus is not on \"About flashing light\"" % how)
	var found := false
	for s in About.sections():
		if s[0] == FlashNotice.TITLE and s[1].contains("No lightning flashes") and s[1].contains("in Settings"):
			found = true
	if not found:
		p.append("About has no flashing light section")
	main.hud.show_settings(false)
	await tree.process_frame
	main.free()


func _key(tree: SceneTree, k: int) -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = k
		ev.physical_keycode = k
		ev.pressed = down
		tree.root.push_input(ev)


func _joy(tree: SceneTree, button: int) -> void:
	for down in [true, false]:
		var b := InputEventJoypadButton.new()
		b.button_index = button
		b.pressed = down
		tree.root.push_input(b)


func _click(tree: SceneTree, c: Control, wait := true) -> void:
	var at: Vector2 = c.get_global_rect().get_center()
	for down in [true, false]:
		var b := InputEventMouseButton.new()
		b.button_index = MOUSE_BUTTON_LEFT
		b.position = at
		b.global_position = at
		b.pressed = down
		tree.root.push_input(b, true)
	if wait:
		await tree.process_frame
