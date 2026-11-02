## The P&ID viewer (docs/plant3d/REALISM.md §6.1.1, milestone DC1): the generated sheets full screen, the 3D view off
## behind them. Drag (or the left stick, or the arrows) pans; pinch, the wheel, the triggers and + and − zoom; a tap on
## a code opens its card beside the sheet, on an off-sheet connector the other sheet at that code. The card's Drawing
## button opens a code's home sheet with the code centred and outlined.
##
## Drawn with three levels of detail per sheet, each a canvas item recorded once, when first needed: far (one-pixel
## lines, the 5 mm titles only), middle (one-pixel lines, all the text) and near (the line widths in millimetres).
## The lettering is expanded into the same line lists. Panning and zooming only change the paper's transform: no
## sheet is drawn again while it is looked at.
extends Control

const W = preload("res://ui/widgets.gd")
const Drawings = preload("res://ui/drawings.gd")

const PAPER := Color(0.97, 0.97, 0.95)
const INK := Color(0.05, 0.06, 0.08)
const TEXT_INK := Color(0.07, 0.1, 0.3)
const CLOUD := Color(0.85, 0.1, 0.1)
const SELECT := Color(1.0, 0.45, 0.0)
const FAR_Z := 2.6          # px per mm below which the far level is drawn (2.5 mm text under 6.5 px: unreadable)
const NEAR_Z := 6.0         # and from which the near one
const MAX_Z := 30.0
const FAR_TEXT := 4.9       # the far level's smallest text (mm): the sheet's title (7 mm) and the legend's code example
const KEEP := 3             # sheets kept drawn (the last ones opened); others are freed (memory, REALISM.md §11)
const TAP_SLOP := 12.0
const PAN_SPEED := 900.0    # px a second, the stick all the way

var ui                              # ui/plant_ui.gd
var set_                            # ui/drawings.gd
var bar: HBoxContainer
var picker: OptionButton
var title: Label
var canvas: Control
var paper: Node2D
var overlay: Node2D
var current := ""
var zoom := 1.0
var offset := Vector2.ZERO
var selected := ""
var _sel_box := Rect2()
var _lods := {}                     # sheet id -> [Node2D or null] × 3
var _order: Array = []              # sheet ids, the most recently opened last
var _touches := {}
var _pinch0 := 0.0
var _dragging := false
var _moved := 0.0
var _trigger := {}
var _fitted_for := Vector2.ZERO
var _pending_code := ""             # a code to centre once the canvas has its size
## measurements (the Note 9's, REALISM.md §11; the walk's DRAWINGS line): ms to read and record a level
var build_ms := {}                  # "sheet:level" -> ms
var open_ms := {}                   # sheet id -> ms from asking to the first level ready


func setup(u, drawings) -> void:
	ui = u
	set_ = drawings
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.13, 0.15)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(v)
	bar = HBoxContainer.new()
	bar.name = "drawing_bar"
	v.add_child(bar)
	var prev := W.button("Previous", func(): _step(-1))
	prev.name = "prev"
	bar.add_child(prev)
	picker = OptionButton.new()
	picker.name = "sheets"
	picker.custom_minimum_size = Vector2(0, 52 * W.scale)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.clip_text = true
	for s in set_.sheets:
		picker.add_item("%s  %s" % [s["number"], s["title"]])
	picker.item_selected.connect(func(i): open_sheet(String(set_.sheets[i]["id"])))
	bar.add_child(picker)
	var nxt := W.button("Next", func(): _step(1))
	nxt.name = "next"
	bar.add_child(nxt)
	var fit_b := W.button("Fit", func(): fit())
	fit_b.name = "fit"
	bar.add_child(fit_b)
	var close := W.button("Close", func(): ui.close_drawings())
	close.name = "close"
	bar.add_child(close)
	canvas = Control.new()
	canvas.name = "sheet"
	canvas.clip_contents = true
	canvas.focus_mode = Control.FOCUS_ALL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.gui_input.connect(_canvas_input)
	canvas.resized.connect(_on_resized)
	canvas.draw.connect(_draw_canvas)
	v.add_child(canvas)
	paper = Node2D.new()
	paper.name = "paper"
	paper.draw.connect(func(): if current != "": paper.draw_rect(Rect2(Vector2.ZERO, _size_of(current)), PAPER))
	canvas.add_child(paper)
	overlay = Node2D.new()
	overlay.name = "overlay"
	overlay.z_index = 1
	overlay.draw.connect(_draw_overlay)
	paper.add_child(overlay)


