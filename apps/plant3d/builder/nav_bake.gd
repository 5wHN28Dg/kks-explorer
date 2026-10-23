## The walking directions' navigation mesh (docs/PLANT3D.md §8 `"go": "walk"`, decision 0059), baked by the content
## build from the pre-built scenes' collision shapes, so the app loads it instead of baking it (the app's start has
## no time to spare: 0054 §4). What a walker can stand on and pass is what the walker's own capsule collides with
## (app/player.gd), with three changes:
##   - the doors are left out: they open in front of a walker (app/door.gd);
##   - the stairs are left out, and their flights are obstructions down to the floor below: Recast (Godot's baker)
##     joined flights stacked above each other in a stair tower into polygons spanning several floors. The app joins
##     each stair's foot and top with a navigation link instead, and walks it along the stair's own path (the one the
##     walking test climbs), as it climbs a ladder between its foot and its top;
##   - only what a walker can reach from the plant's start, on foot, by the stairs and by the ladders, is kept: the
##     tops of machines, roofs and fan stacks are flat but nobody walks there, and a route must never end on one.
extends RefCounted

const OUT := "nav.res"

## The walker (app/player.gd): a 0.3 m capsule, 1.8 m tall (the stack platform at +40 leaves it 0.4 m between the
## stack and the rail: no room to spare). Floors and platforms are level and stairs are links: a ledge is
## climbed only as high as the capsule rides up one, r (1 - cos 46°) = 0.09 m (a machine's base is not).
const AGENT_RADIUS := 0.3
const AGENT_HEIGHT := 1.8
const AGENT_CLIMB := 0.09
const AGENT_SLOPE := 20.0
const CELL := 0.1               # a 1 m personnel door less the radius on both sides leaves 0.3 m: three cells
const CELL_H := 0.03            # the climb, 0.09 m, is three of them (Recast floors it to whole cells)
const LINK_REACH := 1.0         # how far from a stair's or a ladder's end its link finds the mesh (the app's map too)
const APPROACH := 0.8           # metres in front of a stair's end where its link starts

const TILE := 102.4              # metres (1024 cells): the site is baked in tiles of this size (bake_tiled)
const BORDER := 1.0             # metres baked round each tile and cut off again, so a tile's edge is not eroded

static func params() -> NavigationMesh:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nm.sample_partition_type = NavigationMesh.SAMPLE_PARTITION_WATERSHED
	nm.cell_size = CELL
	nm.cell_height = CELL_H
	nm.agent_radius = AGENT_RADIUS
	nm.agent_height = AGENT_HEIGHT
	nm.agent_max_climb = AGENT_CLIMB
	nm.agent_max_slope = AGENT_SLOPE
	nm.region_min_size = 4.0
	nm.edge_max_error = 1.0
	nm.detail_sample_distance = 2.0
	nm.detail_sample_max_error = 0.2
	return nm

