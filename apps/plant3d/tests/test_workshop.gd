## The Workshop's component trees and pre-built scenes (docs/plant3d/WORKSHOP.md §4, §5, §10; milestone K1a), for every
## kind with a Workshop data file and for the data-only fixture kind (tests/fixtures/workshop_gadget.*):
## - the join of generator and data file is clean: unique ids, existing parents, no cycle, depth within 6, every
##   component and fastener group on both sides; each component's pivot inside the part's box;
## - the Workshop's outside is the plant's: Kit.make in both modes, per material, class and size bucket, the plant's
##   triangles are exactly the Workshop's shared ones plus its stand-ins'; each stand-in's replacements ("split"
##   pieces) cover its box within 1 mm in its material with 1 to 1.5 times its triangles;
## - "workshop" pieces are hidden (every ray from inside them meets the Workshop's outside) or small outside pieces
##   (at most 30 mm, listed with their sizes), fastener items too;
## - every non-thin component is closed (§7.2); the kind is within 120,000 triangles (§8);
## - the built scene (built/workshop/<part>.scn) loads, as the tree, with its words;
## - a generator that declares no components gives one component `body`; Kit.register adds a kind, never replaces one;
## - no part id of kit.json in the Workshop's code (apps/plant3d/workshop/).
extends RefCounted

const Kit = preload("res://kit/kit.gd")
const WB = preload("res://builder/workshop_build.gd")
const FIXTURE := "res://tests/fixtures/workshop_gadget.gd"
const FIXTURE_DATA := "res://tests/fixtures/workshop_gadget.json"
const DIRS := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1),
	Vector3(1, 1, 1), Vector3(1, 1, -1), Vector3(1, -1, 1), Vector3(1, -1, -1), Vector3(-1, 1, 1), Vector3(-1, 1, -1),
	Vector3(-1, -1, 1), Vector3(-1, -1, -1)]

var problems: Array = []

func check(ok: bool, what: String) -> void:
	if not ok:
		problems.append(what)

func run(_tree: SceneTree) -> Array:
	var data_dir := ProjectSettings.globalize_path("res://").path_join("../../data/plant3d/workshop").simplify_path()
	var kinds := 0
	for f in DirAccess.get_files_at(data_dir):
		if not f.ends_with(".json"):
			continue
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(data_dir.path_join(f)))
		var part: String = data.part
		kinds += 1
		# the parameters the build made its scene with (the plant's first instance of the kind), else the defaults
		var params := WB.params_for(part, data, {})
		var built := "res://built/workshop/%s.scn" % part
		if ResourceLoader.exists(built):
			var bs: Node = (load(built) as PackedScene).instantiate()
			params = bs.get_meta("params", params)
			bs.free()
		_kind(part, data, params)
		_built(part, data)
	check(kinds >= 1, "a kind with Workshop data (the pressure transmitter)")
	_fixture()
	_misuse()
	_pieces_owned()
	_body()
	_no_part_ids()
	Kit.clear_cache()
	return problems

## One kind: the join, the outside against the plant's, hidden and outside pieces, closed shells, the budget.
func _kind(part: String, data: Dictionary, params: Dictionary) -> void:
	var r := WB.scene(part, data, params)
	for e in r.errors:
		problems.append("%s: %s" % [part, e])
	var ws: Dictionary = r.res
	if ws.is_empty():
		return
	check(ws.tris <= WB.TRIS_MAX, "%s: %d triangles in the Workshop, at most %d" % [part, ws.tris, WB.TRIS_MAX])
	var whole := AABB()
	var first := true
	for k in ws.layers:
		var bb: AABB = ws.layers[k].mesh.get_aabb()
		whole = bb if first else whole.merge(bb)
		first = false
	var ids := {}
	for c in ws.components:
		check(not ids.has(c.id), "%s: component %s is unique" % [part, c.id])
		ids[c.id] = true
		check(whole.grow(0.001).has_point(c.pivot), "%s: %s's pivot %s inside the part's box" % [part, c.id, str(c.pivot)])
	# the same parameters in plant mode, for the outside: as the builder makes the plant's part
	var plant := Kit.make(part, params, {})
	_outside(part, plant, ws)
	_pieces(part, ws)
	_closed(part, ws)
	print("workshop: %s %d components, %d fastener groups, %d triangles (plant %d)" % [part, ws.components.size(),
		ws.fasteners.size(), ws.tris, plant.tris])

