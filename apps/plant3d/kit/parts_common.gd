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
	m.use("steel_bolt", "detail", r * 3.4)
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
## `g` (the Workshop, WORKSHOP.md §4; milestone K6): the motor's component tree under `root` (its stator and frame),
## the root's own spec `root_spec`. The motor kind's and the horizontal pump's motor are this one tree (kit/README.md
## "Workshop: the motor"); plant mode draws exactly what it drew before (the Workshop's pieces are "workshop" pieces
## and the split of the plant's stand-ins). Without `g` (every other kind) nothing changes.
static func motor_h(m, front: Vector3, dir: Vector3, kw: float, floor_z: float, mat := "paint_motor", g = null,
		root := "", root_spec := {}) -> Dictionary:
	var md := motor_dims(kw)
	var r: float = md.d * 0.5
	var l: float = md.l
	var back := front - dir * l
	var ax: Array = m.across(dir)
	var ws: bool = g != null
	var F0 := front - dir * 0.06            # the frame's drive end (the drive-end shield in front of it)
	var B0 := back + dir * l * 0.18         # the frame's non-drive end (the fan cowl behind it)
	if ws:
		_motor_comps(g, root, root_spec, front, dir, r, l, md.h)
		g.comp(root)
		g.only("plant", [root, "end_shield_nde", "end_shield_de", "fan_cowl"])
	m.use(mat, "form")
	m.cyl(F0, B0, r * 0.92)          # the frame
	if ws:
		_motor_frame(g, m, mat, root, F0, B0, dir, r, l, md.h)
		g.comp("end_shield_de")
		g.only("plant", [root, "end_shield_nde", "end_shield_de", "fan_cowl"])
		m.use(mat, "form")
	m.cyl(front, F0, r * 0.7)                            # drive end shield
	if ws:
		_motor_de(g, m, mat, front, F0, dir, r, md.h)
		g.comp("fan_cowl")
		g.only("plant", [root, "end_shield_nde", "end_shield_de", "fan_cowl"])
		m.use(mat, "form")
	m.lathe(B0, -dir, [[r * 0.98, 0.0], [r * 0.98, l * 0.16], [r * 0.6, l * 0.2]], 0, true)   # fan cowl
	if ws:
		_motor_cowl(g, m, mat, B0, dir, r, l)
		g.comp("grille")
	m.use("dark", "identify")
	m.disk(back - dir * (l * 0.02 + 0.002), -dir, r * 0.55, 16)          # the cowl's grille: a TEFC motor's tell
	if ws:
		g.comp(root)
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
	if ws:
		g.comp("terminal_box")
	m.box(tb + up * r * 0.18, Vector3(r * 0.7, r * 0.7, r * 0.36), Basis(side, dir, up))
	m.use("steel_dark", "detail", 0.03)
	m.cyl(tb + side * r * 0.3 + up * r * 0.12, tb + side * r * 0.45 + up * r * 0.12, 0.02, -1.0, 6)   # cable gland
	if ws:
		_motor_rotor(g, front, F0, B0, dir, r, l, md.h)
		g.comp(root)
	return {"r": r, "l": l, "back": back}

# ------------------------------------------------------------------ the motor in the Workshop (WORKSHOP.md K6)
# A totally enclosed fan-cooled motor (IC 411, foot mounted IM B3) as the public manuals describe one; its take-apart
# order is derived from how it is built, not from a manual (kit/README.md "Workshop: the motor"). Every piece here is
# a Workshop piece: plant mode draws what it drew before.

## A flat face (a disk when r0 is 0, else a ring) at c across the axis d, facing +d or -d, its points listed as a
## cylinder along d lists them (across(d)): so it meets that cylinder's rim exactly, whichever way it faces.
static func _face(m, c: Vector3, d: Vector3, r0: float, r1: float, n: int, toward_d: bool) -> void:
	m.lathe(c, d, [[r1, 0.0], [r0, 0.0]] if toward_d else [[r0, 0.0], [r1, 0.0]], n, false)

