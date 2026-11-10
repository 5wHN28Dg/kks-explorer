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
## (the Workshop) the control valve's static stand-in: the plant's body, neck, bonnet and diaphragm casing
const VC_STAND := ["body", "bonnet", "lower_casing", "upper_casing"]

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
static func _body(g, part: String, od: float, F: float, bulge: float, cv := {}) -> void:
	var m = g.m
	var r := od * 0.5
	var rating: String = g.p.get("rating", "pn16")
	if not cv.is_empty():
		g.comp("body")
		g.only("plant", cv.stand)
	m.use("paint_valve", "identify")
	var prof := [[r * 1.02, -F * 0.5], [r * 1.05, -F * 0.38], [r * bulge, -F * 0.18], [r * bulge, F * 0.18],
		[r * 1.05, F * 0.38], [r * 1.02, F * 0.5]]
	var pr: Array = []
	for q in prof:
		pr.append(q)
	m.lathe(Vector3.ZERO, Vector3(0, 1, 0), pr, 0, false)
	C.flange(m, Vector3(0, -F * 0.5, 0), Vector3(0, -1, 0), od, "paint_valve", rating)
	C.flange(m, Vector3(0, F * 0.5, 0), Vector3(0, 1, 0), od, "paint_valve", rating)
	if not cv.is_empty():
		_cv_body(g, m, pr, F, od, rating, cv)
		g.only()
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
	# (the Workshop's trees, kit/README.md "The Workshop mode": the pneumatic control valve, the manual gate valve
	# with its handwheel on top, the globe valve with a multi-turn electric actuator)
	var kind := ""
	if g.workshop:
		if part == "valve_control" and act == "pneumatic":
			kind = "control"
		elif part == "valve_gate" and act == "manual" and side == "top":
			kind = "gate"
		elif part == "valve_globe" and act == "electric":
			kind = "globe"
	var tree := kind != ""
	var stand: Array = VC_STAND if kind == "control" else ["body", "bonnet"]
	var zb := r * (1.15 if part == "valve_gate" else 1.35)
	var bf := od * 0.42 + 0.02
	var zt := zb + 0.02 + od * 0.06
	var s := stroke(part, od)
	var hb := (s + od * 0.25 + 0.05) if part == "valve_gate" else (od * 0.35 + 0.06)
	var zg := zt + hb   # the gland: the stem comes out here
	var stem_r := clampf(0.006 + od * 0.04, 0.007, 0.06)
	var cv := {}
	if tree:
		cv = _cv_dims(r, zb, bf, zt, zg, stem_r, s, kind)
		cv["stand"] = stand
		match kind:
			"control": _cv_comps(g, cv, od)
			"gate": _gv_comps(g, cv, od)
			"globe": _gl_comps(g, cv, od)
	_body(g, part, od, F, bulge, cv)
	# the neck and bonnet flange
	if tree:
		g.comp("body")
		g.only("plant", stand)
	m.use("paint_valve", "identify")
	m.cyl(Vector3(0, 0, r * 0.4), Vector3(0, 0, zb), r * 0.62 if part == "valve_gate" else r * 0.7, -1.0)
	if tree:
		g.comp("bonnet")
	m.cyl(Vector3(0, 0, zb), Vector3(0, 0, zb + 0.02 + od * 0.06), bf, -1.0)
	if tree:
		g.only("plant", ["bonnet_bolts"])
	C.bolt_ring(m, Vector3(0, 0, zb + 0.01 + od * 0.03), Vector3(0, 0, 1), bf * 0.85, 8 if od < 0.3 else 12, clampf(0.006 + od * 0.01, 0.006, 0.02), od * 0.1 + 0.04)
	if tree:
		g.only()
		if g.workshop:   # the bonnet's studs and nuts, where the plant draws its ring: they back out upwards
			_ring_bolts_z(g, "bonnet_bolts", Vector3(0, 0, zb + 0.01 + od * 0.03), bf * 0.85, 8 if od < 0.3 else 12,
				clampf(0.006 + od * 0.01, 0.006, 0.02), od * 0.1 + 0.04)
		g.only("plant", stand)
	# bonnet: a gate valve's is tall (it houses the wedge's travel)
	m.use("paint_valve", "identify")
	m.cyl(Vector3(0, 0, zt), Vector3(0, 0, zt + hb), r * 0.36 + 0.015, r * 0.28 + 0.012)
	if tree:
		_cv_bonnet(g, m, cv, r)
		g.comp("packing")
	m.use("brass", "form")
	m.cyl(Vector3(0, 0, zg), Vector3(0, 0, zg + 0.03), r * 0.18 + 0.012, -1.0, 12)
	if tree:
		_cv_packing(g, m, cv)
		g.comp("yoke" if kind == "control" else "bonnet")   # (the gate's and the globe's yoke is the bonnet's own)
	# the yoke: two arms from the bonnet up to the yoke head
	var yh := s + 0.08 + od * 0.15
	var zy := zg + yh
	var yw := r * 0.45 + 0.03
	m.use("paint_valve", "identify")
	for k: float in [-1.0, 1.0]:
		m.box_lh(Vector3(yw * k - 0.012 - od * 0.015, -0.012 - od * 0.04, zg), Vector3(yw * k + 0.012 + od * 0.015, 0.012 + od * 0.04, zy))
	m.box_lh(Vector3(-yw - 0.02, -0.025 - od * 0.05, zy), Vector3(yw + 0.02, 0.025 + od * 0.05, zy + 0.03 + od * 0.04))
	var ztop := zy + 0.03 + od * 0.04
	# the stem (moves): from inside the bonnet up through the yoke; its top shows the position
	var top_extra := 0.04 + od * 0.05
	if kind == "control":
		g.comp("plug_stem")
		g.only("plant", ["plug_stem", "actuator_stem"])
	elif tree:   # the gate's and the globe's stem is the plant's, whole
		g.comp("stem")
	var sm = g.move("stem", Vector3(0, 0, zg), Vector3(0, 0, 1), "translate", s)
	sm.use("chrome", "identify")
	sm.cyl(Vector3(0, 0, zg - s), Vector3(0, 0, ztop + top_extra), stem_r, -1.0, 10)
	if kind == "control":
		_cv_stems(g, sm, cv, ztop + top_extra)
		g.comp("stem_connector")
		sm.use("chrome", "identify")
	elif tree:
		_gv_stem(g, sm, cv)
		if kind == "globe":
			g.comp("stem_clamp")
		sm.use("chrome", "identify")
	if act != "manual" or part == "valve_control":
		# a coupling block in the yoke window and the travel pointer against a scale on the yoke (control valves)
		sm.use("steel", "identify")
		sm.box(Vector3(0, 0, zg + 0.04 + od * 0.03), Vector3(stem_r * 4, stem_r * 3, 0.03 + od * 0.04))
		sm.use("paint_red", "identify")
		sm.box(Vector3(yw * 0.6, 0, zg + 0.04 + od * 0.03), Vector3(yw * 0.8, 0.006, 0.008))
		if tree:
			g.comp("yoke" if kind == "control" else "bonnet")
		m.use("plate", "identify")
		m.box(Vector3(yw + 0.012 + od * 0.015, 0.0, zg + 0.04 + od * 0.03 + s * 0.5), Vector3(0.004, 0.03, s + 0.02))
	var wr := wheel_r(od)
	match act:
		"manual":
			if tree:
				_gv_stem_nut(g, cv, zy, ztop)
				g.comp("handwheel")
			_wheel(g, Vector3(0, 0, ztop + 0.02), side, wr)
		"gear":
			_gearbox(g, ztop, od, side, wr)
		"electric":
			if tree:
				_gl_stem_nut(g, cv, zy, ztop, od)
				g.comp("actuator")
			_motor_actuator(g, ztop, od, side, tree)
		"pneumatic":
			if part == "valve_control":
				_diaphragm(g, ztop, od, side, cv)
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
	if g.workshop and g.cur_comp == "handwheel":   # (a Workshop tree's) the spokes' open ends closed, inside the hub and the rim
		var ax: Array = hw.across(nrm)
		var t := clampf(R * 0.09, 0.008, 0.035)
		var spokes := 3 if R < 0.2 else (4 if R < 0.35 else 5)
		for i in spokes:
			var a := TAU * i / spokes
			var dir: Vector3 = ax[0] * cos(a) + ax[1] * sin(a)
			var p0: Vector3 = c + dir * t * 2.0
			var p1: Vector3 = c + dir * (R - t * 0.5) - nrm * t * 0.6
			var d := (p1 - p0).normalized()
			g.only("workshop")
			hw.use("paint_red", "identify")
			C._face(hw, p0, d, 0.0, t * 0.55, 6, false)
			g.only("workshop", "outside")   # (its end at the rim shows a little beside the rim's tube)
			hw.use("paint_red", "identify")
			C._face(hw, p1, d, 0.0, t * 0.55, 6, true)
		g.only()

