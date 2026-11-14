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
const Explode = preload("res://workshop/explode.gd")
## The way the working fluid flows along the shaft, per kind with blade rows (Godot's axes: the generator's +y is -z):
## the steam turbine's steam from its inlet end to its exhaust end (generator -y), the gas turbine's air and gas from
## the compressor to the exhaust (generator +y). Every kind whose drawn faces lean about a shaft is listed here.
## A kind whose flow leaves the shaft radially (a centrifugal pump's impeller, a motor's fan) says "radial", with the
## number of its moving rows whose vanes lean (RADIAL_ROWS): an impeller's vanes curve back against its turn, a
## motor's fan has straight radial blades (it cools whichever way the motor turns), so it has none.
const FLOW := {"steam_turbine": Vector3(0, 0, 1), "gas_turbine": Vector3(0, 0, -1), "pump_horizontal": "radial",
	"motor": "radial", "pump_vertical": "radial"}
const RADIAL_ROWS := {"pump_horizontal": 1, "motor": 0, "pump_vertical": 2}
## Pairs of a turning component and a standing one that may meet as it turns ("kind|turning|standing", standing may
## end in "*"), each with its reason (_turning).
const RUBS := {}
const RUB := 0.002   # how far (m) a turning surface may reach into a standing one's band (a polygon's flats, a fit)
const TURN_SMALL := 0.05   # the longest edge (m) of the pieces a triangle is halved into for it
## Pairs of components whose explode may pass through each other ("kind|a|b", either order; b may end in "*" for
## every component whose id begins so), each with its reason (_explode_paths).
const PASSES := {
	"gas_turbine|intake|rotor": "the plant draws the inlet plenum as a closed box round the shaft: lifted off, it "
		+ "passes over it as if its floor and walls were split round the shaft, as a real plenum's are",
	"gas_turbine|intake|bell_*": "the same box round the bellmouth's halves",
	"steam_turbine|rotor|pedestal_f": "the plant draws the front pedestal's end walls whole round the shaft: a real "
		+ "pedestal's are split at the joint and their upper parts come off with the cap",
	"gas_turbine|fuel_ring|*": "the plant draws the fuel gas ring closed round the discharge casing, among the cans' "
		+ "end covers and into the foundation block: it stays, and what lifts passes through it (a real one's pigtails "
		+ "are undone and it comes off in segments)",
	"steam_turbine|valve_l|ctrl_l": "the plant draws each valve chest closed (§7.2): the control valve's plug is "
		+ "lifted out through its top, as a real one comes out through the chest's opening once the servomotor and "
		+ "the cover are off",
	"steam_turbine|valve_r|ctrl_r": "the same chest on the other side",
	"motor|end_shield_de|rotor": "the plant draws the drive-end shield's face closed and the shaft's stub standing on it: "
		+ "the shield comes off forwards over the stub, as a real one does through its bore",
	"shell_tube_hx|bundle|saddles": "the plant draws the saddles as boxes reaching 0.3 m up into the shell (a real "
		+ "saddle is a cradle under it): the bundle's baffles pass their tops as it is drawn out",
	"test_gadget|base|core": "the fixture's core is drawn inside its closed base on purpose (a hidden piece) and "
		+ "comes out through its wall",
}
## A valve's closure member, its seat and the moving piece that carries it ("kind": [plug, seat, moving]) (_seats).
const SEATS := {"valve_control": ["plug_stem", "seat_ring", "stem"], "valve_globe": ["disc", "seat_ring", "stem"]}
## A gate valve's wedge, its seat rings and the moving piece that lifts it ("kind": [wedge, seats, moving]): the
## wedge lies across the flow between the two rings (_wedge).
const WEDGES := {"valve_gate": ["wedge", "seat_rings", "stem"]}
## A butterfly valve's disc, its seat (the liner) and the moving piece that turns it ("kind": [disc, seat, moving])
## (_discs).
const DISCS := {"valve_butterfly": ["disc", "liner", "disc"]}
## A plate heat exchanger's frame plate, pressure plate, plates (in order from the pressure plate's side) and bolt
## groups ("kind": {...}): the plates lie square between the two plates and the bolts span them (_packs).
const PACKS := {"plate_hx": {"frame": "frame_plate", "pressure": "pressure_plate",
	"plates": ["end_plate_1", "plates", "end_plate_2"], "bolts": ["tightening_bolts", "locking_bolts"]}}
## A shell-and-tube exchanger's tubes, its tubesheets (stationary, floating) and its shell ("kind": {...}): the tubes
## run straight from one tubesheet to the other inside the shell's bore (_bundles).
const BUNDLES := {"shell_tube_hx": {"tubes": "tubes", "sheets": ["bundle", "tubesheet_f"], "shell": "shell"}}
const CELL := 0.25   # the cells' width (m) in which the explode's paths are compared
const SMALL := 0.1   # the longest edge of a small triangle there (m)
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
		# WS_ONLY=kind,kind… checks those kinds alone (a quicker run while a kind's tree is being written; CI sets none)
		var only := OS.get_environment("WS_ONLY")
		if only != "" and not part in only.split(","):
			continue
		kinds += 1
		# the parameters the build made its scene with (the plant's first instance of the kind), else the defaults
		var params := WB.params_for(part, data, {})
		var ctx := {}   # and the context it named from that instance (a shaft line), else none
		var built := "res://built/workshop/%s.scn" % part
		if ResourceLoader.exists(built):
			var bs: Node = (load(built) as PackedScene).instantiate()
			params = bs.get_meta("params", params)
			ctx = bs.get_meta("ctx", ctx)
			bs.free()
		_kind(part, data, params, ctx)
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
func _kind(part: String, data: Dictionary, params: Dictionary, ctx := {}) -> void:
	var r := WB.scene(part, data, params, ctx)
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
	# a fastener group's name that counts its items ("44 joint studs") counts what the generator draws
	var re := RegEx.create_from_string("^(\\d+) ")
	for f in ws.fasteners:
		var m := re.search(String(data.get("fasteners", {}).get(f.id, {}).get("name", "")))
		check(m == null or int(m.get_string(1)) == f.items.size(), "%s: %s's name counts %s, the generator draws %d" % [
			part, f.id, m.get_string(1) if m != null else "", f.items.size()])
	# the same parameters in plant mode, for the outside: as the builder makes the plant's part
	var plant := Kit.make(part, params, ctx)
	_outside(part, plant, ws)
	_pieces(part, ws)
	_closed(part, ws)
	_blade_lean(part, ws)
	_turning(part, ws)
	_seats(part, ws)
	_wedge(part, ws)
	_discs(part, ws)
	_packs(part, ws)
	_bundles(part, ws)
	if r.scene != null:
		_explode_paths(part, r.scene)
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
		var piv := Vector3.ZERO   # a moving piece's stand-in is relative to its pivot, as its layers are
		for mv in ws.moving:
			if mv.name == si.moving:
				from = mv.layers
				piv = mv.pivot
		for k in from:
			var L: Dictionary = from[k]
			if L.tag == "split" and L.comp in si.replaced_by:
				var bb: AABB = L.mesh.get_aabb()
				box = bb if not any else box.merge(bb)
				any = true
				tris[L.mat] = tris.get(L.mat, 0) + L.tris[0]
		for f in ws.fasteners:   # a fastener group that replaces it: every item, where it stands
			if f.get("role", "outside") == "split" and f.id in si.replaced_by:
				for k in f.layers:
					var L: Dictionary = f.layers[k]
					for t in f.items:
						var bb: AABB = (t as Transform3D) * (L.mesh.get_aabb() as AABB)
						bb.position -= piv
						box = bb if not any else box.merge(bb)
						any = true
					tris[L.mat] = tris.get(L.mat, 0) + L.tris[0] * f.items.size()
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
	var stands := {}   # fastener groups that replace a stand-in (held to the plant's outside by _outside instead)
	for si in ws.standins:
		for c in si.replaced_by:
			stands[c] = true
	for f in ws.fasteners:
		if f.get("role", "outside") == "split":
			check(stands.has(f.id), "%s: the fastener group %s is drawn as a stand-in's replacement but replaces none" % [part, f.id])
			listed.append("%s %d (replacing a stand-in)" % [f.id, f.items.size()])
			continue
		if f.get("role", "outside") == "hidden":   # held to the hidden pieces' rule below, every item where it stands
			listed.append("%s %d (hidden)" % [f.id, f.items.size()])
			continue
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
	var hidden: Array = []   # [layer, offset, key, item transform]
	for pr in _all_layers(ws):
		if pr[0].tag == "hidden":
			hidden.append([pr[0], pr[1], pr[2], Transform3D.IDENTITY])
	for f in ws.fasteners:
		if f.get("role", "outside") == "hidden":
			for k in f.layers:
				for i in f.items.size():
					hidden.append([f.layers[k], Vector3.ZERO, "%s/%d/%s" % [f.id, i, k], f.items[i]])
	for pr in hidden:
		var L: Dictionary = pr[0]
		var k: String = pr[2]
		var off: Vector3 = pr[1]
		var arr := (L.mesh as ArrayMesh).surface_get_arrays(0)
		var it: Transform3D = pr[3]
		var v: PackedVector3Array = it * (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array)
		var nm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		for i in nm.size():
			nm[i] = it.basis * nm[i]
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

