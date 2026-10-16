## The HRSG and vessels (docs/PLANT3D.md §9 "HRSG", "Vessels"): the HRSG's casing with its inlet and outlet ducts,
## its modules, drums, the stack, ducts, vent silencers, tanks and vessels, the package boiler and open basins.
## Walkable surfaces the content describes on or round a part (an HRSG's roof deck, a stack's platform) are passed
## in ctx.decks (their heights above the part's origin): the part leaves room for them and draws no access of its
## own there (kit/README.md "Context").
extends RefCounted

const C = preload("res://kit/parts_common.gd")

static func _has_deck(g, z: float, tol := 0.5) -> bool:
	for d in g.ctx.get("decks", []):
		if absf(float(d) - z) <= tol:
			return true
	return false

## A rectangle's corners (x across, z up) at y: [x0, x1, z0, z1].
static func _rect_at(y: float, r: Array) -> Array:
	return [Vector3(r[0], y, r[2]), Vector3(r[1], y, r[2]), Vector3(r[1], y, r[3]), Vector3(r[0], y, r[3])]

static func hrsg(_part: String, g) -> void:
	var m = g.m
	var L: float = g.num("length", 55)
	var W: float = g.num("width", 22)
	var H: float = g.num("height", 30)
	var li: float = g.num("inlet_duct", 15)
	var lo: float = g.num("outlet_duct", 10)
	var top := H - 0.12 if _has_deck(g, H) else H   # under the content's roof deck
	# the foundation, the casing and its stiffeners (vertical buckstays: what makes a casing read as an HRSG's)
	m.use("concrete", "form")
	m.box_lh(Vector3(-W * 0.5 - 0.3, -L * 0.5 - 0.3, 0), Vector3(W * 0.5 + 0.3, L * 0.5 + 0.3, 0.5))
	m.use("corrugated_casing", "identify")
	m.box_lh(Vector3(-W * 0.5, -L * 0.5, 0.5), Vector3(W * 0.5, L * 0.5, top))
	m.use("paint_grey", "form")
	var nb := maxi(4, int(L / 3.0))
	for i in nb + 1:
		var y := -L * 0.5 + L * i / nb
		for s: float in [-1.0, 1.0]:
			m.box_lh(Vector3(s * W * 0.5 - 0.15, y - 0.15, 0.5), Vector3(s * W * 0.5 + 0.15, y + 0.15, top))
	m.use("paint_grey", "detail", 0.15)
	var z := 3.0
	while z < top - 1.0:   # horizontal stiffeners
		for s: float in [-1.0, 1.0]:
			m.box_lh(Vector3(s * W * 0.5 - 0.08, -L * 0.5, z), Vector3(s * W * 0.5 + 0.08, L * 0.5, z + 0.25))
		z += 3.0
	# the inlet duct: from the GT's diffuser duct (ctx.inlet = [w, h, zc], when a duct ends there) to the casing
	var inl: Array = g.ctx.get("inlet", [W * 0.4, H * 0.32, H * 0.16 + 0.5])
	var y0 := -L * 0.5 - li
	if li > 0.1:
		m.use("corrugated_casing", "identify")
		m.hexa(_rect_at(y0, [-inl[0] * 0.5, inl[0] * 0.5, inl[2] - inl[1] * 0.5, inl[2] + inl[1] * 0.5]) +
			_rect_at(-L * 0.5, [-W * 0.5, W * 0.5, 0.5, top]))
		m.use("paint_grey", "form")
		for f: float in [0.0, 0.5, 1.0]:   # the transition's frames
			var y := lerpf(y0, -L * 0.5, f)
			var w := lerpf(inl[0], W, f) * 0.5 + 0.12
			var z0 := lerpf(inl[2] - inl[1] * 0.5, 0.5, f) - 0.12
			var z1 := lerpf(inl[2] + inl[1] * 0.5, top, f) + 0.12
			m.box_lh(Vector3(-w, y - 0.15, z0), Vector3(w, y + 0.15, z0 + 0.25))
			m.box_lh(Vector3(-w, y - 0.15, z1 - 0.25), Vector3(w, y + 0.15, z1))
			m.box_lh(Vector3(-w, y - 0.15, z0), Vector3(-w + 0.25, y + 0.15, z1))
			m.box_lh(Vector3(w - 0.25, y - 0.15, z0), Vector3(w, y + 0.15, z1))
		m.use("paint_grey", "form")   # its supports
		for x: float in [-inl[0] * 0.4, inl[0] * 0.4]:
			m.box_lh(Vector3(x - 0.2, y0 + li * 0.35 - 0.2, 0), Vector3(x + 0.2, y0 + li * 0.35 + 0.2, inl[2] - inl[1] * 0.5))
	# the outlet duct: from the casing's end to the stack's side
	var sd: float = g.ctx.get("stack_d", 7.0)
	if lo > 0.1:
		var w1 := minf(sd * 0.8, W)
		var h1 := minf(sd * 1.2, top - 1.0)
		m.use("corrugated_casing", "identify")
		m.hexa(_rect_at(L * 0.5, [-W * 0.5, W * 0.5, 0.5, top]) + _rect_at(L * 0.5 + lo, [-w1 * 0.5, w1 * 0.5, 1.0, 1.0 + h1]))
		m.use("paint_grey", "form")
		m.box_lh(Vector3(-w1 * 0.5 - 0.15, L * 0.5 + lo * 0.6 - 0.2, 0), Vector3(-w1 * 0.5 + 0.25, L * 0.5 + lo * 0.6 + 0.2, 1.2))
		m.box_lh(Vector3(w1 * 0.5 - 0.25, L * 0.5 + lo * 0.6 - 0.2, 0), Vector3(w1 * 0.5 + 0.15, L * 0.5 + lo * 0.6 + 0.2, 1.2))
	# the nozzles (kit.json): steam out through the roof, feedwater and condensate in on the east side, the drain
	for n in ["hp_steam", "hrh_out", "crh_in", "lp_steam", "hp_fw_in", "lp_cond_in", "sh_drain"]:
		var spec: Dictionary = g.ctx.get("nozzles", {}).get(n, {})
		if spec.is_empty():
			continue
		var p: Vector3 = g.nozzle(spec)
		var od: float = g.ctx.get("used", {}).get(n, 0.3)
		var d := Vector3(0, 0, 1) if spec.dir == "up" else Vector3(1, 0, 0)
		var from := p - d * (0.6 if spec.dir == "up" else 0.4)
		if spec.dir == "up":
			from.z = top - 0.3
		C.nozzle(m, from, p, od, "cladding" if spec.dir == "up" else "paint_grey", "pn160")
	# access doors along the casing's sides at the bottom
	m.use("paint_darkgrey", "identify")
	for i in 4:
		var y := -L * 0.5 + L * (i + 0.5) / 4.0
		m.box(Vector3(W * 0.5 + 0.17, y, 1.6), Vector3(0.04, 0.9, 1.4))
	g.plate("casing", Vector3(W * 0.5 + 0.2, -L * 0.5 + 2.0, 2.5), Vector3(1, 0, 0), "large")
	g.solid_box(Vector3(-W * 0.5, -L * 0.5, 0), Vector3(W * 0.5, L * 0.5, top))
	g.axis_line = [Vector3(0, -L * 0.5, H * 0.5), Vector3(0, L * 0.5, H * 0.5)]

