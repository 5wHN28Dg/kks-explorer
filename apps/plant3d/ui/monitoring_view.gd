## Condition monitoring (docs/plant3d/REALISM.md §2.19, §9.3; milestone AG3): a machine's measurement points, opened
## from its card's "Condition monitoring". Drawn from the monitoring file (built/content/monitoring.json, made by
## tools/plant3d/train_monitoring.py; the engine never reads it) and the model's values:
## - the vibration data collector's screen: the overall velocity its meter shows, the ISO 20816-3 zone it falls in (the
##   point's group and zone limits), and the point's spectrum drawn from the model values the file names (the 1×, the
##   2×, the bearing's defect tones or the gear mesh, a noise floor), the lines' energy adding up to the overall;
## - the thermal camera's spot reading at the bearing housing, against its alert and alarm limits, and its false-colour
##   picture: the pump's Workshop tree with each component at its model value's temperature (ui/thermal_picture.gd);
## - the oil sample: a hand action at the equipment's work place with the sampling kit (`samples`), the lab's results
##   arriving after the lab's turnaround (the engine's `lab` events), against their alert and alarm limits.
## A reading is recorded as S1's `read` with the meter named (ui/inputs.gd); the point's readings are listed from the
## run's inputs (a reading no task step waits on makes no event; saves keep the inputs).
extends Control

const W = preload("res://ui/widgets.gd")
const JsonStrict = preload("res://sim/json_strict.gd")
const Hands = preload("res://sim/hands.gd")
const WorkView = preload("res://ui/work_view.gd")
const ThermalPicture = preload("res://ui/thermal_picture.gd")

const FILE := "res://built/content/monitoring.json"
const ZONE_NAMES := ["A", "B", "C", "D"]
## ISO 20816-3's zones in words (its evaluation zones, §6.2 of part 1).
const ZONE_WORDS := ["newly commissioned machines", "unrestricted long-term operation",
	"restricted: plan a remedy, not for long-term operation", "damage: vibration severe enough to damage the machine"]
const ZONE_COLOURS := [Color(0.25, 0.75, 0.35), Color(0.75, 0.85, 0.25), Color(1.0, 0.6, 0.1), Color(0.95, 0.25, 0.2)]
## ISO 20816-3's zone limits (mm/s r.m.s., A/B, B/C, C/D) by group and support: a point whose limits are one of these
## is labelled with the standard; any other (the fans' gear reducers: AG2's advisory values) as the plant's own.
const ISO_ZONES := [[1, "rigid", [2.3, 4.5, 7.1]], [1, "flexible", [3.5, 7.1, 11.0]], [2, "rigid", [1.4, 2.8, 4.5]],
	[2, "flexible", [2.3, 4.5, 7.1]]]
const LEVEL_WORDS := ["normal", "alert", "alarm"]
const LEVEL_COLOURS := [Color(0.6, 1.0, 0.6), Color(1.0, 0.75, 0.2), Color(1.0, 0.4, 0.35)]
## The engine's reasons for a refused oil sample, in words (the work view's for the rest).
const WHY := {
	"authority": "Taking oil samples needs the sample authority: the mechanical technician's, or a chemist's",
	"where": "Stand at its work place to take the sample (Go there, then walk up to it)",
	"tool": "Carry the oil sampling kit (Tools, at the store counter)",
	"lab": "The lab already holds 8 of its samples: wait for their results",
}
const HISTORY := 5              # readings listed per point


