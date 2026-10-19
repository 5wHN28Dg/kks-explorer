## The control room screens (docs/PLANT3D.md §7.11): one overview screen per system of the train and the train's
## overview, as a plant's control system shows them, in the high-performance style of ISA-101: a grey screen, grey
## equipment, colour only for what is abnormal (alarms by priority, trips). Made from the model by
## ui/screens_model.gd; drawn here at a few hertz, not every frame (the values change at the model's 0.1 s step).
##
## Tap or click a drive, valve, breaker or measurement: its card (ui/card.gd) opens beside the screen, with the ops the
## content offers on the screens and their permissives: everything goes through the card and the engine, as from the
## field. Drag to pan, pinch or the mouse wheel to zoom; keyboard and gamepad: the arrows or D-pad move from item to
## item, Enter or A opens it, Page Up/Down or the shoulder buttons change screen, + and − zoom, Esc or B closes.
extends Control

const W = preload("res://ui/widgets.gd")
const ScreensModel = preload("res://ui/screens_model.gd")
const Trends = preload("res://ui/trends.gd")

const REFRESH := 0.25           # seconds between redraws of the values (4 Hz)
const CELL_W := 236.0
const PAD := 10.0
const GAP := 64.0               # between the groups: room for the flow lines
const TREND := Vector2(300, 96)
# the high-performance palette: greys, colour only for the abnormal
const BG := Color(0.80, 0.81, 0.82)
const PANEL := Color(0.86, 0.87, 0.88)
const CELL := Color(0.90, 0.905, 0.91)
const EDGE := Color(0.55, 0.56, 0.58)
const INK := Color(0.10, 0.11, 0.12)
const INK_DIM := Color(0.32, 0.33, 0.35)
const EQUIP := Color(0.30, 0.31, 0.33)       # a running drive, an open valve: filled dark grey
const HOLLOW := Color(0.97, 0.97, 0.97)      # a stopped drive, a closed valve: hollow
const LINE := Color(0.40, 0.41, 0.43)
const TRIP := Color(0.85, 0.10, 0.10)
const SELECT := Color(0.05, 0.25, 0.65)
const PRIO := {1: Color(0.86, 0.10, 0.10), 2: Color(1.0, 0.55, 0.0), 3: Color(0.95, 0.85, 0.10)}

var ui                          # ui/plant_ui.gd
var sm                          # ui/screens_model.gd
var trends                      # ui/trends.gd
var current := -1               # -1: the overview, else the screen's index in sm.screens
var selected := ""              # the selected target: a code, "screen:<i>" (an overview tile) or ""
var canvas: Control
var banner: Control
var tabs: HFlowContainer
var _tab_btns: Array = []
var _layouts := {}              # screen index -> layout (below)
var _view := {}                 # screen index -> [zoom, offset]
var zoom := 1.0
var offset := Vector2.ZERO
var _t := 0.0
var _blink := true
var _last_pos := {}             # valve code -> position at the last redraw (moving when it changed)
var _banner_rows: Array = []    # [rect, alarm position]
var _press_at := Vector2.ZERO
var _dragging := false
var _moved := 0.0
var _touches := {}              # index -> position (two fingers: pinch)
var _pinch0 := 0.0
var redraws := 0                # pieces drawn (tests: each a few times a second, not every frame)
var draw_us := 0                # the longest piece's drawing time since the screen was shown, in microseconds
var _pieces: Array = []         # the screen's pieces, each drawn on its own: [Control, layout rect]
var _ci: CanvasItem             # the piece being drawn
var _rr := 0                    # the next piece to redraw (round robin: a few each frame, each at REFRESH)
var _rr_acc := 0.0
var _fit_cache := {}            # text cut to a width: the same names every redraw

## A layout: {size, title, groups: [{rect, title}], cells: [{rect, code or value name, kind: item | extra | tile}],
## lines: [[from rect, to rect, label]], trends: [[value, rect]], keys: [[value, rect]]}


func setup(u, screens_model, trend_buffer) -> void:
	ui = u
	sm = screens_model
	trends = trend_buffer
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var bg := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.13, 0.15)
	bg.add_theme_stylebox_override("panel", sb)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", int(4 * W.scale))
	add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	tabs = HFlowContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tabs)
	var names := [sm.overview.get("short", "Overview")]
	for sc in sm.screens:
		names.append(sc.short)
	for i in names.size():
		var b := W.button(names[i], show_screen.bind(i - 1))
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE        # the screens are worked on the canvas; the tabs by Page Up/Down
		b.custom_minimum_size.y = 44 * W.scale
		b.name = "tab_" + ("overview" if i == 0 else sm.screens[i - 1].id)
		tabs.add_child(b)
		_tab_btns.append(b)
	for z in [["−", func(): zoom_by(1.0 / 1.25)], ["+", func(): zoom_by(1.25)], ["Fit", func(): fit()],
			["Close", func(): ui.close_screens()]]:
		var b := W.button(z[0], z[1], 52)
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size.y = 44 * W.scale
		b.name = "btn_" + String(z[0]).to_lower()
		top.add_child(b)
	var brow := HBoxContainer.new()
	v.add_child(brow)
	banner = Control.new()
	banner.name = "banner"
	banner.custom_minimum_size = Vector2(0, 3 * 26 * W.scale + 8)
	banner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	banner.mouse_filter = Control.MOUSE_FILTER_STOP
	banner.draw.connect(_draw_banner)
	banner.gui_input.connect(_banner_input)
	brow.add_child(banner)
	var bb := VBoxContainer.new()
	brow.add_child(bb)
	for a in [["Acknowledge screen", func(): ack_screen()], ["Alarm list", func(): ui.toggle_alarms()]]:
		var b := W.button(a[0], a[1])
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size.y = 38 * W.scale
		bb.add_child(b)
	canvas = Control.new()
	canvas.name = "canvas"
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.focus_mode = Control.FOCUS_ALL
	canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.clip_contents = true
	canvas.draw.connect(_draw_canvas)
	canvas.gui_input.connect(_canvas_input)
	canvas.resized.connect(_on_resized)
	v.add_child(canvas)


