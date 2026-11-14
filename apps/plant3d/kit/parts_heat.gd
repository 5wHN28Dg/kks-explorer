## Heat exchange (docs/PLANT3D.md §9 "Heat exchange"): the condenser, shell-and-tube and plate heat exchangers and the
## wet cooling tower (mechanical draft, counterflow: its cells, air inlets with louvres, fill, casing, the hot water
## header; the fans stand on its deck as parts of their own, the deck itself is the content's walkable platform when
## there is one: ctx.decks).
extends RefCounted

const C = preload("res://kit/parts_common.gd")

## The nozzles named, from kit.json. `ws` (the Workshop's trees): nozzle -> [component, stand-in]: the plant's nozzle
## is a stand-in that the component replaces with the same nozzle, each piece closed (_ws_nozzle); an empty stand-in
## leaves it out of the Workshop.
static func _nozzles(g, names: Array, mat: String, stub := 0.6, rating := "pn16", ws := {}) -> void:
	for n in names:
		var spec: Dictionary = g.ctx.get("nozzles", {}).get(n, {})
		if spec.is_empty():
			continue
		var p: Vector3 = g.nozzle(spec)
		var od: float = g.ctx.get("used", {}).get(n, 0.0)
		if od <= 0.0:
			od = g.ctx.get("nozzle_od", {}).get(n, 0.2)
		var dir: Vector3 = {"n": Vector3(0, 1, 0), "s": Vector3(0, -1, 0), "e": Vector3(1, 0, 0), "w": Vector3(-1, 0, 0), "up": Vector3(0, 0, 1), "down": Vector3(0, 0, -1)}[spec.dir]
		if ws.has(n):
			g.comp(ws[n][0])
			g.only("plant", ws[n][1])
		C.nozzle(g.m, p - dir * stub, p, od, mat, rating)
		if ws.has(n):
			if not (ws[n][1] as Array).is_empty():
				_ws_nozzle(g, p - dir * stub, p, od, mat, rating)
			g.only()

## A nozzle as C.nozzle draws it with each piece closed (the pipe, the flange and its neck, their faces listed as their
## cylinders list their rims), its bolts the same: the Workshop's piece replacing the plant's.
static func _ws_nozzle(g, from: Vector3, to: Vector3, od: float, mat: String, rating: String) -> void:
	var m = g.m
	var d := (to - from).normalized()
	var f := C.flange_dims(od, rating)
	g.only("workshop", "split")
	m.use(mat, "form")
	_closed_cyl(m, from, to, od * 0.5, od * 0.5, m.segs(od * 0.5))
	_closed_cyl(m, to - d * f.tf, to, f.df * 0.5, f.df * 0.5, m.segs(f.df * 0.5, 10, 40))
	_closed_cyl(m, to - d * (f.tf * 2.2), to - d * f.tf, od * 0.5 + f.tf * 0.6, od * 0.5 + f.tf * 0.3, m.segs(od * 0.5, 8, 32))
	C.bolt_ring(m, to - d * f.tf * 0.5, d, f.pcd, f.n, f.bolt_r, f.tf * 2.4)

## A cylinder (or a frustum) from a to b closed at both ends: for an even n the kit's caps meet its rims (their
## points are the same), for an odd one the faces are listed as the cylinder lists its rims (C._face).
static func _closed_cyl(m, a: Vector3, b: Vector3, ra: float, rb: float, n: int) -> void:
	var d := (b - a).normalized()
	if n % 2 == 0:
		m.cyl(a, b, ra, rb, n, true)
		return
	m.cyl(a, b, ra, rb, n, false)
	C._face(m, a, d, 0.0, ra, n, false)
	C._face(m, b, d, 0.0, rb, n, true)

## An item's basis for a bolt the plant draws as a cylinder along +y (C.bolt_ring, the plate heat exchanger's
## tightening bolts): its z backs out along -y, and its hexagon's corners stand where the plant's do.
static func _bolt_y() -> Basis:
	return Basis(Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, -1, 0))

## A group of bolts along y replacing the plant's (each a six-sided cylinder of radius r and length len in the
## material `mat`, a detail of `size`, as the plant draws them), each item's origin at its +y end, backing out along -y.
static func _bolts_y(g, id: String, ends: Array, r: float, len: float, mat: String, size: float) -> void:
	var items: Array = []
	for p in ends:
		items.append(Transform3D(_bolt_y(), p))
	var bolt := func(b) -> void:
		b.use(mat, "detail", size)
		b.cyl(Vector3.ZERO, Vector3(0, 0, len), r, -1.0, 6)
	g.fasteners(id, "bolt", items, bolt, "split")

