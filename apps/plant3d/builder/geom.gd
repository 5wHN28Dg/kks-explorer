## Plan geometry for the content build (docs/PLANT3D.md §5): plant coordinates (x east, y north, z up) to Godot's
## (x east, y up, z south), polygons with holes cut into convex pieces, the stair rules of §5 (the same step search as
## ref/plant3d.py check_access), and mesh and collision makers. Used by plant_builder.gd and the tests; nothing here
## runs when the app starts.
extends RefCounted

const EPS := 1e-6

## A plant point (x east, y north, z up) in Godot's axes (x east, y up, z south).
static func g(p) -> Vector3:
	return Vector3(float(p[0]), float(p[2]) if p.size() > 2 else 0.0, -float(p[1]))

## A heading in degrees clockwise from north, as a Godot rotation about the up axis (radians).
static func yaw_rad(yaw_deg: float) -> float:
	return -deg_to_rad(yaw_deg)

## The plan direction of a heading (plant x, y).
static func heading(yaw_deg: float) -> Vector2:
	var r := deg_to_rad(yaw_deg)
	return Vector2(sin(r), cos(r))

## A point of a part's frame (x right, y forward, z up) turned by the part's heading, in plant axes.
static func turn(v: Vector3, yaw_deg: float) -> Vector3:
	var r := deg_to_rad(yaw_deg)
	var c := cos(r)
	var s := sin(r)
	# yaw clockwise from north: forward (0, 1) goes to (sin, cos), right (1, 0) to (cos, -sin)
	return Vector3(v.x * c + v.y * s, -v.x * s + v.y * c, v.z)

static func poly(points, offset := Vector2.ZERO, yaw_deg := 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		var t := turn(Vector3(float(p[0]), float(p[1]), 0.0), yaw_deg)
		out.append(Vector2(t.x, t.y) + offset)
	return out

static func rect(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])

## Is p inside the polygon (even-odd rule)?
static func in_poly(p: Vector2, pg: PackedVector2Array) -> bool:
	var inside := false
	var n := pg.size()
	var j := n - 1
	for i in n:
		var a := pg[i]
		var b := pg[j]
		if (a.y > p.y) != (b.y > p.y):
			var x := a.x + (p.y - a.y) * (b.x - a.x) / (b.y - a.y)
			if p.x < x:
				inside = not inside
		j = i
	return inside

## A polygon's bounding rectangle.
static func bbox(pg: PackedVector2Array) -> Rect2:
	var r := Rect2(pg[0], Vector2.ZERO)
	for q in pg:
		r = r.expand(q)
	return r

## Inside the outline and outside every hole.
static func in_region(p: Vector2, outline: PackedVector2Array, holes: Array) -> bool:
	if not in_poly(p, outline):
		return false
	for h in holes:
		if in_poly(p, h):
			return false
	return true

