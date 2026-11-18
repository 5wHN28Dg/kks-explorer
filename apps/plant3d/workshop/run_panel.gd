## The Workshop's Run panel (docs/plant3d/WORKSHOP.md §3 "Run it", §6.1): the bench model's inputs (a slider per `set`
## op, a button per machine command), the bench clock's Pause and speed (0.1×–2×), the readouts (at most 12) with their
## units, the machines' states, the alarms (Acknowledge), the trainer's faults (each pressed to make it, again to
## repair it) and the last refusal's sentence. Generic: everything comes from the bench file. A mirror of the plant's
## equipment (WORKSHOP.md §6.5) offers none of the bench's ops and faults: it says whose mirror it is, what comes from
## the plant and what is the bench's own.
extends PanelContainer

const TouchScroll = preload("res://ui/touch_scroll.gd")
const W = preload("res://ui/widgets.gd")
const Mirror = preload("res://workshop/mirror.gd")
const FONT := 20                # the text's size at scale 1 (the theme's, as the Workshop's other panels: #389)

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
	scroll.follow_focus = true      # (the D-pad's focus brings a fault's button into view)
	add_child(scroll)
	TouchScroll.attach(scroll, func(): return ws._reader_on())      # (a finger's drag that begins on a button scrolls the bench: its buttons fill it)
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
			FONT, W.DIM))
		state_label = null
		alarm_label = null
		note = null
		return
	var ro: bool = ws.mirror_code != ""     # a mirror: read only (§6.5)
	box.add_child(W.label("Run", 24, Color.WHITE))
	if ro:
		var ml := W.label("Mirror of %s, read only" % ws.mirror_code, FONT, Color(0.55, 0.85, 1.0))
		ml.name = "run_mirror"
		box.add_child(ml)
		var wo: Dictionary = Mirror.words_of(ws.mirror_info)
		var got := PackedStringArray()
		for k in wo.mirrored:
			got.append(_title(k).to_lower())
		var t := "From the plant%s: %s. The rest is the bench's own model." % [
			" as it runs" if ws.mirror_live else " as you left it", ", ".join(got)]
		for x in wo.missing:
			t += "\nNot mirrored: %s (%s)." % [_title(x[0]).to_lower(), x[1]]
		var fl := W.label(t, FONT, W.DIM)
		fl.name = "run_mirror_from"
		box.add_child(fl)
		var lb := W.button("Leave the mirror: the bench is yours", func(): ws.leave_mirror())
		lb.name = "run_leave_mirror"
		lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # (alone on its row: its words wrap in a narrow panel)
		box.add_child(lb)
	var row := HFlowContainer.new()   # (the machine's commands and the bench's other ops: as many as the file has)
	box.add_child(row)
	var rb := W.button("Restart the bench", func(): ws.restart_bench(); machine_shown())
	rb.name = "run_restart"
	for o in ([] if ro else c.m.ops_ui):
		if not o.has("machine") and o.get("do") != "set":   # an open, a close, a trip's reset
			var ob := W.button(String(o.get("title", "%s %s" % [String(o.do).capitalize(), _title(o.at)])),
				ws.run_op.bind(o.at, o.do, o.get("trip")))
			ob.name = "run_op_%s_%s" % [o.at, o.do] + ("_" + String(o.trip) if o.has("trip") else "")
			row.add_child(_wrapping(ob))
	for o in ([] if ro else c.m.ops_ui):
		if o.has("machine"):
			var bt := W.button(String(o.get("title", o.do.capitalize())), ws.run_command.bind(o.at, o.do))
			bt.name = "run_%s_%s" % [o.machine, o.do]
			row.add_child(_wrapping(bt))
	var row2 := HFlowContainer.new()   # (it wraps in a narrow panel or a large UI: #389)
	box.add_child(row2)
	if ro:
		rb.free()
	else:
		row2.add_child(rb)
	pause_btn = W.button("Pause", func(): ws.bench.paused = not ws.bench.paused)
	pause_btn.name = "run_pause"
	row2.add_child(pause_btn)
	speed_label = W.label("1.0×", FONT, W.DIM, false)
	row2.add_child(speed_label)
	var sp := HSlider.new()
	sp.name = "run_speed"
	sp.min_value = c.SPEED_MIN
	sp.max_value = c.SPEED_MAX
	sp.step = 0.1
	sp.value = c.speed
	sp.custom_minimum_size = Vector2(160 * W.scale, 52 * W.scale)
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.value_changed.connect(func(v): ws.bench.set_speed(v))
	row2.add_child(sp)
	for o in ([] if ro else c.m.ops_ui):
		if o.get("do") == "set" and o.has("range"):
			var r := HFlowContainer.new()
			box.add_child(r)
			r.add_child(_wrapping_label(W.label(String(o.get("title", o.input)), FONT, W.DIM, false)))
			var s := HSlider.new()
			s.name = "set_" + String(o.input)
			s.min_value = float(o.range[0])
			s.max_value = float(o.range[1])
			s.step = (s.max_value - s.min_value) / 260.0
			s.value = c.now(o.input)
			s.custom_minimum_size = Vector2(160 * W.scale, 52 * W.scale)
			s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			s.value_changed.connect(func(v): ws.bench.op_set(o.at, v))
			s.drag_started.connect(func(): s.set_meta("dragging", true))
			s.drag_ended.connect(func(_c): s.set_meta("dragging", false))
			r.add_child(s)
			var vl := W.label("", FONT, Color.WHITE, false)
			r.add_child(vl)
			sliders.append([s, o, vl])
	box.add_child(W.label("Readings", FONT, W.DIM))
	for k in c.m.readouts:   # (its name and its value with the unit: the value goes under the name where it is narrow)
		var rr := HFlowContainer.new()
		box.add_child(rr)
		rr.add_child(_wrapping_label(W.label(_title(k), FONT, Color.WHITE, false)))
		var l := W.label("", FONT, Color.WHITE, false)
		l.name = "read_" + String(k)
		rr.add_child(l)
		readouts.append([l, k])
	# the colour legend of the heat or pressure colours shown (§3 "See inside")
	legend_box = VBoxContainer.new()
	legend_box.name = "run_legend"
	box.add_child(legend_box)
	_legend_for = ""
	state_label = W.label("", FONT, Color.WHITE)
	box.add_child(state_label)
	alarm_label = W.label("", FONT, W.PRIO_COLOURS[2])
	alarm_label.name = "run_alarms"
	box.add_child(alarm_label)
	var ack := W.button("Acknowledge", func(): ws.ack_bench_alarms())
	ack.name = "run_ack"
	ack.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(ack)
	if not c.m.faults.is_empty() and not ro:
		box.add_child(W.label("Faults (the trainer's)", FONT, W.DIM))
	for f in ([] if ro else c.m.faults):
		var b := W.button(String(f.text), ws.toggle_fault.bind(String(f.id)))
		b.name = "fault_" + String(f.id)
		b.toggle_mode = true
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # (a fault's words wrap in a narrow panel)
		box.add_child(b)
		fault_btns[f.id] = b
	note = W.label("", FONT, Color(1.0, 0.75, 0.35))
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
		var t: String = c.shown(r[1])
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
	legend_box.add_child(W.label("%s, %s" % [kind.capitalize(), lg.unit], FONT, W.DIM))
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
	var a := W.label("%s" % _num(lo), FONT, W.DIM, false)
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ends.add_child(a)
	ends.add_child(W.label("%s" % _num(hi), FONT, W.DIM, false))


## A button of a row whose words are long ("Reset: exhaust temperature") wraps them at BUTTON_MAX instead of making the
## row, and so the panel, wider than its share of the screen (#389: the bench widened on the phone at 150 %).
const BUTTON_MAX := 200.0       # canvas px at scale 1

static func _wrapping(b: Button) -> Button:
	var fs := int(FONT * W.scale)
	var w: float = ThemeDB.fallback_font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 24.0 * W.scale
	if w > BUTTON_MAX * W.scale:
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size.x = BUTTON_MAX * W.scale
	return b


## A row's name too long for BUTTON_MAX wraps there, as a button's (a long reading's name widened the bench past its
## share on a 16:9 phone at 150 %).
static func _wrapping_label(l: Label) -> Label:
	var fs := int(FONT * W.scale)
	if ThemeDB.fallback_font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > BUTTON_MAX * W.scale:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = BUTTON_MAX * W.scale
	return l


static func _num(x: float) -> String:
	return str(int(x)) if x == floorf(x) else "%.1f" % x


static func _title(name: String) -> String:
	return name.replace("_", " ").capitalize()