static func condenser(_part: String, g) -> void:
	var m = g.m
	var L: float = g.num("length", 14)
	var W: float = g.num("width", 12)
	var H: float = g.num("height", 16)
	var wb := int(g.num("waterboxes", 4))
	var hot: bool = g.p.get("hotwell", true)
	var zh := 1.5 if hot else 0.0
	m.use("paint_grey", "identify")
	if hot:   # the hotwell: narrower, under the shell
		m.box_lh(Vector3(-W * 0.35, -L * 0.4, 0.2), Vector3(W * 0.35, L * 0.4, zh))
	m.box_lh(Vector3(-W * 0.5, -L * 0.5, zh), Vector3(W * 0.5, L * 0.5, H - 1.0))
	# the neck up to the turbine's exhaust, with its expansion joint at the top
	m.hexa([Vector3(-W * 0.5, -L * 0.5, H - 1.0), Vector3(W * 0.5, -L * 0.5, H - 1.0), Vector3(W * 0.5, L * 0.5, H - 1.0), Vector3(-W * 0.5, L * 0.5, H - 1.0),
		Vector3(-W * 0.4, -L * 0.42, H - 0.3), Vector3(W * 0.4, -L * 0.42, H - 0.3), Vector3(W * 0.4, L * 0.42, H - 0.3), Vector3(-W * 0.4, L * 0.42, H - 0.3)])
	m.use("rubber", "identify")
	m.box_lh(Vector3(-W * 0.41, -L * 0.43, H - 0.3), Vector3(W * 0.41, L * 0.43, H))
	m.use("paint_grey", "detail", 0.12)
	var k := maxi(3, int(L / 1.5))
	for i in k + 1:   # the shell's stiffeners
		var y := -L * 0.5 + L * i / k
		for s: float in [-1.0, 1.0]:
			m.box(Vector3(s * (W * 0.5 + 0.06), y, (zh + H - 1.0) * 0.5), Vector3(0.12, 0.15, H - 1.0 - zh))
	# the water boxes on both ends: half drums, one or two per end, with manways
	var per := 2 if wb >= 4 else 1
	for s: float in [-1.0, 1.0]:
		for j in per:
			var x0 := -W * 0.5 + W * j / per
			var x1 := x0 + W / per
			var zc := 0.5 + (H * 0.55 - 0.5) * 0.5
			var rz := (H * 0.55 - 0.5) * 0.5
			m.use("paint_motor", "identify")   # the water boxes are painted apart (cooling water side)
			var prof: Array = []
			for i in 9:
				var a := PI * i / 8.0
				prof.append(Vector2(-cos(a) * rz, sin(a) * 0.9))
			# a half-round box: its section (z across, y out) extruded along x
			var pts: Array = []
			for q in prof:
				pts.append(Vector2(q.y, q.x))
			# extruded along u x w: +x on the north end, -x on the south end
			var start := Vector3(x0 + 0.05, s * L * 0.5, zc) if s > 0 else Vector3(x1 - 0.05, s * L * 0.5, zc)
			m.prism(start, Vector3(0, s, 0), Vector3(0, 0, 1), pts, (x1 - x0) - 0.1)
			m.use("steel", "identify")   # a manway cover
			m.cyl(Vector3((x0 + x1) * 0.5, s * (L * 0.5 + 0.85), zc + rz * 0.35), Vector3((x0 + x1) * 0.5, s * (L * 0.5 + 0.98), zc + rz * 0.35), 0.35, -1.0, 16)
			C.bolt_ring(m, Vector3((x0 + x1) * 0.5, s * (L * 0.5 + 0.93), zc + rz * 0.35), Vector3(0, 1, 0), 0.31, 16, 0.012, 0.08)
	_nozzles(g, ["cw_inlet_a", "cw_inlet_b", "cw_outlet_a", "cw_outlet_b"], "paint_motor", 0.15)
	_nozzles(g, ["bypass_in", "recirc_in", "hotwell_out", "air_out"], "paint_grey", 0.5)
	# feet
	m.use("concrete", "form")
	for x: float in [-W * 0.35, W * 0.35]:
		for y: float in [-L * 0.35, 0.0, L * 0.35]:
			m.box_lh(Vector3(x - 0.4, y - 0.4, 0), Vector3(x + 0.4, y + 0.4, 0.2))
	g.plate("shell", Vector3(W * 0.5 + 0.13, -L * 0.3, 3.0), Vector3(1, 0, 0), "large")
	g.plate("waterbox", Vector3(-W * 0.25, -L * 0.5 - 0.92, H * 0.3 + 0.8), Vector3(0, -1, 0), "large")
	g.solid_box(Vector3(-W * 0.5, -L * 0.5, 0), Vector3(W * 0.5, L * 0.5, H))
	g.axis_line = [Vector3(0, 0, 0), Vector3(0, 0, H)]

