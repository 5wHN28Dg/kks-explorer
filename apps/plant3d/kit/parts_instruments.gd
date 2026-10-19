## Instruments and people cues (docs/PLANT3D.md §9 "Instruments", "People cues"). An instrument stands on what it
## measures: `ctx.out` is the direction away from that (a pipe's side or top, a machine's casing, a vessel's wall;
## the builder works it out), and the instrument is drawn from its origin along it. `ctx.floor_dz` (when given) is
## how far below the origin the floor is: a transmitter standing free beside a pump gets a 2" stand pipe down to it.
##
## Moving nodes (kit/README.md "Moving parts"): `needle` (gauges: turns clockwise as the dial is read, about the
## dial's inward normal, travel 4.71 rad: 0 = the scale's start, 1 = its end), `level` (a level glass's water column: kind scale along z, 0 empty, 1 full),
## `light` (lamps and beacons: its child `on` is the lit lens, hidden until the light is on).
extends RefCounted

const C = preload("res://kit/parts_common.gd")

## The frame an instrument is drawn in: z along ctx.out, y as near the world's up as it can be (or the part's forward
## when out is vertical), origin at the mount.
static func frame(g) -> Transform3D:
	var out: Vector3 = g.ctx.get("out", Vector3(0, 0, 1))
	out = out.normalized()
	var y := Vector3(0, 0, 1) if absf(out.z) < 0.8 else Vector3(0, 1, 0)
	y = (y - out * y.dot(out)).normalized()
	var x := y.cross(out).normalized()
	return Transform3D(Basis(x, y, out), Vector3.ZERO)

static func _local(g, mb) -> Transform3D:
	var t := frame(g)
	mb.xf = t
	return t

## A dial gauge on a stem: pressure (a root valve and a siphon) or temperature (a thermowell into the pipe).
static func _gauge(g, temp: bool) -> void:
	var m = g.m
	var t := _local(g, m)
	var Rd: float = g.num("dial_d", 0.1) * 0.5 if not temp else 0.05
	var vertical: bool = absf(t.basis.z.z) > 0.8
	m.use("steel", "identify")
	if temp:
		m.cyl(Vector3(0, 0, -0.08), Vector3(0, 0, 0.04), 0.012, -1.0, 8)   # the thermowell's neck
		m.cyl(Vector3(0, 0, 0.0), Vector3(0, 0, 0.02), 0.025, -1.0, 6)
	else:
		m.box(Vector3(0, 0, 0.03), Vector3(0.05, 0.04, 0.05))              # root valve
		m.use("paint_red", "identify")
		m.cyl(Vector3(0.025, 0, 0.03), Vector3(0.06, 0, 0.03), 0.006, -1.0, 6)
		m.box(Vector3(0.062, 0, 0.03), Vector3(0.008, 0.05, 0.012))
		m.use("steel", "detail", 0.01)
		m.torus(Vector3(0, 0, 0.09), Vector3(1, 0, 0), Vector3(0, 0, 1), 0.02, 0.005, TAU, 10, 6)   # the siphon's loop
	m.use("steel", "identify")
	var zc: float
	var nrm: Vector3
	if vertical:
		zc = 0.12 + Rd
		nrm = Vector3(1, 0, 0)
		m.cyl(Vector3(0, 0, 0.05), Vector3(0, 0, zc - Rd * 0.9), 0.008, -1.0, 8)
	else:
		zc = 0.12
		nrm = Vector3(0, 0, 1)
		m.cyl(Vector3(0, 0, 0.05), Vector3(0, 0, zc - 0.02), 0.008, -1.0, 8)
	var c := Vector3(0, 0, zc) if vertical else Vector3(0, 0, zc)
	var back := c - nrm * 0.02
	var front := c + nrm * 0.02
	m.use("chrome", "identify")
	m.cyl(back, front, Rd, -1.0, 24)
	m.use("dial", "identify")
	m.disk(front + nrm * 0.001, nrm, Rd * 0.88, 24)
	# the scale: from 135 degrees left of the top to 135 degrees right of it, clockwise as the viewer sees it
	var up_d := Vector3(0, 0, 1) if vertical else Vector3(0, 1, 0)
	var right_d := up_d.cross(nrm)
	var at_angle := func(deg: float) -> Vector3: return up_d * cos(deg_to_rad(deg)) + right_d * sin(deg_to_rad(deg))
	m.use("needle", "detail", Rd * 0.1)
	for i in 11:
		var dir: Vector3 = at_angle.call(-135.0 + 27.0 * i)
		m.box(front + nrm * 0.0015 + dir * Rd * 0.75, Vector3(0.003, Rd * 0.14, 0.002), Basis(nrm.cross(dir), dir, nrm))
	m.use("paint_red", "identify")   # the red mark at the limit
	m.box(front + nrm * 0.002 + at_angle.call(115.0) * Rd * 0.74, Vector3(0.007, Rd * 0.2, 0.003), Basis(nrm.cross(at_angle.call(115.0)), at_angle.call(115.0), nrm))
	# the needle at the scale's start; it turns clockwise (about -normal) by 270 degrees from 0 to 1
	var nd = g.move("needle", t * c, t.basis * -nrm, "rotate", PI * 1.5)
	nd.xf = t
	nd.use("needle", "identify")
	var nd_dir: Vector3 = at_angle.call(-135.0)
	nd.box(front + nrm * 0.004 + nd_dir * Rd * 0.3, Vector3(0.005, Rd * 0.75, 0.002), Basis(nrm.cross(nd_dir), nd_dir, nrm))
	nd.cyl(front + nrm * 0.002, front + nrm * 0.007, Rd * 0.08, -1.0, 8)
	g.plate("dial", t * (c - up_d * (Rd + 0.02)), t.basis * nrm, "small")
	g.axis_line = [t * Vector3.ZERO, t * c]