func is_open() -> bool:
	return visible


## Where the sheet itself starts (below the viewer's bar): the side panels stand below it, the bar stays in reach.
func canvas_top() -> float:
	return position.y + bar.size.y + 8.0


## The part of the canvas a card does not cover (canvas coordinates): codes are centred in it.
func clear_rect() -> Rect2:
	var cs := _canvas_size()
	var right := cs.x
	if ui != null and ui.card != null and ui.card.visible:
		right = clampf(ui.card.position.x - canvas.global_position.x - 16.0, cs.x * 0.4, cs.x)
	return Rect2(Vector2.ZERO, Vector2(right, cs.y))


## Opens the viewer at a sheet (its id; "" the last one, else the first after the legend), with a code centred and
## outlined when given.
func open(id := "", code := "") -> void:
	visible = true
	if id == "":
		id = current if current != "" else (String(set_.sheets[1]["id"]) if set_.sheets.size() > 1 else String(set_.sheets[0]["id"]))
	open_sheet(id, code)
	take_focus()


func take_focus() -> void:
	if visible:
		canvas.grab_focus()


func _step(d: int) -> void:
	var i: int = set_.index_of(current)
	var n: int = set_.sheets.size()
	open_sheet(String(set_.sheets[(i + d + n) % n]["id"]))


func open_sheet(id: String, code := "") -> void:
	var i: int = set_.index_of(id)
	if i < 0:
		return
	var t0 := Time.get_ticks_usec()
	var first := not _lods.has(id)
	if current != "" and _lods.has(current):
		for n in _lods[current]:
			if n != null:
				n.visible = false
	current = id
	_order.erase(id)
	_order.append(id)
	_free_old()
	if picker.selected != i:
		picker.select(i)
	selected = ""
	_sel_box = Rect2()
	paper.queue_redraw()
	if code != "":
		focus_code(code)
	else:
		fit()
	if first:
		open_ms[id] = (Time.get_ticks_usec() - t0) / 1000.0


## Keeps the last KEEP sheets drawn: the others' canvas items are freed (they are made again when opened again).
func _free_old() -> void:
	while _order.size() > KEEP:
		var old: String = _order.pop_front()
		for n in _lods.get(old, []):
			if n != null:
				n.queue_free()
		_lods.erase(old)


func _size_of(id: String) -> Vector2:
	var s: Array = set_.sheet(id).get("size", [841.0, 594.0])
	return Vector2(s[0], s[1])


# ------------------------------------------------------------------ the view

func fit() -> void:
	var cs := _canvas_size()
	var s := _size_of(current)
	zoom = minf(cs.x / s.x, cs.y / s.y)
	offset = (cs - s * zoom) * 0.5
	_fitted_for = canvas.size
	_apply()


func _canvas_size() -> Vector2:
	return canvas.size if canvas.size.x > 10 else Vector2(1200, 700)


func min_zoom() -> float:
	var cs := _canvas_size()
	var s := _size_of(current)
	return minf(cs.x / s.x, cs.y / s.y) * 0.9


## Centres a code's home spot on its sheet at a zoom where its text reads, and outlines it.
func focus_code(code: String) -> void:
	var r := spot_rect(code)
	if r.size == Vector2.ZERO:
		fit()
		return
	selected = code
	_sel_box = r
	if canvas.size.x <= 10:
		_pending_code = code
	zoom = clampf(maxf(NEAR_Z * 0.8 * W.scale, zoom), min_zoom(), MAX_Z)
	offset = clear_rect().get_center() - r.get_center() * zoom
	_apply()


