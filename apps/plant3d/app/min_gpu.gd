## The minimum GPU (decision 0076, the user's choice of 2026-11-19, #432): on Windows and Linux Walkdown Plant needs a
## graphics driver with Vulkan or Direct3D 12. When Godot found neither and fell back to its Compatibility renderer
## (OpenGL 3.3, or ANGLE on Direct3D 11), a message says so once, before the plant loads: what the computer lacks, that
## the plant will be slow (an Intel HD Graphics 4400 walked it at about 12 frames a second, #432), and Continue anyway
## or Quit, with "Don't show this again" kept in user://settings.cfg. Never on a phone (Android has its own path,
## decision 0041), never for a measurement started from the command line (walk=, shot=, mp= …: SCRIPTED), never without a display
## unless a test asks for it.
##
## Switched off until the owner's check (the user's UI and UX policy 8.5: a tier-2 change merges behind a switch that
## is off): the project setting `walkdown/min_gpu_message` (project.godot), turned on for the check by an override.cfg
## beside the exe ([walkdown] min_gpu_message=true), and by the owner's OK in project.godot.
##
## Keys: Tab and the arrows move between the box and the buttons, Enter or Space presses; Escape and gamepad B mean
## Continue anyway (they close the message, as they close any layer: the rulebook's N2; quitting is always a press).
extends CanvasLayer

const W = preload("res://ui/widgets.gd")
const Quality = preload("res://app/quality.gd")

const SECTION := "graphics"
const KEY_OFF := "min_gpu_notice_off"
const MEASURED_FPS := 12    # #432: the frame walk on an Intel HD Graphics 4400, 80–86 ms a frame median
## Command-line options of scripted starts (measurements, test clients: app/main.gd's list) that skip the message.
const SCRIPTED := ["walk", "shot", "mp", "mp_inputs", "probe", "seconds", "digest", "step", "voice", "crowd", "crews"]
const PAD := 8              # the words' margin inside their scroll (px)

## Tests only: the rendering method and the device kind as if Godot had reported them ("" and -1: the real ones).
static var renderer_override := ""
static var phone_override := -1

signal answered(go: bool)

var cf: ConfigFile
var panel: PanelContainer
var dont_show: CheckBox
var continue_button: Button
var quit_button: Button
var words: VBoxContainer
var scroll: ScrollContainer
var _done := false


## The switch (see above); `switch_override` for the tests (-1: the project setting).
static var switch_override := -1
static func switched_on() -> bool:
	return switch_override == 1 if switch_override >= 0 else bool(ProjectSettings.get_setting("walkdown/min_gpu_message", false))


static func renderer() -> String:
	return renderer_override if renderer_override != "" else RenderingServer.get_current_rendering_method()


static func on_phone() -> bool:
	return phone_override == 1 if phone_override >= 0 else Quality.is_phone()


## Whether the message is due at this start: a desktop on the Compatibility renderer, not turned off in the settings,
## not a measurement, and a display to show it on (or a test's renderer).
static func wanted(settings: ConfigFile, opts: Dictionary) -> bool:
	if not switched_on():
		return false
	if on_phone() or renderer() != "gl_compatibility":
		return false
	if bool(settings.get_value(SECTION, KEY_OFF, false)):
		return false
	for k in SCRIPTED:      # (a scripted or measured start never waits for a press)
		if opts.has(k):
			return false
	return DisplayServer.get_name() != "headless" or renderer_override != ""


func _init(settings: ConfigFile) -> void:
	cf = settings
	layer = 20
	name = "min_gpu"


