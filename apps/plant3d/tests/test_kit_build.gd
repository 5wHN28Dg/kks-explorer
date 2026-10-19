## The built plant made with the parts kit (builder/kit_place.gd, kit/README.md "Nodes"): every `anim` binding of the
## behaviour model (data/plant3d/model) finds its node, <KKS>/<channel>, with a unit axis and a kind; every equipment
## node carries its box; the instanced cells' saved transforms fill their MultiMeshes when the plant loads (twelve
## floats per instance); `detail` cells carry their size and box for their range, and no detail cell casts a shadow;
## tag plates' codes carry their legibility size.
extends RefCounted

const Plant = preload("res://app/plant.gd")

func run(tree: SceneTree) -> Array:
	var p: Array = []
	var plant: Node3D = Plant.new()
	tree.root.add_child(plant)
	var err: String = plant.load_plant()
	if err != "":
		plant.free()
		return ["the built plant loads: " + err]
	var nodes := {}
	for n in tree.get_nodes_in_group("equipment"):
		nodes[n.name] = n
		if not n.has_meta("aabb"):
			p.append("%s has its box (meta aabb)" % n.name)
	# every valve carries its tag plate, inline ones on pipes too (PLANT3D.md §4 `plate`, §10): the plate's code is
	# a Label3D named "plate" on the valve's node
	var valves := 0
	for n in tree.get_nodes_in_group("equipment"):
		if String(n.get_meta("part", "")).begins_with("valve_"):
			valves += 1
			if not n.get_node_or_null("plate") is Label3D:
				p.append("%s (%s) carries its tag plate" % [n.name, n.get_meta("part")])
	if valves < 15:
		p.append("the plant's valves were found (%d)" % valves)
	# the model's anim bindings
	var dir := ProjectSettings.globalize_path("res://").path_join("../../data/plant3d/model").simplify_path()
	var bound := 0
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".json"):
			continue
		var m = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(f)))
		for b in m.get("bind", []):
			if not b.has("anim"):
				continue
			var eq: Node = nodes.get(b.kks)
			if eq == null:
				p.append("%s: the binding's equipment %s is a node" % [f, b.kks])
				continue
			var mv: Node = eq.get_node_or_null(NodePath(b.anim))
			if mv == null:
				p.append("%s: %s has a node %s for its binding" % [f, b.kks, b.anim])
				continue
			bound += 1
			var ax = mv.get_meta("anim_axis", null)
			if not ax is Vector3 or absf(ax.length() - 1.0) > 1e-3 or not mv.has_meta("anim_kind"):
				p.append("%s/%s has a unit axis and a kind" % [b.kks, b.anim])
	if bound < 20:
		p.append("the model's anim bindings were found (%d)" % bound)
	# the cells
	var cells := 0
	for c in tree.get_nodes_in_group("kit_cells"):
		var mmi := c as MultiMeshInstance3D
		cells += 1
		var n := int(mmi.get_meta("count", -1))
		var buf: PackedFloat32Array = mmi.get_meta("xforms", PackedFloat32Array())
		if n < 1 or buf.size() != n * 12 or mmi.multimesh.instance_count != n:
			p.append("%s: %d instances, %d floats, the MultiMesh holds %d" % [mmi.name, n, buf.size(), mmi.multimesh.instance_count])
		if mmi.is_in_group("detail"):
			if not (mmi.has_meta("detail_size") and mmi.has_meta("box_half")) or mmi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				p.append("%s: a detail cell has its size and box and casts no shadow" % mmi.name)
	if cells < 100:
		p.append("the plant has its instanced cells (%d)" % cells)
	for l in tree.get_nodes_in_group("legible"):
		if not l.has_meta("legible_size"):
			p.append("%s: a plate's code has its legibility size" % l.get_path())
	# a tier switches every material with textures to its size, structures' too, each keeping its own set
	const Mat = preload("res://kit/materials.gd")
	if Mat.missing_textures().is_empty():
		# held here as the app's meshes hold theirs (a material nobody holds is loaded afresh from its file)
		var held: Array = []
		for name in ["deck_steel", "ground", "paint", "metal"]:
			held.append(load("res://built/materials/%s.tres" % name))
		Mat.apply_tier("full")
		var want := Mat.size_for("full")
		for name in ["deck_steel", "ground", "paint", "metal"]:
			var m := load("res://built/materials/%s.tres" % name) as Material
			var nt := Mat.texture_of(m, "NormalGL") if m != null else null
			var path := nt.resource_path if nt != null else ""
			var set_name: String = {"deck_steel": "DiamondPlate008C", "ground": "Gravel023", "paint": "PaintedMetal004", "metal": "Metal032"}[name]
			if not ("/%d/" % want in path and set_name in path):
				p.append("%s after the full tier: %s (want %s at %d px)" % [name, path, set_name, want])
		Mat.apply_tier("lean+vis")
	plant.free()
	return p
