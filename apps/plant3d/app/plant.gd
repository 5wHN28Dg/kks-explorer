## Loads the pre-built plant (made by builder/, decision 0054 §4): the manifest, the ground and every area's scene.
## Loading only: no geometry is made at start.
extends Node3D

const BUILT := "res://built/plant.json"

var manifest: Dictionary = {}
var load_ms := 0
var stages := PackedStringArray()   # each scene's load and instancing, in ms (main.gd's LAUNCH lines)

## Loads everything; returns "" or what went wrong.
func load_plant() -> String:
	var t0 := Time.get_ticks_msec()
	var f := FileAccess.open(BUILT, FileAccess.READ)
	if f == null:
		return "no built plant (%s): run apps/plant3d/build.sh" % BUILT
	var m = JSON.parse_string(f.get_as_text())
	if not m is Dictionary or m.get("format", "") != "walkdown-plant-built":
		return "the built plant's manifest is not one this app reads"
	manifest = m
	var scenes: Array = [m.ground]
	for a in m.areas:
		scenes.append(a.scene)
	for path in scenes:
		var t := Time.get_ticks_usec()
		var ps := load(path) as PackedScene
		if ps == null:
			return "cannot load " + path
		var t1 := Time.get_ticks_usec()
		var area := ps.instantiate()
		var t2 := Time.get_ticks_usec()
		add_child(area)
		fill_cells(area)
		stages.append("%s: load %d ms, instance %d ms, add %d ms" % [path.get_file().get_basename(), (t1 - t) / 1000,
			(t2 - t1) / 1000, (Time.get_ticks_usec() - t2) / 1000])
	load_ms = Time.get_ticks_msec() - t0
	return ""

## The parts kit's instanced cells (builder/kit_place.gd): the build saves their transforms as meta (Godot's headless
## renderer, which the build runs in, keeps no MultiMesh data); here they go to the MultiMeshes.
static func fill_cells(area: Node) -> int:
	var kit := area.get_node_or_null("kit")
	if kit == null:
		return 0
	var n := 0
	for c in kit.get_children():
		var mmi := c as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null or not mmi.has_meta("xforms"):
			continue
		var mm := mmi.multimesh
		mm.instance_count = int(mmi.get_meta("count"))
		mm.buffer = mmi.get_meta("xforms")
		n += mm.instance_count
	return n

static func v3(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

## The start (plant.json `start`): position and heading (radians about the up axis).
func start() -> Array:
	return [v3(manifest.start.at), -deg_to_rad(float(manifest.start.yaw))]

## Plant coordinates (x east, y north, z up) to Godot's.
static func g(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, z, -y)

func stair_path(id: String) -> Array:
	for s in manifest.stairs:
		if s.id == id:
			return s.path.map(func(p): return v3(p))
	return []

## The center of the plant's extent, in Godot's axes, and its size.
func extent() -> Rect2:
	var e: Array = manifest.extent
	return Rect2(Vector2(e[0][0], e[0][1]), Vector2(e[1][0] - e[0][0], e[1][1] - e[0][1]))
