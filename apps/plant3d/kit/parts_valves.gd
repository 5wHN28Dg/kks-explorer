## Valves and dampers (docs/PLANT3D.md §9 "Valves"). Inline: the origin is on the pipe's centre line, y along the
## flow, z up (a valve on a vertical pipe is turned by the builder: its z then lies across the pipe). What tells a
## trainee the type and the state is `identify` and drawn on every tier (R9a): the body's shape, the bonnet and yoke,
## the handwheel (red), the rising stem (how far it stands out shows how far the valve is open), the actuator, a
## butterfly's or ball valve's position indicator, a check valve's lever and weight.
##
## Moving nodes (kit/README.md "Moving parts"):
##   stem       translate along +z (the bonnet's axis): 0 closed, 1 open; travel = the stroke in metres
##   handwheel  rotate about its own axis (z for a wheel on top, x for one on the side); travel 0 (turns freely)
##   disc       rotate about z (butterfly, ball: the position indicator or lever turns with it; 0 closed, 1 open,
##              travel PI/2) or about x through the hinge (check: 0 closed, 1 fully open, travel 1.2 rad)
##   blades     (damper) a node holding blade_0 … blade_n, each rotates about its own x axis, travel PI/2
extends RefCounted

const C = preload("res://kit/parts_common.gd")

## Face-to-face length per type, from the outside diameter (EN 558 basic series, rounded: README "Tables").
static func ftf(part: String, od: float) -> float:
	match part:
		"valve_gate": return maxf(0.15, 1.1 * od + 0.1)
		"valve_globe", "valve_control": return maxf(0.18, 1.9 * od + 0.12)
		"valve_ball": return maxf(0.14, 1.15 * od + 0.06)
		"valve_check": return maxf(0.18, 1.9 * od + 0.1)
		"valve_butterfly": return maxf(0.05, 0.25 * od + 0.06)
		"valve_safety": return maxf(0.12, 1.2 * od + 0.08)
	return od

## The stroke of a rising stem (gate: about the bore; globe and control: a quarter of it).
static func stroke(part: String, od: float) -> float:
	if part == "valve_gate":
		return clampf(od * 0.9, 0.03, 1.6)
	return clampf(od * 0.25 + 0.01, 0.015, 0.4)

## The handwheel's radius for a manual valve of outside diameter od (makers' tables: ~160 mm wheel for DN 50,
## ~400–600 mm for DN 300; README "Tables").
static func wheel_r(od: float) -> float:
	return clampf(0.06 + od * 0.75, 0.07, 0.40)

static func valve_gate(_part: String, g) -> void:
	_rising(g, "valve_gate")

static func valve_globe(_part: String, g) -> void:
	_rising(g, "valve_globe")

static func valve_control(_part: String, g) -> void:
	_rising(g, "valve_control")

## The body between two flanges: a lathe along y. `bulge` is its widest radius as a share of od.
static func _body(g, part: String, od: float, F: float, bulge: float) -> void:
	var m = g.m
	var r := od * 0.5
	var rating: String = g.p.get("rating", "pn16")
	m.use("paint_darkgrey", "identify")
	var prof := [[r * 1.02, -F * 0.5], [r * 1.05, -F * 0.38], [r * bulge, -F * 0.18], [r * bulge, F * 0.18],
		[r * 1.05, F * 0.38], [r * 1.02, F * 0.5]]
	var pr: Array = []
	for q in prof:
		pr.append(q)
	m.lathe(Vector3.ZERO, Vector3(0, 1, 0), pr, 0, false)
	C.flange(m, Vector3(0, -F * 0.5, 0), Vector3(0, -1, 0), od, "paint_darkgrey", rating)
	C.flange(m, Vector3(0, F * 0.5, 0), Vector3(0, 1, 0), od, "paint_darkgrey", rating)
	g.plate("body", Vector3(r * bulge + 0.01, 0, 0), Vector3(1, 0, 0), "small")
	g.solid_box(Vector3(-r * bulge, -F * 0.5, -r * bulge), Vector3(r * bulge, F * 0.5, r * bulge))

