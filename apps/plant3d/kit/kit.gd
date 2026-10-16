## The parts kit (docs/PLANT3D.md §9, decision 0054 §1): every part of data/plant3d/kit.json made by code from its
## parameters. A part is made once per distinct parameter set and instanced wherever it stands (the builder groups
## the instances per 12 m cell: decision 0041).
##
## make(part, params, ctx) gives:
##   layers   {key: {mat, cls, size, mesh: ArrayMesh with LODs, tris: [per LOD]}}: the static pieces, one mesh per
##            (material, visibility class, size bucket), in the part's Godot frame (origin at the part's origin)
##   moving   [{name, pivot, axis, kind, travel, layers}]: the pieces a value moves (§7.7 `anim`), each its own node:
##            pivot and axis in the part's Godot frame; the meshes are relative to the pivot (kit/README.md)
##   plates   {name: {at, normal}} tag plate mounting points (part's Godot frame), `solids` collision boxes and
##            cylinders, `axis` the part's centre line (children's instruments face away from it)
## ctx carries what the builder knows about the surroundings (README "Context"): the DN table, the nozzles pipes end
## on, a shaft line shared with neighbours, the height of what stands above or below.
extends RefCounted

const MB = preload("res://kit/mesh.gd")
const P_MACH = preload("res://kit/parts_machines.gd")
const P_ROT = preload("res://kit/parts_rotating.gd")
const P_HX = preload("res://kit/parts_heat.gd")
const P_VES = preload("res://kit/parts_vessels.gd")
const P_VAL = preload("res://kit/parts_valves.gd")
const P_INS = preload("res://kit/parts_instruments.gd")
const P_EL = preload("res://kit/parts_electrical.gd")
const P_PIPE = preload("res://kit/parts_pipes.gd")

## The parts each generator script makes (structure parts are made by the builder itself: §5).
const MAKERS := {
	"gas_turbine": "MACH", "generator": "MACH", "steam_turbine": "MACH", "sfc": "MACH", "turning_gear": "MACH",
	"filter_house": "MACH",
	"hrsg": "VES", "hrsg_module": "VES", "drum": "VES", "stack": "VES", "duct": "VES", "silencer": "VES",
	"tank_vertical": "VES", "vessel_horizontal": "VES", "package_boiler": "VES", "basin": "VES",
	"pump_horizontal": "ROT", "pump_vertical": "ROT", "fan_axial": "ROT", "compressor_skid": "ROT",
	"vacuum_pump_skid": "ROT", "motor": "ROT",
	"condenser": "HX", "shell_tube_hx": "HX", "plate_hx": "HX", "cooling_tower": "HX",
	"valve_gate": "VAL", "valve_globe": "VAL", "valve_butterfly": "VAL", "valve_ball": "VAL", "valve_check": "VAL",
	"valve_control": "VAL", "valve_safety": "VAL", "damper": "VAL",
	"pressure_gauge": "INS", "pressure_transmitter": "INS", "temperature_element": "INS", "temperature_gauge": "INS",
	"level_glass": "INS", "level_transmitter": "INS", "flow_element": "INS", "position_switch": "INS",
	"vibration_probe": "INS", "speed_probe": "INS", "flame_detector": "INS", "local_panel": "INS",
	"push_button_station": "INS",
	"transformer": "EL", "breaker": "EL", "switchgear_row": "EL", "cabinet": "EL", "junction_box": "EL",
	"cable_tray": "EL",
	"elbow": "PIPE", "tee": "PIPE", "reducer": "PIPE", "flange": "PIPE", "pipe_support": "PIPE",
	"tag_plate": "INS", "sign": "INS", "lamp": "INS", "beacon": "INS", "horn": "INS", "emergency_stop": "INS",
	"safety_shower": "INS",
}

