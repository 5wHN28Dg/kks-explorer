## The staff's ways as people walk them (docs/PLANT3D.md §18.1 as built): every way of staff.json found on the
## navigation mesh the content build has just baked (app/walk_route.gd, so a stair is walked along its own path and a
## ladder climbed), with the feet put on what a walker stands on (a stair's slope, a floor, a deck), and saved in
## built/staff_paths.bin for ui/people_view.gd (app/staff_ways.gd reads it), which moves each person along their way's line instead of the
## straight one between its places: through doors and round machines, rails and beams, up and down the steps. The
## app searches no path at run time.
##
## The file (FileAccess.store_var): {"format": FORMAT, "ways": {"A|B": [points, times, on]}}, a way by its places'
## ids as staff.json has it, its points from A to B (Godot's frame, the feet), `times` the fraction of the way's time
## at each point (0 to 1: a stair's steps walked at the staff's stair speed, a ladder climbed at its ladder speed, the
## rest at the walking speed), `on` per stretch between two points (ON_FLOOR, ON_STAIRS or ON_LADDER).
extends RefCounted

const WalkRoute = preload("res://app/walk_route.gd")
const StaffWays = preload("res://app/staff_ways.gd")   # the app's reader of the file

const OUT := "staff_paths.bin"
const FORMAT := StaffWays.FORMAT
const ON_FLOOR := StaffWays.ON_FLOOR
const ON_STAIRS := StaffWays.ON_STAIRS
const ON_LADDER := StaffWays.ON_LADDER
const SAMPLE := 0.1             # metres between the points a way's feet are put down at (then thinned)
const KEEP := 0.01              # metres a thinned line may leave the feet's (Douglas-Peucker)
const SNAP := 0.6               # metres above and below the mesh a walkable surface is looked for
const STEEP := 0.3              # rise over run above which a stretch is stairs (the flights are about 0.7)


## Finds and saves the ways of the staff in `staff_file` (staff.json) on the mesh `nm`, in the world of `parent`,
## whose scenes are loaded (their colliders are what the feet are put on). Returns {"ways": n, "points": n, "bytes":
## n} or {"error": …}; no staff.json: {"ways": 0} and no file.
static func build(parent: Node, nm: NavigationMesh, staff_file: String, built_dir: String) -> Dictionary:
	if not FileAccess.file_exists(staff_file):
		return {"ways": 0}
	var d = JSON.parse_string(FileAccess.get_file_as_string(staff_file))
	if typeof(d) != TYPE_DICTIONARY:
		return {"error": "staff paths: cannot read " + staff_file}
	var route := WalkRoute.new()
	route.warm_up = false
	parent.add_child(route)
	var err: String = route.setup(null, nm)
	if err != "":
		route.queue_free()
		return {"error": "staff paths: " + err}
	var t0 := Time.get_ticks_msec()
	while not route.ready_to_find():
		if Time.get_ticks_msec() - t0 > 30000:
			route.queue_free()
			return {"error": "staff paths: the navigation map was not ready after 30 s"}
		await parent.get_tree().physics_frame
	var space: PhysicsDirectSpaceState3D = parent.get_world_3d().direct_space_state
	var doors: Array[RID] = []
	for n in parent.get_tree().get_nodes_in_group("doors"):
		if n is CollisionObject3D:
			doors.append(n.get_rid())
	var at := {}
	for p in d["places"]:
		at[p["id"]] = Vector3(p["at"][0], p["at"][2], -p["at"][1])
	var speeds: Dictionary = d["speeds"]
	var ways := {}
	var points := 0
	for w in d["ways"]:
		var a: Vector3 = at[w[0]]
		var b: Vector3 = at[w[1]]
		var f: Dictionary = route.find(a, b)
		if not f.reached:
			route.queue_free()
			return {"error": "staff paths: the way %s–%s is not walkable on the mesh" % [w[0], w[1]]}
		var line := feet_line(space, a, b, f.points, f.marks, doors)
		var timed := times(line[0], line[1], speeds)
		ways["%s|%s" % [w[0], w[1]]] = [line[0], timed, line[1]]
		points += line[0].size()
	route.queue_free()
	var path := built_dir.path_join(OUT)
	var fo := FileAccess.open(path, FileAccess.WRITE)
	if fo == null:
		return {"error": "staff paths: cannot write " + path}
	fo.store_var({"format": FORMAT, "ways": ways})
	fo.close()
	return {"ways": ways.size(), "points": points, "bytes": FileAccess.get_file_as_bytes(path).size(),
		"ms": Time.get_ticks_msec() - t0}