static func shell_tube_hx(_part: String, g) -> void:
	var m = g.m
	var d: float = g.num("d", 1.2)
	var L: float = g.num("length", 5)
	var vert: bool = g.p.get("orientation", "horizontal") == "vertical"
	var r := d * 0.5
	if vert:
		var keep: Transform3D = m.xf
		m.use("paint_tank", "identify")
		m.cyl(Vector3(0, 0, 0.6), Vector3(0, 0, L - 0.3), r)
		m.dish(Vector3(0, 0, L - 0.3), Vector3(0, 0, 1), r, r * 0.4, 0, 4)
		C.flange_pair(m, Vector3(0, 0, L - r * 0.8), Vector3(0, 0, 1), d, "paint_tank")
		m.use("paint_darkgrey", "form")
		for k in 4:
			var a := TAU * (k + 0.5) / 4.0
			m.box_lh(Vector3(cos(a) * r * 0.9 - 0.06, sin(a) * r * 0.9 - 0.06, 0), Vector3(cos(a) * r * 0.9 + 0.06, sin(a) * r * 0.9 + 0.06, 1.0))
		m.xf = keep
		g.plate("shell", Vector3(r + 0.01, 0, 1.5), Vector3(1, 0, 0), "large")
		g.solid_cyl(Vector3(0, 0, 0), Vector3(0, 0, L), r)
		g.axis_line = [Vector3(0, 0, 0), Vector3(0, 0, L)]
		return
	var zc := r + 0.5
	# the Workshop's tree (kit/README.md "The Workshop mode"): the horizontal exchanger as a removable bundle with a
	# packed floating tubesheet and a bonnet at each end (TEMA BEW)
	var tree: bool = g.workshop
	var st := {}
	var n: int = m.segs(r)
	if tree:
		st = _ste_dims(d, L, zc)
		_ste_comps(g, st)
		g.comp("shell")
	m.use("paint_tank", "identify")
	m.cyl(Vector3(0, -L * 0.5 + 0.5, zc), Vector3(0, L * 0.5 - 0.3, zc), r, -1.0, 0, false)
	if tree:
		_ste_shell(g, st, n)
		g.comp("rear_bonnet")
		m.use("paint_tank", "identify")
	m.dish(Vector3(0, L * 0.5 - 0.3, zc), Vector3(0, 1, 0), r, 0.3, 0, 4)
	if tree:   # the dish closed at its rim, inside the shell's end
		g.only("workshop")
		m.use("paint_tank", "identify")
		C._face(m, Vector3(0, L * 0.5 - 0.3, zc), Vector3(0, 1, 0), 0.0, r, n, false)
		g.only()
		g.comp("front_bonnet")
	m.use("paint_grey", "identify")   # the channel head with its flange
	m.cyl(Vector3(0, -L * 0.5 + 0.1, zc), Vector3(0, -L * 0.5 + 0.5, zc), r)
	m.dish(Vector3(0, -L * 0.5 + 0.1, zc), Vector3(0, -1, 0), r, 0.1 + r * 0.2, 0, 4)
	if tree:
		# the plant's head is a closed cylinder with the dish on its end: one more face there (facing in) closes it
		g.only("workshop")
		m.use("paint_grey", "identify")
		m.disk(Vector3(0, -L * 0.5 + 0.1, zc), Vector3(0, 1, 0), r, n)
		g.only()
		# the joint's flanges as the plant draws them (C.flange_pair), its studs a fastener group
		var fc := Vector3(0, -L * 0.5 + 0.5, zc)
		var f := C.flange_dims(d, "pn16")
		m.use("paint_grey", "form")
		m.cyl(fc - Vector3(0, f.tf, 0), fc + Vector3(0, f.tf, 0), f.df * 0.5, -1.0, m.segs(f.df * 0.5, 10, 40))
		g.only("plant", ["bonnet_bolts"])
		C.bolt_ring(m, fc, Vector3(0, 1, 0), f.pcd, f.n, f.bolt_r, f.tf * 3.0)
		g.only()
		var ends: Array = []
		var ax: Array = m.across(Vector3(0, 1, 0))
		for i in f.n:
			var a: float = TAU * (i + 0.5) / float(f.n)
			ends.append(fc + (ax[0] * cos(a) + ax[1] * sin(a)) * f.pcd + Vector3(0, f.tf * 1.5, 0))
		_bolts_y(g, "bonnet_bolts", ends, f.bolt_r * 1.7, f.tf * 3.0, "steel_bolt", f.bolt_r * 3.4)
		g.comp("saddles")
	else:
		C.flange_pair(m, Vector3(0, -L * 0.5 + 0.5, zc), Vector3(0, 1, 0), d, "paint_grey")
	m.use("paint_darkgrey", "form")
	for y: float in [-L * 0.3, L * 0.3]:
		m.box_lh(Vector3(-r * 0.75, y - 0.12, 0), Vector3(r * 0.75, y + 0.12, zc - r * 0.5))
	# (the shell's nozzles stand inside the shell, their points under its top: the Workshop leaves them out)
	var ws := {"shell_in": ["shell", []], "shell_out": ["shell", []], "tube_in": ["rear_bonnet", ["rear_bonnet"]],
		"tube_out": ["front_bonnet", ["front_bonnet"]]}
	_nozzles(g, ["shell_in", "shell_out", "tube_in", "tube_out"], "paint_tank", 0.25, "pn16", ws if tree else {})
	if tree:
		_ste_bundle(g, st, n)
	g.plate("shell", Vector3(r + 0.01, 0, zc), Vector3(1, 0, 0), "large")
	g.solid_cyl(Vector3(0, -L * 0.5, zc), Vector3(0, L * 0.5, zc), r)
	g.axis_line = [Vector3(0, -L * 0.5, zc), Vector3(0, L * 0.5, zc)]