## Gate, globe and control valves: body, bonnet, yoke, rising stem, and the handwheel or actuator on top.
static func _rising(g, part: String) -> void:
	var m = g.m
	var od: float = g.od(g.num("dn", 100))
	var r := od * 0.5
	var F := ftf(part, od)
	var act: String = g.p.get("actuator", "manual" if part != "valve_control" else "pneumatic")
	var side: String = g.p.get("handwheel", "top")
	var bulge := 1.25 if part == "valve_gate" else 1.55
	_body(g, part, od, F, bulge)
	# the neck and bonnet flange
	m.use("paint_darkgrey", "identify")
	var zb := r * (1.15 if part == "valve_gate" else 1.35)
	m.cyl(Vector3(0, 0, r * 0.4), Vector3(0, 0, zb), r * 0.62 if part == "valve_gate" else r * 0.7, -1.0)
	var bf := od * 0.42 + 0.02
	m.cyl(Vector3(0, 0, zb), Vector3(0, 0, zb + 0.02 + od * 0.06), bf, -1.0)
	C.bolt_ring(m, Vector3(0, 0, zb + 0.01 + od * 0.03), Vector3(0, 0, 1), bf * 0.85, 8 if od < 0.3 else 12, clampf(0.006 + od * 0.01, 0.006, 0.02), od * 0.1 + 0.04)
	var zt := zb + 0.02 + od * 0.06
	var s := stroke(part, od)
	# bonnet: a gate valve's is tall (it houses the wedge's travel)
	var hb := (s + od * 0.25 + 0.05) if part == "valve_gate" else (od * 0.35 + 0.06)
	m.use("paint_darkgrey", "identify")
	m.cyl(Vector3(0, 0, zt), Vector3(0, 0, zt + hb), r * 0.36 + 0.015, r * 0.28 + 0.012)
	var zg := zt + hb   # the gland: the stem comes out here
	m.use("brass", "form")
	m.cyl(Vector3(0, 0, zg), Vector3(0, 0, zg + 0.03), r * 0.18 + 0.012, -1.0, 12)
	# the yoke: two arms from the bonnet up to the yoke head
	var yh := s + 0.08 + od * 0.15
	var zy := zg + yh
	var yw := r * 0.45 + 0.03
	m.use("paint_darkgrey", "identify")
	for k: float in [-1.0, 1.0]:
		m.box_lh(Vector3(yw * k - 0.012 - od * 0.015, -0.012 - od * 0.04, zg), Vector3(yw * k + 0.012 + od * 0.015, 0.012 + od * 0.04, zy))
	m.box_lh(Vector3(-yw - 0.02, -0.025 - od * 0.05, zy), Vector3(yw + 0.02, 0.025 + od * 0.05, zy + 0.03 + od * 0.04))
	var ztop := zy + 0.03 + od * 0.04
	# the stem (moves): from inside the bonnet up through the yoke; its top shows the position
	var stem_r := clampf(0.006 + od * 0.04, 0.007, 0.06)
	var sm = g.move("stem", Vector3(0, 0, zg), Vector3(0, 0, 1), "translate", s)
	sm.use("chrome", "identify")
	var top_extra := 0.04 + od * 0.05
	sm.cyl(Vector3(0, 0, zg - s), Vector3(0, 0, ztop + top_extra), stem_r, -1.0, 10)
	if act != "manual" or part == "valve_control":
		# a coupling block in the yoke window and the travel pointer against a scale on the yoke (control valves)
		sm.use("steel", "identify")
		sm.box(Vector3(0, 0, zg + 0.04 + od * 0.03), Vector3(stem_r * 4, stem_r * 3, 0.03 + od * 0.04))
		sm.use("paint_red", "identify")
		sm.box(Vector3(yw * 0.6, 0, zg + 0.04 + od * 0.03), Vector3(yw * 0.8, 0.006, 0.008))
		m.use("plate", "identify")
		m.box(Vector3(yw + 0.012 + od * 0.015, 0.0, zg + 0.04 + od * 0.03 + s * 0.5), Vector3(0.004, 0.03, s + 0.02))
	var wr := wheel_r(od)
	match act:
		"manual":
			_wheel(g, Vector3(0, 0, ztop + 0.02), side, wr)
		"gear":
			_gearbox(g, ztop, od, side, wr)
		"electric":
			_motor_actuator(g, ztop, od, side)
		"pneumatic":
			if part == "valve_control":
				_diaphragm(g, ztop, od, side)
			else:
				_cylinder_actuator(g, ztop, od, false)
		"hydraulic":
			_cylinder_actuator(g, ztop, od, true)
	_no_wheel(g, ztop)
	g.axis_line = [Vector3(0, -F, 0), Vector3(0, F, 0)]