## Each blade row's lean, from its drawn faces: a flat blade turned b from the flow f towards the way t its row's
## points move as the rotor turns has faces whose normals n give (n·f)(n·t) = -sin b cos b, whichever face; summed over
## a component's faces (each by its area; surfaces of revolution give 0) its sign is the lean's. A stationary row
## (nozzles, stator vanes) leans with the rotor's turn and a moving row (buckets, rotor blades) against it, in a
## compressor and in a turbine alike: so the turbine drives the rotor the way it turns (its anim's axis, right-handed)
## and the compressor is driven that way. Any kind with a shaft must say its flow (FLOW).
func _blade_lean(part: String, ws: Dictionary) -> void:
	var shaft = null
	for mv in ws.moving:
		if mv.name == "shaft":
			shaft = mv
	if shaft == null:
		return
	check(FLOW.has(part), "%s: a kind with a shaft says the way its flow goes along it (FLOW)" % part)
	if not FLOW.has(part):
		return
	if FLOW[part] is String:
		_radial_lean(part, ws, shaft)
		if int(RADIAL_ROWS.get(part, 0)) > 0:   # the check itself: the same vanes with the shaft turning the other way fail
			var kept := problems.duplicate()
			var back: Dictionary = shaft.duplicate()
			back.axis = -(shaft.axis as Vector3)
			_radial_lean(part, ws, back)
			var caught := problems.size() > kept.size()
			problems = kept
			check(caught, "%s: the vane check misses an impeller turning the wrong way" % part)
		return
	var f: Vector3 = FLOW[part]
	var ax: Vector3 = shaft.axis
	check(absf(ax.dot(f)) > 0.999, "%s: the shaft turns about the flow's line (%s, %s)" % [part, ax, f])
	var sums := {}   # comp -> [sum, area, moving]
	for pr in _all_layers(ws):
		var L: Dictionary = pr[0]
		var shift: Vector3 = pr[1]
		var arr := (L.mesh as ArrayMesh).surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var acc: Array = sums.get(L.comp, [0.0, 0.0, false])
		acc[2] = acc[2] or String(pr[2]).begins_with("shaft/")
		for i in range(0, idx.size(), 3):
			var a := v[idx[i]] + shift
			var b := v[idx[i + 1]] + shift
			var c := v[idx[i + 2]] + shift
			var cr := (b - a).cross(c - a)
			var area := cr.length() * 0.5
			if area < 1e-12:
				continue
			var n := cr.normalized()
			var rel: Vector3 = (a + b + c) / 3.0 - (shaft.pivot as Vector3)
			var rad: Vector3 = rel - ax * rel.dot(ax)
			if rad.length() < 1e-4:
				continue
			var tg := ax.cross(rad.normalized())
			acc[0] += area * n.dot(f) * n.dot(tg)
			acc[1] += area
		sums[L.comp] = acc
	var rows := [0, 0]
	for id in sums:
		var acc: Array = sums[id]
		var lean: float = acc[0] / maxf(acc[1], 1e-9)
		if absf(lean) < 0.05:
			continue
		rows[1 if acc[2] else 0] += 1
		# stationary: b > 0, the sum < 0; moving: b < 0, the sum > 0
		check((lean > 0.0) == bool(acc[2]), "%s: %s (%s) leans %s the rotor's turn (%.2f): a %s row leans %s it" % [part, id,
			"moving" if acc[2] else "stationary", "with" if lean < 0.0 else "against", lean,
			"moving" if acc[2] else "stationary", "against" if acc[2] else "with"])
	check(rows[0] > 0 and rows[1] > 0, "%s: blade rows found, stationary and moving (%d, %d)" % [part, rows[0], rows[1]])

