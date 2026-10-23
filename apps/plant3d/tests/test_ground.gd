## The ground in the built plant (builder/site.gd, the areas' roads): no two upward-facing surfaces at ground level lie
## in the same plane over the same ground. Two such surfaces fight in the depth buffer: which one is drawn changes from
## pixel to pixel and frame to frame, worst on a phone's 24-bit depth buffer far from the camera (2026-10-23: on the
## Note 9, on the road to the camp, the country's terrain lay in the camp's gravel's plane over the whole 20 m strip
## and showed through it in patches with straight seams that moved as one walked).
## Checked over every area's scene and the ground's: each pair of upward faces near z = 0 whose plans overlap, and
## that are near parallel, must stand at least MIN_GAP apart everywhere they overlap, or not overlap by more than a
## sliver (OVERLAP_AREA). Pieces never drawn together (their visibility ranges do not meet) do not count.
extends RefCounted

const Plant = preload("res://app/plant.gd")
const Builder = preload("res://builder/plant_builder.gd")
const Site = preload("res://builder/site.gd")

const GROUND := 0.6          # faces with every corner within this of z = 0 are the ground's
const MIN_GAP := 0.015       # metres between two surfaces drawn over each other: a phone's 24-bit depth buffer with the near plane at 5 cm resolves 1.5 cm to about 110 m, 2 cm to about 130 m (beyond, a ground piece is a few pixels)
const PARALLEL := 0.9986     # cos 3°: surfaces closer to parallel than this fight where they meet (crossing ones meet in a line)
const OVERLAP_AREA := 0.02   # m² of overlap within MIN_GAP that counts as a fight
const BIN := 8.0
const SLIVER := 0.001        # m²: an overlap smaller than this between two faces is rounding

func run(tree: SceneTree) -> Array:
	var world := Node3D.new()
	tree.root.add_child(world)
	var plant := Plant.new()
	world.add_child(plant)
	var err := plant.load_plant()
	if err == "":
		err = plant.load_interiors()   # their furniture stands on the halls' floors
	if err != "":
		world.free()
		return [err]
	var tris := faces(plant, -12.0)   # down to the deepest pit's floor
	var p := fights(tris)
	if tris.size() < 1000:
		p.append("the ground's faces are read from the built plant (%d)" % tris.size())
	p.append_array(terrain_meets_ground(plant))
	p.append_array(no_gaps(tris))
	world.free()
	return p

## The site's own ground (the wall's rect, the camp's areas), as builder/site.gd lays it.
static func ground_rects() -> Array:
	var b := Builder.new()
	var data := ProjectSettings.globalize_path("res://").path_join("../../data/plant3d").simplify_path()
	if not b.read(data) or not b.collect():
		return []
	var s := Site.new(b)
	return s.ground_rects(s.wall_rect())

## The terrain lies nowhere over the site's own ground, and meets its edges at the ground's height (no step, no gap).
static func terrain_meets_ground(root: Node) -> Array:
	var zones := ground_rects()
	if zones.is_empty():
		return ["the content builds (the site's ground rects)"]
	var t := root.find_child("terrain", true, false) as MeshInstance3D
	if t == null or t.mesh == null:
		return ["the built plant has its terrain"]
	var p: Array = []
	var v: PackedVector3Array = t.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = t.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	var on_edge := 0
	for k in range(0, idx.size(), 3):
		var c := Vector2.ZERO
		for m in 3:
			var q: Vector3 = t.global_transform * v[idx[k + m]]
			var pl := Vector2(q.x, -q.z)   # plan (x east, y north)
			c += pl / 3.0
			for r in zones:
				var rr: Rect2 = r
				if rr.grow(0.01).has_point(pl) and not rr.grow(-0.01).has_point(pl):
					on_edge += 1
					if absf(q.y) > 0.001:
						p.append("the terrain meets the ground's edge at plan %s at height %.3f, not 0" % [str(pl), q.y])
		for r in zones:
			if (r as Rect2).has_point(c):
				p.append("a terrain triangle lies over the site's ground at plan %s" % str(c))
				break
		if p.size() > 5:
			return p
	if on_edge < 100:
		p.append("the terrain's edge runs along the site's ground (%d corners on it)" % on_edge)
	return p

