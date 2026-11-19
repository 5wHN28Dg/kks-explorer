## The minimum GPU (decision 0076, the user's choice of 2026-11-19, #432): on Windows and Linux Walkdown Plant needs a
## graphics driver with Vulkan or Direct3D 12. When Godot found neither and fell back to its Compatibility renderer
## (OpenGL 3.3, or ANGLE on Direct3D 11), a message says so once, before the plant loads: what the computer lacks, that
## the plant will be slow (an Intel HD Graphics 4400 walked it at about 12 frames a second, #432), and Continue anyway
## or Quit, with "Don't show this again" kept in user://settings.cfg. Never on a phone (Android has its own path,
## decision 0041), never for a measurement started from the command line (walk=, shot=), never without a display
## unless a test asks for it.
##
## Keys: Tab and the arrows move between the box and the buttons, Enter or Space presses; Escape and gamepad B mean
## Continue anyway (they close the message, as they close any layer: UI-UX-POLICY R2; quitting is always a press).
extends CanvasLayer

const W = preload("res://ui/widgets.gd")
const Quality = preload("res://app/quality.gd")

const SECTION := "graphics"
const KEY_OFF := "min_gpu_notice_off"
const MEASURED_FPS := 12    # #432: the frame walk on an Intel HD Graphics 4400, 80–86 ms a frame median

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


static func renderer() -> String:
	return renderer_override if renderer_override != "" else RenderingServer.get_current_rendering_method()


static func on_phone() -> bool:
	return phone_override == 1 if phone_override >= 0 else Quality.is_phone()


## Whether the message is due at this start: a desktop on the Compatibility renderer, not turned off in the settings,
## not a measurement, and a display to show it on (or a test's renderer).
static func wanted(settings: ConfigFile, opts: Dictionary) -> bool:
	if on_phone() or renderer() != "gl_compatibility":
		return false
	if bool(settings.get_value(SECTION, KEY_OFF, false)):
		return false
	if opts.has("walk") or opts.has("shot"):
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
	add_child(back)
	panel = PanelContainer.new()
	panel.name = "panel"
	panel.accessibility_name = "Graphics below Walkdown Plant's minimum"
	back.add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	v.add_child(W.label("This computer's graphics are below what Walkdown Plant needs", 26))
	# the words scroll on a small window or a large UI size; the buttons stay below them, always on screen (R1)
	scroll = ScrollContainer.new()
	scroll.name = "words"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	words = VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(words)
	words.add_child(W.label(("Its graphics chip or driver lacks a feature Walkdown Plant needs, so the plant is drawn "
			+ "a slower way. It will run slowly and jerkily: on a similar laptop it showed about %d pictures a second, "
			+ "where smooth movement needs 30 or more.") % MEASURED_FPS, 20))
	words.add_child(W.label(("Walkdown Plant needs graphics whose driver supports Vulkan or Direct3D 12: for example "
			+ "Intel HD Graphics 510 or newer (6th generation Core processors, from 2015), AMD Radeon HD 7700 or newer, "
			+ "or NVIDIA GeForce GTX 600 or newer. If this computer's graphics are that new, updating the graphics "
			+ "driver may fix this."), 20, W.DIM))
	dont_show = CheckBox.new()
	dont_show.name = "dont_show"
	dont_show.text = "Don't show this again"
	dont_show.focus_mode = Control.FOCUS_ALL
	dont_show.custom_minimum_size.y = 52 * W.scale
	dont_show.add_theme_font_size_override("font_size", int(20 * W.scale))
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
	get_viewport().size_changed.connect(_place)


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
	var h := panel.get_combined_minimum_size().y
	panel.size = Vector2(w, h)
	panel.position = Vector2((vs.x - w) * 0.5, maxf(16.0, (vs.y - h) * 0.5))


## The words' full height at the panel's width `w` (a ScrollContainer asks for no height of its own).
func _words_height(w: float) -> float:
	var inner := w - 2.0 * 14.0 * W.scale - 2.0           # the panel's margins and border (ui/widgets.gd make_theme)
	var h := 0.0
	for l: Label in words.get_children():
		var fs := l.get_theme_font_size("font_size")
		h += l.get_theme_font("font").get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, inner, fs).y
	return h + (words.get_child_count() - 1) * 8.0 * W.scale + 4.0


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
	answered.emit(go)
	queue_free()
