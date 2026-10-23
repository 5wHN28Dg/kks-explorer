## The water treatment plant's and its intake's far view (builder/plant_builder.gd `far_merge`): their pieces merged
## per square and material, drawn from FAR_MERGE_RANGE out, each piece itself drawn only nearer (its
## `visibility_parent`); nothing lost in the merge (every piece's geometry is in its square's far mesh), in the
## plant's vertex format without UV2 (no pipeline of its own), and casting no shadow.
extends RefCounted

const Plant = preload("res://app/plant.gd")
const Builder = preload("res://builder/plant_builder.gd")
const FORMAT := Mesh.ARRAY_FORMAT_VERTEX | Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_TANGENT | Mesh.ARRAY_FORMAT_COLOR | Mesh.ARRAY_FORMAT_TEX_UV

func run(tree: SceneTree) -> Array:
	var p: Array = []
	var plant: Node3D = Plant.new()
	tree.root.add_child(plant)
	var err: String = plant.load_plant()
	if err != "":
		plant.free()
		return ["the built plant loads: " + err]
	for id in ["area_wtp", "area_intake"]:
		var area := plant.get_node_or_null(id) as Node3D
		if area == null:
			p.append("%s is in the built plant" % id)
			continue
		var far := area.get_node_or_null("far")
		if far == null or far.get_child_count() == 0:
			p.append("%s has its far view" % id)
			continue
		var far_v := 0
		for f in far.get_children():
			var mi := f as MeshInstance3D
			if absf(mi.visibility_range_begin - Builder.FAR_MERGE_RANGE) > 1e-3 or mi.visibility_range_end != 0.0:
				p.append("%s's far mesh %s is drawn from %d m out" % [id, mi.name, int(Builder.FAR_MERGE_RANGE)])
			if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				p.append("%s's far mesh %s casts no shadow" % [id, mi.name])
			for s in mi.mesh.get_surface_count():
				var fmt: int = (mi.mesh as ArrayMesh).surface_get_format(s) & (Mesh.ARRAY_FORMAT_VERTEX | Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_TANGENT | Mesh.ARRAY_FORMAT_COLOR | Mesh.ARRAY_FORMAT_TEX_UV | Mesh.ARRAY_FORMAT_TEX_UV2)
				if fmt != FORMAT:
					p.append("%s's far mesh %s is in the plant's vertex format without UV2 (%d)" % [id, mi.name, fmt])
				far_v += (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		# every drawn piece (but the far meshes) has a far mesh as its visibility parent; its vertices are all merged
		var near_v := 0
		var orphans := 0
		var orphan := ""
		var stack: Array = area.get_children()
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n == far:
				continue
			stack.append_array(n.get_children())
			var gi := n as GeometryInstance3D
			if gi == null or not gi.visible or gi is Label3D or gi.has_meta("hlod_keep"):
				continue
			if gi.visibility_parent.is_empty() or not (gi.get_node_or_null(gi.visibility_parent) is MeshInstance3D):
				orphans += 1
				orphan = str(area.get_path_to(gi))
			if Builder._in_door(gi):
				continue
			var mesh: Mesh = gi.mesh if gi is MeshInstance3D else ((gi as MultiMeshInstance3D).multimesh.mesh if gi is MultiMeshInstance3D and gi.multimesh != null else null)
			var count := 1 if gi is MeshInstance3D else int(gi.get_meta("count", 0))
			if mesh == null:
				continue
			for s in mesh.get_surface_count():
				near_v += (mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() * count
		if orphans > 0:
			p.append("%s: %d pieces are drawn at every distance (no far view as their visibility parent), %s among them" % [id, orphans, orphan])
		if far_v != near_v:
			p.append("%s's far view holds all its pieces' geometry (%d vertices of %d)" % [id, far_v, near_v])
	plant.free()
	return p