## A heating surface inside the casing (seen through its access door): the tube bank between its headers, and the
## access door with the module's plate on the casing's wall outside it.
static func hrsg_module(_part: String, g) -> void:
	var m = g.m
	var W: float = g.num("width", 20)
	var D: float = g.num("depth", 2.5)
	var H: float = g.num("height", 26)
	var kind: String = g.p.get("kind", "economiser")
	var mat: String = {"economiser": "paint_darkgrey", "evaporator": "steel_dark", "superheater": "steel", "reheater": "steel"}.get(kind, "steel")
	m.use(mat, "form")
	m.box_lh(Vector3(-W * 0.5, -D * 0.4, 0.3), Vector3(W * 0.5, D * 0.4, H - 0.6))
	m.use("cladding", "form")
	for z: float in [0.15, H - 0.3]:   # the headers
		m.cyl(Vector3(-W * 0.5, -D * 0.25, z), Vector3(W * 0.5, -D * 0.25, z), 0.2, -1.0, 12)
		m.cyl(Vector3(-W * 0.5, D * 0.25, z), Vector3(W * 0.5, D * 0.25, z), 0.2, -1.0, 12)
	# the access door on the casing wall (1 m beyond the module's end) with the module's plate beside it
	var xw := W * 0.5 + 1.0 + 0.2
	m.use("paint_darkgrey", "identify")
	m.box(Vector3(xw, 0, 0.8), Vector3(0.05, 0.7, 0.9))
	m.use("steel", "identify")
	m.box(Vector3(xw + 0.04, 0.25, 0.8), Vector3(0.03, 0.05, 0.2))
	g.plate("door", Vector3(xw + 0.03, -0.55, 1.0), Vector3(1, 0, 0), "large")
	g.axis_line = [Vector3(-W * 0.5, 0, H * 0.5), Vector3(W * 0.5, 0, H * 0.5)]

