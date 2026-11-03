## Machines (docs/PLANT3D.md §9 "Machines"): the gas turbine (inlet casing, compressor, combustors, turbine, exhaust
## diffuser), generators, steam turbines (casings, crossover), the turning gear, the SFC and the intake filter house.
## Machines on one shaft line share its height and their shafts meet half way (the builder finds the line:
## ctx.axis_z, ctx.shaft_lo, ctx.shaft_hi; kit/README.md "Context"). Each has a `shaft` node turning about y.
extends RefCounted

const C = preload("res://kit/parts_common.gd")

## The shaft line's height above the part's origin when the part stands alone (the gas turbine's is fixed by its
## exhaust nozzle in kit.json: casing_d / 2 + 1).
static func natural_axis(part: String, p: Dictionary) -> float:
	match part:
		"gas_turbine": return float(p.get("casing_d", 4.5)) * 0.5 + 1.0
		"generator": return float(p.get("d", 3.5)) * 0.5 + 0.8
		"steam_turbine": return float(p.get("d", 4)) * 0.5 + 0.6
		"turning_gear": return 1.2
		"motor":
			var md := C.motor_dims(float(p.get("kw", 100)))
			return md.h + 0.15
	return 0.0

## How far the part reaches along its shaft line from its origin: [back (-y), front (+y)].
static func axial_extent(part: String, p: Dictionary) -> Array:
	match part:
		"gas_turbine": return [float(p.get("length", 22)) * 0.5, float(p.get("length", 22)) * 0.5]
		"generator", "steam_turbine": return [float(p.get("length", 10)) * 0.5 + 0.4, float(p.get("length", 10)) * 0.5 + 0.4]
		"turning_gear": return [0.6, 0.6]
		"motor":
			var md := C.motor_dims(float(p.get("kw", 100)))
			return [md.l * 0.5, md.l * 0.5]
	return [0.0, 0.0]

## The shaft stubs out of both ends, with a coupling where they meet a neighbour's half way.
## `bolts_id` (the Workshop, WORKSHOP.md §4.4): the coupling's bolts are that fastener group, replacing the plant's
## bolt ring as a stand-in (the current component holds them).
static func _shaft(g, za: float, y_back: float, y_front: float, r: float, bolts_id := "") -> void:
	var sh = g.move("shaft", Vector3(0, 0, za), Vector3(0, 1, 0), "rotate", 0.0)
	var lo: float = g.ctx.get("shaft_lo", 0.0)
	var hi: float = g.ctx.get("shaft_hi", 0.0)
	var coupled := 0
	for e in [[y_back, -1.0, lo], [y_front, 1.0, hi]]:
		var y0: float = e[0]
		var s: float = e[1]
		var ext: float = e[2]
		var len := maxf(ext, 0.35)
		sh.use("steel", "identify")
		sh.cyl(Vector3(0, y0, za), Vector3(0, y0 + s * len, za), r, -1.0, 16)
		if ext > 0.0:   # the coupling half at the meeting point
			sh.use("paint_darkgrey", "identify")
			sh.cyl(Vector3(0, y0 + s * (len - 0.12), za), Vector3(0, y0 + s * len, za), r * 2.2, -1.0, 20)
			if bolts_id != "":
				g.only("plant", [bolts_id if coupled == 0 else bolts_id + "_2"])
			C.bolt_ring(sh, Vector3(0, y0 + s * (len - 0.06), za), Vector3(0, 1, 0), r * 1.8, 12, 0.012, 0.16)
			if bolts_id != "":
				g.only()
				coupled += 1   # (a machine coupled at both ends: the second group's own id, which its data must name)
				_coupling_bolts(g, bolts_id if coupled == 1 else bolts_id + "_2", Vector3(0, y0 + s * (len - 0.06), za), s, r * 1.8, 12, 0.012, 0.16)
		sh.use("paint_yellow", "identify")
		sh.box(Vector3(0, y0 + s * len * 0.5, za + r * 0.98), Vector3(r * 0.4, len * 0.3, 0.012))

