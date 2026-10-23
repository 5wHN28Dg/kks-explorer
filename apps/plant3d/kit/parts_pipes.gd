## Pipes (docs/PLANT3D.md §4, §9 "Pipes"): a route with bends of 1.5 × OD (or 3d, 5d), metal cladding over the
## insulation, the medium's colour bands and flow arrows (identify: they say what flows where, on every tier), the
## mating flanges at the nozzles, bare pipe where a valve or an instrument sits in insulated pipe, and the supports
## the builder places at the span table's spacing on whatever stands below (kit/README.md "Pipes").
## The standalone pipe parts (elbow, tee, reducer, flange, pipe_support) are here too.
extends RefCounted

const C = preload("res://kit/parts_common.gd")

## Maximum span between supports of a water-filled steel pipe by DN (ASME B31.1 Table 121.5 to DN 600, then
## extrapolated and capped at 12 m: README "Tables").
const SPANS := [[25, 2.1], [50, 3.0], [80, 3.7], [100, 4.3], [150, 5.2], [200, 5.8], [300, 7.0], [400, 8.2],
	[500, 8.8], [600, 9.8], [800, 11.0], [1000, 12.0]]

static func span(dn: float) -> float:
	for row in SPANS:
		if dn <= row[0]:
			return row[1]
	return 12.0

## The pieces of a route: straight runs (trimmed by the bends) and bends, with their distance along the route.
## pts: the route (plant coordinates); bend_r: the bends' radius. Returns {runs: [{a, b, s0, s1, seg}], bends: [{c, u,
## w, R, angle, seg}]}; seg is the route segment's index (for `buried`).
static func pieces(pts: Array, bend_r: float) -> Dictionary:
	var m := pts.size()
	var starts: Array = []
	var ends: Array = []
	for i in m - 1:
		starts.append(pts[i])
		ends.append(pts[i + 1])
	var bends: Array = []
	for i in range(1, m - 1):
		var d0: Vector3 = (pts[i] - pts[i - 1]).normalized()
		var d1: Vector3 = (pts[i + 1] - pts[i]).normalized()
		var th := acos(clampf(d0.dot(d1), -1.0, 1.0))
		if th < 0.01:
			continue
		var cut := bend_r * tan(th * 0.5)
		cut = minf(cut, minf(pts[i].distance_to(pts[i - 1]), pts[i].distance_to(pts[i + 1])) * 0.5)
		var rr := cut / tan(th * 0.5)
		ends[i - 1] = pts[i] - d0 * cut
		starts[i] = pts[i] + d1 * cut
		var inward := (d1 - d0).normalized()
		var centre: Vector3 = pts[i] + inward * (rr / cos(th * 0.5))
		bends.append({"c": centre, "u": (ends[i - 1] - centre).normalized(), "w": d0, "R": rr, "angle": th, "seg": i})
	var runs: Array = []
	var s := 0.0
	for i in m - 1:
		var a: Vector3 = starts[i]
		var b: Vector3 = ends[i]
		var s0: float = s + pts[i].distance_to(a)
		runs.append({"a": a, "b": b, "s0": s0, "s1": s0 + a.distance_to(b), "seg": i})
		s += pts[i].distance_to(pts[i + 1])
	return {"runs": runs, "bends": bends}

