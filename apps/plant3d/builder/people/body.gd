## A person's mesh (decision 0063; docs/PLANT3D.md §18.2), made by code at build time like the parts kit: our own
## body in work clothes and PPE (CC0 by authorship), in the rest pose of builder/people/rig.gd's skeleton, skinned to
## it, every colour in the vertices (one material: the plant's weathered shader with `use_vertex_colour`, so the
## people share the plant's pipelines, decision 0060). Three levels of detail from the same description:
##   2  the skinned mesh near (LOD0, ≤ 4,000 triangles)
##   1  the skinned mesh further (LOD1, ≤ 1,500 triangles)
##   0  the posed band's mesh (≤ 500 triangles; baked into poses by builder/people/build_people.gd)
## The vertex format is the plant's (position, normal, tangent, UV, colour) plus bones and weights, which only the
## skinning reads.
extends RefCounted

const Rig = preload("res://builder/people/rig.gd")

const SIDES := [5, 7, 12]
const SPHERE := [Vector2i(5, 3), Vector2i(7, 5), Vector2i(12, 8)]

var st := SurfaceTool.new()
var bone_index := {}          # bone name -> index in the skeleton
var detail := 2
var tris := 0


func _init(bones: PackedStringArray, level: int) -> void:
	for i in bones.size():
		bone_index[bones[i]] = i
	detail = level
	st.begin(Mesh.PRIMITIVE_TRIANGLES)


## The mesh of a look (builder/people/looks.gd) at this level of detail.
static func make(bones: PackedStringArray, look: Dictionary, level: int) -> ArrayMesh:
	var b = load("res://builder/people/body.gd").new(bones, level)
	b._person(look)
	return b.commit()


func commit() -> ArrayMesh:
	st.index()
	st.generate_tangents()
	var arrays := st.commit_to_arrays()
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


# ---- the person -------------------------------------------------------------------------------------------------