## A radial machine's vanes, from the faces of what turns with the shaft (its `shaft` node): with the flow f the
## radial direction at each face, a vane curved back against the turn t (its tip trailing) has faces whose normals n
## give (n·f)(n·t) > 0, one curved forwards < 0, and a straight radial blade 0. Faces nearly facing outwards (a
## surface of revolution's facets) or across the shaft are left out. Per component: the signed sum over the sum of
## its magnitudes, for each component whose faces lean one way by more than 2 % of its area; every one must lean back (an impeller drawn turning the wrong way, or its vanes mirrored, fails),
## and the kind has RADIAL_ROWS of them.
func _radial_lean(part: String, ws: Dictionary, shaft: Dictionary) -> void:
	var ax: Vector3 = shaft.axis
	var sums := {}   # comp -> [signed, magnitude, area]
	for pr in _all_layers(ws):
		var L: Dictionary = pr[0]
		if not String(pr[2]).begins_with("shaft/"):
			continue
		var shift: Vector3 = pr[1]
		var arr := (L.mesh as ArrayMesh).surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var acc: Array = sums.get(L.comp, [0.0, 0.0, 0.0])
		for i in range(0, idx.size(), 3):
			var a := v[idx[i]] + shift
			var b := v[idx[i + 1]] + shift
			var c := v[idx[i + 2]] + shift
			var cr := (b - a).cross(c - a)
			var area := cr.length() * 0.5
			if area < 1e-12:
				continue
			var n := cr.normalized()
			var rel: Vector3 = (a + b + c) / 3.0 - (shaft.pivot as Vector3)
			var rad: Vector3 = rel - ax * rel.dot(ax)
			if rad.length() < 1e-4:
				continue
			var f := rad.normalized()
			acc[2] += area
			if absf(n.dot(f)) > 0.97 or absf(n.dot(ax)) > 0.5:
				continue   # (a surface of revolution's facets, a face across the shaft: no vane)
			var x := area * n.dot(f) * n.dot(ax.cross(f))
			acc[0] += x
			acc[1] += absf(x)
		sums[L.comp] = acc
	var rows := 0
	for id in sums:
		var acc: Array = sums[id]
		if absf(acc[0]) < 0.02 * acc[2]:
			continue
		rows += 1
		check(acc[0] / acc[1] > 0.5, "%s: %s's vanes lean %s the shaft's turn (%.2f): an impeller's curve back against it" % [
			part, id, "with" if acc[0] < 0.0 else "neither way against", acc[0] / acc[1]])
	check(rows == int(RADIAL_ROWS.get(part, -1)), "%s: %d leaning rows turn with the shaft, %d expected (RADIAL_ROWS)" % [
		part, rows, int(RADIAL_ROWS.get(part, -1))])

## What turns turns on the shaft's line and rubs nothing that stands (K6): every component drawn in the `shaft` node
## has its box centred on the node's axis (within RUB), and no standing component's triangle lies in the band a turning
## triangle sweeps round the axis: a triangle of each is reduced to its span along the axis and its nearest and
## farthest distance from it (corners and edges' midpoints: a chord's nearest point), and a standing one whose span
## meets a turning one's by more than RUB along the axis and RUB across it (an impeller wider than its bowl, a rotor off
## its line), or crosses it (_across: a shaft drawn through a closed face), is cut by it as it turns. The centrifugal kinds (FLOW "radial").
func _turning(part: String, ws: Dictionary) -> void:
	var shaft = null
	for mv in ws.moving:
		if mv.name == "shaft":
			shaft = mv
	if shaft == null or not FLOW.get(part, null) is String:
		return   # (the turbines' rows turn in their carriers' grooves: their tens of thousands of triangles are left)
	var ax: Vector3 = (shaft.axis as Vector3).normalized()
	var piv: Vector3 = shaft.pivot
	var turning := {}   # comp -> [[t0, t1, r0, r1], ...]
	var standing := {}
	var boxes := {}
	for pr in _all_layers(ws):
		var L: Dictionary = pr[0]
		var turns := String(pr[2]).begins_with("shaft/")
		var into: Dictionary = turning if turns else standing
		var arr := (L.mesh as ArrayMesh).surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var spans: Array = into.get(L.comp, [])
		for i in range(0, idx.size(), 3):
			var a: Vector3 = v[idx[i]] + pr[1]
			var b: Vector3 = v[idx[i + 1]] + pr[1]
			var c: Vector3 = v[idx[i + 2]] + pr[1]
			if turns:
				var bb: AABB = boxes.get(L.comp, AABB(a, Vector3.ZERO))
				boxes[L.comp] = bb.expand(a).expand(b).expand(c)
			var stack: Array = [[a, b, c]]
			while not stack.is_empty():   # halved along the longest edge down to TURN_SMALL: a span is the triangle's
				var tri: Array = stack.pop_back()
				var p0: Vector3 = tri[0]
				var p1: Vector3 = tri[1]
				var p2: Vector3 = tri[2]
				var l01 := p0.distance_squared_to(p1)
				var l12 := p1.distance_squared_to(p2)
				var l20 := p2.distance_squared_to(p0)
				var lm := maxf(l01, maxf(l12, l20))
				if lm > TURN_SMALL * TURN_SMALL:
					if lm == l01:
						stack.append([p0, (p0 + p1) * 0.5, p2]); stack.append([(p0 + p1) * 0.5, p1, p2])
					elif lm == l12:
						stack.append([p0, p1, (p1 + p2) * 0.5]); stack.append([p0, (p1 + p2) * 0.5, p2])
					else:
						stack.append([p0, p1, (p2 + p0) * 0.5]); stack.append([(p2 + p0) * 0.5, p1, p2])
					continue
				var t0 := INF
				var t1 := -INF
				var r0 := INF
				var r1 := -INF
				for q: Vector3 in [p0, p1, p2, (p0 + p1) * 0.5, (p1 + p2) * 0.5, (p2 + p0) * 0.5, (p0 + p1 + p2) / 3.0]:
					var rel := q - piv
					var t := rel.dot(ax)
					var r := (rel - ax * t).length()
					t0 = minf(t0, t)
					t1 = maxf(t1, t)
					r0 = minf(r0, r)
					r1 = maxf(r1, r)
				spans.append([t0, t1, r0, r1])
		into[L.comp] = spans
	for id in boxes:
		var cen: Vector3 = (boxes[id] as AABB).get_center() - piv
		var off: float = (cen - ax * cen.dot(ax)).length()
		check(off <= RUB, "%s: %s turns with the shaft but its box is %.1f mm off the shaft's line" % [part, id,
			off * 1000.0])
	var bins := {}   # (bin along the axis, bin out from it) -> [[span, standing comp]]
	var rmax := 0.0
	for tid in turning:
		for x: Array in turning[tid]:
			rmax = maxf(rmax, x[3])
	for sid in standing:
		for y: Array in standing[sid]:
			if y[2] > rmax:
				continue   # (beyond anything that turns)
			for k in range(floori(y[0] / TURN_SMALL), floori(y[1] / TURN_SMALL) + 1):
				for j in range(floori(y[2] / TURN_SMALL), floori(minf(y[3], rmax) / TURN_SMALL) + 1):
					var key := Vector2i(k, j)
					if not bins.has(key):
						bins[key] = []
					bins[key].append([y, sid])
	var told := {}
	for tid in turning:
		if standing.has(tid):
			check(false, "%s: %s is drawn partly in the turning node and partly standing" % [part, tid])
			continue
		for x: Array in turning[tid]:
			# (a polygon's flats: a turning corner sweeps past a standing flat of the same circle by r (1 - cos(pi/n)),
			# 2 % of r at 16 sides)
			var tol: float = maxf(RUB, x[3] * 0.025)
			for k in range(floori(x[0] / TURN_SMALL), floori(x[1] / TURN_SMALL) + 1):
				for j in range(floori(x[2] / TURN_SMALL), floori(x[3] / TURN_SMALL) + 1):
					for e: Array in bins.get(Vector2i(k, j), []):
						var y: Array = e[0]
						var sid: String = e[1]
						if (minf(x[1], y[1]) - maxf(x[0], y[0]) > RUB and minf(x[3], y[3]) - maxf(x[2], y[2]) > tol \
								or _across(x, y)) and not told.has(tid + "|" + sid) and not _rubs_listed(part, tid, sid):
							told[tid + "|" + sid] = true
							check(false, "%s: %s rubs %s as it turns (its piece %.3f-%.3f m along the shaft, %.3f-%.3f m from it; %s's %.3f-%.3f, %.3f-%.3f)" % [
								part, tid, sid, x[0], x[1], x[2], x[3], sid, y[0], y[1], y[2], y[3]])