static func pressure_gauge(_part: String, g) -> void:
	_gauge(g, false)

static func temperature_gauge(_part: String, g) -> void:
	_gauge(g, true)

## A 2" stand pipe from below the instrument down to the floor (part frame), when it stands free.
static func _stand(g, top: Vector3) -> void:
	var dz: float = g.ctx.get("floor_dz", 0.0)
	if dz > -0.3 or dz < -2.4:
		return
	var m = g.m
	var keep: Transform3D = m.xf
	m.xf = Transform3D.IDENTITY
	m.use("galvanised", "form")
	var foot := Vector3(top.x, top.y, dz)
	m.cyl(foot, top, 0.03, -1.0, 8)
	m.box(foot + Vector3(0, 0, 0.005), Vector3(0.2, 0.2, 0.01))
	m.box(top + Vector3(0, 0, -0.02), Vector3(0.08, 0.08, 0.04))
	m.xf = keep

## A pressure (or differential pressure) transmitter: its valve manifold, the sensor and the electronics housing with
## its display; on a stand when it stands free.
static func _transmitter(g, level: bool) -> void:
	var m = g.m
	var t := _local(g, m)
	m.use("steel", "form")
	if level:   # two impulse legs to the vessel (the high and the low tap)
		for k: float in [-1.0, 1.0]:
			m.cyl(Vector3(0, 0.25 * k, -0.02), Vector3(0, 0.25 * k, 0.1), 0.008, -1.0, 6)
			m.cyl(Vector3(0, 0.25 * k, 0.1), Vector3(0, 0.03 * k, 0.1), 0.008, -1.0, 6)
	else:
		m.cyl(Vector3(0, 0, -0.02), Vector3(0, 0, 0.06), 0.008, -1.0, 6)
	m.use("steel", "identify")
	m.box(Vector3(0, 0, 0.08), Vector3(0.09, 0.06, 0.05))           # the manifold
	m.use("paint_red", "detail", 0.02)
	for k: float in [-1.0, 0.0, 1.0]:
		m.cyl(Vector3(0.03 * k, 0.03, 0.08), Vector3(0.03 * k, 0.055, 0.08), 0.006, -1.0, 6)
	m.use("steel", "identify")
	m.box(Vector3(0, 0, 0.125), Vector3(0.09, 0.09, 0.04))          # the coplanar sensor flange
	m.cyl(Vector3(0, 0, 0.145), Vector3(0, 0, 0.19), 0.025, -1.0, 12)
	m.use("paint_motor", "identify")                                   # the housing (makers paint them blue)
	m.cyl(Vector3(-0.06, 0, 0.22), Vector3(0.06, 0, 0.22), 0.05, -1.0, 16)
	m.use("glass", "identify")
	m.disk(Vector3(0.0605, 0, 0.22), Vector3(1, 0, 0), 0.035, 16)  # the display
	m.use("paint_darkgrey", "detail", 0.02)
	m.cyl(Vector3(0, -0.05, 0.22), Vector3(0, -0.08, 0.22), 0.012, -1.0, 6)   # cable gland
	g.plate("body", t * Vector3(-0.065, 0, 0.22), t.basis * Vector3(-1, 0, 0), "small")
	g.axis_line = [t * Vector3.ZERO, t * Vector3(0, 0, 0.25)]
	_stand(g, t * Vector3(0, -0.06, 0.15))