## Per material|class|bucket: the plant's triangles == the Workshop's shared ones + its stand-ins'.
func _outside(part: String, plant: Dictionary, ws: Dictionary) -> void:
	var want := {}   # plant key -> {triangle: count}
	for k in plant.layers:
		_count(want, k, plant.layers[k].mesh, 1)
	for mv in plant.moving:
		for k in mv.layers:
			_count(want, mv.name + "/" + k, mv.layers[k].mesh, 1)
	var got := {}
	for k in ws.layers:
		var L: Dictionary = ws.layers[k]
		if L.tag == "shared":
			_count(got, _plant_key(k), L.mesh, 1)
	for mv in ws.moving:
		for k in mv.layers:
			if mv.layers[k].tag == "shared":
				_count(got, mv.name + "/" + _plant_key(k), mv.layers[k].mesh, 1)
	for si in ws.standins:
		for k in si.layers:
			_count(got, (si.moving + "/" if si.moving != "" else "") + _plant_key(k), si.layers[k].mesh, 1)
	var keys := {}
	for k in want:
		keys[k] = true
	for k in got:
		keys[k] = true
	for k in keys:
		var a: Dictionary = want.get(k, {})
		var b: Dictionary = got.get(k, {})
		var diff := 0
		for t in a:
			diff += absi(a[t] - b.get(t, 0))
		for t in b:
			if not a.has(t):
				diff += b[t]
		check(diff == 0, "%s: layer %s: the Workshop's shared pieces and stand-ins differ from the plant's by %d triangles" % [part, k, diff])
	# each stand-in against the components that replace it ("split" pieces)
	for si in ws.standins:
		if si.replaced_by.is_empty():
			continue   # a mounting the Workshop leaves out
		var box := AABB()
		var any := false
		var tris := {}
		var stand_tris := {}
		for k in si.layers:
			stand_tris[si.layers[k].mat] = stand_tris.get(si.layers[k].mat, 0) + si.layers[k].tris[0]
		var from: Dictionary = ws.layers
		for mv in ws.moving:
			if mv.name == si.moving:
				from = mv.layers
		for k in from:
			var L: Dictionary = from[k]
			if L.tag == "split" and L.comp in si.replaced_by:
				var bb: AABB = L.mesh.get_aabb()
				box = bb if not any else box.merge(bb)
				any = true
				tris[L.mat] = tris.get(L.mat, 0) + L.tris[0]
		check(any, "%s: the stand-in for %s has its split pieces" % [part, str(si.replaced_by)])
		var sb: AABB = si.box
		check(box.position.distance_to(sb.position) <= 0.001 and box.end.distance_to(sb.end) <= 0.001,
			"%s: %s cover their stand-in's box within 1 mm (%s against %s)" % [part, str(si.replaced_by), str(box), str(sb)])
		for mat in stand_tris:
			var n: int = tris.get(mat, 0)
			check(n >= stand_tris[mat] and n <= stand_tris[mat] * 1.5,
				"%s: %s: %d triangles of %s against the stand-in's %d (1 to 1.5 times)" % [part, str(si.replaced_by), n, mat, stand_tris[mat]])
		for mat in tris:
			check(stand_tris.has(mat), "%s: %s add the material %s, which their stand-in hasn't" % [part, str(si.replaced_by), mat])
	# a "split" piece belongs to a component that replaces a stand-in: never a large outside shape of the Workshop's own
	var replacing := {}
	for si in ws.standins:
		for c in si.replaced_by:
			replacing[c] = true
	for pr in _all_layers(ws):
		var L: Dictionary = pr[0]
		check(L.tag != "split" or replacing.has(L.comp), "%s: %s has split pieces but replaces no stand-in" % [part, L.comp])

## Every layer, static and moving, with the offset that places it in the part's frame ([layer, offset]).
func _all_layers(ws: Dictionary) -> Array:
	var out: Array = []
	for k in ws.layers:
		out.append([ws.layers[k], Vector3.ZERO, k])
	for mv in ws.moving:
		for k in mv.layers:
			out.append([mv.layers[k], mv.pivot, mv.name + "/" + k])
	return out