func open(screen := -1) -> void:
	visible = true
	show_screen(screen)
	if ui.wants_focus():
		canvas.grab_focus()


func show_screen(i: int) -> void:
	if current != i and _layouts.has(current):
		_view[current] = [zoom, offset]
	current = clampi(i, -1, sm.screens.size() - 1)
	for k in _tab_btns.size():
		(_tab_btns[k] as Button).set_pressed_no_signal(k == current + 1)
	_layout_of(current)
	_build_pieces()
	draw_us = 0
	if _view.has(current):
		zoom = _view[current][0]
		offset = _view[current][1]
		_place_pieces()
	else:
		fit()
	var targets := _targets()
	if not targets.is_empty() and not targets.any(func(c): return c.id == selected):
		selected = targets[0].id
	refresh()


func refresh() -> void:
	if not visible:
		return
	_tabs_text()
	banner.queue_redraw()
	canvas.queue_redraw()
	for pc in _pieces:
		(pc[0] as Control).queue_redraw()


## The screen in pieces (a group, a trend, an overview tile), each a canvas item of its own: panning and zooming
## move them without drawing anything, and the values are redrawn a few pieces a frame, each one every REFRESH,
## so no frame pays for the whole screen (the Note 9's frame rule, decision 0041).
func _build_pieces() -> void:
	for pc in _pieces:
		(pc[0] as Control).queue_free()
	_pieces.clear()
	var L: Dictionary = _layout_of(current)
	for g in L.groups:
		_piece(g.rect, _draw_group.bind(g))
	for c in L.cells:
		if c.kind == "tile":
			_piece(c.rect, _draw_tile_piece.bind(c))
	for t in L.trends:
		_piece(t[1], _draw_trend.bind(t[1], t[0], 13))
	for t in L["keys"]:
		_piece(t[1], _draw_trend.bind(t[1], t[0], 15))


func _piece(rect: Rect2, f: Callable) -> void:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size = rect.size
	c.draw.connect(func():
		if ui == null or ui.clock == null:
			return
		var t0 := Time.get_ticks_usec()
		_ci = c
		c.draw_set_transform(-rect.position, 0.0, Vector2.ONE)
		f.call()
		redraws += 1
		draw_us = maxi(draw_us, Time.get_ticks_usec() - t0))
	canvas.add_child(c)
	_pieces.append([c, rect])


func _place_pieces() -> void:
	var view := Rect2(-offset / zoom, canvas.size / zoom)
	for pc in _pieces:
		var c: Control = pc[0]
		var r: Rect2 = pc[1]
		c.position = offset + r.position * zoom
		c.scale = Vector2(zoom, zoom)
		c.visible = view.intersects(r) or canvas.size.x <= 10
	canvas.queue_redraw()


func pieces_count() -> int:
	return _pieces.size()


func _process(delta: float) -> void:
	if not visible:
		return
	if ui.clock == null or not ui.in_control_room():
		ui.close_screens()
		return
	_t += delta
	if _t >= REFRESH:
		_t = 0.0
		_blink = not _blink if _any_unack() else true
		_tabs_text()
		banner.queue_redraw()
	# the pieces in turn: each one every REFRESH, spread over the frames
	if not _pieces.is_empty():
		_rr_acc += _pieces.size() * delta / REFRESH
		var n := mini(int(_rr_acc), _pieces.size())
		_rr_acc -= n
		for k in n:
			var c: Control = _pieces[_rr % _pieces.size()][0]
			if c.visible:
				c.queue_redraw()
			_rr += 1


func _any_unack() -> bool:
	var e = ui.clock.engine
	for k in e._al.size():
		var s: String = e.astate[k]
		if (s == "active_unack" or s == "cleared_unack") and e.shelved[k] == -1 and not ScreensModel.suppressed(e, k):
			return true
	return false


func _tabs_text() -> void:
	var e = ui.clock.engine
	for i in sm.screens.size():
		var a: Dictionary = sm.screen_alarms(i, e)
		var by: Array = a.by
		var n: int = by[0] + by[1] + by[2]
		var b: Button = _tab_btns[i + 1]
		b.text = sm.screens[i].short + ("  %d" % n if n > 0 else "")
		var top := 1 if by[0] > 0 else (2 if by[1] > 0 else (3 if by[2] > 0 else 0))
		var col: Color = PRIO.get(top, Color.WHITE)
		b.modulate = col.lerp(Color.WHITE, 0.25) if top > 0 and (a.unack == 0 or _blink) else Color.WHITE


# ------------------------------------------------------------------ the layout (once per screen; the values change, not the places)

func _font() -> Font:
	return get_theme_default_font()


func _layout_of(i: int) -> Dictionary:
	if not _layouts.has(i):
		_layouts[i] = _make_overview() if i < 0 else _make_screen(i)
	return _layouts[i]


func _cell_h(it: Dictionary) -> float:
	var h := PAD + 18.0 + 20.0                 # the code, the name
	if it.kind != "measure":
		h += 46.0                              # the symbol and its state
	elif not it.lamps.is_empty():
		h += 22.0                              # a measurement's lamp (a flame detector): on or off
	h += 22.0 * _cell_values(it).size()
	if not it.ops.is_empty():
		h += 20.0                              # the next operation and its permissives
	return h + PAD


