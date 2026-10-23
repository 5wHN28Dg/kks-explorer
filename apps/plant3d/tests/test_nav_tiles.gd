## The walking directions' mesh baked in tiles (builder/nav_bake.gd bake_tiled): Recast's heightfield overflowed on
## the whole site at once (the bake came out empty or crashed), so the build bakes tiles and joins them. On a small
## synthetic floor cut into 4 m tiles, with boxes standing across the seams: the joined mesh is one piece a walker
## crosses from tile to tile (the seams' vertices welded and their edges split where the other side's are): from one
## corner a walker reaches as much floor as in one bake of the whole floor, in at least 5 of the 6 tiles. And two
## hand-made tiles whose seam vertices differ (Recast places each side's on its own: none did on the site in 2026-10,
## but nothing promises it) are joined: the long edge is split where the other side's vertex is.
extends RefCounted

const NavBake = preload("res://builder/nav_bake.gd")

var problems: Array = []

func check(ok: bool, what: String) -> void:
	if not ok:
		problems.append(what)

func run(tree: SceneTree) -> Array:
	_t_junction()
	_long_seam()
	var root := Node3D.new()
	tree.root.add_child(root)
	_box(root, Vector3(5.0, -0.25, 3.0), Vector3(10.0, 0.5, 6.0))   # the floor, 10 x 6 m, its top at 0
	_box(root, Vector3(3.9, 0.5, 2.2), Vector3(0.7, 1.0, 1.3))     # boxes across the seams at x = 4 and z = 4
	_box(root, Vector3(8.1, 0.5, 4.1), Vector3(0.9, 1.0, 0.5))
	_box(root, Vector3(6.3, 0.5, 4.6), Vector3(1.1, 1.0, 0.9))
	for z in [0.9, 1.9, 2.9, 3.6, 5.2]:                              # pillars near one side of the seam at x = 4 only
		_box(root, Vector3(3.0, 1.0, z), Vector3(0.3, 2.0, 0.3))
	for x in [1.1, 2.3, 6.9]:                                         # and of the seam at z = 4
		_box(root, Vector3(x, 1.0, 3.2), Vector3(0.3, 2.0, 0.3))
	var nm := NavBake.params()
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, root)
	root.queue_free()
	var whole := NavBake.params()
	NavigationServer3D.bake_from_source_geometry_data(whole, src)
	var tiled: Dictionary = NavBake.bake_tiled(nm, src, 4.0)
	check(not tiled.has("error"), "bake_tiled: %s" % str(tiled.get("error", "")))
	check(tiled.get("tiles", 0) == 6 and tiled.get("grid", 0) == 6, "baked in %s tiles of %s, not 6 of 6" % [str(tiled.get("tiles")), str(tiled.get("grid"))])
	# the level faces by tile (what an empty tile is checked against): the floor's top and bottom, 4 x 4 m each
	var floors: Dictionary = NavBake.floor_area_by_tile(src, Vector2.ZERO, 4.0)
	check(absf(floors.get(Vector2i(0, 0), 0.0) - 32.0) < 1.0, "the level faces in tile (0, 0): %.2f m², not about 32" % floors.get(Vector2i(0, 0), 0.0))
	check(nm.get_polygon_count() > 0, "the tiled mesh is empty")
	if problems:
		return problems
	# the floor reached from one corner: as much as in one bake of the whole (the boxes' tops are reached in neither)
	var kept: Dictionary = NavBake.reachable(nm, Vector3(1.0, 0.0, 1.0), [])
	var kept_whole: Dictionary = NavBake.reachable(whole, Vector3(1.0, 0.0, 1.0), [])
	check(not kept.has("error") and not kept_whole.has("error"), "reachable: %s %s" % [str(kept.get("error", "")), str(kept_whole.get("error", ""))])
	if problems:
		return problems
	var a := _area(nm, kept.polygons)
	var w := _area(whole, kept_whole.polygons)
	check(w > 30.0, "one bake reaches only %.2f m² of the floor" % w)
	check(absf(a - w) < 0.03 * w, "the tiles are not joined: %.2f m² reached across them, %.2f m² in one bake" % [a, w])
	var tiles := {}
	var verts := nm.get_vertices()
	for i in nm.get_polygon_count():
		var c := Vector3.ZERO
		for idx in nm.get_polygon(i):
			c += verts[idx]
		c /= nm.get_polygon(i).size()
		var sq := Vector2i(floori(c.x / 4.0), floori(c.z / 4.0))
		tiles[sq] = true
		for idx in nm.get_polygon(i):   # a tile's polygons end on its edges: none reaches into the next tile
			if verts[idx].x < sq.x * 4.0 - 0.01 or verts[idx].x > sq.x * 4.0 + 4.01 or verts[idx].z < sq.y * 4.0 - 0.01 or verts[idx].z > sq.y * 4.0 + 4.01:
				check(false, "polygon %d reaches out of its tile %s at %s" % [i, str(sq), str(verts[idx])])
	check(tiles.size() >= 5, "the mesh lies in %d tiles (the floor spans 6)" % tiles.size())
	return problems