## The spectrum's drawing: vertical lines at their orders of the running speed over a noise floor.
class Spectrum extends Control:
	var lines: Array = []       # [name, order, mm/s]
	var floor_v := 0.0
	var top := 1.0              # the amplitude axis' full scale, mm/s
	var max_order := 10.0
	var rpm := 0.0

	func _draw() -> void:
		var f := ThemeDB.fallback_font
		var fs := int(14 * W.scale)
		var s := size
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.03, 0.06, 0.04))
		var l := 34.0 * W.scale
		var b := s.y - 34.0 * W.scale
		var t := 20.0 * W.scale
		var w := s.x - l - 10.0 * W.scale
		var h := b - t
		var axis := Color(0.5, 0.6, 0.5)
		draw_line(Vector2(l, t), Vector2(l, b), axis, 1.0)
		draw_line(Vector2(l, b), Vector2(l + w, b), axis, 1.0)
		var step := 1.0 if max_order <= 12.0 else (5.0 if max_order <= 60.0 else 10.0)
		var o := 0.0
		while o <= max_order + 1e-9:
			var x := l + o / max_order * w
			draw_line(Vector2(x, b), Vector2(x, b + 4 * W.scale), axis, 1.0)
			draw_string(f, Vector2(x - 12 * W.scale, b + 18 * W.scale), "%d" % int(o), HORIZONTAL_ALIGNMENT_CENTER,
					24 * W.scale, fs, axis)
			o += step
		draw_string(f, Vector2(l, s.y - 2 * W.scale), "orders of the running speed (1× = %d rpm, %.1f Hz)" % [int(rpm),
				rpm / 60.0], HORIZONTAL_ALIGNMENT_LEFT, w, fs, axis)
		draw_string(f, Vector2(2, t - 6 * W.scale), "%.2f mm/s" % top, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, axis)
		# the noise floor: a fixed ragged line (not random each frame) about its level
		var pts := PackedVector2Array()
		var n := int(w / (3.0 * W.scale))
		for i in n + 1:
			var jit := 0.55 + 0.45 * absf(sin(float(i) * 12.9898) * 43758.5453 - floorf(sin(float(i) * 12.9898) * 43758.5453))
			pts.append(Vector2(l + w * float(i) / maxf(n, 1), b - minf(floor_v * jit / top, 1.0) * h))
		if pts.size() >= 2:
			draw_polyline(pts, Color(0.35, 0.6, 0.4), 1.0)
		var green := Color(0.55, 1.0, 0.55)
		for ln in lines:
			if float(ln[1]) > max_order:
				continue
			var x := l + float(ln[1]) / max_order * w
			var y := b - minf(float(ln[2]) / top, 1.0) * h
			draw_line(Vector2(x, b), Vector2(x, y), green, 3.0 * W.scale)
			if float(ln[2]) >= 2.0 * floor_v:
				draw_string(f, Vector2(x - 40 * W.scale, y - 4 * W.scale), String(ln[0]), HORIZONTAL_ALIGNMENT_CENTER,
						80 * W.scale, fs, Color.WHITE)


## ISO 20816-3's zones as a bar, the value marked.
class ZoneBar extends Control:
	var zones: Array = [1.0, 2.0, 3.0]
	var value := 0.0

	func _draw() -> void:
		var f := ThemeDB.fallback_font
		var fs := int(14 * W.scale)
		var s := size
		var full := float(zones[2]) * 1.35
		var edges := [0.0, float(zones[0]), float(zones[1]), float(zones[2]), full]
		var bar := s.y - 18.0 * W.scale
		for i in 4:
			var x0 := float(edges[i]) / full * s.x
			var x1 := float(edges[i + 1]) / full * s.x
			draw_rect(Rect2(x0, 0, x1 - x0, bar), ZONE_COLOURS[i].darkened(0.25))
			draw_string(f, Vector2(x0, bar * 0.5 + fs * 0.35), ZONE_NAMES[i], HORIZONTAL_ALIGNMENT_CENTER, x1 - x0, fs,
					Color.BLACK)
			if i < 3:
				draw_string(f, Vector2(x1 - 30 * W.scale, s.y - 2), "%.1f" % float(edges[i + 1]),
						HORIZONTAL_ALIGNMENT_CENTER, 60 * W.scale, fs, Color(0.8, 0.8, 0.8))
		var vx := clampf(value / full, 0.0, 1.0) * s.x
		draw_line(Vector2(vx, -2), Vector2(vx, bar + 2), Color.WHITE, 3.0 * W.scale)