## Every valve kit.json gives a handwheel channel has a `handwheel` node; where the actuator carries no wheel (a
## lever, a cylinder) it is empty, so a binding to it still finds it (kit/README.md "Moving parts").
static func _no_wheel(g, z: float) -> void:
	if not g.moving.has("handwheel"):
		g.move("handwheel", Vector3(0, 0, z), Vector3(0, 0, 1), "rotate", 0.0)

## A handwheel on top (axis z) or on the side (axis x, left or right), its own node.
static func _wheel(g, c: Vector3, side: String, R: float) -> void:
	var nrm := Vector3(0, 0, 1)
	if side == "left":
		nrm = Vector3(-1, 0, 0)
	elif side == "right":
		nrm = Vector3(1, 0, 0)
	var hw = g.move("handwheel", c, nrm, "rotate", 0.0)
	hw.use("paint_red", "identify")
	hw.handwheel(c, nrm, R)

## A bevel gearbox on the yoke with its handwheel on the side.
static func _gearbox(g, z: float, od: float, side: String, wr: float) -> void:
	var m = g.m
	var s := 0.12 + od * 0.35
	m.use("paint_darkgrey", "identify")
	m.box(Vector3(0, 0, z + s * 0.5), Vector3(s, s * 0.8, s))
	var sx := -1.0 if side == "left" else 1.0
	m.cyl(Vector3(s * 0.5 * sx, 0, z + s * 0.5), Vector3((s * 0.5 + 0.12) * sx, 0, z + s * 0.5), 0.02 + od * 0.02, -1.0, 10)
	_wheel(g, Vector3((s * 0.5 + 0.12) * sx, 0, z + s * 0.5), "left" if sx < 0 else "right", clampf(wr * 0.8, 0.1, 0.35))

## A multi-turn electric actuator: motor, gearbox, local controls, a handwheel on the side.
static func _motor_actuator(g, z: float, od: float, side: String) -> void:
	var m = g.m
	var s := clampf(0.22 + od * 0.35, 0.22, 0.6)
	m.use("paint_motor", "identify")
	m.box(Vector3(0, 0, z + s * 0.45), Vector3(s, s * 0.9, s * 0.9))                       # gearbox
	m.cyl(Vector3(-s * 0.5, -s * 0.05, z + s * 0.55), Vector3(-s * 1.25, -s * 0.05, z + s * 0.55), s * 0.3)   # motor
	m.cyl(Vector3(0, s * 0.45, z + s * 0.6), Vector3(0, s * 0.62, z + s * 0.6), s * 0.28)   # the local controls' cover
	m.use("paint_red", "identify")
	m.cyl(Vector3(-s * 0.08, s * 0.62, z + s * 0.6), Vector3(-s * 0.08, s * 0.67, z + s * 0.6), s * 0.05, -1.0, 10)   # selector knob
	m.use("paint_black", "identify")
	m.cyl(Vector3(s * 0.1, s * 0.62, z + s * 0.6), Vector3(s * 0.1, s * 0.67, z + s * 0.6), s * 0.05, -1.0, 10)
	m.use("glass", "identify")
	m.disk(Vector3(0, s * 0.621, z + s * 0.72), Vector3(0, 1, 0), s * 0.09, 16)               # the display
	var sx := -1.0 if side == "left" else 1.0
	_wheel(g, Vector3((s * 0.5 + 0.06) * sx, 0, z + s * 0.45), "left" if sx < 0 else "right", s * 0.6)
	m.use("steel_dark", "detail", 0.03)
	m.cyl(Vector3(-s * 0.3, -s * 0.45, z + s * 0.2), Vector3(-s * 0.3, -s * 0.6, z + s * 0.2), 0.02, -1.0, 6)   # cable glands
	m.cyl(Vector3(s * 0.1, -s * 0.45, z + s * 0.2), Vector3(s * 0.1, -s * 0.6, z + s * 0.2), 0.02, -1.0, 6)