## Whether one span crosses the other: within it along the shaft and across it from the shaft, by a millimetre each way
## (a standing face a turning surface passes through, however thin either is: a shaft through a closed face).
func _across(x: Array, y: Array) -> bool:
	var e := 0.001
	var along: bool = (y[0] > x[0] + e and y[1] < x[1] - e) or (x[0] > y[0] + e and x[1] < y[1] - e)
	var out: bool = (y[2] < x[2] - e and y[3] > x[3] + e) or (x[2] < y[2] - e and x[3] > y[3] + e)
	return along and out

func _rubs_listed(part: String, a: String, c: String) -> bool:
	for k in RUBS:
		var s: PackedStringArray = String(k).split("|")
		if s[0] == part and s[1] == a and (s[2] == c or s[2].ends_with("*") and c.begins_with(s[2].trim_suffix("*"))):
			return true
	return false

## The explode's paths (§4.3), sampled through every stage of the slider: no component goes below the floor (the
## machine's lowest point, assembled, when it stands on the ground, y = 0, on a part that stays), and none passes
## through another: while a
## stage moves, no two cells of two components (_mesh_cells, _meet) share more than they did at the stage's start; a
## pair listed in PASSES is not compared. Wherever two components' whole boxes meet while they move apart from each
## other (a child and its parent too: it leaves the parent along its own way), their triangles (halved down to SMALL,
## found through the cells) are tested: two that cut each other at a sample and not at the stage's start pass through
## each other. Two whose triangles already cut each other at the stage's start are not judged.
func _explode_paths(part: String, ps: PackedScene) -> void:
	var root: Node3D = ps.instantiate()
	var spec := Explode.spec_of(root)
	var home := {}
	var pieces := {}
	_home_boxes(root, root, Vector3.ZERO, home, pieces)
	root.free()
	var floor_y := INF
	var lowest := ""
	for id in home:
		if (home[id] as AABB).position.y < floor_y:
			floor_y = (home[id] as AABB).position.y
			lowest = id
	var b_end := _boxes_at(spec, home, 1.0)
	if absf(floor_y) > 0.01 or not b_end[lowest].position.is_equal_approx(home[lowest].position - Vector3.ONE * 0.005):
		floor_y = -INF   # (it doesn't stand on the ground on a part that stays: no floor)
	var ids: Array = home.keys()
	var D: int = Explode.levels(spec)[2]
	var N := 8
	var bad := {}
	for d in D:
		var b0 := _boxes_at(spec, home, float(d) / D)
		for k in range(1, N + 1):
			var b1 := _boxes_at(spec, home, (d + float(k) / N) / D)
			for i in ids.size():
				var a: String = ids[i]
				if b1[a].position.y < floor_y - 0.005 and not bad.has(a):
					bad[a] = true
					check(false, "%s: %s goes below the floor in the explode (%.2f m under it at s = %.2f)" % [part, a,
						floor_y - b1[a].position.y, (d + float(k) / N) / D])
				for j in range(i + 1, ids.size()):
					var c: String = ids[j]
					if bad.has(a + "|" + c) or not b1[a].intersects(b1[c]) or _passes(part, a, c):
						continue
					var r0: Vector3 = (b0[a].position - home[a].position) - (b0[c].position - home[c].position)
					var r1: Vector3 = (b1[a].position - home[a].position) - (b1[c].position - home[c].position)
					if r0.is_equal_approx(r1):
						continue   # (they move together, or neither moves)
					var ca: Dictionary = pieces[a]
					var cc: Dictionary = pieces[c]
					var small: bool = ca.size() <= cc.size()
					var hit := _cells_pass(ca.values(), cc, r0, r1) if small else _cells_pass(cc.values(), ca, -r0, -r1)
					# (two drawn into each other at the stage's start, a can through its wrapper's wall, a shaft
					# through a housing's end walls, are not judged: their surfaces slide through each other)
					if hit and (_cells_pass(ca.values(), cc, r0, r0) if small else _cells_pass(cc.values(), ca, -r0, -r0)):
						bad[a + "|" + c] = true
						continue
					if hit:
						bad[a + "|" + c] = true
						check(false, "%s: %s and %s pass through each other in the explode (stage %d of %d, s = %.2f)" % [
							part, a, c, d + 1, D, (d + float(k) / N) / D])