## The shell-and-tube exchanger's measures in the Workshop: the shell's wall and bore, the stationary tubesheet's face
## (the flange's back face, y0) and the shell's end (y1), the tubesheets, baffles and packing rings.
static func _ste_dims(d: float, L: float, zc: float) -> Dictionary:
	var r := d * 0.5
	var f := C.flange_dims(d, "pn16")
	var ri := r - clampf(d * 0.01, 0.006, 0.03)            # the shell's bore (a 12 mm wall at 1.2 m)
	var w := clampf(d * 0.035, 0.02, 0.08)                  # each packing ring's and the lantern ring's width
	var y1 := L * 0.5 - 0.3
	return {"r": r, "ri": ri, "zc": zc, "d": d, "ys": -L * 0.5 + 0.5, "y0": -L * 0.5 + 0.5 + f.tf, "y1": y1,
		"ts": clampf(d * 0.05, 0.03, 0.15),                 # the stationary tubesheet's thickness
		"rb": ri - 0.006,                                    # the stationary tubesheet's and the baffles' radius
		"rf": ri - clampf(d * 0.025, 0.015, 0.06),          # the floating tubesheet's (the packing round it)
		"w": w, "yf0": y1 - 0.002 - 3.0 * w - 0.01,         # the floating tubesheet's inner face
		"yf1": y1 - 0.002}                                   # its outer face, just inside the shell's end

## The tree. The shell stays on its saddles with its pipes; the bonnets come off its ends, the packing rings and the
## lantern ring out of the floating end, and the bundle is drawn out of the stationary end (it goes farther than the
## shell is long; the front bonnet farther still, so the bundle comes out behind it).
static func _ste_comps(g, st: Dictionary) -> void:
	var up := Vector3(0, 0, 1)
	var back := Vector3(0, -1, 0)
	var fwd := Vector3(0, 1, 0)
	var len: float = st.y1 - st.y0
	g.comp("shell", {"explode": [up, 0.0]})
	g.comp("saddles", {"parent": "shell", "explode": [up, 0.0]})
	g.comp("bundle", {"parent": "shell", "explode": [back, len + 0.4]})
	g.comp("tubesheet_f", {"parent": "bundle", "explode": [up, 0.0], "sym": [fwd, 0]})
	g.comp("tubes", {"parent": "bundle", "explode": [up, 0.0]})
	g.comp("baffles", {"parent": "bundle", "explode": [up, 0.0]})
	g.comp("tie_rods", {"parent": "bundle", "explode": [up, 0.0]})
	g.comp("packing_in", {"parent": "shell", "explode": [fwd, 0.5], "sym": [fwd, 0]})
	g.comp("lantern_ring", {"parent": "shell", "explode": [fwd, 0.7], "sym": [fwd, 0]})
	g.comp("packing_out", {"parent": "shell", "explode": [fwd, 0.9], "sym": [fwd, 0]})
	g.comp("rear_bonnet", {"parent": "shell", "explode": [fwd, 1.2]})
	g.comp("front_bonnet", {"parent": "shell", "explode": [back, len + 1.0]})

## The shell's wall (hidden): its bore and its two ends' faces, inside the joint's flanges and the rear bonnet.
static func _ste_shell(g, st: Dictionary, n: int) -> void:
	var m = g.m
	var y := Vector3(0, 1, 0)
	var c0 := Vector3(0, st.ys, st.zc)
	var c1 := Vector3(0, st.y1, st.zc)
	g.only("workshop")
	m.use("paint_tank", "identify")
	m._inner(c0, c1, st.ri, n)
	C._face(m, c0, y, st.ri, st.r, n, false)
	C._face(m, c1, y, st.ri, st.r, n, true)
	g.only()