## A steam drum on its saddles: the shell with elliptical heads, the manways, the safety valves and vents on top,
## the level instruments' bridles; insulated and clad.
static func drum(_part: String, g) -> void:
	var m = g.m
	var d: float = g.num("d", 1.8)
	var L: float = g.num("length", 15)
	var ns := int(g.num("saddles", 2))
	var r := d * 0.5
	var zc := r + 0.1
	var hd := minf(d * 0.25, L * 0.2)
	var rc := r + 0.08   # with its insulation
	m.use("cladding", "identify")
	m.cyl(Vector3(0, -L * 0.5 + hd, zc), Vector3(0, L * 0.5 - hd, zc), rc, -1.0, 0, false)
	m.dish(Vector3(0, L * 0.5 - hd, zc), Vector3(0, 1, 0), rc, hd, 0, 5)
	m.dish(Vector3(0, -L * 0.5 + hd, zc), Vector3(0, -1, 0), rc, hd, 0, 5)
	m.use("cladding", "detail", 0.05)
	var k := maxi(2, int(L / 1.2))
	for i in range(1, k):   # the cladding's bands
		var y := -L * 0.5 + hd + (L - 2 * hd) * i / k
		m.cyl(Vector3(0, y - 0.02, zc), Vector3(0, y + 0.02, zc), rc + 0.012, -1.0)
	# saddles
	m.use("paint_darkgrey", "form")
	for i in ns:
		var y := lerpf(-L * 0.3, L * 0.3, float(i) / maxf(ns - 1, 1)) if ns > 1 else 0.0
		m.box_lh(Vector3(-r * 0.75, y - 0.15, 0), Vector3(r * 0.75, y + 0.15, zc - r * 0.55))
		m.box_lh(Vector3(-r * 0.9, y - 0.25, 0), Vector3(r * 0.9, y + 0.25, 0.04))
	# manways on both heads
	m.use("steel", "identify")
	for s: float in [-1.0, 1.0]:
		var c := Vector3(0, s * (L * 0.5 - hd * 0.25), zc)
		m.cyl(c, c + Vector3(0, s * (hd * 0.3 + 0.1), 0), 0.25, -1.0, 16)
		C.bolt_ring(m, c + Vector3(0, s * (hd * 0.3 + 0.08), 0), Vector3(0, 1, 0), 0.22, 12, 0.012, 0.06)
	# the nozzles (kit.json): steam out on top, water out and blowdown at the ends
	for n in ["steam_out", "water_out", "blowdown"]:
		var spec: Dictionary = g.ctx.get("nozzles", {}).get(n, {})
		if spec.is_empty():
			continue
		var p: Vector3 = g.nozzle(spec)
		var od: float = g.ctx.get("used", {}).get(n, clampf(d * 0.12, 0.06, 0.4))
		var dir: Vector3 = {"up": Vector3(0, 0, 1), "n": Vector3(0, 1, 0), "s": Vector3(0, -1, 0)}.get(spec.dir, Vector3(0, 0, 1))
		C.nozzle(m, p - dir * (0.45 if n != "steam_out" else 0.3), p, od, "cladding", "pn160")
	# two safety valves and a vent on top (red: they tell the drum from a header)
	for y: float in [-L * 0.3, -L * 0.2]:
		m.use("paint_red", "identify")
		m.cyl(Vector3(0, y, zc + rc - 0.05), Vector3(0, y, zc + rc + 0.25), 0.07, -1.0, 12)
		m.cyl(Vector3(0, y, zc + rc + 0.25), Vector3(0, y, zc + rc + 0.75), 0.11, 0.07, 12)
		m.cyl(Vector3(0, y, zc + rc + 0.35), Vector3(0.35, y, zc + rc + 0.35), 0.08, -1.0, 12)
		m.cyl(Vector3(0.35, y, zc + rc + 0.35), Vector3(0.35, y, zc + rc + 1.8), 0.09, -1.0, 12)
	# level bridles on the side: the instruments mount on them
	m.use("cladding", "form")
	for s: float in [-1.0, 1.0]:
		m.cyl(Vector3(s * (rc + 0.25), L * 0.05, zc - r * 0.8), Vector3(s * (rc + 0.25), L * 0.05, zc + r * 0.8), 0.06, -1.0, 10)
		for zz: float in [zc - r * 0.7, zc + r * 0.7]:
			m.cyl(Vector3(s * rc * 0.9, L * 0.05, zz), Vector3(s * (rc + 0.25), L * 0.05, zz), 0.04, -1.0, 8)
	g.plate("side", Vector3(rc + 0.01, -L * 0.25, zc), Vector3(1, 0, 0), "large")
	g.solid_cyl(Vector3(0, -L * 0.5, zc), Vector3(0, L * 0.5, zc), rc)
	g.axis_line = [Vector3(0, -L * 0.5, zc), Vector3(0, L * 0.5, zc)]