## A bevel gearbox on the yoke with its handwheel on the side.
static func _gearbox(g, z: float, od: float, side: String, wr: float) -> void:
	var m = g.m
	var s := 0.12 + od * 0.35
	m.use("paint_valve", "identify")
	m.box(Vector3(0, 0, z + s * 0.5), Vector3(s, s * 0.8, s))
	var sx := -1.0 if side == "left" else 1.0
	m.cyl(Vector3(s * 0.5 * sx, 0, z + s * 0.5), Vector3((s * 0.5 + 0.12) * sx, 0, z + s * 0.5), 0.02 + od * 0.02, -1.0, 10)
	_wheel(g, Vector3((s * 0.5 + 0.12) * sx, 0, z + s * 0.5), "left" if sx < 0 else "right", clampf(wr * 0.8, 0.1, 0.35))

## A multi-turn electric actuator: motor, gearbox, local controls, a handwheel on the side.
static func _motor_actuator(g, z: float, od: float, side: String, tree := false) -> void:
	var m = g.m
	var s := clampf(0.22 + od * 0.35, 0.22, 0.6)
	m.use("paint_actuator", "identify")
	m.box(Vector3(0, 0, z + s * 0.45), Vector3(s, s * 0.9, s * 0.9))                       # gearbox
	m.cyl(Vector3(-s * 0.5, -s * 0.05, z + s * 0.55), Vector3(-s * 1.25, -s * 0.05, z + s * 0.55), s * 0.3)   # motor
	m.cyl(Vector3(0, s * 0.45, z + s * 0.6), Vector3(0, s * 0.62, z + s * 0.6), s * 0.28)   # the local controls' cover
	m.use("paint_red", "identify")
	m.cyl(Vector3(-s * 0.08, s * 0.62, z + s * 0.6), Vector3(-s * 0.08, s * 0.67, z + s * 0.6), s * 0.05, -1.0, 10)   # selector knob
	m.use("paint_black", "identify")
	m.cyl(Vector3(s * 0.1, s * 0.62, z + s * 0.6), Vector3(s * 0.1, s * 0.67, z + s * 0.6), s * 0.05, -1.0, 10)
	if tree:
		g.comp("display")
	m.use("glass", "identify")
	m.disk(Vector3(0, s * 0.621, z + s * 0.72), Vector3(0, 1, 0), s * 0.09, 16)               # the display
	if tree:
		g.comp("actuator")
	var sx := -1.0 if side == "left" else 1.0
	if tree:
		g.comp("handwheel")
	_wheel(g, Vector3((s * 0.5 + 0.06) * sx, 0, z + s * 0.45), "left" if sx < 0 else "right", s * 0.6)
	if tree:
		g.comp("actuator")
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
	m.use("paint_valve", "identify")
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
static func _diaphragm(g, z: float, od: float, side: String, cv := {}) -> void:
	var m = g.m
	var tree := not cv.is_empty()
	var R := clampf(0.12 + od * 0.6, 0.13, 0.42)
	var zc := z + 0.06 + R * 0.35
	var prof := [[R * 0.3, -R * 0.35], [R * 0.9, -R * 0.12], [R, 0.0], [R * 0.9, R * 0.15], [R * 0.3, R * 0.42], [0.0, R * 0.45]]
	if tree:
		g.comp("lower_casing")
		g.only("plant", VC_STAND)
	m.use("paint_machine", "identify")
	m.cyl(Vector3(0, 0, z), Vector3(0, 0, z + 0.06), R * 0.25, -1.0)
	m.lathe(Vector3(0, 0, zc), Vector3(0, 0, 1), prof, 0, true)
	m.use("paint_valve", "form")
	m.cyl(Vector3(0, 0, zc - 0.01), Vector3(0, 0, zc + 0.01), R * 1.04, -1.0)   # the casing's bolted rim
	if tree:
		_cv_casings(g, m, cv, z, zc, R, prof)
		g.comp("upper_casing")
		g.only("plant", ["casing_bolts"])
	C.bolt_ring(m, Vector3(0, 0, zc), Vector3(0, 0, 1), R * 0.98, 16, 0.006, 0.04)
	if tree:
		g.only()
		if g.workshop:   # the casing's cap screws and nuts round the rim: they back out upwards
			_ring_bolts_z(g, "casing_bolts", Vector3(0, 0, zc), R * 0.98, 16, 0.006, 0.04)
		_cv_actuator_insides(g, cv, z, zc, R)
		g.comp("positioner")
	# positioner on the yoke's side, with its gauges and the air tubing
	var sx := -1.0 if side == "left" else 1.0
	var pp := Vector3((R * 0.35 + 0.08) * sx, 0.02, z - 0.08)
	m.use("paint_grey", "identify")
	m.box(pp, Vector3(0.1, 0.14, 0.18))
	m.use("dial", "detail", 0.04)
	for k: float in [-1.0, 1.0]:
		m.cyl(pp + Vector3(0.05 * sx, 0.035 * k, 0.05), pp + Vector3(0.07 * sx, 0.035 * k, 0.05), 0.022, -1.0, 10)
	if tree:
		g.comp("tubing")
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
	# (the Workshop's tree: the butterfly valve with a part-turn electric actuator, kit/README.md "The Workshop mode")
	var bt: bool = g.workshop and part == "valve_butterfly" and act == "electric"
	var top: float = r * 1.3 + 0.06 if part == "valve_ball" else C.flange_dims(od).df * 0.5 + 0.02
	var sa := clampf(0.14 + od * 0.25, 0.14, 0.6)   # the electric actuator's size, as drawn below
	var bv := {}
	if bt:
		bv = {"r": r, "od": od, "F": F, "top": top, "s": sa, "zt": top + 0.02, "disc_t": 0.01 + od * 0.02,
			"neck": clampf(od * 0.12, 0.025, 0.2), "flange": clampf(od * 0.2, 0.04, 0.3)}
		bv["shaft"] = minf(minf(od * 0.05, bv.neck * 0.6), bv.disc_t * 0.8)
		_bf_comps(g, bv)
	if part == "valve_ball":
		_body(g, part, od, F, 1.45)
	else:
		var rating: String = g.p.get("rating", "pn16")
		var f := C.flange_dims(od, rating)
		if bt:   # (the drum's first face lists an odd circle's points mirrored: the Workshop closes it with a seam)
			g.only("plant", ["body"])
		m.use("paint_valve", "identify")
		m.cyl(Vector3(0, -F * 0.5, 0), Vector3(0, F * 0.5, 0), f.df * 0.5 * 0.96, -1.0, 0, true)
		if bt:
			g.only("workshop", "split")
			m.use("paint_valve", "identify")
			var R: float = f.df * 0.5 * 0.96
			m.cyl(Vector3(0, -F * 0.5, 0), Vector3(0, F * 0.5, 0), R, -1.0, 0, true)
			C._zip(m, Vector3(0, -F * 0.5, 0), Vector3(0, 1, 0), R, m.segs(R), Vector3(0, -1, 0))
			g.only()
			_bf_liner(g, bv, f.df * 0.5 * 0.96)
			m.use("paint_valve", "identify")
		C.bolt_ring(m, Vector3(0, 0, 0), Vector3(0, 1, 0), f.pcd, f.n, f.bolt_r, F + 0.06)
		g.plate("body", Vector3(f.df * 0.5, 0, 0), Vector3(1, 0, 0), "small")
		g.solid_box(Vector3(-f.df * 0.5, -F * 0.5, -f.df * 0.5), Vector3(f.df * 0.5, F * 0.5, f.df * 0.5))
	m.use("paint_valve", "identify")
	m.cyl(Vector3(0, 0, r * 0.6), Vector3(0, 0, top), clampf(od * 0.12, 0.025, 0.2), -1.0, 12)   # the stem housing
	m.cyl(Vector3(0, 0, top), Vector3(0, 0, top + 0.02), clampf(od * 0.2, 0.04, 0.3), -1.0, 16)
	if bt:
		g.comp("disc")
	var disc = g.move("disc", Vector3(0, 0, 0), Vector3(0, 0, 1), "rotate", PI * 0.5)
	if part == "valve_butterfly":   # the disc itself (seen down the pipe's open end, and in the cut-away)
		disc.use("steel", "form")
		disc.cyl(Vector3(0, -0.01 - od * 0.02, 0), Vector3(0, 0.01 + od * 0.02, 0), r * 0.98, -1.0)
		if bt:   # its first face lists an odd circle's points mirrored: a seam closes it (C._zip)
			g.only("workshop")
			disc.use("steel", "form")
			C._zip(disc, Vector3(0, -0.01 - od * 0.02, 0), Vector3(0, 1, 0), r * 0.98, disc.segs(r * 0.98), Vector3(0, -1, 0))
			g.only()
			_bf_shaft(g, disc, bv)
	var zt := top + 0.02
	if act == "manual" and od < 0.22:
		# a lever: lies along the pipe when open, across it when closed (as built: value 0 is closed)
		disc.use("paint_red", "identify")
		var L := clampf(0.15 + od * 1.8, 0.15, 0.6)
		disc.box(Vector3(L * 0.45, 0, zt + 0.02), Vector3(L, 0.03, 0.015))
		disc.box(Vector3(L * 0.9, 0, zt + 0.02), Vector3(0.08, 0.04, 0.03))
		_no_wheel(g, zt)
		g.axis_line = [Vector3(0, -F, 0), Vector3(0, F, 0)]
		return
	var s := clampf(0.14 + od * 0.25, 0.14, 0.6)
	if act == "manual" or act == "gear":
		m.use("paint_valve", "identify")
		m.box(Vector3(0, 0, zt + s * 0.4), Vector3(s, s * 0.9, s * 0.8))
		var sx := -1.0 if side == "left" else 1.0
		m.cyl(Vector3(s * 0.5 * sx, 0, zt + s * 0.4), Vector3((s * 0.5 + 0.1) * sx, 0, zt + s * 0.4), 0.025, -1.0, 10)
		_wheel(g, Vector3((s * 0.5 + 0.1) * sx, 0, zt + s * 0.4), "left" if sx < 0 else "right", clampf(wheel_r(od) * 0.7, 0.1, 0.35))
		zt += s * 0.8
	elif act == "electric":
		if bt:
			_bf_coupling(g, bv)
			g.comp("actuator")
		m.use("paint_actuator", "identify")
		m.box(Vector3(0, 0, zt + s * 0.45), Vector3(s, s, s * 0.9))
		m.cyl(Vector3(-s * 0.5, 0, zt + s * 0.5), Vector3(-s * 1.15, 0, zt + s * 0.5), s * 0.28)
		var sx := -1.0 if side == "left" else 1.0
		if bt:
			g.comp("handwheel")
		_wheel(g, Vector3((s * 0.5 + 0.05) * sx, 0, zt + s * 0.45), "left" if sx < 0 else "right", s * 0.55)
		if bt:
			g.comp("indicator")
		zt += s * 0.9
	else:   # pneumatic or hydraulic: a rack-and-pinion or scotch-yoke body across the top
		m.use("paint_machine" if act == "pneumatic" else "paint_yellow", "identify")
		m.cyl(Vector3(-s * 1.0, 0, zt + s * 0.35), Vector3(s * 1.0, 0, zt + s * 0.35), s * 0.33)
		m.box(Vector3(0, 0, zt + s * 0.35), Vector3(s * 0.7, s * 0.75, s * 0.7))
		zt += s * 0.7
	# the position indicator on top: an arrow along the disc (along the pipe = open, across = closed; built closed)
	disc.use("paint_yellow", "identify")
	var ir := clampf(s * 0.35, 0.05, 0.2)
	disc.cyl(Vector3(0, 0, zt), Vector3(0, 0, zt + ir * 0.5), ir, -1.0, 16)
	disc.use("paint_black", "identify")
	disc.box(Vector3(0, 0, zt + ir * 0.5 + 0.004), Vector3(ir * 1.9, ir * 0.25, 0.008))
	disc.box(Vector3(ir * 0.85, 0, zt + ir * 0.5 + 0.004), Vector3(ir * 0.25, ir * 0.6, 0.008))
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
	m.use("paint_valve", "identify")
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
	disc.use("paint_valve", "identify")
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
	m.use("paint_valve", "form")
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
			m.use("paint_valve", "identify")
			m.box(ac, Vector3(0.25, 0.25, 0.25))
			_wheel(g, ac + Vector3(0.2, 0, 0), "right", 0.25)
		"electric":
			m.use("paint_actuator", "identify")
			m.box(ac, Vector3(0.35, 0.35, 0.45))
		_:
			m.use("paint_machine" if act == "pneumatic" else "paint_yellow", "identify")
			m.cyl(ac - Vector3(0, 0, 0.4), ac + Vector3(0, 0, 0.4), 0.12)
	g.plate("frame", Vector3(-W * 0.5 - t, -D * 0.5 - 0.01, H * 0.3), Vector3(0, -1, 0), "large")
	g.solid_box(Vector3(-W * 0.5 - t, -D * 0.5, -H * 0.5 - t), Vector3(W * 0.5 + t, D * 0.5, H * 0.5 + t))
	g.axis_line = [Vector3(0, -1, 0), Vector3(0, 1, 0)]

