## The parts kit's mesh builder (docs/PLANT3D.md §9, §10): primitives in a part's frame (x right, y forward along the
## main axis, z up, metres from the part's origin) collected into layers, one per (material, visibility class, size
## bucket). Every primitive carries texture coordinates in metres (the materials scale them: one texel density on
## every part, whatever its size), outward normals and, at the end, tangents (the materials' normal maps need them).
## Godot's axes (x east, y up, z south) are applied when a layer is turned into arrays.
##
## Visibility classes (§10): `form` (what a thing is: drawn to the far plane, LOD only), `identify` (which one and in
## which state: never removed for performance), `detail` (bolts, fins, small brackets: a visibility range by size).
## `size` is the piece's smallest telling feature in metres; it decides a `detail` piece's range.
extends RefCounted

const CLASSES := ["form", "identify", "detail"]

var layers := {}          # key "mat|cls|bucket" -> {mat, cls, size, v: PackedVector3Array, n, uv, idx: PackedInt32Array}
var cur: Dictionary = {}
var xf := Transform3D.IDENTITY   # applied to every primitive (part frame), for groups of pieces placed together
var seg_scale := 1.0             # the kit's segment density (1 = full detail)

## Selects the layer the next primitives go to.
func use(mat: String, cls := "form", size := 0.0) -> void:
	assert(cls in CLASSES)
	var bucket := 0
	if cls == "detail":
		bucket = int(floor(log(maxf(size, 0.001)) / log(2.0)))   # a factor of 2 (§10): pieces of one bucket share a range
	var key := "%s|%s|%d" % [mat, cls, bucket]
	if not layers.has(key):
		layers[key] = {"mat": mat, "cls": cls, "size": size, "v": PackedVector3Array(), "n": PackedVector3Array(),
			"uv": PackedVector2Array(), "idx": PackedInt32Array()}
	cur = layers[key]
	if cls == "detail":
		cur.size = minf(cur.size, size) if cur.size > 0.0 else size

## Segments round a circle of radius r: one every ~10 cm of circumference, 8 to 48 (fewer with seg_scale < 1).
func segs(r: float, lo := 8, hi := 48) -> int:
	return clampi(int(ceil(TAU * r / 0.10 * seg_scale)), lo, hi)

# ------------------------------------------------------------------ the raw parts

func _pt(p: Vector3) -> Vector3:
	var q := xf * p
	return Vector3(q.x, q.z, -q.y)   # part frame (x right, y forward, z up) to Godot's

func _nm(n: Vector3) -> Vector3:
	var q := (xf.basis * n).normalized()
	return Vector3(q.x, q.z, -q.y)

func _vert(p: Vector3, n: Vector3, uv: Vector2) -> int:
	cur.v.append(_pt(p))
	cur.n.append(_nm(n))
	cur.uv.append(uv)
	return cur.v.size() - 1

## A triangle a, b, c whose front face is counter-clockwise seen from outside (the normal side). Godot's front faces
## are clockwise, and the part-to-Godot change of axes keeps handedness, so the indices are stored reversed.
func _tri(a: int, b: int, c: int) -> void:
	cur.idx.append(a)
	cur.idx.append(c)
	cur.idx.append(b)

func _quad(a: int, b: int, c: int, d: int) -> void:
	_tri(a, b, c)
	_tri(a, c, d)

## Two unit vectors across axis d.
static func across(d: Vector3) -> Array:
	var ref := Vector3(0, 0, 1) if absf(d.z) < 0.9 else Vector3(1, 0, 0)
	var u := d.cross(ref).normalized()
	var w := d.cross(u).normalized()
	return [u, w]

# ------------------------------------------------------------------ primitives (part frame)

## A flat polygon (counter-clockwise seen from where normal points), planar texture coordinates.
func poly(pts: Array, normal: Vector3) -> void:
	var ax: Array = across(normal)
	var first: int = cur.v.size()
	for p in pts:
		_vert(p, normal, Vector2(p.dot(ax[0]), p.dot(ax[1])))
	for i in range(1, pts.size() - 1):
		_tri(first, first + i, first + i + 1)