## comp|tag|mat|class|bucket -> mat|class|bucket
func _plant_key(k: String) -> String:
	var s := k.split("|")
	return "|".join(s.slice(2))

func _count(into: Dictionary, key: String, mesh: ArrayMesh, n: int) -> void:
	if not into.has(key):
		into[key] = {}
	var arr := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var c: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	for t in range(0, idx.size(), 3):
		var tri: Array = []
		for j in 3:
			var i := idx[t + j]
			tri.append_array([v[i], nm[i], uv[i], c[i]])
		var s := var_to_bytes(tri).hex_encode()
		into[key][s] = into[key].get(s, 0) + n

## Hidden pieces are hidden; outside pieces and fastener items are small.
func _pieces(part: String, ws: Dictionary) -> void:
	var listed := PackedStringArray()
	for pc in ws.pieces:
		if pc.kind == "workshop" and pc.role == "outside":
			var size: float = maxf(pc.box.size.x, maxf(pc.box.size.y, pc.box.size.z))
			check(size <= 0.030 + 1e-6, "%s: an outside piece of %s is %.1f mm, at most 30" % [part, pc.comp, size * 1000.0])
			listed.append("%s %.1f mm" % [pc.comp, size * 1000.0])
	for f in ws.fasteners:
		var size: float = maxf(f.box.size.x, maxf(f.box.size.y, f.box.size.z))
		check(size <= 0.030 + 1e-6, "%s: a fastener of %s is %.1f mm, at most 30" % [part, f.id, size * 1000.0])
		listed.append("%s %d x %.1f mm" % [f.id, f.items.size(), size * 1000.0])
	print("workshop: %s small outside pieces: %s" % [part, ", ".join(listed)])
	# the outside the trainee sees assembled: shared and split pieces
	var occ := PackedVector3Array()
	for pr in _all_layers(ws):
		var L: Dictionary = pr[0]
		if L.tag in ["shared", "split"]:
			var arr := (L.mesh as ArrayMesh).surface_get_arrays(0)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for i in (arr[Mesh.ARRAY_INDEX] as PackedInt32Array):
				occ.append(v[i] + pr[1])
	for pr in _all_layers(ws):
		var L: Dictionary = pr[0]
		var k: String = pr[2]
		var off: Vector3 = pr[1]
		if L.tag != "hidden":
			continue
		var arr := (L.mesh as ArrayMesh).surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		# each triangle's centre (a corner can lie on the outside it closes against: a ring's outer edge), moved a
		# little inwards and off any axis; rays turned a little off the axes, never exactly along an outside edge
		var turn := Basis(Vector3(0.3, 0.7, 0.2).normalized(), 0.13)
		var ntri := idx.size() / 3
		var step := maxi(1, ntri / 400)   # every triangle of a small part; a big kind's sampled
		var seen := 0
		for t in range(0, ntri, step):
			var a := idx[t * 3]
			var b := idx[t * 3 + 1]
			var c := idx[t * 3 + 2]
			var centre := (v[a] + v[b] + v[c]) / 3.0 + off
			var n := (nm[a] + nm[b] + nm[c]).normalized()
			var from: Vector3 = centre - n * 0.0005 + Vector3(1.7e-5, -1.1e-5, 0.6e-5)
			for d in DIRS:
				if not _hits(occ, from, (turn * d).normalized()):
					seen += 1
					break
		check(seen == 0, "%s: %s: %d triangles of a hidden piece are seen from outside" % [part, k, seen])

## Whether the ray hits any of the triangles. In millimetres: Godot's test takes a ray as parallel to a triangle when
## the triangle's edges and the ray's slant give less than 1e-5 (CMP_EPSILON) in metres, and a ray turned a few degrees
## off a narrow ring's plane (a cover's face round its window, 15 mm wide) went through it as if it were not there.
func _hits(tris: PackedVector3Array, from: Vector3, dir: Vector3) -> bool:
	var f := from * 1000.0
	for t in range(0, tris.size(), 3):
		if Geometry3D.ray_intersects_triangle(f, dir, tris[t] * 1000.0, tris[t + 1] * 1000.0, tris[t + 2] * 1000.0) != null:
			return true
	return false

