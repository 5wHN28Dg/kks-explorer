## Pieces many parts share: flanges with their bolts, nozzle stubs, baseplates, motors, lifting lugs, handrails and
## ladders on equipment. Dimensions follow kit/README.md "Tables".
extends RefCounted

## A flange's outside diameter, thickness and bolts for a pipe of outside diameter od (m) (EN 1092-1 PN 16 sizes,
## rounded: README "Tables"). Higher ratings are thicker.
static func flange_dims(od: float, rating := "pn16") -> Dictionary:
	var pn := float(rating.trim_prefix("pn")) if rating.begins_with("pn") else 16.0
	var k := 1.0 + clampf((pn - 16.0) / 250.0, 0.0, 1.0) * 0.6
	var df := od + 2.0 * clampf(0.035 + 0.12 * od, 0.04, 0.13) * k
	var tf := clampf(0.012 + 0.06 * od, 0.016, 0.09) * k
	var n := 4 * maxi(1, int(round((4.0 + 22.0 * od) / 4.0)))
	var br := clampf(0.006 + 0.012 * od, 0.007, 0.03) * sqrt(k)
	return {"df": df, "tf": tf, "n": n, "bolt_r": br, "pcd": (od * 0.5 + df * 0.5) * 0.5 + br * 0.3}

## A flange at c facing d (the face is at c, the flange's body runs back along -d), with its bolts (detail).
static func flange(m, c: Vector3, d: Vector3, od: float, mat: String, rating := "pn16", bolts := true) -> void:
	var f := flange_dims(od, rating)
	m.use(mat, "form")
	m.cyl(c - d * f.tf, c, f.df * 0.5, -1.0, m.segs(f.df * 0.5, 10, 40))
	m.cyl(c - d * (f.tf * 2.2), c - d * f.tf, od * 0.5 + f.tf * 0.6, od * 0.5 + f.tf * 0.3, m.segs(od * 0.5, 8, 32), false)
	if bolts:
		bolt_ring(m, c - d * f.tf * 0.5, d, f.pcd, f.n, f.bolt_r, f.tf * 2.4)

## A ring of n studs with nuts (detail: §10's example of what makes a thing look real but tells nothing).
static func bolt_ring(m, c: Vector3, d: Vector3, R: float, n: int, r: float, len: float) -> void:
	m.use("steel_dark", "detail", r * 3.4)
	var ax: Array = m.across(d)
	for i in n:
		var a := TAU * (i + 0.5) / n
		var p: Vector3 = c + (ax[0] * cos(a) + ax[1] * sin(a)) * R
		m.cyl(p - d * len * 0.5, p + d * len * 0.5, r * 1.7, -1.0, 6)

## A pair of mating flanges at c on axis d (a joint in a pipe or between a body and its pipe).
static func flange_pair(m, c: Vector3, d: Vector3, od: float, mat: String, rating := "pn16") -> void:
	var f := flange_dims(od, rating)
	m.use(mat, "form")
	m.cyl(c - d * f.tf, c + d * f.tf, f.df * 0.5, -1.0, m.segs(f.df * 0.5, 10, 40))
	bolt_ring(m, c, d, f.pcd, f.n, f.bolt_r, f.tf * 3.0)

## A nozzle: a short pipe from `from` to the nozzle point `to` with a flange there (the pipe's own flange meets it).
static func nozzle(m, from: Vector3, to: Vector3, od: float, mat: String, rating := "pn16") -> void:
	var d := (to - from).normalized()
	m.use(mat, "form")
	m.cyl(from, to, od * 0.5, -1.0, 0, false)
	flange(m, to, d, od, mat, rating)

