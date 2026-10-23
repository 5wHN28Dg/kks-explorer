## Occlusion culling (builder/plant_builder.gd `_occluder`, project.godot): every building's walls and roof are an
## occluder, so that a hall's inside is not drawn from outdoors nor the plant outside from in a hall (the Note 9's GPU
## held 100-120 ms frames in the water treatment plant's hall, where 1,570 draw calls were made for a view of its
## walls). An occluder must never stand in a doorway: what is seen through an open door would vanish.
extends RefCounted

const Plant = preload("res://app/plant.gd")
const Builder = preload("res://builder/plant_builder.gd")

func run(tree: SceneTree) -> Array:
	var p: Array = []
	if not ProjectSettings.get_setting("rendering/occlusion_culling/use_occlusion_culling", false):
		p.append("occlusion culling is on in project.godot")
	var plant: Node3D = Plant.new()
	tree.root.add_child(plant)
	var err: String = plant.load_plant()
	if err != "":
		plant.free()
		return p + ["the built plant loads: " + err]
	var tris: Array = []   # [a, b, c] in world space
	var buildings := 0
	for body in plant.find_children("*", "StaticBody3D", true, false):
		if not body.has_meta("building"):
			continue
		buildings += 1
		var oi := body.get_node_or_null("occluder") as OccluderInstance3D
		var ao := oi.occluder as ArrayOccluder3D if oi != null else null
		if ao == null or ao.get_vertices().size() < 3 or ao.get_indices().size() % 3 != 0:
			p.append("building %s has its walls and roof as an occluder" % body.get_meta("building"))
			continue
		var v := ao.get_vertices()
		var ix := ao.get_indices()
		var xf: Transform3D = oi.global_transform
		var own: Array = []
		var top := -INF
		for k in range(0, ix.size(), 3):
			own.append([xf * v[ix[k]], xf * v[ix[k + 1]], xf * v[ix[k + 2]]])
			top = maxf(top, (xf * v[ix[k]]).y)
		tris.append_array(own)
		# it covers the roof and the walls: from under a piece of the roof, a line up meets it, and lines out across
		# the floor meet it at least three ways of four (a door may stand in the fourth)
		var under := Vector3.INF
		for t in own:
			if absf(t[0].y - top) < 1e-3 and absf(t[1].y - top) < 1e-3 and absf(t[2].y - top) < 1e-3:
				under = (t[0] + t[1] + t[2]) / 3.0
				break
		if under == Vector3.INF:
			p.append("building %s's occluder has its roof" % body.get_meta("building"))
			continue
		# the roof's occluder covers the whole roof: its area that of the roof mesh's top faces
		var occ_area := 0.0
		for t in own:
			if absf(t[0].y - top) < 1e-3 and absf(t[1].y - top) < 1e-3 and absf(t[2].y - top) < 1e-3:
				occ_area += ((t[1] - t[0]).cross(t[2] - t[0])).length() * 0.5
		var roof_area := _top_area(body.get_node_or_null("roof") as MeshInstance3D)
		if roof_area <= 0.0 or absf(occ_area - roof_area) > 0.01 * roof_area + 0.05:
			p.append("building %s's occluder covers its roof (%.1f of %.1f m²)" % [body.get_meta("building"), occ_area, roof_area])
		var mid := Vector3(under.x, top * 0.5, under.z)
		if not _hits(own, Vector3(under.x, 0.5, under.z), under + Vector3.UP * 5.0):
			p.append("building %s's occluder covers its roof" % body.get_meta("building"))
		var ways := 0
		for d in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
			if _hits(own, mid, mid + d * 400.0):
				ways += 1
		if ways < 3:
			p.append("building %s's occluder has its walls (a line out met it %d ways of four)" % [body.get_meta("building"), ways])
		# the occluder is the building's own: inside its walls' bounds
		var aabb := AABB()
		var first := true
		for mi in body.find_children("*", "MeshInstance3D", false, false):
			var bb: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
			aabb = bb if first else aabb.merge(bb)
			first = false
		for q in v:
			if not aabb.grow(0.3).has_point(xf * q):
				p.append("building %s's occluder stays within its walls (%s)" % [body.get_meta("building"), xf * q])
				break
	if buildings < 5:
		p.append("the plant has its buildings (%d)" % buildings)
	# no occluder in a doorway: a line through each door, at half its height, from a metre before it to a metre behind
	var doors := 0
	for d in plant.find_children("*", "AnimatableBody3D", true, false):
		if not "kind" in d or not "height" in d:
			continue
		doors += 1
		var xf: Transform3D = d.global_transform
		var mid: Vector3 = xf.origin + xf.basis.y.normalized() * (float(d.height) * 0.5)
		var through: Vector3 = xf.basis.z.normalized()
		# and none within a few decimetres round it (Builder.OCC_MARGIN): beside each jamb and over the head
		var side: Vector3 = xf.basis.x.normalized() * (float(d.width) * 0.5 + Builder.OCC_MARGIN * 0.5)
		var up: Vector3 = xf.basis.y.normalized() * (float(d.height) * 0.5 + Builder.OCC_MARGIN * 0.5)
		for at in [mid, mid + side, mid - side, mid + up]:
			var hit := false
			for t in tris:
				if Geometry3D.segment_intersects_triangle(at - through, at + through, t[0], t[1], t[2]) != null:
					hit = true
					break
			if hit:
				p.append("no occluder in or just round the doorway of %s (at %s)" % [d.name, at])
				break
	if doors < 5:
		p.append("the plant's doors are found (%d)" % doors)
	plant.free()
	# what is drawn through walls on purpose (no depth test: the pointer's box and arrow, the map's marker and labels)
	# is never culled by the occluders
	var main: Node = (load("res://app/main.tscn") as PackedScene).instantiate()
	tree.root.add_child(main)
	for i in 30:
		await tree.process_frame
		if main.first_frame_ms >= 0:
			break
	var through := 0
	for g in main.find_children("*", "GeometryInstance3D", true, false):
		var nd := false
		if g is Label3D:
			nd = (g as Label3D).no_depth_test
		elif g.material_override is BaseMaterial3D:
			nd = (g.material_override as BaseMaterial3D).no_depth_test
		if nd:
			through += 1
			if not (g as GeometryInstance3D).ignore_occlusion_culling:
				p.append("%s, drawn through walls, is not culled by the occluders" % main.get_path_to(g))
	if through < 3:
		p.append("the app's pointer and map marker are found (%d drawn through walls)" % through)
	main.free()
	return p