## The region (outline less holes, holes may overlap each other and the outline) as convex pieces: trapezoids
## between the heights of every vertex and every edge crossing (a scanline cut), each 3 or 4 points.
static func decompose(outline: PackedVector2Array, holes: Array) -> Array:
	var polys: Array = [outline]
	polys.append_array(holes)
	var edges: Array = []   # [a, b, poly index]
	var ys: Array = []
	for pi in polys.size():
		var pg: PackedVector2Array = polys[pi]
		for i in pg.size():
			var a := pg[i]
			var b := pg[(i + 1) % pg.size()]
			ys.append(a.y)
			if absf(a.y - b.y) > EPS:
				edges.append([a, b, pi])
	for i in edges.size():
		for j in range(i + 1, edges.size()):
			var x = Geometry2D.segment_intersects_segment(edges[i][0], edges[i][1], edges[j][0], edges[j][1])
			if x != null:
				ys.append(x.y)
	ys.sort()
	var cuts: Array = []
	for y in ys:
		if cuts.is_empty() or y - cuts[-1] > EPS:
			cuts.append(y)
	var out: Array = []
	for k in range(cuts.size() - 1):
		var y0: float = cuts[k]
		var y1: float = cuts[k + 1]
		var ym := (y0 + y1) * 0.5
		var cross: Array = []   # [x at y0, x at y1, x at ym, poly]
		for e in edges:
			var a: Vector2 = e[0]
			var b: Vector2 = e[1]
			if minf(a.y, b.y) < ym and maxf(a.y, b.y) > ym:
				var f := func(y: float) -> float: return a.x + (y - a.y) * (b.x - a.x) / (b.y - a.y)
				cross.append([f.call(y0), f.call(y1), f.call(ym), e[2]])
		cross.sort_custom(func(p, q): return p[2] < q[2])
		var inside := []
		inside.resize(polys.size())
		inside.fill(false)
		for i in cross.size():
			inside[cross[i][3]] = not inside[cross[i][3]]
			if i + 1 >= cross.size():
				break
			var ok: bool = inside[0]
			for h in range(1, polys.size()):
				if inside[h]:
					ok = false
			if not ok:
				continue
			var l = cross[i]
			var r = cross[i + 1]
			var piece := PackedVector2Array()
			piece.append(Vector2(l[0], y0))
			if r[0] - l[0] > EPS: piece.append(Vector2(r[0], y0))
			piece.append(Vector2(r[1], y1))
			if r[1] - l[1] > EPS: piece.append(Vector2(l[1], y1))
			if piece.size() >= 3:
				out.append(piece)
	return out

static func area(pieces: Array) -> float:
	var a := 0.0
	for pc in pieces:
		var s := 0.0
		for i in pc.size():
			var p: Vector2 = pc[i]
			var q: Vector2 = pc[(i + 1) % pc.size()]
			s += p.x * q.y - q.x * p.y
		a += absf(s) * 0.5
	return a

# ------------------------------------------------------------------ stairs (§5, EN ISO 14122-3)

## The step count and the flights of a stair: the first count that keeps the rules, as ref/plant3d.py finds it.
## Returns {} when none does (bad_stair).
static func stair_steps(foot: Vector3, top: Vector3, layout: String, width: float) -> Dictionary:
	var h := top.z - foot.z
	if h <= 0.0:
		return {}
	var dx := absf(top.x - foot.x)
	var dy := absf(top.y - foot.y)
	var flights := int(ceil(h / 3.6 - 1e-9))
	for n in range(int(ceil(h / 0.20 - 1e-9)), int(floor(h / 0.15 + 1e-9)) + 1):
		var rise := h / n
		var per := int(ceil(float(n) / flights - 1e-9))
		var going := 1.0
		if layout == "straight":
			var treads := n - flights
			if treads > 0:
				going = (sqrt(dx * dx + dy * dy) - (flights - 1) * width) / treads
		else:
			if minf(dx, dy) < 2.0 * width - 1e-9:
				return {}
			if per > 1:
				going = (maxf(dx, dy) - 2.0 * width) / (per - 1)
		var g2 := going + 2.0 * rise
		if going >= 0.25 - 1e-9 and g2 >= 0.60 - 1e-9 and g2 <= 0.66 + 1e-9:
			return {"steps": n, "flights": flights, "rise": rise, "going": going, "per": per}
	return {}