## A pneumatic (or hydraulic) cylinder actuator on the yoke: barrel, end caps, tie rods.
static func _cylinder_actuator(g, z: float, od: float, hydraulic: bool) -> void:
	var m = g.m
	var rr := clampf(0.07 + od * 0.35, 0.07, 0.4) * (0.7 if hydraulic else 1.0)
	var h := rr * 3.0 + od * 0.5
	m.use("paint_machine" if not hydraulic else "paint_yellow", "identify")
	m.cyl(Vector3(0, 0, z + 0.03), Vector3(0, 0, z + h), rr)
	m.use("paint_darkgrey", "identify")
	m.box(Vector3(0, 0, z + 0.03), Vector3(rr * 2.3, rr * 2.3, 0.05))
	m.box(Vector3(0, 0, z + h), Vector3(rr * 2.3, rr * 2.3, 0.05))
	m.use("steel", "detail", 0.02)
	for k in 4:
		var a := TAU * (k + 0.5) / 4.0
		var p := Vector3(cos(a), sin(a), 0) * rr * 1.35
		m.cyl(p + Vector3(0, 0, z + 0.03), p + Vector3(0, 0, z + h), 0.008 + rr * 0.03, -1.0, 6)
	if hydraulic:
		m.use("brass", "identify")
		m.box(Vector3(rr * 1.4, 0, z + h * 0.5), Vector3(rr * 0.6, rr * 1.0, rr * 1.2))   # the valve block
		m.use("rubber", "detail", 0.02)
		m.cyl(Vector3(rr * 1.7, rr * 0.2, z + h * 0.5), Vector3(rr * 1.7, rr * 0.2, z + h * 0.5 - 0.6), 0.012, -1.0, 6)

## A spring-and-diaphragm actuator (the dome every control valve is known by) with its positioner.
static func _diaphragm(g, z: float, od: float, side: String) -> void:
	var m = g.m
	var R := clampf(0.12 + od * 0.6, 0.13, 0.42)
	var zc := z + 0.06 + R * 0.35
	m.use("paint_machine", "identify")
	m.cyl(Vector3(0, 0, z), Vector3(0, 0, z + 0.06), R * 0.25, -1.0)
	m.lathe(Vector3(0, 0, zc), Vector3(0, 0, 1), [[R * 0.3, -R * 0.35], [R * 0.9, -R * 0.12], [R, 0.0], [R * 0.9, R * 0.15], [R * 0.3, R * 0.42], [0.0, R * 0.45]], 0, true)
	m.use("paint_darkgrey", "form")
	m.cyl(Vector3(0, 0, zc - 0.01), Vector3(0, 0, zc + 0.01), R * 1.04, -1.0)   # the casing's bolted rim
	C.bolt_ring(m, Vector3(0, 0, zc), Vector3(0, 0, 1), R * 0.98, 16, 0.006, 0.04)
	# positioner on the yoke's side, with its gauges and the air tubing
	var sx := -1.0 if side == "left" else 1.0
	var pp := Vector3((R * 0.35 + 0.08) * sx, 0.02, z - 0.08)
	m.use("paint_grey", "identify")
	m.box(pp, Vector3(0.1, 0.14, 0.18))
	m.use("dial", "detail", 0.04)
	for k: float in [-1.0, 1.0]:
		m.cyl(pp + Vector3(0.05 * sx, 0.035 * k, 0.05), pp + Vector3(0.07 * sx, 0.035 * k, 0.05), 0.022, -1.0, 10)
	m.use("chrome", "detail", 0.01)
	m.cyl(pp + Vector3(0, 0, 0.09), Vector3(0, 0, zc + R * 0.43), 0.005, -1.0, 6, false)
	g.plate("actuator", Vector3(0, -R, zc), Vector3(0, -1, 0), "small")