## Closes a seam at radius r round c on the axis d: a cylinder's rim there lists its n points by across(d), a disk or
## ring facing the other way (as the kit's cyl() draws its first cap) lists them by across(-d), which for an odd n are
## other points of the same circle; a strip of thin triangles between the two in the plane joins them, so that what
## the plant draws stays as it is and a Workshop solid is still closed (every edge used twice). `out`: the way the face
## it lies in looks out of the solid. Nothing for an even n.
static func _zip(m, c: Vector3, d: Vector3, r: float, n: int, out: Vector3) -> void:
	if n % 2 == 0:
		return
	var A: Array = m.across(d)
	var B: Array = m.across(-d)
	var pts: Array = []   # [angle in A's frame, point]
	for i in n:
		var t := TAU * i / n
		pts.append([t, c + (A[0] * cos(t) + A[1] * sin(t)) * r])
		pts.append([fposmod(PI - t, TAU), c + (B[0] * cos(t) + B[1] * sin(t)) * r])
	pts.sort_custom(func(x, y): return x[0] < y[0])
	for i in pts.size():
		m.poly([pts[i][1], pts[(i + 1) % pts.size()][1], pts[(i + 2) % pts.size()][1]], out)

## The bore of the stator, the bearings' outside radius and the shaft's radius.
static func _motor_r(r: float, h: float) -> Dictionary:
	var rs := h * 0.15
	return {"bore": r * 0.68, "brg": rs * 2.0, "shaft": rs, "core": r * 0.6, "e": 0.04, "cowl_in": r * 0.9}

## The tree: the root (the stator in its frame) and, one stage later, everything that comes off it; the bearings come
## off the rotor's shaft after it is out. Each part leaves the way it is taken off, the faster ones ahead of the slower
## ones on the same line (the cowl ahead of the fan ahead of the non-drive end shield; the drive-end shield ahead of
## the rotor), so none passes through another.
static func _motor_comps(g, root: String, root_spec: Dictionary, front: Vector3, dir: Vector3, r: float, l: float,
		h: float) -> void:
	var up := Vector3(0, 0, 1)
	var spec := root_spec.duplicate()
	var ranim: String = spec.get("rotor_anim", "")   # the motor kind's rotor is its `shaft` node (in a pump, the coupling)
	spec.erase("rotor_anim")
	spec["anchors"] = {"vib_nde": front - dir * l * 0.78 + up * r * 0.92}
	g.comp(root, spec)
	var axis := front - dir * l * 0.5
	g.comp("terminal_box", {"parent": root, "explode": [up, r * 1.2],
		"anchors": {"u1": front - dir * l * 0.41 + up * r * 1.2, "v1": front - dir * l * 0.45 + up * r * 1.2,
			"w1": front - dir * l * 0.49 + up * r * 1.2}})
	g.comp("end_shield_de", {"parent": root, "explode": [dir, l * 1.4], "anchors": {"vib_de": front - dir * 0.03 + up * r * 0.7}})
	g.comp("end_shield_nde", {"parent": root, "explode": [-dir, l * 0.2]})
	g.comp("fan", {"parent": root, "explode": [-dir, l * 0.55], "sym": [dir, 8]})
	g.comp("fan_cowl", {"parent": root, "explode": [-dir, l * 0.95]})
	g.comp("grille", {"parent": "fan_cowl", "explode": [-dir, 0.0], "thin": true})
	g.comp("rotor", {"parent": root, "explode": [dir, l * 1.05], "pivot": axis, "sym": [dir, 0],
		"anim": ranim})
	g.comp("bearing_de", {"parent": "rotor", "explode": [dir, l * 0.25], "sym": [dir, 0]})
	g.comp("bearing_nde", {"parent": "rotor", "explode": [-dir, l * 0.2], "sym": [dir, 0]})

