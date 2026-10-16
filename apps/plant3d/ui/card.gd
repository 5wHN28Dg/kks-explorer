## The equipment card (docs/PLANT3D.md §6–§7): the KKS code with its meaning in the plant's own words, where the
## equipment is, its state and current values, its alarms, and its operations with their permissives. An operation
## is offered where the content says (`where`: at the equipment, within reach, or from the control room screens);
## pressing it sends it to the plant, and a refusal comes back in words: which permissive failed, or why the sequence
## or the trip doesn't take it.
extends PanelContainer

const W = preload("res://ui/widgets.gd")
const JsonStrict = preload("res://sim/json_strict.gd")

var ui                          # ui/plant_ui.gd
var code := ""
var body: VBoxContainer
var title: Label
var _state: Label
var _where: Label
var _values := {}               # value name -> Label
var _alarms: Label
var _ops: Array = []            # [op, button, permissives label, feedback label, entry or null, note label]
var _t := 0.0


func setup(u) -> void:
	ui = u
	var parts := W.panel("", func(): ui.close_card())
	var p: PanelContainer = parts[0]
	# the panel's content moves into this node (one PanelContainer)
	var v := p.get_child(0)
	p.remove_child(v)
	p.free()
	add_child(v)
	mouse_filter = Control.MOUSE_FILTER_STOP
	body = parts[1]
	title = parts[2]
	visible = false


func open(c: String, note := "") -> void:
	code = c
	var info = ui.info
	W.clear(body)
	_values.clear()
	_ops.clear()
	var nm: String = info.name_of(c)
	title.text = c + ("\n" + nm if nm != "" else "")
	if note != "":
		body.add_child(W.label(note, 18, Color(1.0, 0.8, 0.4)))
	for line in info.meaning(c):
		body.add_child(W.label(line, 17, W.DIM))
	_where = W.label("", 17, W.DIM)
	body.add_child(_where)
	var row := HBoxContainer.new()
	body.add_child(row)
	if ui.index.has(c):
		row.add_child(W.button("Show me", func(): ui.show_me(code)))
		row.add_child(W.button("Go there", func(): ui.fly_to(code)))
	_state = W.label("", 20, Color.WHITE)
	body.add_child(_state)
	var vals: Array = info.values_of.get(c, [])
	if not vals.is_empty():
		var g := GridContainer.new()
		g.columns = 2
		g.add_theme_constant_override("h_separation", int(16 * W.scale))
		body.add_child(g)
		for vn in vals:
			g.add_child(W.label(info.value_label(vn), 17, W.DIM, false))
			var l := W.label("", 19, Color.WHITE, false)
			g.add_child(l)
			_values[vn] = l
	_alarms = W.label("", 18, W.BAD_COLOUR)
	body.add_child(_alarms)
	var ops: Array = info.ops_of.get(c, [])
	if ops.is_empty():
		body.add_child(W.label("Nothing to operate here: it is watched, not worked.", 17, W.DIM))
	else:
		body.add_child(W.label("Operations", 22))
	for o in ops:
		var box := VBoxContainer.new()
		body.add_child(box)
		var line := HBoxContainer.new()
		box.add_child(line)
		var entry: LineEdit = null
		if o["do"] == "set":
			entry = LineEdit.new()
			entry.custom_minimum_size = Vector2(130 * W.scale, 52 * W.scale)
			entry.placeholder_text = _range_text(o)
			var want: Dictionary = ui.tracker.expected(c, "set") if ui.tracker != null else {}
			if want.has("value"):
				entry.text = _shown(o, want["value"])
			line.add_child(entry)
			line.add_child(W.label("%" if _percent(o) else String(info.units.get(o["input"], "")), 18, W.DIM, false))
		var b := W.button(info.op_label(o), _press.bind(o, entry), 140)
		line.add_child(b)
		var note_l := W.label("", 16, W.DIM)
		box.add_child(note_l)
		var perm := W.label("", 16, W.DIM)
		box.add_child(perm)
		var fb := W.label("", 17, Color.WHITE)
		box.add_child(fb)
		if entry != null:
			entry.text_submitted.connect(func(_t): _press(o, entry))
		_ops.append([o, b, perm, fb, entry, note_l])
	visible = true
	refresh()
	if ui.wants_focus():
		var first := _first_button(self)
		if first:
			first.grab_focus()


static func _first_button(n: Node) -> Button:
	for c in n.get_children():
		if c is Button and c.name != "close" and not c.disabled:
			return c
		var f := _first_button(c)
		if f:
			return f
	return null


static func _percent(o: Dictionary) -> bool:
	return o["range"][0] == 0 and o["range"][1] == 1