static func pressure_transmitter(_part: String, g) -> void:
	_transmitter(g, false)

static func level_transmitter(_part: String, g) -> void:
	_transmitter(g, true)

## A thermocouple or resistance thermometer: the thermowell into the pipe or casing, its extension and the
## connection head (aluminium, a domed cap, a cable gland).
static func temperature_element(_part: String, g) -> void:
	var m = g.m
	var t := _local(g, m)
	m.use("steel", "identify")
	m.cyl(Vector3(0, 0, -0.06), Vector3(0, 0, 0.0), 0.013, -1.0, 8)
	m.cyl(Vector3(0, 0, 0.0), Vector3(0, 0, 0.012), 0.022, -1.0, 6)   # the well's hex
	m.cyl(Vector3(0, 0, 0.012), Vector3(0, 0, 0.11), 0.008, -1.0, 8)
	m.use("cladding", "identify")
	m.cyl(Vector3(0, 0, 0.11), Vector3(0, 0, 0.16), 0.04, -1.0, 16)
	m.dish(Vector3(0, 0, 0.16), Vector3(0, 0, 1), 0.04, 0.015, 16, 3)
	m.use("paint_darkgrey", "detail", 0.02)
	m.cyl(Vector3(0.035, 0, 0.13), Vector3(0.06, 0, 0.13), 0.01, -1.0, 6)
	g.plate("head", t * Vector3(0, -0.045, 0.13), t.basis * Vector3(0, -1, 0), "small")
	g.axis_line = [t * Vector3.ZERO, t * Vector3(0, 0, 0.17)]

## A level glass: the two isolating valves on their taps and the glass between them, its water column (moving).
static func level_glass(_part: String, g) -> void:
	var m = g.m
	var rng: Array = g.p.get("range", [-500, 500])
	var h := clampf(absf(float(rng[1]) - float(rng[0])) / 1000.0, 0.2, 3.0)
	var out: Vector3 = g.ctx.get("out", Vector3(1, 0, 0))
	out = Vector3(out.x, out.y, 0).normalized() if Vector2(out.x, out.y).length() > 0.1 else Vector3(1, 0, 0)
	var side := Vector3(0, 0, 1).cross(out).normalized()
	var c := out * 0.25
	m.use("steel", "identify")
	for k: float in [-1.0, 1.0]:
		var z := h * 0.5 * k + 0.08 * k
		m.cyl(Vector3(0, 0, z), out * 0.25 + Vector3(0, 0, z), 0.015, -1.0, 8)
		m.box(out * 0.2 + Vector3(0, 0, z), Vector3(0.06, 0.06, 0.06))
		m.use("paint_red", "identify")
		m.cyl(out * 0.2 + Vector3(0, 0, z) + side * 0.03, out * 0.2 + Vector3(0, 0, z) + side * 0.08, 0.006, -1.0, 6)
		m.use("steel", "identify")
	# the frame and the glass
	var bg := Basis(side, out, Vector3(0, 0, 1))
	m.box(c, Vector3(0.09, 0.05, h + 0.1), bg)
	m.use("glass", "identify")
	m.box(c + out * 0.026, Vector3(0.04, 0.002, h), bg)
	var lv = g.move("level", c + out * 0.028 - Vector3(0, 0, h * 0.5), Vector3(0, 0, 1), "scale", 1.0)
	lv.use("water", "identify")
	lv.box(c + out * 0.031, Vector3(0.03, 0.002, h), bg)
	g.plate("body", c + out * 0.03 + Vector3(0, 0, h * 0.5 + 0.12), out, "small")
	g.axis_line = [Vector3.ZERO, c]

