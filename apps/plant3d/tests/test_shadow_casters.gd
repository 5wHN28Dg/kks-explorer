## The sun's shadow casters (decision 0057, "The shadow casters"; builder/plant_builder.gd): what the shadow pass draws
## for nothing is left out without changing what is seen.
## - Long meshes across the site (the ring road's kerbs, the boundary wall's panels) are a mesh per SHADOW_CELL square,
##   so that each cascade draws only the squares near the walker: `split_by_cell` keeps every triangle, with its
##   vertices' every attribute, exactly once, each square's triangles in that square; in the built plant no kerb or
##   panel mesh spans more than a square (and a triangle's reach).
## - A piece under a roof casts no shadow only when every ray from it to the sun leaves its building through solid wall
##   or roof (`roof_shades`): never through a door, a pipe's opening or a roof opening; in the built plant some do,
##   each stands inside a building of its area, and every building's own walls and roof still cast.
extends RefCounted

const Plant = preload("res://app/plant.gd")
const Builder = preload("res://builder/plant_builder.gd")
const Lighting = preload("res://app/lighting.gd")

func run(tree: SceneTree) -> Array:
	var p: Array = []
	p.append_array(_split())
	p.append_array(_shades())
	p.append_array(_built(tree))
	return p

## A triangle as text: its three vertices' position, normal, colour, UV and tangent (an order-free key).
static func _tri_key(arr: Array, idx: PackedInt32Array, t: int) -> String:
	var vs: Array = []
	for k in 3:
		var i := idx[t + k]
		var tg: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT]
		vs.append("%s %s %s %s %s" % [arr[Mesh.ARRAY_VERTEX][i], arr[Mesh.ARRAY_NORMAL][i], arr[Mesh.ARRAY_COLOR][i],
			arr[Mesh.ARRAY_TEX_UV][i], [tg[i * 4], tg[i * 4 + 1], tg[i * 4 + 2], tg[i * 4 + 3]]])
	vs.sort()
	return "|".join(vs)

func _split() -> Array:
	var p: Array = []
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# kerb-like blocks along x, from -100 m to 150 m, each a quad 2 m long, coloured by its place
	for k in 125:
		var x0 := -100.0 + k * 2.0
		st.set_color(Color(k / 125.0, 0.5, 1.0 - k / 125.0))
		for q in [Vector3(x0, 0, 0), Vector3(x0 + 2.0, 0, 0), Vector3(x0 + 2.0, 0, -0.3),
				Vector3(x0, 0, 0), Vector3(x0 + 2.0, 0, -0.3), Vector3(x0, 0, -0.3)]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(q.x, q.z))
			st.add_vertex(q)
	st.generate_tangents()
	st.index()
	var arr := st.commit_to_arrays()
	var parts := Builder.split_by_cell(arr, Builder.SHADOW_CELL)
	var want := {}
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	for t in range(0, idx.size(), 3):
		want[_tri_key(arr, idx, t)] = int(want.get(_tri_key(arr, idx, t), 0)) + 1
	var got := {}
	var squares := {}
	for part in parts:
		var pi: PackedInt32Array = part[Mesh.ARRAY_INDEX]
		var pv: PackedVector3Array = part[Mesh.ARRAY_VERTEX]
		if (part[Mesh.ARRAY_TANGENT] as PackedFloat32Array).size() != pv.size() * 4 or (part[Mesh.ARRAY_COLOR] as PackedColorArray).size() != pv.size():
			p.append("a square's arrays keep one tangent (four floats) and one colour per vertex")
		var sq := {}
		for t in range(0, pi.size(), 3):
			var k := _tri_key(part, pi, t)
			got[k] = int(got.get(k, 0)) + 1
			var c := (pv[pi[t]] + pv[pi[t + 1]] + pv[pi[t + 2]]) / 3.0
			sq[Vector2i(int(floor(c.x / Builder.SHADOW_CELL)), int(floor(c.z / Builder.SHADOW_CELL)))] = true
		if sq.size() != 1:
			p.append("each square's mesh holds that square's triangles only (%d squares)" % sq.size())
		for s in sq:
			if squares.has(s):
				p.append("a square is one mesh, not two (%s)" % s)
			squares[s] = true
		var used := {}
		for i in pi:
			used[i] = true
		if used.size() != pv.size():
			p.append("a square's mesh holds only the vertices its triangles use (%d of %d)" % [used.size(), pv.size()])
	if got != want:
		p.append("split by square, every triangle is kept once with its vertices as they were (%d kinds of %d)" % [got.size(), want.size()])
	# -100 … 150 m in 48 m squares: -144…-96, -96…-48, …, 144…192: seven
	if parts.size() != 7:
		p.append("250 m of kerb is seven squares' meshes (%d)" % parts.size())
	if not Builder.split_by_cell([], Builder.SHADOW_CELL).is_empty():
		p.append("nothing to split is no mesh")
	return p