## Every non-thin component's triangles form closed shells: each edge (by position, to 0.01 mm) used an even number
## of times.
func _closed(part: String, ws: Dictionary) -> void:
	var by := {}
	for pr in _all_layers(ws):
		var L: Dictionary = pr[0]
		if not by.has(L.comp):
			by[L.comp] = []
		by[L.comp].append(L.mesh)
	for c in ws.components:
		if c.thin or not by.has(c.id):
			continue
		var edges := {}
		for mesh in by[c.id]:
			var arr := (mesh as ArrayMesh).surface_get_arrays(0)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			for t in range(0, idx.size(), 3):
				for j in 3:
					var a := _q(v[idx[t + j]])
					var b := _q(v[idx[t + (j + 1) % 3]])
					if a == b:
						continue
					var key := a + "/" + b if a < b else b + "/" + a
					edges[key] = edges.get(key, 0) + 1
		var open := 0
		for e in edges:
			if edges[e] % 2 != 0:
				open += 1
		check(open == 0, "%s: %s is not closed (%d open edges): close it with Workshop faces or mark it thin (§7.2)" % [part, c.id, open])

func _q(p: Vector3) -> String:
	return "%d,%d,%d" % [roundi(p.x * 100000.0), roundi(p.y * 100000.0), roundi(p.z * 100000.0)]

## The built scene loads as the tree, with its words.
func _built(part: String, data: Dictionary) -> void:
	var path := "res://built/workshop/%s.scn" % part
	check(ResourceLoader.exists(path), "%s: the build made %s" % [part, path])
	if not ResourceLoader.exists(path):
		return
	_scene_ok(part, load(path), data)

func _scene_ok(part: String, ps: PackedScene, data: Dictionary) -> void:
	check(ps != null, "%s: the Workshop scene loads" % part)
	if ps == null:
		return
	var root: Node3D = ps.instantiate()
	check(root.name == part, "%s: the root is named by the part" % part)
	var words: Dictionary = root.get_meta("workshop", {})
	check(words.get("part", "") == part, "%s: the scene carries its words" % part)
	for id in data.components:
		var n := root.find_child(id, true, false)
		check(n != null and n.get_meta("id", "") == id, "%s: the component %s is a node" % [part, id])
		if n == null:
			continue
		check(words.components.get(id, {}).get("name", "") == data.components[id].name, "%s: %s's name is in the scene" % [part, id])
		var ex: Array = n.get_meta("explode", [])
		check(ex.size() == 2 and ex[0] is Vector3 and absf((ex[0] as Vector3).length() - 1.0) < 1e-4, "%s: %s has its explode direction" % [part, id])
		var meshes := n.get_children().filter(func(c): return c is MeshInstance3D)
		for mi in meshes:
			check(mi.has_meta("mat") and mi.mesh != null, "%s: %s's meshes keep their material names" % [part, id])
	for g in data.get("fasteners", {}):
		var n := root.find_child(g, true, false)
		check(n != null and n.get_meta("items", []).size() > 0, "%s: the fastener group %s is a node with its items" % [part, g])
		if n != null:
			check(n.get_children().any(func(c): return c is MultiMeshInstance3D), "%s: %s is drawn as a MultiMesh" % [part, g])
	root.free()