## Bakes the built scenes (the ground and the areas, as app/plant.gd loads them) under `parent` (a node in the tree)
## and saves the mesh in `built_dir`. `stairs` and `ladders` are the builder's (builder/plant_builder.gd), `start`
## the plant's start (Godot's axes). Returns {"error": …} or what was made.
static func bake(parent: Node, built_dir: String, scenes: Array, stairs: Array, ladders: Array, start: Vector3) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var root := Node3D.new()
	root.name = "nav_source"
	parent.add_child(root)
	for path in scenes:
		var ps := load(path) as PackedScene
		if ps == null:
			root.free()
			return {"error": "nav: cannot load " + path}
		root.add_child(ps.instantiate())
	# the stairs' ways, found while the stairs still stand (their rails are what a way must not cross)
	await parent.get_tree().physics_frame
	await parent.get_tree().physics_frame
	var space := root.get_world_3d().direct_space_state
	var ways: Array = []
	for s in stairs:
		var w := stair_way(space, s.lay.path.map(func(p): return _g(p)))
		if w.is_empty():
			root.free()
			return {"error": "nav: no floor to walk onto from one end of the stair %s" % s.id}
		ways.append({"kind": "stair", "id": s.id, "path": PackedVector3Array(w)})
	for l in ladders:
		ways.append({"kind": "ladder", "id": l.id, "path": PackedVector3Array([_g(l.foot), _g(l.exit)])})
	var left_out := {"doors": 0, "stairs": 0}
	for n in _left_out(root):
		left_out["stairs" if n.has_meta("stair") else "doors"] += 1
		n.get_parent().remove_child(n)
		n.free()
	var nm := params()
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, root)
	root.free()
	# each flight, from just below its top down to the floor under its foot: no way under a stair, none onto it
	for s in stairs:
		for fl in s.lay.flights:
			var dir: Vector2 = (fl.b - fl.a).normalized()
			var going: float = fl.a.distance_to(fl.b) / maxf(fl.steps - 1, 1)
			var pc: PackedVector2Array = _strip(fl.a - dir * going, fl.b, fl.side, fl.width)
			var v := PackedVector3Array()
			for p in pc:
				v.append(Vector3(p.x, 0, -p.y))
			var lo: float = fl.z0 - 0.5
			src.add_projected_obstruction(v, lo, fl.z1 - 0.15 - lo, false)
	var tiled := bake_tiled(nm, src, TILE)
	if nm.get_polygon_count() == 0:
		return {"error": "nav: the navigation mesh is empty"}
	# the links: each stair's foot and top, each ladder's foot and step-off point
	var links: Array = []
	for w in ways:
		links.append([w.path[0], w.path[-1], "%s %s" % [w.kind, w.id]])
	nm.set_meta("ways", ways)
	var kept := reachable(nm, start, links)
	if kept.has("error"):
		return kept
	var all := nm.get_polygon_count()
	_keep(nm, kept.polygons)
	var path := built_dir.path_join(OUT)
	var e := ResourceSaver.save(nm, path, ResourceSaver.FLAG_COMPRESS)
	if e != OK:
		return {"error": "nav: save %s: error %d" % [path, e]}
	return {"polygons": nm.get_polygon_count(), "dropped": all - nm.get_polygon_count(), "vertices": nm.get_vertices().size(),
		"doors": left_out.doors, "stairs": left_out.stairs, "tiles": tiled.tiles, "splits": tiled.splits, "ms": Time.get_ticks_msec() - t0,
		"bytes": FileAccess.get_file_as_bytes(path).size()}

## A stair's way (its path, Godot's axes) with the floor in front of each end, APPROACH metres on, where its link
## joins the mesh: straight on from the flight if the walker's capsule fits along there and finds the end's floor,
## else the nearest direction that does (a stair arriving at a landing's corner turns onto it). [] when none does.
static func stair_way(space: PhysicsDirectSpaceState3D, path: Array) -> Array:
	var out := path.duplicate()
	var cap := CapsuleShape3D.new()
	cap.radius = AGENT_RADIUS
	cap.height = AGENT_HEIGHT - 0.2
	for end in [0, path.size() - 1]:
		var p: Vector3 = path[end]
		var k := 1 if end == 0 else path.size() - 2
		var d := Vector3.ZERO
		while k >= 0 and k < path.size():
			d = Vector3(p.x - path[k].x, 0, p.z - path[k].z)
			if d.length() > 0.05:
				break
			k += 1 if end == 0 else -1
		d = d.normalized() if d.length() > 0.05 else Vector3.FORWARD
		var found := Vector3.INF
		for a in [0, 45, -45, 90, -90, 135, -135, 180]:
			var dir := d.rotated(Vector3.UP, deg_to_rad(a))
			var q := p + dir * APPROACH
			var floor := space.intersect_ray(PhysicsRayQueryParameters3D.create(q + Vector3.UP * 0.5, q + Vector3.DOWN * 0.5))
			if floor.is_empty() or absf(floor.position.y - p.y) > 0.1 or floor.normal.y < 0.9:
				continue
			# the capsule, 0.35 m above the floor (clear of a flight's slope, which starts above the floor at its foot),
			# along from the end to there
			var sq := PhysicsShapeQueryParameters3D.new()
			sq.shape = cap
			sq.transform = Transform3D(Basis(), p + Vector3.UP * (0.35 + 0.8))
			sq.motion = q - p
			var m := space.cast_motion(sq)
			if m.size() == 2 and m[0] >= 1.0:
				found = Vector3(q.x, floor.position.y, q.z)
				break
		if found == Vector3.INF:
			return []
		if end == 0:
			out.push_front(found)
		else:
			out.push_back(found)
	return out

