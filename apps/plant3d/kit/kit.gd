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
##
## make(part, params, ctx, seg_scale, true) is the Workshop mode (docs/plant3d/WORKSHOP.md §4.2): the same generator
## with its component tags. Its layers are keyed `comp|tag|material|class|bucket` (no LODs: one machine seen close), and
## it gives the component tree (`components`), the fastener groups, flow paths, the stand-ins the plant draws in place
## of split components, and every Workshop-only piece with its box (`pieces`). Plant mode is untouched by it.
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
const P_SITE = preload("res://kit/parts_site.gd")
const P_WAT = preload("res://kit/parts_water.gd")
const P_HOIST = preload("res://kit/parts_hoists.gd")
const P_LIFT = preload("res://kit/parts_lifts.gd")

## The parts each generator script makes (structure parts are made by the builder itself, §5, except the site's and
## the camp's: planting, vehicles, furniture, PLANT3D.md §18.6).
const MAKERS := {
	"gas_turbine": "MACH", "generator": "MACH", "steam_turbine": "MACH", "sfc": "MACH", "turning_gear": "MACH",
	"filter_house": "MACH", "monorail_hoist": "HOIST", "overhead_crane": "HOIST", "hoist_unit": "HOIST",
	"service_lift": "LIFT", "lift_gate": "LIFT", "lift_call": "LIFT", "lift_unit": "LIFT",
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
	"push_button_station": "INS", "operator_desk": "INS",
	"transformer": "EL", "breaker": "EL", "switchgear_row": "EL", "cabinet": "EL", "junction_box": "EL",
	"cable_tray": "EL",
	"elbow": "PIPE", "tee": "PIPE", "reducer": "PIPE", "flange": "PIPE", "pipe_support": "PIPE",
	"tag_plate": "INS", "sign": "INS", "lamp": "INS", "beacon": "INS", "horn": "INS", "emergency_stop": "INS",
	"safety_shower": "INS",
	"planting": "SITE", "vehicle": "SITE", "barrier": "SITE", "guard_booth": "SITE", "canopy": "SITE",
	"lamp_post": "SITE", "kerb": "SITE", "crossing": "SITE", "court": "SITE", "porch": "SITE", "room": "SITE", "bed": "SITE",
	"locker": "SITE", "desk": "SITE", "chair": "SITE", "table": "SITE", "bench": "SITE", "counter": "SITE",
	"shelf": "SITE", "washer": "SITE", "gym_rack": "SITE", "sofa": "SITE", "screen": "SITE", "carpet": "SITE",
	"sanitary": "SITE", "hydrant": "SITE", "bollard": "SITE", "skip_bin": "SITE", "mast": "SITE", "ac_unit": "SITE",
	"clarifier": "WAT", "thickener": "WAT", "filter_bank": "WAT", "cartridge_housing": "WAT", "ro_train": "WAT",
	"degasser": "WAT", "ion_exchanger": "WAT", "dosing_skid": "WAT", "metering_pump": "WAT", "chemical_tank": "WAT",
	"filter_press": "WAT", "sample_panel": "WAT", "lab_bench": "WAT", "agitator": "WAT", "bar_screen": "WAT",
	"screen_band": "WAT",
}

