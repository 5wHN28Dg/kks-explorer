## What lies over the view: the touch controls (two sticks: move on the left, look on the right, Godot's own
## VirtualJoystick driving the same actions as a gamepad's sticks), the buttons (walk/fly, map, use, up and down in
## flight, settings), a line saying where the trainee is and how, and the settings panel (the quality tier, with
## "Automatic" saying what it chose and why, the UI size, the touch controls, the walking pace and whether the run key
## toggles, and About: app/about.gd). With a gamepad in use (app/input_mode.gd) the touch controls hide and the bar
## names the gamepad's buttons; touching the screen brings them back.
extends CanvasLayer

const Cost = preload("res://app/script_cost.gd")   # where the scripts' time goes (a measured walk)

const Quality = preload("res://app/quality.gd")
const Player = preload("res://app/player.gd")
const About = preload("res://app/about.gd")
const Report = preload("res://app/report.gd")
const W = preload("res://ui/widgets.gd")
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
var report: Report              # "Report a problem" (#446), from About, in its place; null while switched off
var report_btn: Button          # About's "Report a problem"
var close_btn: Button
var settings_head: HBoxContainer   # the settings' title row: the title, About and Close (always on screen)
var settings_scroll: ScrollContainer   # the settings' body, under the title row
var controls_btn: Button       # "Controls": folds the keyboard and gamepad help (controls_help) open and shut
var controls_help: Label
var _fit_queued := false
var hud_root: Control
var bar: HBoxContainer           # Fly, Use, Map, Settings at the top right
var top_box: VBoxContainer       # the status line and the gamepad's buttons at the top left
var _status_h := 0.0             # top_box's height (the most it had since the last reset: _measure_status)
var _status_len := Vector2i(-1, -1)   # the lengths of the status line's and the gamepad line's texts last measured
signal top_changed               # top_bottom() may have changed: the interaction layer's bar moves (ui/plant_ui.gd)
const BUTTON := Vector2(120, 64) # the HUD's buttons at UI scale 1
const STATUS_W_MIN := 500.0      # the status line goes to the bottom when it has less beside the buttons (at scale 1)
var _status_low := false         # the status line at the bottom (_layout_top)
## The compact bar (ui/plant_ui.gd compact: a phone): the HUD's buttons as narrow as their words, Settings in the
## layer's More, the status line at the bottom, and the layer's buttons in the same row left of them.
var compact := false
const COMPACT_MARGIN := 16.0     # right of the HUD's buttons in the compact row (the full bar keeps 50)
## Up and Down (flying, touch): right of the middle, below the bars (place_updown)
var updown_box: VBoxContainer
var ui_size_opt: OptionButton    # the settings' UI size (100 % to 200 %, ui/widgets.gd ui_size)
var ui_size_steps: Array = []    # its Smaller and Larger buttons
var settings_layer: CanvasLayer
var _theme_scale := 0.0        # the UI scale the settings' theme was made for
const SETTINGS_W := 700.0      # the settings panel's width at UI scale 1 (less on a narrower canvas)
const SETTINGS_MARGIN := 16.0  # the least room left round the settings panel (as the layer's panels)
const SETTINGS_LAYER := 8      # the settings' canvas layer (_settings)
const SETTINGS_TOP := 160.0    # where it may begin without the interaction layer (below the HUD's buttons)