## A code's home spot on the current sheet (in sheet mm), or an empty rect.
func spot_rect(code: String) -> Rect2:
	for s in set_.sheet(current).get("spots", []):
		if s[0] == code and int(s[5]) == 1:
			return Rect2(Vector2(s[1], s[2]), Vector2(s[3] - s[1], s[4] - s[2]))
	return Rect2()


func zoom_by(f: float, about := Vector2(-1, -1)) -> void:
	if about.x < 0:
		about = _canvas_size() * 0.5
	var z := clampf(zoom * f, min_zoom(), MAX_Z)
	var p := (about - offset) / zoom
	zoom = z
	offset = about - p * zoom
	_apply()


func pan(d: Vector2) -> void:
	offset += d
	_apply()


func _clamp() -> void:
	var cs := _canvas_size()
	var s := _size_of(current) * zoom
	var m := 60.0
	# with a card open the sheet's right edge may go as far as the card's left: a code near it is not left under it
	var right := clear_rect().size.x
	if s.x + 2 * m <= cs.x:
		offset.x = clampf(offset.x, m, cs.x - s.x - m) if cs.x - s.x - m >= m else (cs.x - s.x) * 0.5
	else:
		offset.x = clampf(offset.x, right - s.x - m, m)
	if s.y + 2 * m <= cs.y:
		offset.y = clampf(offset.y, m, cs.y - s.y - m) if cs.y - s.y - m >= m else (cs.y - s.y) * 0.5
	else:
		offset.y = clampf(offset.y, cs.y - s.y - m, m)


## The paper's transform, and which level of detail shows (made the first time it is needed).
func _apply() -> void:
	if current == "":
		return
	_clamp()
	paper.position = offset
	paper.scale = Vector2(zoom, zoom)
	var want := level()
	var nodes: Array = _lods.get(current, [null, null, null])
	if nodes[want] == null:
		nodes[want] = _make_level(current, want)
		_lods[current] = nodes
	for k in 3:
		if nodes[k] != null:
			nodes[k].visible = k == want
	overlay.queue_redraw()
	canvas.queue_redraw()


func level() -> int:
	return 0 if zoom < FAR_Z else (1 if zoom < NEAR_Z else 2)


func _on_resized() -> void:
	if not visible or current == "":
		return
	if _pending_code != "" and canvas.size.x > 10:
		var c := _pending_code
		_pending_code = ""
		focus_code(c)
	elif _fitted_for.x <= 10 or absf(canvas.size.aspect() - _fitted_for.aspect()) > 0.3:
		fit()
	else:
		_apply()


# ------------------------------------------------------------------ recording a level