## Triangle budgets per part at full detail (LOD 0), the most any one instance may take with any parameters the kit
## allows (kit/README.md "Budgets"; tests/test_kit.gd checks every part with its defaults, the first train's
## parameters and the limits of its size parameters).
const BUDGET := {
	"gas_turbine": 30000, "generator": 12000, "steam_turbine": 30000, "sfc": 4000, "turning_gear": 4000,
	"filter_house": 8000, "hrsg": 20000, "hrsg_module": 1500, "drum": 8000, "stack": 18000, "duct": 4000,
	"silencer": 3000, "tank_vertical": 8000, "vessel_horizontal": 6000, "package_boiler": 8000, "basin": 1000,
	"pump_horizontal": 9000, "pump_vertical": 9000, "fan_axial": 6000, "compressor_skid": 8000,
	"vacuum_pump_skid": 8000, "motor": 5000, "condenser": 12000, "shell_tube_hx": 6000, "plate_hx": 4000,
	"cooling_tower": 40000, "valve_gate": 5000, "valve_globe": 5000, "valve_butterfly": 4000, "valve_ball": 4000,
	"valve_check": 4700, "valve_control": 5800, "valve_safety": 4600, "damper": 4000, "pressure_gauge": 800,
	"pressure_transmitter": 1200, "temperature_element": 600, "temperature_gauge": 800, "level_glass": 1500,
	"level_transmitter": 1500, "flow_element": 2500, "position_switch": 400, "vibration_probe": 400,
	"speed_probe": 400, "flame_detector": 500, "local_panel": 1500, "push_button_station": 800,
	"transformer": 25000, "breaker": 6000, "switchgear_row": 8000, "cabinet": 1500, "junction_box": 400,
	"cable_tray": 2000, "elbow": 3000, "tee": 2000, "reducer": 1000, "flange": 1500, "pipe_support": 400,
	"tag_plate": 60, "sign": 60, "lamp": 300, "beacon": 400, "horn": 300, "emergency_stop": 400,
	"safety_shower": 1500,
}

class Gen:
	var p: Dictionary
	var ctx: Dictionary
	var m                     # the static pieces' mesh builder
	var moving := {}          # name -> {pivot, axis, kind, travel, mb}
	var plates := {}
	var solids: Array = []
	var axis_line: Array = [Vector3.ZERO, Vector3(0, 0, 1)]
	var dn_table: Array = []

	func _init(params: Dictionary, context: Dictionary, MBs) -> void:
		p = params
		ctx = context
		m = MBs.new()
		dn_table = ctx.get("dn_od_mm", [])
		_mb_script = MBs

	var _mb_script

	func num(k: String, d := 0.0) -> float:
		return float(p.get(k, d))

	## The outside diameter in metres of a nominal size (the kit's DN table, the next smaller size for a DN between).
	func od(dn: float) -> float:
		var best := 0.0
		for row in dn_table:
			if float(row[0]) == dn:
				return float(row[1]) / 1000.0
			if float(row[0]) < dn:
				best = float(row[1])
		return (best if best > 0.0 else dn * 1.1) / 1000.0

	## A moving piece (§7.7 anim channel): its own mesh builder, in the part frame; pivot and axis in the part frame.
	##   kind "rotate": the node turns about axis through pivot (travel: radians for 0 -> 1; 0 = turns freely)
	##   kind "translate": the node moves along axis (travel: metres for 0 -> 1)
	##   kind "scale": the node's mesh is scaled along axis from pivot (travel 1: value 0 -> 0, 1 -> full)
	func move(name: String, pivot: Vector3, axis: Vector3, kind: String, travel: float):
		if not moving.has(name):
			moving[name] = {"pivot": pivot, "axis": axis.normalized(), "kind": kind, "travel": travel, "mb": _mb_script.new()}
		return moving[name].mb

	func plate(name: String, at: Vector3, normal: Vector3, kind := "large") -> void:
		plates[name] = {"at": at, "normal": normal.normalized(), "kind": kind}

	func solid_box(lo: Vector3, hi: Vector3) -> void:
		solids.append({"kind": "box", "lo": lo, "hi": hi})

	func solid_cyl(a: Vector3, b: Vector3, r: float) -> void:
		solids.append({"kind": "cyl", "a": a, "b": b, "r": r})

	## A nozzle's position from kit.json (numbers or [param, factor, offset]).
	func nozzle(spec: Dictionary) -> Vector3:
		var c := Vector3.ZERO
		for i in 3:
			var v = spec.at[i]
			c[i] = float(v) if not v is Array else float(p.get(v[0], 0)) * float(v[1]) + float(v[2])
		return c

	func used(nozzle_name: String) -> bool:
		return nozzle_name in ctx.get("used", [])

static var _cache := {}
static var _kit_json: Dictionary = {}

static func kit_json() -> Dictionary:
	if _kit_json.is_empty():
		var path := ProjectSettings.globalize_path("res://").path_join("../../data/plant3d/kit.json").simplify_path()
		var v = JSON.parse_string(FileAccess.get_file_as_string(path))
		_kit_json = v if v is Dictionary else {}
	return _kit_json

static func use_kit(k: Dictionary) -> void:
	_kit_json = k

