## About (decision 0054 §7, app/about.gd): opened from the settings panel, it shows the app's version, the commit
## build.sh recorded, the assets of built/about.json with their licence, and Godot's own notices; it scrolls by
## gamepad (D-pad, stick) and keyboard (Page Down, Home); gamepad A opens it and B, Esc or Back returns to the settings with the walker's
## controls still held.
extends RefCounted

const UiApp = preload("res://tests/ui_app.gd")


func run(tree: SceneTree) -> Array:
	var p: Array = []
	# (packaging, decision 0056) a link's start takes no options: a crafted link can't add `--out=…` on Windows
	var Main = load("res://app/main.gd")
	if Main.parse_options(PackedStringArray(["--walk=frames", "--seconds=5"])) != {"walk": "frames", "seconds": "5"}:
		p.append("options after -- are not read")
	if Main.parse_options(PackedStringArray(["walkdown-plant://kks/A", "--out=//host/share"])) != {}:
		p.append("a link's start takes options from the link's text")
	var main: Node = UiApp.start(tree)
	for i in 10:
		await tree.process_frame
	var hud = main.hud
	hud.show_settings(true)
	await tree.process_frame
	var btn: Button = UiApp.find_button(hud.panel, "About")
	if btn == null:
		main.free()
		return ["the settings panel has no About button"]
	if hud.get_viewport().gui_get_focus_owner() != btn:
		p.append("the settings panel does not give About the keyboard and gamepad focus")
	# the gamepad's A on the focused button opens it
	_press(tree, _joy(JOY_BUTTON_A))
	await tree.process_frame
	await tree.process_frame
	if not hud.about.visible:
		main.free()
		return p + ["gamepad A on About did not open it"]
	if hud.settings_box.visible or not hud.panel.visible or main.player.input_enabled:
		p.append("About replaces the settings in their panel and keeps the walker's controls held")
	var shown := UiApp.texts(hud.about)
	var version: String = ProjectSettings.get_setting("application/config/version", "")
	if version == "" or not shown.contains("Walkdown Plant " + version):
		p.append("About does not show the version %s" % version)
	var bi: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://built/build_info.json"))
	if not (bi.commit is String and bi.commit.length() == 40 and shown.contains("commit " + bi.commit)):
		p.append("About does not show the commit build.sh recorded (%s)" % str(bi.get("commit")))
	var assets: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://about.json"))
	for a in assets.assets:
		if not shown.contains("%s: %s" % [a.name, a.license]):
			p.append("About does not list %s with its licence" % a.name)
	if not shown.contains("Creative Commons Legal Code"):
		p.append("About does not carry the CC0 text")
	if not shown.contains(Engine.get_license_text().strip_edges().get_slice("\n", 0)):
		p.append("About does not carry Godot's licence")
	var ci: Array = Engine.get_copyright_info()
	if ci.is_empty() or not shown.contains(str(ci[ci.size() - 1].name)):
		p.append("About does not carry Godot's copyright notices")
	var li: Dictionary = Engine.get_license_info()
	for n in li:
		if not shown.contains("Licence: " + n):
			p.append("About does not carry the licence %s" % n)
			break
	# scrolling: the D-pad, a stick, Page Down, Home
	await tree.process_frame
	var sc: ScrollContainer = hud.about.scroll
	_press(tree, _joy(JOY_BUTTON_DPAD_DOWN))
	await tree.process_frame
	var after_dpad := sc.scroll_vertical
	if after_dpad <= 0:
		p.append("the D-pad does not scroll About")
	Input.action_press("look_down")
	for i in 10:
		await tree.process_frame
	Input.action_release("look_down")
	if sc.scroll_vertical <= after_dpad:
		p.append("the right stick does not scroll About")
	var k := InputEventKey.new()
	k.keycode = KEY_PAGEDOWN
	k.pressed = true
	var before := sc.scroll_vertical
	_press(tree, k)
	await tree.process_frame
	if sc.scroll_vertical <= before:
		p.append("Page Down does not scroll About")
	k = InputEventKey.new()
	k.keycode = KEY_HOME
	k.pressed = true
	_press(tree, k)
	await tree.process_frame
	if sc.scroll_vertical != 0:
		p.append("Home does not go back to the top")
	# Esc goes back to the settings, not out of them
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	_press(tree, esc)
	await tree.process_frame
	if hud.about.visible or not hud.settings_box.visible or not hud.panel.visible:
		p.append("Esc in About does not go back to the settings")
	elif hud.get_viewport().gui_get_focus_owner() != btn:
		p.append("back in the settings, About does not have the focus again")
	# gamepad A opens it again, B goes back
	_press(tree, _joy(JOY_BUTTON_A))
	await tree.process_frame
	if not hud.about.visible:
		p.append("gamepad A on About did not open it a second time")
	_press(tree, _joy(JOY_BUTTON_B))
	await tree.process_frame
	if hud.about.visible or not hud.panel.visible:
		p.append("gamepad B in About does not go back to the settings")
	# gamepad A on a check box of the settings toggles it (and leaves a disabled one)
	var cb := CheckBox.new()
	cb.focus_mode = Control.FOCUS_ALL
	hud.extra.add_child(cb)
	cb.grab_focus()
	_press(tree, _joy(JOY_BUTTON_A))
	if not cb.button_pressed:
		p.append("gamepad A does not toggle a check box in the settings")
	cb.disabled = true
	_press(tree, _joy(JOY_BUTTON_A))
	if not cb.button_pressed:
		p.append("gamepad A toggled a disabled check box")
	cb.free()
	btn.grab_focus()
	# Back by touch or mouse, and closing the settings while About shows
	hud.show_about()
	UiApp.find_button(hud.about, "Back").pressed.emit()
	if hud.about.visible or not hud.panel.visible:
		p.append("Back does not return to the settings")
	hud.show_about()
	hud.show_settings(false)
	await tree.process_frame
	if hud.about.visible or hud.panel.visible or not main.player.input_enabled:
		p.append("closing the settings while About shows leaves something open")
	main.free()
	return p


func _joy(b: int) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	e.pressed = true
	return e


## The event pressed and released, as a device sends them, into the window (headless Godot has no input device).
func _press(tree: SceneTree, e: InputEvent) -> void:
	tree.root.push_input(e)
	var up: InputEvent = e.duplicate()
	up.pressed = false
	tree.root.push_input(up)
