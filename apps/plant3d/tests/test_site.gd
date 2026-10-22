## The site and the camp in the built plant (docs/plant3d/SITE.md, milestone C1; decision 0066):
## - the interiors (PLANT3D.md §18.5) load on a worker thread when the walker comes within 15 m of their doors, show,
##   and are freed beyond 30 m (app/interiors.gd); each holds its rooms' partitions, its furniture and its doors;
## - an interior's surfaces are the plant's one shader in the instanced pieces' vertex format and lighting (no UV2,
##   not baked): showing one compiles no pipeline the start has not (decision 0060);
## - the windbreak (builder/site.gd): two rows of tamarisk inside the wall's north and west sides, none in a process
##   area or by a road; the wall open at the plant gate's road and walkway only; the admin area and the gate inside the
##   wall, the camp and its road outside it.
extends RefCounted

const Plant = preload("res://app/plant.gd")
const Interiors = preload("res://app/interiors.gd")
const TestLaunch = preload("res://tests/test_launch.gd")
const Builder = preload("res://builder/plant_builder.gd")
const Site = preload("res://builder/site.gd")

func run(tree: SceneTree) -> Array:
	var p: Array = await interiors(tree)
	p.append_array(site())
	return p

func interiors(tree: SceneTree) -> Array:
	var p: Array = []
	var world := Node3D.new()
	tree.root.add_child(world)
	var plant := Plant.new()
	world.add_child(plant)
	var err := plant.load_plant()
	if err != "":
		world.free()
		return [err]
	var who := Node3D.new()
	world.add_child(who)
	var it := Interiors.new()
	world.add_child(it)
	it.setup(plant, who)
	for id in ["block1_in", "mess_in", "prayer_in", "gym_in", "laundry_in", "rec_in", "admin_in", "workshop_in"]:
		if not it.items.has(id):
			p.append("the interior %s is in the built plant's manifest" % id)
	if not p.is_empty():
		world.free()
		return p
	if plant.manifest.areas.any(func(a): return it.items.has(a.id)):
		p.append("an interior is not loaded with the plant's areas at the start")
	# 12 m from block 1's west door: it loads (on a worker thread), and nothing far away does
	var door: Vector3 = it.items.block1_in.doors[0]
	who.global_position = door + Vector3(-12, 1, 0)
	var waited := 0
	while not it.loaded("block1_in") and waited < 600:
		await tree.process_frame
		waited += 1
	if not it.loaded("block1_in"):
		p.append("block 1's interior is shown 12 m from its door (waited %d frames)" % waited)
		world.free()
		return p
	for far in ["mess_in", "admin_in", "workshop_in"]:
		if it.loaded(far):
			p.append("%s is loaded while the walker is %.0f m from it" % [far, it.distance(far, who.global_position)])
	var node: Node = it.items.block1_in.node
	var doors := node.find_children("*", "AnimatableBody3D", true, false).filter(func(n): return n.is_in_group("doors"))
	if doors.size() < 4:
		p.append("block 1's interior has its rooms' and bathrooms' doors (%d)" % doors.size())
	var solid := node.find_children("*", "CollisionShape3D", true, false).size()
	if solid < 40:
		p.append("block 1's partitions and furniture are solid (%d shapes)" % solid)
	# its surfaces: the plant's shader and vertex format, unbaked (no UV2, the sky's light): no new pipeline
	p.append_array(TestLaunch.lit_surfaces(node, "block 1's interior"))
	p.append_array(unbaked(node, "block 1's interior"))
	# beyond 30 m it is freed
	who.global_position = door + Vector3(-40, 1, 0)
	var t_free := Time.get_ticks_msec()   # by the clock: the loader checks 4 times a second of frame time
	while it.loaded("block1_in") and Time.get_ticks_msec() - t_free < 5000:
		await tree.process_frame
	if it.loaded("block1_in"):
		p.append("block 1's interior is freed 40 m from its doors")
	while not it._dying.is_empty() and Time.get_ticks_msec() - t_free < 10000:
		await tree.process_frame   # (taken out a few pieces a frame)
	if not it._dying.is_empty():
		p.append("block 1's interior is taken out within 10 s")
	# every interior, as the walking tests load them: each the same kind of surfaces
	err = plant.load_interiors()
	if err != "":
		p.append(err)
	else:
		for a in plant.manifest.interiors:
			var n := plant.find_child("area_" + a.id, false, false)
			if n == null:
				p.append("the interior %s loads" % a.id)
				continue
			p.append_array(TestLaunch.lit_surfaces(n, a.id))
			p.append_array(unbaked(n, a.id))
	world.free()
	return p

