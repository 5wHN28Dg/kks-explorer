## The Workshop's pre-built scenes (docs/plant3d/WORKSHOP.md §5, milestone K1a): for every part kind with a Workshop
## data file (`data/plant3d/workshop/<part>.json`, checked by ref/plant3d_workshop.py first), `built/workshop/<part>.scn`
## from `Kit.make(..., workshop = true)`, joined with the data file's words and order. The app never builds geometry
## (decision 0054 §4): it loads these.
##
## The scene: the root `Node3D` (named by the part; meta `workshop`: the data file's words, order, views and sources,
## `tris`, `box`, `flows`), then one `Node3D` per component at its pivot, named by its id and nested as the tree (metas
## `id`, `depth`, `box` (the part's frame in Godot's axes), `explode` [direction, metres], `sym`, `anchors`
## (relative to the component's pivot, Godot's axes), `anim`,
## `thin`), each with one `MeshInstance3D` per material (its pieces merged, relative to the pivot; meta `mat`: the
## plant's material name, resolved when the scene is shown) and its fastener groups (a `Node3D` per group, metas
## `id`, `kind`, `items` (transforms relative to the component's pivot: Godot's headless renderer keeps no MultiMesh
## data), `back_out` (metres), with a `MultiMeshInstance3D` per material). Same frame as the plant's part (kit/README.md
## "Frames"): origin and axes of the part.
extends RefCounted

const Kit = preload("res://kit/kit.gd")
const CID := "^[a-z_][a-z0-9_]{0,15}$"
const MAX_DEPTH := 6
const TRIS_MAX := 120000   # one kind's scene, all components and insides (WORKSHOP.md §8)
const FASTENER_KINDS := ["bolt", "stud_nut", "screw", "cap_screw", "threaded_cover", "clamp", "gland", "pin", "circlip", "key"]

## Builds every kind with a data file in `data_dir` into `out_dir`. `equipment` (the plant builder's, kks -> {part,
## params}) gives a kind's parameters where its data file has none: the first instance of that kind in the plant.
## Returns {built: [part], tris: {part: n}, errors: [text]}.
static func build_all(out_dir: String, data_dir: String, equipment: Dictionary) -> Dictionary:
	var out := {"built": [], "tris": {}, "errors": []}
	var dir := ProjectSettings.globalize_path(data_dir) if data_dir.begins_with("res://") else data_dir
	if not DirAccess.dir_exists_absolute(dir):
		return out
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var files := Array(DirAccess.get_files_at(dir))
	files.sort()
	for f in files:
		if not f.ends_with(".json"):
			continue
		var data = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(f)))
		if not data is Dictionary or not data.get("part") is String:
			out.errors.append("workshop/%s: not a Workshop data file" % f)
			continue
		var part: String = data.part
		var r := scene(part, data, params_for(part, data, equipment))
		if not r.errors.is_empty():
			for e in r.errors:
				out.errors.append("workshop/%s: %s" % [f, e])
			continue
		var path := out_dir.path_join(part + ".scn")
		var e := ResourceSaver.save(r.scene, path, ResourceSaver.FLAG_COMPRESS)
		if e != OK:
			out.errors.append("workshop/%s: save %s: error %d" % [f, path, e])
			continue
		out.built.append(part)
		out.tris[part] = r.tris
	return out

## A kind's parameters in the Workshop: its data file's, or its first instance's in the plant, or the kit's defaults.
static func params_for(part: String, data: Dictionary, equipment: Dictionary) -> Dictionary:
	if data.has("params"):
		return Kit.params_of(part, data.params)
	for kks in equipment:
		var e: Dictionary = equipment[kks]
		if e.get("part", "") == part:
			return Kit.params_of(part, e.get("params", {}))
	return Kit.params_of(part, {})

## One kind's Workshop scene: {scene: PackedScene, tris, res (Kit.make's Workshop result), errors}. `ctx` as Kit.make's
## (default: the part standing free, upright).
static func scene(part: String, data: Dictionary, params: Dictionary, ctx := {}) -> Dictionary:
	var out := {"scene": null, "tris": 0, "res": {}, "errors": [], "params": params}
	if not Kit.has_part(part):
		out.errors.append("the kit has no part %s" % part)
		return out
	var res := Kit.make(part, params, ctx, 1.0, true)
	out.res = res
	out.tris = res.get("tris", 0)
	out.errors = join(res, data)
	if out.tris > TRIS_MAX:
		out.errors.append("%d triangles, over the Workshop's %d for one kind" % [out.tris, TRIS_MAX])
	if not out.errors.is_empty():
		return out
	var root := _nodes(part, res, data)
	root.set_meta("params", params)   # what it was built with (the tests check that very shape)
	for c in root.get_children():
		_own(root, c)
	var ps := PackedScene.new()
	var e := ps.pack(root)
	root.free()
	if e != OK:
		out.errors.append("pack: error %d" % e)
		return out
	out.scene = ps
	return out

