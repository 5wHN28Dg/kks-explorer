## The alarm list (docs/PLANT3D.md §7.5–§7.6, ISA-18.2 states): every alarm that is not normal, with its priority,
## ISA letters, KKS code, text, the model time it entered its state, and its state; unacknowledged ones flash.
## Acknowledge one or all; shelve one for a while (no horn, its own list, back when the time ends or when
## un-shelved); alarms suppressed by design are listed apart and never sound. Latched trips are listed with the
## first-out of each group marked, and can be reset from here (from the control room, as the content says).
extends PanelContainer

const W = preload("res://ui/widgets.gd")
const SHELF_TIMES := [[600, "10 min"], [1800, "30 min"], [3600, "1 h"]]

var ui
var body: VBoxContainer
var tab := "active"             # active, shelved, suppressed, trips
var since := {}                 # alarm id -> model step it entered its state
var _sig := ""
var _rows: Array = []           # [row control, alarm position] (flashing)
var _t := 0.0
var _blink := 0.0
var _tabs := {}


func setup(u) -> void:
	ui = u
	var parts := W.panel("Alarms", func(): ui.close_alarms())
	var p: PanelContainer = parts[0]
	var v := p.get_child(0)
	p.remove_child(v)
	p.free()
	add_child(v)
	mouse_filter = Control.MOUSE_FILTER_STOP
	body = parts[1]
	var bar := HFlowContainer.new()
	v.add_child(bar)
	v.move_child(bar, 1)
	for t in [["active", "Active"], ["shelved", "Shelved"], ["suppressed", "Suppressed"], ["trips", "Trips"]]:
		var b := W.button(t[1], _tab.bind(t[0]))
		b.toggle_mode = true
		bar.add_child(b)
		_tabs[t[0]] = b
	bar.add_child(W.button("Acknowledge all", _ack_all))
	visible = false


func _tab(t: String) -> void:
	tab = t
	_sig = ""
	refresh()


## Follows the events: the time each alarm entered its state.
func on_events(evs: Array, from: int) -> void:
	for i in range(from, evs.size()):
		var ev: Array = evs[i]
		if ev[1] == "alarm":
			since[ev[2]] = ev[0]


func open() -> void:
	visible = true
	tab = "active"
	_sig = ""
	refresh()
	if ui.wants_focus():
		(_tabs[tab] as Button).grab_focus()


func _ack_all() -> void:
	var e = ui.clock.engine
	for k in e._al.size():
		if _listed(e, k, "active") and (e.astate[k] == "active_unack" or e.astate[k] == "cleared_unack"):
			ui.ack(e._al[k][0])


static func suppressed(e, k: int) -> bool:
	var slot: int = e._al[k][3]
	return slot != -1 and e.cur[slot] >= 0.5


func _listed(e, k: int, t: String) -> bool:
	var shelved: bool = e.shelved[k] != -1
	var sup := suppressed(e, k)
	match t:
		"shelved": return shelved
		"suppressed": return sup and not shelved
		"active": return not shelved and not sup and e.astate[k] != "normal"
	return false


## What the list shows, in order: unacknowledged first, then by priority, then the newest.
func entries(t: String) -> Array:
	var e = ui.clock.engine
	var out := []
	for k in e._al.size():
		if _listed(e, k, t):
			out.append(k)
	out.sort_custom(func(a, b):
		var ua := 0 if String(e.astate[a]).ends_with("unack") else 1
		var ub := 0 if String(e.astate[b]).ends_with("unack") else 1
		if ua != ub:
			return ua < ub
		if e._al[a][5] != e._al[b][5]:
			return e._al[a][5] < e._al[b][5]
		return since.get(e._al[a][0], 0) > since.get(e._al[b][0], 0))
	return out


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_blink += delta
	var on := fmod(_blink, 1.0) < 0.6
	var e = ui.clock.engine
	for r in _rows:
		if e.astate[r[1]] == "active_unack" or e.astate[r[1]] == "cleared_unack":
			(r[0] as Control).modulate = Color.WHITE if on else Color(1, 1, 1, 0.45)
		else:
			(r[0] as Control).modulate = Color.WHITE
	if _t >= 0.25:
		_t = 0.0
		refresh()