func setup(m) -> void:
	main = m
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	hud_root = root
	# the status line and the gamepad's buttons under it, left of the buttons; they wrap when the canvas is narrow
	# (a phone at a large UI size), and the interaction layer's bar goes below them (top_bottom)
	top_box = VBoxContainer.new()
	top_box.name = "top_box"
	top_box.position = Vector2(16, 12)
	top_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_box.add_theme_constant_override("separation", 0)
	root.add_child(top_box)
	status = Label.new()
	status.name = "status"
	status.add_theme_font_size_override("font_size", int(20 * W.scale))
	status.add_theme_constant_override("outline_size", 6)
	status.add_theme_color_override("font_outline_color", Color.BLACK)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_box.add_child(status)
	pad_hint = Label.new()
	pad_hint.name = "pad_hint"
	pad_hint.add_theme_font_size_override("font_size", int(18 * W.scale))
	pad_hint.add_theme_constant_override("outline_size", 6)
	pad_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	pad_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pad_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pb := StyleBoxFlat.new()          # (a backing: it may lie over the screens or the drawings, K5)
	pb.bg_color = Color(0.05, 0.05, 0.06, 0.85)
	pb.set_content_margin_all(4)
	pad_hint.add_theme_stylebox_override("normal", pb)
	top_box.add_child(pad_hint)
	# the two sticks (shown on touch screens, or when chosen in the settings)
	for side in [["move", Control.PRESET_BOTTOM_LEFT], ["look", Control.PRESET_BOTTOM_RIGHT]]:
		var j := VirtualJoystick.new()
		j.name = side[0] + "_stick"
		j.set_anchors_preset(side[1])
		# (sized and placed by _layout_sticks: a thumb's size whatever the UI size)
		j.joystick_mode = 1   # dynamic: the stick appears where the thumb lands
		if side[0] == "move":
			j.action_left = "move_left"; j.action_right = "move_right"; j.action_up = "move_forward"; j.action_down = "move_back"
		else:
			j.action_left = "look_left"; j.action_right = "look_right"; j.action_up = "look_up"; j.action_down = "look_down"
		root.add_child(j)
		sticks.append(j)
	bar = HBoxContainer.new()
	bar.name = "hud_bar"
	bar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	bar.add_theme_constant_override("separation", 10)
	# right-aligned in a fixed width, Fly and Use first: when the gamepad hides them (or a touch brings them back)
	# Map and Settings stay where they are, so that the tap that switches lands on the button it began on
	bar.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(bar)
	fly_btn = _button(bar, "Fly", func(): main.player.toggle_fly())
	use_btn = _button(bar, "Use", func(): main.player.press_door())
	map_btn = _button(bar, "Map", func(): main.toggle_map())
	settings_btn = _button(bar, "Settings", func(): show_settings(not panel.visible))
	_layout_sticks()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE   # (its empty part lies over nothing it should take)
	_place_bar()
	bar.offset_top = 12.0
	bar.offset_bottom = 12.0 + button_h()
	root.resized.connect(_layout_top)
	pad_hint.visibility_changed.connect(_status_reset)
	_layout_top()
	var ud := VBoxContainer.new()
	ud.name = "updown"
	updown_box = ud
	ud.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	ud.offset_left = -140.0 * W.scale
	ud.offset_top = -120.0 * W.scale
	root.add_child(ud)
	for a in ["up", "down"]:
		var b := Button.new()
		b.text = a.capitalize()
		b.custom_minimum_size = Vector2(120, 100) * W.scale
		b.add_theme_font_size_override("font_size", int(22 * W.scale))
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

## The HUD's buttons' row at the top right: four 120 px buttons 50 px from the edge; in the compact bar Fly (or Walk),
## Use and Map, each as wide as the widest of their words (a touch that brings Fly and Use back moves nothing), Settings
## in the layer's More.
func _place_bar() -> void:
	var bw := 4.0 * BUTTON.x * W.scale + 3.0 * 10.0
	var right := 50.0
	var bw1 := BUTTON.x * W.scale
	if compact:
		bw1 = compact_button_w()
		bw = 3.0 * bw1 + 2.0 * 10.0
		right = COMPACT_MARGIN
	for b in [fly_btn, use_btn, map_btn, settings_btn]:
		b.custom_minimum_size.x = bw1
	settings_btn.visible = not compact
	# (offsets from the right edge: a position would be taken from the canvas's width at this moment)
	bar.offset_left = -bw - right
	bar.offset_right = -right

