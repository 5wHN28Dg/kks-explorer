## Occlusion culling (builder/plant_builder.gd `_occluder`, project.godot): every building's walls and roof are an
## occluder, so that a hall's inside is not drawn from outdoors nor the plant outside from in a hall (the Note 9's GPU
## held 100-120 ms frames in the water treatment plant's hall, where 1,570 draw calls were made for a view of its
## walls). An occluder must never stand in a doorway: what is seen through an open door would vanish.
extends RefCounted

const Plant = preload("res://app/plant.gd")

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
		var lo := Vector3.INF
		var hi := -Vector3.INF
		for k in range(0, ix.size(), 3):
			tris.append([xf * v[ix[k]], xf * v[ix[k + 1]], xf * v[ix[k + 2]]])
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
		for t in tris:
			if Geometry3D.segment_intersects_triangle(mid - through, mid + through, t[0], t[1], t[2]) != null:
				p.append("no occluder in the doorway of %s (at %s)" % [d.name, mid])
				break
	if doors < 5:
		p.append("the plant's doors are found (%d)" % doors)
	plant.free()
	return p