## A level of a sheet as a canvas item: the lines (one call per width), the text's strokes, the circles, the filled
## shapes in one triangle array, the revision clouds. Recorded once; drawn by the renderer from then on.
func _make_level(id: String, k: int) -> Node2D:
	var t0 := Time.get_ticks_usec()
	var d: Dictionary = set_.sheet(id)
	var near := k == 2
	var groups := {}                # width (or -1) -> PackedVector2Array of segment pairs
	var hair := -1.0
	for l in d.get("lines", []):
		var w: float = float(l[0]) if near else hair
		var dash: float = float(l[1])
		var pts: Array = l[2]
		var g: PackedVector2Array = groups.get(w, PackedVector2Array())
		for i in range(0, pts.size() - 2, 2):
			var a := Vector2(pts[i], pts[i + 1])
			var b := Vector2(pts[i + 2], pts[i + 3])
			if dash > 0.0:
				_dashed(g, a, b, dash)
			else:
				g.append(a)
				g.append(b)
		groups[w] = g
	for c in d.get("circles", []):
		var w: float = float(c[0]) if near else hair
		var g: PackedVector2Array = groups.get(w, PackedVector2Array())
		var ctr := Vector2(c[1], c[2])
		var r: float = c[3]
		var n := 24 if near else 12
		var prev := ctr + Vector2(r, 0)
		for i in range(1, n + 1):
			var p := ctr + Vector2(cos(TAU * i / n), sin(TAU * i / n)) * r
			g.append(prev)
			g.append(p)
			prev = p
		groups[w] = g
	var text_pts := PackedVector2Array()
	var min_h := 0.0 if k > 0 else FAR_TEXT
	for t in d.get("texts", []):
		if float(t[2]) >= min_h:
			_text(text_pts, t)
	var tri_pts := PackedVector2Array()
	var tri_idx := PackedInt32Array()
	for f in d.get("fills", []):
		var base := tri_pts.size()
		for i in range(0, f.size(), 2):
			tri_pts.append(Vector2(f[i], f[i + 1]))
		var n2: int = f.size() / 2
		for i in range(1, n2 - 1):
			tri_idx.append(base)
			tri_idx.append(base + i)
			tri_idx.append(base + i + 1)
	var clouds := PackedVector2Array()
	for c in d.get("clouds", []):
		_cloud(clouds, Rect2(Vector2(c[1], c[2]), Vector2(c[3] - c[1], c[4] - c[2])))
	var node := Node2D.new()
	node.name = "%s_%d" % [id, k]
	var widths := groups.keys()
	widths.sort()
	var tw := 0.25 if near else hair
	var colours := PackedColorArray()
	colours.resize(tri_pts.size())
	colours.fill(INK)
	node.draw.connect(func():
		for w in widths:
			if groups[w].size() >= 2:
				node.draw_multiline(groups[w], INK, w)
		if text_pts.size() >= 2:
			node.draw_multiline(text_pts, TEXT_INK, tw)
		if tri_idx.size() >= 3:
			RenderingServer.canvas_item_add_triangle_array(node.get_canvas_item(), tri_idx, tri_pts, colours)
		if clouds.size() >= 2:
			node.draw_multiline(clouds, CLOUD, 0.35 if near else hair))
	paper.add_child(node)
	paper.move_child(overlay, -1)
	build_ms["%s:%d" % [id, k]] = (Time.get_ticks_usec() - t0) / 1000.0
	return node


static func _dashed(g: PackedVector2Array, a: Vector2, b: Vector2, dash: float) -> void:
	var L := a.distance_to(b)
	if L < 1e-6:
		return
	var u := (b - a) / L
	var s := 0.0
	while s < L:
		g.append(a + u * s)
		g.append(a + u * minf(s + dash, L))
		s += dash * 2.0


## A text run's strokes in the lettering (tools/plant3d/pid_font.py): [x, y, height, angle, align, text], the anchor on
## the baseline; angle 90 reads upwards.
func _text(out: PackedVector2Array, t: Array) -> void:
	var x: float = t[0]
	var y: float = t[1]
	var h: float = t[2]
	var up: bool = int(t[3]) == 90
	var s: String = t[5]
	var k: float = h / float(set_.cap)
	var n := s.length()
	var w: float = (n * float(set_.advance) - 1.0) * k if n > 0 else 0.0
	var x0: float = [0.0, -w * 0.5, -w][int(t[4])]
	for i in n:
		var strokes = set_.glyphs.get(s[i])
		if strokes == null:
			continue
		var ox: float = x0 + i * float(set_.advance) * k
		for st in strokes:
			var p: PackedVector2Array = st
			for j in p.size() - 1:
				var a := Vector2(ox + p[j].x * k, -p[j].y * k)
				var b := Vector2(ox + p[j + 1].x * k, -p[j + 1].y * k)
				if up:
					a = Vector2(a.y, -a.x)
					b = Vector2(b.y, -b.x)
				out.append(Vector2(x, y) + a)
				out.append(Vector2(x, y) + b)


## A revision cloud round a rectangle: scallops of about 4 mm.
static func _cloud(out: PackedVector2Array, r: Rect2) -> void:
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
	for c in 4:
		var a: Vector2 = corners[c]
		var b: Vector2 = corners[c + 1]
		var n := maxi(1, int(round(a.distance_to(b) / 4.0)))
		var u := (b - a) / n
		var out_n := Vector2(u.y, -u.x).normalized()
		for i in n:
			var p0 := a + u * i
			var p1 := a + u * (i + 1)
			var prev := p0
			for j in range(1, 7):
				var q := p0.lerp(p1, j / 6.0) + out_n * sin(PI * j / 6.0) * u.length() * 0.35
				out.append(prev)
				out.append(q)
				prev = q


