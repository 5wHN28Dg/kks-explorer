## The photosensitivity notice (issue #443, the rulebook's GM8.3; the owner, 2026-11-22: "Yes, once at first start"):
## the plant has weather with lightning, whose flashes light the whole scene; they are capped (app/weather_view.gd:
## at most one every FLASH_GAP real seconds, whatever the speed), and "No lightning flashes" or Reduced motion turns
## them into a soft glow. Shown once, at the first start, before the plant loads, with that setting on the notice
## itself; kept as seen in user://settings.cfg whichever way it was closed. Read again from the settings' "About
## flashing light" (`again`: then its button is Close, and a change to the box applies at once) and in About.
## Never for a measurement started from the command line (app/min_gpu.gd SCRIPTED), never without a display unless a
## test asks for it.
##
## Switched off until the owner's check (the user's UI and UX policy 8.5: a tier-2 change merges behind a switch that
## is off): the project setting `walkdown/flash_notice` (project.godot), turned on for the check by an override.cfg
## beside the exe ([walkdown] flash_notice=true), and by the owner's OK in project.godot.
##
## Keys: Tab and the arrows move between the words (when they scroll), the box and the button; Enter or Space presses
## or ticks; Escape and gamepad B close it as Continue does; gamepad A presses or ticks what has the focus. A screen
## reader says the notice's title and words with the button that has the focus at first.
extends CanvasLayer

const W = preload("res://ui/widgets.gd")
const Quality = preload("res://app/quality.gd")
const MinGpu = preload("res://app/min_gpu.gd")
const Weather = preload("res://app/weather_view.gd")

const SECTION := "ui"
const KEY_SEEN := "flash_notice_seen"
const KEY_NO_FLASHES := "no_flashes"            # the settings' "No lightning flashes" (ui/plant_ui.gd)
const KEY_REDUCED := "reduced_motion"
const TITLE := "Flashing light"
const NO_FLASHES := "No lightning flashes: the lightning glows softly instead"   # (ui/plant_ui.gd NO_FLASHES)
const PAD := 8              # the words' margin inside their scroll (px)

## The notice's words, paragraph by paragraph; `in_about`: as About shows them (no box below them there).
static func paragraphs(in_about := false) -> Array:
	return [
		("Walkdown Plant has weather. In a thunderstorm, each lightning flash briefly lights up the whole scene. "
			+ "Flashes come at most once every %d seconds, also in fast-forward.") % int(Weather.FLASH_GAP),
		("If flashing light can affect you, turn on \"No lightning flashes\" %s: the lightning then only glows "
			+ "softly. Reduced motion turns it on too.") % ("in Settings" if in_about else "below"),
		"Both are in Settings, where you can also read this note again." if not in_about
			else "Settings' \"About flashing light\" shows this note again.",
	]


## Tests only: shown without a display too (1), or as the real start decides (-1).
static var display_override := -1

signal closed

var cf: ConfigFile
var again := false
var panel: PanelContainer
var no_flashes: CheckBox
var continue_button: Button
var words: VBoxContainer
var scroll: ScrollContainer
var on_no_flashes: Callable      # (on: bool): the box changed (the settings apply it at once)
var _done := false


## The switch (see above); `switch_override` for the tests (-1: the project setting).
static var switch_override := -1
static func switched_on() -> bool:
	return switch_override == 1 if switch_override >= 0 else bool(ProjectSettings.get_setting("walkdown/flash_notice", false))


## Whether the notice is due at this start: switched on, not seen before, not a measurement, and a display to show it
## on (or a test's).
static func wanted(settings: ConfigFile, opts: Dictionary) -> bool:
	if not switched_on() or bool(settings.get_value(SECTION, KEY_SEEN, false)):
		return false
	for k in MinGpu.SCRIPTED:      # (a scripted or measured start never waits for a press)
		if opts.has(k):
			return false
	return display_override == 1 or DisplayServer.get_name() != "headless"


