## Doors open for people as for the trainee (docs/PLANT3D.md §18.1; app/door.gd opens for the walkers itself): HZ
## times a second, everyone app/people.gd draws who is walking towards a door's leaf, or through it, presses it
## (door.gd press(): open, and open HOLD seconds more) once they are within NEAR of it, or LEAD seconds of their
## speed (a runner's opens sooner). Doors are found by a grid of CELL metres made when the doors change (the interiors'
## come and go), so a check looks only at the doors near each person. View only: a door's opening changes nothing
## in the engine.
extends RefCounted

const HZ := 4.0
const CELL := 8.0               # metres: the grid's cells
const SIDE := 0.5               # metres beyond a door's edges that someone walking at it is taken as going through
const NEAR := 2.5               # metres in front of or behind its leaf at which it opens for someone walking at it
const LEAD := 2.0               # seconds ahead: a faster walker's door opens this long before they reach it
const REACH := 8.0              # metres: the farthest that is looked (LEAD at a run, and more)
const IN := 1.6                 # metres from its leaf within which it opens for anyone walking at its width (through it,
                                # or turning into it)
const TOWARDS := 0.3            # walking at a door: the cosine of the angle off its normal, at least (not along it)
const STILL := 0.15             # m/s: slower than this is standing (app/people.gd)

var _doors: Array = []          # [door, its shut transform's inverse (global), half its width and SIDE, its height]
var _cells := {}                # Vector2i -> Array of _doors' indices
var _count := -1
var _sig := 0
var _t := 0.0
var pressed := 0                # presses made (the tests)


func _init(phase := 0.0) -> void:
	_t = phase


## The check, when it is due (every 1 / HZ s): `people` as app/people.gd has them.
func tick(tree: SceneTree, people: Array, delta: float) -> void:
	_t += delta
	if _t < 1.0 / HZ:
		return
	_t = 0.0
	check(tree, people)


## Every person walking at or through a door presses it.
func check(tree: SceneTree, people: Array) -> void:
	# made again when the doors change (the interiors' come and go: two may change places with the same count)
	var sig := 0
	for d in tree.get_nodes_in_group("doors"):
		sig = (sig * 31 + d.get_instance_id()) & 0x7fffffffffff
	if sig != _sig or _count < 0:
		_sig = sig
		_index(tree)
	for p in people:
		var v: float = p.get("speed", 0.0)
		if v <= STILL:
			continue
		var at: Vector3 = p.at
		var list = _cells.get(Vector2i(floori(at.x / CELL), floori(at.z / CELL)))
		if list == null:
			continue
		# the way they walk (`dir`, from their line), else the way they face
		var f: Vector3 = p.get("dir", Vector3.ZERO)
		if f.length_squared() < 0.25:
			var yaw: float = p.get("yaw", 0.0)
			f = Vector3(-sin(yaw), 0.0, -cos(yaw))
		for k in list:
			var d: Array = _doors[k]
			if not is_instance_valid(d[0]):
				_count = -1          # (freed with its interior: the grid is made again at the next check)
				continue
			var xf: Transform3D = d[1]
			var local: Vector3 = xf * at
			if absf(local.x) > d[2] or local.y < -1.0 or local.y > d[3]:
				continue
			if absf(local.z) > minf(REACH, maxf(NEAR, v * LEAD + 0.5)):
				continue
			# walking towards the leaf (from its side of it, at it: not along it), or within IN of it
			if absf(local.z) > IN and (xf.basis * f).z * signf(local.z) > -TOWARDS:
				continue
			d[0].press()
			pressed += 1


func _index(tree: SceneTree) -> void:
	_doors.clear()
	_cells.clear()
	var doors := tree.get_nodes_in_group("doors")
	_count = doors.size()
	for door in doors:
		if not (door is Node3D) or not door.has_method("press") or not ("closed_xf" in door):
			continue
		var par := (door as Node3D).get_parent_node_3d()
		var shut: Transform3D = (par.global_transform if par != null else Transform3D()) * door.closed_xf
		var half: float = float(door.width) * 0.5 + SIDE
		var k := _doors.size()
		_doors.append([door, shut.affine_inverse(), half, float(door.height)])
		var r := half + REACH
		var c := shut.origin
		for x in range(floori((c.x - r) / CELL), floori((c.x + r) / CELL) + 1):
			for z in range(floori((c.z - r) / CELL), floori((c.z + r) / CELL) + 1):
				var key := Vector2i(x, z)
				if not _cells.has(key):
					_cells[key] = []
				(_cells[key] as Array).append(k)