## A HUD button's width in the compact bar: its widest word and the button's margins, square at the least.
func compact_button_w() -> float:
	var f: Font = fly_btn.get_theme_font("font")
	var fs: int = fly_btn.get_theme_font_size("font_size")
	var w := 0.0
	for t in ["Walk", "Fly", "Use", "Map"]:
		w = maxf(w, f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	return maxf(ceilf(w) + fly_btn.get_theme_stylebox("normal").get_minimum_size().x, button_h())

## The width the HUD's buttons take at the right in the compact bar, their margin included.
func compact_width() -> float:
	return 3.0 * compact_button_w() + 2.0 * 10.0 + COMPACT_MARGIN

## The compact bar on or off (ui/plant_ui.gd _set_compact).
func set_compact(on: bool) -> void:
	if on == compact:
		return
	compact = on
	_place_bar()
	_layout_top()

## The HUD's buttons' height: 64 px on a desktop; on a phone the layer's buttons' (ui/widgets.gd: 52 at its scale),
## which reaches 48 dp at the phone's UI size (issue #382).
static func button_h() -> float:
	return maxf(BUTTON.y, 52.0 * W.scale)

## Where the HUD's top ends: below its buttons, and below the status line and the gamepad's buttons (which wrap on a
## narrow canvas). The interaction layer's bar goes below it (ui/plant_ui.gd _layout).
func top_bottom() -> float:
	var b := 12.0 + button_h()
	if top_box != null and not _status_low:
		b = maxf(b, top_box.position.y + _status_h)
	return b

## Up and Down at the middle of the right edge, or lower when the bars reach below their top there (a large UI size:
## the interaction layer's bar wraps), never over them (ui/plant_ui.gd _layout calls this with where its panels begin).
func place_updown(below: float) -> void:
	if updown_box == null or hud_root == null:
		return
	var top := maxf(-120.0 * W.scale, below - hud_root.size.y * 0.5)
	# never past the bottom (above the margin): on screen first, over the bar's lowest row if it must
	var h := updown_box.get_combined_minimum_size().y
	top = minf(top, hud_root.size.y * 0.5 - 16.0 - h)
	if not is_equal_approx(updown_box.offset_top, top):
		updown_box.offset_top = top

## The two sticks the same size on the screen at every UI size (a thumb does not grow with the text): 420 px square
## at 100 %, in the bottom corners, less at a larger size (the canvas's units are larger).
func _layout_sticks() -> void:
	var k := 1.0 / W.ui_size
	for j in sticks:
		var left: bool = j.name == "move_stick"
		j.custom_minimum_size = Vector2(420, 420) * k
		j.offset_left = 20.0 * k if left else -440.0 * k
		j.offset_right = j.offset_left + 420.0 * k
		j.offset_top = -440.0 * k
		j.offset_bottom = -20.0 * k
		j.joystick_size = 220.0 * k
		j.tip_size = 90.0 * k

## The status line's room: as wide as the canvas leaves left of the buttons.
func _layout_top() -> void:
	if hud_root == null or bar == null:
		return
	_layout_sticks()
	# beside the buttons where there is room for a line of it; else at the bottom between the sticks' corners (a
	# narrow canvas, a large UI size: beside the buttons it wrapped onto many lines and pushed the bars and every
	# panel down). Down there it hides while a panel or view is open (it would lie under it: _each_frame).
	var w := hud_root.size.x - bar.size.x - 50.0 - 16.0 - 24.0
	var low := compact or w < STATUS_W_MIN * W.scale
	if low:
		w = hud_root.size.x - 2.0 * _stick_side()
	if absf(top_box.size.x - w) > 0.5 or low != _status_low:
		_status_low = low
		top_box.size = Vector2(w, 0)
		_status_reset()
	_place_status()

## The status box's place: at the top left, or at the bottom when it is low (its height known: _measure_status).
func _place_status() -> void:
	var at := Vector2(16, 12) if not _status_low else Vector2(_stick_side(), hud_root.size.y - _status_h - 8.0)
	if top_box.position != at:
		top_box.position = at

## The width of a stick's corner (its touch area and its margin: _layout_sticks).
func _stick_side() -> float:
	return 440.0 / W.ui_size

## The status box measured again (a new width, the gamepad's line shown or hidden).
func _status_reset() -> void:
	_status_h = 0.0
	_status_len = Vector2i(-1, -1)
	_measure_status()

## The status box's height, the most it has had since the last reset: the line's text changes as the trainee moves,
## and the bar below it does not jump each time it wraps one line more or less. Measured from the text at the box's
## width (a label's own size lags a frame behind a change, and is a word a line while it has no width yet); again when
## a text's length changes.
func _measure_status() -> void:
	if top_box == null:
		return
	var n := Vector2i(status.text.length(), pad_hint.text.length() if pad_hint.visible else -1)
	if n == _status_len:
		return
	_status_len = n
	var w := top_box.size.x
	var h := (_text_h(status, w) if status.visible else 0.0) + (_text_h(pad_hint, w) if pad_hint.visible else 0.0)
	if h > _status_h + 0.5:
		_status_h = h
		if _status_low:
			_place_status()
		else:
			top_changed.emit()

static func _text_h(l: Label, w: float) -> float:
	if l.text == "":
		return 0.0
	var f: Font = l.get_theme_font("font")
	var fs: int = l.get_theme_font_size("font_size")
	var line := f.get_height(fs)
	var sz := f.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, w, fs)
	var lines := maxi(1, roundi(sz.y / line))
	return lines * (line + l.get_theme_constant("line_spacing"))