## A steel baseplate (skid frame) from lo to hi with grout under it (lo.z is the floor).
static func baseplate(m, lo: Vector3, hi: Vector3, mat := "paint_darkgrey") -> void:
	m.use("concrete", "form")
	m.box_lh(Vector3(lo.x - 0.1, lo.y - 0.1, lo.z), Vector3(hi.x + 0.1, hi.y + 0.1, lo.z + 0.08))
	m.use(mat, "form")
	var t := clampf(hi.x - lo.x, 0.2, 2.0) * 0.08
	m.box_lh(Vector3(lo.x, lo.y, lo.z + 0.08), Vector3(lo.x + t, hi.y, hi.z))
	m.box_lh(Vector3(hi.x - t, lo.y, lo.z + 0.08), Vector3(hi.x, hi.y, hi.z))
	m.box_lh(Vector3(lo.x + t, lo.y, hi.z - 0.02), Vector3(hi.x - t, hi.y, hi.z))
	m.use("steel_dark", "detail", 0.04)
	var n := maxi(2, int((hi.y - lo.y) / 0.8))
	for i in n + 1:
		var y := lerpf(lo.y + 0.1, hi.y - 0.1, float(i) / n)
		for x: float in [lo.x + t * 0.5, hi.x - t * 0.5]:
			m.cyl(Vector3(x, y, hi.z), Vector3(x, y, hi.z + 0.04), 0.018, -1.0, 6)

## A motor's size from its power (IEC 60072-1 frame sizes, 4-pole TEFC: README "Tables"): shaft height h, body
## diameter d over the fins, body length l, all in metres.
static func motor_dims(kw: float) -> Dictionary:
	const T := [[0.75, 0.08], [1.5, 0.09], [3.0, 0.10], [5.5, 0.112], [7.5, 0.132], [15.0, 0.16], [22.0, 0.18],
		[30.0, 0.20], [45.0, 0.225], [55.0, 0.25], [90.0, 0.28], [132.0, 0.315], [250.0, 0.355], [355.0, 0.40],
		[560.0, 0.45], [1000.0, 0.50], [2000.0, 0.56], [4000.0, 0.63], [8000.0, 0.71], [16000.0, 0.80], [30000.0, 0.90]]
	var h := 0.9
	for row in T:
		if kw <= row[0]:
			h = row[1]
			break
	return {"h": h, "d": h * 1.85, "l": h * 3.3 + 0.1}

## A horizontal motor: its drive end at `front` (on the shaft line), the body running back along -dir. Feet down to
## the floor at `floor_z`. The shaft stub is not drawn here (the part's `shaft` node has it).
static func motor_h(m, front: Vector3, dir: Vector3, kw: float, floor_z: float, mat := "paint_motor") -> Dictionary:
	var md := motor_dims(kw)
	var r: float = md.d * 0.5
	var l: float = md.l
	var back := front - dir * l
	var ax: Array = m.across(dir)
	m.use(mat, "form")
	m.cyl(front - dir * 0.06, back + dir * l * 0.18, r * 0.92)          # the frame
	m.cyl(front, front - dir * 0.06, r * 0.7)                            # drive end shield
	m.lathe(back + dir * l * 0.18, -dir, [[r * 0.98, 0.0], [r * 0.98, l * 0.16], [r * 0.6, l * 0.2]], 0, true)   # fan cowl
	m.use("dark", "identify")
	m.disk(back - dir * (l * 0.02 + 0.002), -dir, r * 0.55, 16)          # the cowl's grille: a TEFC motor's tell
	# cooling fins along the frame (detail)
	m.use(mat, "detail", r * 0.08)
	var nf := 12 if r < 0.25 else 16
	for i in nf:
		var a := TAU * (i + 0.5) / nf
		var rad: Vector3 = ax[0] * cos(a) + ax[1] * sin(a)
		if rad.z < -0.7:
			continue
		var c: Vector3 = (front - dir * 0.06 + back + dir * l * 0.18) * 0.5 + rad * r * 0.97
		m.box(c, Vector3(r * 0.06, l * 0.62, r * 0.14), Basis(dir.cross(rad).normalized(), dir, rad))
	# feet and the terminal box
	m.use(mat, "form")
	var up := Vector3(0, 0, 1)
	var side: Vector3 = dir.cross(up).normalized()
	for s: float in [-1.0, 1.0]:
		for t: float in [0.25, 0.7]:
			var p: Vector3 = front - dir * l * t + side * (r * 0.75 * s)
			m.box_lh(Vector3(p.x - 0.04 - absf(dir.x) * l * 0.08, p.y - 0.04 - absf(dir.y) * l * 0.08, floor_z),
				Vector3(p.x + 0.04 + absf(dir.x) * l * 0.08, p.y + 0.04 + absf(dir.y) * l * 0.08, front.z - r * 0.5))
	var tb := front - dir * l * 0.45 + up * (r * 0.95)
	m.box(tb + up * r * 0.18, Vector3(r * 0.7, r * 0.7, r * 0.36), Basis(side, dir, up))
	m.use("steel_dark", "detail", 0.03)
	m.cyl(tb + side * r * 0.3 + up * r * 0.12, tb + side * r * 0.45 + up * r * 0.12, 0.02, -1.0, 6)   # cable gland
	return {"r": r, "l": l, "back": back}

