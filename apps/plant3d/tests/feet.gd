## Where a skinned avatar's soles are (tests/test_people_feet.gd, tests/test_people_motion.gd): the body's vertices
## that carry the soles (weighted to the feet and toes, below 0.12 m at rest; builder/people/build_people.gd), skinned
## as app/people.gd's avatar is posed now, in the world; and a foot's slide: how far the point of a sole that is on
## the floor moves while it is there, against the ground the person covers.
extends RefCounted

const BP = preload("res://builder/people/build_people.gd")
## of the ground covered, at most (tests/test_people_feet.gd SLIDE: KayKit's walk sets a foot down still moving forward,
## and the crossfades between standing and walking slide, without IK)
const SLIDE := 0.15

var pos := PackedVector3Array()     # the sole's vertices at rest
var wts: Array = []                 # per vertex: [[bone, weight]…]
var left := PackedByteArray()       # per vertex: 1 on the left foot
# slide(): kept from one update to the next
var slid := 0.0                     # metres the point on the floor moved
var covered := 0.0                  # metres the person covered meanwhile (in plan)
var worst := 0.0                    # the most it moved over one stance
var _foot := -1
var _vertex := -1
var _prev := PackedVector3Array()
var _stance := 0.0
var _body := Vector3.INF


## The sole vertices of `info` (people.json)'s first look.
static func of(info: Dictionary):
	var f = new()
	var look: String = info.looks.keys()[0]
	var m: ArrayMesh = load(info.looks[look].lod0)
	var a := m.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
	var w: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
	var scn: Node3D = (load(info.avatar) as PackedScene).instantiate()
	var sk: Skeleton3D = scn.get_node("Skeleton3D")
	var ids := []
	for b in BP.SOLE_BONES:
		ids.append(sk.find_bone(b))
	scn.free()
	for i in v.size():
		if v[i].y > 0.12:
			continue
		var on_foot := 0.0
		var bw := []
		for k in 4:
			if w[i * 4 + k] > 0.0:
				bw.append([bones[i * 4 + k], w[i * 4 + k]])
				if bones[i * 4 + k] in ids:
					on_foot += w[i * 4 + k]
		if on_foot >= 0.5:
			f.pos.append(v[i])
			f.wts.append(bw)
			f.left.append(1 if v[i].x > 0.0 else 0)
	return f


## The soles' vertices in the world, as the avatar `node` (app/people.gd's) is posed now.
func world(node: Node3D) -> PackedVector3Array:
	var sk: Skeleton3D = node.get_node("Skeleton3D")
	var skin := []
	for b in sk.get_bone_count():
		skin.append(sk.get_bone_global_pose(b) * sk.get_bone_global_rest(b).affine_inverse())
	var xf := sk.global_transform
	var out := PackedVector3Array()
	out.resize(pos.size())
	for i in pos.size():
		var p := Vector3.ZERO
		for bw in wts[i]:
			p += ((skin[bw[0]] as Transform3D) * pos[i]) * float(bw[1])
		out[i] = xf * p
	return out


## The lowest vertex of each foot: [left index, right index] into `pts` (world()).
func lowest(pts: PackedVector3Array) -> Array:
	var lo := [-1, -1]
	for i in pts.size():
		var s := 0 if left[i] == 1 else 1
		if lo[s] < 0 or pts[i].y < pts[lo[s]].y:
			lo[s] = i
	return lo


## One update of the slide: the soles `pts` (world()), the body's feet point `body`, `floor_of` the floor's height
## under a point (a Callable; on a flight its tread's), `on` how near the floor a sole counts as on it. The point of
## the soles on the floor at the last update (the lowest, within `on` of its floor) is followed to this one: if it is
## still on the floor, how far it moved counts (a stance: while the same foot holds the lowest point).
func slide(pts: PackedVector3Array, body: Vector3, floor_of: Callable, on := 0.02) -> void:
	if _body != Vector3.INF:
		covered += Vector2(body.x - _body.x, body.z - _body.z).length()
	_body = body
	if _vertex >= 0:
		var a := _prev[_vertex]
		var b := pts[_vertex]
		if b.y - float(floor_of.call(b)) <= on:
			var d := Vector2(b.x - a.x, b.z - a.z).length()
			slid += d
			_stance += d
			worst = maxf(worst, _stance)
	var lo := 0
	var gap := INF
	for i in pts.size():
		var g := pts[i].y - float(floor_of.call(pts[i]))
		if g < gap:
			gap = g
			lo = i
	var foot := int(left[lo])
	if foot != _foot:
		_stance = 0.0
	_foot = foot
	_vertex = lo if gap <= on else -1
	_prev = pts


func ratio() -> float:
	return slid / covered if covered > 0.0 else 0.0