## A flow element in the pipe: an orifice plate between its flanges (its tab sticks out), a venturi or a magnetic
## flow meter with its converter; the DP transmitter on top for the first two.
static func flow_element(_part: String, g) -> void:
	var m = g.m
	var od: float = g.ctx.get("pipe_od", 0.22)
	var kind: String = g.p.get("kind", "orifice")
	var r := od * 0.5
	match kind:
		"orifice":
			C.flange_pair(m, Vector3.ZERO, Vector3(0, 1, 0), od, "steel")
			m.use("steel", "identify")
			m.box(Vector3(0, 0, C.flange_dims(od).df * 0.5 + 0.05), Vector3(0.05, 0.006, 0.12))   # the plate's tab
		"venturi":
			m.use("paint_darkgrey", "identify")
			m.lathe(Vector3(0, -od * 1.5, 0), Vector3(0, 1, 0), [[r * 1.02, 0.0], [r * 0.6, od * 1.0], [r * 0.6, od * 1.3], [r * 1.02, od * 3.0]], 0, false)
			C.flange(m, Vector3(0, -od * 1.5, 0), Vector3(0, -1, 0), od, "paint_darkgrey")
			C.flange(m, Vector3(0, od * 1.5, 0), Vector3(0, 1, 0), od, "paint_darkgrey")
		_:
			m.use("paint_motor", "identify")
			m.cyl(Vector3(0, -od * 0.6, 0), Vector3(0, od * 0.6, 0), r * 1.12)
			C.flange(m, Vector3(0, -od * 0.6, 0), Vector3(0, -1, 0), od, "paint_motor")
			C.flange(m, Vector3(0, od * 0.6, 0), Vector3(0, 1, 0), od, "paint_motor")
			m.use("paint_motor", "identify")
			m.cyl(Vector3(0, 0, r * 1.1), Vector3(0, 0, r * 1.1 + 0.15), 0.04, -1.0, 12)
			m.box(Vector3(0, 0, r * 1.1 + 0.25), Vector3(0.2, 0.15, 0.2))
			m.use("glass", "identify")
			m.disk(Vector3(0, -0.0751, r * 1.1 + 0.27), Vector3(0, -1, 0), 0.05, 16)
			g.plate("body", Vector3(r * 1.13, 0, 0), Vector3(1, 0, 0), "small")
			g.axis_line = [Vector3(0, -od, 0), Vector3(0, od, 0)]
			return
	# the DP transmitter over the taps
	var top: float = C.flange_dims(od).df * 0.5
	m.use("steel", "detail", 0.02)
	for k: float in [-1.0, 1.0]:
		m.cyl(Vector3(0.0, 0.03 * k, top), Vector3(0.0, 0.03 * k, top + 0.25), 0.007, -1.0, 6)
	m.use("paint_motor", "identify")
	m.box(Vector3(0, 0, top + 0.3), Vector3(0.09, 0.09, 0.07))
	m.cyl(Vector3(-0.06, 0, top + 0.4), Vector3(0.06, 0, top + 0.4), 0.05, -1.0, 16)
	g.plate("body", Vector3(0, -0.06, top + 0.3), Vector3(0, -1, 0), "small")
	g.axis_line = [Vector3(0, -od, 0), Vector3(0, od, 0)]