var ui                          # ui/plant_ui.gd
var points: Array = []          # the monitoring file's points
var by_machine := {}            # machine key (machine_of) -> [point index]
var by_code := {}               # a point's code -> true (only those codes' cards offer the view)
var by_node := {}               # an oil result's node -> point index
var code := ""                  # open from this code ("" closed)
var machine := ""
var last_text := ""             # the last refusal or result shown (tests read it)
var panel: PanelContainer
var body: VBoxContainer
var title: Label
var note: Label
var _sig := ""
var _rows := {}                 # point index -> {widgets}
var _t := 0.0
var _js: Array = []             # the run's jumps, at the last rebuild
var _reads := 0                 # the machine's readings recorded (the panel's history rebuilt when it changes)
var _in_seen := 0               # the run's inputs looked at for them
var _qprev := {}                # an oil point's first node -> its queue's length at the last look (on_events)
var _eng = null                 # the engine those belong to (a restart or a load starts again)


func setup(u) -> void:
	ui = u
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	read_points(FILE)
	var p := W.panel("", close)
	panel = p[0]
	body = p[1]
	title = p[2]
	panel.name = "monitoring_panel"
	add_child(panel)
	panel.visible = false
	note = W.label("", 18, W.BAD_COLOUR)
	note.name = "note"
	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	var vs := get_viewport_rect().size
	var w := minf(560.0 * W.scale, vs.x * 0.5)
	panel.position = Vector2(vs.x - w - 12, 12)
	panel.size = Vector2(w, vs.y - 24)


## The monitoring file's points (none when it is missing or fails the strict reader: the cards then offer nothing).
func read_points(path: String) -> void:
	points.clear()
	by_machine.clear()
	by_code.clear()
	by_node.clear()
	if not FileAccess.file_exists(path):
		return
	var r := JsonStrict.parse(FileAccess.get_file_as_bytes(path))
	if not r.get("ok", false) or r["value"].get("format", "") != "walkdown-plant-monitoring":
		push_warning("monitoring.json: %s" % r.get("error", "not a monitoring file"))
		return
	points = r["value"]["points"]
	for i in points.size():
		var k := machine_of(String(points[i]["code"]))
		if not by_machine.has(k):
			by_machine[k] = []
		by_machine[k].append(i)
		by_code[String(points[i]["code"])] = true
		for res in points[i].get("results", []):
			by_node[String(res["node"])] = i


## A machine's points share their system and number: a pump's vibration probe 30PAC10CY001 and its motor
## 30PAC10AP001, a fan's probe 30PAD10CY001 and its gear reducer 30PAD10AN001. Only the points' own codes offer the
## view (30PAC10CP001, a pressure transmitter of the same number, does not).
static func machine_of(c: String) -> String:
	return c.substr(0, 7) + "|" + c.right(3)


func has_points(c: String) -> bool:
	return by_code.has(c)


func is_open() -> bool:
	return panel.visible


func open(c: String) -> bool:
	if not has_points(c):
		return false
	code = c
	machine = machine_of(c)
	title.text = "Condition monitoring\n%s  %s" % [c, ui.info.name_of(c)]
	last_text = ""
	note.text = ""
	_sig = ""
	_eng = null             # (another machine: its readings counted afresh)
	panel.visible = true
	ui.close_card()
	refresh()
	return true


func close() -> void:
	panel.visible = false
	code = ""
	machine = ""


func _process(delta: float) -> void:
	if not panel.visible:
		return
	_t += delta
	if _t >= 0.25:
		_t = 0.0
		refresh()


# ------------------------------------------------------------------ what is drawn (pure: the tests call these)

## What a point's zones are: ISO 20816-3's (group and support) or the plant's own limits.
static func zone_basis(p: Dictionary) -> String:
	for z in ISO_ZONES:
		if int(z[0]) == int(p["group"]) and z[2] == p["zones"]:
			return "ISO 20816-3 group %d, %s support" % [int(z[0]), String(z[1])]
	return "the plant's own limits for it (not ISO 20816-3's)"


## The ISO 20816-3 zone (0 A … 3 D) a velocity falls in: a boundary belongs to the zone below it.
static func zone(p: Dictionary, v: float) -> int:
	var z: Array = p["zones"]
	for i in 3:
		if v <= float(z[i]):
			return i
	return 3