## A valve's plug closes its seat (SEATS): at 0 travel its face toward the seat lies on the seat's face (within 1 mm)
## and covers the seat's bore; the plug, the seat's bore and the moving piece's axis are one line; opening (the moving
## piece's travel along its axis) lifts the plug off the seat, never into it.
func _seats(part: String, ws: Dictionary) -> void:
	if not SEATS.has(part):
		return
	var who: Array = SEATS[part]
	var mv = null
	for x in ws.moving:
		if x.name == who[2]:
			mv = x
	check(mv != null, "%s: the moving piece %s" % [part, who[2]])
	if mv == null:
		return
	var a: Vector3 = mv.axis
	var o: Vector3 = mv.pivot
	var pts := {who[0]: PackedVector3Array(), who[1]: PackedVector3Array()}
	for pr in _all_layers(ws):
		var L: Dictionary = pr[0]
		if pts.has(L.comp):
			var arr := (L.mesh as ArrayMesh).surface_get_arrays(0)
			for v in (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				pts[L.comp].append(v + pr[1])
	for c in pts:
		check(not pts[c].is_empty(), "%s: %s is drawn" % [part, c])
		if pts[c].is_empty():
			return
	var off := func(p: Vector3) -> float: return ((p - o) - a * (p - o).dot(a)).length()   # from the axis line
	var centre := func(ps: PackedVector3Array) -> Vector3:
		var b := AABB(ps[0], Vector3.ZERO)
		for p in ps:
			b = b.expand(p)
		return b.get_center()
	var cp: Vector3 = centre.call(pts[who[0]])
	var cs: Vector3 = centre.call(pts[who[1]])
	check(off.call(cp) <= 0.001 and off.call(cs) <= 0.001, "%s: %s and %s on %s's axis (%.1f and %.1f mm off it)" % [
		part, who[0], who[1], who[2], off.call(cp) * 1000.0, off.call(cs) * 1000.0])
	var low := INF
	for p in pts[who[0]]:
		low = minf(low, (p - o).dot(a))
	var top := -INF
	var bore := INF
	for p in pts[who[1]]:
		top = maxf(top, (p - o).dot(a))
		bore = minf(bore, off.call(p))
	var face := 0.0   # the plug's radius at its face toward the seat
	for p in pts[who[0]]:
		if absf((p - o).dot(a) - low) <= 0.001:
			face = maxf(face, off.call(p))
	check(absf(low - top) <= 0.001, "%s: %s sits on %s at 0 travel (%.1f mm apart)" % [part, who[0], who[1],
		(low - top) * 1000.0])
	# opening moves the stem along +axis by its travel; the plug lies wholly on that side of the seat's top (its
	# lowest point on it, above), so opening lifts it off and never drives it into the seat
	check(mv.travel > 0.0 and low >= top - 0.001, "%s: opening %s lifts %s off %s" % [part, who[2], who[0], who[1]])
	check(face > bore + 0.001, "%s: %s's face (radius %.1f mm) covers %s's bore (%.1f mm)" % [part, who[0], who[1],
		face * 1000.0, bore * 1000.0])

## A gate valve's wedge at 0 travel (closed): on the stem's axis, between its two seat rings, each face lying on the
## ring on its side (no ring's point inside the wedge, the nearest within 1 mm of its face), wider than the rings'
## bore; opening lifts it by its travel clear of the bore (its lowest point above the bore's top).
func _wedge(part: String, ws: Dictionary) -> void:
	if not WEDGES.has(part):
		return
	var who: Array = WEDGES[part]
	var mv = null
	for x in ws.moving:
		if x.name == who[2]:
			mv = x
	check(mv != null, "%s: the moving piece %s" % [part, who[2]])
	if mv == null:
		return
	var a: Vector3 = mv.axis
	var o: Vector3 = mv.pivot
	var pts := {who[0]: PackedVector3Array(), who[1]: PackedVector3Array()}
	var faces: Array = []   # the wedge's triangles [p0, p1, p2]
	for pr in _all_layers(ws):
		var L: Dictionary = pr[0]
		if not pts.has(L.comp):
			continue
		var arr := (L.mesh as ArrayMesh).surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for q in v:
			pts[L.comp].append(q + pr[1])
		if L.comp == who[0]:
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			for t in range(0, idx.size(), 3):
				faces.append([v[idx[t]] + pr[1], v[idx[t + 1]] + pr[1], v[idx[t + 2]] + pr[1]])
	for c in pts:
		check(not pts[c].is_empty(), "%s: %s is drawn" % [part, c])
		if pts[c].is_empty():
			return
	var centre := func(ps: PackedVector3Array) -> Vector3:
		var b := AABB(ps[0], Vector3.ZERO)
		for p in ps:
			b = b.expand(p)
		return b.get_center()
	var cw: Vector3 = centre.call(pts[who[0]])
	var cs: Vector3 = centre.call(pts[who[1]])
	var off := func(p: Vector3) -> float: return ((p - o) - a * (p - o).dot(a)).length()
	check(off.call(cw) <= 0.001 and off.call(cs) <= 0.001, "%s: %s and %s on %s's axis (%.1f and %.1f mm off it)" % [
		part, who[0], who[1], who[2], off.call(cw) * 1000.0, off.call(cs) * 1000.0])
	# the bore's axis (the flow's way): the direction across the stem's axis in which the rings' points spread least
	var flow := Vector3.ZERO
	var best := INF
	for k in 36:
		var t := PI * k / 36.0
		var A: Array = _perp(a)
		var dir: Vector3 = A[0] * cos(t) + A[1] * sin(t)
		var spread := 0.0
		for p in pts[who[1]]:
			spread = maxf(spread, absf((p - cs).dot(dir)))
		if spread < best:
			best = spread
			flow = dir
	var bore := INF   # the rings' bore: their nearest point to the flow line through their centre
	for p in pts[who[1]]:
		var d: Vector3 = (p - cs) - flow * (p - cs).dot(flow)
		bore = minf(bore, d.length())
	var reach := 0.0  # the wedge's reach from that line
	for p in pts[who[0]]:
		var d: Vector3 = (p - cs) - flow * (p - cs).dot(flow)
		reach = maxf(reach, d.length())
	check(reach > bore + 0.001, "%s: %s (reaching %.1f mm from the bore's axis) covers %s's bore (%.1f mm)" % [part,
		who[0], reach * 1000.0, who[1], bore * 1000.0])
	for sg: float in [-1.0, 1.0]:
		var side := flow * sg
		var plane = null   # the wedge's face toward this ring
		for f in faces:   # (by where it lies, not its winding)
			var nrm: Vector3 = (f[1] - f[0]).cross(f[2] - f[0])
			if nrm.length() < 1e-9 or absf(nrm.normalized().dot(side)) < 0.9:
				continue
			if ((f[0] + f[1] + f[2]) / 3.0 - cw).dot(side) > 0.0:
				nrm = nrm.normalized()
				plane = [nrm if nrm.dot(side) > 0.0 else -nrm, f[0]]
				break
		check(plane != null, "%s: %s has a face toward the ring on its %s side" % [part, who[0], "+" if sg > 0 else "-"])
		if plane == null:
			continue
		var near := INF
		var inside := 0.0
		for p in pts[who[1]]:
			if (p - cs).dot(side) <= 0.0:
				continue
			var h: float = (p - plane[1]).dot(plane[0])
			near = minf(near, h)
			inside = minf(inside, h)
		check(absf(near) <= 0.001 and inside >= -0.001, "%s: %s's face lies on the %s side's ring (%.1f mm apart, %.1f mm into it)" % [
			part, who[0], "+" if sg > 0 else "-", near * 1000.0, -inside * 1000.0])
	var low := INF
	for p in pts[who[0]]:
		low = minf(low, (p - cs).dot(a))
	check(mv.travel > 0.0 and low + mv.travel >= bore - 0.001, "%s: opening %s by its travel (%.1f mm) lifts %s clear of %s's bore (its lowest point %.1f mm below the bore's centre, the bore %.1f mm)" % [
		part, who[2], mv.travel * 1000.0, who[0], who[1], -low * 1000.0, bore * 1000.0])

## A butterfly valve's disc at 0 (closed): its centre on the shaft's axis and on the liner's bore axis, its edge on the
## liner's bore all round (within 1 mm), within the liner's width; turned by its travel it lies edge-on in the bore
## (open: across the bore no wider than at its thickest).
func _discs(part: String, ws: Dictionary) -> void:
	if not DISCS.has(part):
		return
	var who: Array = DISCS[part]
	var mv = null
	for x in ws.moving:
		if x.name == who[2]:
			mv = x
	check(mv != null, "%s: the moving piece %s" % [part, who[2]])
	if mv == null:
		return
	var a: Vector3 = mv.axis
	var o: Vector3 = mv.pivot
	var pts := {who[0]: PackedVector3Array(), who[1]: PackedVector3Array()}
	for pr in _all_layers(ws):
		var L: Dictionary = pr[0]
		# (the disc as the plant draws it, not the seam that closes its face; the liner is hidden)
		if pts.has(L.comp) and (L.tag != "hidden" or L.comp == who[1]):
			for q in ((L.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				pts[L.comp].append(q + pr[1])
	for c in pts:
		check(not pts[c].is_empty(), "%s: %s is drawn" % [part, c])
		if pts[c].is_empty():
			return
	var box := func(ps: PackedVector3Array) -> AABB:
		var b := AABB(ps[0], Vector3.ZERO)
		for p in ps:
			b = b.expand(p)
		return b
	var cd: Vector3 = (box.call(pts[who[0]]) as AABB).get_center()
	var cs: Vector3 = (box.call(pts[who[1]]) as AABB).get_center()
	var off := func(p: Vector3) -> float: return ((p - o) - a * (p - o).dot(a)).length()
	check(off.call(cd) <= 0.001 and off.call(cs) <= 0.001, "%s: %s and %s on %s's axis (%.1f and %.1f mm off it)" % [
		part, who[0], who[1], who[2], off.call(cd) * 1000.0, off.call(cs) * 1000.0])
	var flow := Vector3.ZERO   # the bore's axis: across the shaft, the way the liner's points spread least
	var best := INF
	var A: Array = _perp(a)
	for k in 36:
		var t := PI * k / 36.0
		var dir: Vector3 = A[0] * cos(t) + A[1] * sin(t)
		var spread := 0.0
		for p in pts[who[1]]:
			spread = maxf(spread, absf((p - cs).dot(dir)))
		if spread < best:
			best = spread
			flow = dir
	var bore := INF
	for p in pts[who[1]]:
		bore = minf(bore, ((p - cs) - flow * (p - cs).dot(flow)).length())
	var reach := 0.0
	var thick := 0.0
	for p in pts[who[0]]:
		reach = maxf(reach, ((p - cs) - flow * (p - cs).dot(flow)).length())
		thick = maxf(thick, absf((p - cs).dot(flow)))
	check(absf(reach - bore) <= 0.001, "%s: %s's edge (%.1f mm from the bore's axis) on %s's bore (%.1f mm)" % [part,
		who[0], reach * 1000.0, who[1], bore * 1000.0])
	check(thick <= best + 0.0005, "%s: %s (%.1f mm each side) within %s's width (%.1f mm)" % [part, who[0],
		thick * 1000.0, who[1], best * 1000.0])
	var across := a.cross(flow).normalized()
	var turned := 0.0
	var rot := Basis(a, mv.travel)
	for p in pts[who[0]]:
		turned = maxf(turned, absf((rot * (p - o) + o - cs).dot(across)))
	check(mv.travel > 0.0 and turned <= thick + 0.001, "%s: turning %s by its travel lays %s edge-on in the bore (%.1f mm across it, %.1f mm thick)" % [
		part, who[2], who[0], turned * 1000.0, thick * 1000.0])

## A component's triangles in the part's frame (Godot's axes), every layer: [[a, b, c], ...]; `tags` limits the layers.
func _tris_of(ws: Dictionary, comp: String, tags := []) -> Array:
	var out: Array = []
	for pr in _all_layers(ws):
		var L: Dictionary = pr[0]
		if L.comp != comp or (not tags.is_empty() and not L.tag in tags):
			continue
		var arr := (L.mesh as ArrayMesh).surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for t in range(0, idx.size(), 3):
			out.append([v[idx[t]] + pr[1], v[idx[t + 1]] + pr[1], v[idx[t + 2]] + pr[1]])
	return out

## The span [lo, hi] of triangles along the axis a.
func _span(tris: Array, a: Vector3) -> Vector2:
	var lo := INF
	var hi := -INF
	for t in tris:
		for p: Vector3 in t:
			lo = minf(lo, p.dot(a))
			hi = maxf(hi, p.dot(a))
	return Vector2(lo, hi)

## The plane across the axis a in which a component's faces looking along `side` (+1 or -1 times a) have the most
## area: a plate's face that way.
func _face_at(tris: Array, a: Vector3, side: float) -> float:
	var area := {}
	for t in tris:
		var n: Vector3 = (t[1] - t[0]).cross(t[2] - t[0])
		if n.length() < 1e-12 or n.normalized().dot(a) * side < 0.9999:
			continue
		var k := snappedf((t[0] as Vector3).dot(a), 0.0001)
		area[k] = area.get(k, 0.0) + n.length() * 0.5
	var best := 0.0
	var at := NAN
	for k in area:
		if area[k] > best:
			best = area[k]
			at = k
	return at

## A plate heat exchanger's pack (PACKS): every plate's faces lie square to the line from the pressure plate to the
## frame plate (or along it); the plates follow each other along it without a gap or an overlap (1 mm), from the
## pressure plate's inner face to the frame plate's; every bolt of the groups runs along that line, from beyond the
## pressure plate's outer face to beyond the frame plate's, beside the plates (never through them).
func _packs(part: String, ws: Dictionary) -> void:
	if not PACKS.has(part):
		return
	var w: Dictionary = PACKS[part]
	var frame := _tris_of(ws, w.frame)
	var press := _tris_of(ws, w.pressure)
	var plates: Array = []
	for c in w.plates:
		plates.append(_tris_of(ws, c))
	for x in [frame, press] + plates:
		check(not (x as Array).is_empty(), "%s: a part of the plate pack is drawn" % part)
		if (x as Array).is_empty():
			return
	var box := func(tris: Array) -> AABB:
		var b := AABB(tris[0][0], Vector3.ZERO)
		for t in tris:
			for p: Vector3 in t:
				b = b.expand(p)
		return b
	var pack: AABB = box.call(plates[0])
	for x in plates:
		pack = pack.merge(box.call(x))
	var a: Vector3 = (pack.get_center() - (box.call(press) as AABB).get_center()).normalized()   # towards the frame plate
	var f_in: float = _face_at(frame, a, -1.0)
	var f_out: float = _face_at(frame, a, 1.0)
	var p_in: float = _face_at(press, a, 1.0)
	var p_out: float = _face_at(press, a, -1.0)
	var at := p_in
	for i in plates.size():
		var bad := 0
		for t in plates[i]:
			var n: Vector3 = (t[1] - t[0]).cross(t[2] - t[0])
			if n.length() > 1e-12 and absf(n.normalized().dot(a)) > 0.0001 and absf(n.normalized().dot(a)) < 0.9999:
				bad += 1
		check(bad == 0, "%s: %s: %d faces lie neither square to the pack's line nor along it" % [part, w.plates[i], bad])
		var sp := _span(plates[i], a)
		check(absf(sp.x - at) <= 0.001, "%s: %s starts %.1f mm from where the one before it ends (%s)" % [part,
			w.plates[i], (sp.x - at) * 1000.0, "the pressure plate" if i == 0 else w.plates[i - 1]])
		at = sp.y
	check(absf(at - f_in) <= 0.001, "%s: the pack ends %.1f mm from the frame plate's face" % [part, (at - f_in) * 1000.0])
	for gid in w.bolts:
		var found := false
		for f in ws.fasteners:
			if f.id != gid:
				continue
			found = true
			for t in f.items:
				var bb := AABB()
				var first := true
				for k in f.layers:
					var b: AABB = (t as Transform3D) * ((f.layers[k].mesh as ArrayMesh).get_aabb())
					bb = b if first else bb.merge(b)
					first = false
				var lo := INF
				var hi := -INF
				var wide := 0.0
				for j in 8:
					var c: Vector3 = bb.get_endpoint(j)
					lo = minf(lo, c.dot(a))
					hi = maxf(hi, c.dot(a))
				var along := bb.size.dot(a.abs())
				wide = (bb.size - a.abs() * along).length()
				check(along > 10.0 * wide, "%s: a bolt of %s runs along the pack's line" % [part, gid])
				check(lo < p_out and hi > f_out, "%s: a bolt of %s spans the pack from the pressure plate's outer face to the frame plate's (%.3f to %.3f against %.3f to %.3f)" % [
					part, gid, lo, hi, p_out, f_out])
				check(not bb.grow(-0.0005).intersects(pack), "%s: a bolt of %s passes beside the plates, not through them" % [part, gid])
		check(found, "%s: the bolt group %s" % [part, gid])

## A shell-and-tube exchanger's bundle (BUNDLES): each tube (a connected piece of the tubes' mesh) runs straight along
## the line from the stationary tubesheet to the floating one, starts within the stationary tubesheet's thickness
## (or at its outer face) and ends within the floating one's, and lies inside the floating tubesheet's rim and the
## shell's bore.
func _bundles(part: String, ws: Dictionary) -> void:
	if not BUNDLES.has(part):
		return
	var w: Dictionary = BUNDLES[part]
	var tubes := _tris_of(ws, w.tubes)
	var s0 := _tris_of(ws, w.sheets[0])
	var s1 := _tris_of(ws, w.sheets[1])
	var shell := _tris_of(ws, w.shell, ["hidden"])   # its bore
	for x in [tubes, s0, s1, shell]:
		check(not (x as Array).is_empty(), "%s: a part of the bundle is drawn" % part)
		if (x as Array).is_empty():
			return
	var centre := func(tris: Array) -> Vector3:
		var b := AABB(tris[0][0], Vector3.ZERO)
		for t in tris:
			for p: Vector3 in t:
				b = b.expand(p)
		return b.get_center()
	var c0: Vector3 = centre.call(s0)
	var a: Vector3 = ((centre.call(s1) as Vector3) - c0).normalized()
	var off := func(p: Vector3) -> float: return ((p - c0) - a * (p - c0).dot(a)).length()
	var sp0 := _span(s0, a)
	var sp1 := _span(s1, a)
	var rim := 0.0
	for t in s1:
		for p: Vector3 in t:
			rim = maxf(rim, off.call(p))
	var bore := INF
	for t in shell:
		for p: Vector3 in t:
			bore = minf(bore, off.call(p))
	# the tubes one by one: the triangles joined by their corners (to 0.01 mm)
	var parent := {}
	var find := func(k: String) -> String:
		while parent[k] != k:
			k = parent[k]
		return k
	for t in tubes:
		var ks: Array = []
		for p: Vector3 in t:
			var k := _q(p)
			if not parent.has(k):
				parent[k] = k
			ks.append(k)
		for j in range(1, 3):
			var x: String = find.call(ks[0])
			var y: String = find.call(ks[j])
			if x != y:
				parent[y] = x
	var groups := {}
	for t in tubes:
		var k: String = find.call(_q(t[0]))
		if not groups.has(k):
			groups[k] = []
		groups[k].append(t)
	check(groups.size() >= 2, "%s: the tubes are drawn (%d)" % [part, groups.size()])
	var bad := {}
	for k in groups:
		var tr: Array = groups[k]
		var sp := _span(tr, a)
		# its centre line at each end: the middle of its points there, across the line
		var ends := [Vector3.ZERO, Vector3.ZERO]
		var cnt := [0, 0]
		var reach := 0.0
		for t in tr:
			for p: Vector3 in t:
				var q: float = p.dot(a)
				for e in 2:
					if absf(q - (sp.x if e == 0 else sp.y)) <= 0.0001:
						ends[e] += (p - c0) - a * (p - c0).dot(a)
						cnt[e] += 1
				reach = maxf(reach, off.call(p))
		var e0: Vector3 = ends[0] / maxi(cnt[0], 1)
		var e1: Vector3 = ends[1] / maxi(cnt[1], 1)
		if e0.distance_to(e1) > 0.001:
			bad["a tube leans off the bundle's line (%.1f mm over its length)" % (e0.distance_to(e1) * 1000.0)] = true
		if sp.x < sp0.x - 0.001 or sp.x > sp0.y:
			bad["a tube starts outside the stationary tubesheet (%.1f mm from its outer face)" % ((sp.x - sp0.x) * 1000.0)] = true
		if sp.y > sp1.y + 0.001 or sp.y < sp1.x:
			bad["a tube ends outside the floating tubesheet (%.1f mm from its outer face)" % ((sp.y - sp1.y) * 1000.0)] = true
		if reach > rim + 0.0005 or reach > bore + 0.0005:
			bad["a tube reaches %.1f mm from the axis, past the floating tubesheet's rim (%.1f) or the shell's bore (%.1f)" % [
				reach * 1000.0, rim * 1000.0, bore * 1000.0]] = true
	for b in bad:
		check(false, "%s: %s" % [part, b])
	print("workshop: %s %d tubes from %s to %s" % [part, groups.size(), w.sheets[0], w.sheets[1]])

## Two unit vectors across d.
func _perp(d: Vector3) -> Array:
	var u := d.cross(Vector3(1, 0, 0) if absf(d.x) < 0.9 else Vector3(0, 1, 0)).normalized()
	return [u, d.cross(u).normalized()]

## Whether two components' cells pass through each other between two moments: each cell moved by its component's
## offset (a's relative to c's: r0 at the first, r1 at the second); a cell of a only meets c's cells near it, and
## where two cells' boxes meet more than before, their small triangles' boxes decide.
func _cells_pass(ca: Array, cc: Dictionary, r0: Vector3, r1: Vector3) -> bool:
	for x: Array in ca:
		var lo: Vector3 = x[0]
		var hi: Vector3 = x[1]
		var k := Vector3i((((lo + hi) * 0.5 + r1) / CELL).floor())
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					var y = cc.get(k + Vector3i(dx, dy, dz))
					if y == null:
						continue
					if _meet(lo + r1, hi + r1, y[0], y[1]) > 0.0 and _small_grow(x[2], y[2], r0, r1):
						return true
	return false

## Whether box a, moved from r0 to r1, comes to share more with box b.
func _grows(alo: Vector3, ahi: Vector3, blo: Vector3, bhi: Vector3, r0: Vector3, r1: Vector3) -> bool:
	var before := _meet(alo + r0, ahi + r0, blo, bhi)
	var now := _meet(alo + r1, ahi + r1, blo, bhi)
	return now > before + 0.02 * minf(_meet(alo, ahi, alo, ahi), _meet(blo, bhi, blo, bhi)) + 1e-12

## Whether a small triangle of one cell, moved by r1, cuts one of the other's (their boxes first).
func _small_grow(sa: PackedVector3Array, sb: PackedVector3Array, _r0: Vector3, r1: Vector3) -> bool:
	for i in range(0, sa.size(), 5):
		for j in range(0, sb.size(), 5):
			if _meet(sa[i] + r1, sa[i + 1] + r1, sb[j], sb[j + 1]) > 0.0 and \
					_tris_cut(sa[i + 2] + r1, sa[i + 3] + r1, sa[i + 4] + r1, sb[j + 2], sb[j + 3], sb[j + 4]):
				return true
	return false

## Whether two triangles cut each other: an edge of one through the other.
func _tris_cut(a0: Vector3, a1: Vector3, a2: Vector3, b0: Vector3, b1: Vector3, b2: Vector3) -> bool:
	for e in [[a0, a1], [a1, a2], [a2, a0]]:
		if Geometry3D.segment_intersects_triangle(e[0], e[1], b0, b1, b2) != null:
			return true
	for e in [[b0, b1], [b1, b2], [b2, b0]]:
		if Geometry3D.segment_intersects_triangle(e[0], e[1], a0, a1, a2) != null:
			return true
	return false

## How much two boxes (lo, hi) share: the product of their overlaps along each axis, where touching faces share
## nothing (each thick side is drawn in by 2 mm) and a flat side (under 4 mm thick) counts 1 mm when it lies inside
## the other's span, so a flat face crossing another is seen and two faces in one plane are not.
func _meet(alo: Vector3, ahi: Vector3, blo: Vector3, bhi: Vector3) -> float:
	var m := 1.0
	for i in 3:
		var a0: float = alo[i]
		var a1: float = ahi[i]
		var b0: float = blo[i]
		var b1: float = bhi[i]
		var at := a1 - a0 >= 0.004
		var bt := b1 - b0 >= 0.004
		if at:
			a0 += 0.002
			a1 -= 0.002
		if bt:
			b0 += 0.002
			b1 -= 0.002
		var o: float
		if at and bt:
			o = minf(a1, b1) - maxf(a0, b0)
		elif at:
			var c := (b0 + b1) * 0.5
			o = 0.001 if c > a0 and c < a1 else 0.0
		elif bt:
			var c := (a0 + a1) * 0.5
			o = 0.001 if c > b0 and c < b1 else 0.0
		else:
			o = 0.0   # (two flat sides in one axis: in one plane, or apart)
		if o <= 0.0:
			return 0.0
		m *= o
	return m

## A mesh's triangles, halved along their longest edge down to SMALL, each small one's box in the cell of the grid
## CELL wide its centre falls in: per cell [lo, hi, its small boxes (lo, hi, ...)] ({Vector3i: Array}), moved by p.
func _mesh_cells(mi: MeshInstance3D, p: Vector3, cells: Dictionary) -> void:
	var mesh: Mesh = mi.mesh
	for si in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(si)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for t in range(0, idx.size(), 3):
			var stack: Array = [[mi.transform * v[idx[t]] + p, mi.transform * v[idx[t + 1]] + p, mi.transform * v[idx[t + 2]] + p]]
			while not stack.is_empty():
				var tri: Array = stack.pop_back()
				var a: Vector3 = tri[0]
				var b: Vector3 = tri[1]
				var c: Vector3 = tri[2]
				var lab := a.distance_squared_to(b)
				var lbc := b.distance_squared_to(c)
				var lca := c.distance_squared_to(a)
				var m := maxf(lab, maxf(lbc, lca))
				if m > SMALL * SMALL:
					if m == lab:
						var q := (a + b) * 0.5
						stack.append([a, q, c]); stack.append([q, b, c])
					elif m == lbc:
						var q := (b + c) * 0.5
						stack.append([a, b, q]); stack.append([a, q, c])
					else:
						var q := (c + a) * 0.5
						stack.append([a, b, q]); stack.append([q, b, c])
					continue
				var lo := a.min(b).min(c)
				var hi := a.max(b).max(c)
				var key := Vector3i((((lo + hi) * 0.5) / CELL).floor())
				var e = cells.get(key)
				if e == null:
					cells[key] = [lo, hi, PackedVector3Array([lo, hi, a, b, c])]
				else:
					e[0] = (e[0] as Vector3).min(lo)
					e[1] = (e[1] as Vector3).max(hi)
					var smalls: PackedVector3Array = e[2]   # (a packed array is a value: append to it, then store it back)
					smalls.append_array(PackedVector3Array([lo, hi, a, b, c]))
					e[2] = smalls

## Each component's box at home, of its own meshes, in the root's frame (components are placed, never turned), and
## its pieces' boxes.
func _home_boxes(n: Node, root: Node3D, at: Vector3, out: Dictionary, pieces: Dictionary) -> void:
	for c in n.get_children():
		if not (c is Node3D and c.has_meta("explode")):
			continue
		var p: Vector3 = at + (c as Node3D).position
		var bb := AABB()
		var first := true
		var pc := {}
		for m in c.get_children():
			if m is MeshInstance3D and m.mesh != null:
				var b: AABB = (m as MeshInstance3D).transform * (m.mesh as Mesh).get_aabb()
				b.position += p
				bb = b if first else bb.merge(b)
				first = false
				_mesh_cells(m, p, pc)
		if not first:
			out[String(c.get_meta("id"))] = bb
			pieces[String(c.get_meta("id"))] = pc
		_home_boxes(c, root, p, out, pieces)

func _passes(part: String, a: String, c: String) -> bool:
	for k in PASSES:
		var s: PackedStringArray = String(k).split("|")
		if s[0] != part:
			continue
		for pr in [[a, c], [c, a]]:
			if pr[0] == s[1] and (pr[1] == s[2] or s[2].ends_with("*") and String(pr[1]).begins_with(s[2].trim_suffix("*"))):
				return true
	return false

## The boxes at slider value s: each moved by its own offset and its ancestors'.
func _boxes_at(spec: Dictionary, home: Dictionary, s: float) -> Dictionary:
	var off := Explode.offsets(spec, s)
	var out := {}
	for id in home:
		var o := Vector3.ZERO
		var at: String = id
		while at != "":
			o += off.get(at, Vector3.ZERO)
			at = spec.comps[at].parent
		var b: AABB = home[id]
		out[id] = AABB(b.position + o, b.size).grow(0.005)
	return out

func _overlap(a: AABB, b: AABB) -> float:
	var i := a.intersection(b)
	return _vol(i)

func _vol(b: AABB) -> float:
	return maxf(b.size.x, 0.0) * maxf(b.size.y, 0.0) * maxf(b.size.z, 0.0)

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