## Butterfly and ball valves: a quarter-turn body; the `disc` node carries the indicator or lever on top.
static func valve_butterfly(part: String, g) -> void:
	_quarter(g, part)

static func valve_ball(part: String, g) -> void:
	_quarter(g, part)

static func _quarter(g, part: String) -> void:
	var m = g.m
	var od: float = g.od(g.num("dn", 100))
	var r := od * 0.5
	var F := ftf(part, od)
	var act: String = g.p.get("actuator", "manual")
	var side: String = g.p.get("handwheel", "top")
	if part == "valve_ball":
		_body(g, part, od, F, 1.45)
	else:
		var rating: String = g.p.get("rating", "pn16")
		m.use("paint_darkgrey", "identify")
		var f := C.flange_dims(od, rating)
		m.cyl(Vector3(0, -F * 0.5, 0), Vector3(0, F * 0.5, 0), f.df * 0.5 * 0.96, -1.0, 0, true)
		C.bolt_ring(m, Vector3(0, 0, 0), Vector3(0, 1, 0), f.pcd, f.n, f.bolt_r, F + 0.06)
		g.plate("body", Vector3(f.df * 0.5, 0, 0), Vector3(1, 0, 0), "small")
		g.solid_box(Vector3(-f.df * 0.5, -F * 0.5, -f.df * 0.5), Vector3(f.df * 0.5, F * 0.5, f.df * 0.5))
	var top: float = r * 1.3 + 0.06 if part == "valve_ball" else C.flange_dims(od).df * 0.5 + 0.02
	m.use("paint_darkgrey", "identify")
	m.cyl(Vector3(0, 0, r * 0.6), Vector3(0, 0, top), clampf(od * 0.12, 0.025, 0.2), -1.0, 12)   # the stem housing
	m.cyl(Vector3(0, 0, top), Vector3(0, 0, top + 0.02), clampf(od * 0.2, 0.04, 0.3), -1.0, 16)
	var disc = g.move("disc", Vector3(0, 0, 0), Vector3(0, 0, 1), "rotate", PI * 0.5)
	if part == "valve_butterfly":   # the disc itself (seen down the pipe's open end, and in the cut-away)
		disc.use("steel", "form")
		disc.cyl(Vector3(0, -0.01 - od * 0.02, 0), Vector3(0, 0.01 + od * 0.02, 0), r * 0.98, -1.0)
	var zt := top + 0.02
	if act == "manual" and od < 0.22:
		# a lever: lies along the pipe when open, across it when closed
		disc.use("paint_red", "identify")
		var L := clampf(0.15 + od * 1.8, 0.15, 0.6)
		disc.box(Vector3(0, -L * 0.45, zt + 0.02), Vector3(0.03, L, 0.015))
		disc.box(Vector3(0, -L * 0.9, zt + 0.02), Vector3(0.04, 0.08, 0.03))
		_no_wheel(g, zt)
		g.axis_line = [Vector3(0, -F, 0), Vector3(0, F, 0)]
		return
	var s := clampf(0.14 + od * 0.25, 0.14, 0.6)
	if act == "manual" or act == "gear":
		m.use("paint_darkgrey", "identify")
		m.box(Vector3(0, 0, zt + s * 0.4), Vector3(s, s * 0.9, s * 0.8))
		var sx := -1.0 if side == "left" else 1.0
		m.cyl(Vector3(s * 0.5 * sx, 0, zt + s * 0.4), Vector3((s * 0.5 + 0.1) * sx, 0, zt + s * 0.4), 0.025, -1.0, 10)
		_wheel(g, Vector3((s * 0.5 + 0.1) * sx, 0, zt + s * 0.4), "left" if sx < 0 else "right", clampf(wheel_r(od) * 0.7, 0.1, 0.35))
		zt += s * 0.8
	elif act == "electric":
		m.use("paint_motor", "identify")
		m.box(Vector3(0, 0, zt + s * 0.45), Vector3(s, s, s * 0.9))
		m.cyl(Vector3(-s * 0.5, 0, zt + s * 0.5), Vector3(-s * 1.15, 0, zt + s * 0.5), s * 0.28)
		var sx := -1.0 if side == "left" else 1.0
		_wheel(g, Vector3((s * 0.5 + 0.05) * sx, 0, zt + s * 0.45), "left" if sx < 0 else "right", s * 0.55)
		zt += s * 0.9
	else:   # pneumatic or hydraulic: a rack-and-pinion or scotch-yoke body across the top
		m.use("paint_machine" if act == "pneumatic" else "paint_yellow", "identify")
		m.cyl(Vector3(-s * 1.0, 0, zt + s * 0.35), Vector3(s * 1.0, 0, zt + s * 0.35), s * 0.33)
		m.box(Vector3(0, 0, zt + s * 0.35), Vector3(s * 0.7, s * 0.75, s * 0.7))
		zt += s * 0.7
	# the position indicator on top: an arrow along the disc (the pointer says open along the pipe, closed across)
	disc.use("paint_yellow", "identify")
	var ir := clampf(s * 0.35, 0.05, 0.2)
	disc.cyl(Vector3(0, 0, zt), Vector3(0, 0, zt + ir * 0.5), ir, -1.0, 16)
	disc.use("paint_black", "identify")
	disc.box(Vector3(0, 0, zt + ir * 0.5 + 0.004), Vector3(ir * 0.25, ir * 1.9, 0.008))
	disc.box(Vector3(0, ir * 0.85, zt + ir * 0.5 + 0.004), Vector3(ir * 0.6, ir * 0.25, 0.008))
	_no_wheel(g, zt)
	g.axis_line = [Vector3(0, -F, 0), Vector3(0, F, 0)]