func _button(parent: Control, text: String, f: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(BUTTON.x * W.scale, button_h())
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", int(22 * W.scale))
	b.pressed.connect(f)
	parent.add_child(b)
	return b

## The settings panel: a title row with About and Close that stays put, and the settings under it in a body that
## scrolls when they don't fit (on a short canvas, or the phone's larger text): Close is always on screen, and the
## keyboard's and gamepad's focus reaches every control (the body follows it). The long keyboard and gamepad help is
## folded under its own button ("Controls"). Sized to its content, at most the canvas less a margin (_fit_settings).
func _settings(_hud_root: Control) -> void:
	# on a layer of its own above the interaction layer's (ui/plant_ui.gd, 2): its side panels and the control room's
	# screens never cover the settings' Close (below the save offer, 10, and the Workshop, 60)
	settings_layer = CanvasLayer.new()
	settings_layer.name = "settings_layer"
	settings_layer.layer = SETTINGS_LAYER
	add_child(settings_layer)
	visibility_changed.connect(func(): settings_layer.visible = visible)   # hidden with the HUD (the Workshop)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	settings_layer.add_child(root)
	panel = PanelContainer.new()
	panel.name = "settings"
	panel.visible = false
	# opaque: it lies over the view and over the layer's panels, whose text would show through a translucent one (K5)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.11, 1.0)
	sb.border_color = Color(0.3, 0.33, 0.38)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sb)
	root.add_child(panel)
	root.resized.connect(_queue_fit)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	settings_box = v
	about = About.new()
	about.closed.connect(_about_closed)
	panel.add_child(about)
	if Report.switched_on():
		report = Report.new()
		report.main = main
		report.closed.connect(_report_closed)
		panel.add_child(report)
		report_btn = W.button("Report a problem", show_report)
		report_btn.name = "report_problem"
		about.add_child(report_btn)
		about.move_child(report_btn, about.back.get_index())   # above Back, which stays last
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
	tier_opt.accessibility_name = "Quality"
	for s in ["Automatic", "Full (laptops)", "Lean (phones)"]:
		tier_opt.add_item(s)
	tier_opt.item_selected.connect(_on_tier)
	row.add_child(tier_opt)
	tier_note = Label.new()
	tier_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(tier_note)
	# the UI size (issue #382): applied at once, the panel and everything else laid out again at the new size
	var row_s := HFlowContainer.new()
	row_s.name = "ui_size_row"
	body.add_child(row_s)
	var ls := Label.new(); ls.text = "UI size  "; row_s.add_child(ls)
	ui_size_opt = OptionButton.new()
	ui_size_opt.name = "ui_size"
	ui_size_opt.focus_mode = Control.FOCUS_ALL
	ui_size_opt.accessibility_name = "UI size"   # (its label is beside it, not its name: A5)
	for f in W.UI_SIZES:
		ui_size_opt.add_item(ui_size_text(f))
	ui_size_opt.item_selected.connect(_on_ui_size)
	row_s.add_child(ui_size_opt)
	# a step smaller or larger: on a phone the list is longer than the screen, and Android's finger doesn't scroll a
	# Godot list (seen on the Note 9: a drag moves the highlight), so its last sizes were out of reach
	for d in [["Smaller", -1], ["Larger", 1]]:
		var b := W.button(d[0], _step_ui_size.bind(d[1]))
		b.name = "ui_size_" + String(d[0]).to_lower()
		b.focus_mode = Control.FOCUS_ALL
		b.accessibility_name = "UI size " + String(d[0]).to_lower()
		row_s.add_child(b)
		ui_size_steps.append(b)
	var ui_note := Label.new()
	ui_note.name = "ui_size_note"
	ui_note.text = "Text, buttons and panels: larger, or smaller to see more of the plant. The size marked \"default\" is where this device starts: on a phone, the size that makes its buttons big enough for a finger."
	ui_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(ui_note)
	var row2 := HBoxContainer.new()
	body.add_child(row2)
	var l2 := Label.new(); l2.text = "Touch controls  "; row2.add_child(l2)
	touch_opt = OptionButton.new()
	touch_opt.focus_mode = Control.FOCUS_ALL
	touch_opt.accessibility_name = "Touch controls"
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
	pace_opt.accessibility_name = "Walking pace"
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
	# (the interaction layer's shared button, ui/widgets.gd; sized to its UI scale when the panel opens: show_settings)
	controls_btn = W.button("Controls: keyboard and gamepad", func(): pass)
	controls_btn.name = "controls"
	controls_btn.toggle_mode = true
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
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if is_instance_valid(controls_help) and controls_help.is_visible_in_tree():
		settings_scroll.ensure_control_visible(controls_help)
		# the button once the body has moved (its place is stale until then): when the help is taller than the view
		# (a short canvas, a large UI size) it begins just under the button, at the top of the view
		await get_tree().process_frame
		if is_instance_valid(controls_btn) and controls_btn.is_visible_in_tree():
			settings_scroll.ensure_control_visible(controls_btn)