static func gas_turbine(_part: String, g) -> void:
	var m = g.m
	var L: float = g.num("length", 22)
	var D: float = g.num("casing_d", 4.5)
	var za: float = g.ctx.get("axis_z", natural_axis("gas_turbine", g.p))
	var y0 := -L * 0.5
	var ya := func(f: float) -> float: return y0 + L * f
	# the foundation block and the base frame
	m.use("concrete", "form")
	m.box_lh(Vector3(-D * 0.55, y0 + L * 0.05, 0), Vector3(D * 0.55, -y0 - L * 0.05, 0.4))
	# inlet casing: the bellmouth's plenum; with a top intake, the duct up to the filter house
	var pw := D * 0.75
	var top_in := za + D * 0.75
	m.use("paint_beige", "identify")
	m.box_lh(Vector3(-pw, y0, za - D * 0.6), Vector3(pw, ya.call(0.11), top_in))
	if g.p.get("intake", "top") == "top":
		var zt: float = g.ctx.get("intake_top", top_in + 2.0)
		if zt > top_in + 0.1:
			m.use("corrugated_casing", "form")
			m.box_lh(Vector3(-pw * 0.85, y0 + L * 0.005, top_in), Vector3(pw * 0.85, ya.call(0.105), zt))
			m.use("paint_beige", "detail", 0.15)
			var z := top_in + 1.5
			while z < zt - 0.5:   # the duct's stiffeners
				m.box_lh(Vector3(-pw * 0.87, y0, z), Vector3(pw * 0.87, ya.call(0.11), z + 0.12))
				z += 1.5
	else:
		m.use("dark", "identify")
		m.box(Vector3(pw + 0.01, ya.call(0.055), za), Vector3(0.02, L * 0.09, D * 1.0))
	# compressor casing (cold, painted), with its horizontal joint
	m.use("paint_machine", "identify")
	m.cyl(Vector3(0, ya.call(0.11), za), Vector3(0, ya.call(0.40), za), D * 0.44, D * 0.37)
	for s: float in [-1.0, 1.0]:
		m.box_lh(Vector3(s * D * 0.37 - 0.08 if s > 0 else -D * 0.44 - 0.08, ya.call(0.11), za - 0.07),
			Vector3(D * 0.44 + 0.08 if s > 0 else -D * 0.37 + 0.08, ya.call(0.40), za + 0.07))
	m.use("steel_dark", "detail", 0.05)
	for s: float in [-1.0, 1.0]:
		var k := 20
		for i in k:
			var y: float = ya.call(0.12 + 0.27 * i / (k - 1.0))
			m.cyl(Vector3(s * (D * 0.42 + 0.04), y, za + 0.07), Vector3(s * (D * 0.42 + 0.04), y, za + 0.16), 0.025, -1.0, 6)
	# compressor bleed pipes (form: their size tells the compressor end)
	m.use("paint_machine", "form")
	for s: float in [-1.0, 1.0]:
		m.pipe_path([Vector3(s * D * 0.38, ya.call(0.3), za + D * 0.15), Vector3(s * D * 0.55, ya.call(0.3), za + D * 0.15),
			Vector3(s * D * 0.55, ya.call(0.3), 0.6)], 0.12, 0.35)
	# the combustion section: the wrapper, the cans round it, the fuel gas ring and its pigtails
	m.use("paint_machine", "identify")
	m.cyl(Vector3(0, ya.call(0.40), za), Vector3(0, ya.call(0.58), za), D * 0.5)
	var ncan := 12
	for i in ncan:
		var a := TAU * (i + 0.5) / ncan
		var rad := Vector3(cos(a), 0, sin(a))
		var c0 := Vector3(0, ya.call(0.50), za) + rad * D * 0.46
		var c1 := c0 + rad * D * 0.16 + Vector3(0, -L * 0.03, 0)
		m.use("cladding", "identify")
		m.cyl(c0, c1, D * 0.075)
		m.use("steel", "form")
		m.cyl(c1, c1 + (c1 - c0).normalized() * 0.08, D * 0.085)
	m.use("paint_yellow", "identify")   # fuel gas is yellow (plant.json media)
	var yr: float = ya.call(0.47)
	m.torus(Vector3(0, yr, za), Vector3(1, 0, 0), Vector3(0, 0, 1), D * 0.68, 0.07, TAU, 48, 8)
	m.use("chrome", "detail", 0.04)
	for i in ncan:
		var a := TAU * (i + 0.5) / ncan
		var rad := Vector3(cos(a), 0, sin(a))
		m.cyl(Vector3(0, yr, za) + rad * D * 0.68, Vector3(0, ya.call(0.49), za) + rad * D * 0.6, 0.02, -1.0, 6, false)
	# the fuel supply from the ring down to the fuel_in nozzle (kit.json: west of the casing, 1 m up)
	var fin := Vector3(-(D * 0.5 + 0.8), 0, 1.0)
	m.use("paint_yellow", "identify")
	m.pipe_path([Vector3(-D * 0.68, yr, za), Vector3(-D * 0.68, yr, 1.0), Vector3(-D * 0.68, 0, 1.0), fin], 0.08, 0.25)
	C.flange(m, fin, Vector3(-1, 0, 0), 0.16, "paint_yellow", "pn63")
	# the turbine and the exhaust diffuser: hot, insulated and clad
	m.use("cladding", "identify")
	m.cyl(Vector3(0, ya.call(0.58), za), Vector3(0, ya.call(0.72), za), D * 0.49, D * 0.52)
	m.lathe(Vector3(0, ya.call(0.72), za), Vector3(0, 1, 0), [[D * 0.52, 0.0], [D * 0.6, L * 0.14], [D * 0.67, L * 0.28]], 0, false)
	m.use("cladding", "detail", 0.06)
	for f: float in [0.62, 0.68, 0.76, 0.84, 0.92]:   # the cladding's seams
		var rr: float = D * (0.52 + (f - 0.72) / 0.28 * 0.15) if f > 0.72 else D * 0.51
		m.cyl(Vector3(0, ya.call(f) - 0.03, za), Vector3(0, ya.call(f) + 0.03, za), rr + 0.03, -1.0)
	m.use("steel_dark", "identify")   # the expansion joint at the diffuser's end
	m.cyl(Vector3(0, L * 0.5 - 0.35, za), Vector3(0, L * 0.5, za), D * 0.69, -1.0, 0, false)
	# supports: the compressor's and the turbine's legs
	m.use("paint_machine", "form")
	for y: float in [ya.call(0.14), ya.call(0.66)]:
		for s: float in [-1.0, 1.0]:
			m.box_lh(Vector3(s * D * 0.32 - 0.25, y - 0.3, 0.4), Vector3(s * D * 0.32 + 0.25, y + 0.3, za - D * 0.3))
	m.box_lh(Vector3(-D * 0.4, ya.call(0.86) - 0.4, 0.4), Vector3(D * 0.4, ya.call(0.86) + 0.4, za - D * 0.55))
	# the bearing housing at the cold end, the shaft to the generator
	m.use("paint_machine", "identify")
	m.cyl(Vector3(0, y0 - 0.6, za), Vector3(0, y0, za), D * 0.15)
	m.box_lh(Vector3(-D * 0.18, y0 - 0.6, 0.4), Vector3(D * 0.18, y0, za - D * 0.1))
	_shaft(g, za, y0 - 0.6, y0 + 0.2, 0.22)
	C.lug(m, Vector3(0, ya.call(0.25), za + D * 0.43), Vector3(0, 0, 1), 0.4)
	g.plate("side", Vector3(D * 0.43, ya.call(0.25), za - D * 0.12), Vector3(1, 0, 0), "large")
	g.solid_cyl(Vector3(0, y0, za), Vector3(0, -y0, za), D * 0.5)
	g.solid_box(Vector3(-pw, y0, za - D * 0.6), Vector3(pw, ya.call(0.11), top_in))
	g.axis_line = [Vector3(0, y0, za), Vector3(0, -y0, za)]

static func generator(_part: String, g) -> void:
	var m = g.m
	var L: float = g.num("length", 10)
	var d: float = g.num("d", 3.5)
	var za: float = g.ctx.get("axis_z", natural_axis("generator", g.p))
	var hyd: bool = g.p.get("cooling", "air") == "hydrogen"
	var hw := d * 0.62
	var zb := za - d * 0.55
	m.use("concrete", "form")
	m.box_lh(Vector3(-hw - 0.2, -L * 0.5 - 0.3, 0), Vector3(hw + 0.2, L * 0.5 + 0.3, maxf(zb, 0.3)))
	if hyd:
		m.use("paint_machine", "identify")
		m.lathe(Vector3(0, -L * 0.5, za), Vector3(0, 1, 0), [[d * 0.32, 0.0], [d * 0.52, L * 0.06], [d * 0.55, L * 0.12], [d * 0.55, L * 0.88], [d * 0.52, L * 0.94], [d * 0.32, L]], 0, true)
		m.use("paint_machine", "form")
		for f: float in [0.25, 0.75]:   # the hydrogen coolers' housings on top
			m.box(Vector3(0, -L * 0.5 + L * f, za + d * 0.55), Vector3(d * 0.7, L * 0.15, d * 0.35))
		g.solid_cyl(Vector3(0, -L * 0.5, za), Vector3(0, L * 0.5, za), d * 0.55)
	else:
		# the stator frame: a box with chamfered top edges, the coolers' housing on top (TEWAC)
		var top := za + d * 0.5
		var pts := [Vector2(-hw, zb), Vector2(hw, zb), Vector2(hw, top - d * 0.18), Vector2(hw - d * 0.18, top), Vector2(-hw + d * 0.18, top), Vector2(-hw, top - d * 0.18)]
		m.use("paint_machine", "identify")
		m.prism(Vector3(0, L * 0.5, 0), Vector3(1, 0, 0), Vector3(0, 0, 1), pts, L)
		m.use("paint_machine", "form")
		m.box_lh(Vector3(-hw * 0.8, -L * 0.4, top), Vector3(hw * 0.8, L * 0.4, top + d * 0.35))
		m.use("galvanised", "detail", 0.1)   # cooling water to the coolers
		for f: float in [-0.25, 0.25]:
			m.pipe_path([Vector3(hw * 0.8, L * f, top + d * 0.2), Vector3(hw + 0.3, L * f, top + d * 0.2), Vector3(hw + 0.3, L * f, 0.5)], 0.06, 0.2)
		m.use("paint_machine", "detail", 0.08)
		for i in 9:   # the frame's ribs
			var y := -L * 0.5 + L * (i + 0.5) / 9.0
			m.box(Vector3(hw + 0.03, y, za), Vector3(0.06, 0.1, d * 0.9))
			m.box(Vector3(-hw - 0.03, y, za), Vector3(0.06, 0.1, d * 0.9))
		g.solid_box(Vector3(-hw, -L * 0.5, 0), Vector3(hw, L * 0.5, top + d * 0.35))
	# end bearings, the exciter at the non-drive end, the terminal box under it
	m.use("paint_machine", "identify")
	for s: float in [-1.0, 1.0]:
		m.box_lh(Vector3(-d * 0.22, s * (L * 0.5) + (0.0 if s > 0 else -0.4), maxf(zb, 0.3)), Vector3(d * 0.22, s * (L * 0.5) + (0.4 if s > 0 else 0.0), za + d * 0.12))
	m.use("paint_machine", "identify")
	m.cyl(Vector3(0, -L * 0.5 - 0.4, za), Vector3(0, -L * 0.5 - 0.4 - d * 0.4, za), d * 0.24)
	m.use("dark", "detail", 0.1)
	m.disk(Vector3(0, -L * 0.5 - 0.41 - d * 0.4, za), Vector3(0, -1, 0), d * 0.18, 24)
	m.use("paint_grey", "identify")
	m.box_lh(Vector3(-hw * 0.7, -L * 0.45, maxf(zb - 0.9, 0.35)), Vector3(hw * 0.7, -L * 0.2, zb))   # the phase terminals' box
	C.lug(m, Vector3(hw * 0.6, 0, za + d * 0.5), Vector3(0, 0, 1), 0.4)
	_shaft(g, za, -L * 0.5 - 0.4 - d * 0.4, L * 0.5 + 0.4, 0.18)
	g.plate("side", Vector3(hw + 0.07, L * 0.15, za + d * 0.1), Vector3(1, 0, 0), "large")
	g.axis_line = [Vector3(0, -L * 0.5, za), Vector3(0, L * 0.5, za)]