func _ready() -> void:
	var back := ColorRect.new()
	back.color = Color(0.05, 0.06, 0.08)   # nothing is drawn behind it yet: the plant isn't loaded
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	back.theme = W.make_theme()
	back.theme.set_stylebox("focus", "ScrollContainer", back.theme.get_stylebox("focus", "Button"))
	add_child(back)
	panel = PanelContainer.new()
	panel.name = "panel"
	panel.accessibility_name = "Graphics below Walkdown Plant's minimum"
	back.add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	v.add_child(W.label("This computer's graphics are below what Walkdown Plant needs", 26))
	# the words scroll on a small window or a large UI size; the buttons stay below them, always on screen (the rulebook's N3)
	scroll = ScrollContainer.new()
	scroll.name = "words"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.draw_focus_border = true
	scroll.gui_input.connect(_scroll_keys)
	scroll.accessibility_name = "The message's text"
	v.add_child(scroll)
	# a margin inside the scroll: the focus ring (3 px, drawn over the scroll's edge) never covers the words
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, PAD)
	scroll.add_child(pad)
	words = VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(words)
	words.add_child(W.label(("Its graphics chip or driver lacks a feature Walkdown Plant needs, so the plant is drawn "
			+ "a slower way. It will probably run slowly and jerkily: on a similar laptop it showed about %d pictures a "
			+ "second, where smooth movement needs 30 or more.") % MEASURED_FPS, 20))
	words.add_child(W.label(("Walkdown Plant needs graphics that support %s (a graphics card's or computer's "
			+ "specifications list it). For example: Intel HD Graphics 510 or newer (computers from 2015 on), AMD Radeon "
			+ "HD 7700 or newer (not the low-end models), or NVIDIA GeForce GTX 600 or newer. If this computer's graphics are that new, updating "
			+ "its graphics driver (the software for its graphics) may fix this.")
			% ("Vulkan or Direct3D 12" if OS.get_name() == "Windows" else "Vulkan"), 20, W.DIM))
	dont_show = CheckBox.new()
	dont_show.name = "dont_show"
	dont_show.text = "Don't show this again"
	dont_show.focus_mode = Control.FOCUS_ALL
	dont_show.custom_minimum_size.y = 52 * W.scale
	dont_show.add_theme_font_size_override("font_size", int(20 * W.scale))
	# the box drawn light on the button's slate (Godot's own dark grey box hardly shows there: non-text contrast, A2), ticked or empty
	var px := int(22 * W.scale)
	dont_show.add_theme_icon_override("unchecked", box_icon(px, false))
	dont_show.add_theme_icon_override("checked", box_icon(px, true))
	v.add_child(dont_show)
	var row := HBoxContainer.new()
	v.add_child(row)
	continue_button = W.button("Continue anyway", func(): _answer(true), 220)
	continue_button.name = "continue"
	row.add_child(continue_button)
	quit_button = W.button("Quit", func(): _answer(false), 160)
	quit_button.name = "quit"
	row.add_child(quit_button)
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	continue_button.grab_focus.call_deferred()
	_place()
	_place.call_deferred()   # (again once the containers have laid the labels out at the panel's width)
	get_viewport().size_changed.connect(_on_resized)   # (a method: the connection goes with the node)


## The check box's icon, `px` square: a light outline, and when ticked a light fill with a dark tick.
static func box_icon(px: int, ticked: bool) -> ImageTexture:
	var light := Color(0.93, 0.93, 0.93)
	var img := Image.create_empty(px, px, false, Image.FORMAT_RGBA8)
	img.fill(light if ticked else Color(0, 0, 0, 0))
	var t := maxi(2, px / 10)
	for i in px:
		for k in t:
			for q in [Vector2i(i, k), Vector2i(i, px - 1 - k), Vector2i(k, i), Vector2i(px - 1 - k, i)]:
				img.set_pixelv(q, light)
	if ticked:
		var dark := Color(0.08, 0.09, 0.11)
		var a := Vector2(px * 0.22, px * 0.52)
		var b := Vector2(px * 0.42, px * 0.72)
		var c := Vector2(px * 0.78, px * 0.28)
		for seg in [[a, b], [b, c]]:
			for j in 64:
				var pt: Vector2 = seg[0].lerp(seg[1], j / 63.0)
				for dx in range(-t, t + 1):
					for dy in range(-t, t + 1):
						var q := Vector2i(roundi(pt.x) + dx, roundi(pt.y) + dy)
						if q.x >= 0 and q.y >= 0 and q.x < px and q.y < px and Vector2(dx, dy).length() <= t:
							img.set_pixelv(q, dark)
	return ImageTexture.create_from_image(img)