## The values a cell lists (a valve's position is in its state line already).
static func _cell_values(it: Dictionary) -> Array:
	return it.values.filter(func(v): return v != it.pos)


func _make_screen(si: int) -> Dictionary:
	var sc: Dictionary = sm.screens[si]
	var groups := []
	var cols := {}
	var rows := {}
	for gr in sc.groups:
		var n: int = gr.items.size() + gr.extra.size()
		var per := clampi(int(ceil(sqrt(n * 1.6))), 1, 5)
		var heights := []
		for c in gr.items:
			heights.append(_cell_h(sm.items[c]))
		for _v in gr.extra:
			heights.append(PAD * 2 + 18.0 + 22.0)
		var row_h := []
		for k in heights.size():
			var r := k / per
			if row_h.size() <= r:
				row_h.append(0.0)
			row_h[r] = maxf(row_h[r], heights[k])
		var w := PAD + mini(n, per) * (CELL_W + PAD)
		var h := 40.0 + PAD
		for rh in row_h:
			h += rh + PAD
		groups.append({"gr": gr, "per": per, "row_h": row_h, "size": Vector2(w, h)})
		cols[gr.at[0]] = maxf(cols.get(gr.at[0], 0.0), w)
		rows[gr.at[1]] = maxf(rows.get(gr.at[1], 0.0), h)
	var x_of := {}
	var x := 24.0
	var ck := cols.keys()
	ck.sort()
	for c in ck:
		x_of[c] = x
		x += cols[c] + GAP
	var y_of := {}
	var y := 64.0
	var rk := rows.keys()
	rk.sort()
	for r in rk:
		y_of[r] = y
		y += rows[r] + GAP
	var out := {"title": sc.title, "groups": [], "cells": [], "lines": [], "trends": [], "keys": []}
	var rect_of := {}
	for g in groups:
		var gr: Dictionary = g.gr
		var at := Vector2(x_of[gr.at[0]], y_of[gr.at[1]])
		var rect := Rect2(at, g.size)
		rect_of[gr.id] = rect
		var gd := {"rect": rect, "title": gr.title, "cells": []}
		out.groups.append(gd)
		var k := 0
		var cy := at.y + 40.0 + PAD
		var entries: Array = gr.items.map(func(c): return [c, "item"]) + gr.extra.map(func(v): return [v, "extra"])
		for en in entries:
			var r := k / int(g.per)
			var cx: float = at.x + PAD + (k % int(g.per)) * (CELL_W + PAD)
			if k % int(g.per) == 0 and r > 0:
				cy += g.row_h[r - 1] + PAD
			var ch: float = _cell_h(sm.items[en[0]]) if en[1] == "item" else PAD * 2 + 18.0 + 22.0
			var cell := {"rect": Rect2(cx, cy, CELL_W, ch), "id": en[0], "kind": en[1]}
			out.cells.append(cell)
			gd.cells.append(cell)
			k += 1
	for l in sc.lines:
		var label: String = String(l.get("medium", "")).replace("_", " ")
		out.lines.append([rect_of[l["from"]], rect_of[l["to"]], label])
	var right := x - GAP + 24.0
	var bottom := y - GAP + 24.0
	var tx := 24.0
	for v in sc.trend:
		out.trends.append([v, Rect2(tx, bottom + 8.0, TREND.x, TREND.y)])
		tx += TREND.x + PAD * 2
	if not sc.trend.is_empty():
		bottom += TREND.y + 32.0
	out.size = Vector2(maxf(right, tx + 16.0), bottom)
	return out


func _make_overview() -> Dictionary:
	var out := {"title": sm.overview.get("title", "Overview"), "groups": [], "cells": [], "lines": [], "trends": [], "keys": []}
	var x := 24.0
	var y := 64.0
	var keys: Array = sm.overview.get("key", [])
	var per := 6
	for i in keys.size():
		var r := Rect2(24.0 + (i % per) * (TREND.x * 0.8 + PAD * 2), y + (i / per) * (128.0 + PAD * 2), TREND.x * 0.8, 128.0)
		out["keys"].append([keys[i], r])
	y += ceili(keys.size() / float(per)) * (128.0 + PAD * 2) + 24.0
	var tw := 372.0
	var th := 170.0
	var tper := 4
	for i in sm.screens.size():
		var r := Rect2(24.0 + (i % tper) * (tw + PAD * 2), y + (i / tper) * (th + PAD * 2), tw, th)
		out.cells.append({"rect": r, "id": "screen:%d" % i, "kind": "tile"})
	y += ceili(sm.screens.size() / float(tper)) * (th + PAD * 2)
	x = 24.0 + mini(maxi(keys.size(), 1), per) * (TREND.x * 0.8 + PAD * 2)
	out.size = Vector2(maxf(x, 24.0 + tper * (tw + PAD * 2)), y + 16.0)
	return out


# ------------------------------------------------------------------ the view: zoom and pan

## The zoom at which text is read comfortably where the screens are: larger on phones (W.scale).
func readable_zoom() -> float:
	return 1.6 if W.scale > 1.0 else 1.0


## The canvas got its size (the first layout after opening, a turned phone): a view fitted before then is fitted again.
func _on_resized() -> void:
	if _unsized and canvas.size.x > 10:
		fit()
		if selected != "":
			reveal(selected)
	else:
		_clamp_offset()


var _unsized := false