## Problems with an interior's pieces: every drawn piece left out of the bake (GI disabled) and without UV2.
static func unbaked(root: Node, what: String) -> Array:
	var p: Array = []
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		var mesh: Mesh = null
		if n is MeshInstance3D:
			mesh = n.mesh
		elif n is MultiMeshInstance3D and n.multimesh != null:
			mesh = n.multimesh.mesh
		if mesh == null:
			continue
		if gi.gi_mode != GeometryInstance3D.GI_MODE_DISABLED:
			p.append("%s: %s is left out of the bake (GI mode %d)" % [what, n.name, gi.gi_mode])
		for s in mesh.get_surface_count():
			if (mesh as ArrayMesh) != null and (mesh as ArrayMesh).surface_get_format(s) & Mesh.ARRAY_FORMAT_TEX_UV2:
				p.append("%s: %s has a second UV set (a pipeline of its own unbaked)" % [what, n.name])
		if p.size() > 5:
			break
	return p

func site() -> Array:
	var p: Array = []
	var b := Builder.new()
	var data := ProjectSettings.globalize_path("res://").path_join("../../data/plant3d").simplify_path()
	if not b.read(data) or not b.collect():
		return ["the content builds: %s" % str(b.errors)]
	var s := Site.new(b)
	var wall := s.wall_rect()
	var ext := s.extent()
	var road_out := ext.grow(Site.ROAD_GAP + Site.ROAD_W)
	# the site areas inside the wall, the camp's outside it
	for a in b.areas:
		if Site.interior(a):
			continue
		var r := Site._rect(a.data.bounds)
		var pack: String = a.data.get("pack", "")
		if pack == Site.CAMP_PACK and wall.intersects(r):
			p.append("the camp's area %s lies outside the plant's wall" % a.id)
		elif pack != Site.CAMP_PACK and not wall.encloses(r):
			p.append("the area %s lies inside the plant's wall" % a.id)
		if pack == Site.SITE_PACK and road_out.intersects(r):
			p.append("the site's area %s keeps clear of the ring road" % a.id)
	# the wall is open at the plant gate (its road and walkway, side by side) and nowhere else
	var pg := Site.poly_of(wall)
	var gaps := 0
	for j in pg.size():
		for cut in s.road_cuts(pg[j], pg[(j + 1) % pg.size()]):
			gaps += 1
			var width: float = cut[1] - cut[0]
			if width < 9.0 or width > 12.0:
				p.append("the plant gate's opening is the road and its walkway wide (%.1f m)" % width)
	if gaps != 1:
		p.append("the wall has one opening, the plant gate (%d)" % gaps)
	# the windbreak
	var trees := s.windbreak_places(wall, road_out)
	if trees.size() < 300:
		p.append("the windbreak has its trees along the north and west walls (%d)" % trees.size())
	var north := 0
	var west := 0
	for t in trees:
		var tp: Vector2 = t
		var dn := wall.end.y - tp.y
		var dw := tp.x - wall.position.x
		if dn > 0.0 and dn <= 6.0:
			north += 1
		elif dw > 0.0 and dw <= 6.0:
			west += 1
		else:
			p.append("a windbreak tree at %s stands along the north or west wall" % str(tp))
			break
		for a in b.areas:
			if not Site.interior(a) and not a.data.get("pack", "") in [Site.SITE_PACK, Site.CAMP_PACK] and Site._rect(a.data.bounds).has_point(tp):
				p.append("a windbreak tree stands in the process area %s" % a.id)
		for sf in s.roads():
			if Site._bbox(sf.outline).grow(4.0).has_point(tp):
				p.append("a windbreak tree at %s stands by the road %s" % [str(tp), sf.id])
	if north < 200 or west < 60:
		p.append("the windbreak lines both the north (%d trees) and the west (%d) walls" % [north, west])
	return p