func _draw_overlay() -> void:
	if _sel_box.size != Vector2.ZERO:
		overlay.draw_rect(_sel_box.grow(1.5), SELECT, false, 3.0 / zoom)


## The gamepad's aim (A opens what is under it) when a gamepad is in use.
func _draw_canvas() -> void:
	if ui != null and ui.main != null and ui.main.hud != null and ui.main.hud.pad_on():
		var c := canvas.size * 0.5
		canvas.draw_line(c - Vector2(14, 0), c + Vector2(14, 0), SELECT, 2.0)
		canvas.draw_line(c - Vector2(0, 14), c + Vector2(0, 14), SELECT, 2.0)


# ------------------------------------------------------------------ input

var _pad_shown := false


func _process(delta: float) -> void:
	if not visible:
		return
	var pad: bool = ui != null and ui.main != null and ui.main.hud != null and ui.main.hud.pad_on()
	if pad != _pad_shown:
		_pad_shown = pad
		canvas.queue_redraw()           # the gamepad's cross comes and goes with the gamepad
	# the left stick of whichever gamepad is connected pans
	var v := Vector2.ZERO
	for dev in Input.get_connected_joypads():
		var s := Vector2(Input.get_joy_axis(dev, JOY_AXIS_LEFT_X), Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y))
		if s.length() > v.length():
			v = s
	if v.length() > 0.25 and canvas.has_focus():
		pan(-v * PAN_SPEED * delta)


func _canvas_input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		if ev.pressed:
			_touches[ev.index] = ev.position
			if _touches.size() >= 2:
				_moved = 999.0
		else:
			_touches.erase(ev.index)
		_pinch0 = _pinch_dist()
		return
	if ev is InputEventScreenDrag:
		_touches[ev.index] = ev.position
		if _touches.size() >= 2:
			var d := _pinch_dist()
			if _pinch0 > 0.0 and d > 0.0:
				zoom_by(d / _pinch0, _pinch_mid())
			_pinch0 = d
			_moved = 999.0
		canvas.accept_event()
		return
	if ev is InputEventMagnifyGesture:
		zoom_by(ev.factor, ev.position)
		canvas.accept_event()
		return
	if ev is InputEventPanGesture:
		pan(-ev.delta * 20.0)
		canvas.accept_event()
		return
	if ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP and ev.pressed:
			zoom_by(1.15, ev.position)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN and ev.pressed:
			zoom_by(1.0 / 1.15, ev.position)
		elif ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				_dragging = true
				_moved = 0.0
				canvas.grab_focus()
			elif _dragging:
				_dragging = false
				if _moved < TAP_SLOP * W.scale and _touches.size() < 2:
					tap(ev.position)
		canvas.accept_event()
		return
	if ev is InputEventMouseMotion and _dragging and _touches.size() < 2:
		pan(ev.relative)
		_moved += ev.relative.length()
		canvas.accept_event()
		return
	if ev is InputEventJoypadButton and ev.pressed:
		match ev.button_index:
			JOY_BUTTON_LEFT_SHOULDER: _step(-1); canvas.accept_event(); return
			JOY_BUTTON_RIGHT_SHOULDER: _step(1); canvas.accept_event(); return
			JOY_BUTTON_RIGHT_STICK: fit(); canvas.accept_event(); return
			JOY_BUTTON_A: tap(canvas.size * 0.5); canvas.accept_event(); return
	# the left stick pans (in _process) and the D-pad steps: neither may move the focus off the sheet (Godot's ui_*
	# actions include them)
	if ev is InputEventJoypadMotion and (ev.axis == JOY_AXIS_LEFT_X or ev.axis == JOY_AXIS_LEFT_Y):
		canvas.accept_event()
		return
	if ev is InputEventJoypadButton and ev.button_index in [JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN]:
		if ev.pressed:
			pan({JOY_BUTTON_DPAD_LEFT: Vector2(120, 0), JOY_BUTTON_DPAD_RIGHT: Vector2(-120, 0),
					JOY_BUTTON_DPAD_UP: Vector2(0, 120), JOY_BUTTON_DPAD_DOWN: Vector2(0, -120)}[ev.button_index])
		canvas.accept_event()
		return
	if ev is InputEventJoypadMotion and (ev.axis == JOY_AXIS_TRIGGER_LEFT or ev.axis == JOY_AXIS_TRIGGER_RIGHT):
		var down: bool = ev.axis_value > 0.5
		if down and not _trigger.get(ev.axis, false):
			zoom_by(1.4 if ev.axis == JOY_AXIS_TRIGGER_RIGHT else 1.0 / 1.4)
		_trigger[ev.axis] = down
		canvas.accept_event()
		return
	if ev is InputEventKey and ev.pressed:
		match ev.physical_keycode:
			KEY_PAGEUP: _step(-1); canvas.accept_event(); return
			KEY_PAGEDOWN: _step(1); canvas.accept_event(); return
			KEY_F: fit(); canvas.accept_event(); return
			KEY_KP_ADD: zoom_by(1.4); canvas.accept_event(); return
			KEY_KP_SUBTRACT: zoom_by(1.0 / 1.4); canvas.accept_event(); return
			KEY_LEFT: pan(Vector2(80, 0)); canvas.accept_event(); return
			KEY_RIGHT: pan(Vector2(-80, 0)); canvas.accept_event(); return
			KEY_UP: pan(Vector2(0, 80)); canvas.accept_event(); return
			KEY_DOWN: pan(Vector2(0, -80)); canvas.accept_event(); return
			KEY_ENTER, KEY_KP_ENTER: tap(canvas.size * 0.5); canvas.accept_event(); return
		if ev.unicode == 43 or ev.unicode == 61:
			zoom_by(1.4); canvas.accept_event(); return
		if ev.unicode == 45 or ev.unicode == 0x2212:
			zoom_by(1.0 / 1.4); canvas.accept_event(); return