func refresh() -> void:
	if not visible:
		return
	var e = ui.clock.engine
	for t in _tabs:
		(_tabs[t] as Button).set_pressed_no_signal(t == tab)
	var counts := {}
	for t in ["active", "shelved", "suppressed"]:
		counts[t] = entries(t).size()
	(_tabs["active"] as Button).text = "Active (%d)" % counts["active"]
	(_tabs["shelved"] as Button).text = "Shelved (%d)" % counts["shelved"]
	(_tabs["suppressed"] as Button).text = "Suppressed (%d)" % counts["suppressed"]
	var tripped := 0
	for k in e._tr.size():
		tripped += e.latched[k]
	(_tabs["trips"] as Button).text = "Trips (%d)" % tripped
	var sig := tab + "|" + str(e.step_no / 10 if tab == "shelved" else 0)
	if tab == "trips":
		sig += str(e.latched) + str(e.first_out)
	else:
		for k in entries(tab):
			sig += "%d:%s;" % [k, e.astate[k]]
	if sig == _sig:
		return
	_sig = sig
	var had_focus := get_viewport().gui_get_focus_owner() != null and is_ancestor_of(get_viewport().gui_get_focus_owner())
	W.clear(body)
	_rows.clear()
	if tab == "trips":
		_trips(e)
	else:
		var list := entries(tab)
		if list.is_empty():
			body.add_child(W.label({"active": "No alarms.", "shelved": "Nothing shelved.",
					"suppressed": "Nothing suppressed by design now."}[tab], 18, W.DIM))
		for k in list:
			_row(e, k)
	if had_focus:
		var b := _first(body)
		if b:
			b.grab_focus()


static func _first(n: Node) -> Button:
	for c in n.get_children():
		if c is Button:
			return c
		var f := _first(c)
		if f:
			return f
	return null


func _row(e, k: int) -> void:
	var a: Dictionary = ui.info.m.alarms[k]
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(2 * W.scale))
	body.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var pr := int(e._al[k][5])
	var badge := W.label(" %d " % pr, 20, Color.BLACK, false)
	var sb := StyleBoxFlat.new()
	sb.bg_color = W.PRIO_COLOURS.get(pr, Color.WHITE)
	sb.set_corner_radius_all(4)
	badge.add_theme_stylebox_override("normal", sb)
	head.add_child(badge)
	var code: String = a.get("kks", a.get("where", ""))
	var st: String = e.astate[k]
	var state_words := {"active_unack": "ACTIVE, not acknowledged", "active_ack": "active", "cleared_unack": "cleared, not acknowledged", "normal": "normal"}
	var extra := ""
	if tab == "shelved":
		extra = " · back in %s" % W.model_time(maxi(0, e.shelved[k] - e.step_no))
	var id := W.label("%s  %s · %s · %s%s" % [a.get("isa", "—"), code, W.model_time(since.get(a["id"], 0)),
			state_words.get(st, st), extra], 17, W.DIM)
	id.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(id)
	box.add_child(W.label(a["text"], 19))
	var row := HBoxContainer.new()
	box.add_child(row)
	if tab == "active":
		var ack := W.button("Ack", func(): ui.ack(a["id"]))
		ack.disabled = not st.ends_with("unack")
		row.add_child(ack)
		var sh := MenuButton.new()
		sh.text = "Shelve"
		sh.flat = false
		sh.focus_mode = Control.FOCUS_ALL
		sh.custom_minimum_size = Vector2(0, 52 * W.scale)
		for i in SHELF_TIMES.size():
			sh.get_popup().add_item(SHELF_TIMES[i][1], i)
		sh.get_popup().id_pressed.connect(func(i): ui.shelve(a["id"], SHELF_TIMES[i][0]))
		row.add_child(sh)
	elif tab == "shelved":
		row.add_child(W.button("Un-shelve", func(): ui.unshelve(a["id"])))
	if code != "":
		row.add_child(W.button("Go to", func(): ui.open_card(a.get("where", code))))
	_rows.append([box, k])


func _trips(e) -> void:
	var any := false
	var groups := {}
	for k in e._tr.size():
		if e.latched[k]:
			any = true
			var g = e._tr[k][3]
			var key: String = g if typeof(g) == TYPE_STRING else ""
			if not groups.has(key):
				groups[key] = []
			groups[key].append(k)
	if not any:
		body.add_child(W.label("No trip is latched.", 18, W.DIM))
		return
	for g in groups:
		body.add_child(W.label(("Group " + g) if g != "" else "Trips", 20))
		for k in groups[g]:
			var t: Dictionary = ui.info.m.trips[k]
			var row := HBoxContainer.new()
			body.add_child(row)
			var first: bool = g != "" and e.first_out.get(g, "") == t["id"]
			if first:
				var fo := W.label(" FIRST OUT ", 18, Color.BLACK, false)
				var sb := StyleBoxFlat.new()
				sb.bg_color = W.PRIO_COLOURS[1]
				fo.add_theme_stylebox_override("normal", sb)
				row.add_child(fo)
			var l := W.label("%s  %s\n%s" % [t.get("isa", "—"), t.get("kks", ""), t.get("text", t["id"])], 18)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.custom_minimum_size.x = 200 * W.scale
			row.add_child(l)
			for o in ui.info.m.ops:
				if o["do"] == "reset" and o.get("trip") == t["id"]:
					var b := W.button("Reset", func(): ui.do_op(o, null))
					b.disabled = not ui.info.offered(o, ui.near(o["kks"]), ui.in_control_room())
					row.add_child(b)
			if t.has("kks"):
				row.add_child(W.button("Go to", func(): ui.open_card(t["kks"])))