## The join of the generator's half and the data file's (WORKSHOP.md §4): every refusal as text.
static func join(res: Dictionary, data: Dictionary) -> Array:
	var errs: Array = []
	for p in res.get("problems", []):
		errs.append("the generator: " + p)
	var rx := RegEx.create_from_string(CID)
	var words: Dictionary = data.get("components", {})
	var fwords: Dictionary = data.get("fasteners", {})
	var gen := {}
	for c in res.components:
		if rx.search(c.id) == null:
			errs.append("component %s: not an identifier of at most 16 characters" % c.id)
		if gen.has(c.id):
			errs.append("component %s: declared twice" % c.id)
		gen[c.id] = c
	for c in res.components:
		if c.parent != "" and not gen.has(c.parent):
			errs.append("component %s: its parent %s is no component" % [c.id, c.parent])
		if not words.has(c.id):
			errs.append("component %s: the generator makes it, the data file doesn't name it" % c.id)
		var d := depth_of(c.id, gen)
		if d < 0:
			errs.append("component %s: its parents make a cycle" % c.id)
		elif d >= MAX_DEPTH:
			errs.append("component %s: %d levels deep, at most %d" % [c.id, d + 1, MAX_DEPTH])
	for id in words:
		if not gen.has(id):
			errs.append("component %s: the data file names it, the generator doesn't make it" % id)
	var groups := {}
	for f in res.fasteners:
		if rx.search(f.id) == null:
			errs.append("fastener group %s: not an identifier of at most 16 characters" % f.id)
		if groups.has(f.id) or gen.has(f.id):
			errs.append("fastener group %s: its id is taken" % f.id)
		groups[f.id] = f
		if not fwords.has(f.id):
			errs.append("fastener group %s: the generator makes it, the data file doesn't name it" % f.id)
		if f.items.is_empty():
			errs.append("fastener group %s: no items" % f.id)
		if not f.kind in FASTENER_KINDS:
			errs.append("fastener group %s: its kind %s is none of WORKSHOP.md §4.4's" % [f.id, f.kind])
	for id in fwords:
		if not groups.has(id):
			errs.append("fastener group %s: the data file names it, the generator doesn't make it" % id)
		for j in fwords[id].get("joins", []):
			if not gen.has(j):
				errs.append("fastener group %s: joins %s, which is no component" % [id, j])
	for s in data.get("assembly", []):
		if not (gen.has(s.get("place", "")) or groups.has(s.get("place", ""))):
			errs.append("assembly: a step places %s, which the generator doesn't make" % s.get("place", ""))
		for n in s.get("needs", []):
			if not gen.has(n[0]):
				errs.append("assembly: a step needs %s, which the generator doesn't make" % n[0])
	var views: Dictionary = data.get("views", {})
	var named: Array = views.get("xray_all", []) + views.get("cutaway", {}).get("keep", [])
	if views.get("run_exploded") is Dictionary:
		named += views.run_exploded.get("allowed", [])
	for id in named:
		if not gen.has(id):
			errs.append("views: %s is no component the generator makes" % id)
	for c in res.components:
		if c.anim != "" and not res.moving.any(func(mv): return mv.name == c.anim):
			errs.append("component %s: its anim %s is no moving piece" % [c.id, c.anim])
	return errs

## A component's depth (0 at the top), or -1 on a cycle.
static func depth_of(id: String, gen: Dictionary) -> int:
	var d := 0
	var seen := {}
	var at := id
	while gen.has(at) and gen[at].parent != "":
		if seen.has(at):
			return -1
		seen[at] = true
		at = gen[at].parent
		d += 1
		if d > 64:
			return -1
	return d

## A component's explode [direction, metres] (WORKSHOP.md §4.1): the generator's, else from the parent's box centre
## to the component's, 0.6 of the parent's size that way; where the two centres coincide, straight up by the
## parent's height and a tenth more. The top level's parent is the whole part.
static func explode_of(c: Dictionary, parent_box: AABB) -> Array:
	if not c.explode.is_empty():
		return [c.explode[0], float(c.explode[1])]
	var d: Vector3 = c.box.get_center() - parent_box.get_center()
	if d.length() < 1e-4:
		return [Vector3.UP, parent_box.size.y * 1.1]
	d = d.normalized()
	var s := parent_box.size
	return [d, 0.6 * (absf(d.x) * s.x + absf(d.y) * s.y + absf(d.z) * s.z)]