## The panel's size again at the next frame (its content or the canvas changed).
func _queue_fit() -> void:
	if not _fit_queued:
		_fit_queued = true
		_fit_settings.call_deferred()

## The settings panel centred across, just below the bars (the HUD's buttons and the interaction layer's: ui/plant_ui.gd
## panels_top), as tall as its content but at most the room there less a margin: the title row with Close stays on
## screen and the body scrolls under it. (About has the whole canvas less a margin: show_about.)
func _fit_settings() -> void:
	_fit_queued = false
	if panel == null or about.visible or (report != null and report.visible):
		return
	var vs: Vector2 = (panel.get_parent() as Control).size
	if vs.x <= 0.0 or vs.y <= 0.0:
		return
	var top: float = main.ui.panels_top() if main != null and main.ui != null and main.ui.has_method("panels_top") \
		else SETTINGS_TOP
	# at least half the canvas's height: where the bars leave less (a phone at a large UI size with a gamepad's line
	# under the status) the panel rises over the bar's lower rows, its body still a few rows tall
	top = minf(top, settings_top_min(vs.y))
	var room := maxf(vs.y - top - SETTINGS_MARGIN, 200.0)
	var pad := panel.get_theme_stylebox("panel").get_minimum_size()
	var w := minf(SETTINGS_W * W.scale, vs.x - 2.0 * SETTINGS_MARGIN)
	var body: Control = settings_scroll.get_child(0)
	var want := settings_head.get_combined_minimum_size().y + float(settings_box.get_theme_constant("separation")) \
		+ body.get_combined_minimum_size().y + pad.y
	var h := minf(want, room)
	var y := top                  # from the top: opening the Controls help doesn't move Close or the button pressed
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = -w * 0.5
	panel.offset_right = w * 0.5
	panel.offset_top = y
	panel.offset_bottom = y + h
	# the control with the focus kept in view in the body made shorter (the bar above grew a row: a gamepad's line
	# under the status, a larger UI size)
	var fo := panel.get_viewport().gui_get_focus_owner() if panel.is_inside_tree() else null
	if fo != null and settings_scroll.is_ancestor_of(fo):
		_keep_in_view.call_deferred(fo)