# ------------------------------------------------------------------ the control valve in the Workshop (K6)
# A cage-guided globe valve (Fisher easy-e ES) under a spring-and-diaphragm actuator (Fisher 667) with its positioner,
# as their manuals describe them; what is simplified: kit/README.md "Workshop: the control valve". Every piece here is
# a Workshop piece or the split of a plant stand-in: plant mode draws what it drew before.

## The trim's and the gallery's sizes (m): the plug seats at z 0 (the flow's centre line) on the seat ring, guided in
## the cage, which the bonnet holds down; the gallery (the body's well) runs from under the seat up to the bonnet.
static func _cv_dims(r: float, zb: float, bf: float, zt: float, zg: float, stem_r: float, s: float, kind := "control") -> Dictionary:
	var rp := r * 0.5
	var d := {"kind": kind, "r": r, "zb": zb, "bf": bf, "zt": zt, "zg": zg, "stem_r": stem_r, "s": s,
		"plug": rp, "plug_h": rp * 0.95, "port": rp * 0.8, "cage_in": rp + 0.002, "cage_out": rp + 0.012,
		"well": rp + 0.014, "bot": -rp * 0.7, "seat_h": rp * 0.3, "bore": stem_r * 1.8}
	var od := r * 2.0
	d["zy"] = zg + s + 0.08 + od * 0.15   # the yoke's head, as _rising draws it
	d["ztop"] = d.zy + 0.03 + od * 0.04
	if kind == "gate":
		# the wedge between its two seat rings, in a well as wide as the plant's bonnet flange allows (the gallery's
		# opening lies under it): a wedge of radius `wedge`, half as thick as `wt` at its middle, its faces leaning
		# `lean` (the tangent) from the stem's axis, thicker at the top
		var rw := bf * 0.85
		var rg := rw - 0.01
		d.merge({"well": rw, "wedge": rg, "wt": rg * 0.2, "lean": tan(deg_to_rad(5.0)), "seat_t": rg * 0.1,
			"seat_bore": rg * 0.7, "bot": -(rg + 0.008)}, true)
		var ys: float = d.wt + d.seat_t + d.lean * rg   # the seat rings' outer faces at the top
		d["seat_out"] = minf(rg, sqrt(rw * rw - ys * ys) - 0.002)
	return d