func fit() -> void:
	var L: Dictionary = _layout_of(current)
	_unsized = canvas.size.x <= 10
	var cs := canvas.size if not _unsized else Vector2(1200, 600)
	var z := minf(cs.x / L.size.x, cs.y / L.size.y)
	zoom = clampf(z, 0.75 * readable_zoom(), 1.3 * readable_zoom())
	offset = Vector2(maxf(0.0, (cs.x - L.size.x * zoom) * 0.5), 0.0)
	_clamp_offset()
	_place_pieces()


func zoom_by(f: float, about := Vector2(-1, -1)) -> void:
	if about.x < 0:
		about = canvas.size * 0.5
	var z := clampf(zoom * f, 0.35, 3.0)
	var p := (about - offset) / zoom
	zoom = z
	offset = about - p * zoom
	_clamp_offset()
	_place_pieces()


func _clamp_offset() -> void:
	var L: Dictionary = _layout_of(current)
	var cs := canvas.size
	var s: Vector2 = L.size * zoom
	var lo := Vector2(minf(0.0, cs.x - s.x - 40.0), minf(0.0, cs.y - s.y - 40.0))
	var hi := Vector2(maxf(40.0, cs.x - s.x), maxf(40.0, cs.y - s.y)) if s.x < cs.x or s.y < cs.y else Vector2(40, 40)
	offset = Vector2(clampf(offset.x, lo.x, maxf(lo.x, hi.x)), clampf(offset.y, lo.y, maxf(lo.y, hi.y)))


func to_screen(p: Vector2) -> Vector2:
	return offset + p * zoom


## Pans so that the target stands in view, clear of the card on the right when it is open.
func reveal(id: String) -> void:
	var r := target_rect(id)
	if r.size == Vector2.ZERO:
		return
	var cs := canvas.size
	var right := cs.x
	if ui.card.visible:
		right = maxf(cs.x * 0.4, ui.card.position.x - canvas.global_position.x - 16.0)
	var a := to_screen(r.position)
	var b := to_screen(r.end)
	if a.x < 8.0 or b.x > right - 8.0:
		offset.x += (right * 0.5) - (a.x + b.x) * 0.5
	if a.y < 8.0 or b.y > cs.y - 8.0:
		offset.y += cs.y * 0.5 - (a.y + b.y) * 0.5
	_clamp_offset()
	_place_pieces()


func target_rect(id: String) -> Rect2:
	for c in _layout_of(current).cells:
		if c.id == id:
			return c.rect
	return Rect2()


## Where the target is drawn on the canvas now (its centre, in the canvas's coordinates).
func target_centre(id: String) -> Vector2:
	var r := target_rect(id)
	return to_screen(r.get_center())


func _targets() -> Array:
	return _layout_of(current).cells.filter(func(c): return c.kind != "extra")


# ------------------------------------------------------------------ input

func _canvas_input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		if ev.pressed:
			_touches[ev.index] = ev.position
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
			_moved = 999.0                       # a pinch is never a tap
		canvas.accept_event()
		return
	if ev is InputEventMagnifyGesture:
		zoom_by(ev.factor, ev.position)
		canvas.accept_event()
		return
	if ev is InputEventPanGesture:
		offset -= ev.delta * 20.0
		_clamp_offset()
		_place_pieces()
		canvas.accept_event()
		return
	if ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP and ev.pressed:
			zoom_by(1.1, ev.position)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN and ev.pressed:
			zoom_by(1.0 / 1.1, ev.position)
		elif ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				_press_at = ev.position
				_dragging = true
				_moved = 0.0
			elif _dragging:
				_dragging = false
				if _moved < 14.0 and _touches.size() < 2:
					tap(ev.position)
		canvas.accept_event()
		return
	if ev is InputEventMouseMotion and _dragging and _touches.size() < 2:
		offset += ev.relative
		_moved += ev.relative.length()
		_clamp_offset()
		_place_pieces()
		canvas.accept_event()
		return
	if ev is InputEventJoypadButton and ev.pressed:
		if ev.button_index == JOY_BUTTON_LEFT_SHOULDER:
			show_screen(_prev_screen()); canvas.accept_event(); return
		if ev.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			show_screen(_next_screen()); canvas.accept_event(); return
	if ev is InputEventKey and ev.pressed:
		match ev.physical_keycode:
			KEY_PAGEUP: show_screen(_prev_screen()); canvas.accept_event(); return
			KEY_PAGEDOWN: show_screen(_next_screen()); canvas.accept_event(); return
			KEY_EQUAL, KEY_KP_ADD: zoom_by(1.25); canvas.accept_event(); return
			KEY_MINUS, KEY_KP_SUBTRACT: zoom_by(1.0 / 1.25); canvas.accept_event(); return
	for d in [["ui_left", Vector2.LEFT], ["ui_right", Vector2.RIGHT], ["ui_up", Vector2.UP], ["ui_down", Vector2.DOWN]]:
		if ev.is_action_pressed(d[0], true):
			move_selection(d[1])
			canvas.accept_event()
			return
	if ev.is_action_pressed("ui_accept"):
		activate(selected)
		canvas.accept_event()


func _prev_screen() -> int:
	return current - 1 if current > -1 else sm.screens.size() - 1


func _next_screen() -> int:
	return current + 1 if current < sm.screens.size() - 1 else -1


func _pinch_dist() -> float:
	var ps := _touches.values()
	return (ps[0] as Vector2).distance_to(ps[1]) if ps.size() >= 2 else 0.0


func _pinch_mid() -> Vector2:
	var ps := _touches.values()
	return ((ps[0] as Vector2) + (ps[1] as Vector2)) * 0.5