static func turning_gear(_part: String, g) -> void:
	var m = g.m
	var kw: float = g.num("kw", 30)
	var za: float = g.ctx.get("axis_z", natural_axis("turning_gear", g.p))
	var s := clampf(0.7 + kw / 300.0, 0.7, 1.4)
	m.use("concrete", "form")
	m.box_lh(Vector3(-s * 0.6, -0.6, 0), Vector3(s * 0.6, 0.6, maxf(za - s * 0.5, 0.2)))
	m.use("paint_machine", "identify")
	m.box(Vector3(0, 0, za), Vector3(s, 1.0, s))
	m.box(Vector3(0, 0, za + s * 0.55), Vector3(s * 0.6, 0.6, s * 0.15))
	var mo := C.motor_v(m, Vector3(s * 0.2, 0.0, za + s * 0.62), kw)
	m.use("paint_red", "identify")   # the engaging lever
	m.box(Vector3(-s * 0.55, 0.2, za + s * 0.3), Vector3(0.04, 0.04, s * 0.6))
	m.dish(Vector3(-s * 0.55, 0.2, za + s * 0.6), Vector3(0, 0, 1), 0.05, 0.04, 12, 3)
	_shaft(g, za, -0.6, 0.6, 0.18)
	g.plate("side", Vector3(s * 0.5 + 0.01, 0, za), Vector3(1, 0, 0), "small")
	g.solid_box(Vector3(-s * 0.5, -0.5, 0), Vector3(s * 0.5, 0.5, mo.top))
	g.axis_line = [Vector3(0, -0.6, za), Vector3(0, 0.6, za)]

## The coupling's bolts as a fastener group, each item where C.bolt_ring draws one (the same hexagon, so the group
## matches the ring it replaces), backing out away from the coupling's face (towards the machine, -s).
static func _coupling_bolts(g, id: String, c: Vector3, s: float, R: float, n: int, r: float, len: float) -> void:
	var items: Array = []
	var d := Vector3(0, s, 0)
	var ax: Array = g.m.across(d)
	for i in n:
		var a := TAU * (i + 0.5) / n
		var p: Vector3 = c + (ax[0] * cos(a) + ax[1] * sin(a)) * R
		# basis: y the ring's across(d)[0], z = -d (backing out); x = y × z keeps it right-handed
		var by: Vector3 = ax[0]
		var bz := -d
		items.append(Transform3D(Basis(by.cross(bz), by, bz), p + d * len * 0.5))
	var bolt := func(b) -> void:
		b.use("steel_bolt", "detail", r * 3.4)
		b.cyl(Vector3.ZERO, Vector3(0, 0, len), r * 1.7, -1.0, 6)
	g.fasteners(id, "bolt", items, bolt, "split")

## Where each casing of a steam turbine lies along y: [{kind, y0, y1, d}] from the front (+y, the HP end).
static func st_casings(p: Dictionary) -> Array:
	var L := float(p.get("length", 30))
	var d := float(p.get("d", 4))
	var cs: Array = p.get("casings", [])
	if cs.is_empty():
		cs = [{"kind": "hp", "length": L * 0.3, "d": d * 0.7}, {"kind": "ip", "length": L * 0.3, "d": d * 0.85}, {"kind": "lp", "length": L * 0.4, "d": d}]
	var total := 0.0
	for c in cs:
		total += float(c.length)
	var gap := maxf(0.0, (L - total) / maxf(cs.size(), 1))
	var out: Array = []
	var y := L * 0.5
	for c in cs:
		var l := float(c.length) * minf(1.0, L / maxf(total, 0.01))
		out.append({"kind": c.kind, "y1": y - gap * 0.5, "y0": y - gap * 0.5 - l, "d": float(c.d)})
		y -= l + gap
	return out