## The frame split: the stator's frame open at both ends round its bore (the end shields close it), the non-drive end
## shield the frame's end as the plant draws it, with its spigot in the bore and its bearing housing open to the rotor.
static func _motor_frame(g, m, mat: String, root: String, F0: Vector3, B0: Vector3, dir: Vector3, r: float, l: float,
		h: float) -> void:
	var k := _motor_r(r, h)
	var n: int = m.segs(r * 0.92)   # the plant's frame's
	g.only("workshop", "split")
	m.use(mat, "form")
	m.cyl(F0, B0, r * 0.92, -1.0, n, false)
	_face(m, F0, -dir, k.bore, r * 0.92, n, false)
	g.only("workshop")
	m._inner(F0, B0, k.bore, n)                     # the stator's bore
	m.ring(B0, -dir, k.bore, r * 0.92, n)
	m.use("brass", "identify")                       # the winding's end turns, at both ends of the core
	var ax: Array = m.across(dir)
	for c in [F0 - dir * 0.05, B0 + dir * (k.e + 0.04)]:
		m.torus(c, ax[0], ax[1], r * 0.81, r * 0.065, TAU, 24, 8)
	# the non-drive-end shield: the plant's cap; its flange against the frame is drawn facing out (it lies in the cap's
	# plane), so that what is inside it is held to the outside by the frame
	g.comp("end_shield_nde")
	g.only("workshop", "split")
	m.use(mat, "form")
	m.disk(B0, -dir, r * 0.92, n)
	g.only("workshop")
	m.ring(B0, -dir, k.bore, r * 0.92, n)
	m.cyl(B0 + dir * k.e, B0, k.bore, -1.0, n, false)   # its spigot in the bore
	_face(m, B0 + dir * k.e, -dir, k.brg, k.bore, n, false)
	m._inner(B0 + dir * k.e, B0 + dir * (k.e - 0.03), k.brg, n)   # the bearing housing, open to the rotor
	_face(m, B0 + dir * (k.e - 0.03), -dir, 0.0, k.brg, n, false)
	g.comp(root)
	g.only()

## The drive-end shield as the plant draws it, its bearing housing open to the rotor.
static func _motor_de(g, m, mat: String, front: Vector3, F0: Vector3, dir: Vector3, r: float, h: float) -> void:
	var k := _motor_r(r, h)
	var n: int = m.segs(r * 0.7)   # the plant's shield's
	g.only("workshop", "split")
	m.use(mat, "form")
	m.cyl(F0, front, r * 0.7, -1.0, n, false)   # (its points as its front face lists them)
	m.disk(front, dir, r * 0.7, n)
	_face(m, F0, dir, k.brg, r * 0.7, n, false)
	g.only("workshop")
	m._inner(F0, F0 + dir * 0.03, k.brg, n)
	_face(m, F0 + dir * 0.03, dir, 0.0, k.brg, n, false)
	g.only()
	var bolts: Array = []   # 4 bolts through the shield into the frame, backing out forwards
	var ax: Array = m.across(dir)
	for i in 4:
		var a := TAU * (i + 0.5) / 4.0
		var p: Vector3 = front + (ax[0] * cos(a) + ax[1] * sin(a)) * r * 0.58
		var by: Vector3 = ax[0]
		bolts.append(Transform3D(Basis(by.cross(dir), by, dir), p))
	var bolt := func(b) -> void:
		b.use("steel_bolt", "detail", 0.02)
		b.cyl(Vector3(0, 0, 0), Vector3(0, 0, 0.008), 0.009, -1.0, 6)    # the head, on the shield's face
		b.cyl(Vector3(0, 0, -0.02), Vector3(0, 0, 0), 0.005, -1.0, 6)    # the shank, in the shield
	g.fasteners("de_bolts", "bolt", bolts, bolt)

