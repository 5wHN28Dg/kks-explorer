## The parts kit (docs/PLANT3D.md §9, §10; kit/README.md): every part kit.json declares is made by the kit; every part
## makes valid meshes at every LOD (indices in range, finite vertices, unit normals, each LOD no larger than the one
## before) within its triangle budget (kit/kit.gd BUDGET) with its defaults, with every parameter set the first train
## uses and at the limits of its size parameters; every anim channel kit.json names is a moving node with a unit
## axis; every plate mounting point kit.json names exists.
extends RefCounted

const Kit = preload("res://kit/kit.gd")
const KitPlace = preload("res://builder/kit_place.gd")

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
	_site_budgets()
	_states()
	_frames()
	_solids(kit)
	_breaker()
	return problems

## The site's parts (the `structures` group, skipped above: their params are routes and outlines) within their
## budgets at their largest: photo pass 3's new parts and kinds.
func _site_budgets() -> void:
	var sets := [["hydrant", {}], ["bollard", {"height": 1.6}], ["skip_bin", {}], ["mast", {"height": 60}],
		["mast", {"height": 10}], ["ac_unit", {}], ["table", {"kind": "wood"}], ["sofa", {"seats": 4, "cover": "leather"}],
		["vehicle", {"kind": "ambulance"}], ["canopy", {"kind": "sail", "length": 100, "width": 20, "height": 8}],
		["canopy", {"kind": "sail"}], ["planting", {"species": "dracaena", "height": 20}]]
	for ps in sets:
		var part: String = ps[0]
		var p := Kit.params_of(part, ps[1])
		var res := Kit.make(part, p, {})
		check(res.tris > 0 and res.tris <= Kit.BUDGET.get(part, 0), "%s: %d triangles at full detail, budget %d (%s)" % [part, res.tris, Kit.BUDGET.get(part, 0), JSON.stringify(ps[1])])
		check(not res.solids.is_empty(), "%s is solid (%s)" % [part, JSON.stringify(ps[1])])

## Parts a trainee could walk into are solid (the GT's exhaust duct, a basin's walls, trays, every machine).
func _solids(kit: Dictionary) -> void:
	for part in kit.parts:
		var g: String = kit.parts[part].group
		if not Kit.has_part(part) or g in ["structures", "instruments", "cues", "pipes"] or part == "hrsg_module":
			continue
		var p := Kit.params_of(part, {})
		_complete(part, kit.parts[part], p)
		var res := Kit.make(part, p, {"pipe_od": 0.3})
		check(not res.solids.is_empty(), "%s is solid (it has collision shapes)" % part)

## The breaker's position flag is seen: a ray from its face out through the window meets nothing static.
func _breaker() -> void:
	for kind in ["gcb", "mv"]:
		var res := Kit.make("breaker", Kit.params_of("breaker", {"kind": kind}), {})
		var out := Vector3(1, 0, 0) if kind == "gcb" else Vector3(0, 0, -1)   # in Godot's axes
		for mv in res.moving:
			if mv.name != "contacts":
				continue
			var face := -INF
			var centre := Vector3.ZERO
			for k in mv.layers:
				var bb: AABB = mv.layers[k].mesh.get_aabb()
				bb.position += mv.pivot
				var f: float = bb.end.dot(out) if out.x > 0.0 else -bb.position.z
				if f > face:
					face = f
					centre = bb.get_center()
			var from := centre - out * centre.dot(out) + out * (face + 0.001)
			var hit := false
			for k in res.layers:
				var arr: Array = res.layers[k].mesh.surface_get_arrays(0)
				var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
				for t in range(0, idx.size(), 3):
					if Geometry3D.ray_intersects_triangle(from, out, v[idx[t]], v[idx[t + 1]], v[idx[t + 2]]) != null:
						hit = true
			check(not hit, "the %s breaker's position flag is seen through its window (nothing static in front of it)" % kind)

## As built (value 0) a quarter-turn valve is closed: its lever or indicator lies across the pipe (x), not along it.
func _states() -> void:
	for part in ["valve_butterfly", "valve_ball"]:
		for act in ["manual", "gear", "electric", "pneumatic"]:
			for dn in [100, 600]:
				var res := Kit.make(part, Kit.params_of(part, {"dn": dn, "actuator": act}), {})
				for mv in res.moving:
					if mv.name != "disc":
						continue
					for k in mv.layers:
						if mv.layers[k].mat != "paint":
							continue
						# the lever (red) or the indicator's arrow (black), not the round yellow dial under it
						var arr: Array = mv.layers[k].mesh.surface_get_arrays(0)
						var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
						var cs: PackedColorArray = arr[Mesh.ARRAY_COLOR]
						var bb := AABB()
						var first := true
						for i in vs.size():
							if cs[i].g < 0.5:
								bb = AABB(vs[i], Vector3.ZERO) if first else bb.expand(vs[i])
								first = false
						check(not first and bb.size.x > bb.size.z, "%s DN %d %s: at 0 (closed) the indicator lies across the pipe (x %.2f, along %.2f)" % [part, dn, act, bb.size.x, bb.size.z])

## A part on a sloped pipe stands square to it (an orthonormal frame, its forward along the pipe).
func _frames() -> void:
	var kp = KitPlace.new(null)
	for fwd in [Vector3(1, 0, 1).normalized(), Vector3(0, 1, -0.3).normalized(), Vector3(0, 1, 0)]:
		var t: Transform3D = kp.xform({"pos": Vector3.ZERO, "yaw": 0.0, "fwd": fwd, "up": Vector3(0, 0, 1)})
		var bs := t.basis
		check(absf(bs.x.dot(bs.y)) < 1e-5 and absf(bs.y.dot(bs.z)) < 1e-5 and absf(bs.x.dot(bs.z)) < 1e-5 and absf(bs.determinant() - 1.0) < 1e-4,
			"the frame on a pipe along %s is square" % str(fwd))
		check((-bs.z).distance_to(Vector3(fwd.x, fwd.z, -fwd.y)) < 1e-4, "its forward runs along the pipe %s" % str(fwd))

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
	if L.cls == "identify":
		check(t.size() == 1, "%s %s: identify pieces get no LODs (§10: never removed)" % [part, key])
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

## Each number parameter at its min and its max (the others at their defaults), every enum value, and every number
## parameter at its max at once.
func _limits(part: String, spec: Dictionary) -> Array:
	var out: Array = []
	var all_max := {}
	for k in spec.params:
		if spec.params[k].type in ["num", "int"]:
			all_max[k] = spec.params[k].max
	var pm := Kit.params_of(part, all_max)
	if not all_max.is_empty() and _complete(part, spec, pm):
		out.append(pm)
		# and with every enum value and both values of every flag
		for k in spec.params:
			var ps: Dictionary = spec.params[k]
			var vals: Array = ps.values if ps.type == "enum" else ([true, false] if ps.type == "bool" else [])
			for v in vals:
				var q := pm.duplicate()
				q[k] = v
				out.append(q)
	# a long route for parts along a path
	for k in spec.params:
		if spec.params[k].type == "path":
			var q := Kit.params_of(part, {k: [[0, 0, 5], [100, 0, 5], [100, 100, 5], [200, 100, 8]]})
			if _complete(part, spec, q):
				out.append(q)
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
