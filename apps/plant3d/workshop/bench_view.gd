## The bench model drawn (docs/plant3d/WORKSHOP.md §6.1 "Bindings"): every channel reads one model value through the
## bench clock (workshop/bench_clock.gd), drawn between the last two steps, so nothing moves on its own:
##   anim      a component the generator gave a moving piece: translated along its axis (travel × value × scale) or
##             turned about it (radians)
##   show      the value on the component: on its face when the binding has `lit` (a display: dark while `lit` is
##             false, its face lit while true), else a tag over it (the terminals' current)
##   flow      a flow path's particles: speed and density from the value (its sign the direction), colour from a legend
##   heat, pressure   the component's colour from the legend of that name
##   sound     a sound of sounds.json (ui/sound_player.gd's files), its gain and pitch from tables of a value: heard
##             while the Workshop shows, not while the bench is paused or the plant's sounds were muted (K4b: the
##             turbine's blade-pass tone rising with its speed)
## Heat and pressure are shown while their toggle is on (views.heat_on, pressure_on); a component bound to both shows
## heat while both are. Lamps are not drawn on the bench yet (no kind has one).
extends RefCounted

const Views = preload("res://workshop/views.gd")
const LCD_ON := Color(0.70, 0.82, 0.66)         # a lit display's face (the backlight's colour on the grey LCD)
const LCD_OFF := Color(0.10, 0.11, 0.10)        # a dark one (no loop current: a loop-powered display goes out)
const FLOW_COLOUR := Color(0.45, 0.75, 1.0)     # a flow without a colour legend
## A freely turning part is drawn at most this fast (revolutions a second): faster, at 30 frames a second, a row of 34
## blades seems to stand or turn back (the wagon wheel), and a turbine at 3,000 rpm would turn 1.7 times a frame. Its
## real speed is on its tag, in the readouts and in its blade-pass tone.
const MAX_DRAWN_RPS := 0.4

var ws                          # workshop/workshop.gd
var clock                       # workshop/bench_clock.gd
var views                       # workshop/views.gd
var labels: Array = []          # [{label: Label3D, at, shows: [value], lit: value or ""}]
var anims: Array = []           # [{at, of, scale, axis, kind, travel}]
var flows: Array = []           # [{flow, of, speed, legend, by}]
var ramps: Array = []           # [{at, of, legend}]
var lits := {}                  # component -> its `lit` value (a display's face)
var sounds: Array = []          # [{gain, pitch, players: [[AudioStreamPlayer, layer]]}]
var muted := false              # the plant's sounds were muted when the Workshop opened
var shown_ramps := {}           # component -> the ramp entry it shows now (tests)


## The machine and its bench model are loaded: the bindings found, the labels made where they show.
func setup(machine: Node3D) -> void:
	labels.clear()
	anims.clear()
	flows.clear()
	ramps.clear()
	lits.clear()
	sounds.clear()
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
		elif x.has("sound"):
			var u = ws.get("ui")   # (null in the gallery's stand-in)
			var sp = u.sounds if u != null else null
			var players: Array = []
			if sp != null and sp.available():
				var s: Dictionary = sp.index.get(x.sound, {})
				for layer in s.get("layers", []):
					var st: AudioStream = sp._stream(layer["file"], s.get("loop", true))
					if st == null or not s.get("loop", true):
						continue
					var pl := AudioStreamPlayer.new()
					pl.bus = sp.PLANT_BUS   # (masked under the phone's music as the plant's sounds are)
					pl.name = "bench_sound_%s_%s" % [x.sound, layer["layer"]]
					pl.stream = st
					pl.volume_db = -80.0
					machine.add_child(pl)
					players.append([pl, layer])
			sounds.append({"id": x.sound, "gain": x.get("gain", 1.0), "pitch": x.get("pitch", 1.0), "players": players})


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
			else:                   # turns freely: the value × scale is its speed in revolutions a second, drawn at
									# most MAX_DRAWN_RPS
				# (dt is bench time: the cap is per second of the screen's, whatever the bench's speed)
				var rps := signf(v) * minf(absf(v), MAX_DRAWN_RPS / maxf(clock.speed, 0.01))
				a["angle"] = fmod(float(a.get("angle", 0.0)) + TAU * rps * dt, TAU)
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
	var shown := shown_ramps    # component -> the ramp it shows now
	shown.clear()
	for r in ramps:
		if (r.legend == "heat" and views.heat_on) or (r.legend == "pressure" and views.pressure_on):
			if not shown.has(r.at) or r.legend == "heat":
				shown[r.at] = r
	for r in ramps:
		if views.is_xrayed(r.at):
			continue
		if shown.get(r.at) == r:
			views.set_ramp(r.at, Views.legend_colour(clock.m.legends.get(r.legend, {}), clock.val(r.of)), 1.0)
		elif not shown.has(r.at) and not lits.has(r.at):
			views.set_ramp(r.at, Color.BLACK, 0.0)
	for s in sounds:
		var g := level(s.gain)
		var p := level(s.pitch)
		var on: bool = g > 0.001 and not muted and not clock.paused
		for pp in s.players:
			var pl: AudioStreamPlayer = pp[0]
			if on and not pl.playing:
				pl.play()
			elif not on and pl.playing:
				pl.stop()
			pl.volume_db = linear_to_db(maxf(g, 1e-5))
			if pp[1].get("pitch", true):
				pl.pitch_scale = clampf(p, 0.05, 4.0)


## A sound binding's gain or pitch now: a table of a value, or a number.
func level(spec) -> float:
	if typeof(spec) == TYPE_DICTIONARY:
		var t: Array = spec.table   # (the key as a property: table is also a part of the kit, not named here)
		var x: float = clock.val(spec["of"])
		if x <= float(t[0][0]):
			return float(t[0][1])
		for i in range(1, t.size()):
			if x <= float(t[i][0]):
				var a: Array = t[i - 1]
				var b: Array = t[i]
				return lerpf(float(a[1]), float(b[1]), (x - float(a[0])) / maxf(float(b[0]) - float(a[0]), 1e-12))
		return float(t[-1][1])
	return float(spec)


## The legend the Run panel shows: of the colours drawn now (heat first), "" when none.
func legend_shown() -> String:
	var kinds := {}
	for r in ramps:
		kinds[r.legend] = true
	if views.heat_on and kinds.has("heat"):
		return "heat"
	if views.pressure_on and kinds.has("pressure"):
		return "pressure"
	return ""


## The labels' text in the machine's first frame (so their pipelines compile with it, §7.1).
func warm_labels() -> void:
	for e in labels:
		e.label.text = "0.00"
