## What lies over the view: the touch controls (two sticks: move on the left, look on the right, Godot's own
## VirtualJoystick driving the same actions as a gamepad's sticks), the buttons (walk/fly, map, use, up and down in
## flight, settings), a line saying where the trainee is and how, and the settings panel (the quality tier, with
## "Automatic" saying what it chose and why).
extends CanvasLayer

const Quality = preload("res://app/quality.gd")
const Player = preload("res://app/player.gd")

var main   # app/main.gd
var status: Label
var sticks: Array = []
var fly_btn: Button
var updown: Array = []
var panel: PanelContainer
var tier_opt: OptionButton
var touch_opt: OptionButton
var tier_note: Label
var extra: VBoxContainer       # rows the interaction layer adds (ui/plant_ui.gd: instructor mode, motion, sound)

func setup(m) -> void:
	main = m
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	status = Label.new()
	status.position = Vector2(16, 12)
	status.add_theme_font_size_override("font_size", 20)
	status.add_theme_constant_override("outline_size", 6)
	status.add_theme_color_override("font_outline_color", Color.BLACK)
	root.add_child(status)
	# the two sticks (shown on touch screens, or when chosen in the settings)
	for side in [["move", Control.PRESET_BOTTOM_LEFT], ["look", Control.PRESET_BOTTOM_RIGHT]]:
		var j := VirtualJoystick.new()
		j.name = side[0] + "_stick"
		j.set_anchors_preset(side[1])
		j.custom_minimum_size = Vector2(420, 420)
		j.size = j.custom_minimum_size
		j.position = Vector2(20, -440) if side[0] == "move" else Vector2(-440, -440)
		j.joystick_size = 220
		j.tip_size = 90
		j.joystick_mode = 1   # dynamic: the stick appears where the thumb lands
		if side[0] == "move":
			j.action_left = "move_left"; j.action_right = "move_right"; j.action_up = "move_forward"; j.action_down = "move_back"
		else:
			j.action_left = "look_left"; j.action_right = "look_right"; j.action_up = "look_up"; j.action_down = "look_down"
		root.add_child(j)
		sticks.append(j)
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	bar.position = Vector2(-560, 12)
	bar.add_theme_constant_override("separation", 10)
	root.add_child(bar)
	fly_btn = _button(bar, "Fly", func(): main.player.toggle_fly())
	_button(bar, "Map", func(): main.toggle_map())
	_button(bar, "Use", func(): main.player.press_door())
	_button(bar, "Settings", func(): show_settings(not panel.visible))
	var ud := VBoxContainer.new()
	ud.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	ud.position = Vector2(-140, -120)
	root.add_child(ud)
	for a in ["up", "down"]:
		var b := Button.new()
		b.text = a.capitalize()
		b.custom_minimum_size = Vector2(120, 100)
		b.focus_mode = Control.FOCUS_NONE
		b.button_down.connect(func(): Input.action_press(a))
		b.button_up.connect(func(): Input.action_release(a))
		ud.add_child(b)
		updown.append(b)
	_settings(root)
	refresh()

func _button(parent: Control, text: String, f: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(120, 64)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(f)
	parent.add_child(b)
	return b

func _settings(root: Control) -> void:
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-330, -170)
	panel.custom_minimum_size = Vector2(660, 340)
	panel.visible = false
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	var t := Label.new()
	t.text = "Settings"
	t.add_theme_font_size_override("font_size", 28)
	v.add_child(t)
	var row := HBoxContainer.new()
	v.add_child(row)
	var l := Label.new(); l.text = "Quality  "; row.add_child(l)
	tier_opt = OptionButton.new()
	for s in ["Automatic", "Full (laptops)", "Lean (phones)"]:
		tier_opt.add_item(s)
	tier_opt.item_selected.connect(_on_tier)
	row.add_child(tier_opt)
	tier_note = Label.new()
	tier_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tier_note.custom_minimum_size = Vector2(620, 0)
	v.add_child(tier_note)
	var row2 := HBoxContainer.new()
	v.add_child(row2)
	var l2 := Label.new(); l2.text = "Touch controls  "; row2.add_child(l2)
	touch_opt = OptionButton.new()
	for s in ["Automatic", "Always", "Never"]:
		touch_opt.add_item(s)
	touch_opt.item_selected.connect(_on_touch)
	row2.add_child(touch_opt)
	extra = VBoxContainer.new()
	v.add_child(extra)
	var help := Label.new()
	help.text = "Keyboard: W A S D to walk, Shift to run, mouse to look (click the view), F to fly (Space and C up and down), M for the map, E to open a door or the card of the part in the middle of the view (or click or tap a part), L alarms, P procedures and tours, K pause and run, the full stop to fast-forward, H to the control room and its screens (there: the arrows move between items, Enter opens one, Page Up and Down change screen, + and − zoom), Esc for this panel or to close the top one. Gamepad: sticks, Y fly, Back map, A use, Start settings, D-pad up alarms, left procedures, down pause, right fast-forward, X the control room's screens (D-pad between items, A opens one, LB and RB change screen), B closes a panel."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(620, 0)
	v.add_child(help)
	_button(v, "Close", func(): show_settings(false))

func show_settings(on: bool) -> void:
	panel.visible = on
	refresh()
	if on:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		var mode: String = main.cf.get_value("quality", "mode", "auto")
		tier_opt.selected = ["auto", "full", "lean+vis"].find(mode)
		touch_opt.selected = ["auto", "on", "off"].find(main.cf.get_value("controls", "touch", "auto"))
		tier_note.text = "Now: %s (%s), %s renderer." % [main.tier, main.tier_why, Quality.renderer()]

func _on_tier(i: int) -> void:
	main.cf.set_value("quality", "mode", ["auto", "full", "lean+vis"][i])
	Quality.save(main.cf)
	main.choose_tier()
	show_settings(true)

func _on_touch(i: int) -> void:
	main.cf.set_value("controls", "touch", ["auto", "on", "off"][i])
	Quality.save(main.cf)
	refresh()

func touch_on() -> bool:
	var t: String = main.cf.get_value("controls", "touch", "auto")
	return t == "on" or (t == "auto" and DisplayServer.is_touchscreen_available())

func refresh() -> void:
	var screens: bool = main.ui != null and main.ui.screens_open()      # the control room screens take the view
	main.player.input_enabled = not (main.map.active or panel.visible or main.probing or screens)
	var touch := touch_on()
	for s in sticks:
		s.visible = touch and not main.map.active and not screens
	var flying: bool = main.player.mode == Player.Mode.FLY
	fly_btn.text = "Walk" if flying else "Fly"
	for b in updown:
		b.visible = touch and flying and not main.map.active

func _process(_d: float) -> void:
	var p: Vector3 = main.player.global_position
	var mode: String = ["walking", "flying", "on a ladder"][main.player.mode]
	status.text = "%s · %s · x %.0f  y %.0f  +%.1f m · %s" % [main.area_at(p), mode, p.x, -p.z, p.y, main.tier]