## The stack: the shell with its base and breeching, the aviation marking at the top, the stiffening rings, the
## sampling platform(s) with their ladder (not where the content has its own platforms: ctx.decks), the damper.
static func stack(_part: String, g) -> void:
	var m = g.m
	var d: float = g.num("d", 7)
	var H: float = g.num("height", 60)
	var n := int(g.num("platforms", 2))
	var r := d * 0.5
	m.use("concrete", "form")
	m.cyl(Vector3(0, 0, 0), Vector3(0, 0, 0.6), r + 0.6, -1.0)
	m.use("galvanised", "identify")
	m.cyl(Vector3(0, 0, 0.6), Vector3(0, 0, H * 0.82), r, -1.0, 0, false)
	m.use("paint_white", "identify")   # the top's red and white bands (aviation marking)
	m.cyl(Vector3(0, 0, H * 0.82), Vector3(0, 0, H * 0.88), r)
	m.cyl(Vector3(0, 0, H * 0.94), Vector3(0, 0, H), r, -1.0, 0, false)
	m.use("paint_red", "identify")
	m.cyl(Vector3(0, 0, H * 0.88), Vector3(0, 0, H * 0.94), r, -1.0, 0, false)
	m.use("dark", "identify")
	m.disk(Vector3(0, 0, H - 0.3), Vector3(0, 0, 1), r - 0.02)
	m.use("steel", "form")
	m.ring(Vector3(0, 0, H), Vector3(0, 0, 1), r - 0.02, r + 0.08)
	m.use("galvanised", "detail", 0.2)
	var z := 6.0
	while z < H - 2.0:   # stiffening rings
		m.cyl(Vector3(0, 0, z), Vector3(0, 0, z + 0.2), r + 0.1, -1.0)
		z += 6.0
	# platforms and the ladder, where the content has none
	var own: Array = []
	if g.ctx.get("decks", []).is_empty():
		for k in n:
			own.append(H * (k + 1) / (n + 1.5))
	for pz in own:
		m.use("grating", "form")
		m.ring(Vector3(0, 0, pz), Vector3(0, 0, 1), r, r + 1.2, 48)
		m.ring(Vector3(0, 0, pz - 0.05), Vector3(0, 0, -1), r, r + 1.2, 48)
		var pts: Array = []
		for i in 25:
			var a := TAU * i / 24.0
			pts.append(Vector2(cos(a), sin(a)) * (r + 1.15))
		C.rail_loop(m, pts, pz, false)
		m.use("steel", "detail", 0.15)
		for i in 8:   # the brackets under it
			var a := TAU * i / 8.0
			var dir := Vector3(cos(a), sin(a), 0)
			m.box(dir * (r + 0.6) + Vector3(0, 0, pz - 0.3), (dir * 1.2).abs() + Vector3(0.08, 0.08, 0.5) - (dir * 0.0).abs())
		m.use("steel_dark", "detail", 0.1)
		for i in 3:   # sampling ports
			var a := TAU * i / 3.0 + 0.4
			m.cyl(Vector3(cos(a), sin(a), 0) * r + Vector3(0, 0, pz + 1.2), Vector3(cos(a), sin(a), 0) * (r + 0.25) + Vector3(0, 0, pz + 1.2), 0.08, -1.0, 8)
	if not own.is_empty():
		C.ladder(m, Vector3(r + 0.25, 0, 0.6), own[-1], Vector2(-1, 0))
	if g.p.get("damper", false):
		m.use("paint_darkgrey", "identify")
		m.box(Vector3(r + 0.4, 0, H * 0.75), Vector3(0.6, 0.6, 0.8))
		m.cyl(Vector3(-r, 0, H * 0.75), Vector3(r + 0.1, 0, H * 0.75), 0.08, -1.0, 8)
	g.plate("base", Vector3(0, -r - 0.01, 1.8), Vector3(0, -1, 0), "large")
	g.solid_cyl(Vector3(0, 0, 0), Vector3(0, 0, H), r)
	g.axis_line = [Vector3(0, 0, 0), Vector3(0, 0, H)]

