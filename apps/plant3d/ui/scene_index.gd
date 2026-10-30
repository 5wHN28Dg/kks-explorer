## The plant's equipment as the built scenes hold it: every node carrying a `kks` meta (equipment, its parts, pipes and
## the valves on them; builder/ names each node by its code), where each one is and how big, and which one the trainee
## points at (a ray through the view first, then the nearest code on screen, for small parts without collision).
extends RefCounted

const PICK_PX := 48.0           # a tap within this many pixels of a part's centre on screen picks it
const PICK_RANGE := 40.0        # metres: farther parts are not picked by a tap

var nodes := {}                 # code -> Node3D
var _boxes := {}                # code -> AABB (global), cached


func scan(root: Node) -> void:
	nodes.clear()
	_boxes.clear()
	_walk(root)


func _walk(n: Node) -> void:
	if n.has_meta("kks") and n is Node3D and not nodes.has(n.get_meta("kks")):
		nodes[String(n.get_meta("kks"))] = n
	for c in n.get_children():
		_walk(c)


## A part that moved (a code riding on a hoist, ui/bindings.gd): its bounds are measured again when next asked.
func forget(code: String) -> void:
	_boxes.erase(code)


func has(code: String) -> bool:
	return nodes.has(code)


## The part's bounds in the world: every mesh under its node (labels and the app's own markers left out).
func box(code: String) -> AABB:
	if _boxes.has(code):
		return _boxes[code]
	var n: Node3D = nodes.get(code)
	if n == null:
		return AABB()
	if n.has_meta("aabb"):               # the parts kit's box in the node's own axes (its meshes are instanced per cell)
		var bb: AABB = n.get_meta("aabb")
		_boxes[code] = n.global_transform * bb
		return _boxes[code]
	var b := AABB()
	var any := false
	for mi in _meshes(n):
		var a: AABB = mi.global_transform * mi.get_aabb()
		b = a if not any else b.merge(a)
		any = true
	if not any:
		b = AABB(n.global_position - Vector3(0.5, 0, 0.5), Vector3(1, 1, 1))
	_boxes[code] = b
	return b


static func _meshes(n: Node) -> Array:
	var out := []
	for c in n.get_children():
		if c.has_meta("kks") or c.has_meta("ui"):
			continue          # another code's node, or the app's own marker
		if c is MeshInstance3D:
			out.append(c)
		out.append_array(_meshes(c))
	return out


func center(code: String) -> Vector3:
	return box(code).get_center()


## Metres from a point to the part's bounds (0 inside).
func distance(code: String, p: Vector3) -> float:
	var b := box(code)
	var q := p.clamp(b.position, b.end)
	return q.distance_to(p)


## The code under a screen point: the first body a ray hits that belongs to a code, else the nearest code whose
## centre is within PICK_PX on screen and in sight range. "" when none.
func pick(cam: Camera3D, at: Vector2, space: PhysicsDirectSpaceState3D, exclude: Array = []) -> String:
	var from := cam.project_ray_origin(at)
	var dir := cam.project_ray_normal(at)
	var hit_d := PICK_RANGE
	if space != null:
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * PICK_RANGE)
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			var c := code_of(hit.collider)
			if c != "":
				return c
			hit_d = from.distance_to(hit.position)
	var best := ""
	var best_px := PICK_PX
	for code in nodes:
		var p := center(code)
		var d := from.distance_to(p)
		if d > hit_d + 1.0 or d > PICK_RANGE or cam.is_position_behind(p):
			continue
		var px := cam.unproject_position(p).distance_to(at)
		if px < best_px:
			best_px = px
			best = code
	return best


static func code_of(n) -> String:
	while n != null and n is Node:
		if n.has_meta("kks"):
			return String(n.get_meta("kks"))
		n = n.get_parent()
	return ""
