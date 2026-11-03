## The Workshop's Run panel (docs/plant3d/WORKSHOP.md §3 "Run it", §6.1): the bench model's inputs (a slider per `set`
## op, a button per machine command), the bench clock's Pause and speed (0.1×–2×), the readouts (at most 12) with their
## units, the machines' states, the alarms (Acknowledge), the trainer's faults (each pressed to make it, again to
## repair it) and the last refusal's sentence. Generic: everything comes from the bench file.
extends PanelContainer

const W = preload("res://ui/widgets.gd")

var ws                          # workshop/workshop.gd
var box: VBoxContainer
var speed_label: Label
var pause_btn: Button
var readouts: Array = []        # [[Label, value name]]
var sliders: Array = []         # [[HSlider, op, value Label]]
var fault_btns := {}            # fault id -> Button
var state_label: Label
var alarm_label: Label
var note: Label
var _shown_for := ""
var legend_box: VBoxContainer
var _legend_for := ""           # the legend drawn now ("" none)


func setup(w) -> void:
	ws = w
	name = "run_panel"
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)


## Builds the panel for the bench now loaded (or says there is none).
func machine_shown() -> void:
	W.clear(box)
	readouts.clear()
	sliders.clear()
	fault_btns.clear()
	var c = ws.bench
	_shown_for = ws.part
	if c == null or not c.loaded():
		box.add_child(W.label("This machine has no bench model yet: it can be taken apart and looked into, not run.",
			18, W.DIM))
		state_label = null
		alarm_label = null
		note = null
		return
	box.add_child(W.label("Run", 22, Color.WHITE, false))
	var row := HFlowContainer.new()   # (the machine's commands and the bench's other ops: as many as the file has)
	box.add_child(row)
	var rb := W.button("Restart the bench", func(): ws.restart_bench(); machine_shown())
	rb.name = "run_restart"
	for o in c.m.ops_ui:
		if not o.has("machine") and o.get("do") != "set":   # an open, a close, a trip's reset
			var ob := W.button(String(o.get("title", "%s %s" % [String(o.do).capitalize(), _title(o.at)])),
				ws.run_op.bind(o.at, o.do, o.get("trip")))
			ob.name = "run_op_%s_%s" % [o.at, o.do]
			row.add_child(ob)
	for o in c.m.ops_ui:
		if o.has("machine"):
			var bt := W.button(String(o.get("title", o.do.capitalize())), ws.run_command.bind(o.at, o.do))
			bt.name = "run_%s_%s" % [o.machine, o.do]
			row.add_child(bt)
	var row2 := HBoxContainer.new()
	box.add_child(row2)
	row2.add_child(rb)
	pause_btn = W.button("Pause", func(): ws.bench.paused = not ws.bench.paused)
	pause_btn.name = "run_pause"
	row2.add_child(pause_btn)
	speed_label = W.label("1.0×", 18, W.DIM, false)
	row2.add_child(speed_label)
	var sp := HSlider.new()
	sp.name = "run_speed"
	sp.min_value = c.SPEED_MIN
	sp.max_value = c.SPEED_MAX
	sp.step = 0.1
	sp.value = c.speed
	sp.custom_minimum_size = Vector2(160 * W.scale, 40 * W.scale)
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.value_changed.connect(func(v): ws.bench.set_speed(v))
	row2.add_child(sp)
	for o in c.m.ops_ui:
		if o.get("do") == "set" and o.has("range"):
			var r := HBoxContainer.new()
			box.add_child(r)
			r.add_child(W.label(String(o.get("title", o.input)), 18, W.DIM, false))
			var s := HSlider.new()
			s.name = "set_" + String(o.input)
			s.min_value = float(o.range[0])
			s.max_value = float(o.range[1])
			s.step = (s.max_value - s.min_value) / 260.0
			s.value = c.now(o.input)
			s.custom_minimum_size = Vector2(160 * W.scale, 40 * W.scale)
			s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			s.value_changed.connect(func(v): ws.bench.op_set(o.at, v))
			s.drag_started.connect(func(): s.set_meta("dragging", true))
			s.drag_ended.connect(func(_c): s.set_meta("dragging", false))
			r.add_child(s)
			var vl := W.label("", 18, Color.WHITE, false)
			r.add_child(vl)
			sliders.append([s, o, vl])
	box.add_child(W.label("Readings", 18, W.DIM, false))
	for k in c.m.readouts:
		var l := W.label("", 18, Color.WHITE, false)
		l.name = "read_" + String(k)
		box.add_child(l)
		readouts.append([l, k])
	# the colour legend of the heat or pressure colours shown (§3 "See inside")
	legend_box = VBoxContainer.new()
	legend_box.name = "run_legend"
	box.add_child(legend_box)
	_legend_for = ""
	state_label = W.label("", 18, Color.WHITE)
	box.add_child(state_label)
	alarm_label = W.label("", 18, W.PRIO_COLOURS[2])
	alarm_label.name = "run_alarms"
	box.add_child(alarm_label)
	var ack := W.button("Acknowledge", func(): ws.ack_bench_alarms())
	ack.name = "run_ack"
	box.add_child(ack)
	if not c.m.faults.is_empty():
		box.add_child(W.label("Faults (the trainer's)", 18, W.DIM, false))
	for f in c.m.faults:
		var b := W.button(String(f.text), ws.toggle_fault.bind(String(f.id)))
		b.name = "fault_" + String(f.id)
		b.toggle_mode = true
		box.add_child(b)
		fault_btns[f.id] = b
	note = W.label("", 18, Color(1.0, 0.75, 0.35))
	note.name = "run_note"
	box.add_child(note)