## A pipe into mesh builder m (plant coordinates relative to `origin`).
##   p: {od (m), ins (m), band (material name), paint (bare pipe's material name, default paint_pipe), arrows (m, 0 = none), buried: {seg: true}, gaps: [[s0, s1], …] (bare
##       stretches along the route: valves and instruments in insulated pipe), flanges: [point, dir] (the route's ends
##       on nozzles), supports: [{at, z_to, kind}], bend: factor of OD}
static func pipe(m, pts: Array, p: Dictionary, origin: Vector3) -> void:
	var od: float = p.od
	var ins: float = p.get("ins", 0.0)
	var r := od * 0.5
	var rr := r + ins
	var buried: Dictionary = p.get("buried", {})
	var gaps: Array = p.get("gaps", [])
	var body: String = "cladding" if ins > 0.0 else p.get("paint", "paint_pipe")   # bare: painted by what it carries
	var local: Array = []
	for q in pts:
		local.append(q - origin)
	var pc := pieces(local, od * float(p.get("bend", 1.5)))
	var n: int = m.segs(rr, 8, 40)
	# bends
	m.use(body, "form")
	for b in pc.bends:
		if buried.has(b.seg - 1) or buried.has(b.seg):
			continue
		m.torus(b.c, b.u, b.w, b.R, rr, b.angle, clampi(int(ceil(b.angle / 0.2)), 3, 12), n)
	# straight runs, bare where a gap is, with the cladding's end rings
	var bands: Array = []
	for run in pc.runs:
		if buried.has(run.seg):
			continue
		var a: Vector3 = run.a
		var b: Vector3 = run.b
		var len := a.distance_to(b)
		if len < 1e-3:
			continue
		var d := (b - a) / len
		var cuts: Array = [[0.0, len, false]]
		if ins > 0.0:
			cuts = []
			var t := 0.0
			var gs: Array = []
			for g in gaps:
				var g0: float = clampf(float(g[0]) - run.s0, 0.0, len)
				var g1: float = clampf(float(g[1]) - run.s0, 0.0, len)
				if g1 > g0 + 1e-3:
					gs.append([g0, g1])
			gs.sort_custom(func(x, y): return x[0] < y[0])
			for g in gs:
				if g[0] > t:
					cuts.append([t, g[0], false])
				cuts.append([maxf(g[0], t), g[1], true])
				t = maxf(t, g[1])
			if t < len:
				cuts.append([t, len, false])
		for c in cuts:
			var pa: Vector3 = a + d * c[0]
			var pb: Vector3 = a + d * c[1]
			if pa.distance_to(pb) < 1e-3:
				continue
			if c[2]:
				m.use("steel", "form")
				m.cyl(pa, pb, r, -1.0, m.segs(r, 8, 40), false)
				m.use("cladding", "detail", ins)
				if c[0] > 1e-3:
					m.ring(pa, -d, r, rr, n)
				if c[1] < len - 1e-3:
					m.ring(pb, d, r, rr, n)
			else:
				m.use(body, "form")
				# in pieces of at most 6 m, so the builder can give each its cell (decision 0041)
				var np := maxi(1, int(ceil(pa.distance_to(pb) / 6.0)))
				for q in np:
					m.cyl(pa.lerp(pb, float(q) / np), pa.lerp(pb, float(q + 1) / np), rr, -1.0, n, false)
				bands.append([pa, pb, d, run.s0 + c[0]])
	# the cladding's end rings at the route's ends
	if ins > 0.0 and local.size() >= 2:
		m.use("cladding", "detail", ins)
		if not buried.has(0):
			m.ring(local[0], (local[0] - local[1]).normalized(), r, rr, n)
		if not buried.has(local.size() - 2):
			m.ring(local[-1], (local[-1] - local[-2]).normalized(), r, rr, n)
	# colour bands and flow arrows (DIN 2403's idea: the band says the medium, the arrow the direction)
	var every: float = p.get("arrows", 0.0)
	var band_every := every if every > 0.0 else 12.0
	var bw := clampf(od * 0.6, 0.12, 0.5)
	for bd in bands:
		var pa: Vector3 = bd[0]
		var pb: Vector3 = bd[1]
		var d: Vector3 = bd[2]
		var len := pa.distance_to(pb)
		if len < bw * 4.0:
			continue
		var k := maxi(1, int(round(len / band_every)))
		for i in k:
			var t := len * (i + 0.5) / k
			var c := pa + d * t
			m.use(p.band, "identify")
			m.cyl(c - d * bw * 0.5, c + d * bw * 0.5, rr * 1.015 + 0.002, -1.0, n, false)
			if every > 0.0:
				_arrow(m, c + d * (bw * 0.5 + 0.05), d, rr * 1.015 + 0.002, clampf(od * 1.4, 0.3, 1.2))
	# mating flanges at nozzles
	for f in p.get("flanges", []):
		C.flange(m, f[0] - origin - f[1] * C.flange_dims(od).tf, -f[1], od, "steel", p.get("rating", "pn16"), true)
	# supports
	for s in p.get("supports", []):
		if s.kind == "bridge":
			_bridge(m, s.at - origin, rr, s.legs.map(func(l): return {"at": l.at - origin, "z": l.z - origin.z,
				"foot": float(l.get("foot", 0.02))}), s.dir)
		else:
			_support(m, s.at - origin, s.z_to - origin.z, rr, s.get("kind", "shoe"), s.get("dir", Vector3(1, 0, 0)),
				float(s.get("foot", 0.02)))

