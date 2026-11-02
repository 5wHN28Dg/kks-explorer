## The plant's kit output, frozen (WORKSHOP.md §4.2, milestone K1a): a digest of everything `Kit.make()` gives the
## plant (every layer's key, material, class, size, arrays and LOD triangle counts, the moving pieces, plates, solids
## and axis) for every part of the kit, with its defaults, the parameter sets the content uses and the limits of its
## parameters, and the instruments standing every way. tests/test_kit_frozen.gd compares the digests with the ones
## recorded in tests/fixtures/kit_plant.json; a difference means the plant's geometry changed.
##
## Run it (after `build.sh` or `godot --import`) to record the digests again, only when a change to the plant's shape is
## meant (then bake the lightmap again and run the plant's Note 9 walk again: WORKSHOP.md §4.2):
##   godot --headless --path apps/plant3d --script res://tests/kit_frozen.gd
extends SceneTree

const Kit = preload("res://kit/kit.gd")
const OUT := "res://tests/fixtures/kit_plant.json"
const FORMAT := "walkdown-plant-kit-frozen"

func _init() -> void:
	var cases := cases_now()
	var rows: Array = []
	for c in cases:
		rows.append({"part": c.part, "params": c.params, "ctx": c.ctx, "sha256": digest(c.part, c.params, c.ctx)})
	var lines := PackedStringArray()   # one case a line: a change shows as the lines of the parts it changed
	for r in rows:
		lines.append(JSON.stringify(r, "", true, true))   # full precision: the cases read back exactly
	var f := FileAccess.open(ProjectSettings.globalize_path(OUT), FileAccess.WRITE)
	f.store_string('{"format": "%s", "cases": [\n%s\n]}\n' % [FORMAT, ",\n".join(lines)])
	f.close()
	print("kit_frozen: %d cases of %d parts -> %s" % [rows.size(), parts().size(), OUT])
	quit(0)

## Every part the kit makes (the structures of kit.json are the builder's own).
static func parts() -> Array:
	var out: Array = []
	for part in Kit.MAKERS:
		out.append(part)
	out.sort()
	return out

## The cases: {part, params, ctx} (ctx as JSON: vectors as arrays).
static func cases_now() -> Array:
	var kit := Kit.kit_json()
	var used := _used()
	var out: Array = []
	var seen := {}
	for part in parts():
		var spec: Dictionary = kit.parts.get(part, {"params": {}})
		var sets: Array = []
		var d := Kit.params_of(part, {})
		if _complete(spec, d):
			sets.append(d)
		for p in used.get(part, []):
			var q := Kit.params_of(part, p)
			if _complete(spec, q):
				sets.append(q)
		sets.append_array(_limits(part, spec))
		var ctxs: Array = [_ctx(part)]
		if spec.get("group", "") == "instruments":
			ctxs.append_array([{"out": [1, 0, 0]}, {"out": [0, -1, 0]}, {"out": [0.6, 0, 0.8]}, {"out": [0, 0, 1], "floor_dz": -1.2}])
		for p in sets:
			for c in ctxs:
				var key := "%s|%s|%s" % [part, JSON.stringify(p, "", true), JSON.stringify(c, "", true)]
				if seen.has(key):
					continue
				seen[key] = true
				out.append({"part": part, "params": p, "ctx": c})
	return out

## The context of a case as Kit.make takes it (arrays of three numbers to vectors).
static func ctx_of(c: Dictionary) -> Dictionary:
	var out := {}
	for k in c:
		var v = c[k]
		out[k] = Vector3(v[0], v[1], v[2]) if v is Array and v.size() == 3 and not (v[0] is Array) else v
	return out