## A tap or click on the canvas at `at` (canvas coordinates): the target there is selected and opened.
func tap(at: Vector2) -> void:
	var p := (at - offset) / zoom
	for c in _targets():
		if (c.rect as Rect2).has_point(p):
			selected = c.id
			activate(c.id)
			return


## Opens what a target stands for: an overview tile its screen, an item its card (the screen's operations).
func activate(id: String) -> void:
	if id == "":
		return
	if id.begins_with("screen:"):
		show_screen(int(id.substr(7)))
		return
	ui.open_card(id)
	select(id)


func select(id: String) -> void:
	selected = id
	reveal(id)
	for pc in _pieces:
		(pc[0] as Control).queue_redraw()


## The nearest target in a direction from the selected one (the arrows, the D-pad).
func move_selection(dir: Vector2) -> void:
	var targets := _targets()
	if targets.is_empty():
		return
	var from := target_rect(selected)
	if from.size == Vector2.ZERO:
		select(targets[0].id)
		return
	var c0 := from.get_center()
	var best := ""
	var best_d := INF
	for c in targets:
		if c.id == selected:
			continue
		var d: Vector2 = (c.rect as Rect2).get_center() - c0
		var along := d.dot(dir)
		if along <= 1.0:
			continue
		var across := absf(d.dot(Vector2(-dir.y, dir.x)))
		var score := along + across * 2.0
		if score < best_d:
			best_d = score
			best = c.id
	if best != "":
		select(best)


## Acknowledges the alarms of the screen shown (the overview: every alarm), as a control system's page acknowledge.
func ack_screen() -> void:
	var e = ui.clock.engine
	var ks: Array = []
	if current < 0:
		for k in e._al.size():
			ks.append(k)
	else:
		ks = sm.screen_alarms(current, e).alarms
	for k in ks:
		var s: String = e.astate[k]
		if e.shelved[k] == -1 and (s == "active_unack" or s == "cleared_unack"):
			ui.ack(e._al[k][0])
	refresh()


func _banner_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		for r in _banner_rows:
			if (r[0] as Rect2).has_point(ev.position):
				go_to_alarm(r[1])
				banner.accept_event()
				return


## Shows the screen with an alarm's code and selects it.
func go_to_alarm(k: int) -> void:
	var a: Dictionary = ui.model.alarms[k]
	var c = a.get("kks", a.get("where"))
	if c == null or not sm.screen_of.has(c):
		return
	show_screen(sm.screen_of[c][0])
	select(c)


# ------------------------------------------------------------------ drawing

func _text(ci: CanvasItem, at: Vector2, s: String, size: int, col: Color, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var f := _font()
	if width > 0.0:
		var key := "%s|%d|%d" % [s, size, int(width)]
		if _fit_cache.has(key):
			s = _fit_cache[key]
		else:
			if f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
				while s.length() > 1 and f.get_string_size(s + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
					s = s.left(s.length() - 1)
				s += "…"
			if _fit_cache.size() > 4000:
				_fit_cache.clear()
			_fit_cache[key] = s
	ci.draw_string(f, at + Vector2(0, f.get_ascent(size)), s, align, width, size, col)


func _draw_canvas() -> void:
	canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), BG)
	if ui == null or ui.clock == null:
		return
	var L: Dictionary = _layout_of(current)
	canvas.draw_set_transform(offset, 0.0, Vector2(zoom, zoom))
	_ci = canvas
	_text(canvas, Vector2(24, 18), L.title, 24, INK)
	for l in L.lines:
		_draw_line(l[0], l[1], l[2])
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A group: its panel, title and items.
func _draw_group(g: Dictionary) -> void:
	var r: Rect2 = g.rect
	_ci.draw_rect(r, PANEL)
	_ci.draw_rect(r, EDGE, false, 1.5)
	_text(_ci, r.position + Vector2(PAD, 9), g.title, 18, INK, r.size.x - PAD * 2)
	var e = ui.clock.engine
	for c in g.cells:
		var cr: Rect2 = c.rect
		if c.kind == "item":
			_draw_item(cr, sm.items[c.id], e)
		else:
			_draw_extra(cr, c.id, e)
		if c.id == selected:
			_ci.draw_rect(cr.grow(3), SELECT, false, 3.0)


func _draw_tile_piece(c: Dictionary) -> void:
	_draw_tile(c.rect, int(String(c.id).substr(7)), ui.clock.engine)
	if c.id == selected:
		_ci.draw_rect((c.rect as Rect2).grow(3), SELECT, false, 3.0)


func _draw_line(a: Rect2, b: Rect2, label: String) -> void:
	var p0: Vector2
	var p1: Vector2
	var pts: PackedVector2Array
	if b.position.x >= a.end.x - 1.0:
		p0 = Vector2(a.end.x, a.get_center().y)
		p1 = Vector2(b.position.x, b.get_center().y)
		var mx := (p0.x + p1.x) * 0.5
		pts = PackedVector2Array([p0, Vector2(mx, p0.y), Vector2(mx, p1.y), p1])
	elif b.end.x <= a.position.x + 1.0:
		p0 = Vector2(a.position.x, a.get_center().y)
		p1 = Vector2(b.end.x, b.get_center().y)
		var mx := (p0.x + p1.x) * 0.5
		pts = PackedVector2Array([p0, Vector2(mx, p0.y), Vector2(mx, p1.y), p1])
	else:
		var x := (maxf(a.position.x, b.position.x) + minf(a.end.x, b.end.x)) * 0.5
		if b.position.y >= a.end.y:
			p0 = Vector2(x, a.end.y)
			p1 = Vector2(x, b.position.y)
		else:
			p0 = Vector2(x, a.position.y)
			p1 = Vector2(x, b.end.y)
		pts = PackedVector2Array([p0, p1])
	canvas.draw_polyline(pts, LINE, 3.0)
	var d := (pts[pts.size() - 1] - pts[pts.size() - 2]).normalized()
	var s := Vector2(-d.y, d.x)
	canvas.draw_colored_polygon(PackedVector2Array([p1, p1 - d * 14 + s * 7, p1 - d * 14 - s * 7]), LINE)
	if label != "":
		var mid := (pts[1] + pts[pts.size() - 2]) * 0.5 if pts.size() > 2 else (p0 + p1) * 0.5
		_text(canvas, mid + Vector2(6, -20), label, 13, INK_DIM)