## A flow arrow lying on the pipe's surface on both sides (and on top for a horizontal run): a shaft and a head.
static func _arrow(m, start: Vector3, d: Vector3, r: float, len: float) -> void:
	var up := Vector3(0, 0, 1)
	var sides: Array = []
	if absf(d.z) < 0.9:
		var s := d.cross(up).normalized()
		sides = [s, -s, up]
	else:
		sides = [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0)]
	var w := clampf(len * 0.18, 0.04, 0.2)
	for n in sides:
		var o: Vector3 = start + n * (r + 0.003)
		var across: Vector3 = d.cross(n).normalized()
		m.box(o + d * len * 0.3, Vector3(w * 0.45, len * 0.6, 0.004), Basis(across, d, n))
		_head(m, o + d * len * 0.6, d, across, n, w, len * 0.4)

static func _head(m, base: Vector3, d: Vector3, across: Vector3, n: Vector3, w: float, l: float) -> void:
	var a: Vector3 = base - across * w
	var b: Vector3 = base + d * l
	var c: Vector3 = base + across * w
	m.poly([a, c, b] if d.cross(across).dot(n) < 0.0 else [a, b, c], n)

## A support under (or over) a pipe: a shoe (or a clamp) and a post down to z_to (or a rod up to it).
## Its post's base plate is `foot` thick (builder/kit_place.gd `_foot`: thicker where another plate lies beside it).
static func _support(m, at: Vector3, z_to: float, r: float, kind: String, dir: Vector3, foot := 0.02) -> void:
	var side := dir.cross(Vector3(0, 0, 1)).normalized() if absf(dir.z) < 0.9 else Vector3(1, 0, 0)
	if z_to > at.z:   # a hanger from above
		m.use("galvanised", "form")
		m.cyl(at + Vector3(0, 0, r), Vector3(at.x, at.y, z_to), 0.015, -1.0, 6)
		m.use("galvanised", "detail", 0.04)
		m.torus(at, side, Vector3(0, 0, 1), r + 0.02, 0.012, TAU, 16, 6)
		return
	var bottom := at.z - r
	m.use("steel", "form")
	var sw := clampf(r * 1.2, 0.12, 0.6)
	var fl := Vector3(dir.x, dir.y, 0).normalized() if Vector2(dir.x, dir.y).length() > 0.01 else Vector3(0, 1, 0)
	var bs := Basis(side, fl, Vector3(0, 0, 1))
	m.box(Vector3(at.x, at.y, bottom - 0.05), Vector3(sw, clampf(r * 2.0, 0.2, 0.8), 0.1), bs)
	if kind == "guide":
		m.use("steel", "detail", 0.05)
		for s: float in [-1.0, 1.0]:
			m.box(Vector3(at.x, at.y, bottom - 0.05) + side * (sw * 0.5 + 0.03) * s, Vector3(0.04, 0.2, 0.12), bs)
	var h := bottom - 0.1 - z_to
	if h > 0.05:
		m.use("galvanised", "form")
		var pw := 0.1 if h < 2.0 else (0.2 if h < 8.0 else 0.3)
		m.box(Vector3(at.x, at.y, z_to + h * 0.5), Vector3(pw, pw, h))
		m.box(Vector3(at.x, at.y, z_to + foot * 0.5), Vector3(pw * 2.5, pw * 2.5, foot))
		if h > 8.0:   # a tall trestle: a second leg and its bracing
			var o := side * 1.2
			m.box(Vector3(at.x, at.y, z_to + h * 0.5) + o, Vector3(pw, pw, h))
			m.box(Vector3(at.x, at.y, bottom - 0.25) + o * 0.5, Vector3(1.4, pw, 0.2), bs)
			var z := z_to + 3.0
			while z < bottom - 2.0:
				m.box(Vector3(at.x, at.y, z) + o * 0.5, Vector3(1.2, 0.1, 0.12), bs)
				z += 3.0