static func steam_turbine(_part: String, g) -> void:
	var m = g.m
	var L: float = g.num("length", 30)
	var d: float = g.num("d", 4)
	var za: float = g.ctx.get("axis_z", natural_axis("steam_turbine", g.p))
	var cs := st_casings(g.p)
	var exhaust: String = g.p.get("exhaust", "down")
	# the Workshop's tree (WORKSHOP.md §4; docs/plant3d/WORKSHOP.md K4a): an HP turbine of one casing, taken apart as
	# an overhaul does (kit/README.md "Workshop": the steam turbine). Other arrangements show as one component.
	var tree: bool = cs.size() == 1 and cs[0].kind == "hp"
	var paint_by := ["casing_upper", "casing_lower", "pedestal_f", "cap_f", "pedestal_r", "cap_r"]
	var prev: Dictionary = {}
	for c in cs:
		var r: float = c.d * 0.5
		var y0: float = c.y0
		var y1: float = c.y1
		var len := y1 - y0
		match c.kind:
			"hp", "ip":
				var prof := [[r * 0.55, 0.0], [r * 0.85, len * 0.15], [r, len * 0.35], [r, len * 0.7], [r * 0.8, len * 0.9], [r * 0.5, len]]
				if tree:
					_st_comps(g, c, za)
					g.comp("lagging_upper")
					g.only("plant", ["lagging_upper", "lagging_lower"])
				m.use("cladding", "identify")
				m.lathe(Vector3(0, y0, za), Vector3(0, 1, 0), prof, 0, true)
				if tree:
					_st_lagging(g, c, za, prof)
					g.comp("casing_upper")
					g.only("plant", paint_by)
				m.use("paint_machine", "identify")   # the horizontal joint's flange
				for s: float in [-1.0, 1.0]:
					m.box_lh(Vector3(s * r * 0.92 - 0.1, y0 + len * 0.1, za - 0.09), Vector3(s * r * 0.92 + 0.12, y1 - len * 0.1, za + 0.09))
				if tree:
					_st_casing(g, c, za)
					g.comp("casing_upper")
					g.only("plant", ["joint_bolts"])
				m.use("steel_dark", "detail", 0.06)
				var studs: Array = []
				for s: float in [-1.0, 1.0]:
					var k := maxi(6, int(len / 0.35))
					for i in k:
						var y := lerpf(y0 + len * 0.12, y1 - len * 0.12, float(i) / (k - 1))
						m.cyl(Vector3(s * (r * 0.92 + 0.05), y, za + 0.09), Vector3(s * (r * 0.92 + 0.05), y, za + 0.25), 0.035, -1.0, 6)
						studs.append(Transform3D(Basis.IDENTITY, Vector3(s * (r * 0.92 + 0.05), y, za + 0.09)))
				if tree:   # the joint's studs and nuts, each as the plant draws it, backing out upwards
					g.only()
					g.fasteners("joint_bolts", "stud_nut", studs, func(b) -> void:
						b.use("steel_dark", "detail", 0.06)
						b.cyl(Vector3.ZERO, Vector3(0, 0, 0.16), 0.035, -1.0, 6), "split")
				if c.kind == "hp":   # the main stop and control valve chests on the casing's sides
					m.use("cladding", "identify")
					for s: float in [-1.0, 1.0]:
						if tree:
							g.comp("valve_r" if s > 0.0 else "valve_l")
						m.cyl(Vector3(s * (r + 0.6), y1 - len * 0.3, za - r * 0.4), Vector3(s * (r + 0.6), y1 - len * 0.3, za + r * 0.9), 0.45)
						m.cyl(Vector3(s * (r + 0.6), y1 - len * 0.3, za), Vector3(s * r * 0.8, y1 - len * 0.3, za), 0.25)
					if tree:
						_st_valves(g, c, za)
					m.use("paint_machine", "identify")   # the servomotors on top of the valves
					for s: float in [-1.0, 1.0]:
						if tree:
							g.comp("servo_r" if s > 0.0 else "servo_l")
						m.cyl(Vector3(s * (r + 0.6), y1 - len * 0.3, za + r * 0.9), Vector3(s * (r + 0.6), y1 - len * 0.3, za + r * 0.9 + 0.8), 0.2)
			"ip_lp", "lp":
				var y_hood := y0 if c.kind == "lp" else y0 + 0.0
				var y_ip := y1 if c.kind == "ip_lp" else y0
				if c.kind == "ip_lp":   # the IP part: a barrel ahead of the hood
					y_ip = y1 - len * 0.38
					m.use("cladding", "identify")
					m.lathe(Vector3(0, y_ip, za), Vector3(0, 1, 0), [[r * 0.75, 0.0], [r * 0.75, len * 0.05], [r * 0.6, len * 0.3], [r * 0.4, len * 0.38]], 0, true)
				# the LP exhaust hood: a box, rounded on top, down into the condenser
				var hwid := r * 1.55
				var hl := y_ip - y_hood
				var topz := za + r * 0.95
				var pts := [Vector2(-hwid, 0.0), Vector2(hwid, 0.0), Vector2(hwid, za), Vector2(hwid * 0.75, topz - r * 0.15), Vector2(hwid * 0.3, topz), Vector2(-hwid * 0.3, topz), Vector2(-hwid * 0.75, topz - r * 0.15), Vector2(-hwid, za)]
				m.use("paint_machine", "identify")
				m.prism(Vector3(0, y_ip, 0), Vector3(1, 0, 0), Vector3(0, 0, 1), pts, hl)
				m.use("paint_machine", "detail", 0.1)
				var k := maxi(3, int(hl / 1.2))
				for i in k + 1:   # the hood's stiffening ribs
					var y := lerpf(y_hood + 0.1, y_ip - 0.1, float(i) / k)
					m.box(Vector3(hwid + 0.05, y, za * 0.5), Vector3(0.1, 0.12, za))
					m.box(Vector3(-hwid - 0.05, y, za * 0.5), Vector3(0.1, 0.12, za))
				m.use("paint_machine", "identify")   # the joint's flange and its bolts
				for s: float in [-1.0, 1.0]:
					m.box_lh(Vector3(s * hwid - 0.1, y_hood, za - 0.08), Vector3(s * hwid + 0.1, y_ip, za + 0.08))
				m.use("dark", "identify")   # a sight of the atmospheric relief diaphragm on top
				m.disk(Vector3(hwid * 0.5, (y_hood + y_ip) * 0.5, topz - r * 0.07 + 0.02), Vector3(0.25, 0, 1).normalized(), 0.35, 16)
				if exhaust == "down":
					var zl: float = g.ctx.get("exhaust_to", -2.0)
					if zl < -0.05:
						m.use("paint_machine", "form")
						m.box_lh(Vector3(-hwid * 0.9, y_hood + 0.1, zl), Vector3(hwid * 0.9, y_ip - 0.1, 0.0))
				else:
					m.use("paint_machine", "form")
					m.box_lh(Vector3(-hwid * 0.8, y_hood - 2.0, za - r * 0.8), Vector3(hwid * 0.8, y_hood, za + r * 0.8))
		# a crossover from an IP casing to the LP casing behind it, over the top
		if not prev.is_empty() and prev.kind == "ip" and c.kind in ["lp", "ip_lp"]:
			m.use("cladding", "identify")
			var pr: float = prev.d * 0.5
			var cr: float = r
			m.pipe_path([Vector3(0, prev.y0 + 0.6, za + pr * 0.8), Vector3(0, prev.y0 + 0.6, za + pr + 1.4), Vector3(0, c.y1 - 1.0, za + pr + 1.4), Vector3(0, c.y1 - 1.0, za + cr * 0.9)], 0.45, 1.4)
		prev = c
	# bearing pedestals at the ends and between the casings
	if tree:
		g.comp("pedestal_f")
		g.only("plant", paint_by)
	m.use("paint_machine", "identify")
	var ends: Array = [L * 0.5 + 0.2, -L * 0.5 - 0.2]
	for i in range(cs.size() - 1):
		ends.append((cs[i].y0 + cs[i + 1].y1) * 0.5)
	for y in ends:
		m.box_lh(Vector3(-0.55, y - 0.4, 0), Vector3(0.55, y + 0.4, za + 0.35))
		m.use("paint_machine", "identify")
	if tree:
		_st_pedestals(g, ends, za)
		g.comp("casing_lower")   # (the steam pipes below, when the context names the nozzles in use: the casing's)
	# the steam pipes from the casings down through the deck to the nozzles in use (kit.json: on the deck)
	var used: Dictionary = g.ctx.get("used", {})
	for n in used:
		var spec: Dictionary = g.ctx.get("nozzles", {}).get(n, {})
		if spec.is_empty():
			continue
		var p: Vector3 = g.nozzle(spec)
		var od: float = used[n]
		var c0: Dictionary = cs[0]
		for c in cs:
			if p.y >= c.y0 - 0.5 and p.y <= c.y1 + 0.5:
				c0 = c
		var yy := clampf(p.y, float(c0.y0) + 0.3, float(c0.y1) - 0.3)
		m.use("cladding", "identify")
		var zc := za - float(c0.d) * 0.35
		if absf(yy - p.y) > 0.05 or absf(p.x) > 0.05:
			m.pipe_path([Vector3(p.x * 0.3, yy, zc), Vector3(p.x, yy, zc - 0.5), Vector3(p.x, p.y, zc - 0.5), Vector3(p.x, p.y, 0.0)] if absf(yy - p.y) > 0.6 else [Vector3(p.x, yy, zc), Vector3(p.x, p.y, 0.0)], od * 0.5 + 0.05, od * 1.5)
		else:
			m.cyl(Vector3(p.x, p.y, zc), Vector3(p.x, p.y, 0.0), od * 0.5 + 0.05, -1.0, 0, false)
		C.flange(m, Vector3(p.x, p.y, 0.0), Vector3(0, 0, -1), od, "steel", "pn160")
	if tree:
		g.comp("rotor")
	_shaft(g, za, -L * 0.5 - 0.6, L * 0.5 + 0.6, 0.22, "coupling_bolts" if tree else "")
	if tree:
		_st_rotor(g, cs[0], za, L)
	g.plate("side", Vector3(float(cs[0].d) * 0.5 + 0.02, (float(cs[0].y0) + float(cs[0].y1)) * 0.5, za - 0.4), Vector3(1, 0, 0), "large")
	var wmax := 0.0
	for c in cs:
		wmax = maxf(wmax, float(c.d) * (0.78 if c.kind in ["lp", "ip_lp"] else 0.5))
	g.solid_box(Vector3(-wmax, -L * 0.5, 0), Vector3(wmax, L * 0.5, za + d * 0.5))
	g.axis_line = [Vector3(0, -L * 0.5, za), Vector3(0, L * 0.5, za)]

# ------------------------------------------------------------------ the HP turbine in the Workshop (WORKSHOP.md K4a)
# Sources and what is simplified: kit/README.md "Workshop: the steam turbine". All of it is Workshop-only ("workshop"
# pieces and the split of the plant's stand-ins): plant mode draws exactly what it drew before.