func _alarm_badges(r: Rect2, al: Array) -> void:
	var x := r.end.x - PAD
	for a in al.slice(0, 3):
		var p: int = clampi(a[0], 1, 3)
		x -= 22.0
		var box := Rect2(x, r.position.y + 6, 20, 18)
		var col: Color = PRIO[p]
		if a[1] and not _blink:
			_ci.draw_rect(box, col, false, 2.0)
		else:
			_ci.draw_rect(box, col)
		_text(_ci, box.position + Vector2(6, 0), str(p), 14, INK if (not a[1] or _blink) else col)
		x -= 2.0


func _draw_item(r: Rect2, it: Dictionary, e) -> void:
	var al: Array = sm.alarms_now(it, e)
	var tk: int = sm.tripped(it, e)
	_ci.draw_rect(r, CELL)
	_ci.draw_rect(r, TRIP if tk >= 0 else EDGE, false, 2.0 if tk >= 0 else 1.0)
	var x := r.position.x + PAD
	var y := r.position.y + PAD * 0.6
	var w := r.size.x - PAD * 2
	_text(_ci, Vector2(x, y), it.code, 13, INK_DIM, w - 70.0)
	_alarm_badges(r, al)
	y += 18.0
	_text(_ci, Vector2(x, y), it.name, 15, INK, w)
	y += 20.0
	if it.kind != "measure":
		var state := _draw_symbol(Vector2(x + 20, y + 22), it, e)
		var sx := x + 48.0
		if tk >= 0:
			var tb := Rect2(sx, y + 4, 52, 20)
			_ci.draw_rect(tb, TRIP)
			_text(_ci, tb.position + Vector2(5, 1), "TRIP", 14, Color.WHITE)
			sx += 58.0
		_text(_ci, Vector2(sx, y + 4), state.words, 15, INK, r.end.x - PAD - sx)
		if state.second != "":
			_text(_ci, Vector2(x + 48.0, y + 24), state.second, 13, INK_DIM, w - 48.0)
		y += 46.0
	elif not it.lamps.is_empty():
		var words := PackedStringArray()
		for l in it.lamps:
			words.append(("%s: %s" % [String(l[0]).capitalize(), "on" if e.truth(l[1]) else "off"]) if l[0] != "running" else ("On" if e.truth(l[1]) else "Off"))
		_text(_ci, Vector2(x, y), " · ".join(words), 15, INK, w)
		if tk >= 0:
			_text(_ci, Vector2(r.end.x - PAD - 40, y), "TRIP", 14, TRIP)
		y += 22.0
	var vals: Array = _cell_values(it)
	for vn in vals:
		var label: String = ui.info.value_label(vn) if vals.size() > 1 or it.kind != "measure" else ""
		var txt: String = ui.info.fmt(vn, e.v(vn))
		var vw := _font().get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		if label != "":
			_text(_ci, Vector2(x, y + 2), label, 13, INK_DIM, w - vw - 10.0)
		if it.kind == "measure" and not al.is_empty() and vals.size() == 1:
			var col: Color = PRIO[clampi(al[0][0], 1, 3)]
			if not al[0][1] or _blink:
				_ci.draw_rect(Rect2(r.end.x - PAD - vw - 6, y - 1, vw + 12, 22), col)
		_text(_ci, Vector2(r.end.x - PAD - vw, y), txt, 17, INK)
		if tk >= 0 and it.kind == "measure" and it.lamps.is_empty():
			_text(_ci, Vector2(x, y), "TRIP", 14, TRIP)
		y += 22.0
	if not it.ops.is_empty():
		_text(_ci, Vector2(x, y + 1), _next_text(it, e), 13, INK_DIM, w)


## What the item's next operation needs, in a few words: "Start: ready", "Start: 2 of 4 missing".
func _next_text(it: Dictionary, e) -> String:
	var o: Dictionary = sm.next_op(it, e)
	if o.is_empty():
		return ""
	var name: String = ui.info.op_label(o)
	if o["do"] == "reset":
		name = "Reset trip"
	if not o.get("where", ["local", "screen"]).has("screen"):
		return "%s: at the equipment" % name
	var perms: Array = ui.info.permissives(o, e)
	var missing := perms.filter(func(p): return not p[1]).size()
	if missing == 0:
		return "%s: ready" % name
	return "%s: %d of %d missing" % [name, missing, perms.size()]