static func _nodes(part: String, res: Dictionary, data: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = part
	var whole := AABB()
	var first := true
	for c in res.components:
		if c.box.size != Vector3.ZERO or c.box.position != Vector3.ZERO:
			whole = c.box if first else whole.merge(c.box)
			first = false
	var gen := {}
	for c in res.components:
		gen[c.id] = c
	var nodes := {}
	# parents before children (declaration order may not be): placed by depth
	var order: Array = res.components.duplicate()
	order.sort_custom(func(a, b): return depth_of(a.id, gen) < depth_of(b.id, gen))
	for c in order:
		var n := Node3D.new()
		n.name = c.id
		var parent: Node3D = root if c.parent == "" else nodes[c.parent]
		var ppiv: Vector3 = Vector3.ZERO if c.parent == "" else gen[c.parent].pivot
		n.position = c.pivot - ppiv
		parent.add_child(n)
		nodes[c.id] = n
		var pbox: AABB = whole if c.parent == "" else gen[c.parent].box
		n.set_meta("id", c.id)
		n.set_meta("depth", depth_of(c.id, gen))
		n.set_meta("box", c.box)
		n.set_meta("explode", explode_of(c, pbox))
		n.set_meta("sym", c.sym)
		var anchors := {}         # relative to the pivot: they ride with the component
		for k in c.anchors:
			anchors[k] = c.anchors[k] - c.pivot
		n.set_meta("anchors", anchors)
		n.set_meta("anim", c.anim)
		n.set_meta("thin", c.thin)
	# each component's pieces merged per material, relative to its pivot (the moving pieces where they stand at 0)
	var per := {}   # comp -> mat -> [arrays, origin shift]
	for k in res.layers:
		var L: Dictionary = res.layers[k]
		_add(per, L.comp, L.mat, L.mesh.surface_get_arrays(0), Vector3.ZERO)
	for mv in res.moving:
		for k in mv.layers:
			var L: Dictionary = mv.layers[k]
			_add(per, L.comp, L.mat, L.mesh.surface_get_arrays(0), mv.pivot)
	for id in per:
		for mat in per[id]:
			var mi := MeshInstance3D.new()
			mi.name = "mesh_" + mat
			mi.mesh = _merged(per[id][mat], gen[id].pivot, "%s|%s" % [id, mat])
			mi.set_meta("mat", mat)
			nodes[id].add_child(mi)
	for f in res.fasteners:
		var host: Node3D = nodes.get(f.parent, root)
		var hpiv: Vector3 = gen[f.parent].pivot if gen.has(f.parent) else Vector3.ZERO
		var g := Node3D.new()
		g.name = f.id
		var items: Array = []
		for t in f.items:
			items.append(Transform3D(t.basis, t.origin - hpiv))
		g.set_meta("id", f.id)
		g.set_meta("kind", f.kind)
		g.set_meta("items", items)
		g.set_meta("back_out", maxf(0.01, 2.0 * f.box.size.length()))
		host.add_child(g)
		var mats := {}
		for k in f.layers:
			var L: Dictionary = f.layers[k]
			if not mats.has(L.mat):
				mats[L.mat] = []
			mats[L.mat].append([L.mesh.surface_get_arrays(0), Vector3.ZERO])
		for mat in mats:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = _merged(mats[mat], Vector3.ZERO, "%s|%s" % [f.id, mat])
			mm.instance_count = items.size()
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "mesh_" + mat
			mmi.multimesh = mm
			mmi.set_meta("mat", mat)
			g.add_child(mmi)
	var words := {"format": data.get("format", ""), "version": data.get("version", 0), "part": part,
		"components": data.get("components", {}), "fasteners": data.get("fasteners", {}),
		"assembly": data.get("assembly", []), "views": data.get("views", {}), "sources": data.get("sources", [])}
	root.set_meta("workshop", words)
	root.set_meta("tris", res.tris)
	root.set_meta("box", whole)
	root.set_meta("flows", res.flows)
	return root

static func _add(per: Dictionary, comp: String, mat: String, arr: Array, shift: Vector3) -> void:
	if not per.has(comp):
		per[comp] = {}
	if not per[comp].has(mat):
		per[comp][mat] = []
	per[comp][mat].append([arr, shift])

## Surfaces of one material merged into one mesh, vertices moved by their shift and then relative to `pivot`.
static func _merged(parts: Array, pivot: Vector3, name: String) -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var tg := PackedFloat32Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	for pr in parts:
		var arr: Array = pr[0]
		var shift: Vector3 = pr[1] - pivot
		var base := v.size()
		var pv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for p in pv:
			v.append(p + shift)
		n.append_array(arr[Mesh.ARRAY_NORMAL])
		if arr[Mesh.ARRAY_TANGENT] != null:
			tg.append_array(arr[Mesh.ARRAY_TANGENT])
		uv.append_array(arr[Mesh.ARRAY_TEX_UV])
		col.append_array(arr[Mesh.ARRAY_COLOR])
		for i in (arr[Mesh.ARRAY_INDEX] as PackedInt32Array):
			idx.append(base + i)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = v
	out[Mesh.ARRAY_NORMAL] = n
	if tg.size() == v.size() * 4:
		out[Mesh.ARRAY_TANGENT] = tg
	out[Mesh.ARRAY_TEX_UV] = uv
	out[Mesh.ARRAY_COLOR] = col
	out[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	mesh.resource_name = name
	return mesh

static func _own(owner: Node, n: Node) -> void:
	n.owner = owner
	for c in n.get_children():
		_own(owner, c)
