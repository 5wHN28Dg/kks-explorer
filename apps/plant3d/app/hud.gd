## What lies over the view: the touch controls (two sticks: move on the left, look on the right, Godot's own
## VirtualJoystick driving the same actions as a gamepad's sticks), the buttons (walk/fly, map, use, up and down in
## flight, settings), a line saying where the trainee is and how, and the settings panel (the quality tier, with
## "Automatic" saying what it chose and why, the touch controls, the walking pace and whether the run key toggles, and
## About: app/about.gd). With a gamepad in use (app/input_mode.gd) the touch controls hide and the bar names the
## gamepad's buttons; touching the screen brings them back.
extends CanvasLayer

const Cost = preload("res://app/script_cost.gd")   # where the scripts' time goes (a measured walk)

const Quality = preload("res://app/quality.gd")
const Player = preload("res://app/player.gd")
const About = preload("res://app/about.gd")
const InputMode = preload("res://app/input_mode.gd")
const TOUCH := ["auto", "on", "off"]   # the settings' values of "Touch controls": Automatic, Always, Never

var main   # app/main.gd
var status: Label
var input: InputMode           # gamepad or touch in use
var touch_screen := DisplayServer.is_touchscreen_available()   # (the tests set it: headless has none)
var pad_hint: Label            # the gamepad's buttons, under the status line while the gamepad is in use
var map_btn: Button
var settings_btn: Button
var sticks: Array = []
var fly_btn: Button
var use_btn: Button
var updown: Array = []
var panel: PanelContainer
var tier_opt: OptionButton
var touch_opt: OptionButton
var pace_opt: OptionButton
var run_toggle_cb: CheckBox
var tier_note: Label
var extra: VBoxContainer       # rows the interaction layer adds (ui/plant_ui.gd: instructor mode, motion, sound)
var settings_box: VBoxContainer
var about: About               # shown in the settings panel in place of the settings, the panel made larger
var about_btn: Button
var close_btn: Button
var settings_head: HBoxContainer   # the settings' title row: the title, About and Close (always on screen)
var settings_scroll: ScrollContainer   # the settings' body, under the title row
var controls_btn: Button       # "Controls": folds the keyboard and gamepad help (controls_help) open and shut
var controls_help: Label
var _fit_queued := false
const SETTINGS_W := 700.0      # the settings panel's width (less on a narrower canvas)
const SETTINGS_MARGIN := 16.0  # the least room left round the settings panel (as the layer's panels)
const SETTINGS_TOP := 160.0    # where it may begin without the interaction layer (below the HUD's buttons)

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
	pad_hint = Label.new()
	pad_hint.name = "pad_hint"
	pad_hint.position = Vector2(16, 44)
	pad_hint.add_theme_font_size_override("font_size", 18)
	pad_hint.add_theme_constant_override("outline_size", 6)
	pad_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	pad_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(pad_hint)
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
	# right-aligned in a fixed width, Fly and Use first: when the gamepad hides them (or a touch brings them back)
	# Map and Settings stay where they are, so that the tap that switches lands on the button it began on
	bar.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(bar)
	fly_btn = _button(bar, "Fly", func(): main.player.toggle_fly())
	use_btn = _button(bar, "Use", func(): main.player.press_door())
	map_btn = _button(bar, "Map", func(): main.toggle_map())
	settings_btn = _button(bar, "Settings", func(): show_settings(not panel.visible))
	bar.size = Vector2(4 * 120 + 3 * 10, 64)
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
	input = InputMode.new()
	input.name = "input_mode"
	input.scan()
	input.changed.connect(_on_input_changed)
	_place_input.call_deferred()
	apply_gait()
	refresh()

## The input mode goes last under the window's root (app/input_mode.gd: it sees every event first); it goes with the HUD.
func _place_input() -> void:
	if is_inside_tree() and input != null and not input.is_inside_tree():
		get_tree().root.add_child(input)