## A box: centre c, size s along the frame's axes turned by basis b.
func box(c: Vector3, s: Vector3, b := Basis.IDENTITY) -> void:
	var h := s * 0.5
	if b.determinant() < 0.0:   # a left-handed basis would turn the faces inside out
		b = Basis(-b.x, b.y, b.z)
	var ax := [b.x, b.y, b.z]
	var hs := [h.x, h.y, h.z]
	for i in 3:
		for sgn in [-1.0, 1.0]:
			var n: Vector3 = ax[i] * sgn
			var u: Vector3 = ax[(i + 1) % 3]
			var w: Vector3 = ax[(i + 2) % 3]
			var hu: float = hs[(i + 1) % 3]
			var hw: float = hs[(i + 2) % 3]
			var o: Vector3 = c + n * hs[i]
			var q := [o - u * hu - w * hw, o + u * hu - w * hw, o + u * hu + w * hw, o - u * hu + w * hw]
			if sgn < 0:
				q.reverse()
			poly(q, n)

## A box from corner lo to corner hi (axis-aligned in the part frame).
func box_lh(lo: Vector3, hi: Vector3) -> void:
	box((lo + hi) * 0.5, (hi - lo).abs())

## A cylinder (or a cone frustum) from a to b, radius ra at a and rb at b; `caps` closes the ends.
func cyl(a: Vector3, b: Vector3, ra: float, rb := -1.0, n := 0, caps := true) -> void:
	if rb < 0.0:
		rb = ra
	var d := b - a
	var len := d.length()
	if len < 1e-5:
		return
	d /= len
	if n <= 0:
		n = segs(maxf(ra, rb))
	var ax: Array = across(d)
	var slope := (ra - rb) / len
	var first: int = cur.v.size()
	var circ := TAU * maxf(ra, rb)
	for i in n + 1:
		var t := TAU * i / n
		var radial: Vector3 = ax[0] * cos(t) + ax[1] * sin(t)
		var nrm := (radial + d * slope).normalized()
		_vert(a + radial * ra, nrm, Vector2(circ * i / n, 0))
		_vert(b + radial * rb, nrm, Vector2(circ * i / n, len))
	for i in n:
		var k: int = first + i * 2
		_quad(k, k + 2, k + 3, k + 1)
	if caps:
		disk(a, -d, ra, n)
		disk(b, d, rb, n)

## A disk at c facing n.
func disk(c: Vector3, nrm: Vector3, r: float, n := 0) -> void:
	if r <= 1e-5:
		return
	if n <= 0:
		n = segs(r)
	var ax: Array = across(nrm)
	var first: int = cur.v.size()
	_vert(c, nrm, Vector2(0, 0))
	for i in n + 1:
		var t := TAU * i / n
		var p: Vector3 = c + (ax[0] * cos(t) + ax[1] * sin(t)) * r
		_vert(p, nrm, Vector2(cos(t) * r, sin(t) * r))
	for i in n:
		# counter-clockwise seen from the normal's side (across(d) gives u, w with u x w = d)
		_tri(first, first + 1 + i, first + 2 + i)

## A ring (a flat annulus) at c facing nrm, radii r0 < r1.
func ring(c: Vector3, nrm: Vector3, r0: float, r1: float, n := 0) -> void:
	if n <= 0:
		n = segs(r1)
	var ax: Array = across(nrm)
	var first: int = cur.v.size()
	for i in n + 1:
		var t := TAU * i / n
		var radial: Vector3 = ax[0] * cos(t) + ax[1] * sin(t)
		_vert(c + radial * r0, nrm, Vector2(cos(t), sin(t)) * r0)
		_vert(c + radial * r1, nrm, Vector2(cos(t), sin(t)) * r1)
	for i in n:
		var k: int = first + i * 2
		_quad(k, k + 1, k + 3, k + 2)

## A tube (a hollow cylinder with wall): outer and inner surfaces and the two rings, from a to b.
func tube(a: Vector3, b: Vector3, r_out: float, r_in: float, n := 0) -> void:
	if n <= 0:
		n = segs(r_out)
	var d := (b - a).normalized()
	cyl(a, b, r_out, r_out, n, false)
	_inner(a, b, r_in, n)
	ring(a, -d, r_in, r_out, n)
	ring(b, d, r_in, r_out, n)

func _inner(a: Vector3, b: Vector3, r: float, n: int) -> void:
	var d := b - a
	var len := d.length()
	d /= len
	var ax: Array = across(d)
	var first: int = cur.v.size()
	for i in n + 1:
		var t := TAU * i / n
		var radial: Vector3 = ax[0] * cos(t) + ax[1] * sin(t)
		_vert(a + radial * r, -radial, Vector2(TAU * r * i / n, 0))
		_vert(b + radial * r, -radial, Vector2(TAU * r * i / n, len))
	for i in n:
		var k: int = first + i * 2
		_quad(k, k + 1, k + 3, k + 2)