## The area of a mesh's upward faces at its top (a roof slab's upper side), in world space.
static func _top_area(mi: MeshInstance3D) -> float:
	if mi == null or mi.mesh == null:
		return 0.0
	var xf := mi.global_transform
	var tris: Array = []
	var top := -INF
	for si in mi.mesh.get_surface_count():
		var arr := mi.mesh.surface_get_arrays(si)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ix = arr[Mesh.ARRAY_INDEX]
		var n: int = ix.size() if ix != null else v.size()
		for k in range(0, n, 3):
			var t := [xf * v[ix[k] if ix != null else k], xf * v[ix[k + 1] if ix != null else k + 1], xf * v[ix[k + 2] if ix != null else k + 2]]
			tris.append(t)
			top = maxf(top, maxf(t[0].y, maxf(t[1].y, t[2].y)))
	var area := 0.0
	for t in tris:
		if absf(t[0].y - top) < 1e-3 and absf(t[1].y - top) < 1e-3 and absf(t[2].y - top) < 1e-3:
			area += ((t[1] - t[0]).cross(t[2] - t[0])).length() * 0.5
	return area

static func _hits(tris: Array, a: Vector3, b: Vector3) -> bool:
	for t in tris:
		if Geometry3D.segment_intersects_triangle(a, b, t[0], t[1], t[2]) != null:
			return true
	return false