## A limit switch: its box and roller lever.
static func position_switch(_part: String, g) -> void:
	var m = g.m
	var t := _local(g, m)
	m.use("paint_darkgrey", "form")
	m.box(Vector3(0, 0, 0.03), Vector3(0.08, 0.05, 0.06))
	m.use("paint_yellow", "identify")
	m.box(Vector3(0, 0, 0.09), Vector3(0.07, 0.05, 0.06))
	m.use("steel", "identify")
	m.box(Vector3(0.05, 0, 0.11), Vector3(0.06, 0.008, 0.008))
	m.cyl(Vector3(0.08, -0.01, 0.11), Vector3(0.08, 0.01, 0.11), 0.012, -1.0, 8)
	g.plate("body", t * Vector3(0, -0.03, 0.06), t.basis * Vector3(0, -1, 0), "small")

## A vibration probe on a bearing: proximity probes in a holder with a cable conduit; velocity sensors a
## cylindrical body on a stud.
static func vibration_probe(_part: String, g) -> void:
	var m = g.m
	var t := _local(g, m)
	if g.p.get("kind", "proximity") == "velocity":
		m.use("steel", "identify")
		m.cyl(Vector3(0, 0, 0), Vector3(0, 0, 0.012), 0.02, -1.0, 6)
		m.cyl(Vector3(0, 0, 0.012), Vector3(0, 0, 0.09), 0.019, -1.0, 12)
		m.use("rubber", "identify")
		m.cyl(Vector3(0, 0, 0.09), Vector3(0, 0, 0.12), 0.011, -1.0, 8)
	else:
		m.use("steel", "identify")
		m.box(Vector3(0, 0, 0.03), Vector3(0.06, 0.06, 0.06))
		m.cyl(Vector3(0, 0, 0.06), Vector3(0, 0, 0.12), 0.014, -1.0, 8)
		m.use("paint_yellow", "identify")   # the probe's holder cap (the colour the eye finds on a bearing)
		m.cyl(Vector3(0, 0, 0.12), Vector3(0, 0, 0.14), 0.02, -1.0, 8)
	m.use("galvanised", "detail", 0.02)
	m.cyl(Vector3(0, 0, 0.1), Vector3(0, -0.25, 0.1), 0.009, -1.0, 6)   # the cable's conduit
	g.plate("body", t * Vector3(0.03, 0, 0.05), t.basis * Vector3(1, 0, 0), "small")

## A speed pickup: a threaded probe in its bracket over the toothed wheel, with its cable.
static func speed_probe(_part: String, g) -> void:
	var m = g.m
	var t := _local(g, m)
	m.use("paint_darkgrey", "form")
	m.box(Vector3(0, 0, 0.015), Vector3(0.1, 0.06, 0.03))
	m.use("steel", "identify")
	m.cyl(Vector3(0, 0, -0.03), Vector3(0, 0, 0.1), 0.009, -1.0, 8)
	m.cyl(Vector3(0, 0, 0.03), Vector3(0, 0, 0.042), 0.015, -1.0, 6)
	m.use("rubber", "detail", 0.02)
	m.cyl(Vector3(0, 0, 0.1), Vector3(0, -0.2, 0.15), 0.006, -1.0, 6)
	g.plate("body", t * Vector3(0, -0.035, 0.015), t.basis * Vector3(0, -1, 0), "small")

## A flame detector: an angled sight tube with its lens and the electronics head.
static func flame_detector(_part: String, g) -> void:
	var m = g.m
	var t := _local(g, m)
	m.use("steel", "form")
	m.cyl(Vector3(0, 0, 0), Vector3(0, 0, 0.12), 0.025, -1.0, 10)
	m.use("paint_red", "identify")
	m.cyl(Vector3(0, 0, 0.12), Vector3(0, 0, 0.24), 0.045, -1.0, 16)
	m.use("glass", "identify")
	m.disk(Vector3(0, 0, 0.241), Vector3(0, 0, 1), 0.03, 16)
	g.plate("body", t * Vector3(0.05, 0, 0.18), t.basis * Vector3(1, 0, 0), "small")