func _shades() -> Array:
	var p: Array = []
	var bld := Builder.new()
	# a hall 40 × 20 m, 10 m high; the sun 45° up in the south (plan -y; Godot +z): rays from inside go south and up
	var sun := Vector3(0.0, sin(PI / 4.0), cos(PI / 4.0))
	var pg := PackedVector2Array([Vector2(0, 0), Vector2(40, 0), Vector2(40, 20), Vector2(0, 20)])
	var hall := func(openings: Array) -> Dictionary:
		return {"id": "hall", "area": "a", "outline": pg, "height": 10.0, "openings": openings, "at": Vector2.ZERO, "yaw": 0.0}
	# a box from plan (x0, y0) to (x1, y1), z0 to z1 up, as an AABB in Godot's frame (y up, z = -plan y)
	var box := func(x0: float, y0: float, x1: float, y1: float, z0: float, z1: float) -> AABB:
		return AABB(Vector3(x0, z0, -y1), Vector3(x1 - x0, z1 - z0, y1 - y0))
	var south_door: Dictionary = hall.call([{"kind": "door", "at": [20, 0, 0], "width": 4.0, "height": 5.0}])
	var h1 := bld.roof_shade_holes(south_door)
	# in the middle: its rays reach the south wall at 10 m and more, over the door, then the roof
	if not Builder.roof_shades(box.call(18, 10, 22, 12, 0, 2), south_door, h1, sun):
		p.append("a piece in the hall's middle, its rays over the door, is shaded by the roof")
	# by the door, on the sun's side: its rays leave through the door
	if Builder.roof_shades(box.call(19, 2, 21, 3, 0, 1), south_door, h1, sun):
		p.append("a piece whose rays leave by the door on the sun's side casts its shadow")
	# beside the door but within the margin of its frame's edge
	if Builder.roof_shades(box.call(22.2, 2, 23, 3, 0, 1), south_door, h1, sun):
		p.append("a piece whose rays pass within the margin of the door casts its shadow")
	# the same piece in a hall whose door is in the north wall, away from the sun: shaded
	var north_door: Dictionary = hall.call([{"kind": "door", "at": [20, 20, 0], "width": 4.0, "height": 5.0}])
	if not Builder.roof_shades(box.call(19, 2, 21, 3, 0, 1), north_door, bld.roof_shade_holes(north_door), sun):
		p.append("a piece by the south wall, the door in the north one, is shaded")
	# a piece across the whole hall high up (its lamps), the door in the wall away from the sun: no ray from it goes
	# that way (the plane behind a ray's start is never met)
	if not Builder.roof_shades(box.call(2, 2, 38, 18, 8, 9), north_door, bld.roof_shade_holes(north_door), sun):
		p.append("a piece across the hall high up, the door in the wall away from the sun, is shaded")
	# a pipe's opening lets the sun in as a door does; a window and a louvre are on solid wall
	var pipe: Dictionary = hall.call([{"kind": "pipe", "at": [20, 0, 3], "width": 1.0, "height": 1.0}])
	if Builder.roof_shades(box.call(19.5, 1, 20.5, 1.5, 1.5, 2), pipe, bld.roof_shade_holes(pipe), sun):
		p.append("a piece whose rays leave by a pipe's opening casts its shadow")
	var win: Dictionary = hall.call([{"kind": "window", "at": [20, 0, 3], "width": 2.0, "height": 2.0},
		{"kind": "louvre", "at": [10, 0, 3], "width": 2.0, "height": 2.0}])
	if not Builder.roof_shades(box.call(19.5, 1, 20.5, 1.5, 1.5, 2), win, bld.roof_shade_holes(win), sun):
		p.append("windows and louvres (drawn on solid wall) stop the sun")
	# a roof opening (an intake on the roof): a piece high up under it casts; one far from it does not
	var intake: Dictionary = hall.call([{"kind": "intake", "at": [20, 10, 10], "width": 4.0, "height": 4.0}])
	var h2 := bld.roof_shade_holes(intake)
	if Builder.roof_shades(box.call(19, 11, 21, 12, 8, 9), intake, h2, sun):
		p.append("a piece whose rays leave by a roof opening casts its shadow")
	if not Builder.roof_shades(box.call(5, 15, 7, 16, 8, 9), intake, h2, sun):
		p.append("a piece far from the roof opening is shaded")
	# the sun straight along the south wall: its rays never meet that wall's plane
	var along := Vector3(sin(PI / 4.0), sin(PI / 4.0), 0.0).normalized()
	if not Builder.roof_shades(box.call(18, 10, 22, 12, 0, 2), south_door, h1, along):
		p.append("rays along a wall with its door: shaded")
	# the app's sun and the build's are one (Lighting.to_sun)
	var l := Lighting.sun()
	if l.basis.z.distance_to(Lighting.to_sun(Lighting.sky_info())) > 1e-4:
		p.append("the sun shines from Lighting.to_sun")
	l.free()
	return p