## A surface of revolution about the axis from c along d: profile [[r, t], …] (t along the axis), closed with disks
## where the profile starts or ends at r > 0 and `caps` is set.
func lathe(c: Vector3, d: Vector3, profile: Array, n := 0, caps := true) -> void:
	d = d.normalized()
	if n <= 0:
		var rmax := 0.0
		for p in profile:
			rmax = maxf(rmax, p[0])
		n = segs(rmax)
	var ax: Array = across(d)
	for k in range(profile.size() - 1):
		var r0: float = profile[k][0]
		var r1: float = profile[k + 1][0]
		var t0: float = profile[k][1]
		var t1: float = profile[k + 1][1]
		if absf(t1 - t0) < 1e-6 and absf(r1 - r0) < 1e-6:
			continue
		# the profile segment's normal in the (radial, axial) plane
		var sn := Vector2(t1 - t0, -(r1 - r0)).normalized()
		var first: int = cur.v.size()
		var circ := TAU * maxf(r0, r1)
		for i in n + 1:
			var t := TAU * i / n
			var radial: Vector3 = ax[0] * cos(t) + ax[1] * sin(t)
			var nrm := (radial * sn.x + d * sn.y).normalized()
			_vert(c + d * t0 + radial * r0, nrm, Vector2(circ * i / n, t0 + r0))
			_vert(c + d * t1 + radial * r1, nrm, Vector2(circ * i / n, t1 + r1))
		for i in n:
			var q: int = first + i * 2
			_quad(q, q + 2, q + 3, q + 1)
	if caps:
		var p0: Array = profile[0]
		var p1: Array = profile[-1]
		if p0[0] > 1e-5:
			disk(c + d * p0[1], -d if p1[1] >= p0[1] else d, p0[0], n)
		if p1[0] > 1e-5:
			disk(c + d * p1[1], d if p1[1] >= p0[1] else -d, p1[0], n)

## A dish (a shallow spherical cap) closing a cylinder end: at c, bulging along d by h, radius r.
func dish(c: Vector3, d: Vector3, r: float, h: float, n := 0, rings_ := 4) -> void:
	var prof: Array = []
	for k in rings_ + 1:
		var f := float(k) / rings_
		var a := f * PI * 0.5
		prof.append([r * cos(a), h * sin(a)])
	lathe(c, d, prof, n, false)

## A torus segment: centre c, the ring in the plane spanned by u (start direction) and w, major radius R, tube radius
## r, from angle 0 to `angle`. Used for handwheels and pipe bends.
func torus(c: Vector3, u: Vector3, w: Vector3, R: float, r: float, angle := TAU, nm := 0, nr := 0) -> void:
	u = u.normalized()
	w = w.normalized()
	if nm <= 0:
		nm = clampi(int(ceil(absf(angle) * R / 0.12 * seg_scale)), 6, 48)
	if nr <= 0:
		nr = segs(r, 6, 32)
	var axis := u.cross(w).normalized()
	var first: int = cur.v.size()
	for i in nm + 1:
		var a := angle * i / nm
		var radial := u * cos(a) + w * sin(a)
		var centre := c + radial * R
		var bx: Array = [radial, axis]
		for j in nr + 1:
			var b := TAU * j / nr
			var nrm: Vector3 = bx[0] * cos(b) + bx[1] * sin(b)
			_vert(centre + nrm * r, nrm, Vector2(R * a, TAU * r * j / nr))
	for i in nm:
		for j in nr:
			var k: int = first + i * (nr + 1) + j
			_quad(k, k + nr + 1, k + nr + 2, k + 1)

## A handwheel: rim (torus), hub and spokes, in the plane facing nrm, at c. Rim tube radius from the wheel's size.
func handwheel(c: Vector3, nrm: Vector3, R: float, spokes := 0) -> void:
	var ax: Array = across(nrm)
	var t := clampf(R * 0.09, 0.008, 0.035)
	torus(c, ax[0], ax[1], R, t)
	cyl(c - nrm * t * 1.5, c + nrm * t * 1.5, t * 2.2, -1.0, 12)
	if spokes <= 0:
		spokes = 3 if R < 0.2 else (4 if R < 0.35 else 5)
	for i in spokes:
		var a := TAU * i / spokes
		var dir: Vector3 = ax[0] * cos(a) + ax[1] * sin(a)
		cyl(c + dir * t * 2.0, c + dir * (R - t * 0.5) - nrm * t * 0.6, t * 0.55, -1.0, 6, false)