const ST_STAGES := 8          # the blade path's stages drawn (a stationary row, then a moving row)
const ST_LAG := 0.2           # the lagging's thickness (radial), its ends 0.1
const ST_WALL := 0.15         # the outer casing's wall
const ST_N := 48              # segments round the shells (even: the halves meet at the horizontal joint)

## The plant's casing profile's radius at t along the casing (t from its rear end).
static func _st_r(prof: Array, t: float) -> float:
	if t <= prof[0][1]:
		return prof[0][0]
	for k in range(prof.size() - 1):
		if t <= prof[k + 1][1]:
			return lerpf(prof[k][0], prof[k + 1][0], (t - prof[k][1]) / maxf(prof[k + 1][1] - prof[k][1], 1e-6))
	return prof[-1][0]

## A profile `inset` inside the plant's between t0 and t1: [[radius, t]] at t0, the plant's corners between, t1.
static func _st_inset(prof: Array, inset: float, t0: float, t1: float) -> Array:
	var out := [[_st_r(prof, t0) - inset, t0]]
	for p in prof:
		if p[1] > t0 + 1e-4 and p[1] < t1 - 1e-4:
			out.append([p[0] - inset, p[1]])
	out.append([_st_r(prof, t1) - inset, t1])
	return out

## One half of a surface of revolution about y through c0 (`upper`: z above the axis): the profile's surface and its
## end disks (inward: an inner wall, its ends facing into the hollow).
static func _st_half(m, c0: Vector3, prof: Array, n: int, upper: bool, inward: bool, caps := true) -> void:
	var d := Vector3(0, 1, 0)
	var i0 := n / 2 if upper else 0
	var i1 := n if upper else n / 2
	m.lathe_arc(c0, d, prof, n, i0, i1, inward)
	if caps:
		var sg := -1.0 if inward else 1.0
		m.sector(c0 + d * float(prof[0][1]), d, -d * sg, 0.0, prof[0][0], n, i0, i1)
		m.sector(c0 + d * float(prof[-1][1]), d, d * sg, 0.0, prof[-1][0], n, i0, i1)

## The faces a half shell is cut by at the horizontal joint, between its outer and inner profiles (as many points
## each). `solid`: closed ends (the profiles run to the axis at their ends); else a ring, its ends closed here too.
static func _st_cuts(m, c0: Vector3, outer: Array, inner: Array, n: int, upper: bool, solid: bool) -> void:
	var d := Vector3(0, 1, 0)
	var ax: Array = m.across(d)
	var a: Array = outer.duplicate()
	var b: Array = inner.duplicate()
	if solid:
		a = [[0.0, outer[0][1]]] + a + [[0.0, outer[-1][1]]]
		b = [[0.0, inner[0][1]]] + b + [[0.0, inner[-1][1]]]
	for i in ([n / 2, n] if upper else [0, n / 2]):
		var t: float = TAU * i / n
		var radial: Vector3 = ax[0] * cos(t) + ax[1] * sin(t)
		var tang: Vector3 = -ax[0] * sin(t) + ax[1] * cos(t)
		var nrm: Vector3 = -tang if i == (n / 2 if upper else 0) else tang   # away from the half's own angles
		for k in range(a.size() - 1):
			var p := func(q: Array) -> Vector3: return c0 + d * float(q[1]) + radial * float(q[0])
			m.quad_n(p.call(a[k]), p.call(a[k + 1]), p.call(b[k + 1]), p.call(b[k]), nrm)
	if not solid:   # a ring's two ends
		var i0 := n / 2 if upper else 0
		var i1 := n if upper else n / 2
		m.sector(c0 + d * float(outer[0][1]), d, -d, inner[0][0], outer[0][0], n, i0, i1)
		m.sector(c0 + d * float(outer[-1][1]), d, d, inner[-1][0], outer[-1][0], n, i0, i1)

## A whole half shell, every face hidden (insides).
static func _st_shell(g, c0: Vector3, outer: Array, inner: Array, upper: bool, solid: bool, n := ST_N) -> void:
	_st_half(g.m, c0, outer, n, upper, false, solid)
	_st_half(g.m, c0, inner, n, upper, true, solid)
	_st_cuts(g.m, c0, outer, inner, n, upper, solid)

## A box's faces (each of "x-", "x+", "y-", "y+", "z-", "z+" listed), facing out.
static func _st_faces(m, lo: Vector3, hi: Vector3, faces: Array) -> void:
	var c := (lo + hi) * 0.5
	var h := (hi - lo) * 0.5
	var axes := {"x": Vector3(1, 0, 0), "y": Vector3(0, 1, 0), "z": Vector3(0, 0, 1)}
	for f in faces:
		var a: Vector3 = axes[f[0]]
		var n: Vector3 = a * (1.0 if f[1] == "+" else -1.0)
		var u: Vector3 = axes["yzx"["xyz".find(f[0])]]
		var w: Vector3 = n.cross(u).normalized()
		var hu := absf(h.dot(u))
		var hw := absf(h.dot(w))
		var o := c + n * absf(h.dot(a))
		m.quad_n(o - u * hu - w * hw, o + u * hu - w * hw, o + u * hu + w * hw, o - u * hu + w * hw, n)

## The blade path along a casing: [{y (the row's centre), moving}], the rows' hub radius, the bore's radius at the
## first and last row (a cone: the blades lengthen as the steam expands towards the exhaust, the rear).
static func _st_path(c: Dictionary) -> Dictionary:
	var r: float = c.d * 0.5
	var len: float = c.y1 - c.y0
	var y_in: float = c.y1 - len * 0.34
	var y_out: float = c.y0 + len * 0.2
	var pitch := (y_in - y_out) / ST_STAGES
	var rows: Array = []
	for k in ST_STAGES:
		rows.append({"stage": k + 1, "y": y_in - pitch * (k + 0.27), "moving": false})
		rows.append({"stage": k + 1, "y": y_in - pitch * (k + 0.73), "moving": true})
	return {"rows": rows, "y_in": y_in, "y_out": y_out, "hub": r * 0.23, "bore_in": r * 0.31, "bore_out": r * 0.39,
		"chord": pitch * 0.24}

## The bore's radius at y (the cone from the first row to the last).
static func _st_bore(pa: Dictionary, y: float) -> float:
	return lerpf(pa.bore_in, pa.bore_out, clampf((pa.y_in - y) / (pa.y_in - pa.y_out), -0.1, 1.1))

## One blade row's blades: flat plates from the hub to the bore (moving: short of it), turned to the steam. The
## rotor turns right-handed about +y; steam flows to -y. A stationary row's trailing edge leans the way the rotor
## turns (the nozzles throw the steam that way), a moving row's leans back.
static func _st_blades(mb, za: float, pa: Dictionary, y: float, moving: bool, a0: float, a1: float, count: int) -> void:
	var beta := deg_to_rad(-35.0 if moving else 50.0)
	var r_in: float = pa.hub + (0.0 if moving else 0.012)
	var r_out: float = _st_bore(pa, y) - (0.012 if moving else 0.0)
	for j in count:
		var phi := lerpf(a0, a1, (j + 0.5) / count)
		var er := Vector3(cos(phi), 0, -sin(phi))   # across(+y): cos·x + sin·(-z), as the shells' angles
		var tang := Vector3(0, 1, 0).cross(er)
		var chord := (Vector3(0, -1, 0) * cos(beta) + tang * sin(beta)).normalized()
		var bs := Basis(chord.cross(er), chord, er)
		_st_box(mb, Vector3(0, y, za) + er * (r_in + r_out) * 0.5, Vector3(0.014, pa.chord, r_out - r_in), bs)

