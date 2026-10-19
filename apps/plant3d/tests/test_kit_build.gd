## The built plant made with the parts kit (builder/kit_place.gd, kit/README.md "Nodes"): every `anim` binding of the
## behaviour model (data/plant3d/model) finds its node, <KKS>/<channel>, with a unit axis and a kind; every equipment
## node carries its box; the instanced cells' saved transforms fill their MultiMeshes when the plant loads (twelve
## floats per instance); `detail` cells carry their size and box for their range, and no detail cell casts a shadow;
## tag plates' codes carry their legibility size; the hearing-protection signs are ISO 7010 M003 (the symbol drawn as
## it should be: sampled from its mesh) above their text, on a board of one draw call (merged into its cell where it can be).
extends RefCounted

const Plant = preload("res://app/plant.gd")
const KitPlace = preload("res://builder/kit_place.gd")
const BLUE := Color(0.08, 0.28, 0.54)

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
	p.append_array(_safety_signs(tree))
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


## The colour seen at (x, y) of a sign's face (its frame: x across, y up, z out; Godot axes): the front-most face
## facing out that covers the point, null where none does.
static func _seen(arr: Array, x: float, y: float):
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var c: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var best = null
	var top := -INF
	var p := Vector2(x, y)
	for i in range(0, idx.size(), 3):
		var a := v[idx[i]]
		var b := v[idx[i + 1]]
		var d := v[idx[i + 2]]
		if absf((b - a).cross(d - a).normalized().z) < 0.9:
			continue           # the board's edges: only faces in the sign's plane (the front-most of them is seen)
		if Geometry2D.point_is_inside_triangle(p, Vector2(a.x, a.y), Vector2(b.x, b.y), Vector2(d.x, d.y)):
			var z := maxf(a.z, maxf(b.z, d.z))
			if z > top:
				top = z
				best = c[idx[i]]
	return best


## (a saved mesh keeps its colours in 8 bits)
static func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01


static func _is_blue(col) -> bool:
	return col is Color and _near(col, BLUE)


static func _is_white(col) -> bool:
	return col is Color and (col as Color).r > 0.85 and (col as Color).g > 0.85 and (col as Color).b > 0.85