## Triangle budgets per part at full detail (LOD 0), the most any one instance may take with any parameters the kit
## allows (kit/README.md "Budgets"; tests/test_kit.gd checks every part with its defaults, the first train's
## parameters and the limits of its size parameters).
const BUDGET := {
	"gas_turbine": 30000, "generator": 12000, "steam_turbine": 30000, "sfc": 4000, "turning_gear": 4000,
	"filter_house": 8000, "monorail_hoist": 5000, "overhead_crane": 5000, "hoist_unit": 0, "service_lift": 6000, "lift_gate": 600, "lift_call": 200, "lift_unit": 0, "hrsg": 20000, "hrsg_module": 1500, "drum": 9000, "stack": 26000, "duct": 4000,
	"silencer": 3000, "tank_vertical": 9000, "vessel_horizontal": 6000, "package_boiler": 8000, "basin": 1000,
	"pump_horizontal": 9000, "pump_vertical": 11000, "fan_axial": 6000, "compressor_skid": 8000,
	"vacuum_pump_skid": 8000, "motor": 5000, "condenser": 12000, "shell_tube_hx": 6000, "plate_hx": 4000,
	"cooling_tower": 40000, "valve_gate": 5000, "valve_globe": 5000, "valve_butterfly": 4000, "valve_ball": 4000,
	"valve_check": 4700, "valve_control": 5800, "valve_safety": 4600, "damper": 4000, "pressure_gauge": 800,
	"pressure_transmitter": 1200, "temperature_element": 600, "temperature_gauge": 800, "level_glass": 1500,
	"level_transmitter": 1500, "flow_element": 2500, "position_switch": 400, "vibration_probe": 400,
	"speed_probe": 400, "flame_detector": 500, "local_panel": 1500, "push_button_station": 800, "operator_desk": 1500,
	"transformer": 25000, "breaker": 6000, "switchgear_row": 8000, "cabinet": 1500, "junction_box": 400,
	"cable_tray": 6000, "elbow": 3000, "tee": 2000, "reducer": 1000, "flange": 1500, "pipe_support": 400,
	"tag_plate": 60, "sign": 60, "lamp": 300, "beacon": 400, "horn": 300, "emergency_stop": 400,
	"safety_shower": 1500,
	"planting": 2500, "vehicle": 1500, "barrier": 600, "guard_booth": 500, "canopy": 4000, "lamp_post": 500,
	"kerb": 6000, "crossing": 300, "court": 8000, "porch": 1200, "room": 6000, "bed": 300, "locker": 400, "desk": 150, "chair": 300,
	"table": 400, "bench": 150, "counter": 1200, "shelf": 1600, "washer": 200, "gym_rack": 600, "sofa": 200,
	"screen": 50, "carpet": 1500, "sanitary": 300, "hydrant": 600, "bollard": 150, "skip_bin": 300, "mast": 4000,
	"ac_unit": 200,
	"clarifier": 9000, "thickener": 7000, "filter_bank": 9000, "cartridge_housing": 3000, "ro_train": 16000,
	"degasser": 7000, "ion_exchanger": 6000, "dosing_skid": 3000, "metering_pump": 2500, "chemical_tank": 6000,
	"filter_press": 6000, "sample_panel": 4000, "lab_bench": 2000, "agitator": 3500, "bar_screen": 5000,
	"screen_band": 4000,
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
	var seg_scale := 1.0
	var workshop := false     # the Workshop mode (WORKSHOP.md §4.2): comp(), only(), fasteners() and flow() count
	var components := {}      # id -> its spec in the part frame (Workshop mode)
	var fastener_groups: Array = []
	var flows := {}
	var cur_comp := "body"
	var cur_only := ["", "hidden", []]   # the current only(): kind, role, replaced_by (moving builders made later take it)

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
			var mb = _mb_script.new()
			mb.seg_scale = seg_scale
			mb.workshop = workshop
			mb.comp_id = cur_comp
			mb.set_only(cur_only[0], cur_only[1], cur_only[2])
			moving[name] = {"pivot": pivot, "axis": axis.normalized(), "kind": kind, "travel": travel, "mb": mb}
		return moving[name].mb

	## Declares a component and makes it current for the next primitives (WORKSHOP.md §4.1, §4.2). Points and
	## directions are in the frame the static builder draws in now (its `xf`), as its primitives are. spec:
	##   parent    another component's id ("" or absent: the machine's top level)
	##   pivot     the component's origin (default: its box's centre)
	##   explode   [direction, metres] (default: the builder's, from the parent's box centre)
	##   sym       [axis, n] rotational symmetry for snapping (n 0: any angle)
	##   anchors   {name: point} terminals, test points, lifting eyes
	##   anim      the moving piece (g.move's name) this component is
	##   thin      true for a sheet or a glass, not a closed solid (§7.2)
	## In plant mode it only selects the layer again (nothing changes).
	func comp(id: String, spec := {}) -> void:
		cur_comp = id
		if workshop and not components.has(id):
			var t: Transform3D = m.xf
			var c := {"parent": spec.get("parent", ""), "thin": spec.get("thin", false), "anim": spec.get("anim", "")}
			if spec.has("pivot"):
				c["pivot"] = t * (spec.pivot as Vector3)
			if spec.has("explode"):
				c["explode"] = [(t.basis * (spec.explode[0] as Vector3)).normalized(), float(spec.explode[1])]
			if spec.has("sym"):
				c["sym"] = [(t.basis * (spec.sym[0] as Vector3)).normalized(), int(spec.sym[1])]
			var an := {}
			for k in spec.get("anchors", {}):
				an[k] = t * (spec.anchors[k] as Vector3)
			c["anchors"] = an
			components[id] = c
		m.set_comp(id)
		for n in moving:
			moving[n].mb.set_comp(id)

	## What the next primitives are (WORKSHOP.md §4.2): only() shared; only("workshop") hidden insides, inner faces,
	## closing faces; only("workshop", "outside") a small outside piece the plant doesn't draw (at most 30 mm);
	## only("workshop", "split") a piece of a component that replaces a stand-in; only("plant", [components]) a merged
	## stand-in those components replace (none: a mounting the Workshop leaves out). After a "workshop" block call
	## use() again before the next shared primitive.
	func only(kind := "", arg = null) -> void:
		var role: String = arg if arg is String else "hidden"
		var by: Array = arg if arg is Array else []
		cur_only = [kind, role, by]
		m.set_only(kind, role, by)
		for n in moving:
			moving[n].mb.set_only(kind, role, by)

	## A group of identical fasteners (WORKSHOP.md §4.4): `items` their transforms (origin at the item's seat, z the
	## way it backs out) in the frame the static builder draws in now; `draw` draws one item into the mesh builder it
	## is given, in the item's own frame. A small outside piece of the Workshop: plant mode draws nothing. Its
	## component in the tree is the current one (the group backs out in the stage after that component's, as a level
	## below it: workshop/explode.gd).
	func fasteners(id: String, kind: String, items: Array, draw: Callable) -> void:
		if not workshop:
			return
		var mb = _mb_script.new()
		mb.seg_scale = seg_scale
		mb.workshop = true
		mb.comp_id = id
		mb.set_only("workshop", "outside")
		draw.call(mb)
		var xs: Array = []
		for it in items:
			xs.append(m.xf * (it as Transform3D))
		fastener_groups.append({"id": id, "kind": kind, "parent": cur_comp, "items": xs, "mb": mb})

	## A flow path (WORKSHOP.md §4.1): a polyline in the frame the static builder draws in now. Workshop mode only.
	func flow(id: String, pts: Array) -> void:
		if workshop:
			flows[id] = pts.map(func(q): return m.xf * (q as Vector3))

	func plate(name: String, at: Vector3, normal: Vector3, kind := "large") -> void:
		plates[name] = {"at": at, "normal": normal.normalized(), "kind": kind}

	func solid_box(lo: Vector3, hi: Vector3) -> void:
		solids.append({"kind": "box", "lo": lo, "hi": hi})

	## A box turned by basis bs (part frame), centre c, size s along the basis' axes.
	func solid_obox(c: Vector3, s: Vector3, bs: Basis) -> void:
		solids.append({"kind": "obox", "c": c, "size": s, "basis": bs})

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
static var problems: Array = []   # generators' misuse of comp()/only(), "part: what" (kept until the process ends)
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
	return MAKERS.has(part) or _registered.has(part)

## Kinds added from outside the kit's own list (WORKSHOP.md §9): `script` a generator (a static function named as the
## part, as the kit's own), `budget` its triangles at full detail. The tests add a data-only fixture kind this way;
## the app's kinds stay in MAKERS, and a registered kind never replaces one of them.
static var _registered := {}

static func register(part: String, script: Script, budget: int) -> bool:
	if MAKERS.has(part) or script == null or budget <= 0:
		return false
	_registered[part] = {"script": script, "budget": budget}
	clear_cache()   # never a result made by a script registered before under that name
	return true

static func unregister(part: String) -> void:
	_registered.erase(part)
	clear_cache()

## A part's triangle budget at full detail: BUDGET's, or a registered kind's.
static func budget_of(part: String) -> int:
	if _registered.has(part):
		return _registered[part].budget
	return BUDGET.get(part, 0)

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
	if not MAKERS.has(part) and _registered.has(part):
		return _registered[part].script
	match MAKERS.get(part, ""):
		"MACH": return P_MACH
		"ROT": return P_ROT
		"HX": return P_HX
		"VES": return P_VES
		"VAL": return P_VAL
		"INS": return P_INS
		"EL": return P_EL
		"PIPE": return P_PIPE
		"SITE": return P_SITE
		"WAT": return P_WAT
		"HOIST": return P_HOIST
		"LIFT": return P_LIFT
	return null

## Makes a part (cached: the same part with the same parameters and context is made once).
static func make(part: String, params: Dictionary, ctx := {}, seg_scale := 1.0, workshop := false) -> Dictionary:
	var key := "%s|%s|%s|%.2f" % [part, JSON.stringify(params, "", true), JSON.stringify(_ctx_key(ctx), "", true), seg_scale]
	if workshop:
		key += "|workshop"
	if _cache.has(key):
		return _cache[key]
	var c := ctx.duplicate()
	if not c.has("dn_od_mm"):
		c["dn_od_mm"] = kit_json().get("dn_od_mm", [])
	c["nozzles"] = kit_json().get("parts", {}).get(part, {}).get("nozzles", {})
	var g := Gen.new(params, c, MB)
	g.m.seg_scale = seg_scale
	g.seg_scale = seg_scale
	g.workshop = workshop
	g.m.workshop = workshop
	var s = _script(part)
	if s == null:
		return {}
	s.call(part, part, g)
	# a generator's misuse of comp()/only() (kit/mesh.gd `problems`), reported in either mode: in plant mode here and
	# in `problems` (tests/test_kit_frozen.gd fails on any), in Workshop mode in its result too
	var found: Array = g.m.problems.duplicate()
	for n in g.moving:
		found.append_array(g.moving[n].mb.problems)
	for f in found:
		var msg := "%s: %s" % [part, f]
		if not problems.has(msg):
			problems.append(msg)
			push_error("kit: " + msg)
	if workshop:
		var w := _workshop_result(part, g)
		_cache[key] = w
		return w
	var res := {"part": part, "layers": _meshes(g.m.finish(), Vector3.ZERO), "moving": [], "plates": {}, "solids": g.solids,
		"axis": [_gv(g.axis_line[0]), _gv(g.axis_line[1])]}
	for n in g.moving:
		var mv: Dictionary = g.moving[n]
		res.moving.append({"name": n, "pivot": _gv(mv.pivot), "axis": _gv(mv.axis).normalized(), "kind": mv.kind,
			"travel": mv.travel, "layers": _meshes(mv.mb.finish(), _gv(mv.pivot))})
	for n in g.plates:
		var pl: Dictionary = g.plates[n]
		res.plates[n] = {"at": _gv(pl.at), "normal": _gv(pl.normal), "kind": pl.kind}
	res["tris"] = tris_of(res)
	_cache[key] = res
	return res

## The Workshop mode's result (WORKSHOP.md §4.2): every shape in the part's Godot frame.
##   layers      {key: {mat, cls, size, comp, tag, mesh, tris}} static pieces, keyed comp|tag|mat|class|bucket, no LODs
##   moving      as plant mode's, each layer with its comp and tag
##   components  [{id, parent, pivot, box, explode, sym, anchors, anim, thin}] in declaration order (`body` alone when
##               the generator declares none); box: the component's static and moving pieces; explode [] = default
##   fasteners   [{id, kind, parent, items: [Transform3D], layers, box}] (items in the part's Godot frame, layers in an
##               item's own)
##   flows       {id: [points]}
##   standins    [{replaced_by, layers: {comp|shared|mat|class|bucket key: {mat, cls, size, mesh, tris}}, box, moving}]
##               (`moving`: the moving piece's name, "" for the static builder's; its layers are relative to that pivot)
##   pieces      [{comp, kind, role, standin, box, tris, moving}] every only() block (static and moving builders'; a
##               moving piece's box relative to its pivot)
##   problems    the generator's mistakes (a piece in an undeclared component, a misuse of only())
static func _workshop_result(part: String, g) -> Dictionary:
	var res := {"part": part, "workshop": true, "layers": _ws_meshes(g.m.finish(), Vector3.ZERO), "moving": [],
		"plates": {}, "solids": g.solids, "axis": [_gv(g.axis_line[0]), _gv(g.axis_line[1])], "components": [],
		"fasteners": [], "flows": {}, "standins": [], "pieces": [], "problems": g.m.problems.duplicate()}
	for n in g.moving:
		var mv: Dictionary = g.moving[n]
		res.moving.append({"name": n, "pivot": _gv(mv.pivot), "axis": _gv(mv.axis).normalized(), "kind": mv.kind,
			"travel": mv.travel, "layers": _ws_meshes(mv.mb.finish(), _gv(mv.pivot))})
		res.problems.append_array(mv.mb.problems)
	for n in g.plates:
		var pl: Dictionary = g.plates[n]
		res.plates[n] = {"at": _gv(pl.at), "normal": _gv(pl.normal), "kind": pl.kind}
	var comps: Dictionary = g.components.duplicate(true)
	if comps.is_empty():
		comps["body"] = {"parent": "", "thin": false, "anim": "", "anchors": {}}
	# each component's box from its pieces (the moving ones where they stand at value 0)
	var boxes := {}
	for k in res.layers:
		var L: Dictionary = res.layers[k]
		boxes[L.comp] = _merge_box(boxes.get(L.comp), L.mesh.get_aabb())
	for mv in res.moving:
		for k in mv.layers:
			var L: Dictionary = mv.layers[k]
			var bb: AABB = L.mesh.get_aabb()
			bb.position += mv.pivot
			boxes[L.comp] = _merge_box(boxes.get(L.comp), bb)
	for id in boxes:
		if not comps.has(id):
			res.problems.append("pieces in the component %s, which the generator never declared" % id)
	for id in comps:
		var c: Dictionary = comps[id]
		var box: AABB = boxes.get(id, AABB())
		var piv: Vector3 = _gv(c.pivot) if c.has("pivot") else box.get_center()
		res.components.append({"id": id, "parent": c.parent, "pivot": piv, "box": box,
			"explode": [_gv(c.explode[0]), c.explode[1]] if c.has("explode") else [],
			"sym": [_gv(c.sym[0]), c.sym[1]] if c.has("sym") else [],
			"anchors": _gv_dict(c.anchors), "anim": c.anim, "thin": c.thin})
	for fg in g.fastener_groups:
		var items: Array = []
		for t in fg.items:
			items.append(_gt(t))
		var layers := _ws_meshes(fg.mb.finish(), Vector3.ZERO)
		var one = null
		for k in layers:
			one = _merge_box(one, layers[k].mesh.get_aabb())
		res.fasteners.append({"id": fg.id, "kind": fg.kind, "parent": fg.parent, "items": items, "layers": layers,
			"box": one if one != null else AABB()})
	for id in g.flows:
		res.flows[id] = g.flows[id].map(func(q): return _gv(q))
	var builders: Array = [["", g.m, Vector3.ZERO]]
	for n in g.moving:
		builders.append([n, g.moving[n].mb, _gv(g.moving[n].pivot)])
	for bd in builders:
		_ws_pieces(res, bd[0], bd[1], bd[2])
	var n := 0
	for k in res.layers:
		n += res.layers[k].tris[0]
	for mv in res.moving:
		for k in mv.layers:
			n += mv.layers[k].tris[0]
	for f in res.fasteners:
		for k in f.layers:
			n += f.layers[k].tris[0] * f.items.size()
	res["tris"] = n
	return res

## A builder's stand-ins and only() blocks into the result (`moving`: its moving piece's name, "" the static builder;
## `pivot`: that piece's pivot in Godot's axes, its layers and boxes made relative to it as its meshes are).
static func _ws_pieces(res: Dictionary, moving: String, mb, pivot: Vector3) -> void:
	var first: int = res.standins.size()
	for si in mb.standins:
		var layers := _ws_meshes(mb.finish_layers(si.layers), pivot)
		var bb = null
		for k in layers:
			bb = _merge_box(bb, layers[k].mesh.get_aabb())
		res.standins.append({"replaced_by": si.replaced_by, "layers": layers, "box": bb if bb != null else AABB(),
			"moving": moving})
	for pc in mb.pieces:
		var box: AABB = pc.box
		box.position -= pivot
		res.pieces.append({"comp": pc.comp, "kind": pc.kind, "role": pc.role,
			"standin": first + pc.standin if pc.standin >= 0 else -1, "box": box, "tris": pc.tris, "moving": moving})

static func _merge_box(a, b: AABB) -> AABB:
	return b if a == null else (a as AABB).merge(b)

static func _gv_dict(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[k] = _gv(d[k])
	return out

## A part-frame transform in Godot's axes (for a mesh whose vertices are in Godot's axes too).
static func _gt(t: Transform3D) -> Transform3D:
	var C := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))   # columns: part x, y, z in Godot's axes
	return Transform3D(C * t.basis * C.inverse(), _gv(t.origin))

## The Workshop's meshes: as _meshes but without LODs, each keeping its component and tag.
static func _ws_meshes(layers: Dictionary, origin: Vector3) -> Dictionary:
	var out := {}
	for k in layers:
		var L: Dictionary = layers[k]
		var arr: Array = L.arrays
		if origin != Vector3.ZERO:
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for i in v.size():
				v[i] -= origin
			arr[Mesh.ARRAY_VERTEX] = v
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.resource_name = k
		out[k] = {"mat": L.mat, "cls": L.cls, "size": L.size, "comp": L.get("comp", ""), "tag": L.get("tag", ""),
			"mesh": mesh, "tris": [L.tris]}
	return out

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
		if L.tris >= 64 and L.cls != "identify":
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
	_kit_json = {}
