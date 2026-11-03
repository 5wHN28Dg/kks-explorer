## The bench model drawn (docs/plant3d/WORKSHOP.md §6.1 "Bindings"): every channel reads one model value through the
## bench clock (workshop/bench_clock.gd), drawn between the last two steps, so nothing moves on its own:
##   anim      a component the generator gave a moving piece: translated along its axis (travel × value × scale) or
##             turned about it (radians)
##   show      the value on the component: on its face when the binding has `lit` (a display: dark while `lit` is
##             false, its face lit while true), else a tag over it (the terminals' current)
##   flow      a flow path's particles: speed and density from the value (its sign the direction), colour from a legend
##   heat, pressure   the component's colour from the legend of that name
## Lamps and sounds are read by the plant's own bindings; the transmitter has none (K4b brings the turbine's sound).
extends RefCounted

const Views = preload("res://workshop/views.gd")
const LCD_ON := Color(0.70, 0.82, 0.66)         # a lit display's face (the backlight's colour on the grey LCD)
const LCD_OFF := Color(0.10, 0.11, 0.10)        # a dark one (no loop current: a loop-powered display goes out)
const FLOW_COLOUR := Color(0.45, 0.75, 1.0)     # a flow without a colour legend

var ws                          # workshop/workshop.gd
var clock                       # workshop/bench_clock.gd
var views                       # workshop/views.gd
var labels: Array = []          # [{label: Label3D, at, shows: [value], lit: value or ""}]
var anims: Array = []           # [{at, of, scale, axis, kind, travel}]
var flows: Array = []           # [{flow, of, speed, legend, by}]
var ramps: Array = []           # [{at, of, legend}]
var lits := {}                  # component -> its `lit` value (a display's face)


## The machine and its bench model are loaded: the bindings found, the labels made where they show.
func setup(machine: Node3D) -> void:
	labels.clear()
	anims.clear()
	flows.clear()
	ramps.clear()
	lits.clear()
	if clock == null or not clock.loaded():
		return
	var moving := {}
	for mv in machine.get_meta("moving", []):
		moving[mv.name] = mv
	var face := {}              # component -> its on-face label's entry
	var tag := {}               # component -> its tag's entry
	for x in clock.m.binds:
		if x.has("anim") and ws.comps.has(x.at) and moving.has(x.anim):
			var mv: Dictionary = moving[x.anim]
			anims.append({"at": x.at, "of": x.of, "scale": float(x.get("scale", 1.0)), "axis": mv.axis,
				"kind": mv.kind, "travel": float(mv.travel)})
		elif x.has("show") and ws.comps.has(x.at):
			var on_face: bool = x.has("lit")
			var table: Dictionary = face if on_face else tag
			if not table.has(x.at):
				table[x.at] = {"label": _label(machine, x.at, on_face), "at": x.at, "shows": [],
					"lit": x.get("lit", "")}
				labels.append(table[x.at])
				if on_face:
					lits[x.at] = x.lit
			table[x.at].shows.append(x.show)
		elif x.has("flow"):
			flows.append({"flow": x.flow, "of": x.of, "speed": float(x.speed), "legend": x.get("colour", ""),
				"by": x.get("by", "")})
		elif x.has("pressure") or x.has("heat"):
			var k := "pressure" if x.has("pressure") else "heat"
			if ws.comps.has(x.at):
				ramps.append({"at": x.at, "of": x[k], "legend": k})


## A label for a component's shows: on the face of its box that looks away from the machine's centre (its thinnest
## side), or a tag over it facing the camera.
func _label(machine: Node3D, at: String, on_face: bool) -> Label3D:
	var n: Node3D = ws.comps[at]
	var box: AABB = n.get_meta("box", AABB())
	var mbox: AABB = machine.get_meta("box", AABB())
	var l := Label3D.new()
	l.name = "show_" + at
	l.text = " "
	l.font_size = 32
	var p: Vector3
	if on_face:
		var k := 0
		for i in 3:
			if box.size[i] < box.size[k]:
				k = i
		var nrm := Vector3.ZERO
		nrm[k] = 1.0 if box.get_center()[k] >= mbox.get_center()[k] else -1.0
		p = box.get_center() + nrm * (box.size[k] * 0.5 + 0.0008)
		l.pixel_size = minf(box.size[(k + 1) % 3], box.size[(k + 2) % 3]) / 220.0
		l.modulate = Color(0.06, 0.08, 0.06)
		l.outline_size = 0
		var up := Vector3.UP if absf(nrm.y) < 0.9 else Vector3(0, 0, -1)
		l.basis = Basis.looking_at(-nrm, up)
	else:
		p = Vector3(box.get_center().x, box.end.y + 0.012, box.get_center().z)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.pixel_size = 0.0003
		l.font_size = 48
		l.outline_size = 10
		l.modulate = Color(1, 0.95, 0.6)
	n.add_child(l)
	l.position = n.global_transform.affine_inverse() * (machine.global_transform * p)
	return l


## Each frame, after the explode and the handling have placed every component: the bindings drawn. `dt`: the bench
## seconds this frame advanced (the flow's particles move by it, so a paused bench stands still).
func draw(dt: float) -> void:
	if clock == null or not clock.loaded():
		return
	for a in anims:
		var n: Node3D = ws.comps[a.at]
		var v: float = clock.val(a.of) * a.scale
		var t := n.transform
		if a.kind == "translate":
			t.origin += t.basis * (a.axis * a.travel * v)
		elif a.kind == "rotate":
			if a.travel != 0.0:     # turned through travel radians for 0 -> 1 (a stem, a damper)
				t.basis = t.basis * Basis(a.axis, a.travel * v)
			else:                   # turns freely: the value × scale is its speed in revolutions a second
				a["angle"] = fmod(float(a.get("angle", 0.0)) + TAU * v * dt, TAU)
				t.basis = t.basis * Basis(a.axis, a.angle)
		n.transform = t
	for e in labels:
		var lit_ok: bool = e.lit == "" or clock.now(e.lit) >= 0.5
		var txt := ""
		if lit_ok:
			var lines := PackedStringArray()
			for s in e.shows:
				lines.append(clock.shown(s))
			for al in clock.alarms_at(e.at):   # an active alarm shown where it is (`where`): its words to the colon
				lines.append(String(al).get_slice(":", 0))
			txt = "\n".join(lines)
		if e.label.text != txt and not (txt == "" and e.label.text == " "):
			e.label.text = txt if txt != "" else " "
		e.label.visible = not views.cuts(e.label.global_position)   # cut away with its component
	for at in lits:
		var on: bool = clock.now(lits[at]) >= 0.5
		views.set_ramp(at, LCD_ON if on else LCD_OFF, 1.0)
	for f in flows:
		var c := FLOW_COLOUR
		if f.legend != "" and clock.m.legends.has(f.legend):
			c = Views.legend_colour(clock.m.legends[f.legend], clock.val(f.by))
		# drawn only while the machine stands assembled: the path is in the machine's frame, through parts that move
		# when it is taken apart
		views.set_flow(f.flow, clock.val(f.of) if ws.assembled() else 0.0, f.speed, dt, c)
	for r in ramps:
		if views.is_xrayed(r.at):
			continue
		views.set_ramp(r.at, Views.legend_colour(clock.m.legends.get(r.legend, {}), clock.val(r.of)), 1.0)


## The labels' text in the machine's first frame (so their pipelines compile with it, §7.1).
func warm_labels() -> void:
	for e in labels:
		e.label.text = "0.00"