func _exit_tree() -> void:
	if input != null and is_instance_valid(input):
		if input.is_inside_tree():
			input.queue_free()
		elif input.get_parent() == null:   # never placed: nothing else frees it
			input.free()
		# else: out of the tree but still under the root, which is tearing the tree down at a quit (it left before
		# the HUD: it is the root's last child) and frees it itself; freeing it here corrupted the heap (tests/test_app_quit.gd)
		input = null

func _button(parent: Control, text: String, f: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(120, 64)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(f)
	parent.add_child(b)
	return b

## The settings panel: a title row with About and Close that stays put, and the settings under it in a body that
## scrolls when they don't fit (on a short canvas, or the phone's larger text): Close is always on screen, and the
## keyboard's and gamepad's focus reaches every control (the body follows it). The long keyboard and gamepad help is
## folded under its own button ("Controls"). Sized to its content, at most the canvas less a margin (_fit_settings).
func _settings(root: Control) -> void:
	panel = PanelContainer.new()
	panel.name = "settings"
	panel.visible = false
	root.add_child(panel)
	root.resized.connect(_queue_fit)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	settings_box = v
	about = About.new()
	about.closed.connect(_about_closed)
	panel.add_child(about)
	settings_head = HBoxContainer.new()
	settings_head.name = "head"
	settings_head.add_theme_constant_override("separation", 10)
	v.add_child(settings_head)
	var t := Label.new()
	t.text = "Settings"
	t.add_theme_font_size_override("font_size", 28)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_head.add_child(t)
	# these two take the keyboard and gamepad focus (ui_accept presses them, the D-pad moves between them)
	about_btn = _button(settings_head, "About", show_about)
	about_btn.focus_mode = Control.FOCUS_ALL
	close_btn = _button(settings_head, "Close", func(): show_settings(false))
	close_btn.name = "close"
	close_btn.focus_mode = Control.FOCUS_ALL
	settings_scroll = ScrollContainer.new()
	settings_scroll.name = "scroll"
	settings_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	settings_scroll.follow_focus = true        # the control the keyboard or gamepad moves to scrolls into view
	v.add_child(settings_scroll)
	var body := VBoxContainer.new()
	body.name = "body"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	body.minimum_size_changed.connect(_queue_fit)
	settings_scroll.add_child(body)
	var row := HBoxContainer.new()
	body.add_child(row)
	var l := Label.new(); l.text = "Quality  "; row.add_child(l)
	tier_opt = OptionButton.new()
	tier_opt.focus_mode = Control.FOCUS_ALL
	for s in ["Automatic", "Full (laptops)", "Lean (phones)"]:
		tier_opt.add_item(s)
	tier_opt.item_selected.connect(_on_tier)
	row.add_child(tier_opt)
	tier_note = Label.new()
	tier_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(tier_note)
	var row2 := HBoxContainer.new()
	body.add_child(row2)
	var l2 := Label.new(); l2.text = "Touch controls  "; row2.add_child(l2)
	touch_opt = OptionButton.new()
	touch_opt.focus_mode = Control.FOCUS_ALL
	for s in ["Automatic", "Always", "Never"]:
		touch_opt.add_item(s)
	touch_opt.item_selected.connect(_on_touch)
	row2.add_child(touch_opt)
	var touch_note := Label.new()
	touch_note.name = "touch_note"
	touch_note.text = "Automatic: the sticks and walking buttons show on a touch screen, and hide while a gamepad is in use (connected, or its buttons or sticks used); touching the screen brings them back until the gamepad is used again, and they come back when the last gamepad is disconnected. Always: shown, gamepad or not. Never: hidden (walk with a gamepad or the keyboard)."
	touch_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(touch_note)
	var row_g := HFlowContainer.new()
	body.add_child(row_g)
	var lg := Label.new(); lg.text = "Walking pace  "; row_g.add_child(lg)
	pace_opt = OptionButton.new()
	pace_opt.focus_mode = Control.FOCUS_ALL
	for s in ["Slow", "Normal", "Brisk"]:
		pace_opt.add_item(s)
	pace_opt.item_selected.connect(_on_pace)
	row_g.add_child(pace_opt)
	run_toggle_cb = CheckBox.new()
	run_toggle_cb.text = "Run key toggles (no need to hold it)"
	run_toggle_cb.focus_mode = Control.FOCUS_ALL
	run_toggle_cb.toggled.connect(_on_run_toggle)
	row_g.add_child(run_toggle_cb)
	extra = VBoxContainer.new()
	body.add_child(extra)
	# the keyboard's and gamepad's controls, folded: opened, the body scrolls to show them
	controls_btn = Button.new()
	controls_btn.name = "controls"
	controls_btn.text = "Controls: keyboard and gamepad"
	controls_btn.toggle_mode = true
	controls_btn.focus_mode = Control.FOCUS_ALL
	controls_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	body.add_child(controls_btn)
	controls_help = Label.new()
	controls_help.name = "controls_help"
	controls_help.text = "Keyboard: W A S D to walk, Shift to run (held, or pressed once with \"Run key toggles\"), mouse to look (click the view), F to fly (Space and C up and down), M for the map, E to open a door or the card of the part in the middle of the view (or click or tap a part), L alarms, P procedures and tours, T permits to work, K pause and run, the full stop to fast-forward, H to the control room and its screens (there: the arrows move between items, Enter opens one, Page Up and Down change screen, + and − zoom), Esc for this panel or to close the top one. Gamepad: the left stick walks (push it a little to step slowly, further to walk, all the way to jog; click it to run), the right one looks, Y fly, Back map, A use, Start settings, D-pad up alarms, left procedures, down pause, right fast-forward, X the control room's screens (D-pad between items, A opens one, LB and RB change screen), B closes a panel."
	controls_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls_help.visible = false
	body.add_child(controls_help)
	controls_btn.toggled.connect(func(on: bool):
		controls_help.visible = on
		if on:
			_show_controls_help.call_deferred())

## The opened help scrolled into view (after the layout has placed it), its button kept in view above it.
func _show_controls_help() -> void:
	await get_tree().process_frame
	if controls_help.visible:
		settings_scroll.ensure_control_visible(controls_help)
		settings_scroll.ensure_control_visible(controls_btn)

## The panel's size again at the next frame (its content or the canvas changed).
func _queue_fit() -> void:
	if not _fit_queued:
		_fit_queued = true
		_fit_settings.call_deferred()

## The settings panel centred below the bars (the HUD's buttons and the interaction layer's: ui/plant_ui.gd
## panels_top), as tall as its content but at most the room there less a margin: the title row with Close stays on
## screen and the body scrolls under it. (About has the whole canvas less a margin: show_about.)
func _fit_settings() -> void:
	_fit_queued = false
	if panel == null or about.visible:
		return
	var vs: Vector2 = (panel.get_parent() as Control).size
	if vs.x <= 0.0 or vs.y <= 0.0:
		return
	var top: float = main.ui.panels_top() if main != null and main.ui != null and main.ui.has_method("panels_top") \
		else SETTINGS_TOP
	var room := maxf(vs.y - top - SETTINGS_MARGIN, 200.0)
	var pad := panel.get_theme_stylebox("panel").get_minimum_size()
	var w := minf(SETTINGS_W, vs.x - 2.0 * SETTINGS_MARGIN)
	var body: Control = settings_scroll.get_child(0)
	var want := settings_head.get_combined_minimum_size().y + float(settings_box.get_theme_constant("separation")) \
		+ body.get_combined_minimum_size().y + pad.y
	var h := minf(want, room)
	var y := top + (room - h) * 0.5
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = -w * 0.5
	panel.offset_right = w * 0.5
	panel.offset_top = y
	panel.offset_bottom = y + h

## Gamepad A acts as ui_accept on the focused control of the settings panel (Godot's ui_accept has no gamepad button;
## the walker's "use" is off while the panel shows): a button is pressed, a check box toggled, a disabled one left.
func _input(e: InputEvent) -> void:
	if panel == null or not panel.visible or not (e is InputEventJoypadButton and e.button_index == JOY_BUTTON_A):
		return
	var fo := panel.get_viewport().gui_get_focus_owner()
	if fo == null or not panel.is_ancestor_of(fo) or not fo.is_visible_in_tree():
		return
	get_viewport().set_input_as_handled()
	var a := InputEventAction.new()
	a.action = "ui_accept"
	a.pressed = e.pressed
	get_viewport().push_input(a)

## About in the settings panel: the panel fills the screen but for a margin while it shows.
func show_about() -> void:
	if about.visible:
		return
	if not panel.visible:
		show_settings(true)
	settings_box.visible = false
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 40)
	about.open()