## A line's amplitude as the file names it: a model value (times `by`, times `share`), or a share of the overall.
static func line_value(e, ln: Dictionary, overall: float) -> float:
	if ln.has("value"):
		var x: float = _val(e, ln["value"])
		if ln.has("by"):
			x *= _val(e, ln["by"])
		return maxf(x * float(ln.get("share", 1.0)), 0.0)
	return maxf(float(ln["share"]) * overall, 0.0)


static func _val(e, ref) -> float:
	if typeof(ref) == TYPE_STRING:
		return e.v(ref)
	return float(ref)


## The spectrum at a point for the overall shown: [[name, order, mm/s] …] with the 1× first, and the floor drawn.
## The lines' energy and the floor's add up to the overall (REALISM.md §2.19): the 1× takes what the others leave,
## and when they alone would exceed it they are scaled down to fit (the 1× then nothing).
static func spectrum(e, p: Dictionary, overall: float) -> Dictionary:
	var ov := maxf(overall, 0.0)
	var fl := minf(float(p["floor"]), ov)
	var out: Array = []
	var s := 0.0
	for ln in p["lines"]:
		var a := line_value(e, ln, ov)
		out.append([String(ln["name"]), float(ln["order"]), a])
		s += a * a
	var room := ov * ov - fl * fl
	var one := 0.0
	if s > room:
		var k := sqrt(maxf(room, 0.0) / s) if s > 0.0 else 0.0
		for x in out:
			x[2] = x[2] * k
	else:
		one = sqrt(room - s)
	return {"lines": [["1×", 1.0, one]] + out, "floor": fl}


## An oil result's level (0 normal, 1 alert, 2 alarm): a limit is a ceiling, or a band [low, high] (viscosity). The
## app judges the value as shown (`shown`): the same number is never two levels.
static func level(res: Dictionary, v: float) -> int:
	var lv := 0
	for k in 2:
		var lim = res["alert" if k == 0 else "alarm"]
		var out: bool = (v < float(lim[0]) or v > float(lim[1])) if typeof(lim) == TYPE_ARRAY else v > float(lim)
		if out:
			lv = k + 1
	return lv


## The run's jumps done: [[step, tenths added] …] (one look at the log per rebuild, not per line shown).
static func jumps(e) -> Array:
	var out: Array = []
	for ev in e.events:
		if ev[1] == "jump" and ev.size() > 4 and ev[4] == "done":
			out.append([int(ev[0]), int(ev[3]) - int(ev[2])])
	return out


## The plant clock at step n (the jumps made by then counted), in tenths.
static func clock_at(e, n: int, js: Array) -> int:
	var c: int = e._S + n * e._ds
	for j in js:
		if j[0] <= n:
			c += j[1]
	return c


## An oil result as the report shows it: whole numbers (an ISO 4406 code is a whole number), viscosity to 0.1 cSt.
static func shown(res: Dictionary, v: float) -> float:
	return snappedf(v, 0.1) if String(res["unit"]) == "cSt" else roundf(v)


static func clock_words(e, t: int) -> String:
	var s: int = (t % 864000) / 10
	return "Day %d %02d:%02d" % [t / 864000, s / 3600, (s / 60) % 60]


## The point's readings recorded (newest first): [step, value] from the run's `read` inputs with its meter.
static func readings(e, p: Dictionary) -> Array:
	var out: Array = []
	for it in e.inputs:
		if it.size() > 4 and it[1] == "read" and it[2] == p["code"] and typeof(it[4]) == TYPE_STRING \
				and it[4] == p["meter"]:
			out.push_front([int(it[0]), float(it[3])])
	return out