## A rectangular duct along its route (part frame), with its flanged joints and stiffeners; expansion joints
## (`joints`) as darker fabric bands.
static func duct(_part: String, g) -> void:
	var m = g.m
	var route: Array = g.p.get("route", [])
	var W: float = g.num("width", 10)
	var H: float = g.num("height", 10)
	var nj := int(g.num("joints", 1))
	if route.size() < 2:
		return
	var pts: Array = []
	for q in route:
		pts.append(Vector3(float(q[0]), float(q[1]), float(q[2]) if q.size() > 2 else 0.0))
	var total := 0.0
	for i in range(pts.size() - 1):
		total += pts[i].distance_to(pts[i + 1])
	var acc := 0.0
	for i in range(pts.size() - 1):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var dl := a.distance_to(b)
		if dl < 0.01:
			continue
		var dir := (b - a) / dl
		var side := dir.cross(Vector3(0, 0, 1)).normalized() if absf(dir.z) < 0.9 else Vector3(1, 0, 0)
		var up := side.cross(dir).normalized()
		var bs := Basis(side, dir, up)
		m.use("corrugated_casing", "identify")
		m.box((a + b) * 0.5, Vector3(W, dl, H), bs)
		m.use("paint_grey", "form")
		var k := maxi(1, int(dl / 3.0))
		for j in k + 1:   # stiffening frames
			var c := a + dir * (dl * j / k)
			m.box(c, Vector3(W + 0.3, 0.2, H + 0.3), bs)
		m.use("rubber", "identify")
		for j in nj:   # the expansion joints: grey fabric bellows
			var f := (j + 1.0) / (nj + 1.0) * total
			if f >= acc and f < acc + dl:
				m.box(a + dir * (f - acc), Vector3(W + 0.12, 0.6, H + 0.12), bs)
		acc += dl
	m.use("paint_grey", "form")   # supports under the first and last frames
	for q in [pts[0], pts[-1]]:
		var bottom: float = q.z - H * 0.5
		if bottom > 0.3:
			for s: float in [-1.0, 1.0]:
				m.box_lh(Vector3(q.x - 0.2, q.y + s * W * 0.4 - 0.2, 0), Vector3(q.x + 0.2, q.y + s * W * 0.4 + 0.2, bottom))
	g.plate("side", pts[0] + (pts[1] - pts[0]).normalized() * 2.0 + Vector3(0, -W * 0.5 - 0.17, -H * 0.2), Vector3(0, -1, 0), "large")
	g.axis_line = [pts[0], pts[-1]]