## Every plan point of the site's ground, and 30 m of the country round it, is covered by an upward face (the
## ground's slabs, the areas' roads and buildings' floors, a pit's floor, the terrain): no gap shows the void below.
## Sampled every GAP_STEP metres (off the content's whole and half metres).
const GAP_STEP := 1.3731
static func no_gaps(tris: Array) -> Array:
	var zones := ground_rects()
	var bins := {}
	for i in tris.size():
		var r := _plan_box(tris[i])
		for bx in range(floori(r.position.x / BIN), floori(r.end.x / BIN) + 1):
			for bz in range(floori(r.position.y / BIN), floori(r.end.y / BIN) + 1):
				var k := Vector2i(bx, bz)
				if not bins.has(k):
					bins[k] = []
				bins[k].append(i)
	var p: Array = []
	var n := 0
	for zr in zones:
		var r: Rect2 = (zr as Rect2).grow(30.0)
		var y := r.position.y + 0.1129
		while y < r.end.y:
			var x := r.position.x + 0.1337
			while x < r.end.x:
				var q := Vector2(x, -y)   # (x, z) in Godot's plan
				n += 1
				var hit := false
				for i in bins.get(Vector2i(floori(q.x / BIN), floori(q.y / BIN)), []):
					var t: Array = tris[i]
					if Geometry2D.point_is_inside_triangle(q, Vector2(t[0].x, t[0].z), Vector2(t[1].x, t[1].z), Vector2(t[2].x, t[2].z)):
						hit = true
						break
				if not hit:
					p.append("nothing covers the ground at plan (%.1f, %.1f): a gap" % [x, y])
					if p.size() > 5:
						return p
				x += GAP_STEP
			y += GAP_STEP
	if n < 10000:
		p.append("the ground is sampled for gaps (%d points)" % n)
	return p

## The upward faces near z = 0 (from `lo`) of every drawn mesh under root, the instanced pieces' (MultiMeshes: the
## planting, the kit's repeated parts) each in place: [a, b, c (Vector3, world), name, range begin, range end].
static func faces(root: Node, lo := -GROUND) -> Array:
	var out: Array = []
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		if not gi.is_visible_in_tree():
			continue
		var mesh: Mesh = null
		var xfs: Array = []
		if gi is MeshInstance3D:
			mesh = (gi as MeshInstance3D).mesh
			xfs = [gi.global_transform]
		elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh != null:
			var mm := (gi as MultiMeshInstance3D).multimesh
			mesh = mm.mesh
			# from the build's saved buffer (app/plant.gd fill_cells): the headless renderer keeps no MultiMesh data
			if not gi.has_meta("xforms"):
				continue
			var buf: PackedFloat32Array = gi.get_meta("xforms")
			var cnt := int(gi.get_meta("count"))
			if cnt <= 0:
				continue
			var stride := buf.size() / cnt   # 12 floats of transform, then colour and custom data if any
			for k in cnt:
				var o := k * stride
				var xf := Transform3D(Basis(Vector3(buf[o], buf[o + 4], buf[o + 8]), Vector3(buf[o + 1], buf[o + 5], buf[o + 9]),
					Vector3(buf[o + 2], buf[o + 6], buf[o + 10])), Vector3(buf[o + 3], buf[o + 7], buf[o + 11]))
				xfs.append(gi.global_transform * xf)
		if mesh == null or xfs.is_empty():
			continue
		var nm := String(root.get_path_to(gi))
		for s in mesh.get_surface_count():
			var arr: Array = mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var count := idx.size() if idx.size() > 0 else v.size()
			var tris := PackedInt32Array()   # the first vertex of each triangle to look at
			for t in range(0, count - 2, 3):
				var ly := maxf(v[idx[t] if idx.size() > 0 else t].y, maxf(v[idx[t + 1] if idx.size() > 0 else t + 1].y,
					v[idx[t + 2] if idx.size() > 0 else t + 2].y))
				# an instanced piece stands upright on its origin: only its low faces can lie on the ground
				if xfs.size() == 1 or ly <= 1.0:
					tris.append(t)
			for xf: Transform3D in xfs:
				for t in tris:
					var a: Vector3 = xf * v[idx[t] if idx.size() > 0 else t]
					var b: Vector3 = xf * v[idx[t + 1] if idx.size() > 0 else t + 1]
					var c: Vector3 = xf * v[idx[t + 2] if idx.size() > 0 else t + 2]
					if a.y > GROUND or b.y > GROUND or c.y > GROUND or a.y < lo or b.y < lo or c.y < lo:
						continue
					# Godot's front face is clockwise seen from the front: its normal is (c - a) × (b - a)
					var nrm := (c - a).cross(b - a)
					if nrm.length_squared() < 1e-10 or nrm.normalized().y < 0.7:
						continue
					out.append([a, b, c, nm, gi.visibility_range_begin, gi.visibility_range_end])
	return out