static func _range_text(o: Dictionary) -> String:
	if _percent(o):
		return "0–100"
	return "%s – %s" % [o["range"][0], o["range"][1]]


static func _shown(o: Dictionary, v) -> String:
	if _percent(o):
		return str(snappedf(float(v) * 100.0, 0.001)).trim_suffix(".0")
	return str(v)


## The trainee's number, read exactly (a JSON number: correctly rounded, an integer stays an integer); per cent for a
## 0–1 command. null when it isn't a number.
static func read_number(o: Dictionary, text: String):
	var t := text.strip_edges()             # a comma is refused: "1,000" must not pass as 1.0
	if _percent(o):
		t = percent_to_fraction(t)      # "33.3" is read as 0.333, not as 33.3 / 100 (one rounding apart)
	else:
		if t.begins_with("."): t = "0" + t
		elif t.begins_with("-."): t = "-0" + t.substr(1)
		if t.ends_with("."): t += "0"
	var r := JsonStrict.parse_text(t)
	if not r.ok or not (typeof(r.value) == TYPE_INT or typeof(r.value) == TYPE_FLOAT):
		return null
	return float(r.value) if _percent(o) else r.value


## A per cent as the decimal text of its fraction, by moving the point ("15" → "0.15"); "" when not a plain number.
static func percent_to_fraction(t: String) -> String:
	var re := RegEx.create_from_string("^(-?)([0-9]*)(?:\\.([0-9]*))?$")
	var mt := re.search(t)
	if mt == null or (mt.get_string(2) + mt.get_string(3)) == "":
		return ""
	var digits := mt.get_string(2).lpad(3, "0")
	var ip := digits.left(digits.length() - 2).lstrip("0")
	var fp := digits.right(2) + mt.get_string(3)
	return "%s%s.%s" % [mt.get_string(1), ip if ip != "" else "0", fp]


func _press(o: Dictionary, entry: LineEdit) -> void:
	var value = null
	if entry != null:
		value = read_number(o, entry.text)
		if value == null:
			ui.toast("Type a number (with a point for decimals): %s" % _range_text(o))
			return
	ui.do_op(o, value)
	refresh()


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	if _t >= 0.25:
		_t = 0.0
		refresh()


func refresh() -> void:
	if not visible or code == "":
		return
	var info = ui.info
	var e = ui.clock.engine
	var near: bool = ui.near(code)
	var ctl: bool = ui.in_control_room()
	var here := "In the control room" if ctl else ""
	if ui.index.has(code):
		var d: float = ui.distance_to(code)
		var area: String = info.area_titles.get(info.area_of.get(code, ""), "")
		_where.text = "%s · %s" % [area, "within reach" if near else "%.0f m away" % d]
		if ctl:
			_where.text += " · you are in the control room"
	else:
		_where.text = "Not drawn in the plant: worked from the control room screens." + ((" " + here) if here != "" else "")
	_state.text = " · ".join(info.state_words(code, e))
	for vn in _values:
		(_values[vn] as Label).text = info.fmt(vn, e.v(vn))
	var al := PackedStringArray()
	for k in info.alarms_of.get(code, []):
		var s: String = e.astate[k]
		if s != "normal":
			var a: Dictionary = info.m.alarms[k]
			al.append("%s %s: %s" % [a.get("isa", ""), a["text"], s.replace("_", " ")])
	_alarms.text = "\n".join(al)
	for row in _ops:
		var o: Dictionary = row[0]
		var ok: bool = info.offered(o, near, ctl)
		var b: Button = row[1]
		b.disabled = not ok
		var w: Array = o.get("where", ["local", "screen"])
		var note := ""
		if not ok:
			if w.has("local") and w.has("screen"):
				note = "At the equipment (walk up to it) or from the control room"
			elif w.has("screen"):
				note = "From the control room screens only"
			else:
				note = "At the equipment only: walk up to it"
		(row[5] as Label).text = note
		# a permissive's sentence says what is wrong when it is false (§7.2): those are listed, the others counted
		var plines := PackedStringArray()
		var met := 0
		var perms: Array = info.permissives(o, e)
		for pm in perms:
			if pm[1]:
				met += 1
			else:
				plines.append("✗ " + pm[0])
		if not perms.is_empty() and met == perms.size():
			plines.append("✓ every permissive met")
		elif met > 0:
			plines.append("✓ %d other%s met" % [met, "" if met == 1 else "s"])
		(row[2] as Label).text = "\n".join(plines)
		var res: Dictionary = ui.op_result(o)
		var fb: Label = row[3]
		fb.text = res.get("text", "")
		fb.add_theme_color_override("font_color", W.OK_COLOUR if res.get("state", "") == "done" else
				(W.BAD_COLOUR if res.get("state", "") == "refused" else Color.WHITE))