## Each frame while shown: the readings, states, alarms and faults as the model has them.
func tick() -> void:
	var c = ws.bench
	if not visible or c == null or not c.loaded() or state_label == null:
		return
	speed_label.text = "%.1f×" % c.speed
	pause_btn.text = "Resume" if c.paused else "Pause"
	for s in sliders:
		s[2].text = c.shown(s[1].input)
		# the thumb follows the model (a refused set, a fault or a machine writing the input), except while dragged
		if not s[0].get_meta("dragging", false) and absf(s[0].value - c.now(s[1].input)) > s[0].step:
			s[0].set_value_no_signal(c.now(s[1].input))
	for r in readouts:
		var t: String = "%s  %s" % [_title(r[1]), c.shown(r[1])]
		if r[0].text != t:
			r[0].text = t
	var st := PackedStringArray()
	for mc in c.m.machines:
		st.append("%s: %s" % [_title(mc.id), c.machine_state(mc.id)])
	state_label.text = "  ".join(st)
	var al := PackedStringArray()
	for a in c.alarms():
		al.append(("● " if a[2] == "active_unack" or a[2] == "cleared_unack" else "○ ") + String(a[1]))
	alarm_label.text = "\n".join(al)
	for id in fault_btns:
		fault_btns[id].set_pressed_no_signal(c.faulted.has(id))
	note.text = ws.run_note
	var lg: String = ws.bench_view.legend_shown()
	if lg != _legend_for:
		_legend_for = lg
		_legend(c.m.legends.get(lg, {}), lg)


## The legend's bar (its colours left to right over its range) and its ends' numbers with the unit.
func _legend(lg: Dictionary, kind: String) -> void:
	W.clear(legend_box)
	var rows: Array = lg.table if lg.has("unit") else []   # (a legend: unit and table, ref/plant3d_bench.py)
	if rows.size() < 2:
		return
	legend_box.add_child(W.label("%s, %s" % [kind.capitalize(), lg.unit], 18, W.DIM, false))
	var g := Gradient.new()
	var lo := float(rows[0][0])
	var hi := float(rows[-1][0])
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for r in rows:
		offs.append((float(r[0]) - lo) / maxf(hi - lo, 1e-9))
		cols.append(Color.html(String(r[1])))
	g.offsets = offs
	g.colors = cols
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 256
	tex.height = 8
	var bar := TextureRect.new()
	bar.name = "legend_bar"
	bar.texture = tex
	bar.stretch_mode = TextureRect.STRETCH_SCALE
	bar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bar.custom_minimum_size = Vector2(0, 14 * W.scale)
	legend_box.add_child(bar)
	var ends := HBoxContainer.new()
	legend_box.add_child(ends)
	var a := W.label("%s" % _num(lo), 16, W.DIM, false)
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ends.add_child(a)
	ends.add_child(W.label("%s" % _num(hi), 16, W.DIM, false))


static func _num(x: float) -> String:
	return str(int(x)) if x == floorf(x) else "%.1f" % x


static func _title(name: String) -> String:
	return name.replace("_", " ").capitalize()