func _about_closed() -> void:
	settings_box.visible = true
	_fit_settings()
	if panel.visible:
		about_btn.grab_focus()

func show_settings(on: bool) -> void:
	if not on and about.visible:
		about.close()
	panel.visible = on
	if on:
		_fit_settings()
		_queue_fit()                         # again once the body's wrapped text has its width
	refresh()
	if not on and main.ui != null and main.ui.mimic != null:
		main.ui.mimic.take_focus()          # the screens' canvas again, when they are open
	if on:
		if not about.visible:
			about_btn.grab_focus()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		var mode: String = main.cf.get_value("quality", "mode", "auto")
		tier_opt.selected = ["auto", "full", "lean+vis"].find(mode)
		touch_opt.selected = TOUCH.find(touch_setting())
		var pi: int = Player.PACES.keys().find(main.cf.get_value("controls", "pace", "normal"))
		pace_opt.selected = pi if pi >= 0 else Player.PACES.keys().find("normal")     # as apply_gait: unknown is normal
		run_toggle_cb.set_pressed_no_signal(main.cf.get_value("controls", "run_toggle", false))
		tier_note.text = "Now: %s (%s), %s renderer." % [main.tier, main.tier_why, Quality.renderer()]

func _on_tier(i: int) -> void:
	main.cf.set_value("quality", "mode", ["auto", "full", "lean+vis"][i])
	Quality.save(main.cf)
	main.choose_tier()
	show_settings(true)