## The tree. The body stays on its pipes; the actuator (the yoke and everything on it) lifts off first, then the
## bonnet, the plug with its stem, the cage and the seat ring come up out of the gallery, the faster ones above the
## slower; on the bench the actuator comes apart upwards (the upper casing over the diaphragm over the stem's head
## over the spring), the positioner and its tubing aside, the stem connector out of the yoke's window.
static func _cv_comps(g, cv: Dictionary, od: float) -> void:
	var up := Vector3(0, 0, 1)
	g.comp("body", {"explode": [up, 0.0]})
	g.comp("yoke", {"parent": "body", "explode": [up, 1.0 + od]})
	g.comp("bonnet", {"parent": "body", "explode": [up, 0.6], "sym": [up, 8]})
	g.comp("plug_stem", {"parent": "body", "explode": [up, 0.4], "sym": [up, 0], "anim": "stem"})
	g.comp("cage", {"parent": "body", "explode": [up, 0.25], "sym": [up, 4]})
	g.comp("seat_ring", {"parent": "body", "explode": [up, 0.12], "sym": [up, 0]})
	g.comp("packing", {"parent": "bonnet", "explode": [up, 0.15], "sym": [up, 0]})
	g.comp("lower_casing", {"parent": "yoke", "explode": [up, 0.35], "sym": [up, 0]})
	g.comp("positioner", {"parent": "yoke", "explode": [Vector3(1, 0, 0), 0.35]})
	g.comp("tubing", {"parent": "yoke", "explode": [Vector3(1, 0, 0), 0.6], "thin": true})
	g.comp("stem_connector", {"parent": "yoke", "explode": [Vector3(0, -1, 0), 0.3], "anim": "stem"})
	g.comp("upper_casing", {"parent": "lower_casing", "explode": [up, 0.7], "sym": [up, 0]})
	g.comp("diaphragm", {"parent": "lower_casing", "explode": [up, 0.5], "sym": [up, 0], "anim": "stem"})
	g.comp("actuator_stem", {"parent": "lower_casing", "explode": [up, 0.35], "sym": [up, 0], "anim": "stem"})
	g.comp("spring", {"parent": "lower_casing", "explode": [up, 0.15], "sym": [up, 0]})

## A closed solid of revolution about z through the origin: `pts` [[r, z], ...] round its section, the first point
## again at the end (outer surfaces going up, inner ones down: their faces turn outwards).
static func _ring_solid(m, pts: Array, n: int) -> void:
	m.lathe(Vector3.ZERO, Vector3(0, 0, 1), pts, n, false)