## A swing check valve: body with its bolted cover; the disc's hinge shaft comes out of the body with a lever and a
## weight (they show the disc's position from outside); an arrow on the body shows the flow.
static func valve_check(part: String, g) -> void:
	var m = g.m
	var od: float = g.od(g.num("dn", 100))
	var r := od * 0.5
	var F := ftf(part, od)
	_body(g, part, od, F, 1.4)
	m.use("paint_darkgrey", "identify")
	var cz := r * 1.25
	m.cyl(Vector3(0, -F * 0.12, r * 0.3), Vector3(0, -F * 0.05, cz), r * 0.75, r * 0.6)
	m.cyl(Vector3(0, -F * 0.06, cz), Vector3(0, -F * 0.04, cz + 0.02 + od * 0.05), r * 0.7, -1.0)
	C.bolt_ring(m, Vector3(0, -F * 0.05, cz + 0.01), Vector3(0, 0, 1), r * 0.6, 8, clampf(0.006 + od * 0.01, 0.006, 0.02), 0.04 + od * 0.06)
	# the flow arrow (raised, white) on both sides
	m.use("paint_white", "identify")
	for k: float in [-1.0, 1.0]:
		var x := r * 1.4 * k
		m.box(Vector3(x, -F * 0.05, 0), Vector3(0.006, F * 0.35, r * 0.12))
		m.prism(Vector3(x - 0.003, F * 0.12, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), [Vector2(0, -r * 0.25), Vector2(F * 0.14, 0), Vector2(0, r * 0.25)], 0.006)
	var hinge := Vector3(0, -F * 0.25, r * 0.75)
	var disc = g.move("disc", hinge, Vector3(1, 0, 0), "rotate", 1.2)
	disc.use("steel", "identify")
	var sx := r * 1.4 + 0.02
	disc.cyl(Vector3(sx - 0.03, hinge.y, hinge.z), Vector3(sx + 0.05, hinge.y, hinge.z), 0.012 + od * 0.03, -1.0, 10)
	disc.use("paint_red", "identify")
	var L := clampf(0.12 + od * 0.9, 0.12, 0.8)
	disc.box(Vector3(sx + 0.04, hinge.y + L * 0.5, hinge.z), Vector3(0.02, L, 0.03 + od * 0.03))
	disc.use("paint_darkgrey", "identify")
	disc.box(Vector3(sx + 0.04, hinge.y + L, hinge.z), Vector3(0.05 + od * 0.1, 0.06 + od * 0.12, 0.06 + od * 0.12))
	disc.use("steel", "form")
	disc.cyl(Vector3(0, hinge.y + 0.01, hinge.z - r * 0.75), Vector3(0, hinge.y + 0.03 + od * 0.03, hinge.z - r * 0.75), r * 0.92, -1.0)
	g.axis_line = [Vector3(0, -F, 0), Vector3(0, F, 0)]