## The bundle and the packing (hidden, inside the shell): the stationary tubesheet (the bundle's own piece), the
## floating tubesheet, the tubes on a triangular pitch from one tubesheet's outer face to the other's, the segmental
## baffles cut alternately at the top and the bottom, the tie rods (with their spacers) from the stationary tubesheet to
## the last baffle; round the floating tubesheet the inner packing rings, the lantern ring and the outer packing rings.
static func _ste_bundle(g, st: Dictionary, n: int) -> void:
	var m = g.m
	var zc: float = st.zc
	var y0: float = st.y0
	var y0b: float = y0 + float(st.ts)
	var yf0: float = st.yf0
	var yf1: float = st.yf1
	g.only("workshop")
	g.comp("bundle")
	m.use("steel", "identify")
	_closed_cyl(m, Vector3(0, y0, zc), Vector3(0, y0b, zc), st.rb, st.rb, n)
	g.comp("tubesheet_f")
	m.use("steel", "identify")
	_closed_cyl(m, Vector3(0, yf0, zc), Vector3(0, yf1, zc), st.rf, st.rf, n)
	var lay := ste_layout(st)
	g.comp("tubes")
	m.use("brass", "identify")
	for q in lay.tubes:
		_closed_cyl(m, Vector3(q.x, y0, zc + q.y), Vector3(q.x, yf1, zc + q.y), lay.rt, lay.rt, 6)
	g.comp("baffles")
	m.use("steel", "identify")
	var nb: int = lay.baffles.size()
	for i in nb:
		var yb: float = lay.baffles[i]
		var cut := acos(0.5)   # a cut of a quarter of the diameter: the chord half a radius from the centre
		var pts: Array = []
		var k := maxi(8, int(n * 2 / 3))
		# u = z, w = x (the prism's axis +y): angles from +z; the top cut keeps z <= rb / 2, the bottom cut z >= -rb / 2
		var a0: float = cut if i % 2 == 0 else -(PI - cut)
		var a1: float = TAU - cut if i % 2 == 0 else PI - cut
		for j in k + 1:
			var t := lerpf(a0, a1, float(j) / k)
			pts.append(Vector2(cos(t), sin(t)) * float(st.rb))
		m.prism(Vector3(0, yb, zc), Vector3(0, 0, 1), Vector3(1, 0, 0), pts, lay.tb)
	g.comp("tie_rods")
	m.use("steel", "identify")
	for q in lay.rods:
		_closed_cyl(m, Vector3(q.x, y0b, zc + q.y), Vector3(q.x, lay.baffles[nb - 1] + lay.tb, zc + q.y), lay.rr, lay.rr, 6)
	var w: float = st.w
	var ri: float = float(st.rf) + 0.001
	var ro: float = st.ri
	var ids := ["packing_out", "lantern_ring", "packing_in"]
	var mats := ["rubber", "brass", "rubber"]
	for i in 3:
		g.comp(ids[i])
		m.use(mats[i], "identify")
		var a: float = yf1 - w * (i + 1)
		var b: float = yf1 - w * i
		m.lathe(Vector3(0, 0, zc), Vector3(0, 1, 0), [[ri, a], [ro, a], [ro, b], [ri, b], [ri, a]], n, false)
	g.only()

## Where the tubes, the tie rods and the baffles are: a triangular pitch (a picture: a real 1.2 m shell holds about
## 1,500 tubes of 19 mm) inside the floating tubesheet's rim; four places of it, round the outside at 45 degrees,
## carry the tie rods; the baffles evenly between the tubesheets. {tubes: [Vector2 (x, z from the axis)], rods,
## rt: a tube's radius, rr: a rod's, baffles: [y], tb: their thickness}.
static func ste_layout(st: Dictionary) -> Dictionary:
	var rt := 0.0095
	var p := clampf(float(st.d) * 0.075, 0.04, 0.3)
	var R: float = float(st.rf) - rt - 0.02
	var pts: Array = []
	var rows := int(R / (p * 0.866))
	for j in range(-rows, rows + 1):
		var z := j * p * 0.866
		var off := 0.5 * p if absi(j) % 2 == 1 else 0.0
		var cols := int((R + p) / p) + 1
		for i in range(-cols, cols + 1):
			var x := i * p + off
			if Vector2(x, z).length() <= R:
				pts.append(Vector2(x, z))
	var rods: Array = []
	for k in 4:
		var a := PI * 0.25 + PI * 0.5 * k
		var want := Vector2(cos(a), sin(a)) * R * 0.8
		var best := 0
		for i in pts.size():
			if (pts[i] as Vector2).distance_to(want) < (pts[best] as Vector2).distance_to(want):
				best = i
		rods.append(pts[best])
		pts.remove_at(best)
	var y0b: float = float(st.y0) + float(st.ts)
	var span: float = float(st.yf0) - y0b
	var nb := maxi(2, int(span / (float(st.d) * 0.55)))
	var tb := clampf(float(st.d) * 0.007, 0.005, 0.02)
	var baffles: Array = []
	for i in nb:
		baffles.append(y0b + span * (i + 1) / (nb + 1) - tb * 0.5)
	return {"tubes": pts, "rods": rods, "rt": rt, "rr": 0.012, "baffles": baffles, "tb": tb}