## A pipe bridge: two legs beside the walkway, a beam under the pipe between them, the shoe on the beam.
static func _bridge(m, at: Vector3, r: float, legs: Array, dir: Vector3) -> void:
	var bz := at.z - r - 0.15
	m.use("galvanised", "form")
	var a: Vector3 = legs[0].at
	var c: Vector3 = legs[1].at
	for l in legs:
		var h: float = bz - l.z
		if h > 0.05:
			m.box(Vector3(l.at.x, l.at.y, l.z + h * 0.5), Vector3(0.2, 0.2, h))
			var ft: float = l.get("foot", 0.02)
			m.box(Vector3(l.at.x, l.at.y, l.z + ft * 0.5), Vector3(0.45, 0.45, ft))
	m.cyl(Vector3(a.x, a.y, bz), Vector3(c.x, c.y, bz), 0.12, -1.0, 4)
	m.use("steel", "form")
	var side := dir.cross(Vector3(0, 0, 1)).normalized()
	var fl := Vector3(dir.x, dir.y, 0).normalized() if Vector2(dir.x, dir.y).length() > 0.01 else Vector3(0, 1, 0)
	m.box(Vector3(at.x, at.y, bz + 0.1), Vector3(clampf(r * 1.2, 0.12, 0.6), clampf(r * 2.0, 0.2, 0.8), 0.08), Basis(side, fl, Vector3(0, 0, 1)))

# ------------------------------------------------------------------ the standalone pipe parts

static func elbow(_part: String, g) -> void:
	var od: float = g.od(g.num("dn", 100))
	var R := od * 1.5
	g.m.use("paint_grey", "form")
	g.m.torus(Vector3(R, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), R, od * 0.5, PI * 0.5)

static func tee(_part: String, g) -> void:
	var od: float = g.od(g.num("dn", 100))
	g.m.use("paint_grey", "form")
	g.m.cyl(Vector3(0, -od, 0), Vector3(0, od, 0), od * 0.5)
	g.m.cyl(Vector3(0, 0, 0), Vector3(od, 0, 0), od * 0.5)

static func reducer(_part: String, g) -> void:
	var od: float = g.od(g.num("dn", 100))
	var od2: float = g.od(g.num("dn2", 80))
	g.m.use("paint_grey", "form")
	g.m.cyl(Vector3(0, -od * 0.75, 0), Vector3(0, od * 0.75, 0), od * 0.5, od2 * 0.5)

static func flange(_part: String, g) -> void:
	var od: float = g.od(g.num("dn", 100))
	C.flange_pair(g.m, Vector3.ZERO, Vector3(0, 1, 0), od, "steel")

static func pipe_support(_part: String, g) -> void:
	_support(g.m, Vector3(0, 0, 1.0), 0.0, 0.1, g.p.get("kind", "shoe"), Vector3(0, 1, 0))