## The body: the plant's skin (a lathe along the pipe) drawn again with the gallery's opening under the bonnet, its
## ends closed inside the flanges, the flanges' necks closed, and the gallery (hidden) down to under the seat.
static func _cv_body(g, m, prof: Array, F: float, od: float, rating: String, cv: Dictionary) -> void:
	var Y := Vector3(0, 1, 0)
	var n: int = m.segs(float(prof[2][0]))   # the plant's skin's
	var f := C.flange_dims(od, rating)
	# the skin, its ends drawn in to inside the flanges (where it is hidden)
	var e: float = F * 0.5 - f.tf
	var w := Callable(func(a: Array, b: Array, t: float) -> Array:
		return [lerpf(a[0], b[0], (t - a[1]) / (b[1] - a[1])), t])
	var pr: Array = [w.call(prof[0], prof[1], -e), prof[1], prof[2], prof[3], prof[4], w.call(prof[4], prof[5], e)]
	# the angular segments the gallery's opening takes: from the last vertex beside it on one side to the first on
	# the other (vertex i at (cos t, 0, -sin t) * r, t = TAU i / n), over the top
	var R2: float = prof[2][0]
	var rw: float = cv.well
	var ia := -1
	var ib := -1
	for i in n:
		var t := TAU * i / n
		var x := cos(t) * R2
		if -sin(t) <= 0.0:
			continue
		if x < -rw:
			ia = i
		elif x > rw and ib < 0:
			ib = i
	assert(ia >= 0 and ib > ia, "the gallery's opening lies over the body's top")
	g.only("workshop", "split")
	m.use("paint_valve", "identify")
	m.lathe_arc(Vector3.ZERO, Y, pr, n, 0, ia)
	m.lathe_arc(Vector3.ZERO, Y, pr, n, ib, n)
	m.lathe_arc(Vector3.ZERO, Y, pr.slice(0, 3), n, ia, ib)
	m.lathe_arc(Vector3.ZERO, Y, pr.slice(3), n, ia, ib)
	# the lid round the opening: from the gallery's rim (at the bonnet's seat) out to the skin's edge round it
	var K := 16
	var zb: float = cv.zb
	var A: Array = m.across(Vector3(0, 0, 1))
	var inner: Array = []
	for k in K:
		var t := TAU * k / K
		inner.append(Vector3(0, 0, zb) + (A[0] * cos(t) + A[1] * sin(t)) * rw)
	var outer: Array = []
	for i in range(ia, ib + 1):
		var t := TAU * i / n
		outer.append(Vector3(cos(t) * R2, float(prof[2][1]), -sin(t) * R2))
	for i in range(ib, ia - 1, -1):
		var t := TAU * i / n
		outer.append(Vector3(cos(t) * R2, float(prof[3][1]), -sin(t) * R2))
	_fan(m, outer, inner)
	# the flanges again, their necks closed
	for sg: float in [-1.0, 1.0]:
		var d := Y * sg
		var c := Y * F * 0.5 * sg
		m.use("paint_valve", "form")
		var nf: int = m.segs(f.df * 0.5, 10, 40)
		if nf % 2 == 0:
			m.cyl(c - d * f.tf, c, f.df * 0.5, -1.0, nf)
		else:   # (cyl's caps list an odd circle's points mirrored: closed only as the side lists them)
			_closed_cyl(m, c - d * f.tf, c, f.df * 0.5, f.df * 0.5, nf)
		var nn: int = m.segs(od * 0.5, 8, 32)
		var a: Vector3 = c - d * (f.tf * 2.2)
		var b: Vector3 = c - d * f.tf
		m.cyl(a, b, od * 0.5 + f.tf * 0.6, od * 0.5 + f.tf * 0.3, nn, false)
		C.bolt_ring(m, c - d * f.tf * 0.5, d, f.pcd, f.n, f.bolt_r, f.tf * 2.4)
		g.only("workshop")   # the neck's ends, inside the skin and the flange
		m.use("paint_valve", "form")
		C._face(m, a, d, 0.0, od * 0.5 + f.tf * 0.6, nn, false)
		C._face(m, b, d, 0.0, od * 0.5 + f.tf * 0.3, nn, true)
		g.only("workshop", "split")
	# the skin's ends inside the flanges, the gallery down from the bonnet's seat to under the seat ring (hidden)
	g.only("workshop")
	m.use("paint_valve", "identify")
	C._face(m, Vector3(0, -e, 0), Y, 0.0, pr[0][0], n, false)
	C._face(m, Vector3(0, e, 0), Y, 0.0, pr[5][0], n, true)
	m._inner(Vector3(0, 0, cv.bot), Vector3(0, 0, zb), rw, K)
	m.disk(Vector3(0, 0, cv.bot), Vector3(0, 0, 1), rw, K)
	match cv.kind:
		"gate":
			_gv_seats(g, m, cv)
			g.comp("body")
			return
		"globe":
			g.comp("seat_ring")
			m.use("steel", "identify")
			_ring_solid(m, [[cv.port, -cv.seat_h], [rw - 0.001, -cv.seat_h], [rw - 0.001, 0.0], [cv.port, 0.0], [cv.port, -cv.seat_h]], K)
			g.comp("body")
			return
	# the seat ring and the cage, standing in the gallery
	g.comp("seat_ring")
	m.use("steel", "identify")
	_ring_solid(m, [[cv.port, -cv.seat_h], [rw - 0.001, -cv.seat_h], [rw - 0.001, 0.0], [cv.port, 0.0], [cv.port, -cv.seat_h]], K)
	g.comp("cage")
	var ct: float = zb - 0.002
	var bh: float = cv.seat_h
	_ring_solid(m, [[cv.cage_in, 0.0], [cv.cage_out, 0.0], [cv.cage_out, bh], [cv.cage_in, bh], [cv.cage_in, 0.0]], K)
	_ring_solid(m, [[cv.cage_in, ct - bh], [cv.cage_out, ct - bh], [cv.cage_out, ct], [cv.cage_in, ct], [cv.cage_in, ct - bh]], K)
	for k in 4:   # the posts between its windows
		var a := TAU * (k + 0.5) / 4.0
		var rm: float = (cv.cage_in + cv.cage_out) * 0.5
		var wd: float = cv.cage_out - cv.cage_in
		var dir := Vector3(cos(a), sin(a), 0)
		m.box(Vector3(0, 0, ct * 0.5) + dir * rm, Vector3(0.02, wd * 0.9, ct - 2.0 * bh + 0.002),
			Basis(dir.cross(Vector3(0, 0, 1)), -dir, Vector3(0, 0, 1)).orthonormalized())
	g.comp("body")

## A cylinder closed at both ends that is closed for any n (its caps list their points as the side does).
static func _closed_cyl(m, a: Vector3, b: Vector3, ra: float, rb: float, n: int) -> void:
	var d := (b - a).normalized()
	m.cyl(a, b, ra, rb, n, false)
	C._face(m, a, d, 0.0, ra, n, false)
	C._face(m, b, d, 0.0, rb, n, true)

## Triangles between an outer loop and an inner one round the z axis (both in turn, each counter-clockwise seen from
## above, the inner one from its point nearest the outer's first round the axis), facing up: each step goes on along
## the loop whose next point makes the shorter diagonal.
static func _fan(m, outer: Array, inner: Array) -> void:
	var ang := func(p: Vector3) -> float: return atan2(p.y, p.x)
	var a0: float = ang.call(outer[0])
	var rel := func(p: Vector3) -> float: return fposmod(ang.call(p) - a0, TAU)
	# outer in turn from its first point; inner from the first at or past it
	var oa: Array = []
	for p in outer:
		oa.append(rel.call(p))
	var start := 0
	var best := INF
	for k in inner.size():
		var v: float = rel.call(inner[k])
		if v < best:
			best = v
			start = k
	var ins: Array = []
	var ia: Array = []
	for k in inner.size():
		var p: Vector3 = inner[(start + k) % inner.size()]
		ins.append(p)
		ia.append(rel.call(p))
	assert(oa == oa.duplicate() and _increasing(oa) and _increasing(ia), "the loops go round counter-clockwise")
	var no := outer.size()
	var ni := ins.size()
	var o := 0
	var i := 0
	while o < no or i < ni:
		var P: Vector3 = outer[o % no]
		var Q: Vector3 = ins[i % ni]
		var Pn: Vector3 = outer[(o + 1) % no]
		var Qn: Vector3 = ins[(i + 1) % ni]
		# the shorter diagonal (so no triangle reaches across the opening from a far corner of the outer loop)
		if i >= ni or (o < no and Pn.distance_to(Q) <= P.distance_to(Qn)):
			_tri3(m, P, Pn, Q)
			o += 1
		else:
			_tri3(m, P, Qn, Q)
			i += 1

static func _increasing(a: Array) -> bool:
	for k in range(1, a.size()):
		if a[k] <= a[k - 1]:
			return false
	return true

## One flat triangle (counter-clockwise seen from where it faces).
static func _tri3(m, a: Vector3, b: Vector3, c: Vector3) -> void:
	var nrm := (b - a).cross(c - a).normalized()
	var i0: int = m._vert(a, nrm, Vector2(a.x, a.y))
	var i1: int = m._vert(b, nrm, Vector2(b.x, b.y))
	var i2: int = m._vert(c, nrm, Vector2(c.x, c.y))
	m._tri(i0, i1, i2)

## The bonnet: its flange and body as one solid round the stem's bore.
static func _cv_bonnet(g, m, cv: Dictionary, r: float) -> void:
	g.only("workshop", "split")
	m.use("paint_valve", "identify")
	var rb: float = cv.bore
	var n: int = m.segs(cv.bf)
	_ring_solid(m, [[rb, cv.zb], [cv.bf, cv.zb], [cv.bf, cv.zt], [r * 0.36 + 0.015, cv.zt], [r * 0.28 + 0.012, cv.zg],
		[rb, cv.zg]], n)
	g.only("workshop")   # the stem's bore
	m.use("paint_valve", "identify")
	_ring_solid(m, [[rb, cv.zg], [rb, cv.zb]], n)
	g.only()

## The packing rings in the bonnet's bore under the packing flange (the plant's gland: shared).
static func _cv_packing(g, m, cv: Dictionary) -> void:
	g.only("workshop")
	m.use("rubber", "identify")
	var z0: float = cv.zg - 0.04
	var z1: float = cv.zg - 0.0005
	_ring_solid(m, [[cv.stem_r * 1.05, z0], [cv.bore * 0.98, z0], [cv.bore * 0.98, z1], [cv.stem_r * 1.05, z1],
		[cv.stem_r * 1.05, z0]], 12)
	g.only()