## What an item's symbol says now: {words, second (a controller's mode, a sequence's `say`), on (filled: running,
## open, closed breaker, sequence under way), pos (a valve's 0–1), moving}. `was`: a valve's position at the last
## look (it moves when the two differ).
func item_state(it: Dictionary, e, was = null) -> Dictionary:
	match it.kind:
		"valve":
			var pos: float = e.v(it.pos)
			var w: float = pos if was == null else float(was)
			var moving: bool = absf(pos - w) > 1e-6
			var words := "CLOSED" if pos < 0.02 else ("OPEN" if pos > 0.98 else "%.0f %%" % (pos * 100.0))
			if moving:
				words = ("OPENING " if pos > w else "CLOSING ") + "%.0f %%" % (pos * 100.0)
			var second := ""
			if it.machine >= 0:
				second = "Control: " + ui.info.state_name(it.machine, e).replace("_", " ")
			return {"words": words, "second": second, "on": pos > 0.98, "pos": pos, "moving": moving}
		"breaker":
			var on: bool = e.truth(it.closed)
			return {"words": "CLOSED" if on else "OPEN", "second": "", "on": on}
		"machine":
			var st: String = ui.info.state_name(it.machine, e)
			var idle: bool = st == ui.model.machines[it.machine].get("init", "")
			return {"words": st.replace("_", " ").to_upper(), "second": ui.info.state_say(it.machine, e), "on": not idle}
		"drive":
			var run: bool = e.truth(it.run)
			return {"words": "RUNNING" if run else "STOPPED", "second": "", "on": run}
	return {"words": "", "second": "", "on": false}


## Draws the item's symbol centred at c; returns its state (item_state).
func _draw_symbol(c: Vector2, it: Dictionary, e) -> Dictionary:
	var letters: String = it.code.substr(7, 2) if it.code.length() >= 9 else ""
	var st := item_state(it, e, _last_pos.get(it.code))
	match it.kind:
		"valve":
			_last_pos[it.code] = st.pos
			var fill := HOLLOW if st.pos < 0.02 else (EQUIP if st.pos > 0.98 else EQUIP.lerp(HOLLOW, 0.55))
			var l := PackedVector2Array([c + Vector2(-16, -11), c + Vector2(0, 0), c + Vector2(-16, 11)])
			var rr := PackedVector2Array([c + Vector2(16, -11), c + Vector2(0, 0), c + Vector2(16, 11)])
			_ci.draw_colored_polygon(l, fill)
			_ci.draw_colored_polygon(rr, fill)
			for poly in [l, rr]:
				var closed := PackedVector2Array(poly)
				closed.append(poly[0])
				_ci.draw_polyline(closed, EQUIP, 2.0)
			_ci.draw_line(c, c + Vector2(0, -16), EQUIP, 2.0)
			_ci.draw_rect(Rect2(c + Vector2(-7, -22), Vector2(14, 7)), EQUIP if not st.moving or _blink else HOLLOW)
			return st
		"breaker":
			var b := Rect2(c - Vector2(14, 14), Vector2(28, 28))
			_ci.draw_rect(b, EQUIP if st.on else HOLLOW)
			_ci.draw_rect(b, EQUIP, false, 2.0)
			if not st.on:
				_ci.draw_line(c + Vector2(-8, 8), c + Vector2(8, -8), EQUIP, 2.0)
			return st
		"machine":
			var poly := PackedVector2Array([c + Vector2(-18, -8), c + Vector2(18, -16), c + Vector2(18, 16), c + Vector2(-18, 8)])
			_ci.draw_colored_polygon(poly, EQUIP if st.on else HOLLOW)
			var closed := PackedVector2Array(poly)
			closed.append(poly[0])
			_ci.draw_polyline(closed, EQUIP, 2.0)
			return st
	# a drive: a pump a circle with its outlet, a fan or compressor a circle with blades, anything else a motor box
	var fill := EQUIP if st.on else HOLLOW
	if letters == "AP":
		_ci.draw_circle(c, 15, fill)
		_ci.draw_circle(c, 15, EQUIP, false, 2.0)
		_ci.draw_rect(Rect2(c + Vector2(0, -15), Vector2(18, 7)), EQUIP)
	elif letters == "AN":
		_ci.draw_circle(c, 15, fill)
		_ci.draw_circle(c, 15, EQUIP, false, 2.0)
		var bl := HOLLOW if st.on else EQUIP
		_ci.draw_line(c + Vector2(-10, -10), c + Vector2(10, 10), bl, 2.0)
		_ci.draw_line(c + Vector2(-10, 10), c + Vector2(10, -10), bl, 2.0)
	else:
		var b := Rect2(c - Vector2(16, 12), Vector2(32, 24))
		_ci.draw_rect(b, fill)
		_ci.draw_rect(b, EQUIP, false, 2.0)
		_text(_ci, b.position + Vector2(9, 2), "M", 15, HOLLOW if st.on else EQUIP)
	return st


func _draw_extra(r: Rect2, vn: String, e) -> void:
	_ci.draw_rect(r, CELL)
	_ci.draw_rect(r, EDGE, false, 1.0)
	var x := r.position.x + PAD
	_text(_ci, Vector2(x, r.position.y + PAD), ui.info.value_label(vn), 14, INK_DIM, r.size.x - PAD * 2)
	var txt: String = ui.info.fmt(vn, e.v(vn))
	var vw := _font().get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	_text(_ci, Vector2(r.end.x - PAD - vw, r.position.y + PAD + 20), txt, 17, INK)