## The fights between the faces: a list of problems (at most a few, each naming the two pieces and where).
static func fights(tris: Array) -> Array:
	var bins := {}
	for i in tris.size():
		var r := _plan_box(tris[i])
		for bx in range(floori(r.position.x / BIN), floori(r.end.x / BIN) + 1):
			for bz in range(floori(r.position.y / BIN), floori(r.end.y / BIN) + 1):
				var k := Vector2i(bx, bz)
				if not bins.has(k):
					bins[k] = []
				bins[k].append(i)
	# the overlap is added up per pair of pieces (two pieces cut into small triangles fight as much as two whole ones)
	var total := {}   # [name, name] -> [m², first face, second face of the largest overlap, its m²]
	var checked := {}
	for k in bins:
		var list: Array = bins[k]
		for ii in list.size():
			var i: int = list[ii]
			for jj in range(ii + 1, list.size()):
				var j: int = list[jj]
				var key := Vector2i(mini(i, j), maxi(i, j))
				if checked.has(key):
					continue
				checked[key] = true
				if not _ground_pair(tris[i], tris[j]):
					continue
				var area := fight_area(tris[i], tris[j])
				if area <= SLIVER:
					continue   # (two faces that only touch along an edge: float rounding)
				var pair := [tris[i][3], tris[j][3]]
				pair.sort()
				if not total.has(pair):
					total[pair] = [0.0, i, j, 0.0]
				total[pair][0] += area
				if area > total[pair][3]:
					total[pair][1] = i
					total[pair][2] = j
					total[pair][3] = area
	var p: Array = []
	for pair in total:
		var e: Array = total[pair]
		if e[0] > OVERLAP_AREA:
			var at := _overlap_point(tris[e[1]], tris[e[2]])
			p.append("%s and %s lie in one plane (z %.3f and %.3f) over %.2f m² of ground, e.g. at plan (%.1f, %.1f): they fight in the depth buffer" % [
				pair[0], pair[1], _h(tris[e[1]], at), _h(tris[e[2]], at), e[0], at.x, -at.y])
	p.sort()
	return p.slice(0, 40)

## Whether a pair of faces is the ground's business: a structure's or the ground's own pieces (slabs, roads, floors,
## pits' floors and walls, the terrain) at any depth down to the deepest pit; a kit piece (equipment, planting,
## furniture) against one of those, or two kit pieces lying on the ground (within KIT_GROUND of it). Two pieces of
## one machine down in a pit are the parts kit's own detail, not the ground.
const KIT_GROUND := 0.1
static func _ground_pair(s: Array, t: Array) -> bool:
	var ks: bool = String(s[3]).contains("/kit/")
	var kt: bool = String(t[3]).contains("/kit/")
	if not (ks and kt):
		return true
	for f in [s, t]:
		for k in 3:
			if absf((f[k] as Vector3).y) > KIT_GROUND:
				return false
	return true