## A box turned by bs, its eight corners computed once (so its faces share their edges to the last bit).
static func _st_box(m, c: Vector3, sz: Vector3, bs: Basis) -> void:
	var h := sz * 0.5
	var p := func(i: int) -> Vector3:
		return c + bs.x * h.x * (1.0 if i & 1 else -1.0) + bs.y * h.y * (1.0 if i & 2 else -1.0) + bs.z * h.z * (1.0 if i & 4 else -1.0)
	var q: Array = []
	for i in 8:
		q.append(p.call(i))
	for f in [[0, 2, 6, 4, -bs.x], [1, 3, 7, 5, bs.x], [0, 1, 5, 4, -bs.y], [2, 3, 7, 6, bs.y], [0, 1, 3, 2, -bs.z], [4, 5, 7, 6, bs.z]]:
		m.quad_n(q[f[0]], q[f[1]], q[f[2]], q[f[3]], f[4])

## Closes a cylinder the plant draws with an odd number of segments (cyl()'s end disks then turn the other way round
## from its side, and their rims don't meet): at each end, hidden, a disk on the side's rim and one on the end disk's.
static func _st_close_cyl(m, a: Vector3, b: Vector3, r: float) -> void:
	var d := (b - a).normalized()
	var n: int = m.segs(r)
	if n % 2 == 0:
		return
	m.sector(a, d, -d, 0.0, r, n, 0, n)
	m.disk(a, -d, r, n)
	m.sector(b, d, d, 0.0, r, n, 0, n)
	m.disk(b, d, r, n)

## Every component of the tree, declared first (the order of the data file's tree; specs in the part frame).
static func _st_comps(g, c: Dictionary, za: float) -> void:
	var up := Vector3(0, 0, 1)
	var r: float = c.d * 0.5
	g.comp("lagging_upper", {"explode": [up, r * 4.3]})
	g.comp("lagging_lower", {"explode": [-up, 1.0]})
	g.comp("casing_lower", {"explode": [up, 0.0]})
	g.comp("casing_upper", {"parent": "casing_lower", "explode": [up, r * 3.15]})
	g.comp("inner_lower", {"parent": "casing_lower", "explode": [up, 0.0]})
	g.comp("inner_upper", {"parent": "inner_lower", "explode": [up, r * 2.2]})
	g.comp("carrier_lower", {"parent": "inner_lower", "explode": [up, 0.0]})
	g.comp("carrier_upper", {"parent": "inner_lower", "explode": [up, r * 1.4]})
	for k in ST_STAGES:
		g.comp("srow_u%d" % (k + 1), {"parent": "carrier_upper", "explode": [up, 0.0]})
	for k in ST_STAGES:
		g.comp("srow_l%d" % (k + 1), {"parent": "carrier_lower", "explode": [up, 0.0]})
	g.comp("glands_lower", {"parent": "casing_lower", "explode": [up, 0.0]})
	g.comp("glands_upper", {"parent": "casing_lower", "explode": [up, r * 1.15]})
	g.comp("rotor", {"parent": "inner_lower", "explode": [up, r * 0.63], "anim": "shaft",
		"pivot": Vector3(0, 0, za), "sym": [Vector3(0, 1, 0), 0]})
	for k in ST_STAGES:
		g.comp("mrow_%d" % (k + 1), {"parent": "rotor", "explode": [up, 0.0]})
	g.comp("collar", {"parent": "rotor", "explode": [up, 0.0]})
	g.comp("pedestal_f", {"explode": [up, 0.0]})
	g.comp("cap_f", {"parent": "pedestal_f", "explode": [up, 2.4]})
	g.comp("brg_f_upper", {"parent": "pedestal_f", "explode": [up, 0.5]})
	g.comp("brg_f_lower", {"parent": "pedestal_f", "explode": [up, 0.0]})
	g.comp("thrust_upper", {"parent": "pedestal_f", "explode": [up, 1.9]})
	g.comp("thrust_lower", {"parent": "pedestal_f", "explode": [-up, 0.12]})
	g.comp("pedestal_r", {"explode": [up, 0.0]})
	g.comp("cap_r", {"parent": "pedestal_r", "explode": [up, 1.6]})
	g.comp("brg_r_upper", {"parent": "pedestal_r", "explode": [up, 0.5]})
	g.comp("brg_r_lower", {"parent": "pedestal_r", "explode": [up, 0.0]})
	for s in ["l", "r"]:
		var x := -1.0 if s == "l" else 1.0
		g.comp("valve_" + s, {"explode": [Vector3(x, 0, 0), 1.6]})
		g.comp("stop_" + s, {"parent": "valve_" + s, "explode": [up, 0.9]})
		g.comp("ctrl_" + s, {"parent": "valve_" + s, "explode": [up, 1.6]})
		g.comp("servo_" + s, {"parent": "valve_" + s, "explode": [up, 2.4]})

## The lagging: the plant's one drum (the stand-in) as two halves split at the joint, each a shell ST_LAG thick.
static func _st_lagging(g, c: Dictionary, za: float, prof: Array) -> void:
	var m = g.m
	var c0 := Vector3(0, c.y0, za)
	var len: float = c.y1 - c.y0
	var n: int = m.segs(c.d * 0.5)   # as lathe() takes it, so the halves are the plant's drum to the vertex
	var inner := []
	for k in prof.size():
		inner.append([prof[k][0] - ST_LAG, clampf(prof[k][1], 0.1, len - 0.1)])
	for up in [false, true]:
		g.comp("lagging_upper" if up else "lagging_lower")
		g.only("workshop", "split")
		m.use("cladding", "identify")
		_st_half(m, c0, prof, n, up, false)
		g.only("workshop")
		m.use("cladding", "identify")
		_st_half(m, c0, inner, n, up, true)
		_st_cuts(m, c0, prof, inner, n, up, true)
	g.only()