func _person(look: Dictionary) -> void:
	var J := Rig.JOINTS
	var c: Dictionary = look.colours
	var shirt: Color = c.get("shirt", c.suit)
	var vest: Color = c.get("vest", Color.TRANSPARENT)
	var tape: Color = c.tape
	var near := detail >= 1
	var fine := detail >= 2
	var lean: float = look.get("build", 1.0)   # 1 average; > 1 heavier
	# legs: hip to ankle, a band of reflective tape below the knee, the boot's top
	for s in [1.0, -1.0]:
		var side := "l" if s > 0 else "r"
		var x: float = J["upperleg." + side].x
		var kz: float = J["lowerleg." + side].z
		var az: float = J["foot." + side].z
		var leg := [
			[Vector3(x, 0.95, 0), 0.088 * lean, c.suit, {"upperleg." + side: 0.7, "hips": 0.3}],
			[Vector3(x, 0.78, kz * 0.4), 0.080 * lean, c.suit, {"upperleg." + side: 1.0}],
		]
		if fine:
			leg.append([Vector3(x, 0.64, kz * 0.7), 0.070 * lean, c.suit, {"upperleg." + side: 1.0}])
		leg.append([Vector3(x, 0.50, kz), 0.060 * lean, c.suit, {"upperleg." + side: 0.5, "lowerleg." + side: 0.5}])
		if near:
			leg.append_array([
				[Vector3(x, 0.335, lerpf(kz, az, 0.4)), 0.057, c.suit, {"lowerleg." + side: 1.0}],
				[Vector3(x, 0.335, lerpf(kz, az, 0.4)), 0.057, tape, {"lowerleg." + side: 1.0}],
				[Vector3(x, 0.29, lerpf(kz, az, 0.5)), 0.056, tape, {"lowerleg." + side: 1.0}],
				[Vector3(x, 0.29, lerpf(kz, az, 0.5)), 0.056, c.suit, {"lowerleg." + side: 1.0}]])
		leg.append_array([
			[Vector3(x, 0.19, lerpf(kz, az, 0.75)), 0.052, c.suit, {"lowerleg." + side: 1.0}],
			[Vector3(x, 0.19, lerpf(kz, az, 0.75)), 0.054, c.boots, {"lowerleg." + side: 1.0}],
			[Vector3(x, 0.10, az), 0.054, c.boots, {"lowerleg." + side: 0.4, "foot." + side: 0.6}]])
		_loft(leg, Vector3.FORWARD, true, false)
		# the boot: heel to toe
		var boot := [
			[Vector3(x, 0.055, az - 0.065), Vector2(0.050, 0.050), c.boots, {"foot." + side: 1.0}],
			[Vector3(x, 0.060, az + 0.03), Vector2(0.055, 0.060), c.boots, {"foot." + side: 1.0}],
			[Vector3(x, 0.050, az + 0.12), Vector2(0.052, 0.045), c.boots, {"foot." + side: 0.4, "toes." + side: 0.6}],
			[Vector3(x, 0.040, az + 0.185), Vector2(0.042, 0.035), c.boots, {"toes." + side: 1.0}]]
		_loft2(boot, Vector3.UP, true, true)
	# the torso: crotch to the neck; the vest over the coverall (or the shirt) with two bands of tape
	var t := [
		[0.85, Vector2(0.135, 0.095), c.suit, {"hips": 1.0}],
		[0.93, Vector2(0.168, 0.112), c.suit, {"hips": 1.0}],
		[1.00, Vector2(0.163, 0.108), c.suit, {"hips": 0.8, "spine": 0.2}]]
	var vest_from := 1.04
	var vest_to := 1.44
	var top: Color = shirt
	var stations := [[1.08, 0.155, 0.102], [1.18, 0.162, 0.106], [1.30, 0.178, 0.116], [1.40, 0.172, 0.112]]
	if fine:
		stations = [[1.06, 0.153, 0.101], [1.12, 0.156, 0.103], [1.18, 0.162, 0.106], [1.24, 0.170, 0.111],
			[1.30, 0.178, 0.116], [1.36, 0.177, 0.115], [1.40, 0.172, 0.112]]
	var has_vest := vest.a > 0.0
	if has_vest:
		t.append([vest_from, Vector2(0.158, 0.104) * lean, top, _torso_w(vest_from)])
		t.append([vest_from, Vector2(0.162, 0.108) * lean, vest, _torso_w(vest_from)])
	for sv in stations:
		var y: float = sv[0]
		var col: Color = vest if has_vest and y <= vest_to else top
		var r := Vector2(sv[1], sv[2]) * (lean if y < 1.35 else 1.0) + (Vector2(0.004, 0.004) if has_vest and y <= vest_to else Vector2.ZERO)
		if has_vest and near and absf(y - 1.18) < 0.001:
			# tape round the vest
			t.append([1.155, r, vest, _torso_w(1.155)])
			t.append([1.155, r, tape, _torso_w(1.155)])
			t.append([1.19, r, tape, _torso_w(1.19)])
			t.append([1.19, r, vest, _torso_w(1.19)])
			continue
		if has_vest and near and absf(y - 1.30) < 0.001:
			t.append([1.285, r, vest, _torso_w(1.285)])
			t.append([1.285, r, tape, _torso_w(1.285)])
			t.append([1.32, r, tape, _torso_w(1.32)])
			t.append([1.32, r, vest, _torso_w(1.32)])
			continue
		t.append([y, r, col, _torso_w(y)])
	if has_vest:
		t.append([vest_to, Vector2(0.168, 0.110), vest, _torso_w(vest_to)])
		t.append([vest_to, Vector2(0.164, 0.106), top, _torso_w(vest_to)])
	t.append([1.47, Vector2(0.115, 0.085), top, {"chest": 1.0}])
	t.append([1.50, Vector2(0.06, 0.052), c.skin, {"chest": 0.6, "head": 0.4}])
	t.append([1.58, Vector2(0.05, 0.048), c.skin, {"head": 1.0}])
	var loft := []
	for e in t:
		loft.append([Vector3(0, e[0], 0), e[1], e[2], e[3]])
	_loft2(loft, Vector3.FORWARD, true, true)
	# the head, the hard hat (a dome and its brim), glasses and ear defenders
	_ellipsoid(Vector3(0, 1.635, 0.012), Vector3(0.080, 0.103, 0.093), c.skin, {"head": 1.0}, 0.0, 1.0)
	_ellipsoid(Vector3(0, 1.675, 0.0), Vector3(0.106, 0.098, 0.122), c.hat, {"head": 1.0}, 0.0, 0.5)
	_ellipsoid(Vector3(0, 1.672, 0.022), Vector3(0.128, 0.011, 0.155), c.hat, {"head": 1.0}, 0.0, 1.0)
	if near:
		_box(Vector3(0, 1.645, 0.098), Vector3(0.135, 0.026, 0.012), Basis(), c.glasses, {"head": 1.0})
		if look.get("ear", true):
			for s in [1.0, -1.0]:
				_ellipsoid(Vector3(0.086 * s, 1.625, 0.0), Vector3(0.022, 0.042, 0.036), c.ear, {"head": 1.0}, 0.0, 1.0)
	# arms: shoulder to wrist (T-pose: along ±x), tape on the upper arm, the cuff, the glove
	for s in [1.0, -1.0]:
		var side := "l" if s > 0 else "r"
		var sy: float = J["upperarm." + side].y
		var ex: float = absf(J["lowerarm." + side].x)
		var wx: float = absf(J["wrist." + side].x)
		var arm := [
			[Vector3(0.13 * s, sy - 0.01, 0), 0.066, top, {"chest": 0.8, "upperarm." + side: 0.2}],
			[Vector3(0.20 * s, sy, 0), 0.064 * lean, top, {"upperarm." + side: 0.8, "chest": 0.2}]]
		if near:
			arm.append_array([
				[Vector3(0.30 * s, sy, -0.003), 0.058 * lean, top, {"upperarm." + side: 1.0}],
				[Vector3(0.30 * s, sy, -0.003), 0.058 * lean, tape, {"upperarm." + side: 1.0}],
				[Vector3(0.335 * s, sy, -0.004), 0.057 * lean, tape, {"upperarm." + side: 1.0}],
				[Vector3(0.335 * s, sy, -0.004), 0.057 * lean, top, {"upperarm." + side: 1.0}]])
		elif fine:
			arm.append([Vector3(0.33 * s, sy, -0.004), 0.057, top, {"upperarm." + side: 1.0}])
		arm.append([Vector3(ex * s, sy, -0.01), 0.048, top, {"upperarm." + side: 0.5, "lowerarm." + side: 0.5}])
		if fine:
			arm.append([Vector3(lerpf(ex, wx, 0.5) * s, sy, -0.005), 0.044, top, {"lowerarm." + side: 1.0}])
		arm.append_array([
			[Vector3((wx - 0.015) * s, sy, 0), 0.039, top, {"lowerarm." + side: 0.7, "wrist." + side: 0.3}],
			[Vector3((wx - 0.015) * s, sy, 0), 0.040, c.gloves, {"lowerarm." + side: 0.7, "wrist." + side: 0.3}],
			[Vector3((wx + 0.02) * s, sy, 0), 0.036, c.gloves, {"wrist." + side: 1.0}]])
		_loft(arm, Vector3.UP, true, true)
		# the hand (a gloved mitten with a thumb)
		_ellipsoid(Vector3((wx + 0.075) * s, sy - 0.005, 0.005), Vector3(0.058, 0.026, 0.045), c.gloves,
			{"hand." + side: 0.8, "wrist." + side: 0.2}, 0.0, 1.0)
		if near:
			_ellipsoid(Vector3((wx + 0.045) * s, sy - 0.004, 0.045), Vector3(0.028, 0.017, 0.016), c.gloves,
				{"hand." + side: 1.0}, 0.0, 1.0)
	if near:
		_accessories(look)