## The fan cowl as the plant draws it, open at the front over the fan, with its screws into the frame's end.
static func _motor_cowl(g, m, mat: String, B0: Vector3, dir: Vector3, r: float, l: float) -> void:
	var k := _motor_r(r, 0.0)
	var n: int = m.segs(r * 0.98)   # the plant's cowl's
	g.only("workshop", "split")
	m.use(mat, "form")
	m.lathe(B0, -dir, [[r * 0.98, 0.0], [r * 0.98, l * 0.16], [r * 0.6, l * 0.2]], n, false)
	m.disk(B0 - dir * l * 0.2, -dir, r * 0.6, n)
	m.ring(B0, dir, k.cowl_in, r * 0.98, n)   # its face to the frame, as the plant's cap (the outline needs it)
	_zip(m, B0, -dir, r * 0.98, n, dir)       # (a seam in the outside: the stand-in's own)
	g.only("workshop")
	m._inner(B0 - dir * l * 0.16, B0, k.cowl_in, n)
	m.disk(B0 - dir * l * 0.16, dir, k.cowl_in, n)
	g.only()
	var screws: Array = []   # 4 screws through the cowl's rim into the frame's end, backing out outwards
	var ax: Array = m.across(dir)
	for i in 4:
		var a := TAU * (i + 0.125) / 4.0
		var rad: Vector3 = ax[0] * cos(a) + ax[1] * sin(a)
		screws.append(Transform3D(Basis(dir.cross(rad).normalized(), dir, rad), B0 - dir * 0.03 + rad * r * 0.98))
	var screw := func(b) -> void:
		b.use("steel_bolt", "detail", 0.015)
		b.cyl(Vector3(0, 0, 0), Vector3(0, 0, 0.005), 0.007, -1.0, 6)
		b.cyl(Vector3(0, 0, -0.015), Vector3(0, 0, 0), 0.0035, -1.0, 6)
	g.fasteners("cowl_screws", "screw", screws, screw)

## The rotor in the `shaft` node (it turns with the shaft): its shaft from the fan to the drive end, the core in the
## stator's bore, the bearings in the end shields' housings, the fan on the shaft's non-drive end in the cowl. All
## hidden inside the motor.
static func _motor_rotor(g, front: Vector3, F0: Vector3, B0: Vector3, dir: Vector3, r: float, l: float, h: float) -> void:
	var k := _motor_r(r, h)
	var sh = g.move("shaft", Vector3(front.x, 0.0, front.z) if absf(dir.y) > 0.5 else Vector3(0.0, front.y, front.z),
		dir, "rotate", 0.0)
	g.comp("rotor")
	g.only("workshop")
	sh.use("steel", "identify")
	sh.cyl(B0 - dir * l * 0.1, front - dir * 0.001, k.shaft, -1.0, 16)
	sh.use("steel_dark", "identify")
	sh.cyl(B0 + dir * (k.e + 0.02), F0 - dir * 0.02, k.core, -1.0, 32)   # the core (laminations, cage bars)
	sh.use("chrome", "identify")
	g.comp("bearing_de")
	sh.tube(F0 + dir * 0.002, F0 + dir * 0.028, k.brg, k.shaft, 16)
	g.comp("bearing_nde")
	sh.tube(B0 + dir * (k.e - 0.028), B0 + dir * (k.e - 0.002), k.brg, k.shaft, 16)
	g.comp("fan")
	sh.use("paint_darkgrey", "identify")
	sh.cyl(B0 - dir * 0.02, B0 - dir * l * 0.1, k.shaft * 1.6, -1.0, 16)    # its hub
	var ax: Array = sh.across(dir)
	for i in 8:   # straight radial blades: the fan cools whichever way the motor turns
		var a := TAU * i / 8.0
		var rad: Vector3 = ax[0] * cos(a) + ax[1] * sin(a)
		var rr: float = (k.shaft * 1.5 + r * 0.8) * 0.5
		sh.box(B0 - dir * l * 0.06 + rad * rr, Vector3(0.012, l * 0.07, r * 0.8 - k.shaft * 1.5),
			Basis(dir.cross(rad).normalized(), dir, rad))
	g.only()

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
