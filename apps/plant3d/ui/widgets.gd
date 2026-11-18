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
## 100 % to 200 %. A phone starts at the size that gives its buttons 48 dp and its text 14 sp on its own screen
## (UI-UX-POLICY T1, S1: `phone_ui_size`, from the screen's density and the canvas), a desktop at 100 %; either can go
## above or below its start. It is also the text size setting of the policy's S2.
static var ui_size := 1.0
## The size this device starts at (`default_ui_size`, set when the app applies its size): the settings mark it.
static var ui_size_default := 1.0
const UI_SIZES := [1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 2.0]
const BUTTON_DP := 48.0         # the least a phone's target is (UI-UX-POLICY T1)
const TEXT_SP := 14.0           # the least a phone's body text is (S1)
const NOTE9_DENSITY := 420.0    # the Note 9's at its default 2220 x 1080 (`adb shell wm density`; the policy's §2)


## The UI's scale: 1 on desktops; phones get bigger text and targets (a 1600 × 900 canvas on a 6" screen).
static func pick_scale() -> float:
	scale = 1.35 if OS.has_feature("mobile") or DisplayServer.is_touchscreen_available() else 1.0
	return scale


## The UI size a first start takes: on a phone the one its screen needs (`phone_ui_size`), 100 % elsewhere (a desktop's
## touch screen keeps 100 %: its canvas is a laptop's, not a 6" one). `win` is the window's size in the screen's pixels.
static func default_ui_size(win: Vector2) -> float:
	return phone_ui_size(win, screen_density()) if OS.has_feature("mobile") else 1.0


## The least UI size at which a phone's buttons (52 canvas px at its UI scale `sc`) are 48 dp and its body text (20 at
## `sc`) 14 sp on a window `win` screen px across at `density` dpi (Android's: 160 is 1 dp a px), in steps of 10 %,
## 100 % to 200 % (a screen too small for 48 dp at 200 % gets 200 %). The canvas (`project.godot`, 1600 × 900,
## `expand`) is stretched by the window's shorter side: a canvas px is that many screen px.
static func phone_ui_size(win: Vector2, density: float, sc := -1.0) -> float:
	if sc <= 0.0:
		sc = scale
	var base := Vector2(ProjectSettings.get_setting("display/window/size/viewport_width", 1600),
		ProjectSettings.get_setting("display/window/size/viewport_height", 900))
	if win.x <= 0.0 or win.y <= 0.0 or density <= 0.0 or sc <= 0.0:
		return 1.0
	var dp := minf(win.x / base.x, win.y / base.y) * 160.0 / density   # dp a canvas px at 100 %
	var need := maxf(BUTTON_DP / (52.0 * sc * dp), TEXT_SP / (20.0 * sc * dp))
	return clampf(ceilf(need * 10.0 - 1e-4) / 10.0, UI_SIZES[0], UI_SIZES[-1])


## The screen's density in Android's dpi (160 is 1 dp a px): Android's own figure (its DisplayMetrics, through the
## Java bridge), else Godot's `screen_get_dpi()`, which on Android is the density's class (480 for the Note 9's 420:
## a larger UI size than needed, never a smaller one). How it was found: `density_source`.
static var density_source := ""
static func screen_density() -> float:
	if OS.get_name() == "Android" and Engine.has_singleton("AndroidRuntime"):
		var rt = Engine.get_singleton("AndroidRuntime")
		var act = rt.getActivity() if rt != null else null
		var dm = act.getResources().getDisplayMetrics() if act != null else null
		if dm != null:
			# px for 160 dp: the density in dpi (TypedValue.COMPLEX_UNIT_DIP is 1)
			var v = JavaClassWrapper.wrap("android.util.TypedValue").applyDimension(1, 160.0, dm)
			if (v is float or v is int) and float(v) >= 80.0:
				density_source = "android"
				return float(v)
	density_source = "godot"
	return float(DisplayServer.screen_get_dpi())


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
	# a list's rows (an OptionButton's popup) as tall as the buttons: 48 dp on a phone at its UI size (T1)
	t.set_font_size("font_size", "PopupMenu", int(20 * scale))
	t.set_constant("v_separation", "PopupMenu", int(maxf(0.0, 52.0 * scale - 1.3 * 20.0 * scale)))
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


## A target's height: `h` at UI scale 1 on a desktop (where a compact row may be under the buttons' 52), and the
## buttons' at least on a phone (52 at its scale: 48 dp at its UI size, UI-UX-POLICY T1).
static func tap_h(h: float) -> float:
	return h * scale if scale <= 1.0 else maxf(h, 52.0) * scale


static func button(text: String, f: Callable, min_w := 0) -> Button:
	var b := Button.new()
	b.text = text
	# (on a phone as wide as tall at least: 48 dp both ways at its UI size, T1; a desktop keeps a short word's width)
	b.custom_minimum_size = Vector2(maxf(min_w, 0.0 if scale <= 1.0 else 52.0) * scale, 52 * scale)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(f)
	return b


## "Copy CODE": on a narrow panel (a phone at a large UI size) "Copy" goes above the code, which stays whole on its
## line (UI-UX-POLICY S3), instead of the button making its row wider than the panel.
static func copy_button(code: String, f: Callable) -> Button:
	var b := button("Copy " + code, f)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var cw: float = ThemeDB.fallback_font.get_string_size(code, HORIZONTAL_ALIGNMENT_LEFT, -1, int(20 * scale)).x
	b.custom_minimum_size.x = maxf(b.custom_minimum_size.x, ceilf(cw) + 2.0 * 12.0 * scale + 2.0)
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