## A plate heat exchanger: the fixed frame plate with its four nozzles (kit.json), the plate pack, the pressure
## plate, the carrying and guide bars, the end support and the tightening bolts.
static func plate_hx(_part: String, g) -> void:
	var m = g.m
	var n := int(g.num("plates", 200))
	var H: float = g.num("height", 2.2)
	var Wp := clampf(H * 0.42, 0.3, 1.6)
	var pack := clampf(n * 0.0045, 0.05, 4.0)
	var yf := 0.45
	var yb := yf - 0.08 - pack - 0.08
	var yc := yb - 0.4
	var k := clampi(int(pack / 0.03), 2, 60)
	var tree: bool = g.workshop   # the Workshop's tree (kit/README.md "The Workshop mode")
	if tree:
		_phe_comps(g, Wp, yb, yc)
		g.comp("frame_plate")
	m.use("paint_motor", "identify")
	m.box_lh(Vector3(-Wp * 0.6, yf - 0.08, 0.0), Vector3(Wp * 0.6, yf, H))                 # the fixed frame plate
	if tree:
		g.comp("pressure_plate")
	m.box_lh(Vector3(-Wp * 0.6, yb, 0.15), Vector3(Wp * 0.6, yb + 0.08, H - 0.05))          # the pressure plate
	if tree:
		g.comp("plates")
		g.only("plant", PHE_PLATES)
	m.use("steel", "identify")   # the plate pack: corrugated stainless plates
	m.box_lh(Vector3(-Wp * 0.5, yb + 0.08, 0.2), Vector3(Wp * 0.5, yf - 0.08, H - 0.15))
	m.use("steel_dark", "detail", 0.004)
	for i in k:
		var y := yb + 0.08 + (pack) * (i + 0.5) / k
		m.box(Vector3(Wp * 0.505, y, H * 0.5), Vector3(0.004, 0.006, H - 0.4))
	if tree:
		_phe_plates(g, Wp, H, yb + 0.08, yf - 0.08, k + 1)
		g.only()
		g.comp("carrying_bar")
	m.use("steel", "form")   # the carrying bar on top, the guide bar below, the end column
	m.box_lh(Vector3(-0.05, yc, H - 0.1), Vector3(0.05, yf, H + 0.05))
	if tree:
		g.comp("guiding_bar")
	m.box_lh(Vector3(-0.04, yc, 0.12), Vector3(0.04, yf, 0.2))
	if tree:
		g.comp("support_column")
	m.use("paint_motor", "form")
	m.box_lh(Vector3(-0.12, yc - 0.12, 0), Vector3(0.12, yc + 0.12, H + 0.05))
	if tree:
		g.comp("pressure_plate")
		g.only("plant", ["tightening_bolts", "locking_bolts"])
	m.use("steel", "detail", 0.04)
	for x: float in [-Wp * 0.62, Wp * 0.62]:
		for z: float in [0.4, H * 0.5, H - 0.4]:
			m.cyl(Vector3(x, yb - 0.1, z), Vector3(x, yf + 0.06, z), 0.02, -1.0, 6)
	if tree:
		g.only()
		# the bolts at the corners tighten, the two at mid-height lock (Alfa Laval's bolt layout, p. 35)
		var tight: Array = []
		var lock: Array = []
		for x: float in [-Wp * 0.62, Wp * 0.62]:
			for z: float in [0.4, H * 0.5, H - 0.4]:
				(lock if z == H * 0.5 else tight).append(Vector3(x, yf + 0.06, z))
		_bolts_y(g, "tightening_bolts", tight, 0.02, yf + 0.06 - (yb - 0.1), "steel", 0.04)
		_bolts_y(g, "locking_bolts", lock, 0.02, yf + 0.06 - (yb - 0.1), "steel", 0.04)
	var ws := {}
	for nz in ["hot_in", "hot_out", "cold_in", "cold_out"]:
		ws[nz] = ["frame_plate", ["frame_plate"]]
	_nozzles(g, ["hot_in", "hot_out", "cold_in", "cold_out"], "steel", 0.15, "pn16", ws if tree else {})
	g.plate("frame", Vector3(0, yf + 0.005, H * 0.55), Vector3(0, 1, 0), "large")
	g.solid_box(Vector3(-Wp * 0.6, yc - 0.12, 0), Vector3(Wp * 0.6, yf, H))
	g.axis_line = [Vector3(0, yc, H * 0.5), Vector3(0, yf, H * 0.5)]