## The outer casing's halves, the inner casing's (and its joint's bolts), the blade carriers with their stationary
## rows, and the glands: all inside the lagging. The joint's flanges are the plant's, each split at the joint.
static func _st_casing(g, c: Dictionary, za: float) -> void:
	var m = g.m
	var r: float = c.d * 0.5
	var len: float = c.y1 - c.y0
	var c0 := Vector3(0, c.y0, za)
	var prof := [[r * 0.55, 0.0], [r * 0.85, len * 0.15], [r, len * 0.35], [r, len * 0.7], [r * 0.8, len * 0.9], [r * 0.5, len]]
	var ya: float = c.y0 + len * 0.1
	var yb: float = c.y1 - len * 0.1
	for up in [false, true]:
		var nm := "upper" if up else "lower"
		g.comp("casing_" + nm)
		g.only("workshop", "split")   # its flanges: the plant's two boxes, each cut at the joint
		m.use("paint_machine", "identify")
		for s: float in [-1.0, 1.0]:
			var lo := Vector3(s * r * 0.92 - 0.1, ya, za if up else za - 0.09)
			var hi := Vector3(s * r * 0.92 + 0.12, yb, za + 0.09 if up else za)
			_st_faces(m, lo, hi, ["x-", "x+", "y-", "y+", "z+" if up else "z-"])
		g.only("workshop")
		m.use("paint_machine", "identify")
		for s: float in [-1.0, 1.0]:   # the flanges' joint faces
			var lo := Vector3(s * r * 0.92 - 0.1, ya, za if up else za - 0.09)
			var hi := Vector3(s * r * 0.92 + 0.12, yb, za + 0.09 if up else za)
			_st_faces(m, lo, hi, ["z-" if up else "z+"])
		m.use("steel_dark", "identify")   # the casing's wall, under the lagging
		var outer := []
		for p in prof:
			outer.append([p[0] - ST_LAG, clampf(p[1], 0.1, len - 0.1)])
		var inner := []
		for p in outer:
			inner.append([p[0] - ST_WALL, clampf(p[1], 0.25, len - 0.25)])
		_st_shell(g, c0, outer, inner, up, true)
		# the inner casing: inside the outer one, its own joint flanges and bolts
		g.comp("inner_" + nm)
		var t0 := len * 0.125
		var t1 := len * 0.825
		var io := _st_inset(prof, 0.55, t0, t1)
		var ii := []
		for p in io:
			ii.append([p[0] - 0.15, clampf(p[1], t0 + 0.12, t1 - 0.12)])
		_st_shell(g, c0, io, ii, up, true)
		for s: float in [-1.0, 1.0]:
			var lo := Vector3(s * (r - 0.58) - 0.09, c.y0 + len * 0.35, za if up else za - 0.08)
			var hi := Vector3(s * (r - 0.58) + 0.09, c.y0 + len * 0.7, za + 0.08 if up else za)
			_st_faces(m, lo, hi, ["x-", "x+", "y-", "y+", "z-", "z+"])
	g.comp("inner_upper")
	var bolts: Array = []
	var k := maxi(3, roundi(len * 0.35 / 0.45))   # 6 a side for the plant's 8 m casing
	for s: float in [-1.0, 1.0]:
		for i in k:
			var y := lerpf(c.y0 + len * 0.37, c.y0 + len * 0.68, float(i) / (k - 1))
			bolts.append(Transform3D(Basis.IDENTITY, Vector3(s * (r - 0.58), y, za + 0.08)))
	g.fasteners("inner_bolts", "stud_nut", bolts, func(b) -> void:
		b.use("steel_dark", "detail", 0.04)
		b.cyl(Vector3(0, 0, -0.16), Vector3(0, 0, 0.0), 0.022, -1.0, 8)   # the stud, through both flanges
		b.cyl(Vector3(0, 0, 0.0), Vector3(0, 0, 0.05), 0.04, -1.0, 6), "hidden")   # its nut
	# the blade carriers: a ring each half, its bore a cone over the blade path, the stationary rows in it
	var pa := _st_path(c)
	var ca: float = pa.y_out - 0.06
	var cb: float = pa.y_in + 0.06
	var ro := 1e9
	for t in [ca - c.y0, cb - c.y0, len * 0.35, len * 0.15]:
		if t >= ca - c.y0 - 1e-4 and t <= cb - c.y0 + 1e-4:
			ro = minf(ro, _st_r(prof, t) - 0.73)
	ro = minf(ro, minf(_st_r(prof, ca - c.y0), _st_r(prof, cb - c.y0)) - 0.73)
	var co := [[ro, ca - c.y0], [ro, cb - c.y0]]
	var cin := [[_st_bore(pa, ca), ca - c.y0], [_st_bore(pa, cb), cb - c.y0]]
	for up in [false, true]:
		var nm := "upper" if up else "lower"
		g.comp("carrier_" + nm)
		m.use("steel", "identify")
		_st_shell(g, c0, co, cin, up, false)
		for row in pa.rows:
			if row.moving:
				continue
			g.comp("srow_%s%d" % ["u" if up else "l", row.stage])
			m.use("chrome", "identify")
			_st_blades(m, za, pa, row.y, false, PI if up else 0.0, TAU if up else PI, 14)
	# the glands: labyrinth rings round the shaft where it leaves the casing, each end, halves at the joint
	for up in [false, true]:
		g.comp("glands_upper" if up else "glands_lower")
		m.use("steel", "identify")
		for e in [[len - 0.5, len - 0.12], [0.12, 0.5]]:
			_st_shell(g, c0, [[0.40, e[0]], [0.40, e[1]]], [[0.245, e[0]], [0.245, e[1]]], up, false, 24)
	g.only()

## The valves' insides: in each chest a stop valve's disc below and the control valve's plug above, on their stems.
static func _st_valves(g, c: Dictionary, za: float) -> void:
	var m = g.m
	var r: float = c.d * 0.5
	var y: float = c.y1 - (c.y1 - c.y0) * 0.3
	for s in ["l", "r"]:
		var x := (r + 0.6) * (-1.0 if s == "l" else 1.0)
		g.only("workshop")
		g.comp("valve_" + s)   # the chest and the servomotor as the plant draws them, closed (§7.2)
		m.use("cladding", "identify")
		_st_close_cyl(m, Vector3(x, y, za - r * 0.4), Vector3(x, y, za + r * 0.9), 0.45)
		_st_close_cyl(m, Vector3(x, y, za), Vector3(x * r * 0.8 / (r + 0.6), y, za), 0.25)
		g.comp("servo_" + s)
		m.use("paint_machine", "identify")
		_st_close_cyl(m, Vector3(x, y, za + r * 0.9), Vector3(x, y, za + r * 0.9 + 0.8), 0.2)
		g.comp("stop_" + s)
		m.use("steel", "identify")
		m.cyl(Vector3(x, y, za - 0.25), Vector3(x, y, za - 0.05), 0.3, -1.0, 24)
		m.cyl(Vector3(x, y, za - r * 0.4 + 0.06), Vector3(x, y, za - 0.25), 0.04, -1.0, 8)
		g.comp("ctrl_" + s)
		m.cyl(Vector3(x, y, za + 0.35), Vector3(x, y, za + 0.55), 0.26, -1.0, 24)
		m.cyl(Vector3(x, y, za + 0.55), Vector3(x, y, za + r * 0.9 - 0.02), 0.05, -1.0, 8)
	g.only()

## The pedestals (the plant's boxes): each a body open at the top, its pit inside, and a cap plate over it; the
## journal bearings' halves in them, the thrust bearing in the front one beside the journal.
static func _st_pedestals(g, ends: Array, za: float) -> void:
	var m = g.m
	var top := za + 0.35
	for i in 2:
		var y: float = ends[i]
		var f := "f" if i == 0 else "r"
		g.comp("pedestal_" + f)
		g.only("workshop", "split")
		m.use("paint_machine", "identify")
		_st_faces(m, Vector3(-0.55, y - 0.4, 0), Vector3(0.55, y + 0.4, top), ["x-", "x+", "y-", "y+", "z-"])
		g.only("workshop")   # the pit: its walls slope in from the rim to its floor under the bearing
		m.use("paint_machine", "identify")
		var zb := za - 0.5
		var tq := [Vector3(-0.55, y - 0.4, top), Vector3(0.55, y - 0.4, top), Vector3(0.55, y + 0.4, top), Vector3(-0.55, y + 0.4, top)]
		var bq := [Vector3(-0.45, y - 0.3, zb), Vector3(0.45, y - 0.3, zb), Vector3(0.45, y + 0.3, zb), Vector3(-0.45, y + 0.3, zb)]
		for j in 4:
			var a: Vector3 = tq[j]
			var b: Vector3 = tq[(j + 1) % 4]
			var mid := (a + b) * 0.5
			var inw := Vector3(-mid.x, y - mid.y, 0).normalized()
			m.quad_n(a, b, bq[(j + 1) % 4], bq[j], inw)
		m.quad_n(bq[0], bq[1], bq[2], bq[3], Vector3(0, 0, 1))
		g.comp("cap_" + f)   # a plate 10 mm thick: its top the plant's, its edges and underside inside the rim
		g.only("workshop", "split")
		m.use("paint_machine", "identify")
		m.quad_n(tq[0], tq[1], tq[2], tq[3], Vector3(0, 0, 1))
		g.only("workshop")
		m.use("paint_machine", "identify")
		_st_faces(m, Vector3(-0.55, y - 0.4, top - 0.01), Vector3(0.55, y + 0.4, top), ["x-", "x+", "y-", "y+", "z-"])
		var yc := y - 0.125 if i == 0 else y   # the front journal beside the thrust bearing
		for up in [false, true]:
			g.comp("brg_%s_%s" % [f, "upper" if up else "lower"])
			m.use("chrome", "identify")
			var t0 := yc - 0.125
			var t1 := yc + 0.125
			_st_shell(g, Vector3(0, 0, za), [[0.34, t0], [0.34, t1]], [[0.222, t0], [0.222, t1]], up, false, 24)
		if i == 0:   # the thrust bearing's pads on both faces of the collar, in halves at the joint as the bearing's
			for up in [false, true]:
				g.comp("thrust_upper" if up else "thrust_lower")
				m.use("steel", "identify")
				for t in [y + 0.10, y + 0.22]:
					_st_shell(g, Vector3(0, 0, za), [[0.33, t], [0.33, t + 0.04]], [[0.24, t], [0.24, t + 0.04]], up, false, 24)
	g.only()