## The stem's pieces in the `stem` node: the plant's one stem split at the stem connector into the valve stem (with
## the plug, hidden, on its lower end) and the actuator stem; the plug seated on the seat ring at 0 (closed).
static func _cv_stems(g, sm, cv: Dictionary, z_top: float) -> void:
	var zk: float = cv.zg + 0.04 + cv.r * 2.0 * 0.03   # the connector's centre (the plant's coupling block)
	var sr: float = cv.stem_r
	g.only("workshop", "split")
	g.comp("plug_stem")
	sm.use("chrome", "identify")
	sm.cyl(Vector3(0, 0, cv.zg - cv.s), Vector3(0, 0, zk), sr, -1.0, 10, false)
	g.comp("actuator_stem")
	sm.cyl(Vector3(0, 0, zk), Vector3(0, 0, z_top), sr, -1.0, 10, false)
	g.only("workshop")
	g.comp("plug_stem")
	sm.use("chrome", "identify")
	sm.cyl(Vector3(0, 0, cv.plug_h), Vector3(0, 0, cv.zg - cv.s), sr, -1.0, 10, false)
	sm.disk(Vector3(0, 0, cv.plug_h), Vector3(0, 0, -1), sr, 10)
	sm.disk(Vector3(0, 0, zk), Vector3(0, 0, 1), sr, 10)
	sm.use("steel", "identify")
	sm.lathe(Vector3.ZERO, Vector3(0, 0, 1), [[0.0, 0.0], [cv.plug, 0.0], [cv.plug, cv.plug_h], [0.0, cv.plug_h]], 16, false)
	g.only()

## The diaphragm casing split at its rim: the lower casing (the plant's mounting boss and the dome's lower half) and
## the upper casing, each a shell with its half of the rim; the lower one's boss and bottom open round the actuator
## stem.
static func _cv_casings(g, m, cv: Dictionary, z: float, zc: float, R: float, prof: Array) -> void:
	var e := 0.006
	var n: int = m.segs(R)   # the plant's dome's
	var rs: float = cv.stem_r * 1.5
	var Z := Vector3(0, 0, 1)
	var c := Vector3(0, 0, zc)
	g.only("workshop", "split")
	g.comp("lower_casing")
	m.use("paint_machine", "identify")
	var nb: int = m.segs(R * 0.25)   # the plant's boss's
	var nr: int = m.segs(R * 1.04)   # the plant's rim's
	var lo: Array = [[rs, -R * 0.35], prof[0], prof[1], prof[2], [R - e, 0.0], [R * 0.9 - e, -R * 0.12 + e],
		[R * 0.3 - e, -R * 0.35 + e], [rs, -R * 0.35 + e], [rs, -R * 0.35]]
	var hi: Array = [prof[2], prof[3], prof[4], prof[5], [0.0, R * 0.45 - e], [R * 0.3 - e * 0.5, R * 0.42 - e],
		[R * 0.9 - e, R * 0.15 - e * 0.5], [R - e, 0.0], prof[2]]
	# what the trainee sees of each (split), then its inner faces (hidden)
	_ring_solid(m, [[rs, z], [R * 0.25, z], [R * 0.25, z + 0.06]], nb)
	m.lathe(c, Z, lo.slice(0, 4), n, false)
	m.use("paint_valve", "form")
	m.cyl(c - Z * 0.01, c, R * 1.04, -1.0, nr, false)
	g.comp("upper_casing")
	m.use("paint_machine", "identify")
	m.lathe(c, Z, hi.slice(0, 4), n, false)
	m.use("paint_valve", "form")
	m.cyl(c, c + Z * 0.01, R * 1.04, -1.0, nr, false)
	g.only("workshop")
	g.comp("lower_casing")
	m.use("paint_machine", "identify")
	_ring_solid(m, [[R * 0.25, z + 0.06], [rs, z + 0.06], [rs, z]], nb)
	m.lathe(c, Z, lo.slice(3), n, false)
	m.use("paint_valve", "form")
	C._face(m, c - Z * 0.01, Z, 0.0, R * 1.04, nr, false)
	C._face(m, c, Z, 0.0, R * 1.04, nr, true)
	g.comp("upper_casing")
	m.use("paint_machine", "identify")
	m.lathe(c, Z, hi.slice(3), n, false)
	m.use("paint_valve", "form")
	C._face(m, c, Z, 0.0, R * 1.04, nr, false)
	C._face(m, c + Z * 0.01, Z, 0.0, R * 1.04, nr, true)
	g.only()

## The actuator's insides (hidden; the Fisher 667's, air on top of the diaphragm pushing the stem down to close, the
## spring under it lifting): the diaphragm on its head plate and the plate on the actuator stem's top (in the `stem`
## node, at the closed position), the spring between the plate and the lower casing.
static func _cv_actuator_insides(g, cv: Dictionary, z: float, zc: float, R: float) -> void:
	if not g.workshop:
		return
	var m = g.m
	var sm = g.moving["stem"].mb
	var Z := Vector3(0, 0, 1)
	g.only("workshop")
	g.comp("actuator_stem")
	sm.use("chrome", "identify")
	var zk: float = cv.zg + 0.04 + cv.r * 2.0 * 0.03
	sm.cyl(Vector3(0, 0, z + 0.04 + cv.r * 0.1), Vector3(0, 0, zc - 0.012), cv.stem_r, -1.0, 10, false)
	sm.disk(Vector3(0, 0, zk), Vector3(0, 0, -1), cv.stem_r, 10)
	sm.disk(Vector3(0, 0, zc - 0.012), Vector3(0, 0, 1), cv.stem_r, 10)
	sm.use("steel", "identify")
	sm.cyl(Vector3(0, 0, zc - 0.012), Vector3(0, 0, zc - 0.004), R * 0.55, -1.0, 24)   # the diaphragm head
	g.comp("diaphragm")
	sm.use("rubber", "identify")
	sm.cyl(Vector3(0, 0, zc - 0.003), Vector3(0, 0, zc + 0.001), R * 0.58, -1.0, 24)
	g.comp("spring")
	m.use("steel_dark", "identify")
	var z0 := zc - R * 0.35 + 0.006 + 0.006
	var z1 := zc - 0.012 - 0.006
	var turns := 5
	for k in turns:
		var zz := lerpf(z0, z1, float(k) / (turns - 1))
		m.torus(Vector3(0, 0, zz), Vector3(1, 0, 0), Vector3(0, 1, 0), R * 0.3, 0.005, TAU, 16, 6)
	g.only()

## The gate valve's tree (kit/README.md "The Workshop mode"; the yoke is the bonnet's own, as Crane's). The body
## stays on its pipes; the bonnet with its yoke lifts off the body over the stem, the stem and the wedge come up out of
## the gallery (the wedge slower: it stays below the stem's end); the seat rings stay in the body; on the bench the
## handwheel comes off the stem nut, which stays in the yoke's head (the plant draws the head as one closed block).
static func _gv_comps(g, cv: Dictionary, od: float) -> void:
	var up := Vector3(0, 0, 1)
	g.comp("body", {"explode": [up, 0.0]})
	g.comp("seat_rings", {"parent": "body", "explode": [up, 0.0], "sym": [Vector3(0, 1, 0), 0]})
	g.comp("wedge", {"parent": "body", "explode": [up, 0.3 + od * 0.5], "anim": "stem"})
	g.comp("stem", {"parent": "body", "explode": [up, 0.55 + od], "sym": [up, 0], "anim": "stem"})
	g.comp("bonnet", {"parent": "body", "explode": [up, 0.8 + od * 1.5], "sym": [up, 8]})
	g.comp("packing", {"parent": "bonnet", "explode": [up, 0.15], "sym": [up, 0]})
	g.comp("stem_nut", {"parent": "bonnet", "explode": [up, 0.0], "sym": [up, 0]})
	g.comp("handwheel", {"parent": "bonnet", "explode": [up, 0.3], "sym": [up, 0], "anim": "handwheel",
		"pivot": Vector3(0, 0, cv.ztop)})