## The plate pack's components: End plate II against the frame plate, the channel plates, End plate I against the
## pressure plate (Alfa Laval's names).
const PHE_PLATES := ["end_plate_2", "plates", "end_plate_1"]

## The plate heat exchanger's tree. The frame plate, the bars and the column stay; the bolts out, the pressure plate
## is pushed back along the carrying bar to the column; the plates come off the bars to the side, End plate I (next to
## the pressure plate, the first off) farthest.
static func _phe_comps(g, Wp: float, yb: float, yc: float) -> void:
	var up := Vector3(0, 0, 1)
	var side := Vector3(1, 0, 0)
	g.comp("frame_plate", {"explode": [up, 0.0]})
	g.comp("support_column", {"explode": [up, 0.0]})
	g.comp("carrying_bar", {"parent": "frame_plate", "explode": [up, 0.0]})
	g.comp("guiding_bar", {"parent": "frame_plate", "explode": [up, 0.0]})
	g.comp("pressure_plate", {"parent": "carrying_bar", "explode": [Vector3(0, -1, 0), yb - (yc + 0.12) - 0.03]})
	var w := Wp + 0.3
	for i in PHE_PLATES.size():
		g.comp(PHE_PLATES[i], {"parent": "carrying_bar", "explode": [side, w * (i + 1)]})

## The plate pack drawn as N plates side by side (the plant's pack and the plates' edges it draws on it; a picture:
## each as thick as several real plates), from the frame plate's side (End plate II) to the pressure plate's (End
## plate I), every other one darker.
static func _phe_plates(g, Wp: float, H: float, y0: float, y1: float, N: int) -> void:
	var m = g.m
	g.only("workshop", "split")
	for j in N:
		g.comp(PHE_PLATES[0] if j == 0 else (PHE_PLATES[2] if j == N - 1 else PHE_PLATES[1]))
		m.use("steel" if j % 2 == 0 else "steel_dark", "identify")
		m.box_lh(Vector3(-Wp * 0.5, y1 - (y1 - y0) * (j + 1) / N, 0.2), Vector3(Wp * 0.505 + 0.002, y1 - (y1 - y0) * j / N, H - 0.15))

