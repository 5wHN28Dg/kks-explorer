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
static func _shaft(g, za: float, y_back: float, y_front: float, r: float) -> void:
	var sh = g.move("shaft", Vector3(0, 0, za), Vector3(0, 1, 0), "rotate", 0.0)
	var lo: float = g.ctx.get("shaft_lo", 0.0)
	var hi: float = g.ctx.get("shaft_hi", 0.0)
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
			C.bolt_ring(sh, Vector3(0, y0 + s * (len - 0.06), za), Vector3(0, 1, 0), r * 1.8, 12, 0.012, 0.16)
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
	var prev: Dictionary = {}
	for c in cs:
		var r: float = c.d * 0.5
		var y0: float = c.y0
		var y1: float = c.y1
		var len := y1 - y0
		match c.kind:
			"hp", "ip":
				m.use("cladding", "identify")
				m.lathe(Vector3(0, y0, za), Vector3(0, 1, 0), [[r * 0.55, 0.0], [r * 0.85, len * 0.15], [r, len * 0.35], [r, len * 0.7], [r * 0.8, len * 0.9], [r * 0.5, len]], 0, true)
				m.use("paint_machine", "identify")   # the horizontal joint's flange
				for s: float in [-1.0, 1.0]:
					m.box_lh(Vector3(s * r * 0.92 - 0.1, y0 + len * 0.1, za - 0.09), Vector3(s * r * 0.92 + 0.12, y1 - len * 0.1, za + 0.09))
				m.use("steel_dark", "detail", 0.06)
				for s: float in [-1.0, 1.0]:
					var k := maxi(6, int(len / 0.35))
					for i in k:
						var y := lerpf(y0 + len * 0.12, y1 - len * 0.12, float(i) / (k - 1))
						m.cyl(Vector3(s * (r * 0.92 + 0.05), y, za + 0.09), Vector3(s * (r * 0.92 + 0.05), y, za + 0.25), 0.035, -1.0, 6)
				if c.kind == "hp":   # the main stop and control valve chests on the casing's sides
					m.use("cladding", "identify")
					for s: float in [-1.0, 1.0]:
						m.cyl(Vector3(s * (r + 0.6), y1 - len * 0.3, za - r * 0.4), Vector3(s * (r + 0.6), y1 - len * 0.3, za + r * 0.9), 0.45)
						m.cyl(Vector3(s * (r + 0.6), y1 - len * 0.3, za), Vector3(s * r * 0.8, y1 - len * 0.3, za), 0.25)
					m.use("paint_machine", "identify")   # the servomotors on top of the valves
					for s: float in [-1.0, 1.0]:
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
	m.use("paint_machine", "identify")
	var ends: Array = [L * 0.5 + 0.2, -L * 0.5 - 0.2]
	for i in range(cs.size() - 1):
		ends.append((cs[i].y0 + cs[i + 1].y1) * 0.5)
	for y in ends:
		m.box_lh(Vector3(-0.55, y - 0.4, 0), Vector3(0.55, y + 0.4, za + 0.35))
		m.use("paint_machine", "identify")
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
	_shaft(g, za, -L * 0.5 - 0.6, L * 0.5 + 0.6, 0.22)
	g.plate("side", Vector3(float(cs[0].d) * 0.5 + 0.02, (float(cs[0].y0) + float(cs[0].y1)) * 0.5, za - 0.4), Vector3(1, 0, 0), "large")
	var wmax := 0.0
	for c in cs:
		wmax = maxf(wmax, float(c.d) * (0.78 if c.kind in ["lp", "ip_lp"] else 0.5))
	g.solid_box(Vector3(-wmax, -L * 0.5, 0), Vector3(wmax, L * 0.5, za + d * 0.5))
	g.axis_line = [Vector3(0, -L * 0.5, za), Vector3(0, L * 0.5, za)]

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