## A safety valve on top of its pipe: inlet nozzle up from the pipe, body, side outlet, spring bonnet with its coil,
## cap and lifting lever. `stem` lifts the spindle and lever (0 shut, 1 fully open).
static func valve_safety(part: String, g) -> void:
	var m = g.m
	var od: float = g.od(g.num("dn", 100))
	var r := od * 0.5
	var po: float = g.ctx.get("pipe_od", od * 2.0)
	var rating: String = g.p.get("rating", "pn16")
	var z0 := po * 0.5
	m.use("paint_red", "identify")   # safety valves are red (common practice)
	m.cyl(Vector3(0, 0, 0), Vector3(0, 0, z0 + 0.08 + od * 0.3), r * 1.05, -1.0, 0, false)
	C.flange_pair(m, Vector3(0, 0, z0 + 0.08 + od * 0.3), Vector3(0, 0, 1), od, "paint_red", rating)
	var zb := z0 + 0.1 + od * 0.35
	m.use("paint_red", "identify")
	m.lathe(Vector3(0, 0, zb), Vector3(0, 0, 1), [[r * 1.1, 0.0], [r * 1.5, od * 0.4], [r * 1.3, od * 0.9], [r * 0.9, od * 1.0]], 0, true)
	# the outlet, one size up, to the side
	var oo := od * 1.4
	C.nozzle(m, Vector3(0, 0, zb + od * 0.45), Vector3(r * 1.5 + oo * 0.6, 0, zb + od * 0.45), oo, "paint_red", "pn16")
	# the bonnet: an open spring housing (two columns), the spring between
	var zs := zb + od * 1.0
	var hs := clampf(od * 2.2 + 0.15, 0.2, 1.8)
	m.use("paint_red", "identify")
	m.cyl(Vector3(0, 0, zs), Vector3(0, 0, zs + 0.03), r * 1.2, -1.0)
	m.cyl(Vector3(0, 0, zs + hs), Vector3(0, 0, zs + hs + 0.03), r * 1.0, -1.0)
	for k: float in [-1.0, 1.0]:
		m.box_lh(Vector3(r * 1.0 * k - 0.015, -0.02, zs), Vector3(r * 1.0 * k + 0.015, 0.02, zs + hs))
	m.use("steel_dark", "form")
	var turns := 6
	var sr := r * 0.65
	for t in turns:
		m.torus(Vector3(0, 0, zs + 0.05 + (hs - 0.1) * (t + 0.5) / turns), Vector3(1, 0, 0), Vector3(0, 1, 0), sr, clampf(od * 0.06, 0.005, 0.04), TAU, 16, 6)
	var stem = g.move("stem", Vector3(0, 0, zs + hs), Vector3(0, 0, 1), "translate", clampf(od * 0.25, 0.005, 0.1))
	stem.use("chrome", "identify")
	stem.cyl(Vector3(0, 0, zs), Vector3(0, 0, zs + hs + 0.12 + od * 0.1), clampf(od * 0.06, 0.008, 0.05), -1.0, 10)
	stem.use("paint_red", "identify")
	stem.cyl(Vector3(0, 0, zs + hs + 0.03), Vector3(0, 0, zs + hs + 0.1 + od * 0.1), r * 0.5, r * 0.35)   # the cap
	stem.use("steel", "identify")
	var L := clampf(0.15 + od, 0.15, 0.8)
	stem.box(Vector3(L * 0.45, 0, zs + hs + 0.1 + od * 0.1), Vector3(L, 0.02, 0.02))                       # the lifting lever
	g.plate("body", Vector3(0, -r * 1.5, zb + od * 0.5), Vector3(0, -1, 0), "small")
	g.solid_box(Vector3(-r * 1.5, -r * 1.5, z0), Vector3(r * 1.5 + oo, r * 1.5, zs + hs))
	g.axis_line = [Vector3(0, 0, 0), Vector3(0, 0, zs + hs)]