## A vertical motor standing on `base` (its flange), shaft down. Large ones (> 500 kW) get a box-shaped top
## (weather-protected WP II housing), small ones a TEFC frame with a cowl on top.
static func motor_v(m, base: Vector3, kw: float, mat := "paint_motor") -> Dictionary:
	var md := motor_dims(kw)
	var r: float = md.d * 0.55
	var l: float = md.l * 0.95
	var up := Vector3(0, 0, 1)
	m.use(mat, "form")
	m.cyl(base, base + up * 0.08, r * 1.05)                  # mounting flange
	if kw > 500.0:
		m.cyl(base + up * 0.08, base + up * l * 0.55, r)
		m.box(base + up * (l * 0.55 + l * 0.2), Vector3(r * 2.3, r * 2.3, l * 0.4))
		m.use("dark", "identify")
		for s: float in [-1.0, 1.0]:   # air intake louvres on the housing's sides
			m.box(base + up * (l * 0.75) + Vector3(r * 1.151 * s, 0, 0), Vector3(0.01, r * 1.6, l * 0.25))
		m.use(mat, "form")
		m.box(base + up * (l * 0.98), Vector3(r * 1.6, r * 1.6, l * 0.06))
		m.box(base + up * (l * 0.3) + Vector3(r * 1.05, 0, 0), Vector3(r * 0.4, r * 0.7, r * 0.6))   # terminal box
		return {"r": r * 1.15, "top": base.z + l}
	m.cyl(base + up * 0.08, base + up * l * 0.8, r * 0.92)
	m.lathe(base + up * l * 0.8, up, [[r * 0.95, 0.0], [r * 0.95, l * 0.16], [r * 0.5, l * 0.2]], 0, true)
	m.use(mat, "detail", r * 0.08)
	for i in 14:
		var a := TAU * i / 14.0
		var rad := Vector3(cos(a), sin(a), 0)
		m.box(base + up * l * 0.45 + rad * r * 0.95, Vector3(r * 0.06, r * 0.14, l * 0.6), Basis(rad.cross(up), rad, up).orthonormalized())
	m.use(mat, "form")
	m.box(base + up * (l * 0.5) + Vector3(r * 1.0, 0, 0), Vector3(r * 0.35, r * 0.6, r * 0.6))
	return {"r": r, "top": base.z + l}

## A coupling (two hubs with a spacer) on the shaft line from a to b, for a `shaft` node.
static func coupling(m, a: Vector3, b: Vector3, r: float) -> void:
	var d := (b - a).normalized()
	var len := a.distance_to(b)
	m.use("steel", "identify")
	m.cyl(a, b, r * 0.35, -1.0, 12)
	m.use("paint_darkgrey", "identify")
	m.cyl(a + d * len * 0.15, a + d * len * 0.38, r, -1.0, 16)
	m.cyl(b - d * len * 0.38, b - d * len * 0.15, r, -1.0, 16)
	m.use("paint_yellow", "identify")   # a painted stripe: the eye sees it turn
	m.box(a + d * len * 0.26 + Vector3(0, 0, r * 0.98), Vector3(r * 0.25, len * 0.2, r * 0.06), Basis(d.cross(Vector3(0, 0, 1)).normalized() if absf(d.z) < 0.9 else Vector3(1, 0, 0), d, Vector3(0, 0, 1)).orthonormalized())