## A local control panel: a cabinet on a frame with its display, lamps, buttons and the door's handle.
static func local_panel(_part: String, g) -> void:
	var m = g.m
	var W: float = g.num("width", 0.8)
	var H: float = g.num("height", 1.8)
	var D := clampf(W * 0.35, 0.25, 0.6)
	var z0 := 0.3 if H < 1.5 else 0.1
	m.use("galvanised", "form")
	for k: float in [-1.0, 1.0]:
		m.box_lh(Vector3(W * 0.5 * k - 0.03, -D * 0.5, 0), Vector3(W * 0.5 * k + 0.03, D * 0.5, z0))
	m.use("paint_grey", "identify")
	m.box_lh(Vector3(-W * 0.5, -D * 0.5, z0), Vector3(W * 0.5, D * 0.5, z0 + H))
	m.use("paint_darkgrey", "form")
	m.box(Vector3(0, D * 0.5, z0 + H * 0.5), Vector3(0.006, 0.006, H * 0.98))   # the door's seam
	m.box(Vector3(W * 0.4, D * 0.5 + 0.015, z0 + H * 0.5), Vector3(0.02, 0.03, 0.15))
	m.use("glass", "identify")
	m.box(Vector3(-W * 0.1, D * 0.5 + 0.003, z0 + H * 0.75), Vector3(W * 0.5, 0.006, H * 0.15))
	var cols := ["lamp_green", "lamp_red", "lamp_amber"]
	for i in 3:
		m.use(cols[i], "identify")
		m.cyl(Vector3(-W * 0.3 + W * 0.2 * i, D * 0.5, z0 + H * 0.55), Vector3(-W * 0.3 + W * 0.2 * i, D * 0.5 + 0.02, z0 + H * 0.55), 0.018, -1.0, 10)
	for i in 3:
		m.use(["paint_green", "paint_red", "paint_black"][i], "identify")
		m.cyl(Vector3(-W * 0.3 + W * 0.2 * i, D * 0.5, z0 + H * 0.45), Vector3(-W * 0.3 + W * 0.2 * i, D * 0.5 + 0.025, z0 + H * 0.45), 0.022, -1.0, 10)
	g.plate("front", Vector3(0, D * 0.5 + 0.003, z0 + H * 0.92), Vector3(0, 1, 0), "small")
	g.solid_box(Vector3(-W * 0.5, -D * 0.5, 0), Vector3(W * 0.5, D * 0.5, z0 + H))

## An operator desk of the control room (PLANT3D.md §7.11): a worktop on its pedestals and modesty panel, a row of
## `screens` monitors on their feet at the back, a keyboard before each; the operator stands at the front (+y).
static func operator_desk(_part: String, g) -> void:
	var m = g.m
	var W: float = g.num("width", 3.2)
	var n := int(g.p.get("screens", 4))
	var D := 1.0
	m.use("paint_darkgrey", "form")
	m.box_lh(Vector3(-W * 0.5, -D * 0.5, 0), Vector3(-W * 0.5 + 0.04, D * 0.5 - 0.1, 0.72))    # the pedestals
	m.box_lh(Vector3(W * 0.5 - 0.04, -D * 0.5, 0), Vector3(W * 0.5, D * 0.5 - 0.1, 0.72))
	m.box_lh(Vector3(-W * 0.5, -D * 0.5, 0.1), Vector3(W * 0.5, -D * 0.5 + 0.03, 0.72))      # the modesty panel
	m.use("paint_grey", "identify")
	m.box_lh(Vector3(-W * 0.5, -D * 0.5, 0.72), Vector3(W * 0.5, D * 0.5, 0.76))              # the worktop
	var cell := (W - 0.1) / float(n)
	var sw := cell - 0.04
	for i in n:
		var x := -W * 0.5 + 0.05 + cell * (i + 0.5)
		m.use("paint_black", "form")
		m.box(Vector3(x, -D * 0.5 + 0.2, 0.84), Vector3(0.06, 0.06, 0.16))                    # the foot's post
		m.box(Vector3(x, -D * 0.5 + 0.2, 0.765), Vector3(0.25, 0.18, 0.01))                   # and its base
		m.box(Vector3(x, -D * 0.5 + 0.24, 1.12), Vector3(sw, 0.04, sw * 0.6))                # the bezel
		m.use("glass", "identify")
		m.box(Vector3(x, -D * 0.5 + 0.262, 1.12), Vector3(sw - 0.03, 0.004, sw * 0.6 - 0.03))   # the screen
		m.use("paint_black", "form")
		m.box(Vector3(x, D * 0.5 - 0.3, 0.77), Vector3(minf(0.44, sw * 0.8), 0.15, 0.02))     # the keyboard
	g.plate("front", Vector3(0, D * 0.5 + 0.003, 0.6), Vector3(0, 1, 0), "small")
	g.solid_box(Vector3(-W * 0.5, -D * 0.5, 0), Vector3(W * 0.5, D * 0.5, 0.76))