## A way's line with the feet down: from `a` along the route's points (`marks` as app/walk_route.gd find() gives them)
## to `b`, every SAMPLE metres put on the walkable surface within SNAP of it (a ladder's rungs as they are), then
## thinned to the points that matter. [PackedVector3Array points, PackedByteArray on (one per stretch)].
static func feet_line(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3, pts: PackedVector3Array,
		marks: PackedStringArray, exclude: Array[RID] = []) -> Array:
	var src := PackedVector3Array([a])
	var ladder := PackedByteArray()     # per stretch of src: 1 on a ladder
	for i in pts.size():
		if pts[i].distance_to(src[src.size() - 1]) > 1e-3:
			src.append(pts[i])
			ladder.append(1 if i > 0 and marks[i].begins_with("ladder ") and marks[i] == marks[i - 1] else 0)
	if b.distance_to(src[src.size() - 1]) > 1e-3:
		src.append(b)
		ladder.append(0)
	# the feet every SAMPLE metres (and at every point of the route: its corners)
	var feet := PackedVector3Array()
	var on := PackedByteArray()          # per stretch of feet
	feet.append(_down(space, src[0], exclude))
	for i in range(1, src.size()):
		var p := src[i - 1]
		var q := src[i]
		if ladder[i - 1] == 1:
			# up the rungs, then off onto the platform (down: onto the rungs, then down them): never across them
			var bend := Vector3(p.x, q.y, p.z) if q.y > p.y else Vector3(q.x, p.y, q.z)
			feet.append(bend)
			on.append(ON_LADDER if q.y > p.y else ON_FLOOR)
			feet.append(q)
			on.append(ON_FLOOR if q.y > p.y else ON_LADDER)
			continue
		var n := maxi(1, ceili(p.distance_to(q) / SAMPLE))
		for k in range(1, n + 1):
			feet.append(_down(space, p.lerp(q, float(k) / n), exclude))
			on.append(ON_FLOOR)
	for i in on.size():
		if on[i] != ON_LADDER:
			var s := feet[i + 1] - feet[i]
			var run := Vector2(s.x, s.z).length()
			on[i] = ON_STAIRS if absf(s.y) > STEEP * maxf(run, 1e-3) else ON_FLOOR
	# thinned: the points that keep the line within KEEP of the feet's, and every change of what is walked on
	var keep := PackedByteArray()
	keep.resize(feet.size())
	keep.fill(0)
	keep[0] = 1
	keep[feet.size() - 1] = 1
	var lo := 0
	for i in range(1, on.size()):
		if on[i] != on[i - 1]:
			keep[i] = 1
	for i in range(1, feet.size()):
		if keep[i] == 1:
			_thin(feet, lo, i, keep)
			lo = i
	var out := PackedVector3Array()
	var out_on := PackedByteArray()
	for i in feet.size():
		if keep[i] == 1:
			if not out.is_empty():
				out_on.append(on[i - 1])
			out.append(feet[i])
	return [out, out_on]


## The walkable surface under `p` within SNAP above or below it (`p` itself where there is none).
static func _down(space: PhysicsDirectSpaceState3D, p: Vector3, exclude: Array[RID]) -> Vector3:
	var y := surface(space, p, SNAP, SNAP, exclude)
	return p if is_nan(y) else Vector3(p.x, y, p.z)


## The height of the walkable surface under `p`, looked for from `up` above it to `down` below it, or NAN: the
## highest level face three rays a few mm apart meet first. One ray straight down where two slabs or two pieces of a
## deck meet (at whole metres) met their sides, or nothing, or what is under them.
static func surface(space: PhysicsDirectSpaceState3D, p: Vector3, up: float, down: float, exclude: Array[RID]) -> float:
	var best := NAN
	for off in [Vector3.ZERO, Vector3(0.004, 0.0, 0.003), Vector3(-0.003, 0.0, 0.004)]:
		var q := PhysicsRayQueryParameters3D.create(p + off + Vector3.UP * up, p + off + Vector3.DOWN * down)
		q.exclude = exclude
		var r := space.intersect_ray(q)
		if not r.is_empty() and r.normal.y >= 0.5 and (is_nan(best) or r.position.y > best):
			best = r.position.y
	return best


## Douglas-Peucker between two kept points.
static func _thin(v: PackedVector3Array, i: int, j: int, keep: PackedByteArray) -> void:
	if j - i < 2:
		return
	var worst := -1
	var wd := KEEP
	for k in range(i + 1, j):
		var dd := _to_segment(v[k], v[i], v[j])
		if dd > wd:
			wd = dd
			worst = k
	if worst < 0:
		return
	keep[worst] = 1
	_thin(v, i, worst, keep)
	_thin(v, worst, j, keep)


static func _to_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	var t := 0.0 if l2 < 1e-12 else clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## The fraction of the way's time at each point: each stretch takes its length over its speed (`speeds`:
## staff.json's walk, stair and ladder), the whole scaled to 1 (the engine's steps are the way's whole time).
static func times(pts: PackedVector3Array, on: PackedByteArray, speeds: Dictionary) -> PackedFloat32Array:
	var by := {ON_FLOOR: float(speeds.get("walk", 1.3)), ON_STAIRS: float(speeds.get("stair", speeds.get("walk", 1.3))),
		ON_LADDER: float(speeds.get("ladder", speeds.get("walk", 1.3)))}
	var t := PackedFloat32Array([0.0])
	var sum := 0.0
	for i in on.size():
		sum += pts[i].distance_to(pts[i + 1]) / by[on[i]]
		t.append(sum)
	for i in t.size():
		t[i] = t[i] / sum if sum > 0.0 else float(i) / maxf(1.0, t.size() - 1)
	t[t.size() - 1] = 1.0
	return t