static func _g(p: Vector3) -> Vector3:
	return Vector3(p.x, p.z, -p.y)

static func _strip(a: Vector2, b: Vector2, across: Vector2, w: float) -> PackedVector2Array:
	var s := across * (w * 0.5)
	return PackedVector2Array([a - s, b - s, b + s, a + s])

## The doors and the stairs (the builder marks a stair's body with `stair`).
static func _left_out(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c.is_in_group("doors") or c.has_meta("stair"):
			out.append(c)
		else:
			out.append_array(_left_out(c))
	return out

## The polygons a walker reaches from `start`: those joined by shared edges, and across each link whose one end is
## reached. {"polygons": {index: true}} or {"error": …} (the start or a link's end not on the mesh).
static func reachable(nm: NavigationMesh, start: Vector3, links: Array) -> Dictionary:
	var verts := nm.get_vertices()
	var n := nm.get_polygon_count()
	var by_edge := {}
	for i in n:
		var p := nm.get_polygon(i)
		for k in p.size():
			var key := Vector2i(mini(p[k], p[(k + 1) % p.size()]), maxi(p[k], p[(k + 1) % p.size()]))
			if not by_edge.has(key):
				by_edge[key] = []
			by_edge[key].append(i)
	var comp := PackedInt32Array()
	comp.resize(n)
	comp.fill(-1)
	var count := 0
	for s in n:
		if comp[s] != -1:
			continue
		comp[s] = count
		var stack := [s]
		while not stack.is_empty():
			var i: int = stack.pop_back()
			var p := nm.get_polygon(i)
			for k in p.size():
				var key := Vector2i(mini(p[k], p[(k + 1) % p.size()]), maxi(p[k], p[(k + 1) % p.size()]))
				for j in by_edge[key]:
					if comp[j] == -1:
						comp[j] = count
						stack.append(j)
		count += 1
	var c0 := _nearest(nm, verts, start)
	if c0 < 0:
		return {"error": "nav: the plant's start %s is not on the navigation mesh" % str(start)}
	var keep := {comp[c0]: true}
	var ends: Array = []
	for l in links:
		var a := _nearest(nm, verts, l[0])
		var b := _nearest(nm, verts, l[1])
		if a < 0 or b < 0:
			return {"error": "nav: the %s's %s is not within %.1f m of the navigation mesh" % [l[2], "foot" if a < 0 else "top", LINK_REACH]}
		ends.append([comp[a], comp[b]])
	var grew := true
	while grew:
		grew = false
		for e in ends:
			if keep.has(e[0]) != keep.has(e[1]):
				keep[e[0]] = true
				keep[e[1]] = true
				grew = true
	var out := {}
	for i in n:
		if keep.has(comp[i]):
			out[i] = true
	# Godot's region joins an edge of two polygons only: one shared by more (the stair-tower fault, 0059) is no
	# connection at run time, so a walkable one stops the build (unreachable islands may keep theirs: they go)
	for key in by_edge:
		if by_edge[key].size() > 2 and by_edge[key].any(func(i): return out.has(i)):
			return {"error": "nav: an edge at %s is shared by %d polygons (overlapping floors?)" % [str(verts[key.x]), by_edge[key].size()]}
	return {"polygons": out}

## The polygon nearest to `p` in plan within LINK_REACH, at most 0.6 m above or below it, or -1.
static func _nearest(nm: NavigationMesh, verts: PackedVector3Array, p: Vector3) -> int:
	var best := -1
	var bd := LINK_REACH
	var p2 := Vector2(p.x, p.z)
	for i in nm.get_polygon_count():
		var poly := nm.get_polygon(i)
		var pg := PackedVector2Array()
		var y := 0.0
		for idx in poly:
			pg.append(Vector2(verts[idx].x, verts[idx].z))
			y += verts[idx].y
		y /= poly.size()
		if absf(y - p.y) > 0.6:
			continue
		var d := 0.0
		if not Geometry2D.is_point_in_polygon(p2, pg):
			d = INF
			for k in pg.size():
				d = minf(d, p2.distance_to(Geometry2D.get_closest_point_to_segment(p2, pg[k], pg[(k + 1) % pg.size()])))
		if d < bd:
			bd = d
			best = i
	return best

## Keeps only these polygons (and the vertices they use).
static func _keep(nm: NavigationMesh, keep: Dictionary) -> void:
	var verts := nm.get_vertices()
	var polys: Array = []
	for i in nm.get_polygon_count():
		if keep.has(i):
			polys.append(nm.get_polygon(i))
	var remap := {}
	var nv := PackedVector3Array()
	var out: Array = []
	for p in polys:
		var q := PackedInt32Array()
		for idx in p:
			if not remap.has(idx):
				remap[idx] = nv.size()
				nv.append(verts[idx])
			q.append(remap[idx])
		out.append(q)
	nm.clear_polygons()
	nm.vertices = nv
	for q in out:
		nm.add_polygon(q)

## Bakes `src` into `nm` tile by tile, `tile` metres square on the cell grid, and joins the tiles into one mesh.
## Recast (Godot's baker) indexes a heightfield's spans with 24 bits: the site and the camp at 0.1 m cells (some
## 975 x 220 m, 21 million columns) overflowed it, and the bake came out empty or crashed. Each tile is baked with
## a border (BORDER) so its polygons end exactly on the tile's edge; the vertices the tiles share there are welded,
## and an edge on a seam that a vertex of the other side splits is split there too (Recast places the seam's
## vertices on each side independently): Godot's region joins two polygons only by an edge both have exactly.
## Returns {"tiles": tiles with polygons, "splits": polygons split on a seam} (none on the site in 2026-10).
static func bake_tiled(nm: NavigationMesh, src: NavigationMeshSourceGeometryData3D, tile: float) -> Dictionary:
	var b := src.get_bounds()
	var x0 := floorf(b.position.x / tile) * tile
	var z0 := floorf(b.position.z / tile) * tile
	var nx := maxi(1, ceili((b.end.x - x0) / tile))
	var nz := maxi(1, ceili((b.end.z - z0) / tile))
	var tiles: Array = []
	for ix in nx:
		for iz in nz:
			var t := params()
			# Godot cuts the border inside the box it bakes: the box is the tile and the border round it. Half a
			# cell less, as Godot rounds the border up to whole cells (BORDER / CELL in floats is not exactly 10)
			t.filter_baking_aabb = AABB(Vector3(x0 + ix * tile - BORDER, b.position.y - 1.0, z0 + iz * tile - BORDER),
				Vector3(tile + 2.0 * BORDER, b.size.y + 2.0, tile + 2.0 * BORDER))
			t.border_size = BORDER - CELL * 0.5
			NavigationServer3D.bake_from_source_geometry_data(t, src)
			if t.get_polygon_count() > 0:
				tiles.append(t)
	return {"tiles": tiles.size(), "splits": join_tiles(nm, tiles, Vector2(x0, z0), tile, Vector2i(nx, nz))}

## Joins baked tiles (`n` of them across and down from `origin`, `tile` metres square) into `nm`: the vertices
## within 1 cm of each other welded, an edge on a seam split at the other side's vertices on it. Returns how many
## polygons were split.
static func join_tiles(nm: NavigationMesh, tiles: Array, origin: Vector2, tile: float, n: Vector2i) -> int:
	var x0 := origin.x
	var z0 := origin.y
	var nx := n.x
	var nz := n.y
	var verts := PackedVector3Array()
	var polys: Array = []
	var weld := {}   # Vector2i(x, z in cm) -> [vertex indices] (one per floor height)
	for t in tiles:
		var map := PackedInt32Array()
		for v in t.get_vertices():
			map.append(_weld(verts, weld, v))
		for i in t.get_polygon_count():
			var q := PackedInt32Array()
			for idx in t.get_polygon(i):
				q.append(map[idx])
			polys.append(q)
	# the seams: the lines between tiles, and the vertices on each
	var lines := {}   # Vector2i(axis 0 = x / 1 = z, line number) -> [vertex indices]
	for i in verts.size():
		for axis in 2:
			var c: float = verts[i].x - x0 if axis == 0 else verts[i].z - z0
			var k := roundi(c / tile)
			if k > 0 and k < (nx if axis == 0 else nz) and absf(c - k * tile) < 0.005:
				var key := Vector2i(axis, k)
				if not lines.has(key):
					lines[key] = []
				lines[key].append(i)
	nm.clear_polygons()
	var out: Array = []
	var splits := 0
	for p in polys:
		var loop := PackedInt32Array()
		var split := false
		for k in p.size():
			var u: int = p[k]
			var w: int = p[(k + 1) % p.size()]
			loop.append(u)
			for between in _on_seam(verts, lines, x0, z0, tile, u, w):
				loop.append(between)
				split = true
		if not split:
			out.append(p)
			continue
		splits += 1
		# fan round the polygon's middle (a polygon with a straight angle on its edge would have a vertex in line)
		var mid := Vector3.ZERO
		for idx in p:
			mid += verts[idx]
		verts.append(mid / p.size())
		var m := verts.size() - 1
		for k in loop.size():
			out.append(PackedInt32Array([m, loop[k], loop[(k + 1) % loop.size()]]))
	nm.vertices = verts
	for q in out:
		nm.add_polygon(q)
	return splits

## The vertex for `v`: one already there within 1 cm in plan and 0.1 m in height, else `v` added.
static func _weld(verts: PackedVector3Array, weld: Dictionary, v: Vector3) -> int:
	var key := Vector2i(roundi(v.x * 100.0), roundi(v.z * 100.0))
	for dx in [0, -1, 1]:
		for dz in [0, -1, 1]:
			for i in weld.get(key + Vector2i(dx, dz), []):
				if absf(verts[i].y - v.y) < 0.1 and Vector2(verts[i].x, verts[i].z).distance_to(Vector2(v.x, v.z)) < 0.01:
					return i
	verts.append(v)
	if not weld.has(key):
		weld[key] = []
	weld[key].append(verts.size() - 1)
	return verts.size() - 1

## The vertices strictly between `u` and `w`, in order from `u`, when both lie on the same seam (and in height on
## the line between them, within 0.1 m); [] otherwise.
static func _on_seam(verts: PackedVector3Array, lines: Dictionary, x0: float, z0: float, tile: float, u: int, w: int) -> Array:
	var a := verts[u]
	var c := verts[w]
	for axis in 2:
		var ca: float = a.x - x0 if axis == 0 else a.z - z0
		var cc: float = c.x - x0 if axis == 0 else c.z - z0
		var k := roundi(ca / tile)
		if not lines.has(Vector2i(axis, k)) or absf(ca - k * tile) >= 0.005 or absf(cc - k * tile) >= 0.005:
			continue
		var along: float = c.z - a.z if axis == 0 else c.x - a.x
		if absf(along) < 0.005:
			return []
		var found: Array = []
		for i in lines[Vector2i(axis, k)]:
			if i == u or i == w:
				continue
			var v := verts[i]
			var f: float = ((v.z - a.z) if axis == 0 else (v.x - a.x)) / along
			if f <= 0.0005 or f >= 0.9995:
				continue
			if absf(v.y - lerpf(a.y, c.y, f)) < 0.1:
				found.append([f, i])
		found.sort_custom(func(p, q): return p[0] < q[0])
		return found.map(func(p): return p[1])
	return []