## The globe valve's tree with its multi-turn electric actuator. The body stays; the actuator (with the stem nut in
## its output drive) lifts off the yoke's top, its handwheel aside; the stem clamp out of the yoke's window; the
## bonnet with its yoke and packing, the stem and the disc come up as the gate valve's do; the seat ring stays.
static func _gl_comps(g, cv: Dictionary, od: float) -> void:
	var up := Vector3(0, 0, 1)
	g.comp("body", {"explode": [up, 0.0]})
	g.comp("seat_ring", {"parent": "body", "explode": [up, 0.0], "sym": [up, 0]})
	g.comp("disc", {"parent": "body", "explode": [up, 0.14], "sym": [up, 0], "anim": "stem"})
	g.comp("stem", {"parent": "body", "explode": [up, 0.24], "sym": [up, 0], "anim": "stem"})
	g.comp("bonnet", {"parent": "body", "explode": [up, 0.4], "sym": [up, 8]})
	g.comp("packing", {"parent": "bonnet", "explode": [up, 0.05], "sym": [up, 0]})
	g.comp("stem_clamp", {"parent": "bonnet", "explode": [Vector3(0, -1, 0), 0.2], "anim": "stem"})
	g.comp("actuator", {"parent": "bonnet", "explode": [up, 0.5]})
	g.comp("stem_nut", {"parent": "actuator", "explode": [up, 0.0], "sym": [up, 0]})
	g.comp("display", {"parent": "actuator", "explode": [up, 0.0], "thin": true})
	var sa := clampf(0.22 + od * 0.35, 0.22, 0.6)   # the actuator's size, as _motor_actuator draws it
	g.comp("handwheel", {"parent": "actuator", "explode": [Vector3(1, 0, 0), 0.25], "anim": "handwheel",
		"pivot": Vector3(sa * 0.5, 0, cv.ztop + sa * 0.45)})

## The gate's two seat rings (hidden, in the gallery), their faces against the wedge's: each an annulus across the
## flow between two planes leaning as the wedge's faces do.
static func _gv_seats(g, m, cv: Dictionary) -> void:
	g.comp("seat_rings")
	m.use("steel", "identify")
	var a: float = cv.wt
	var t: float = cv.seat_t
	var k: float = cv.lean
	for sg: float in [-1.0, 1.0]:
		var near := func(z: float) -> float: return sg * (a + k * z)
		var far := func(z: float) -> float: return sg * (a + t + k * z)
		if sg > 0.0:
			_slab(m, cv.seat_bore, cv.seat_out, near, far, 16)
		else:
			_slab(m, cv.seat_bore, cv.seat_out, far, near, 16)

## The hidden end of the gate's and the globe's stem (from the closure member up into the plant's stem) and the
## closure member on it, in the `stem` node at the closed position: the gate's wedge between its seat rings, the
## globe's disc on its seat ring.
static func _gv_stem(g, sm, cv: Dictionary) -> void:
	var sr: float = cv.stem_r
	var top: float = cv.zg - cv.s + 0.004
	g.only("workshop")
	g.comp("stem")
	sm.use("chrome", "identify")
	if cv.kind == "gate":
		_closed_cyl(sm, Vector3(0, 0, cv.wedge * 0.8), Vector3(0, 0, top), sr, sr, 10)
		g.comp("wedge")
		sm.use("steel", "identify")
		var a: float = cv.wt
		var k: float = cv.lean
		_slab(sm, 0.0, cv.wedge, func(z: float) -> float: return -(a + k * z), func(z: float) -> float: return a + k * z, 16)
	else:
		_closed_cyl(sm, Vector3(0, 0, cv.plug_h * 0.6), Vector3(0, 0, top), sr, sr, 10)
		g.comp("disc")
		sm.use("steel", "identify")
		sm.lathe(Vector3.ZERO, Vector3(0, 0, 1), [[0.0, 0.0], [cv.plug, 0.0], [cv.plug, cv.plug_h], [0.0, cv.plug_h]], 16, false)
	g.only()

## The gate's stem nut (hidden, in the yoke's head round the stem's thread): the handwheel turns it, and it drives the
## stem up or down.
static func _gv_stem_nut(g, cv: Dictionary, zy: float, ztop: float) -> void:
	var m = g.m
	g.only("workshop")
	g.comp("stem_nut")
	m.use("brass", "identify")
	var ri: float = cv.stem_r * 1.08
	var ro: float = cv.stem_r * 2.2
	_ring_solid(m, [[ri, zy + 0.003], [ro, zy + 0.003], [ro, ztop - 0.003], [ri, ztop - 0.003], [ri, zy + 0.003]], 12)
	g.only()

## The globe's actuator's output drive (a type A thrust base: hidden in the actuator's foot) with the stem nut on
## the stem's thread, and the four bolts that hold the actuator on the yoke's top flange (small outside pieces under
## the flange, backing out downwards).
static func _gl_stem_nut(g, cv: Dictionary, zy: float, ztop: float, od: float) -> void:
	var m = g.m
	var s := clampf(0.22 + od * 0.35, 0.22, 0.6)   # the actuator's size, as _motor_actuator draws it
	g.only("workshop")
	g.comp("stem_nut")
	m.use("brass", "identify")
	var ri: float = cv.stem_r * 1.08
	var ro: float = maxf(cv.stem_r * 2.2, s * 0.12)
	_ring_solid(m, [[ri, ztop + 0.004], [ro, ztop + 0.004], [ro, ztop + s * 0.3], [ri, ztop + s * 0.3], [ri, ztop + 0.004]], 12)
	g.only()
	g.comp("actuator")
	var yw: float = cv.r * 0.45 + 0.03
	var items: Array = []
	for k in 4:
		var x: float = (yw + 0.02 + (s * 0.5 - yw - 0.02) * 0.5) * (-1.0 if k % 2 == 0 else 1.0)
		var y: float = s * 0.3 * (-1.0 if k < 2 else 1.0)
		# its head under the actuator's flange beside the yoke's head, z the way it backs out (down)
		items.append(Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, -1)), Vector3(x, y, ztop)))
	var br := 0.004
	var bolt := func(b) -> void:
		b.use("steel_bolt", "detail", br * 3.4)
		b.cyl(Vector3(0, 0, 0), Vector3(0, 0, 0.006), br * 1.7, -1.0, 6)
		b.cyl(Vector3(0, 0, -0.024), Vector3(0, 0, 0.0), br, -1.0, 6)
	g.fasteners("actuator_bolts", "bolt", items, bolt)