func _on_touch(i: int) -> void:
	main.cf.set_value("controls", "touch", TOUCH[i])
	Quality.save(main.cf)
	refresh()

func _on_pace(i: int) -> void:
	main.cf.set_value("controls", "pace", Player.PACES.keys()[i])
	Quality.save(main.cf)
	apply_gait()

func _on_run_toggle(on: bool) -> void:
	main.cf.set_value("controls", "run_toggle", on)
	Quality.save(main.cf)
	apply_gait()

## The walker's pace and run key from the settings file.
func apply_gait() -> void:
	main.player.pace = Player.PACES.get(main.cf.get_value("controls", "pace", "normal"), Player.WALK_SPEED)
	main.player.run_toggle = main.cf.get_value("controls", "run_toggle", false) == true

## The settings' "Touch controls": "auto" (Automatic, the default), "on" (Always) or "off" (Never). Saved settings keep
## their meaning: "on" and "off" were the explicit choices before the gamepad switch and still are; anything else (an
## unknown value, a hand-edited true or false) reads as its nearest: true Always, false Never, else Automatic.
func touch_setting() -> String:
	var t = main.cf.get_value("controls", "touch", "auto")
	if t is bool:
		return "on" if t else "off"
	return t if t is String and t in TOUCH else "auto"

## The touch controls show: Always; or Automatic on a touch screen while the gamepad is not the controls in use.
func touch_on() -> bool:
	var t := touch_setting()
	return t == "on" or (t == "auto" and touch_screen and not pad_on())

## The gamepad is the controls in use (app/input_mode.gd).
func pad_on() -> bool:
	return input != null and input.pad

func _on_input_changed(_pad: bool) -> void:
	refresh()
	if pad_on() and focus_panel():
		input.swallow = true     # the press that gave a panel the focus doesn't also move it on, or act

## A gamepad has just become the controls: the panel on top takes the focus, so that the D-pad and A work it at once
## (panels opened while touching took none). True when it gave the focus to something.
func focus_panel() -> bool:
	var fo := get_viewport().gui_get_focus_owner()
	if panel.visible:
		if fo == null or not panel.is_ancestor_of(fo):
			if about.visible:
				about.back.grab_focus()
			else:
				about_btn.grab_focus()
			return true
		return false
	return main.ui != null and main.ui.focus_top()