func _pinch_dist() -> float:
	var ps := _touches.values()
	return (ps[0] as Vector2).distance_to(ps[1]) if ps.size() >= 2 else 0.0


func _pinch_mid() -> Vector2:
	var ps := _touches.values()
	return ((ps[0] as Vector2) + (ps[1] as Vector2)) * 0.5


## What is at a point of the canvas: ["link", sheet, code], ["code", code] or [].
func hit(at: Vector2) -> Array:
	var p := (at - offset) / zoom
	var d: Dictionary = set_.sheet(current)
	for l in d.get("links", []):
		if Rect2(Vector2(l[2], l[3]), Vector2(l[4] - l[2], l[5] - l[3])).has_point(p):
			return ["link", String(l[0]), String(l[1])]
	var best := ""
	var area := INF
	var slop := TAP_SLOP * W.scale / zoom     # a finger's width round small targets (screen pixels, in sheet mm)
	for s in d.get("spots", []):
		var r := Rect2(Vector2(s[1], s[2]), Vector2(s[3] - s[1], s[4] - s[2])).grow(slop)
		if r.has_point(p) and r.get_area() < area:
			area = r.get_area()
			best = s[0]
	return ["code", best] if best != "" else []


## A tap or click: a connector opens the other sheet at its code; a code opens its card (the sheet stays).
func tap(at: Vector2) -> void:
	var h := hit(at)
	if h.is_empty():
		return
	if h[0] == "link":
		ui.close_card()                  # the card was of a code on the sheet left behind
		open_sheet(h[1], h[2])
		return
	selected = h[1]
	var r := spot_rect(selected)
	_sel_box = r
	overlay.queue_redraw()
	ui.open_card(selected)


## Puts a sheet point in view (tests): the canvas point it is drawn at.
func to_canvas(p: Vector2) -> Vector2:
	return offset + p * zoom


func levels_made(id: String) -> Array:
	var out: Array = []
	for n in _lods.get(id, []):
		out.append(n != null)
	return out