## A stair's flights and landings in plant coordinates:
##   flights: [{a: plan start, b: plan end, z0, z1, side: unit vector across, steps}]
##   landings: [{poly: plan polygon, z}]
##   path: plan points with heights a walker follows from the foot to the top
## Switchback flights alternate between two lanes along the long side of the rectangle foot and top span, with a
## landing the stair's width deep at each end; the last flight ends at the top's end, on the top's side.
static func stair_layout(foot: Vector3, top: Vector3, layout: String, width: float, st: Dictionary) -> Dictionary:
	var f: int = st.flights
	var h := top.z - foot.z
	var dz := h / f
	var flights: Array = []
	var landings: Array = []
	var path: Array = [foot]
	if layout == "straight":
		var a2 := Vector2(foot.x, foot.y)
		var b2 := Vector2(top.x, top.y)
		var dir := (b2 - a2).normalized()
		var across := Vector2(dir.y, -dir.x)
		var going: float = st.going
		var n: int = st.steps
		var pos := a2
		for i in f:
			var k := n / f + (1 if i < n % f else 0)   # risers in this flight
			var run := (k - 1) * going if i < f - 1 else (b2 - pos).length()
			var end := pos + dir * run
			flights.append({"a": pos, "b": end, "z0": foot.z + dz * i, "z1": foot.z + dz * (i + 1), "side": across, "steps": k, "width": width})
			path.append(Vector3(end.x, end.y, foot.z + dz * (i + 1)))
			pos = end
			if i < f - 1:
				var l_end := pos + dir * width
				landings.append({"poly": _strip(pos, l_end, across, width), "z": foot.z + dz * (i + 1)})
				path.append(Vector3(l_end.x, l_end.y, foot.z + dz * (i + 1)))
				pos = l_end
		path[-1] = top
		return {"flights": flights, "landings": landings, "path": path, "rect": _strip(a2, b2, across, width)}
	# switchback: u along the long side (from the foot's end to the top's), v across (from the foot's side)
	var dx := top.x - foot.x
	var dy := top.y - foot.y
	var u: Vector2
	var v: Vector2
	var lu: float
	var lv: float
	if absf(dx) >= absf(dy):
		u = Vector2(signf(dx), 0); v = Vector2(0, signf(dy)); lu = absf(dx); lv = absf(dy)
	else:
		u = Vector2(0, signf(dy)); v = Vector2(signf(dx), 0); lu = absf(dy); lv = absf(dx)
	var o := Vector2(foot.x, foot.y)
	var at := func(uu: float, vv: float) -> Vector2: return o + u * uu + v * vv
	var lane_v := func(i: int) -> float:   # the centre of flight i's lane across
		return (lv - width * 0.5) if (f - 1 - i) % 2 == 0 else width * 0.5
	var starts_far := (f % 2 == 0)   # an even count starts at the far end so that the last ends at the top's end
	# the landing at the start, at the foot's height (where the first flight begins)
	var u_start := lu - width if starts_far else 0.0
	landings.append({"poly": _rect_uv(at, u_start, 0.0, u_start + width, lv), "z": foot.z})
	if starts_far:   # along the other lane, under the second flight, to the far end
		var vv: float = lane_v.call(1)
		path.append(_p3(at.call(width * 0.5, vv), foot.z))
		path.append(_p3(at.call(lu - width * 0.5, vv), foot.z))
	else:
		path.append(_p3(at.call(width * 0.5, width * 0.5), foot.z))
	for i in f:
		var forward := (i % 2 == 0) != starts_far   # towards the top's end
		var vv: float = lane_v.call(i)
		var ua := width if forward else lu - width
		var ub := lu - width if forward else width
		var z0 := foot.z + dz * i
		var z1 := foot.z + dz * (i + 1)
		path.append(_p3(at.call(ua - (width * 0.5 if forward else -width * 0.5), vv), z0))
		flights.append({"a": at.call(ua, vv), "b": at.call(ub, vv), "z0": z0, "z1": z1, "side": v, "steps": st.per, "width": width})
		path.append(_p3(at.call(ub, vv), z1))
		var ul := lu - width if forward else 0.0
		landings.append({"poly": _rect_uv(at, ul, 0.0, ul + width, lv), "z": z1})
		var next_v: float = lane_v.call(i + 1) if i + 1 < f else lv - width * 0.5
		path.append(_p3(at.call(ul + width * 0.5, vv), z1))
		path.append(_p3(at.call(ul + width * 0.5, next_v), z1))
	path.append(top)
	return {"flights": flights, "landings": landings, "path": path, "rect": _rect_uv(at, 0.0, 0.0, lu, lv)}