func _init(settings: ConfigFile, shown_again := false) -> void:
	cf = settings
	again = shown_again
	layer = 30                  # over the settings (app/hud.gd SETTINGS_LAYER) when opened from them
	name = "flash_notice"


func _ready() -> void:
	var back := ColorRect.new()
	# at the start nothing is drawn behind it yet (the plant isn't loaded); from the settings the plant shows dimmed
	back.color = Color(0, 0, 0, 0.6) if again else Color(0.05, 0.06, 0.08)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	back.theme = W.make_theme()
	back.theme.set_stylebox("focus", "ScrollContainer", back.theme.get_stylebox("focus", "Button"))
	add_child(back)
	panel = PanelContainer.new()
	panel.name = "panel"
	panel.accessibility_name = TITLE
	back.add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	v.add_child(W.label(TITLE, 26))
	# the words scroll on a small window or a large UI size; the box and the button stay below them (the rulebook's N3)
	scroll = ScrollContainer.new()
	scroll.name = "words"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.draw_focus_border = true
	scroll.gui_input.connect(_scroll_keys)
	scroll.accessibility_name = "The notice's text"
	v.add_child(scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, PAD)
	scroll.add_child(pad)
	words = VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(words)
	var paras := paragraphs()
	for i in paras.size():
		words.add_child(W.label(paras[i], 20, Color.WHITE if i < 2 else W.DIM))
	no_flashes = CheckBox.new()
	no_flashes.name = "no_flashes"
	no_flashes.focus_mode = Control.FOCUS_ALL
	no_flashes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	no_flashes.custom_minimum_size.y = 52 * W.scale
	no_flashes.add_theme_font_size_override("font_size", int(20 * W.scale))
	var px := int(22 * W.scale)
	no_flashes.add_theme_icon_override("unchecked", MinGpu.box_icon(px, false))
	no_flashes.add_theme_icon_override("checked", MinGpu.box_icon(px, true))
	no_flashes.add_theme_icon_override("checked_disabled", MinGpu.box_icon(px, true))
	_show_box()
	no_flashes.toggled.connect(_on_box)
	v.add_child(no_flashes)
	var row := HBoxContainer.new()
	v.add_child(row)
	continue_button = W.button("Close" if again else "Continue", close, 200)
	continue_button.name = "continue"
	# a screen reader says the notice with the button that has the focus (AccessKit; the labels alone take no focus)
	continue_button.accessibility_description = TITLE + ". " + " ".join(paras)
	row.add_child(continue_button)
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	continue_button.grab_focus.call_deferred()
	_place()
	_place.call_deferred()      # (again once the containers have laid the labels out at the panel's width)
	get_viewport().size_changed.connect(_on_resized)


## The box as the settings have it: ticked when "No lightning flashes" is on; with Reduced motion on, ticked, not
## changeable, and saying why (as the settings' row: ui/plant_ui.gd _flashes_row).
func _show_box() -> void:
	var rm := bool(cf.get_value(SECTION, KEY_REDUCED, false))
	no_flashes.set_pressed_no_signal(rm or bool(cf.get_value(SECTION, KEY_NO_FLASHES, false)))
	no_flashes.disabled = rm
	no_flashes.text = NO_FLASHES + (" (on with Reduced motion)" if rm else "")
	no_flashes.accessibility_name = no_flashes.text


func _on_box(on: bool) -> void:
	cf.set_value(SECTION, KEY_NO_FLASHES, on)
	Quality.save(cf)
	if on_no_flashes.is_valid():
		on_no_flashes.call(on)