func _safety_signs(tree: SceneTree) -> Array:
	var p: Array = []
	# the symbol, sampled from its mesh: blue to the rim, a white head with its ear cups and the headband over it,
	# each clear of the others by a blue gap; symmetric; a white board round it and behind the text
	var size := 0.3
	var L: Dictionary = KitPlace.sign_layout(4.0, size)
	var arr: Array = KitPlace.sign_mesh("M003", 4.0, size).finish().values()[0].arrays
	var R: float = L.r
	var cy: float = L.disc
	var at := func(x: float, y: float): return _seen(arr, x * R, cy + y * R)
	var want := {"the disc's rim": [[0.0, 0.95], [0.95, 0.0], [-0.67, 0.67], [0.0, -0.95]],
		"the gap between the head and an ear cup": [[0.27, 0.0], [-0.27, 0.0]],
		"the gap between the head and the headband": [[0.0, 0.39]]}
	for what in want:
		for q in want[what]:
			if not _is_blue(at.call(q[0], q[1])):
				p.append("M003: %s is not blue at %s (%s)" % [what, str(q), str(at.call(q[0], q[1]))])
	want = {"the head": [[0.0, 0.1]], "an ear cup": [[0.39, 0.0], [-0.39, 0.0]], "the headband": [[0.0, 0.465]],
		"the shoulders": [[0.0, -0.7], [0.4, -0.7]], "the board beside the disc": [[-1.2, 0.0]],
		"the board behind the text": [[0.0, -cy / R]]}
	for what in want:
		for q in want[what]:
			if not _is_white(at.call(q[0], q[1])):
				p.append("M003: %s is not white at %s (%s)" % [what, str(q), str(at.call(q[0], q[1]))])
	var white := 0
	var inside := 0
	var mirror := 0
	for i in 25:
		for j in 25:
			var x := -1.0 + (i + 0.5) / 12.5
			var y := -1.0 + (j + 0.5) / 12.5
			if x * x + y * y > 0.98:
				continue
			inside += 1
			var w := _is_white(at.call(x, y))
			white += 1 if w else 0
			if w != _is_white(at.call(-x, y)):
				mirror += 1
	if white < inside * 0.15 or white > inside * 0.5 or mirror > 0:
		p.append("M003: %d of %d samples of the disc white (15 to 50 %%), %d not mirrored" % [white, inside, mirror])
	# in the plant: every loud building's door sign carries the symbol; the text is black without an outline (one
	# draw call), as wide as the content's estimate allows (tools/plant3d/train_areas.py: 0.55 em a character),
	# and the board stands behind it in a cell (one surface; merged with its cell's other plain pieces where there are any)
	var signs := 0
	var boards := 0
	var merged := 0
	for l in tree.root.find_children("*", "Label3D", true, false):
		if not l.has_meta("symbol"):
			continue
		signs += 1
		var lab := l as Label3D
		var tw: float = lab.get_meta("text_width")
		var sz := lab.pixel_size * 64.0
		if lab.outline_size != 0 or lab.modulate.v > 0.1:
			p.append("%s: a safety sign's text is black, without an outline" % lab.get_path())
		# blended as the old label (smooth far off), and no shadow (a cut-out label casts one: a draw call more)
		if lab.alpha_cut != Label3D.ALPHA_CUT_DISABLED or lab.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			p.append("%s: a safety sign's text is cut out or casts a shadow" % lab.get_path())
		if tw > 0.55 * sz * lab.text.length() or tw < 0.3 * sz * lab.text.length():
			p.append("%s: its text is %.2f m wide, outside the content's estimate" % [lab.get_path(), tw])
		var disc: Vector3 = lab.global_position + Vector3.UP * KitPlace.sign_layout(tw, sz).disc
		var alone: int = KitPlace.sign_mesh("M003", tw, sz).finish().values()[0].arrays[Mesh.ARRAY_VERTEX].size()
		var found := false
		for c in tree.get_nodes_in_group("kit_cells") + tree.get_nodes_in_group("kit_static"):
			var mesh: Mesh = c.multimesh.mesh if c is MultiMeshInstance3D else c.mesh
			var xfs: Array = []
			if c is MultiMeshInstance3D:
				# from the saved buffer (a headless run's MultiMesh keeps none): 12 floats, basis rows and origin
				var buf: PackedFloat32Array = c.get_meta("xforms", PackedFloat32Array())
				for i in range(0, buf.size() - 11, 12):
					var q := buf.slice(i, i + 12)
					xfs.append(c.global_transform * Transform3D(Basis(Vector3(q[0], q[4], q[8]), Vector3(q[1], q[5], q[9]),
						Vector3(q[2], q[6], q[10])), Vector3(q[3], q[7], q[11])))
			else:
				xfs.append(c.global_transform)
			for xf in xfs:
				if (xf * mesh.get_aabb()).grow(0.05).has_point(disc):
					var cols: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
					if not cols.is_empty() and Array(cols).any(func(k): return _near(k, BLUE)):
						found = true
						# at most one draw call: one surface, merged with the cell's other plain pieces where it has
						# any (more vertices than the board's own); with the text's (its outline, a surface of its
						# own, is gone) no more than the old outlined label's two
						if mesh.get_surface_count() != 1:
							p.append("%s: the sign's board is %d draw calls" % [lab.get_path(), mesh.get_surface_count()])
						boards += 1
						merged += 1 if cols.size() > alone else 0
						if cols.size() <= alone and c.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
							p.append("%s: a board alone in its cell casts a shadow (a draw call more)" % lab.get_path())
		if not found:
			p.append("%s: no board with its blue disc behind the sign's text" % lab.get_path())
	if boards != signs:
		p.append("%d boards for %d signs (one each, in one cell)" % [boards, signs])
	if merged == 0:
		p.append("no sign's board merged into its cell with other pieces")
	if signs != 6:
		p.append("the plant has %d M003 signs (want the loud buildings' six doors)" % signs)
	return p