func _torso_w(y: float) -> Dictionary:
	if y < 1.0:
		return {"hips": 1.0}
	if y < 1.15:
		var k := (y - 1.0) / 0.15
		return {"hips": 1.0 - k, "spine": k}
	if y < 1.32:
		var k := (y - 1.15) / 0.17
		return {"spine": 1.0 - k, "chest": k}
	return {"chest": 1.0}


func _accessories(look: Dictionary) -> void:
	var dark := Color(0.16, 0.16, 0.17)
	for a in look.get("carry", []):
		match a:
			"radio":   # on the chest, left
				_box(Vector3(0.075, 1.33, 0.125), Vector3(0.055, 0.10, 0.03), Basis(), dark, {"chest": 1.0})
				_box(Vector3(0.09, 1.41, 0.125), Vector3(0.009, 0.07, 0.009), Basis(), dark, {"chest": 1.0})
			"clipboard":   # held in the left hand (T-pose: along +x from the palm, flat)
				var hx: float = Rig.JOINTS["hand.l"].x
				_box(Vector3(hx + 0.12, 1.405, 0.045), Vector3(0.30, 0.012, 0.22), Basis(), Color(0.42, 0.31, 0.2), {"hand.l": 1.0})
				_box(Vector3(hx + 0.125, 1.413, 0.045), Vector3(0.26, 0.004, 0.19), Basis(), Color(0.92, 0.92, 0.9), {"hand.l": 1.0})
			"belt":   # a tool belt with pouches
				_loft2([[Vector3(0, 0.985, 0), Vector2(0.178, 0.122), Color(0.24, 0.18, 0.12), {"hips": 1.0}],
					[Vector3(0, 1.035, 0), Vector2(0.172, 0.118), Color(0.24, 0.18, 0.12), {"hips": 0.8, "spine": 0.2}]],
					Vector3.FORWARD, false, false)
				for s in [1.0, -1.0]:
					_box(Vector3(0.155 * s, 0.95, 0.05), Vector3(0.05, 0.10, 0.08), Basis(), Color(0.30, 0.22, 0.14), {"hips": 1.0})
				_box(Vector3(-0.17, 0.93, -0.03), Vector3(0.025, 0.16, 0.035), Basis(), Color(0.55, 0.12, 0.10), {"hips": 1.0})
			"bag":   # the calibrator's case at the right hip, its strap over the left shoulder
				_box(Vector3(-0.19, 0.98, 0.03), Vector3(0.07, 0.15, 0.19), Basis(), Color(0.20, 0.21, 0.24), {"hips": 1.0})
				_box(Vector3(-0.02, 1.25, 0.122), Vector3(0.035, 0.52, 0.008), Basis(Vector3.FORWARD, -0.62), dark,
					{"chest": 0.6, "spine": 0.4})