## A plan point (x, z) in the overlap of two faces' plans (the middle of the first overlap's corners).
static func _overlap_point(s: Array, t: Array) -> Vector2:
	var ps := PackedVector2Array([Vector2(s[0].x, s[0].z), Vector2(s[1].x, s[1].z), Vector2(s[2].x, s[2].z)])
	var pt := PackedVector2Array([Vector2(t[0].x, t[0].z), Vector2(t[1].x, t[1].z), Vector2(t[2].x, t[2].z)])
	var m := Vector2.ZERO
	for poly in Geometry2D.intersect_polygons(ps, pt):
		for q in poly:
			m += q
		return m / (poly as PackedVector2Array).size()
	return ps[0]

static func _plan_box(t: Array) -> Rect2:
	var r := Rect2(Vector2(t[0].x, t[0].z), Vector2.ZERO)
	r = r.expand(Vector2(t[1].x, t[1].z))
	return r.expand(Vector2(t[2].x, t[2].z))

## The plan area over which faces s and t (as `faces` gives them) are near parallel and within MIN_GAP of each other:
## 0 when they are never drawn together, cross at an angle, or do not overlap.
static func fight_area(s: Array, t: Array) -> float:
	if not _ranges_meet(s[4], s[5], t[4], t[5]):
		return 0.0
	var ns := (s[2] - s[0]).cross(s[1] - s[0]).normalized() as Vector3
	var nt := (t[2] - t[0]).cross(t[1] - t[0]).normalized() as Vector3
	if ns.dot(nt) < PARALLEL:
		return 0.0
	if not _plan_box(s).intersects(_plan_box(t)):
		return 0.0
	# (about the first face's corner: single precision hundreds of metres from the plant's origin rounds too coarsely)
	var o := Vector2(s[0].x, s[0].z)
	var ps := PackedVector2Array([Vector2(s[0].x, s[0].z) - o, Vector2(s[1].x, s[1].z) - o, Vector2(s[2].x, s[2].z) - o])
	var pt := PackedVector2Array([Vector2(t[0].x, t[0].z) - o, Vector2(t[1].x, t[1].z) - o, Vector2(t[2].x, t[2].z) - o])
	var total := 0.0
	for poly in Geometry2D.intersect_polygons(ps, pt):
		# the height between the two planes is linear over the overlap: keep where it is within ±MIN_GAP
		var q := PackedVector2Array()
		for v in poly:
			q.append(v + o)
		q = _clip(q, s, t, 1.0)
		q = _clip(q, s, t, -1.0)
		total += _area(q)
	return total

## Keeps the part of polygon q where sign × (height of s − height of t) ≤ MIN_GAP.
static func _clip(q: PackedVector2Array, s: Array, t: Array, sign: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := q.size()
	for k in n:
		var a := q[k]
		var c := q[(k + 1) % n]
		var fa := sign * (_h(s, a) - _h(t, a)) - MIN_GAP
		var fc := sign * (_h(s, c) - _h(t, c)) - MIN_GAP
		if fa <= 0.0:
			out.append(a)
		if (fa < 0.0) != (fc < 0.0) and absf(fa - fc) > 1e-12:
			out.append(a.lerp(c, fa / (fa - fc)))
	return out

## The height of face t's plane over plan point p.
static func _h(t: Array, p: Vector2) -> float:
	var a: Vector3 = t[0]
	var nrm := (t[2] - a).cross(t[1] - a) as Vector3
	if absf(nrm.y) < 1e-9:
		return a.y
	return a.y - (nrm.x * (p.x - a.x) + nrm.z * (p.y - a.z)) / nrm.y

static func _area(q: PackedVector2Array) -> float:
	# about its first corner: Vector2 is single precision, and cross products of coordinates hundreds of metres out
	# round to 0.002 m²
	var s := 0.0
	for k in range(1, q.size() - 1):
		s += (q[k] - q[0]).cross(q[k + 1] - q[0])
	return absf(s) * 0.5

## Whether two visibility ranges (begin, end; an end of 0 is no end) are ever both drawn.
static func _ranges_meet(b0: float, e0: float, b1: float, e1: float) -> bool:
	var end0 := e0 if e0 > 0.0 else INF
	var end1 := e1 if e1 > 0.0 else INF
	return b0 < end1 and b1 < end0