## A vent silencer: the shell on its stand, the inlet at the bottom, a rain cap.
static func silencer(_part: String, g) -> void:
	var m = g.m
	var d: float = g.num("d", 1.2)
	var H: float = g.num("height", 4)
	var r := d * 0.5
	m.use("galvanised", "identify")
	m.cyl(Vector3(0, 0, 0.5), Vector3(0, 0, H), r, -1.0, 0, false)
	m.lathe(Vector3(0, 0, 0.2), Vector3(0, 0, 1), [[r * 0.4, 0.0], [r, 0.3]], 0, true)
	m.use("dark", "identify")
	m.disk(Vector3(0, 0, H - 0.1), Vector3(0, 0, 1), r * 0.95)
	m.use("galvanised", "form")
	m.ring(Vector3(0, 0, H), Vector3(0, 0, 1), r * 0.95, r)
	for k in 4:   # the stand
		var a := TAU * (k + 0.5) / 4.0
		m.box_lh(Vector3(cos(a) * r * 0.8 - 0.05, sin(a) * r * 0.8 - 0.05, 0), Vector3(cos(a) * r * 0.8 + 0.05, sin(a) * r * 0.8 + 0.05, 0.6))
	var spec: Dictionary = g.ctx.get("nozzles", {}).get("inlet", {})
	if not spec.is_empty():
		var p: Vector3 = g.nozzle(spec)
		var od: float = g.ctx.get("used", {}).get("inlet", clampf(d * 0.3, 0.1, 0.6))
		C.nozzle(m, Vector3(0, -r * 0.5, p.z), p, od, "galvanised")
	g.plate("side", Vector3(r + 0.01, 0, 1.2), Vector3(1, 0, 0), "small")
	g.solid_cyl(Vector3(0, 0, 0), Vector3(0, 0, H), r)
	g.axis_line = [Vector3(0, 0, 0), Vector3(0, 0, H)]

## A vertical tank: shell courses, roof (cone, dome or open), the spiral or caged ladder, a roof rail, manway,
## nozzles.
static func tank_vertical(_part: String, g) -> void:
	var m = g.m
	var d: float = g.num("d", 8)
	var H: float = g.num("height", 10)
	var roof: String = g.p.get("roof", "cone")
	var r := d * 0.5
	m.use("concrete", "form")
	m.cyl(Vector3(0, 0, 0), Vector3(0, 0, 0.3), r + 0.3, -1.0)
	m.use("paint_tank", "identify")
	m.cyl(Vector3(0, 0, 0.3), Vector3(0, 0, H), r, -1.0, 0, false)
	m.use("paint_tank", "detail", 0.04)
	var z := 2.0
	while z < H - 0.5:   # the shell courses' seams
		m.cyl(Vector3(0, 0, z - 0.015), Vector3(0, 0, z + 0.015), r + 0.008, -1.0)
		z += 2.0
	m.use("paint_tank", "identify")
	match roof:
		"cone":
			m.lathe(Vector3(0, 0, H), Vector3(0, 0, 1), [[r + 0.05, 0.0], [0.0, r * 0.2]], 0, false)
		"dome":
			m.dish(Vector3(0, 0, H), Vector3(0, 0, 1), r + 0.05, r * 0.3, 0, 6)
		_:
			m.use("water", "identify")
			m.disk(Vector3(0, 0, H - 0.6), Vector3(0, 0, 1), r - 0.02)
			m.use("paint_tank", "identify")
			m._inner(Vector3(0, 0, H - 0.6), Vector3(0, 0, H), r - 0.01, m.segs(r))
	if roof != "open" and d > 3.0:
		var pts: Array = []
		for i in 25:
			var a := TAU * i / 24.0
			pts.append(Vector2(cos(a), sin(a)) * (r - 0.1))
		m.use("paint_yellow", "form")
		for i in 24:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			m.cyl(Vector3(a.x, a.y, H + 1.1), Vector3(b.x, b.y, H + 1.1), 0.022, -1.0, 6, false)
			if i % 2 == 0:
				m.cyl(Vector3(a.x, a.y, H), Vector3(a.x, a.y, H + 1.1), 0.022, -1.0, 6, false)
	# a caged ladder (small tanks) or a stair round the shell (large ones)
	if H > 2.5:
		C.ladder(m, Vector3(0, -r - 0.45, 0.3), H, Vector2(0, 1))
	m.use("steel", "identify")   # the shell manway
	m.cyl(Vector3(r * 0.71, -r * 0.71, 0.9), Vector3(r * 0.71 + 0.2, -r * 0.71 - 0.2, 0.9), 0.32, -1.0, 16)
	for n in ["inlet", "outlet"]:
		var spec: Dictionary = g.ctx.get("nozzles", {}).get(n, {})
		if spec.is_empty():
			continue
		var p: Vector3 = g.nozzle(spec)
		var od: float = g.ctx.get("used", {}).get(n, clampf(d * 0.04, 0.06, 0.6))
		var dir := Vector3(0, 1, 0) if spec.dir == "n" else Vector3(0, -1, 0)
		C.nozzle(m, Vector3(p.x, p.y - dir.y * 0.5, p.z), p, od, "paint_tank")
	g.plate("side", Vector3(r + 0.01, 0, 1.6), Vector3(1, 0, 0), "large")
	g.solid_cyl(Vector3(0, 0, 0), Vector3(0, 0, H), r)
	g.axis_line = [Vector3(0, 0, 0), Vector3(0, 0, H)]