# ---- shapes -----------------------------------------------------------------------------------------------------

## A tube through stations [centre, radius, colour, weights] (round), cross-sections square to the path; `ref` a
## direction across the path; caps at the ends where asked.
func _loft(stations: Array, ref: Vector3, cap0: bool, cap1: bool) -> void:
	var s2 := []
	for e in stations:
		s2.append([e[0], Vector2(e[1], e[1]), e[2], e[3]])
	_loft2(s2, ref, cap0, cap1)


## The same with elliptical cross-sections: radius.x along `ref`, radius.y across both.
func _loft2(stations: Array, ref: Vector3, cap0: bool, cap1: bool) -> void:
	var n: int = SIDES[detail]
	var rings := []
	for i in stations.size():
		var p: Vector3 = stations[i][0]
		var a: Vector3 = stations[mini(i + 1, stations.size() - 1)][0]
		var b: Vector3 = stations[maxi(i - 1, 0)][0]
		var dir := (a - b)
		if dir.length() < 1e-5:
			# a station repeated (a colour's edge): the direction of the stations around it
			for j in range(i + 1, stations.size()):
				if (stations[j][0] - p).length() > 1e-5:
					dir = stations[j][0] - p
					break
			if dir.length() < 1e-5:
				dir = p - b
		dir = dir.normalized()
		var u := (ref - dir * ref.dot(dir)).normalized()
		var v := dir.cross(u).normalized()
		var r: Vector2 = stations[i][1]
		var ring := []
		for k in n:
			var ang := TAU * k / n
			var off := u * cos(ang) * r.x + v * sin(ang) * r.y
			var nrm := (u * cos(ang) * r.y + v * sin(ang) * r.x).normalized()
			ring.append([p + off, nrm])
		rings.append(ring)
	for i in stations.size() - 1:
		if (stations[i + 1][0] - stations[i][0]).length() < 1e-5:
			continue   # a colour's edge: no faces between the two rings
		for k in n:
			var k2 := (k + 1) % n
			var col: Color = stations[i][2]
			var col2: Color = stations[i + 1][2]
			_tri([rings[i][k], rings[i + 1][k], rings[i + 1][k2]], [col, col2, col2],
				[stations[i][3], stations[i + 1][3], stations[i + 1][3]])
			_tri([rings[i][k], rings[i + 1][k2], rings[i][k2]], [col, col2, col],
				[stations[i][3], stations[i + 1][3], stations[i][3]])
	for end in [0, stations.size() - 1]:
		if (end == 0 and not cap0) or (end != 0 and not cap1):
			continue
		var ring: Array = rings[end]
		var cen: Vector3 = stations[end][0]
		var nrm: Vector3 = (stations[end][0] - stations[1 if end == 0 else end - 1][0]).normalized()
		for k in n:
			var k2 := (k + 1) % n
			var a: Array = [[cen, nrm], [ring[k][0], nrm], [ring[k2][0], nrm]]
			if end != 0:
				a = [[cen, nrm], [ring[k2][0], nrm], [ring[k][0], nrm]]
			_tri(a, [stations[end][2], stations[end][2], stations[end][2]], [stations[end][3], stations[end][3], stations[end][3]])