## The lab's reports for an oil point (newest first): [step, {node: value}], one per sample.
static func reports(e, p: Dictionary) -> Array:
	var nodes := {}
	for res in p["results"]:
		nodes[String(res["node"])] = true
	var out: Array = []
	for ev in e.events:
		if ev[1] == "lab" and nodes.has(ev[2]):
			# one sample's results come together; a jump's step can bring several samples of a point: each its own
			if out.is_empty() or out[0][0] != int(ev[0]) or out[0][1].has(ev[2]):
				out.push_front([int(ev[0]), {}])
			out[0][1][ev[2]] = float(ev[3])
	return out


# ------------------------------------------------------------------ the panel

func _carries(kind: String, mode = null) -> bool:
	return Hands.carries_kind(ui.clock.engine, ui.me(), kind, mode)


## Whether the trainee stands within reach of a point (its own code where it is drawn, else the code the view was
## opened from: another point of the same machine).
func _near(p: Dictionary) -> bool:
	var c: String = p["code"]
	return ui.near(c) if ui.index.has(c) else ui.near(code)


func _tool_of(kind: String) -> String:
	var e = ui.clock.engine
	var tools = e.m.tools
	for t in e.carried.get(ui.me(), []):
		if tools != null and tools["list"][tools["ix"][t]]["kind"] == kind:
			return t
	return ""


func refresh() -> void:
	if not panel.visible:
		return
	var e = ui.clock.engine
	if e == null:
		return
	var pid = ui.me()
	_count_reads(e)
	var parts := PackedStringArray([str(e.carried.get(pid, [])), str(e.busy.get(pid, [])), str(_reads)])
	for i in by_machine.get(machine, []):
		var p: Dictionary = points[i]
		parts.append("1" if _near(p) else "0")
		if p["kind"] == "oil":
			parts.append(str(e.lab_q.get(String(p["results"][0]["node"]), []).size()))   # (results arriving: on_events)
	var sig := "|".join(parts)
	if sig != _sig:
		_sig = sig
		_build(e, pid)
	_write(e, pid)


## The machine's readings recorded since the last look (only new inputs read): the panel is rebuilt for a reading of
## its own, not for every input of the run (an arrival, another player's op).
func _count_reads(e) -> void:
	if e != _eng:
		_eng = e
		_in_seen = 0
		_reads = 0
		_qprev.clear()
	if _in_seen > e.inputs.size():
		_in_seen = 0
	var mine := {}
	for i in by_machine.get(machine, []):
		if points[i].has("meter"):
			mine[String(points[i]["meter"])] = true
	for k in range(_in_seen, e.inputs.size()):
		var it: Array = e.inputs[k]
		if it.size() > 4 and it[1] == "read" and typeof(it[4]) == TYPE_STRING and mine.has(it[4]):
			_reads += 1
	_in_seen = e.inputs.size()


func _build(e, pid) -> void:
	_js = jumps(e)
	if note.get_parent() != null:
		note.get_parent().remove_child(note)    # (kept: W.clear frees what it removes)
	W.clear(body)
	_rows.clear()
	if pid == null:
		body.add_child(W.label("Take a role (Crew) to take readings and samples.", 18, W.DIM))
	body.add_child(note)
	for i in by_machine.get(machine, []):
		var p: Dictionary = points[i]
		var box := VBoxContainer.new()
		box.name = "point_%d" % i
		body.add_child(box)
		box.add_child(W.label(String(p["title"]), 22))
		var row := {}
		match String(p["kind"]):
			"vib": _build_vib(e, i, p, box, row)
			"ir": _build_ir(e, i, p, box, row)
			"oil": _build_oil(e, i, p, box, row)
		_rows[i] = row
		body.add_child(HSeparator.new())
	var src := W.label("Oil: the lab's routine tests (ASTM D6224), ISO 4406 cleanliness.", 14, W.DIM)
	body.add_child(src)


