## The staff's lines (builder/staff_paths.gd, app/staff_ways.gd) on a fixed scene of their own: a floor and a beam at
## chest height across the straight line between two places. The content build's steps (the mesh baked as the plant's
## is, the way found on it, the feet put down, the file written) make a line that goes round the beam's end; walked
## by app/staff_ways.gd from either place, a 0.3 m capsule on it touches nothing, the feet stay on the floor, and the
## speed is the line's length over the way's time. A file whose line does not end at the places is not used (another
## staff file than the build's), and neither is one of another format.
extends RefCounted

const NavBake = preload("res://builder/nav_bake.gd")
const StaffPaths = preload("res://builder/staff_paths.gd")
const StaffWays = preload("res://app/staff_ways.gd")

const DIR := "user://test_staff_paths"


## The staff model's parts app/staff_ways.gd reads.
class FakeStaff:
	var places: Array = []
	var pix := {}


func run(tree: SceneTree) -> Array:
	var p: Array = []
	var vp := SubViewport.new()
	vp.own_world_3d = true          # a navigation map and a physics space of its own
	vp.world_3d = World3D.new()
	tree.root.add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	_box(world, Vector3(0, -0.1, 0), Vector3(20, 0.2, 20))           # the floor, its top at 0
	_box(world, Vector3(0, 1.1, 0), Vector3(0.3, 0.3, 6.0))          # the beam: across x = 0 from z -3 to 3
	for i in 3:
		await tree.physics_frame
	var nm := NavBake.params()
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, world)
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	if nm.get_polygon_count() == 0:
		vp.free()
		return ["the fixture's mesh is empty"]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var staff_file := DIR.path_join("staff.json")
	var f := FileAccess.open(staff_file, FileAccess.WRITE)
	# plant coordinates (x east, y north, z up): Godot's (-4, 0, 0) and (4, 0, 0)
	f.store_string(JSON.stringify({"speeds": {"walk": 1.3, "stair": 0.5, "ladder": 0.3},
		"places": [{"id": "a", "at": [-4, 0, 0], "kind": "point"}, {"id": "b", "at": [4, 0, 0], "kind": "point"}],
		"ways": [["a", "b", 9.0, "walk"]]}))
	f.close()
	var r: Dictionary = await StaffPaths.build(world, nm, staff_file, DIR)
	if r.has("error") or r.get("ways", 0) != 1:
		vp.free()
		return ["the fixture's line was not built: %s" % str(r)]
	var file := DIR.path_join(StaffPaths.OUT)
	var sm := FakeStaff.new()
	sm.places = [{"id": "a"}, {"id": "b"}]
	sm.pix = {"a": 0, "b": 1}
	var at := [Vector3(-4, 0, 0), Vector3(4, 0, 0)]
	var ways = StaffWays.open(sm, at, file)
	if ways == null or not ways.lines.has(1):
		vp.free()
		return ["the fixture's line is not read back (%s)" % file]
	var pts: PackedVector3Array = ways.lines[1][0]
	var length := 0.0
	var round_by := 0.0
	for i in range(1, pts.size()):
		length += pts[i - 1].distance_to(pts[i])
	for q in pts:
		round_by = maxf(round_by, absf(q.z))
	# round the beam's end (z = ±3), the walker's radius and the mesh's margin beyond it
	if round_by < 3.3:
		p.append("the line does not go round the beam (at most %.2f m off the straight line): %s" % [round_by, str(pts)])
	if length < 8.0 + 1.0:
		p.append("the line is %.2f m: no longer than the straight line, it goes through the beam" % length)
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state   # (the viewport's own copy of its world: vp.world_3d's space is empty)
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.4
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	var seconds := 9.0 / 1.3
	for from in [0, 1]:
		var last := Vector3.INF
		for i in 101:
			var k := i / 100.0
			if not ways.walk(1, from, k, seconds):
				p.append("walk() has no line")
				break
			var pos: Vector3 = ways.pos
			if i == 0 and pos.distance_to(at[from]) > 0.05:
				p.append("walked from %s, the line starts at %s" % ["ab"[from], str(pos)])
			if i == 100 and pos.distance_to(at[1 - from]) > 0.05:
				p.append("walked from %s, the line ends at %s" % ["ab"[from], str(pos)])
			if last != Vector3.INF and ways.dir.dot(pos - last) < -1e-4:
				p.append("walked from %s, it faces back along its line at %s" % ["ab"[from], str(pos)])
				break
			last = pos
			q.transform = Transform3D(Basis(), pos + Vector3.UP * 1.1)
			if not space.intersect_shape(q, 1).is_empty():
				p.append("walked from %s, the capsule at %s touches the beam" % ["ab"[from], str(pos)])
				break
			if absf(pos.y) > 0.02:
				p.append("walked from %s, the feet at %s are off the floor" % ["ab"[from], str(pos)])
				break
			if i < 100 and absf(ways.speed - length / seconds) > 0.01:
				p.append("walked at %.3f m/s, not the line's %.3f" % [ways.speed, length / seconds])
				break
	# a line that does not end at its places is not used (another staff file than the build's)
	var moved := [Vector3(-4, 0, 0), Vector3(4, 0, 1)]
	var other = StaffWays.open(sm, moved, file)
	if other == null or other.lines.has(1):
		p.append("a line that does not end at its places is used")
	var bad := DIR.path_join("other.bin")
	var fo := FileAccess.open(bad, FileAccess.WRITE)
	fo.store_var({"format": "something else", "ways": {}})
	fo.close()
	if StaffWays.open(sm, at, bad) != null:
		p.append("a file of another format is read")
	if StaffWays.open(sm, at, DIR.path_join("none.bin")) != null:
		p.append("a missing file gives lines")
	vp.free()
	for fn in [staff_file, file, bad]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(fn))
	return p


func _box(parent: Node3D, at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	body.add_child(cs)
	body.position = at
	parent.add_child(body)
