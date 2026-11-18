## Shared pieces of the interaction layer's panels: one theme sized for the device (larger on phones, where the
## same logical pixel is smaller), labels, buttons and panels that keyboard and gamepad can reach.
extends RefCounted

const PRIO_COLOURS := {1: Color(0.95, 0.2, 0.15), 2: Color(1.0, 0.65, 0.0), 3: Color(0.95, 0.9, 0.2)}
const OK_COLOUR := Color(0.45, 0.9, 0.45)
const BAD_COLOUR := Color(1.0, 0.45, 0.4)
const DIM := Color(0.75, 0.75, 0.75)

static var scale := 1.0
## The settings' "UI size" (issue #382): everything drawn on the canvas, panels, bars, the HUD and the Workshop's, is
## this much larger (the window's content scale: the canvas the layout sees is that much smaller), on top of `scale`.
## 100 % to 150 %; a phone starts at 150 %, which gives its buttons 48 dp and its text 14 sp and more (UI-UX-POLICY T1,
## S1; at 100 % they were 32 dp and 12 sp), a desktop at 100 %. It is also the text size setting of the policy's S2.
static var ui_size := 1.0
const UI_SIZES := [1.0, 1.1, 1.2, 1.3, 1.4, 1.5]
const UI_SIZE_PHONE := 1.5


## The UI's scale: 1 on desktops; phones get bigger text and targets (a 1600 × 900 canvas on a 6" screen).
static func pick_scale() -> float:
	scale = 1.35 if OS.has_feature("mobile") or DisplayServer.is_touchscreen_available() else 1.0
	return scale


## The UI size a first start takes: 150 % on a phone, 100 % elsewhere (a desktop's touch screen keeps 100 %: its
## canvas is a laptop's, not a 6" one).
static func default_ui_size() -> float:
	return UI_SIZE_PHONE if OS.has_feature("mobile") else 1.0


## A UI size as saved or given (a number, or text such as "1.5"), held to the nearest of UI_SIZES; anything that is no
## number is `fallback`.
static func clamp_ui_size(v, fallback: float) -> float:
	var f := fallback
	if v is float or v is int:
		f = float(v)
	elif v is String and (v as String).is_valid_float():
		f = (v as String).to_float()
	var best: float = UI_SIZES[0]
	for s in UI_SIZES:
		if absf(s - f) < absf(best - f):
			best = s
	return best


## Applies a UI size to the window: its content is drawn that much larger, at once (every panel lays itself out again
## on the viewport's size_changed). Returns the size applied.
static func apply_ui_size(win: Window, f: float) -> float:
	ui_size = clamp_ui_size(f, 1.0)
	if win != null:
		win.content_scale_factor = ui_size
	return ui_size


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = int(20 * scale)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.11, 0.92)
	sb.set_corner_radius_all(int(10 * scale))
	sb.set_content_margin_all(14 * scale)
	sb.border_color = Color(0.3, 0.33, 0.38)
	sb.set_border_width_all(1)
	t.set_stylebox("panel", "PanelContainer", sb)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = Color(1.0, 0.75, 0.2)
	focus.set_border_width_all(3)
	focus.set_corner_radius_all(int(6 * scale))
	for st in [["normal", Color(0.2, 0.23, 0.28)], ["hover", Color(0.27, 0.31, 0.37)], ["pressed", Color(0.36, 0.41, 0.5)],
			["disabled", Color(0.13, 0.14, 0.16)], ["hover_pressed", Color(0.36, 0.41, 0.5)]]:
		var b := StyleBoxFlat.new()
		b.bg_color = st[1]
		b.set_corner_radius_all(int(6 * scale))
		b.content_margin_left = 12 * scale
		b.content_margin_right = 12 * scale
		b.content_margin_top = 6 * scale
		b.content_margin_bottom = 6 * scale
		t.set_stylebox(st[0], "Button", b)
		t.set_stylebox(st[0], "MenuButton", b)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.5, 0.5))
	t.set_stylebox("focus", "Button", focus)
	t.set_stylebox("focus", "LineEdit", focus)
	t.set_stylebox("focus", "CheckBox", focus)
	t.set_font_size("normal_font_size", "RichTextLabel", int(20 * scale))
	t.set_font_size("bold_font_size", "RichTextLabel", int(20 * scale))
	t.set_font_size("font_size", "Button", int(20 * scale))
	t.set_constant("separation", "VBoxContainer", int(8 * scale))
	t.set_constant("separation", "HBoxContainer", int(8 * scale))
	return t


static func label(text: String, size := 20, colour := Color.WHITE, wrap := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", int(size * scale))
	l.add_theme_color_override("font_color", colour)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func button(text: String, f: Callable, min_w := 0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w * scale, 52 * scale)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(f)
	return b


static func rich() -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.selection_enabled = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return r


static func clear(c: Node) -> void:
	for ch in c.get_children():
		c.remove_child(ch)
		ch.queue_free()


## A panel with a title row (title, close button) and a scrolling body; returns [panel, body, title label].
static func panel(title: String, on_close: Callable) -> Array:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	p.add_child(v)
	var row := HBoxContainer.new()
	v.add_child(row)
	var t := label(title, 24, Color.WHITE, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(t)
	var x := button("Close", on_close)
	x.name = "close"
	row.add_child(x)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(body)
	return [p, body, t]


## A panel's row of tabs or filters (`bar`, made under its title row in `v`) moved into the panel's scrolling body when
## it would take more than a third of the panel's `room` (a short canvas, a large UI size: wrapped onto rows it left
## the list no room), and back under the title once there is room. The body (made by `panel`) is put in a box of its
## own in the scroll (`tabs_box`), the bar above it there. The title row with Close never moves.
static func tabs_box(body: Control) -> VBoxContainer:
	var sc := body.get_parent() as ScrollContainer
	var outer := VBoxContainer.new()
	outer.name = "tabs_box"
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.remove_child(body)
	sc.add_child(outer)
	outer.add_child(body)
	return outer


static func place_bar(bar: Control, v: Control, outer: Control, room: float) -> void:
	var inside := bar.get_combined_minimum_size().y > room / 3.0
	var want: Control = outer if inside else v
	if bar.get_parent() == want:
		return
	bar.get_parent().remove_child(bar)
	want.add_child(bar)
	want.move_child(bar, 0 if inside else 1)


## Sizes a panel (made by `panel`) to its content, at most `max_h` high: on a phone the view stays visible below it.
static func fit(p: Control, max_h: float) -> void:
	var v: Control = p.get_child(0)
	var h := 0.0
	var sep := float(v.get_theme_constant("separation"))
	for c in v.get_children():
		if not c.visible:
			continue
		if c is ScrollContainer:
			h += (c.get_child(0) as Control).get_combined_minimum_size().y
		else:
			h += c.get_combined_minimum_size().y
		h += sep
	h += 2.0 * 14.0 * scale + 4.0
	p.size.y = minf(max_h, h)


static func model_time(step_no: int) -> String:
	var s := int(step_no / 10)
	return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