func _draw_trend(r: Rect2, vn: String, size: int) -> void:
	_ci.draw_rect(r, CELL)
	_ci.draw_rect(r, EDGE, false, 1.0)
	var e = ui.clock.engine
	var txt: String = ui.info.fmt(vn, e.v(vn))
	_text(_ci, r.position + Vector2(8, 4), ui.info.value_label(vn), size, INK_DIM, r.size.x - 100.0)
	var vw := _font().get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size + 3).x
	_text(_ci, Vector2(r.end.x - 8 - vw, r.position.y + 3), txt, size + 3, INK)
	var s: PackedFloat32Array = trends.series(vn)
	var plot := Rect2(r.position + Vector2(8, 26), r.size - Vector2(16, 34))
	_ci.draw_line(Vector2(plot.position.x, plot.end.y), plot.end, EDGE, 1.0)
	if s.size() < 2:
		return
	var lo := s[0]
	var hi := s[0]
	for v in s:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	if hi - lo < 1e-6:
		hi = lo + 1.0
	var pts := PackedVector2Array()
	var n := float(Trends.SIZE - 1)
	var x0 := plot.end.x - plot.size.x * (s.size() - 1) / n
	for k in s.size():
		pts.append(Vector2(x0 + plot.size.x * k / n, plot.end.y - plot.size.y * (s[k] - lo) / (hi - lo)))
	_ci.draw_polyline(pts, INK, 2.0)
	_text(_ci, Vector2(plot.position.x, plot.end.y - 2), "%s min" % (Trends.SIZE * Trends.EVERY / 600), 11, INK_DIM)


func _draw_key(r: Rect2, vn: String) -> void:
	_draw_trend(r, vn, 15)


func _draw_tile(r: Rect2, si: int, e) -> void:
	var sc: Dictionary = sm.screens[si]
	var a: Dictionary = sm.screen_alarms(si, e)
	_ci.draw_rect(r, PANEL)
	_ci.draw_rect(r, EDGE, false, 1.5)
	var x := r.position.x + PAD
	var y := r.position.y + PAD
	_text(_ci, Vector2(x, y), sc.short, 20, INK, r.size.x - PAD * 2)
	y += 26.0
	_text(_ci, Vector2(x, y), sc.title, 13, INK_DIM, r.size.x - PAD * 2)
	y += 24.0
	var running := 0
	var stopped := 0
	var tripped := 0
	var seqs := PackedStringArray()
	for gr in sc.groups:
		for c in gr.items:
			var it: Dictionary = sm.items[c]
			if sm.tripped(it, e) >= 0 and it.kind != "measure":
				tripped += 1
			if it.kind == "drive":
				if e.truth(it.run):
					running += 1
				else:
					stopped += 1
			elif it.kind == "machine":
				seqs.append("%s: %s" % [it.name, ui.info.state_name(it.machine, e).replace("_", " ")])
	_text(_ci, Vector2(x, y), "%d running · %d stopped%s" % [running, stopped, (" · %d tripped" % tripped) if tripped > 0 else ""], 15, INK, r.size.x - PAD * 2)
	y += 22.0
	if tripped > 0:
		_ci.draw_rect(Rect2(r.end.x - PAD - 52, r.position.y + PAD, 52, 20), TRIP)
		_text(_ci, Vector2(r.end.x - PAD - 47, r.position.y + PAD + 1), "TRIP", 14, Color.WHITE)
	for s in seqs.slice(0, 2):
		_text(_ci, Vector2(x, y), s, 14, INK, r.size.x - PAD * 2)
		y += 20.0
	var bx := x
	var by: Array = a.by
	for p in 3:
		var box := Rect2(bx, r.end.y - PAD - 22, 54, 22)
		if by[p] > 0:
			_ci.draw_rect(box, PRIO[p + 1])
		_ci.draw_rect(box, EDGE, false, 1.0)
		_text(_ci, box.position + Vector2(6, 2), "%d: %d" % [p + 1, by[p]], 14, INK)
		bx += 60.0


func _draw_banner() -> void:
	banner.draw_rect(Rect2(Vector2.ZERO, banner.size), Color(0.17, 0.18, 0.2))
	_banner_rows.clear()
	if ui == null or ui.clock == null:
		return
	var e = ui.clock.engine
	var list: Array = ui.alarms.entries("active")
	var rh := 26.0 * W.scale
	var fs := int(16 * W.scale)
	if list.is_empty():
		_text(banner, Vector2(10, 6), "No alarms", fs, Color(0.75, 0.75, 0.75))
		return
	for i in mini(3, list.size()):
		var k: int = list[i]
		var a: Dictionary = ui.model.alarms[k]
		var y := 4.0 + i * rh
		var p: int = clampi(int(e._al[k][5]), 1, 3)
		var unack: bool = String(e.astate[k]).ends_with("unack")
		var box := Rect2(8, y + 2, 30 * W.scale, rh - 6)
		if unack and not _blink:
			banner.draw_rect(box, PRIO[p], false, 2.0)
		else:
			banner.draw_rect(box, PRIO[p])
		_text(banner, box.position + Vector2(9 * W.scale, 0), str(p), fs, Color.BLACK if (not unack or _blink) else PRIO[p])
		var since: int = ui.alarms.since.get(a["id"], 0)
		var line := "%s  %s %s  %s  · %s" % [W.model_time(since), a.get("kks", a.get("where", "")), a.get("isa", ""),
				a.get("text", a["id"]), String(e.astate[k]).replace("_", " ").replace("unack", "unacknowledged").replace("ack", "acknowledged")]
		var more := 160.0 * W.scale if list.size() > 3 and i == 2 else 0.0
		_text(banner, Vector2(box.end.x + 10, y + 1), line, fs, Color.WHITE, banner.size.x - box.end.x - 20 - more)
		_banner_rows.append([Rect2(0, y, banner.size.x, rh), k])
	if list.size() > 3:
		_text(banner, Vector2(banner.size.x - 150 * W.scale, 4.0 + 2 * rh), "+%d more" % (list.size() - 3), fs, Color(0.8, 0.8, 0.8))