func _box(parent: Node3D, at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = size
	body.position = at
	body.add_child(shape)
	parent.add_child(body)

func _area(nm: NavigationMesh, only: Dictionary) -> float:
	var verts := nm.get_vertices()
	var s := 0.0
	for i in only:
		var p := nm.get_polygon(i)
		for k in range(1, p.size() - 1):
			s += (verts[p[k]] - verts[p[0]]).cross(verts[p[k + 1]] - verts[p[0]]).length() * 0.5
	return s

## Tile A, x 0..4: one triangle with its edge on the seam x = 4 from z 0 to 4. Tile B, x 4..8: two triangles meeting
## the seam at z 0, 1.5 and 4 (the vertex at 1.5 is a few millimetres off, as a bake's float sums leave them).
func _t_junction() -> void:
	var a := NavigationMesh.new()
	a.vertices = PackedVector3Array([Vector3(1, 0, 2), Vector3(4, 0, 0), Vector3(4, 0, 4)])
	a.add_polygon(PackedInt32Array([0, 1, 2]))
	var b := NavigationMesh.new()
	b.vertices = PackedVector3Array([Vector3(4.002, 0, 0), Vector3(3.999, 0.01, 1.5), Vector3(4, 0, 4), Vector3(7, 0, 2)])
	b.add_polygon(PackedInt32Array([0, 3, 1]))
	b.add_polygon(PackedInt32Array([1, 3, 2]))
	var nm := NavigationMesh.new()
	var splits := NavBake.join_tiles(nm, [a, b], Vector2.ZERO, 4.0, Vector2i(2, 1))
	check(splits == 1, "hand-made tiles: %d polygons split on the seam, not 1" % splits)
	check(nm.get_vertices().size() == 6, "hand-made tiles: %d vertices, not 6 (5 after the weld, 1 in the split polygon's middle)" % nm.get_vertices().size())
	var kept: Dictionary = NavBake.reachable(nm, Vector3(1.5, 0, 2), [])
	check(kept.get("polygons", {}).size() == nm.get_polygon_count(), "hand-made tiles not joined across the seam: %s" % str(kept))

## A 100 m seam edge on one side, the other side's vertex 3 cm from its end and 0.15 m above its line (a sloping
## edge's detail vertex): split there too.
func _long_seam() -> void:
	var a := NavigationMesh.new()
	a.vertices = PackedVector3Array([Vector3(1, 0, 50), Vector3(4, 0, 0), Vector3(4, 0, 100)])
	a.add_polygon(PackedInt32Array([0, 1, 2]))
	var b := NavigationMesh.new()
	b.vertices = PackedVector3Array([Vector3(4, 0, 0), Vector3(4, 0.15, 0.03), Vector3(4, 0, 100), Vector3(7, 0, 50)])
	b.add_polygon(PackedInt32Array([0, 3, 1]))
	b.add_polygon(PackedInt32Array([1, 3, 2]))
	var nm := NavigationMesh.new()
	var splits := NavBake.join_tiles(nm, [a, b], Vector2.ZERO, 4.0, Vector2i(2, 1))
	check(splits == 1, "long seam: %d polygons split, not 1" % splits)
	var kept: Dictionary = NavBake.reachable(nm, Vector3(2, 0, 50), [])
	check(kept.get("polygons", {}).size() == nm.get_polygon_count(), "long seam not joined: %s" % str(kept))