func _build_vib(e, i: int, p: Dictionary, box: VBoxContainer, row: Dictionary) -> void:
	var why := ""
	if not _carries("collector", "vel"):
		why = "Carry the vibration data collector (Tools, at the store counter) to read it"
	elif not _near(p):
		why = "Walk up to the bearing to put the collector's probe on it"
	box.add_child(W.label("Vibration data collector: overall velocity, 10 Hz to 1 kHz (mm/s r.m.s.). Zones: %s"
			% zone_basis(p), 16, W.DIM))
	if why != "":
		var l := W.label(why, 17, W.DIM)
		l.name = "why"
		box.add_child(l)
	else:
		var screen := PanelContainer.new()
		screen.name = "collector"
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.12, 0.08, 0.95)
		sb.set_corner_radius_all(6)
		sb.set_content_margin_all(8)
		screen.add_theme_stylebox_override("panel", sb)
		var v := VBoxContainer.new()
		screen.add_child(v)
		var val := W.label("", 30, Color(0.6, 1.0, 0.6))
		val.name = "value"
		v.add_child(val)
		var zl := W.label("", 17, Color.WHITE)
		zl.name = "zone"
		v.add_child(zl)
		var bar := ZoneBar.new()
		bar.name = "zone_bar"
		bar.zones = p["zones"]
		bar.custom_minimum_size = Vector2(0, 40 * W.scale)
		v.add_child(bar)
		var sp := Spectrum.new()
		sp.name = "spectrum"
		sp.rpm = float(p["rpm"])
		var mo := 1.0
		for ln in p["lines"]:
			mo = maxf(mo, float(ln["order"]))
		sp.max_order = ceilf(mo * 1.15) if mo * 1.15 <= 12.0 else ceilf(mo * 1.15 / 5.0) * 5.0
		sp.custom_minimum_size = Vector2(0, 230 * W.scale)
		v.add_child(sp)
		var rb := W.button("Record the reading", func(): record(i))
		rb.name = "record"
		v.add_child(rb)
		box.add_child(screen)
		row["value"] = val
		row["zone"] = zl
		row["bar"] = bar
		row["spectrum"] = sp
	_history(e, p, box, row)


func _build_ir(e, i: int, p: Dictionary, box: VBoxContainer, row: Dictionary) -> void:
	var why := ""
	if not _carries("camera", "ir"):
		why = "Carry the thermal camera (Tools, at the store counter) to read it"
	elif not _near(p):
		why = "Walk up to it to aim the camera's spot at the bearing housing"
	box.add_child(W.label("Thermal camera: the spot temperature (°C). Alert %d °C, alarm %d °C" % [int(p["limits"][0]),
			int(p["limits"][1])], 16, W.DIM))
	if why != "":
		var l := W.label(why, 17, W.DIM)
		l.name = "why"
		box.add_child(l)
	else:
		var line := HBoxContainer.new()
		line.name = "camera"
		var val := W.label("", 30, Color(0.6, 1.0, 0.6), false)
		val.name = "value"
		val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(val)
		var rb := W.button("Record the reading", func(): record(i))
		rb.name = "record"
		line.add_child(rb)
		box.add_child(line)
		row["value"] = val
		if p.has("picture"):
			var tp := ThermalPicture.new()
			tp.setup(p["picture"])
			box.add_child(tp)
			row["picture"] = tp
	_history(e, p, box, row)


func _history(e, p: Dictionary, box: VBoxContainer, row: Dictionary) -> void:
	var rs := readings(e, p)
	var unit := "mm/s" if p["kind"] == "vib" else "°C"
	var lines := PackedStringArray()
	for k in mini(rs.size(), HISTORY):
		lines.append("%s   %.2f %s" % [clock_words(e, clock_at(e, rs[k][0], _js)), rs[k][1], unit])
	var l := W.label(("Recorded:\n" + "\n".join(lines)) if not lines.is_empty() else "Nothing recorded yet.", 16, W.DIM)
	l.name = "history"
	box.add_child(l)
	row["history"] = l