## A solid across the y axis between two planes y = lo(z) and y = hi(z) (lo below hi everywhere), over an annulus
## of radii ri to ro in the xz plane round the origin (ri 0: a disc), n segments.
static func _slab(m, ri: float, ro: float, lo: Callable, hi: Callable, n: int) -> void:
	var P := func(r: float, t: float, f: Callable) -> Vector3:
		var z := r * sin(t)
		return Vector3(r * cos(t), f.call(z), z)
	for i in n:
		var t0 := TAU * i / n
		var t1 := TAU * (i + 1) / n
		var o0: Vector3 = P.call(ro, t0, lo)
		var o1: Vector3 = P.call(ro, t1, lo)
		var O0: Vector3 = P.call(ro, t0, hi)
		var O1: Vector3 = P.call(ro, t1, hi)
		var rad := Vector3(cos((t0 + t1) * 0.5), 0, sin((t0 + t1) * 0.5))
		_quad_out(m, o0, o1, O1, O0, rad)   # the rim
		if ri > 0.0:
			var i0: Vector3 = P.call(ri, t0, lo)
			var i1: Vector3 = P.call(ri, t1, lo)
			var I0: Vector3 = P.call(ri, t0, hi)
			var I1: Vector3 = P.call(ri, t1, hi)
			_quad_out(m, i0, i1, I1, I0, -rad)   # the bore
			_quad_out(m, i0, i1, o1, o0, Vector3(0, -1, 0))
			_quad_out(m, I0, I1, O1, O0, Vector3(0, 1, 0))
		else:
			var c0: Vector3 = Vector3(0, lo.call(0.0), 0)
			var c1: Vector3 = Vector3(0, hi.call(0.0), 0)
			_tri_out(m, c0, o0, o1, Vector3(0, -1, 0))
			_tri_out(m, c1, O0, O1, Vector3(0, 1, 0))

## A flat triangle or quad facing the side `out` points to.
static func _tri_out(m, a: Vector3, b: Vector3, c: Vector3, out: Vector3) -> void:
	if (b - a).cross(c - a).dot(out) < 0.0:
		_tri3(m, a, c, b)
	else:
		_tri3(m, a, b, c)

static func _quad_out(m, a: Vector3, b: Vector3, c: Vector3, d: Vector3, out: Vector3) -> void:
	_tri_out(m, a, b, c, out)
	_tri_out(m, a, c, d, out)

## The butterfly valve's tree (Bray's Series 35/36, kit/README.md "The Workshop mode"). The body stays between its
## pipe flanges; the actuator (its coupling and its position indicator with it) lifts off the neck's top flange, its
## handwheel aside; the shaft comes out up through the neck with its packing; then the disc out of the bore; the
## liner (the seat) stays in the body.
static func _bf_comps(g, bv: Dictionary) -> void:
	var up := Vector3(0, 0, 1)
	var od: float = bv.od
	g.comp("body", {"explode": [up, 0.0]})
	g.comp("liner", {"parent": "body", "explode": [up, 0.0], "sym": [Vector3(0, 1, 0), 0]})
	g.comp("disc", {"parent": "liner", "explode": [Vector3(0, -1, 0), 0.2 + od], "anim": "disc"})
	g.comp("shaft", {"parent": "body", "explode": [up, 0.25 + od * 1.5], "sym": [up, 0], "anim": "disc"})
	g.comp("packing", {"parent": "shaft", "explode": [up, 0.0], "sym": [up, 0]})
	g.comp("actuator", {"parent": "body", "explode": [up, 0.45 + od * 2.0]})
	g.comp("coupling", {"parent": "actuator", "explode": [up, 0.0], "sym": [up, 4]})
	g.comp("indicator", {"parent": "actuator", "explode": [up, 0.0], "anim": "disc",
		"pivot": Vector3(0, 0, bv.zt + bv.s * 0.9)})
	g.comp("handwheel", {"parent": "actuator", "explode": [Vector3(1, 0, 0), 0.25], "anim": "handwheel",
		"pivot": Vector3(bv.s * 0.5, 0, bv.zt + bv.s * 0.45)})
	g.comp("body")

## The liner (the resilient seat, hidden in the body): a ring round the bore whose inner face the disc's edge closes on.
static func _bf_liner(g, bv: Dictionary, R: float) -> void:
	var m = g.m
	var r: float = bv.r
	var w: float = minf(bv.disc_t * 2.5, bv.F * 0.5 - 0.004)
	var ro: float = minf(r * 1.08, R - 0.004)
	g.only("workshop")
	g.comp("liner")
	m.use("rubber", "identify")
	m.lathe(Vector3.ZERO, Vector3(0, 1, 0), [[r * 0.98, -w], [ro, -w], [ro, w], [r * 0.98, w], [r * 0.98, -w]], 24, false)
	g.only()
	g.comp("body")

## The shaft through the disc's hub (hidden, in the `disc` node: it turns with it), from the body's bottom up through
## the neck into the actuator's coupling, and the packing round it under the neck's top flange.
static func _bf_shaft(g, disc, bv: Dictionary) -> void:
	var sr: float = bv.shaft
	g.only("workshop")
	g.comp("shaft")
	disc.use("steel", "identify")
	_closed_cyl(disc, Vector3(0, 0, -bv.r * 1.04), Vector3(0, 0, bv.zt + bv.s * 0.1), sr, sr, 10)
	g.comp("packing")
	disc.use("rubber", "identify")
	var z0: float = bv.top - 0.04
	var z1: float = bv.top - 0.004
	_ring_solid(disc, [[sr * 1.05, z0], [bv.neck * 0.85, z0], [bv.neck * 0.85, z1], [sr * 1.05, z1], [sr * 1.05, z0]], 12)
	g.only()
	g.comp("disc")

## The actuator's coupling on the shaft's top (hidden, in the actuator's foot) and the four bolts under its flange
## beside the neck's top flange (small outside pieces, backing out downwards).
static func _bf_coupling(g, bv: Dictionary) -> void:
	var m = g.m
	var s: float = bv.s
	var zt: float = bv.zt
	g.only("workshop")
	g.comp("coupling")
	m.use("steel", "identify")
	_ring_solid(m, [[bv.shaft * 1.05, zt + 0.004], [s * 0.2, zt + 0.004], [s * 0.2, zt + s * 0.25], [bv.shaft * 1.05, zt + s * 0.25],
		[bv.shaft * 1.05, zt + 0.004]], 12)
	g.only()
	g.comp("actuator")
	var items: Array = []
	var x: float = (bv.flange + s * 0.5) * 0.5
	for k in 4:
		items.append(Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, -1)),
			Vector3(x * (-1.0 if k % 2 == 0 else 1.0), s * 0.3 * (-1.0 if k < 2 else 1.0), zt)))
	var br := 0.004
	var bolt := func(b) -> void:
		b.use("steel_bolt", "detail", br * 3.4)
		b.cyl(Vector3(0, 0, 0), Vector3(0, 0, 0.006), br * 1.7, -1.0, 6)
		b.cyl(Vector3(0, 0, -0.024), Vector3(0, 0, 0.0), br, -1.0, 6)
	g.fasteners("actuator_bolts", "bolt", items, bolt)

## A ring of studs as a fastener group, each where C.bolt_ring draws one (the same hexagon), backing out up the z axis.
static func _ring_bolts_z(g, id: String, c: Vector3, R: float, n: int, r: float, len: float) -> void:
	var items: Array = []
	var Z := Vector3(0, 0, 1)
	var ax: Array = g.m.across(Z)
	for i in n:
		var a := TAU * (i + 0.5) / n
		var p: Vector3 = c + (ax[0] * cos(a) + ax[1] * sin(a)) * R
		items.append(Transform3D(Basis.IDENTITY, p - Z * len * 0.5))
	var bolt := func(b) -> void:
		b.use("steel_bolt", "detail", r * 3.4)
		b.cyl(Vector3.ZERO, Vector3(0, 0, len), r * 1.7, -1.0, 6)
	g.fasteners(id, "bolt", items, bolt, "split")