func _built(tree: SceneTree) -> Array:
	var p: Array = []
	var plant: Node3D = Plant.new()
	tree.root.add_child(plant)
	var err: String = plant.load_plant()
	if err != "":
		plant.free()
		return ["the built plant loads: " + err]
	var bld := Builder.new()
	var data := ProjectSettings.globalize_path("res://").path_join("../../data/plant3d").simplify_path()
	if not bld.read(data) or not bld.collect():
		plant.free()
		return ["the content builds (its buildings)"]
	# the kerbs and the boundary wall's panels: a mesh per square
	var ground := plant.get_node_or_null("ground")
	for nm in ["kerbs", "panels"]:
		var whole := ground.find_children(nm, "MeshInstance3D", true, false) if ground != null else []
		var cells := ground.find_children(nm + "_*", "MeshInstance3D", true, false) if ground != null else []
		if not whole.is_empty() or cells.size() < 4:
			p.append("the %s are a mesh per square (%d whole, %d squares)" % [nm, whole.size(), cells.size()])
		for mi in cells:
			var bx: AABB = mi.global_transform * mi.mesh.get_aabb()
			if bx.size.x > Builder.SHADOW_CELL + 8.0 or bx.size.z > Builder.SHADOW_CELL + 8.0:
				p.append("%s spans one square (%.0f × %.0f m)" % [mi.name, bx.size.x, bx.size.z])
			if mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				p.append("%s still casts its shadow" % mi.name)
	# under the roofs
	var shaded := 0
	for a in bld.areas:
		var area := plant.get_node_or_null("area_" + a.id) as Node3D
		if area == null:
			continue
		var mine: Array = bld.buildings.filter(func(b): return b.area == a.id)
		for n in area.find_children("*", "GeometryInstance3D", true, false):
			var gi := n as GeometryInstance3D
			if gi.has_meta("roof_shaded"):
				shaded += 1
				if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
					p.append("%s, under a roof, casts no shadow" % area.get_path_to(gi))
				var bx = Builder.shade_box(gi)
				if bx == null or Builder.inside_building(bx, mine, 0.0) == null:
					p.append("%s, shaded by a roof, stands inside a building of its area" % area.get_path_to(gi))
				if Builder._in_door(gi):
					p.append("%s moves with a door: it keeps its shadow" % area.get_path_to(gi))
		for b in mine:
			var body := area.find_child(b.id, true, false)
			if body == null:
				continue
			for part in ["walls", "roof"]:
				var mi := body.get_node_or_null(part) as GeometryInstance3D
				if mi != null and mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
					p.append("%s's %s cast the shadow that hides what is inside" % [b.id, part])
	if shaded < 20:
		p.append("pieces under the halls' roofs cast no shadow (%d)" % shaded)
	plant.free()
	return p