static func cooling_tower(_part: String, g) -> void:
	var m = g.m
	var nx := int(g.num("cells_x", 5))
	var ny := int(g.num("cells_y", 2))
	var L: float = g.num("length", 80)
	var W: float = g.num("width", 32)
	var H: float = g.num("height", 14)
	var fan_d: float = g.num("fan_d", 9.5)
	var fill: String = g.p.get("fill", "film")
	var deck := false
	for d in g.ctx.get("decks", []):
		if absf(float(d) - H) <= 0.5:
			deck = true
	var top := H - 0.15 if deck else H
	var hin := clampf(H * 0.32, 2.5, 6.0)   # the air inlets' height
	var zfill := hin + 0.1
	var cx := L / nx
	var cy := W / ny
	# columns at the cells' corners round the outside, and the casing above the air inlets
	m.use("concrete", "form")
	for i in nx + 1:
		for j: int in [0, ny]:
			var x := -L * 0.5 + cx * i
			var y := -W * 0.5 + cy * j
			m.box_lh(Vector3(x - 0.25, y - 0.25, 0.2), Vector3(x + 0.25, y + 0.25, hin))
	m.use("paint_ct", "identify")
	for s: float in [-1.0, 1.0]:   # long sides: casing above the inlets
		m.box_lh(Vector3(-L * 0.5, s * W * 0.5 - 0.06, hin), Vector3(L * 0.5, s * W * 0.5 + 0.06, top))
	for s: float in [-1.0, 1.0]:   # ends: closed walls full height
		m.box_lh(Vector3(s * L * 0.5 - 0.06, -W * 0.5, 0.2), Vector3(s * L * 0.5 + 0.06, W * 0.5, top))
	m.use("paint_ct", "detail", 0.1)
	for i in range(1, int(L / 2.0)):   # the casing panels' ribs
		var x := -L * 0.5 + i * 2.0
		for s: float in [-1.0, 1.0]:
			m.box(Vector3(x, s * (W * 0.5 + 0.07), (hin + top) * 0.5), Vector3(0.08, 0.04, top - hin))
	# the air inlets: louvres in front of the dark rain zone, the fill seen through them
	for s: float in [-1.0, 1.0]:
		m.use("dark", "identify")
		m.box_lh(Vector3(-L * 0.5, s * (W * 0.5 - 1.0) - 0.02, 0.2), Vector3(L * 0.5, s * (W * 0.5 - 1.0) + 0.02, hin))
		if s > 0:
			m.use("fill", "identify")
			m.box_lh(Vector3(-L * 0.5 + 0.1, -W * 0.5 + 0.3, zfill), Vector3(L * 0.5 - 0.1, W * 0.5 - 0.3, zfill + 1.5))
		m.use("paint_ct", "identify")
		var nl := int((hin - 0.4) / 0.45)
		for k in nl:
			var z := 0.45 + k * 0.45
			m.box(Vector3(0, s * (W * 0.5 - 0.15), z), Vector3(L, 0.32, 0.03), Basis(Vector3(1, 0, 0), deg_to_rad(40.0) * s))
	if fill == "film":   # film fill's vertical sheets show as stripes at the inlets
		m.use("dark", "detail", 0.05)
		var k := int(L / 0.6)
		for s: float in [-1.0, 1.0]:
			for i in k:
				var x := -L * 0.5 + 0.3 + i * 0.6
				m.box(Vector3(x, s * (W * 0.5 - 0.31), zfill + 0.75), Vector3(0.05, 0.01, 1.4))
	# the partition walls between the cells, seen on the deck as lines (and inside, through the inlets)
	m.use("paint_ct", "form")
	for i in range(1, nx):
		var x := -L * 0.5 + cx * i
		m.box_lh(Vector3(x - 0.05, -W * 0.5 + 1.0, zfill + 1.5), Vector3(x + 0.05, W * 0.5 - 1.0, top))
	for j in range(1, ny):
		var y := -W * 0.5 + cy * j
		m.box_lh(Vector3(-L * 0.5, y - 0.05, 0.2), Vector3(L * 0.5, y + 0.05, top))
	if not deck:   # the fan deck, when the content has none (the content's is walkable)
		m.use("concrete", "form")
		var holes: Array = []
		for i in nx:
			for j in ny:
				holes.append(Vector2(-L * 0.5 + cx * (i + 0.5), -W * 0.5 + cy * (j + 0.5)))
		m.box_lh(Vector3(-L * 0.5, -W * 0.5, H - 0.25), Vector3(L * 0.5, -W * 0.5 + (cy - fan_d) * 0.5, H))
		m.box_lh(Vector3(-L * 0.5, W * 0.5 - (cy - fan_d) * 0.5, H - 0.25), Vector3(L * 0.5, W * 0.5, H))
	# the hot water: the header along the south face from the riser (kit.json hot_water_in), a branch into each cell
	var spec: Dictionary = g.ctx.get("nozzles", {}).get("hot_water_in", {})
	var od: float = g.ctx.get("used", {}).get("hot_water_in", 1.2)
	if not spec.is_empty():
		var p: Vector3 = g.nozzle(spec)
		var hz := p.z
		var hy := -W * 0.5 - 0.6 - od * 0.5
		m.use("galvanised", "identify")
		C.nozzle(m, Vector3(p.x, hy, hz), p, od, "galvanised")
		var ho := od * 0.6
		m.cyl(Vector3(-L * 0.5 + 2.0, hy, hz), Vector3(L * 0.5 - 2.0, hy, hz), ho * 0.5)
		m.use("galvanised", "form")
		for i in nx:
			var x := -L * 0.5 + cx * (i + 0.5)
			m.pipe_path([Vector3(x, hy, hz), Vector3(x, hy, hz + 0.0), Vector3(x, -W * 0.5 + 0.2, hz)], ho * 0.3, ho)
			m.use("paint_darkgrey", "identify")   # each cell's isolating valve (a butterfly with its gearbox)
			m.cyl(Vector3(x, hy + 0.3 + ho * 0.5, hz), Vector3(x, hy + 0.45 + ho * 0.5, hz), ho * 0.45)
			m.box(Vector3(x, hy + 0.37 + ho * 0.5, hz + ho * 0.5 + 0.15), Vector3(0.3, 0.25, 0.3))
			m.use("galvanised", "form")
		m.use("steel", "form")
		var k := maxi(2, int(L / 6.0))
		for i in k + 1:
			var x := -L * 0.5 + 2.0 + (L - 4.0) * i / k
			m.box_lh(Vector3(x - 0.08, hy - 0.08, hz - ho * 0.3 - 0.4), Vector3(x + 0.08, -W * 0.5, hz - ho * 0.3 - 0.25))
	var mspec: Dictionary = g.ctx.get("nozzles", {}).get("makeup_in", {})
	if not mspec.is_empty():
		var p: Vector3 = g.nozzle(mspec)
		C.nozzle(m, Vector3(L * 0.5 + 0.06, p.y, p.z), p, g.ctx.get("used", {}).get("makeup_in", 0.3), "galvanised")
	g.plate("basin", Vector3(L * 0.5 + 0.08, -W * 0.3, 1.8), Vector3(1, 0, 0), "large")
	g.solid_box(Vector3(-L * 0.5, -W * 0.5, 0), Vector3(L * 0.5, W * 0.5, top))
	g.axis_line = [Vector3(0, 0, 0), Vector3(0, 0, H)]