## An ellipsoid (or its part between two heights: v0, v1 in 0..1 from the top), all on the same weights.
func _ellipsoid(c: Vector3, r: Vector3, col: Color, w: Dictionary, v0: float, v1: float) -> void:
	var s: Vector2i = SPHERE[detail]
	var cols := [col, col, col]
	var ws := [w, w, w]
	var pts := []
	for j in s.y + 1:
		var th := PI * lerpf(v0, v1, float(j) / s.y)
		var row := []
		for k in s.x:
			var ph := TAU * k / s.x
			var d := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
			row.append([c + d * r, Vector3(d.x / r.x, d.y / r.y, d.z / r.z).normalized()])
		pts.append(row)
	for j in s.y:
		for k in s.x:
			var k2 := (k + 1) % s.x
			if j > 0 or v0 > 0.0:
				_tri([pts[j][k], pts[j][k2], pts[j + 1][k2]], cols, ws)
			if j < s.y - 1 or v1 < 1.0:
				_tri([pts[j][k], pts[j + 1][k2], pts[j + 1][k]], cols, ws)
	if v1 < 1.0:
		# close the cut (the hat's dome stands on its brim: a flat underside)
		var y := c.y + cos(PI * v1) * r.y
		for k in s.x:
			var k2 := (k + 1) % s.x
			_tri([[Vector3(c.x, y, c.z), Vector3.DOWN], pts[s.y][k2], pts[s.y][k]], cols, ws)


func _box(c: Vector3, size: Vector3, b: Basis, col: Color, w: Dictionary) -> void:
	var h := size * 0.5
	var cols := [col, col, col]
	var ws := [w, w, w]
	for axis in 3:
		for sgn in [1.0, -1.0]:
			var n := Vector3.ZERO
			n[axis] = sgn
			var u := Vector3.ZERO
			u[(axis + 1) % 3] = 1.0
			var v := n.cross(u)
			var q := []
			for k in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
				var p: Vector3 = n * h[axis] + u * h[(axis + 1) % 3] * k[0] + v * h[(axis + 2) % 3] * k[1]
				q.append([c + b * p, (b * n).normalized()])
			_tri([q[0], q[2], q[1]], cols, ws)
			_tri([q[0], q[3], q[2]], cols, ws)


## One triangle: vertices [position, normal], their colours and bone weights. Wound so that its face points along the
## normals (Godot draws clockwise faces as front faces: the winding is checked against the normals here).
func _tri(v: Array, cols: Array, ws: Array) -> void:
	var a: Vector3 = v[0][0]
	var b: Vector3 = v[1][0]
	var c: Vector3 = v[2][0]
	var fn := (b - a).cross(c - a)
	var avg: Vector3 = v[0][1] + v[1][1] + v[2][1]
	var order := [0, 1, 2] if fn.dot(avg) < 0.0 else [0, 2, 1]
	for i in order:
		st.set_color(cols[i])
		st.set_normal(v[i][1])
		st.set_uv(Vector2(v[i][0].x + v[i][0].z, v[i][0].y))
		var bones := PackedInt32Array([0, 0, 0, 0])
		var weights := PackedFloat32Array([0, 0, 0, 0])
		var j := 0
		var total := 0.0
		for bn in ws[i]:
			if j < 4:
				bones[j] = bone_index[bn]
				weights[j] = ws[i][bn]
				total += ws[i][bn]
				j += 1
		for k in j:
			weights[k] /= total
		st.set_bones(bones)
		st.set_weights(weights)
		st.add_vertex(v[i][0])
	tris += 1