## The digest of everything the plant takes from one Kit.make() (plant mode, the default).
static func digest(part: String, params: Dictionary, ctx: Dictionary) -> String:
	Kit.clear_cache()   # never a result made by another case
	var res := Kit.make(part, params, ctx_of(ctx))
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	if res.is_empty():
		h.update("empty".to_utf8_buffer())
		return h.finish().hex_encode()
	_layers(h, res.layers)
	for mv in res.moving:
		h.update(var_to_bytes([mv.name, mv.pivot, mv.axis, mv.kind, mv.travel]))
		_layers(h, mv.layers)
	h.update(var_to_bytes(res.plates))
	h.update(var_to_bytes(res.solids))
	h.update(var_to_bytes(res.axis))
	h.update(var_to_bytes(res.tris))
	h.update(var_to_bytes(res.keys()))
	return h.finish().hex_encode()

static func _layers(h: HashingContext, layers: Dictionary) -> void:
	for k in layers:   # in their order: the builder's cells follow it
		var L: Dictionary = layers[k]
		h.update(var_to_bytes([k, L.mat, L.cls, L.size, L.tris, L.keys()]))
		var mesh: ArrayMesh = L.mesh
		h.update(var_to_bytes([mesh.resource_name, mesh.get_surface_count()]))
		var arr: Array = mesh.surface_get_arrays(0)
		for i in arr.size():
			h.update(var_to_bytes(arr[i]))

static func _used() -> Dictionary:
	var out := {}
	var dir := ProjectSettings.globalize_path("res://").path_join("../../data/plant3d/areas").simplify_path()
	var files := Array(DirAccess.get_files_at(dir))
	files.sort()
	for f in files:
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
		items.append_array(a.get("structures", []))   # the site's parts placed as structures (planting, carpets…)
		for e in items:
			if not e is Dictionary or not e.has("part"):
				continue
			if not out.has(e.part):
				out[e.part] = []
			var p: Dictionary = e.get("params", {})
			if not out[e.part].has(p):
				out[e.part].append(p)
	return out

## As tests/test_kit.gd: each number parameter at its min and its max, every enum value, every flag, every number at
## its max at once, a long route for parts along a path.
static func _limits(part: String, spec: Dictionary) -> Array:
	var out: Array = []
	var params: Dictionary = spec.get("params", {})
	var all_max := {}
	for k in params:
		if params[k].type in ["num", "int"]:
			all_max[k] = params[k].max
	var pm := Kit.params_of(part, all_max)
	if not all_max.is_empty() and _complete(spec, pm):
		out.append(pm)
		for k in params:
			var ps: Dictionary = params[k]
			var vals: Array = ps.values if ps.type == "enum" else ([true, false] if ps.type == "bool" else [])
			for v in vals:
				var q := pm.duplicate()
				q[k] = v
				out.append(q)
	for k in params:
		if params[k].type == "path":
			var q := Kit.params_of(part, {k: [[0, 0, 5], [100, 0, 5], [100, 100, 5], [200, 100, 8]]})
			if _complete(spec, q):
				out.append(q)
	for k in params:
		var ps: Dictionary = params[k]
		match ps.type:
			"num", "int":
				for v in [ps.min, ps.max]:
					var p := Kit.params_of(part, {k: v})
					if _complete(spec, p):
						out.append(p)
			"enum":
				for v in ps.values:
					var p := Kit.params_of(part, {k: v})
					if _complete(spec, p):
						out.append(p)
	return out

static func _complete(spec: Dictionary, p: Dictionary) -> bool:
	var params: Dictionary = spec.get("params", {})
	for k in params:
		if p.has(k):
			continue
		var ps: Dictionary = params[k]
		match ps.type:
			"pair": p[k] = [0, 100]
			"polygon": p[k] = [[0, 0], [4, 0], [4, 3], [0, 3]]
			"path": p[k] = [[0, 0, 5], [20, 0, 5], [20, 10, 5]]
			"enum": p[k] = ps.values[0]
			"records": p[k] = []
			_: return false
	return true

static func _ctx(part: String) -> Dictionary:
	if part in ["valve_safety", "flow_element"]:
		return {"pipe_od": 0.3}
	return {}