func _build_oil(e, i: int, p: Dictionary, box: VBoxContainer, row: Dictionary) -> void:
	box.add_child(W.label("An oil sample (%d minutes with the sampling kit, at its work place); the lab's results after %d hours"
			% [_minutes(e, p), int(p["hours"])], 16, W.DIM))
	var b := W.button("Take an oil sample", func(): sample(i))
	b.name = "sample"
	box.add_child(b)
	var busy := W.label("", 17, W.OK_COLOUR)
	busy.name = "busy"
	box.add_child(busy)
	row["busy"] = busy
	row["sample"] = b
	var q: Array = e.lab_q.get(String(p["results"][0]["node"]), [])
	var ql := W.label("", 16, W.DIM)
	ql.name = "queue"
	if not q.is_empty():
		ql.text = "At the lab: %d sample%s; the next results due %s" % [q.size(), "" if q.size() == 1 else "s",
				clock_words(e, int(q[0][0]))]
	box.add_child(ql)
	var reps := reports(e, p)
	if reps.is_empty():
		var nl := W.label("No lab results yet.", 16, W.DIM)
		nl.name = "results"
		box.add_child(nl)
		return
	var g := GridContainer.new()
	g.name = "results"
	g.columns = 3
	g.add_theme_constant_override("h_separation", int(14 * W.scale))
	box.add_child(W.label("Lab report of %s" % clock_words(e, clock_at(e, reps[0][0], _js)), 17))
	box.add_child(g)
	for res in p["results"]:
		var nd: String = res["node"]
		if not reps[0][1].has(nd):
			continue
		var v: float = shown(res, float(reps[0][1][nd]))
		var lv := level(res, v)
		g.add_child(W.label(String(res["title"]), 16, W.DIM, false))
		var vl := W.label(("%.0f" if String(res["unit"]) != "cSt" else "%.1f") % v + (" " + String(res["unit"])
				if String(res["unit"]) != "" else ""), 17, LEVEL_COLOURS[lv], false)
		vl.name = "res_" + nd
		g.add_child(vl)
		var prev := ""
		if reps.size() > 1 and reps[1][1].has(nd):
			prev = "was %s" % (("%.0f" if String(res["unit"]) != "cSt" else "%.1f") % float(reps[1][1][nd]))
		g.add_child(W.label(LEVEL_WORDS[lv] + ("  (" + prev + ")" if prev != "" else ""), 16, LEVEL_COLOURS[lv], false))


func _minutes(e, p: Dictionary) -> int:
	var x = e.m.hands_ix.get(String(p["code"]) + "|" + String(p["action"]))
	return int(x.get("minutes", 0)) if x != null else 0


## Whether an oil point takes this sampling action at this code (its refusals are this view's to say).
func handles(c: String, action: String) -> bool:
	for i in by_machine.get(machine_of(c), []):
		if points[i]["kind"] == "oil" and points[i]["code"] == c and points[i]["action"] == action:
			return true
	return false


func _write(e, pid) -> void:
	for i in _rows:
		var p: Dictionary = points[i]
		var row: Dictionary = _rows[i]
		if row.has("value") and e.m.meters_ix.has(String(p["meter"])):
			var v: float = Hands.shown(e, String(p["meter"]), e.cur)
			if p["kind"] == "vib":
				(row["value"] as Label).text = "%.2f mm/s" % v
				var z := zone(p, v)
				(row["zone"] as Label).text = "Zone %s: %s" % [ZONE_NAMES[z], ZONE_WORDS[z]]
				(row["zone"] as Label).add_theme_color_override("font_color", ZONE_COLOURS[z])
				var bar: ZoneBar = row["bar"]
				if bar.value != v:
					bar.value = v
					bar.queue_redraw()
				var sp: Spectrum = row["spectrum"]
				var s := spectrum(e, p, v)
				var top := maxf(float(p["floor"]) * 4.0, 0.1)
				for ln in s["lines"]:
					top = maxf(top, float(ln[2]) * 1.25)
				if str(s["lines"]) != str(sp.lines) or sp.top != top:
					sp.lines = s["lines"]
					sp.floor_v = s["floor"]
					sp.top = top
					sp.queue_redraw()
			else:
				var lim: Array = p["limits"]
				v = snappedf(v, 0.1)            # (judged as shown)
				var lv := 2 if v >= float(lim[1]) else (1 if v >= float(lim[0]) else 0)
				(row["value"] as Label).text = "%.1f °C  %s" % [v, LEVEL_WORDS[lv]]
				(row["value"] as Label).add_theme_color_override("font_color", LEVEL_COLOURS[lv])
				if row.has("picture"):
					row["picture"].update(e)
		if p["kind"] == "oil":
			var b = e.busy.get(pid) if pid != null else null
			var busy: bool = b != null and b[0] == p["code"] and b[1] == p["action"]
			(row["sample"] as Button).disabled = busy or pid == null
			if busy:
				var x: Dictionary = e.m.hands_ix[b[0] + "|" + b[1]]
				var start: float = float(b[4]) - ceilf(float(x["minutes"]) * Hands.MINUTE)
				var f := clampf((e.clock() - start) / maxf(float(b[4]) - start, 1.0), 0.0, 1.0)
				(row["busy"] as Label).text = "Taking the sample… %d %%" % int(f * 100.0)
			else:
				(row["busy"] as Label).text = ""