func _keep_in_view(c: Control) -> void:
	if is_instance_valid(c) and c.is_visible_in_tree() and settings_scroll.is_ancestor_of(c):
		await get_tree().process_frame             # (once the body has its new size)
		if is_instance_valid(c) and c.is_visible_in_tree():
			settings_scroll.ensure_control_visible(c)

## The lowest the settings panel begins on a canvas `h` tall: it keeps half the height at least.
static func settings_top_min(h: float) -> float:
	return h * 0.5 - SETTINGS_MARGIN

## Gamepad B closes the settings (Godot's ui_cancel has no gamepad button). Gamepad A acts as ui_accept on the
## focused control of the settings panel (Godot's ui_accept has no gamepad button;
## the walker's "use" is off while the panel shows): a button is pressed, a check box toggled, a disabled one left.
func _input(e: InputEvent) -> void:
	if panel == null or not panel.visible or not e is InputEventJoypadButton:
		return
	# gamepad B closes the settings, the top layer (About, inside them, takes it first to go back: app/about.gd)
	if e.button_index == JOY_BUTTON_B and e.pressed and not about.visible and not (report != null and report.visible):
		get_viewport().set_input_as_handled()
		show_settings(false)
		return
	if e.button_index != JOY_BUTTON_A:
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

## "Report a problem", from About, in its place (the panel as large as About's).
func show_report() -> void:
	if report == null or report.visible:
		return
	if not panel.visible:
		show_settings(true)
	settings_box.visible = false
	about.visible = false
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 40)
	report.open()

func _report_closed() -> void:
	about.open()                     # back where it came from
	if report_btn != null:
		report_btn.grab_focus()

func _about_closed() -> void:
	settings_box.visible = true
	_fit_settings()
	if panel.visible:
		about_btn.grab_focus()