func refresh() -> void:
	var screens: bool = main.ui != null and main.ui.views_open()      # the control room screens or the drawings take the view
	main.player.input_enabled = not (main.map.active or panel.visible or main.probing or screens or main.workshop_open())
	var touch := touch_on()
	var pad := pad_on() and not touch       # (with touch controls Always, the bar stays as it is)
	var away: bool = main.workshop_open()   # the Workshop: its own camera reads the sticks' actions
	for s in sticks:
		_show(s, touch and not main.map.active and not screens and not away, [s.action_left, s.action_right, s.action_up, s.action_down])
	var flying: bool = main.player.mode == Player.Mode.FLY
	fly_btn.text = "Walk" if flying else "Fly"
	fly_btn.visible = not screens and not pad   # walking and flying do nothing on the screens; Y on a gamepad
	use_btn.visible = not screens and not pad   # A on a gamepad
	for i in updown.size():
		_show(updown[i], touch and flying and not main.map.active and not screens and not away, [["up", "down"][i]])
	pad_hint.visible = pad and not main.map.active
	if screens and main.ui.drawings_open():
		pad_hint.text = "Gamepad: left stick pans, triggers zoom, A opens what is under the cross, LB RB sheets, B leaves"
	elif screens:
		pad_hint.text = "Gamepad: D-pad or left stick between items, A opens, LB RB screens, X or B leaves"
	elif flying:
		pad_hint.text = "Gamepad: Y walk, RB up, LB down, A use, Back map, Start settings, X control room, B closes"
	else:
		pad_hint.text = "Gamepad: Y fly, A use or a part's card, Back map, Start settings, X control room, D-pad alarms procedures pause fast, B closes"

## Hides or shows a touch control. Hidden while a thumb holds it, Godot's VirtualJoystick (and a held button) would
## keep its actions pressed and the walker walking: they are let go, and what a gamepad or a key holds for the same
## actions is pressed again (the gamepad's push that hid the stick is already counted in when this runs). A hidden
## VirtualJoystick still follows the drags of the thumb that held it (measured, 4.7.2): it is stopped while hidden.
func _show(c: Control, on: bool, actions: Array) -> void:
	if c.visible == on:
		return
	c.visible = on
	c.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	if on:
		return
	for a in actions:
		Input.action_release(a)
		var s := held(a)
		if s > 0.0:
			Input.action_press(a, s)

## How strongly a gamepad or a key holds an action now (0 when none does).
static func held(action: StringName) -> float:
	var s := 0.0
	var dz := InputMap.action_get_deadzone(action)
	for e in InputMap.action_get_events(action):
		if e is InputEventKey and Input.is_physical_key_pressed(e.physical_keycode):
			s = 1.0
		elif e is InputEventJoypadButton:
			for d in Input.get_connected_joypads():
				if Input.is_joy_button_pressed(d, e.button_index):
					s = 1.0
		elif e is InputEventJoypadMotion:
			for d in Input.get_connected_joypads():
				var v := Input.get_joy_axis(d, e.axis) * signf(e.axis_value)
				if v > dz:
					s = maxf(s, clampf(inverse_lerp(dz, 1.0, v), 0.0, 1.0))
	return s

func _process(_d: float) -> void:
	var _c0 := Time.get_ticks_usec()
	_each_frame(_d)
	Cost.add(Cost.OTHER, _c0)


func _each_frame(_d: float) -> void:
	var p: Vector3 = main.player.global_position
	var mode: String = ["walking", "flying", "on a ladder"][main.player.mode]
	if main.player.mode == Player.Mode.WALK and Vector2(main.player.velocity.x, main.player.velocity.z).length() > Player.JOG_SPEED + 0.2:
		mode = "running"
	status.text = "%s · %s · x %.0f  y %.0f  +%.1f m · %s" % [main.area_at(p), mode, p.x, -p.z, p.y, main.tier]