## A horizontal vessel on its saddles: shell, dished heads, manway, nozzles.
static func vessel_horizontal(_part: String, g) -> void:
	_horizontal(g, "paint_tank")

static func _horizontal(g, mat: String) -> Dictionary:
	var m = g.m
	var d: float = g.num("d", 2)
	var L: float = g.num("length", 6)
	var ns := int(g.num("saddles", 2))
	var r := d * 0.5
	var zc := r + 0.5
	var hd := minf(d * 0.25, L * 0.2)
	m.use(mat, "identify")
	m.cyl(Vector3(0, -L * 0.5 + hd, zc), Vector3(0, L * 0.5 - hd, zc), r, -1.0, 0, false)
	m.dish(Vector3(0, L * 0.5 - hd, zc), Vector3(0, 1, 0), r, hd, 0, 5)
	m.dish(Vector3(0, -L * 0.5 + hd, zc), Vector3(0, -1, 0), r, hd, 0, 5)
	m.use("paint_darkgrey", "form")
	for i in ns:
		var y := lerpf(-L * 0.3, L * 0.3, float(i) / maxf(ns - 1, 1)) if ns > 1 else 0.0
		m.box_lh(Vector3(-r * 0.75, y - 0.12, 0), Vector3(r * 0.75, y + 0.12, zc - r * 0.5))
		m.box_lh(Vector3(-r * 0.85, y - 0.2, 0), Vector3(r * 0.85, y + 0.2, 0.04))
	m.use("steel", "identify")
	m.cyl(Vector3(0, 0, zc + r - 0.05), Vector3(0, 0, zc + r + 0.3), 0.3, -1.0, 16)
	for n in ["inlet", "outlet", "vent"]:
		var spec: Dictionary = g.ctx.get("nozzles", {}).get(n, {})
		if spec.is_empty():
			continue
		var p: Vector3 = g.nozzle(spec)
		var od: float = g.ctx.get("used", {}).get(n, clampf(d * 0.08, 0.06, 0.5))
		var dir: Vector3 = {"up": Vector3(0, 0, 1), "n": Vector3(0, 1, 0), "s": Vector3(0, -1, 0)}.get(spec.dir, Vector3(0, 0, 1))
		C.nozzle(m, p - dir * 0.5, p, od, mat)
	g.plate("side", Vector3(r + 0.01, 0, zc), Vector3(1, 0, 0), "large")
	g.solid_cyl(Vector3(0, -L * 0.5, zc), Vector3(0, L * 0.5, zc), r)
	g.axis_line = [Vector3(0, -L * 0.5, zc), Vector3(0, L * 0.5, zc)]
	return {"r": r, "zc": zc, "L": L}