func show_settings(on: bool) -> void:
	if not on and report != null and report.visible:
		report.visible = false       # (closed with the settings: not back to About; they open as the settings again)
		settings_box.visible = true
	if not on and about.visible:
		about.close()
	var was_on := panel.visible
	panel.visible = on
	if on:
		# the layer's theme (ui/widgets.gd: its buttons' fills and focus ring, its text size) at its UI scale, chosen
		# after the HUD is made; on the opaque panel the default theme's buttons barely showed
		if panel.theme == null or _theme_scale != W.scale:
			panel.theme = W.make_theme()
			_theme_scale = W.scale
		# the Controls button as the layer's buttons
		controls_btn.custom_minimum_size = Vector2(0, 52 * W.scale)
		controls_btn.add_theme_font_size_override("font_size", int(20 * W.scale))
		# the lists and the check box as tall as the layer's buttons (48 dp on a phone: UI-UX-POLICY T1)
		for c in [tier_opt, ui_size_opt, touch_opt, pace_opt, run_toggle_cb]:
			c.custom_minimum_size.y = 52 * W.scale
		if not was_on:                       # each opening as the first: the help folded, the body at its top
			controls_btn.set_pressed_no_signal(false)
			controls_help.visible = false
			settings_scroll.scroll_vertical = 0
		_fit_settings()
		_queue_fit()                         # again once the body's wrapped text has its width
	refresh()
	if not on and main.ui != null and main.ui.mimic != null:
		# the focus back to the top panel under the settings (a side panel, the drawings, the screens' canvas): the
		# About button that had it is hidden now
		if main.workshop_open():
			pass                            # (the Workshop opened from the settings takes its own focus)
		elif main.ui.wants_focus():
			main.ui.focus_top()
		else:
			main.ui.mimic.take_focus()      # the screens' canvas again, when they are open
	if on:
		if not about.visible:
			about_btn.grab_focus()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		var mode: String = main.cf.get_value("quality", "mode", "auto")
		tier_opt.selected = ["auto", "full", "lean+vis"].find(mode)
		for i in W.UI_SIZES.size():               # (the device's start marked: it is known once the app has started)
			ui_size_opt.set_item_text(i, ui_size_text(W.UI_SIZES[i]))
		ui_size_opt.selected = W.UI_SIZES.find(W.ui_size)
		_ui_size_steps_state()
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

## A UI size as the settings' list says it: "150 %", and "(default)" after the one this device starts at.
static func ui_size_text(f: float) -> String:
	return "%d %%" % roundi(f * 100.0) + (" (default)" if is_equal_approx(f, W.ui_size_default) else "")

## Smaller (-1) or Larger (+1): the next of the settings' sizes, applied and saved as a choice in the list is.
func _step_ui_size(d: int) -> void:
	var i := clampi(W.UI_SIZES.find(W.ui_size) + d, 0, W.UI_SIZES.size() - 1)
	if not is_equal_approx(W.UI_SIZES[i], W.ui_size):
		main.set_ui_size(W.UI_SIZES[i])
	ui_size_opt.selected = W.UI_SIZES.find(W.ui_size)
	_ui_size_steps_state()

func _ui_size_steps_state() -> void:
	if ui_size_steps.size() == 2:
		ui_size_steps[0].disabled = W.UI_SIZES.find(W.ui_size) <= 0
		ui_size_steps[1].disabled = W.UI_SIZES.find(W.ui_size) >= W.UI_SIZES.size() - 1

func _on_ui_size(i: int) -> void:
	main.set_ui_size(W.UI_SIZES[i])
	_ui_size_steps_state()

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
			if report != null and report.visible:
				report.back.grab_focus()
			elif about.visible:
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
	# (the screens over the whole compact row: ui/plant_ui.gd views_over_row; Map would lie over their tabs)
	map_btn.visible = not (main.ui != null and main.ui.get("views_over_row") == true and main.ui.screens_open())
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
	# a save that fails, for as long as it does (ui/autosave.gd, issue #473): first, so a narrow line never hides it
	var note: String = main.ui.autosave.save_note() if main.ui != null and main.ui.get("autosave") != null else ""
	if note != "":
		status.text = note + " · " + status.text
	_measure_status()
	if not _status_low and not status.visible:
		status.visible = true            # (it was hidden over a view in the compact layout, which has ended)
		_status_reset()
	if _status_low:
		var covered: bool = panel.visible or (main.ui != null and main.ui.has_method("covers_bottom") and main.ui.covers_bottom())
		# over the screens or the drawings the gamepad's line still shows (it says how they are worked), alone, on a
		# backing: the status line hides
		var pad_only: bool = covered and not panel.visible and pad_hint.visible and main.ui != null and main.ui.views_open()
		var show: bool = not covered or pad_only
		if status.visible == pad_only or top_box.visible != show:
			status.visible = not pad_only
			top_box.visible = show
			top_box.size = Vector2(hud_root.size.x - 2.0 * _stick_side(), 0)   # (shown again at its width)
			_status_reset()
