## The parts kit (docs/PLANT3D.md §9, §10; kit/README.md): every part kit.json declares is made by the kit; every part
## makes valid meshes at every LOD (indices in range, finite vertices, unit normals, each LOD no larger than the one
## before) within its triangle budget (kit/kit.gd BUDGET) with its defaults, with every parameter set the first train
## uses and at the limits of its size parameters; every anim channel kit.json names is a moving node with a unit
## axis; every plate mounting point kit.json names exists.
extends RefCounted

const Kit = preload("res://kit/kit.gd")

var problems: Array = []
var report := PackedStringArray()

func check(ok: bool, what: String) -> void:
	if not ok:
		problems.append(what)

func run(_tree: SceneTree) -> Array:
	var kit := Kit.kit_json()
	check(not kit.is_empty(), "kit.json is read")
	var used := _first_train()
	for part in kit.parts:
		var spec: Dictionary = kit.parts[part]
		if spec.group == "structures":
			continue
		check(Kit.has_part(part), "the kit makes %s (kit.json declares it)" % part)
		if not Kit.has_part(part):
			continue
		var d := Kit.params_of(part, {})
		var sets: Array = [d] if _complete(part, spec, d) else []
		for p in used.get(part, []):
			sets.append(Kit.params_of(part, p))
		sets.append_array(_limits(part, spec))
		var worst := 0
		for p in sets:
			var res := Kit.make(part, p, _ctx(part))
			check(not res.is_empty(), "%s %s makes something" % [part, JSON.stringify(p)])
			if res.is_empty():
				continue
			worst = maxi(worst, res.tris)
			check(res.tris <= Kit.BUDGET.get(part, 0), "%s: %d triangles at full detail, budget %d (%s)" % [part, res.tris, Kit.BUDGET.get(part, 0), JSON.stringify(p)])
			for k in res.layers:
				_valid(part, k, res.layers[k])
			for mv in res.moving:
				check(absf(mv.axis.length() - 1.0) < 1e-4, "%s: %s's axis is a unit vector" % [part, mv.name])
				for k in mv.layers:
					_valid(part + "/" + mv.name, k, mv.layers[k])
			var names: Array = res.moving.map(func(mv): return mv.name)
			for a in spec.get("anim", []):
				check(a in names, "%s: the anim channel %s is a moving node (has %s)" % [part, a, str(names)])
			for pl in spec.get("plates", []):
				check(res.plates.has(pl), "%s: the plate point %s exists (has %s)" % [part, pl, str(res.plates.keys())])
		report.append("%s %d" % [part, worst])
	print("kit: worst triangles per part: ", ", ".join(report))
	return problems

## Every mesh at every LOD: indices in range and in threes, finite vertices, unit normals, LODs shrinking.
func _valid(part: String, key: String, L: Dictionary) -> void:
	var mesh: ArrayMesh = L.mesh
	var arr := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	check(idx.size() > 0 and idx.size() % 3 == 0, "%s %s: indexed triangles" % [part, key])
	var bad := 0
	for i in idx:
		if i < 0 or i >= v.size():
			bad += 1
	check(bad == 0, "%s %s: %d indices out of range" % [part, key, bad])
	var nan := 0
	for p in v:
		if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
			nan += 1
	check(nan == 0, "%s %s: %d vertices not finite" % [part, key, nan])
	var nb := 0
	for q in n:
		if absf(q.length() - 1.0) > 0.01:
			nb += 1
	check(nb == 0, "%s %s: %d normals not of unit length" % [part, key, nb])
	var t: Array = L.tris
	for i in range(1, t.size()):
		check(t[i] <= t[i - 1], "%s %s: LOD %d (%d triangles) no larger than LOD %d (%d)" % [part, key, i, t[i], i - 1, t[i - 1]])
	check(L.cls in ["form", "identify", "detail"], "%s %s: a visibility class" % [part, key])
	if L.cls == "detail":
		check(L.size > 0.0, "%s %s: a detail piece has its size" % [part, key])

## The parameter sets the first train uses, per part.
func _first_train() -> Dictionary:
	var out := {}
	var dir := ProjectSettings.globalize_path("res://").path_join("../../data/plant3d/areas").simplify_path()
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".json"):
			continue
		var a = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(f)))
		if not a is Dictionary:
			continue
		var items: Array = []
		for e in a.get("equipment", []):
			items.append(e)
			items.append_array(e.get("parts", []))
		for p in a.get("pipes", []):
			items.append_array(p.get("valves", []))
			items.append_array(p.get("parts", []))
		for e in items:
			if not out.has(e.part):
				out[e.part] = []
			out[e.part].append(e.get("params", {}))
	return out

## Each number parameter at its min and its max (the others at their defaults), and every enum value.
func _limits(part: String, spec: Dictionary) -> Array:
	var out: Array = []
	for k in spec.params:
		var ps: Dictionary = spec.params[k]
		match ps.type:
			"num", "int":
				for v in [ps.min, ps.max]:
					var p := Kit.params_of(part, {k: v})
					if _complete(part, spec, p):
						out.append(p)
			"enum":
				for v in ps.values:
					var p := Kit.params_of(part, {k: v})
					if _complete(part, spec, p):
						out.append(p)
	return out

## A parameter set with every required parameter (those without a default get a typical value).
func _complete(part: String, spec: Dictionary, p: Dictionary) -> bool:
	for k in spec.params:
		if p.has(k):
			continue
		var ps: Dictionary = spec.params[k]
		match ps.type:
			"pair": p[k] = [0, 100]
			"path": p[k] = [[0, 0, 5], [20, 0, 5], [20, 10, 5]]
			"enum": p[k] = ps.values[0]
			"records": p[k] = []
			_: return false
	return true

func _ctx(part: String) -> Dictionary:
	if part in ["valve_safety", "flow_element"]:
		return {"pipe_od": 0.3}
	return {}