## The data-only fixture kind: registered, built and loaded like the app's kinds; register refuses the kit's own.
func _fixture() -> void:
	var script: Script = load(FIXTURE)
	check(not Kit.has_part("test_gadget"), "the fixture kind is no kit part before it is registered")
	check(not Kit.register("pressure_transmitter", script, 100), "Kit.register never replaces a kit part")
	check(Kit.register("test_gadget", script, 2000), "Kit.register adds the fixture kind")
	check(Kit.has_part("test_gadget") and Kit.budget_of("test_gadget") == 2000, "the registered kind is a part with its budget")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE_DATA))
	var plant := Kit.make("test_gadget", {}, {})
	check(plant.get("tris", 0) > 0 and plant.tris <= Kit.budget_of("test_gadget"), "the fixture kind makes its plant meshes within its budget")
	_kind("test_gadget", data, {})
	var r := WB.scene("test_gadget", data, {})
	check(r.errors.is_empty() and r.scene != null, "the fixture kind's Workshop scene is built: %s" % str(r.errors))
	if r.scene != null:
		var path := "user://workshop_fixture.scn"
		check(ResourceSaver.save(r.scene, path, ResourceSaver.FLAG_COMPRESS) == OK, "the fixture's scene saves")
		_scene_ok("test_gadget", ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE), data)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# a data file that names a component the generator doesn't make is refused, and one it doesn't name
	var bad := data.duplicate(true)
	bad.components["ghost"] = bad.components.base.duplicate()
	bad.components.erase("core")
	var errs := WB.join(Kit.make("test_gadget", {}, {}, 1.0, true), bad)
	check(errs.any(func(e): return e.contains("ghost")) and errs.any(func(e): return e.contains("core")),
		"the join refuses a component on one side only: %s" % str(errs))
	# the tree's order in the assembly: a child is never placed before its parent
	var swapped := data.duplicate(true)
	var steps: Array = swapped.assembly
	var core_step = steps[1]
	steps.remove_at(1)
	steps.insert(0, core_step)
	var oerrs := WB.join(Kit.make("test_gadget", {}, {}, 1.0, true), swapped)
	check(oerrs.any(func(e): return e.contains("before base")), "the join refuses a part placed before its parent: %s" % str(oerrs))
	Kit.unregister("test_gadget")
	check(not Kit.has_part("test_gadget"), "the fixture kind is gone after unregister")

## A generator that declares no components: one component `body`, everything in it.
func _body() -> void:
	var ws := Kit.make("pressure_gauge", Kit.params_of("pressure_gauge", {}), {}, 1.0, true)
	check(ws.components.size() == 1 and ws.components[0].id == "body", "a part without a tree is one component body")
	var all_body := true
	for k in ws.layers:
		all_body = all_body and ws.layers[k].comp == "body"
	check(all_body and ws.problems.is_empty(), "every piece of such a part is in body")

## No part id of kit.json in the Workshop's code (WORKSHOP.md §9).
func _no_part_ids() -> void:
	var dir := "res://workshop"
	if not DirAccess.dir_exists_absolute(dir):
		return
	var ids: Array = Kit.kit_json().parts.keys()
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".gd"):
			continue
		var text := FileAccess.get_file_as_string(dir.path_join(f))
		for id in ids:
			var rx := RegEx.create_from_string("[\"']%s[\"']" % id)   # as a string: the code names no kind
			check(rx.search(text) == null, "workshop/%s names the part %s" % [f, id])

## A generator's misuse of the tags is reported in both modes, and the join refuses it and an unknown fastener kind.
func _misuse() -> void:
	var script: Script = load("res://tests/fixtures/workshop_misuse.gd")
	Kit.register("test_misuse", script, 1000)
	var before: int = Kit.problems.size()
	Kit.make("test_misuse", {}, {})
	check(Kit.problems.size() > before and str(Kit.problems).contains("test_misuse"), "plant mode reports a piece drawn after a Workshop block without use()")
	var ws := Kit.make("test_misuse", {}, {}, 1.0, true)
	check(not ws.problems.is_empty(), "Workshop mode reports it too")
	var data := {"components": {"base": {}}, "fasteners": {"rivets": {"joins": ["base", "base"]}}}
	var errs := WB.join(ws, data)
	check(errs.any(func(e): return e.contains("the generator")), "the join refuses the generator's misuse: %s" % str(errs))
	check(errs.any(func(e): return e.contains("rivet") and e.contains("kind")), "the join refuses an unknown fastener kind: %s" % str(errs))
	Kit.problems = Kit.problems.filter(func(x): return not String(x).begins_with("test_misuse"))
	Kit.unregister("test_misuse")

## Every only() block is recorded under the component it was drawn in (a block running on into the next component
## starts a piece of its own).
func _pieces_owned() -> void:
	var ws := Kit.make("pressure_transmitter", Kit.params_of("pressure_transmitter", {}), {}, 1.0, true)
	var comps := {}
	for pc in ws.pieces:
		if pc.tris > 0:
			comps[pc.comp] = true
	for id in ["isolator", "sensor_cell", "electronics", "display", "terminal_block"]:
		check(comps.has(id), "a Workshop piece is recorded under %s (%s)" % [id, str(comps.keys())])