## A push button station on its post: start (green), stop (red), and an emergency stop (a red mushroom on yellow).
static func push_button_station(_part: String, g) -> void:
	var m = g.m
	var em: bool = g.p.get("buttons", "start_stop") == "start_stop_emergency"
	var h := 0.32 if em else 0.22
	m.use("galvanised", "form")
	m.cyl(Vector3(0, -0.06, 0), Vector3(0, -0.06, 1.25), 0.03, -1.0, 8)
	m.box(Vector3(0, -0.06, 0.005), Vector3(0.2, 0.2, 0.01))
	m.use("paint_grey", "identify")
	m.box(Vector3(0, 0, 1.25), Vector3(0.12, 0.09, h))
	m.use("paint_green", "identify")
	m.cyl(Vector3(0, 0.045, 1.25 + h * 0.25), Vector3(0, 0.065, 1.25 + h * 0.25), 0.02, -1.0, 12)
	m.use("paint_red", "identify")
	m.cyl(Vector3(0, 0.045, 1.25 + h * (0.0 if em else -0.25)), Vector3(0, 0.065, 1.25 + h * (0.0 if em else -0.25)), 0.02, -1.0, 12)
	if em:
		m.use("paint_yellow", "identify")
		m.box(Vector3(0, 0.046, 1.25 - h * 0.3), Vector3(0.1, 0.002, 0.09))
		m.use("paint_red", "identify")
		m.cyl(Vector3(0, 0.046, 1.25 - h * 0.3), Vector3(0, 0.07, 1.25 - h * 0.3), 0.012, -1.0, 8)
		m.dish(Vector3(0, 0.07, 1.25 - h * 0.3), Vector3(0, 1, 0), 0.032, 0.015, 16, 3)
	g.plate("front", Vector3(0, 0.046, 1.25 + h * 0.5 + 0.03), Vector3(0, 1, 0), "small")

# ------------------------------------------------------------------ people cues

## A tag plate as a part of its own (the builder puts plates on equipment itself: kit/README.md "Tag plates").
static func tag_plate(_part: String, g) -> void:
	var m = g.m
	var big: bool = g.p.get("kind", "small") == "large"
	var s := Vector3(0.6, 0.004, 0.15) if big else Vector3(0.16, 0.002, 0.04)
	m.use("plate", "identify")
	m.box(Vector3(0, 0, s.z * 0.5), s)

static func sign(_part: String, g) -> void:
	var m = g.m
	var sz: float = g.num("size", 0.3)
	m.use("galvanised", "form")
	m.cyl(Vector3(0, -0.03, 0), Vector3(0, -0.03, 1.6 + sz), 0.025, -1.0, 8)
	m.use("sign_green", "identify")
	m.box(Vector3(0, 0, 1.6 + sz * 0.5), Vector3(sz * 3.0, 0.01, sz))
	g.plate("front", Vector3(0, 0.006, 1.6 + sz * 0.5), Vector3(0, 1, 0), "large")