## Centred, at most 760 px wide, and never taller than the window: the words get the height they need, or what is
## left beside the title, the box and the button, and scroll (as app/min_gpu.gd's message).
func _place() -> void:
	if panel == null or not panel.is_inside_tree():
		return
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var w := minf(760.0 * W.scale, vs.x - 32.0)
	scroll.custom_minimum_size.y = 0.0
	panel.size = Vector2(w, 0)
	var rest := panel.get_combined_minimum_size().y
	scroll.custom_minimum_size.y = clampf(_words_height(w), 0.0, maxf(60.0 * W.scale, vs.y - 32.0 - rest))
	var scrolls := _words_height(w) > scroll.custom_minimum_size.y + 1.0
	if not scrolls and scroll.has_focus():
		continue_button.grab_focus()
	scroll.focus_mode = Control.FOCUS_ALL if scrolls else Control.FOCUS_NONE
	_focus_ring(scrolls)
	var h := panel.get_combined_minimum_size().y
	panel.size = Vector2(w, h)
	panel.position = Vector2((vs.x - w) * 0.5, maxf(16.0, (vs.y - h) * 0.5))


## Tab, the arrows and the D-pad go round the notice's own controls only (the words when they scroll, the box, the
## button): never to the settings under it.
func _focus_ring(scrolls: bool) -> void:
	var ring: Array = ([scroll] if scrolls else []) + [no_flashes, continue_button]
	for i in ring.size():
		var c: Control = ring[i]
		var nx: Control = ring[(i + 1) % ring.size()]
		var pv: Control = ring[(i - 1 + ring.size()) % ring.size()]
		c.focus_next = c.get_path_to(nx)
		c.focus_previous = c.get_path_to(pv)
		c.focus_neighbor_bottom = c.get_path_to(nx)
		c.focus_neighbor_top = c.get_path_to(pv)
		c.focus_neighbor_left = c.get_path_to(c)
		c.focus_neighbor_right = c.get_path_to(c)


func _words_height(w: float) -> float:
	var inner := w - 2.0 * 14.0 * W.scale - 2.0 - scroll.get_v_scroll_bar().get_combined_minimum_size().x - 2.0 * PAD
	var h := 0.0
	for l: Label in words.get_children():
		var fs := l.get_theme_font_size("font_size")
		var f := l.get_theme_font("font")
		var sz := f.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, inner, fs)
		var n := maxf(1.0, roundf(sz.y / f.get_height(fs)))
		h += sz.y + n * l.get_theme_constant("line_spacing")
	return h + (words.get_child_count() - 1) * 8.0 * W.scale + 8.0 + 2.0 * PAD


## The words scrolled from the keyboard and gamepad while they have the focus (as app/min_gpu.gd's).
func _scroll_keys(e: InputEvent) -> void:
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
	if roundi(to) == scroll.scroll_vertical:
		return
	scroll.scroll_vertical = roundi(to)
	scroll.accept_event()


func _on_resized() -> void:
	_place()
	_place.call_deferred()


## Escape and gamepad B close it; gamepad A presses or ticks the control with the focus (Godot's ui_accept has no
## gamepad button: app/hud.gd and ui/trainer_panel.gd do the same).
func _input(e: InputEvent) -> void:
	if _done or not e.is_pressed():
		return
	if e.is_action_pressed("ui_cancel") or (e is InputEventJoypadButton and e.button_index == JOY_BUTTON_B):
		get_viewport().set_input_as_handled()
		close()
	elif e is InputEventJoypadButton and e.button_index == JOY_BUTTON_A:
		var fo := get_viewport().gui_get_focus_owner()
		if fo is BaseButton and panel.is_ancestor_of(fo) and not fo.disabled:
			get_viewport().set_input_as_handled()
			if fo == no_flashes:
				no_flashes.button_pressed = not no_flashes.button_pressed
			else:
				(fo as BaseButton).pressed.emit()


## Closed (Continue, Close, Escape, gamepad B): kept as seen; the start goes on from the next idle time.
func close() -> void:
	if _done:
		return
	_done = true
	cf.set_value(SECTION, KEY_SEEN, true)
	Quality.save(cf)
	closed.emit.call_deferred()
	queue_free()