## The rotor's insides, in the shaft's moving piece: the drum through the casing (its balance piston ahead of the
## first stage), the moving blade rows, the thrust collar in the front pedestal.
static func _st_rotor(g, c: Dictionary, za: float, L: float) -> void:
	var sh = g.moving["shaft"].mb
	var pa := _st_path(c)
	var ye := L * 0.5 + 0.6
	var yp0: float = pa.y_in + 0.45
	var yp1 := yp0 + 0.55
	g.comp("rotor")
	g.only("workshop")
	sh.use("steel", "identify")
	sh.lathe(Vector3(0, 0, za), Vector3(0, 1, 0), [[0.22, -ye], [0.22, pa.y_out - 0.15], [pa.hub, pa.y_out - 0.1],
		[pa.hub, yp0], [pa.hub * 1.4, yp0], [pa.hub * 1.4, yp1], [0.22, yp1 + 0.05], [0.22, ye]], 32, true)
	for row in pa.rows:
		if not row.moving:
			continue
		g.comp("mrow_%d" % row.stage)
		sh.use("chrome", "identify")
		_st_blades(sh, za, pa, row.y, true, 0.0, TAU, 34)
	g.comp("collar")
	sh.use("steel", "identify")
	sh.cyl(Vector3(0, L * 0.5 + 0.2 + 0.15, za), Vector3(0, L * 0.5 + 0.2 + 0.21, za), 0.33, -1.0, 24)
	g.only()

## The static frequency converter: a row of cabinets on a plinth (doors, handles, louvres, the controller's display).
static func sfc(_part: String, g) -> void:
	var n := int(g.num("panels", 6))
	_cabinet_row(g, n, 0.8, g.num("depth", 0.8), 2.3, true)

## A row of n cabinets of width w along x, centred, doors facing +y (front).
static func _cabinet_row(g, n: int, w: float, depth: float, h: float, louvres: bool) -> void:
	var m = g.m
	var W := n * w
	m.use("paint_darkgrey", "form")
	m.box_lh(Vector3(-W * 0.5, -depth * 0.5, 0), Vector3(W * 0.5, depth * 0.5, 0.1))
	m.use("paint_grey", "identify")
	m.box_lh(Vector3(-W * 0.5, -depth * 0.5, 0.1), Vector3(W * 0.5, depth * 0.5, h))
	for i in n:
		var x := -W * 0.5 + w * (i + 0.5)
		m.use("paint_darkgrey", "identify")
		m.box(Vector3(x - w * 0.5, depth * 0.5 + 0.002, h * 0.5 + 0.05), Vector3(0.008, 0.004, h - 0.1))
		m.box(Vector3(x + w * 0.35, depth * 0.5 + 0.015, h * 0.55), Vector3(0.025, 0.03, 0.18))
		if louvres:
			m.use("dark", "identify")
			m.box(Vector3(x, depth * 0.5 + 0.002, h * 0.15), Vector3(w * 0.6, 0.004, 0.2))
			m.box(Vector3(x, depth * 0.5 + 0.002, h * 0.88), Vector3(w * 0.6, 0.004, 0.15))
		if i == 0:
			m.use("glass", "identify")
			m.box(Vector3(x, depth * 0.5 + 0.004, h * 0.65), Vector3(w * 0.5, 0.006, 0.25))
			for k in 3:
				m.use(["lamp_green", "lamp_amber", "lamp_red"][k], "identify")
				m.cyl(Vector3(x - w * 0.2 + w * 0.2 * k, depth * 0.5, h * 0.48), Vector3(x - w * 0.2 + w * 0.2 * k, depth * 0.5 + 0.02, h * 0.48), 0.02, -1.0, 10)
	g.plate("front", Vector3(-W * 0.5 + w * 0.5, depth * 0.5 + 0.004, h * 0.92), Vector3(0, 1, 0), "large")
	g.solid_box(Vector3(-W * 0.5, -depth * 0.5, 0), Vector3(W * 0.5, depth * 0.5, h))
	g.axis_line = [Vector3(0, 0, 0), Vector3(0, 0, h)]

## The gas turbine's air intake filter house: the casing with its weather hoods on the sides, the filter stages'
## access doors, a platform and ladder, the transition down to the intake duct.
static func filter_house(_part: String, g) -> void:
	var m = g.m
	var L: float = g.num("length", 14)
	var W: float = g.num("width", 12)
	var H: float = g.num("height", 8)
	var zb := 0.0
	m.use("paint_beige", "form")
	for x: float in [-W * 0.5 + 0.3, W * 0.5 - 0.3]:   # the support frame
		for y: float in [-L * 0.5 + 0.3, 0.0, L * 0.5 - 0.3]:
			m.box_lh(Vector3(x - 0.2, y - 0.2, zb), Vector3(x + 0.2, y + 0.2, zb + 1.2))
	m.use("corrugated_casing", "identify")
	m.box_lh(Vector3(-W * 0.5, -L * 0.5, zb + 1.2), Vector3(W * 0.5, L * 0.5, zb + H))
	# the weather hoods: rows of sloping canopies on both long sides
	var rows := maxi(2, int((H - 1.6) / 1.4))
	for s: float in [-1.0, 1.0]:
		for k in rows:
			var z := zb + 1.6 + (H - 1.8) * (k + 0.5) / rows
			m.use("paint_beige", "identify")
			var c := Vector3(s * (W * 0.5 + 0.35), 0, z)
			m.box(c + Vector3(0, 0, 0.25), Vector3(0.7, L * 0.94, 0.04), Basis(Vector3(0, 1, 0), deg_to_rad(-25.0 * s)))
			m.use("dark", "identify")
			m.box(Vector3(s * (W * 0.5 + 0.005), 0, z - 0.05), Vector3(0.01, L * 0.92, 0.55))
			m.use("paint_beige", "detail", 0.06)
			for j in 2:
				m.box(c + Vector3(0, 0, -0.1 - 0.15 * j), Vector3(0.6, L * 0.92, 0.02), Basis(Vector3(0, 1, 0), deg_to_rad(-25.0 * s)))
	# the roof's edge and the access doors at the end
	m.use("paint_beige", "form")
	m.box_lh(Vector3(-W * 0.5 - 0.1, -L * 0.5 - 0.1, zb + H), Vector3(W * 0.5 + 0.1, L * 0.5 + 0.1, zb + H + 0.2))
	for x: float in [-W * 0.25, W * 0.25]:
		m.use("paint_darkgrey", "identify")
		m.box(Vector3(x, -L * 0.5 - 0.02, zb + 2.2), Vector3(0.9, 0.04, 1.9))
	# a platform along the end with its rail and a ladder up to the roof
	m.use("grating", "form")
	m.box_lh(Vector3(-W * 0.5, -L * 0.5 - 1.2, zb + 1.2), Vector3(W * 0.5, -L * 0.5, zb + 1.25))
	C.rail_loop(m, [Vector2(-W * 0.5, -L * 0.5), Vector2(-W * 0.5, -L * 0.5 - 1.2), Vector2(W * 0.5, -L * 0.5 - 1.2), Vector2(W * 0.5, -L * 0.5)], zb + 1.25, false)
	C.ladder(m, Vector3(W * 0.5 - 0.6, -L * 0.5 - 0.25, zb + 1.25), zb + H + 0.2, Vector2(0, 1))
	g.plate("side", Vector3(W * 0.5 + 0.01, L * 0.4, zb + 1.5), Vector3(1, 0, 0), "large")
	g.solid_box(Vector3(-W * 0.5, -L * 0.5, zb), Vector3(W * 0.5, L * 0.5, zb + H))
	g.axis_line = [Vector3(0, 0, 0), Vector3(0, 0, H)]