## A light fitting: the lens in `light` (lit: its child `on`).
static func _light(g, c: Vector3, r: float, colour: String) -> void:
	var lt = g.move("light", c, Vector3(0, 0, 1), "lamp", 0.0)
	lt.use("lamp_off", "identify")
	lt.cyl(c - Vector3(0, 0, r), c + Vector3(0, 0, r), r, -1.0, 16)
	var on = g.move("light/on", c, Vector3(0, 0, 1), "lamp", 0.0)
	on.use("lamp_" + colour, "identify")
	on.cyl(c - Vector3(0, 0, r * 1.02), c + Vector3(0, 0, r * 1.02), r * 1.02, -1.0, 16)

static func lamp(_part: String, g) -> void:
	var m = g.m
	m.use("paint_darkgrey", "form")
	m.box(Vector3(0, -0.05, 0.0), Vector3(0.1, 0.02, 0.15))
	m.cyl(Vector3(0, -0.04, 0.0), Vector3(0, 0.05, 0.0), 0.04, -1.0, 12)
	_light(g, Vector3(0, 0.05, -0.06), 0.05, g.p.get("colour", "white"))

static func beacon(_part: String, g) -> void:
	var m = g.m
	m.use("paint_darkgrey", "form")
	m.cyl(Vector3(0, 0, 0), Vector3(0, 0, 0.06), 0.07, -1.0, 16)
	_light(g, Vector3(0, 0, 0.14), 0.065, g.p.get("colour", "amber"))

static func horn(_part: String, g) -> void:
	var m = g.m
	m.use("paint_grey", "identify")
	m.box(Vector3(0, -0.03, 0.0), Vector3(0.12, 0.06, 0.12))
	m.lathe(Vector3(0, 0, 0), Vector3(0, 1, 0), [[0.03, 0.0], [0.05, 0.12], [0.11, 0.2]], 20, false)

static func emergency_stop(_part: String, g) -> void:
	var m = g.m
	m.use("galvanised", "form")
	m.cyl(Vector3(0, -0.05, 0), Vector3(0, -0.05, 1.3), 0.03, -1.0, 8)
	m.use("paint_yellow", "identify")
	m.box(Vector3(0, 0, 1.3), Vector3(0.12, 0.08, 0.12))
	m.use("paint_red", "identify")
	m.cyl(Vector3(0, 0.04, 1.3), Vector3(0, 0.06, 1.3), 0.015, -1.0, 8)
	m.dish(Vector3(0, 0.06, 1.3), Vector3(0, 1, 0), 0.04, 0.02, 16, 3)
	g.plate("front", Vector3(0, 0.041, 1.38), Vector3(0, 1, 0), "small")

static func safety_shower(_part: String, g) -> void:
	var m = g.m
	m.use("paint_yellow", "identify")
	m.pipe_path([Vector3(0, 0, 0), Vector3(0, 0, 2.3), Vector3(0, 0.6, 2.3)], 0.025, 0.08)
	m.lathe(Vector3(0, 0.6, 2.3), Vector3(0, 0, -1), [[0.02, 0.0], [0.15, 0.08], [0.15, 0.09]], 16, false)
	m.pipe_path([Vector3(0, 0, 1.0), Vector3(0, 0.35, 1.0)], 0.02, 0.06)
	m.use("chrome", "identify")
	m.lathe(Vector3(0, 0.45, 0.95), Vector3(0, 0, 1), [[0.03, 0.0], [0.15, 0.08]], 16, false)
	m.use("sign_green", "identify")
	m.box(Vector3(0, -0.04, 2.0), Vector3(0.3, 0.01, 0.3))
	m.use("galvanised", "form")
	m.box(Vector3(0, 0, 0.01), Vector3(0.3, 0.3, 0.02))