## Centred, at most 760 px wide, and never taller than the window: the words get the height they need, or what is
## left beside the title, the box and the buttons, and scroll.
func _place() -> void:
	if panel == null or not panel.is_inside_tree():
		return
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var w := minf(760.0 * W.scale, vs.x - 32.0)
	scroll.custom_minimum_size.y = 0.0
	panel.size = Vector2(w, 0)
	var rest := panel.get_combined_minimum_size().y      # the title, the box, the buttons and the margins
	scroll.custom_minimum_size.y = clampf(_words_height(w), 0.0, maxf(60.0 * W.scale, vs.y - 32.0 - rest))
	# words that don't all fit can be scrolled from the keyboard and gamepad: the scroll takes the focus then (Tab,
	# arrows or the D-pad up and down, Page Up and Down), with the focus ring (keyboard and gamepad reach everything: A18)
	var scrolls := _words_height(w) > scroll.custom_minimum_size.y + 1.0
	if not scrolls and scroll.has_focus():
		continue_button.grab_focus()   # (the words stop taking the focus: it goes on to Continue anyway, never nowhere)
	scroll.focus_mode = Control.FOCUS_ALL if scrolls else Control.FOCUS_NONE
	var h := panel.get_combined_minimum_size().y
	panel.size = Vector2(w, h)
	panel.position = Vector2((vs.x - w) * 0.5, maxf(16.0, (vs.y - h) * 0.5))


## The words' full height at the panel's width `w` (a ScrollContainer asks for no height of its own).
func _words_height(w: float) -> float:
	# the panel's margins and border (ui/widgets.gd make_theme), and room for the scroll bar
	var inner := w - 2.0 * 14.0 * W.scale - 2.0 - scroll.get_v_scroll_bar().get_combined_minimum_size().x - 2.0 * PAD
	var h := 0.0
	for l: Label in words.get_children():
		var fs := l.get_theme_font_size("font_size")
		var f := l.get_theme_font("font")
		var sz := f.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, inner, fs)
		var n := maxf(1.0, roundf(sz.y / f.get_height(fs)))
		h += sz.y + n * l.get_theme_constant("line_spacing")
	return h + (words.get_child_count() - 1) * 8.0 * W.scale + 8.0 + 2.0 * PAD


## The words scrolled from the keyboard and gamepad while they have the focus: the arrows and the D-pad (ui_up,
## ui_down) by a line, Page Up and Down by most of a page, Home and End.
func _scroll_keys(e: InputEvent) -> void:
	# (not the sticks: an axis sends an event for every small movement, which would race through the words)
	if not e.is_pressed() or e is InputEventJoypadMotion:
		return
	var line := 40.0 * W.scale
	var page := scroll.size.y * 0.9
	var top := maxf(0.0, scroll.get_v_scroll_bar().max_value - scroll.size.y)
	var at := float(scroll.scroll_vertical)
	var to := at
	if e.is_action_pressed("ui_down", true):
		to = at + line
	elif e.is_action_pressed("ui_up", true):
		to = at - line
	elif e.is_action_pressed("ui_page_down", true):
		to = at + page
	elif e.is_action_pressed("ui_page_up", true):
		to = at - page
	elif e.is_action_pressed("ui_end"):
		to = top
	elif e.is_action_pressed("ui_home"):
		to = 0.0
	to = clampf(to, 0.0, top)
	# at the end the press is not taken: the focus moves on (to the box and the buttons below, the D-pad included)
	if roundi(to) == scroll.scroll_vertical:
		return
	scroll.scroll_vertical = roundi(to)
	scroll.accept_event()


## The window's size changed: placed now, and again once the labels have their new widths.
func _on_resized() -> void:
	_place()
	_place.call_deferred()


## Escape and gamepad B: Continue anyway (they close the message).
func _input(e: InputEvent) -> void:
	if _done or not e.is_pressed():
		return
	if e.is_action_pressed("ui_cancel") or (e is InputEventJoypadButton and e.button_index == JOY_BUTTON_B):
		get_viewport().set_input_as_handled()
		_answer(true)


func _answer(go: bool) -> void:
	if _done:
		return
	_done = true
	if dont_show.button_pressed:
		cf.set_value(SECTION, KEY_OFF, true)
		Quality.save(cf)
	# (after the press's own handling: the start goes on from the next idle time, not inside the GUI's input)
	answered.emit.call_deferred(go)
	queue_free()