# ------------------------------------------------------------------ what the trainee does

## The reading recorded: S1's read with the meter named (REALISM.md §2.5).
func record(i: int) -> int:
	var p: Dictionary = points[i]
	var e = ui.clock.engine
	var v := snappedf(Hands.shown(e, String(p["meter"]), e.cur), 0.01)
	last_text = "Recorded %.2f" % v
	return ui.inputs.read(String(p["code"]), v, String(p["meter"]))


## The oil sample taken: its hand action with the sampling kit carried.
func sample(i: int) -> int:
	var p: Dictionary = points[i]
	var t := _tool_of("sampler")
	note.text = ""
	return ui.inputs.hand(String(p["code"]), String(p["action"]), t if t != "" else null, null, ui.me())


func _show(text: String, ok := false) -> void:
	last_text = text
	note.text = text
	note.add_theme_color_override("font_color", W.OK_COLOUR if ok else W.BAD_COLOUR)
	if not panel.visible:
		ui.toast(text)


## The engine's events since the last look (ui/plant_ui.gd passes them on): this person's oil samples refused or
## done, and the lab's results as they arrive (a toast, open or not). A sampling action done takes no sample when its
## node's queue filled while it was under way (REALISM.md §2.19): told by the queue, which grew by the samples taken
## less the results delivered since the last look.
func on_events(evs: Array, from: int) -> void:
	var e = ui.clock.engine
	if e != _eng:
		_eng = e
		_in_seen = 0
		_reads = 0
		_qprev.clear()
	var pid = ui.me()
	var told := {}
	var got := {}           # node -> results delivered in these events
	for k in range(from, evs.size()):
		var ev: Array = evs[k]
		if ev[1] == "lab" and by_node.has(ev[2]):
			got[ev[2]] = got.get(ev[2], 0) + 1
			var i: int = by_node[ev[2]]
			if not told.has(i):
				told[i] = true
				ui.toast("Lab results: %s" % points[i]["title"], 6.0)
			if machine_of(String(points[i]["code"])) == machine:
				_sig = ""
		elif ev[1] == "hand" and pid != null and ev[5] == pid and ev.size() > 7 and handles(str(ev[2]), str(ev[3])):
			if ev[6] == "refused":
				var x = e.m.hands_ix.get(str(ev[2]) + "|" + str(ev[3]))
				var why := PackedStringArray()
				for r in ev[7]:
					why.append(WHY[r] if WHY.has(r) else WorkView.hand_reason(x, String(r), ev[4]))
				_show("; ".join(why))
			elif ev[6] == "done":
				var nd: String = e.m.hands_ix[str(ev[2]) + "|" + str(ev[3])]["samples"][0]
				var before = _qprev.get(nd)
				if before == null or e.lab_q[nd].size() - int(before) + int(got.get(nd, 0)) > 0:
					_show("Sample taken: it goes to the lab", true)
				else:
					_show("No sample taken: the lab already holds 8 of its samples (another was taken meanwhile)")
				_sig = ""
			elif ev[6] == "abandoned":
				_show("The sample was not finished: stay at the equipment until it is done")
	for nd in by_node:
		_qprev[nd] = e.lab_q[nd].size() if e.lab_q.has(nd) else 0