## A coupling guard over the shaft line from a to b (identify: §10 "rotating shaft guards"), open at the bottom.
static func guard(m, a: Vector3, b: Vector3, r: float, floor_z: float) -> void:
	var d := (b - a).normalized()
	var side: Vector3 = d.cross(Vector3(0, 0, 1)).normalized()
	var c := (a + b) * 0.5
	var len := a.distance_to(b)
	m.use("paint_yellow", "identify")
	var top := c + Vector3(0, 0, r * 1.25)
	m.box(top, Vector3(0, 0, 0) + side.abs() * (r * 2.6) + d.abs() * len + Vector3(0, 0, 0.012))
	for s: float in [-1.0, 1.0]:
		m.box(c + side * (r * 1.3 * s) + Vector3(0, 0, r * 0.15), side.abs() * 0.012 + d.abs() * len + Vector3(0, 0, r * 2.2))
	m.use("paint_yellow", "detail", 0.03)
	for s: float in [-1.0, 1.0]:
		var p := c + side * (r * 1.3 * s)
		m.box_lh(Vector3(p.x - 0.015, p.y - 0.015, floor_z), Vector3(p.x + 0.015, p.y + 0.015, c.z - r))

## A lifting lug (detail) at c on a surface facing n.
static func lug(m, c: Vector3, n: Vector3, s: float) -> void:
	m.use("paint_darkgrey", "detail", s * 0.3)
	m.box(c + n * s * 0.4, Vector3(s * 0.15, s * 0.8, s * 0.8) if absf(n.z) > 0.5 else Vector3(s * 0.8, s * 0.15, s * 0.8))

## Handrail posts and rails along a plan polygon at height z (yellow, identify-sized: a trainee sees where an edge is).
static func rail_loop(m, pts: Array, z: float, closed := true) -> void:
	m.use("paint_yellow", "form")
	var n := pts.size()
	var segs_ := n if closed else n - 1
	for i in segs_:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		var len := a.distance_to(b)
		if len < 0.05:
			continue
		for h: float in [1.1, 0.55]:
			m.cyl(Vector3(a.x, a.y, z + h), Vector3(b.x, b.y, z + h), 0.022, -1.0, 6, false)
		var k := maxi(1, int(ceil(len / 1.5)))
		for j in k:
			var p := a.lerp(b, float(j) / k)
			m.cyl(Vector3(p.x, p.y, z), Vector3(p.x, p.y, z + 1.1), 0.022, -1.0, 6, false)

## A caged ladder on equipment from (x, y, z0) to z1, climbing facing `facing` (a unit plan vector).
static func ladder(m, at: Vector3, z1: float, facing: Vector2) -> void:
	var f := Vector3(facing.x, facing.y, 0)
	var s := Vector3(facing.y, -facing.x, 0)
	m.use("paint_yellow", "form")
	for k: float in [-1.0, 1.0]:
		m.box_lh(at + s * (0.23 * k) - Vector3(0.03, 0.03, 0) , at + s * (0.23 * k) + Vector3(0.03, 0.03, z1 - at.z + 1.0))
	m.use("paint_yellow", "detail", 0.03)
	var z := at.z + 0.3
	while z < z1:
		m.cyl(at + s * -0.23 + Vector3(0, 0, z - at.z), at + s * 0.23 + Vector3(0, 0, z - at.z), 0.014, -1.0, 6, false)
		z += 0.3
	if z1 - at.z > 3.0:
		m.use("paint_yellow", "form")
		var hz := at.z + 2.5
		while hz < z1 + 1.0:
			var c := at + Vector3(0, 0, hz - at.z) - f * 0.35
			m.torus(c, s, f, 0.36, 0.012, PI, 8, 6)
			hz += 1.2