## A convex hexahedron from its 8 corners: c[0..3] the bottom (or back) quad, c[4..7] the top (or front) quad above
## them in the same order. Faces are flat, normals outward (a loft between two rectangles: duct transitions).
func hexa(c: Array) -> void:
	var centre := Vector3.ZERO
	for p in c:
		centre += p
	centre /= 8.0
	var faces := [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]
	for f in faces:
		var q: Array = [c[f[0]], c[f[1]], c[f[2]], c[f[3]]]
		var n: Vector3 = (q[2] - q[0]).cross(q[3] - q[1])
		if n.length() < 1e-9:
			continue
		n = n.normalized()
		var fc: Vector3 = (q[0] + q[1] + q[2] + q[3]) * 0.25
		if n.dot(fc - centre) < 0.0:
			n = -n
			q.reverse()
		poly(q, n)

## A straight extrusion of a plan polygon `pts2` (in the plane of u and w, counter-clockwise seen from +axis) from c0
## along `axis` by `len`, with both caps.
func prism(c0: Vector3, u: Vector3, w: Vector3, pts2: Array, len: float) -> void:
	var axis := u.cross(w).normalized()
	var n := pts2.size()
	var bot: Array = []
	var top: Array = []
	for p in pts2:
		bot.append(c0 + u * p.x + w * p.y)
		top.append(c0 + u * p.x + w * p.y + axis * len)
	var acc := 0.0
	for i in n:
		var j := (i + 1) % n
		var e: Vector3 = bot[j] - bot[i]
		var el := e.length()
		if el < 1e-6:
			continue
		var nrm := e.cross(axis).normalized()
		var first: int = cur.v.size()
		_vert(bot[i], nrm, Vector2(acc, 0)); _vert(bot[j], nrm, Vector2(acc + el, 0))
		_vert(top[j], nrm, Vector2(acc + el, len)); _vert(top[i], nrm, Vector2(acc, len))
		_quad(first, first + 1, first + 2, first + 3)
		acc += el
	var rb := top.duplicate()
	poly(rb, axis)
	var rbot := bot.duplicate()
	rbot.reverse()
	poly(rbot, -axis)

## A pipe along a polyline with bends of radius `bend_r` at the corners (§4: R = 1.5 × OD by default). Returns the
## straight pieces actually drawn (for supports and bands): [[a, b], …].
func pipe_path(pts: Array, r: float, bend_r: float, n := 0, skip := {}) -> Array:
	if n <= 0:
		n = segs(r, 8, 40)
	var straight: Array = []
	var m := pts.size()
	var starts: Array = []   # trimmed segment ends
	var ends: Array = []
	for i in m - 1:
		starts.append(pts[i])
		ends.append(pts[i + 1])
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
		if skip.has(i - 1) and skip.has(i):
			continue
		# the bend: centre on the inside of the corner
		var inward := (d1 - d0).normalized()
		var centre: Vector3 = pts[i] + inward * (rr / cos(th * 0.5))
		var u: Vector3 = (ends[i - 1] - centre).normalized()
		var w: Vector3 = d0
		torus(centre, u, w, rr, r, th, clampi(int(ceil(th / 0.2)), 3, 12), n)
	for i in m - 1:
		if skip.has(i):
			continue
		var a: Vector3 = starts[i]
		var b: Vector3 = ends[i]
		if a.distance_to(b) > 1e-3:
			cyl(a, b, r, r, n, false)
			straight.append([a, b])
	return straight

# ------------------------------------------------------------------ the result

## Every layer as mesh arrays in Godot's axes, with tangents; {key: {mat, cls, size, arrays, tris}}.
func finish() -> Dictionary:
	var out := {}
	for k in layers:
		var L: Dictionary = layers[k]
		if L.idx.is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = L.v
		arr[Mesh.ARRAY_NORMAL] = L.n
		arr[Mesh.ARRAY_TEX_UV] = L.uv
		arr[Mesh.ARRAY_INDEX] = L.idx
		var st := SurfaceTool.new()
		st.create_from_arrays(arr)
		st.generate_tangents()
		out[k] = {"mat": L.mat, "cls": L.cls, "size": L.size, "arrays": st.commit_to_arrays(), "tris": L.idx.size() / 3}
	return out