## A package (fire-tube) boiler: the shell on its skid, the burner and its fan at the front, the flue at the back,
## the steam outlet on top, the control panel.
static func package_boiler(_part: String, g) -> void:
	var m = g.m
	var d: float = g.num("d", 3)
	var L: float = g.num("length", 8)
	var r := d * 0.5
	var zc := r + 0.5
	C.baseplate(m, Vector3(-r * 0.9, -L * 0.5, 0), Vector3(r * 0.9, L * 0.5, 0.3))
	m.use("paint_machine", "identify")
	m.cyl(Vector3(0, -L * 0.5 + 0.6, zc), Vector3(0, L * 0.5 - 0.6, zc), r)
	m.use("paint_darkgrey", "form")
	m.cyl(Vector3(0, L * 0.5 - 0.6, zc), Vector3(0, L * 0.5 - 0.4, zc), r * 1.02)   # the front's flange (the door)
	m.use("paint_red", "identify")   # the burner and its fan housing at the front
	m.cyl(Vector3(0, L * 0.5 - 0.4, zc), Vector3(0, L * 0.5 + 0.4, zc), r * 0.4, r * 0.3)
	m.box(Vector3(0, L * 0.5 + 0.2, zc - r * 0.6), Vector3(r * 0.8, 0.8, r * 0.6))
	m.use("paint_darkgrey", "identify")   # the flue at the back, going up
	m.pipe_path([Vector3(0, -L * 0.5 + 0.6, zc), Vector3(0, -L * 0.5 - 0.5, zc), Vector3(0, -L * 0.5 - 0.5, zc + r + 3.0)], r * 0.35, r * 0.7)
	var spec: Dictionary = g.ctx.get("nozzles", {}).get("steam_out", {})
	if not spec.is_empty():
		var p: Vector3 = g.nozzle(spec)
		C.nozzle(m, Vector3(0, 0, zc + r - 0.05), p, g.ctx.get("used", {}).get("steam_out", 0.2), "paint_machine", "pn40")
	m.use("paint_red", "identify")   # the safety valves
	for x: float in [-0.4, 0.4]:
		m.cyl(Vector3(x, L * 0.2, zc + r - 0.05), Vector3(x, L * 0.2, zc + r + 0.6), 0.08, -1.0, 12)
	m.use("paint_grey", "identify")   # the control panel at the side
	m.box(Vector3(r + 0.4, L * 0.35, 1.2), Vector3(0.4, 1.0, 1.8))
	m.use("glass", "identify")
	m.box(Vector3(r + 0.6, L * 0.35, 1.5), Vector3(0.01, 0.5, 0.3))
	m.use("glass", "identify")   # the level glasses on the shell's front
	for x: float in [-r * 0.6, r * 0.6]:
		m.box(Vector3(x, L * 0.5 - 0.35, zc + r * 0.4), Vector3(0.06, 0.05, 0.6))
	g.plate("side", Vector3(r + 0.01, -L * 0.2, zc), Vector3(1, 0, 0), "large")
	g.solid_cyl(Vector3(0, -L * 0.5, zc), Vector3(0, L * 0.5, zc), r)
	g.axis_line = [Vector3(0, -L * 0.5, zc), Vector3(0, L * 0.5, zc)]

## An open concrete basin: walls, water at its level, a rail round it. The origin is at the basin's floor.
static func basin(_part: String, g) -> void:
	var m = g.m
	var L: float = g.num("length", 80)
	var W: float = g.num("width", 32)
	var D: float = g.num("depth", 2)
	var t := 0.3
	m.use("concrete", "form")
	m.box_lh(Vector3(-L * 0.5 - t, -W * 0.5 - t, -0.3), Vector3(L * 0.5 + t, W * 0.5 + t, 0.0))
	m.box_lh(Vector3(-L * 0.5 - t, W * 0.5, 0), Vector3(L * 0.5 + t, W * 0.5 + t, D + 0.25))
	m.box_lh(Vector3(-L * 0.5 - t, -W * 0.5 - t, 0), Vector3(L * 0.5 + t, -W * 0.5, D + 0.25))
	m.box_lh(Vector3(L * 0.5, -W * 0.5, 0), Vector3(L * 0.5 + t, W * 0.5, D + 0.25))
	m.box_lh(Vector3(-L * 0.5 - t, -W * 0.5, 0), Vector3(-L * 0.5, W * 0.5, D + 0.25))
	m.use("water", "identify")
	# the water stands just above the ground round it (a cooling tower's basin is at grade)
	m.box_lh(Vector3(-L * 0.5, -W * 0.5, D + 0.03), Vector3(L * 0.5, W * 0.5, D + 0.05))
	g.plate("edge", Vector3(L * 0.5 + t + 0.01, 0, D + 0.1), Vector3(1, 0, 0), "large")
	g.axis_line = [Vector3(-L * 0.5, 0, D), Vector3(L * 0.5, 0, D)]