static func has_part(part: String) -> bool:
	return MAKERS.has(part)

## The part's parameters with the kit's defaults filled in.
static func params_of(part: String, given) -> Dictionary:
	var out := {}
	var spec: Dictionary = kit_json().get("parts", {}).get(part, {}).get("params", {})
	for k in spec:
		if spec[k].has("default"):
			out[k] = spec[k].default
	if given is Dictionary:
		for k in given:
			out[k] = given[k]
	return out

## The nozzle spec of a part (kit.json), or {}.
static func nozzle_spec(part: String, n: String) -> Dictionary:
	return kit_json().get("parts", {}).get(part, {}).get("nozzles", {}).get(n, {})

static func _script(part: String):
	match MAKERS.get(part, ""):
		"MACH": return P_MACH
		"ROT": return P_ROT
		"HX": return P_HX
		"VES": return P_VES
		"VAL": return P_VAL
		"INS": return P_INS
		"EL": return P_EL
		"PIPE": return P_PIPE
	return null

## Makes a part (cached: the same part with the same parameters and context is made once).
static func make(part: String, params: Dictionary, ctx := {}, seg_scale := 1.0) -> Dictionary:
	var key := "%s|%s|%s|%.2f" % [part, JSON.stringify(params, "", true), JSON.stringify(_ctx_key(ctx), "", true), seg_scale]
	if _cache.has(key):
		return _cache[key]
	var c := ctx.duplicate()
	if not c.has("dn_od_mm"):
		c["dn_od_mm"] = kit_json().get("dn_od_mm", [])
	c["nozzles"] = kit_json().get("parts", {}).get(part, {}).get("nozzles", {})
	var g := Gen.new(params, c, MB)
	g.m.seg_scale = seg_scale
	var s = _script(part)
	if s == null:
		return {}
	s.call(part, part, g)
	var res := {"part": part, "layers": _meshes(g.m.finish(), Vector3.ZERO), "moving": [], "plates": {}, "solids": g.solids,
		"axis": [_gv(g.axis_line[0]), _gv(g.axis_line[1])]}
	for n in g.moving:
		var mv: Dictionary = g.moving[n]
		mv.mb.seg_scale = seg_scale
		res.moving.append({"name": n, "pivot": _gv(mv.pivot), "axis": _gv(mv.axis).normalized(), "kind": mv.kind,
			"travel": mv.travel, "layers": _meshes(mv.mb.finish(), _gv(mv.pivot))})
	for n in g.plates:
		var pl: Dictionary = g.plates[n]
		res.plates[n] = {"at": _gv(pl.at), "normal": _gv(pl.normal), "kind": pl.kind}
	res["tris"] = tris_of(res)
	_cache[key] = res
	return res

## The context keys that change a part's shape (the rest is the builder's bookkeeping).
static func _ctx_key(ctx: Dictionary) -> Dictionary:
	var k := ctx.duplicate()
	k.erase("dn_od_mm")
	k.erase("nozzles")
	return k

## A part-frame vector (x right, y forward, z up) in Godot's axes.
static func _gv(v: Vector3) -> Vector3:
	return Vector3(v.x, v.z, -v.y)

## Mesh arrays to ArrayMeshes with LODs (Godot's own simplifier, as for imported models: decision 0041), shifted by
## -origin (a moving piece's mesh is relative to its pivot).
static func _meshes(layers: Dictionary, origin: Vector3) -> Dictionary:
	var out := {}
	for k in layers:
		var L: Dictionary = layers[k]
		var arr: Array = L.arrays
		if origin != Vector3.ZERO:
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for i in v.size():
				v[i] -= origin
			arr[Mesh.ARRAY_VERTEX] = v
		var im := ImporterMesh.new()
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr)
		if L.tris >= 64:
			im.generate_lods(25.0, 60.0, [])
		var lods: Array = [L.tris]
		for i in im.get_surface_lod_count(0):
			lods.append(im.get_surface_lod_indices(0, i).size() / 3)
		var mesh := im.get_mesh()
		mesh.resource_name = k
		out[k] = {"mat": L.mat, "cls": L.cls, "size": L.size, "mesh": mesh, "tris": lods}
	return out

## Triangles at LOD 0, static and moving together.
static func tris_of(res: Dictionary) -> int:
	var n := 0
	for k in res.layers:
		n += res.layers[k].tris[0]
	for mv in res.moving:
		for k in mv.layers:
			n += mv.layers[k].tris[0]
	return n

static func clear_cache() -> void:
	_cache.clear()