static func _p3(p: Vector2, z: float) -> Vector3:
	return Vector3(p.x, p.y, z)

static func _rect_uv(at: Callable, u0: float, v0: float, u1: float, v1: float) -> PackedVector2Array:
	return PackedVector2Array([at.call(u0, v0), at.call(u1, v0), at.call(u1, v1), at.call(u0, v1)])

## A strip from a to b, w wide, centred on the line.
static func _strip(a: Vector2, b: Vector2, across: Vector2, w: float) -> PackedVector2Array:
	var s := across * (w * 0.5)
	return PackedVector2Array([a - s, b - s, b + s, a + s])

# ------------------------------------------------------------------ meshes and shapes (Godot axes)

## A vertical prism over a plan piece (plant coordinates) from z0 to z1, added to a SurfaceTool (top, bottom, sides).
static func add_prism(st: SurfaceTool, piece: PackedVector2Array, z0: float, z1: float, sides := true) -> void:
	var n := piece.size()
	var ccw := _signed_area(piece) > 0.0
	var top: Array = []
	var bot: Array = []
	for p in piece:
		top.append(g([p.x, p.y, z1]))
		bot.append(g([p.x, p.y, z0]))
	for i in range(1, n - 1):
		# plan counter-clockwise = Godot clockwise seen from above (z flips): wind for an outward normal
		if ccw:
			_tri(st, top[0], top[i + 1], top[i]); _tri(st, bot[0], bot[i], bot[i + 1])
		else:
			_tri(st, top[0], top[i], top[i + 1]); _tri(st, bot[0], bot[i + 1], bot[i])
	if sides:
		for i in n:
			var j := (i + 1) % n
			if ccw:
				_quad(st, bot[j], bot[i], top[i], top[j])
			else:
				_quad(st, bot[i], bot[j], top[j], top[i])

static func _signed_area(pg: PackedVector2Array) -> float:
	var s := 0.0
	for i in pg.size():
		var p := pg[i]
		var q := pg[(i + 1) % pg.size()]
		s += p.x * q.y - q.x * p.y
	return s * 0.5

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var nrm := (b - a).cross(c - a).normalized()
	# Godot's front faces are clockwise: the normal points away from the viewer that sees them clockwise
	st.set_normal(-nrm)
	for p in [a, b, c]:
		st.set_uv(_uv(p, nrm))
		st.add_vertex(p)

## Texture coordinates in metres, projected along the face's main axis (the materials scale them).
static func _uv(p: Vector3, n: Vector3) -> Vector2:
	var an := n.abs()
	if an.y >= an.x and an.y >= an.z:
		return Vector2(p.x, p.z)
	if an.x >= an.z:
		return Vector2(p.z, -p.y)
	return Vector2(p.x, -p.y)

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(st, a, b, c)
	_tri(st, a, c, d)

## The convex hull points of a vertical prism over a plan piece, for a ConvexPolygonShape3D.
static func prism_points(piece: PackedVector2Array, z0: float, z1: float) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for p in piece:
		pts.append(g([p.x, p.y, z0]))
		pts.append(g([p.x, p.y, z1]))
	return pts

## A sloped slab under a flight (plant coordinates): its top runs from (a, z0) to (b, z1), w wide, t thick.
static func ramp_points(a: Vector2, b: Vector2, side: Vector2, w: float, z0: float, z1: float, t: float) -> PackedVector3Array:
	var s := side * (w * 0.5)
	var pts := PackedVector3Array()
	for c in [[a - s, z0], [a + s, z0], [b - s, z1], [b + s, z1]]:
		var p: Vector2 = c[0]
		pts.append(g([p.x, p.y, c[1]]))
		pts.append(g([p.x, p.y, c[1] - t]))
	return pts