## A multi-blade damper in a duct: frame, blades (each its own node), the linkage and the actuator on the side.
## Origin at the frame's centre, y through it (the flow), z up.
static func damper(_part: String, g) -> void:
	var m = g.m
	var W: float = g.num("width", 5)
	var H: float = g.num("height", 5)
	var n := int(g.num("blades", 6))
	var D := 0.35 + minf(W, H) * 0.02
	var t := clampf(minf(W, H) * 0.03, 0.08, 0.25)
	m.use("paint_darkgrey", "form")
	m.box(Vector3(0, 0, H * 0.5 + t * 0.5), Vector3(W + 2 * t, D, t))
	m.box(Vector3(0, 0, -H * 0.5 - t * 0.5), Vector3(W + 2 * t, D, t))
	m.box(Vector3(W * 0.5 + t * 0.5, 0, 0), Vector3(t, D, H))
	m.box(Vector3(-W * 0.5 - t * 0.5, 0, 0), Vector3(t, D, H))
	for k: float in [-1.0, 1.0]:   # the duct's companion flanges
		m.box(Vector3(0, D * 0.5 * k, H * 0.5 + t * 1.2), Vector3(W + 4 * t, 0.03, t * 0.6))
		m.box(Vector3(0, D * 0.5 * k, -H * 0.5 - t * 1.2), Vector3(W + 4 * t, 0.03, t * 0.6))
	var bh := H / n
	g.move("blades", Vector3.ZERO, Vector3(1, 0, 0), "group", PI * 0.5)
	for i in n:
		var zc := -H * 0.5 + bh * (i + 0.5)
		var b = g.move("blades/blade_%d" % i, Vector3(0, 0, zc), Vector3(1, 0, 0), "rotate", PI * 0.5)
		b.use("steel", "form")
		b.box(Vector3(0, 0, zc), Vector3(W * 0.98, 0.02 + bh * 0.04, bh * 0.98))
		b.use("steel_dark", "identify")
		b.cyl(Vector3(W * 0.5, 0, zc), Vector3(W * 0.5 + t + 0.08, 0, zc), 0.025, -1.0, 8)
		b.use("paint_yellow", "identify")   # each blade's crank: the linkage shows the blades' angle
		b.box(Vector3(W * 0.5 + t + 0.06, 0, zc + bh * 0.2), Vector3(0.02, 0.04, bh * 0.4))
	m.use("steel", "identify")
	m.box(Vector3(W * 0.5 + t + 0.1, 0.0, 0), Vector3(0.02, 0.05, H * 0.95))   # the linkage bar
	var act: String = g.p.get("actuator", "manual")
	var ac := Vector3(W * 0.5 + t + 0.35, 0, -H * 0.25)
	match act:
		"manual", "gear":
			m.use("paint_darkgrey", "identify")
			m.box(ac, Vector3(0.25, 0.25, 0.25))
			_wheel(g, ac + Vector3(0.2, 0, 0), "right", 0.25)
		"electric":
			m.use("paint_motor", "identify")
			m.box(ac, Vector3(0.35, 0.35, 0.45))
		_:
			m.use("paint_machine" if act == "pneumatic" else "paint_yellow", "identify")
			m.cyl(ac - Vector3(0, 0, 0.4), ac + Vector3(0, 0, 0.4), 0.12)
	g.plate("frame", Vector3(-W * 0.5 - t, -D * 0.5 - 0.01, H * 0.3), Vector3(0, -1, 0), "large")
	g.solid_box(Vector3(-W * 0.5 - t, -D * 0.5, -H * 0.5 - t), Vector3(W * 0.5 + t, D * 0.5, H * 0.5 + t))
	g.axis_line = [Vector3(0, -1, 0), Vector3(0, 1, 0)]
