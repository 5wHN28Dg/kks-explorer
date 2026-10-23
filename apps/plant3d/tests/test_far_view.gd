## The water treatment plant's and its intake's far view (builder/plant_builder.gd `far_merge`): their pieces merged
## per square and material, drawn from FAR_MERGE_RANGE out, each piece itself drawn only nearer (its
## `visibility_parent`); nothing lost in the merge (every piece's geometry is in its square's far mesh) but the detail
## pieces, which keep their own range and are not in it; in the
## plant's vertex format without UV2 (no pipeline of its own), and casting no shadow.
extends RefCounted

const Plant = preload("res://app/plant.gd")
const Builder = preload("res://builder/plant_builder.gd")
const Main = preload("res://app/main.gd")
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
		var got := {}   # far mesh -> [vertices, indices, bounds] as merged
		for f in far.get_children():
			var mi := f as MeshInstance3D
			if absf(mi.visibility_range_begin - Builder.FAR_MERGE_RANGE) > 1e-3 or mi.visibility_range_end != 0.0:
				p.append("%s's far mesh %s is drawn from %d m out" % [id, mi.name, int(Builder.FAR_MERGE_RANGE)])
			if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				p.append("%s's far mesh %s casts no shadow" % [id, mi.name])
			var g := [0, 0, AABB()]
			for s in mi.mesh.get_surface_count():
				var fmt: int = (mi.mesh as ArrayMesh).surface_get_format(s) & (Mesh.ARRAY_FORMAT_VERTEX | Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_TANGENT | Mesh.ARRAY_FORMAT_COLOR | Mesh.ARRAY_FORMAT_TEX_UV | Mesh.ARRAY_FORMAT_TEX_UV2)
				if fmt != FORMAT:
					p.append("%s's far mesh %s is in the plant's vertex format without UV2 (%d)" % [id, mi.name, fmt])
				var arr := mi.mesh.surface_get_arrays(s)
				g[0] += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
				g[1] += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
			g[2] = (mi.global_transform * mi.mesh.get_aabb())
			got[mi] = g
		# every merged piece has its square's far mesh as its visibility parent, and that mesh holds its geometry in
		# place: per far mesh, the same vertices and indices as its pieces, over the same box
		var want := {}   # far mesh -> [vertices, indices, bounds] of its pieces
		var orphans := 0
		var details := 0
		var orphan := ""
		var stack: Array = area.get_children()
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n == far:
				continue
			stack.append_array(n.get_children())
			var gi := n as GeometryInstance3D
			if gi != null and gi.is_in_group("detail"):   # a detail keeps its own range (app/quality.gd), never under the far view
				details += 1
				if not gi.visibility_parent.is_empty():
					p.append("%s's detail %s keeps its own range, not the far view's" % [id, area.get_path_to(gi)])
				continue
			if not Builder.far_mergeable(gi, area):
				continue
			var par := gi.get_node_or_null(gi.visibility_parent) as MeshInstance3D if not gi.visibility_parent.is_empty() else null
			if par == null or not got.has(par):
				orphans += 1
				orphan = str(area.get_path_to(gi))
				continue
			if Builder._in_door(gi):
				continue
			var mesh: Mesh = gi.mesh if gi is MeshInstance3D else (gi as MultiMeshInstance3D).multimesh.mesh
			var xfs: Array = [gi.global_transform]
			if gi is MultiMeshInstance3D:
				xfs = []
				var buf: PackedFloat32Array = gi.get_meta("xforms")
				for i in int(gi.get_meta("count")):
					var q := buf.slice(i * 12, i * 12 + 12)
					xfs.append(gi.global_transform * Transform3D(Basis(Vector3(q[0], q[4], q[8]), Vector3(q[1], q[5], q[9]), Vector3(q[2], q[6], q[10])), Vector3(q[3], q[7], q[11])))
			if not want.has(par):
				want[par] = [0, 0, null]
			var w: Array = want[par]
			for s in mesh.get_surface_count():
				var arr := mesh.surface_get_arrays(s)
				var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var idx = arr[Mesh.ARRAY_INDEX]
				for t: Transform3D in xfs:
					w[0] += v.size()
					w[1] += (idx as PackedInt32Array).size() if idx != null else v.size()
					for x in v:
						var wx: Vector3 = t * x
						w[2] = AABB(wx, Vector3.ZERO) if w[2] == null else (w[2] as AABB).expand(wx)
		if orphans > 0:
			p.append("%s: %d pieces are drawn at every distance (no far view as their visibility parent), %s among them" % [id, orphans, orphan])
		if details == 0:
			p.append("%s has detail pieces (left out of its far view)" % id)
		for mi in got:
			var g: Array = got[mi]
			var w: Array = want.get(mi, [0, 0, null])
			if g[0] != w[0] or g[1] != w[1]:
				p.append("%s's far mesh %s holds its pieces' geometry (%d vertices and %d indices, of %d and %d)" % [id, mi.name, g[0], g[1], w[0], w[1]])
			elif w[2] == null or not _same_box(g[2], w[2]):
				p.append("%s's far mesh %s lies where its pieces do (%s, they %s)" % [id, mi.name, str(g[2]), str(w[2])])
	# fx_off=farview (app/main.gd): the far views hidden, every piece under one drawn at every distance again
	Main.far_view_off(plant)
	for n in plant.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		if gi.has_meta("far_view") and gi.visible:
			p.append("fx_off=farview hides the far view %s" % gi.name)
		var par := gi.get_node_or_null(gi.visibility_parent) if not gi.visibility_parent.is_empty() else null
		if par != null and par.has_meta("far_view"):
			p.append("fx_off=farview draws %s at every distance" % gi.name)
			break
	plant.free()
	return p

static func _same_box(a: AABB, b: AABB) -> bool:
	return a.position.distance_to(b.position) < 0.01 and a.end.distance_to(b.end) < 0.01
