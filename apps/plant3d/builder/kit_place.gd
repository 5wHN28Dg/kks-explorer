## The content build's equipment and pipes (docs/PLANT3D.md §3, §4, §9, §10; decision 0041): every piece of
## equipment made by the parts kit (apps/plant3d/kit) from its parameters, placed, and its static pieces instanced per
## part, material, visibility class, size bucket and 12 m cell (6 m for `detail` pieces, whose visibility range is
## measured to their cell's centre); its moving pieces as nodes of their own under the equipment's node, which is
## named by its KKS code (kit/README.md "Nodes"). Pipes are made here too, with their bends, cladding, colour bands,
## flow arrows, flanges and supports.
##
## Godot's headless renderer keeps no MultiMesh data, so the instances' transforms are saved as the node's meta
## "xforms" (12 floats each, MultiMesh's own layout) and app/plant.gd hands them to the MultiMesh when the plant loads.
extends RefCounted

const Kit = preload("res://kit/kit.gd")
const Mat = preload("res://kit/materials.gd")
const Geom = preload("res://builder/geom.gd")
const MB = preload("res://kit/mesh.gd")
const P_PIPE = preload("res://kit/parts_pipes.gd")
const P_VAL = preload("res://kit/parts_valves.gd")
const P_MACH = preload("res://kit/parts_machines.gd")
const P_HX = preload("res://kit/parts_heat.gd")
const P_SITE = preload("res://kit/parts_site.gd")
const Lightmap = preload("res://builder/lightmap.gd")

const CELL := 12.0          # the instancing cell (0041)
const SMALL_CELL := 6.0     # for `detail` pieces: a smaller box keeps their range close to the rule
## w, thickness, h: wide enough for a 12-character code in the characters below
const PLATE := {"small": Vector3(0.26, 0.002, 0.06), "large": Vector3(0.9, 0.004, 0.18)}
const PLATE_CHAR := {"small": 0.025, "large": 0.08}   # the code's character height (§10: 25 mm, legible at 8 px)
const WIDE_DECK := 8.0      # a deck at least this wide both ways is a roof or a floor: posts may stand on it
const MAX_POST := 40.0       # the tallest support post (steel trestles beside an HRSG reach its roof)
const SHAFT_MACHINES := ["gas_turbine", "generator", "turning_gear", "steam_turbine", "motor"]

var b                       # the plant builder
var seg_scale := 1.0
var used := {}              # kks -> {nozzle: outside diameter (m)}
var ctx_extra := {}         # kks -> the context the builder works out (trains, what stands above or below)
var cells := {}             # key -> {mesh, mat, cls, size, xf: Array}
var res_of := {}            # kks -> the kit's result (children read their parent's axis)
var tris_total := 0
var instances := 0
var supports := 0
var cells_made := 0
var unsupported: Array = []
## An interior's scene (PLANT3D.md §18.5, loaded near its doors after the start): left out of the lightmap's bake, its
## pieces take the sky's light in the vertex format and pipelines the instanced pieces already compiled at the start
## (no UV2: a mesh with UV2 and no bake would be a pipeline of its own, compiled when the trainee walks in)
var unbaked := false
## Materials whose pieces are never baked, instanced in their cells and lit by the sky and the sun: planting, whose
## leaves' area (two faces of every frond, lumps of every crown) was most of the site's lightmap texels and took the
## bake out of its memory (2026-10-22)
const UNBAKED := ["foliage"]

func _init(builder) -> void:
	b = builder

# ------------------------------------------------------------------ before the areas: what parts need to know

## The nozzles pipes end on, the shaft lines, and what each part stands under or over.
func prepare() -> void:
	Mat.colours.clear()
	for m in b.plant.get("media", {}):
		Mat.colours["medium_" + m] = Color.html(b.plant.media[m].band)
	for a in b.areas:
		for p in a.data.get("pipes", []):
			var od: float = (float(p.od_mm) if p.has("od_mm") else b._od(int(p.dn))) / 1000.0
			for end in [p.from, p.to]:
				if end.has("kks") and end.has("nozzle"):
					if not used.has(end.kks):
						used[end.kks] = {}
					used[end.kks][end.nozzle] = od
	_trains()
	for kks in b.equipment:
		var e: Dictionary = b.equipment[kks]
		var c: Dictionary = ctx_extra.get(kks, {})
		match e.part:
			"gas_turbine": _intake(kks, e, c)
			"steam_turbine": _exhaust(kks, e, c)
			"hrsg": _hrsg_ends(kks, e, c)
		if e.part in ["hrsg", "stack", "cooling_tower"]:
			c["decks"] = _decks(e)
		ctx_extra[kks] = c

## Machines on one shaft line (same area, height, heading line): one shaft height (the highest any of them needs),
## and each shaft reaches half way to its neighbour's.
func _trains() -> void:
	var lines := {}
	for kks in b.equipment:
		var e: Dictionary = b.equipment[kks]
		if not e.part in SHAFT_MACHINES or e.has("child"):
			continue
		var yaw := fposmod(float(e.yaw), 180.0)
		var d := Geom.heading(yaw)
		var lat := Vector2(e.pos.x, e.pos.y).dot(Vector2(d.y, -d.x))
		var key := "%s|%.1f|%d|%.0f" % [e.area, e.pos.z, int(round(yaw)), round(lat * 2.0)]
		if not lines.has(key):
			lines[key] = []
		lines[key].append(kks)
	for key in lines:
		var ms: Array = lines[key]
		if ms.size() < 2:
			continue
		var e0: Dictionary = b.equipment[ms[0]]
		var d := Geom.heading(fposmod(float(e0.yaw), 180.0))
		ms.sort_custom(func(p, q): return Vector2(b.equipment[p].pos.x, b.equipment[p].pos.y).dot(d) < Vector2(b.equipment[q].pos.x, b.equipment[q].pos.y).dot(d))
		var za := 0.0
		for k in ms:
			za = maxf(za, P_MACH.natural_axis(b.equipment[k].part, b.equipment[k].params))
		for i in ms.size():
			var e: Dictionary = b.equipment[ms[i]]
			var c: Dictionary = ctx_extra.get(ms[i], {})
			c["axis_z"] = za
			# the part's own +y may run along d or against it
			var fwd := Geom.heading(float(e.yaw)).dot(d) > 0.0
			var ext: Array = P_MACH.axial_extent(e.part, e.params)
			var s := Vector2(e.pos.x, e.pos.y).dot(d)
			var lo_d: float = s - (ext[0] if fwd else ext[1])   # its end towards -d
			var hi_d: float = s + (ext[1] if fwd else ext[0])
			var to_prev := 0.0
			var to_next := 0.0
			if i > 0:
				var p: Dictionary = b.equipment[ms[i - 1]]
				var pf := Geom.heading(float(p.yaw)).dot(d) > 0.0
				var pe: Array = P_MACH.axial_extent(p.part, p.params)
				var ps: float = Vector2(p.pos.x, p.pos.y).dot(d) + (pe[1] if pf else pe[0])
				if lo_d - ps < 15.0:
					to_prev = maxf(0.0, (lo_d - ps) * 0.5)
			if i < ms.size() - 1:
				var n: Dictionary = b.equipment[ms[i + 1]]
				var nf := Geom.heading(float(n.yaw)).dot(d) > 0.0
				var ne: Array = P_MACH.axial_extent(n.part, n.params)
				var ns: float = Vector2(n.pos.x, n.pos.y).dot(d) - (ne[0] if nf else ne[1])
				if ns - hi_d < 15.0:
					to_next = maxf(0.0, (ns - hi_d) * 0.5)
			c["shaft_lo"] = snappedf(to_prev if fwd else to_next, 0.01)
			c["shaft_hi"] = snappedf(to_next if fwd else to_prev, 0.01)
			ctx_extra[ms[i]] = c

## A gas turbine's top intake reaches up to the filter house standing over it.
func _intake(_kks: String, e: Dictionary, c: Dictionary) -> void:
	var L := float(e.params.get("length", 22))
	var p: Vector3 = e.pos + Geom.turn(Vector3(0, -L * 0.5 + L * 0.055, 0), e.yaw)
	for k in b.equipment:
		var f: Dictionary = b.equipment[k]
		if f.part != "filter_house" or f.area != e.area or f.pos.z <= e.pos.z + 3.0:
			continue
		var loc := Geom.turn(p - f.pos, -float(f.yaw))
		if absf(loc.x) <= float(f.params.get("width", 12)) * 0.5 and absf(loc.y) <= float(f.params.get("length", 14)) * 0.5:
			c["intake_top"] = snappedf(f.pos.z - e.pos.z, 0.01)

## A steam turbine's exhaust goes down to the condenser under it.
func _exhaust(_kks: String, e: Dictionary, c: Dictionary) -> void:
	for k in b.equipment:
		var f: Dictionary = b.equipment[k]
		if f.part != "condenser" or f.area != e.area:
			continue
		var top: float = f.pos.z + float(f.params.get("height", 16))
		var loc := Geom.turn(e.pos - f.pos, -float(f.yaw))
		if top < e.pos.z and absf(loc.x) <= float(f.params.get("width", 12)) * 0.5 + 0.5 and absf(loc.y) <= float(f.params.get("length", 14)) * 0.5 + 8.0:
			c["exhaust_to"] = snappedf(top - e.pos.z, 0.01)

## An HRSG's inlet takes the shape of the duct that ends at it; its outlet runs to the stack's size.
func _hrsg_ends(_kks: String, e: Dictionary, c: Dictionary) -> void:
	var L := float(e.params.get("length", 55))
	var li := float(e.params.get("inlet_duct", 15))
	var inlet: Vector3 = e.pos + Geom.turn(Vector3(0, -L * 0.5 - li, 0), e.yaw)
	for k in b.equipment:
		var f: Dictionary = b.equipment[k]
		if f.part == "duct":
			var route: Array = f.params.get("route", [])
			if route.size() < 2:
				continue
			var last: Vector3 = f.pos + Geom.turn(b._v3(route[-1]), f.yaw)
			if Vector2(last.x - inlet.x, last.y - inlet.y).length() < 3.0:
				c["inlet"] = [float(f.params.get("width", 10)), float(f.params.get("height", 10)), snappedf(last.z - e.pos.z, 0.01)]
		elif f.part == "stack" and f.area == e.area:
			c["stack_d"] = float(f.params.get("d", 7))

## The heights (above the part's origin) of the content's walkable surfaces over the part's footprint.
func _decks(e: Dictionary) -> Array:
	var sh: Dictionary = b.shape_of(e.part, e.params)
	var size: Vector3 = sh.size
	var out: Array = []
	for sf in b.surfaces:
		var hit := false
		for q in [Vector3(0, 0, 0), Vector3(size.x * 0.4, size.y * 0.4, 0), Vector3(-size.x * 0.4, -size.y * 0.4, 0), Vector3(size.x * 0.6, 0, 0), Vector3(0, size.y * 0.6, 0)]:
			var w: Vector3 = e.pos + Geom.turn(q, e.yaw)
			if Geom.in_poly(Vector2(w.x, w.y), sf.outline):
				hit = true
		if hit and sf.z > e.pos.z + 0.5:
			out.append(snappedf(sf.z - e.pos.z, 0.01))
	return out

# ------------------------------------------------------------------ equipment

## The part's frame in Godot's axes: the equipment's position and heading, or, for a part on a pipe, the pipe's
## direction (`fwd`) and an up across it.
func xform(e: Dictionary) -> Transform3D:
	var yf: Vector3
	var zu := Vector3(0, 0, 1)
	if e.has("fwd"):
		yf = e.fwd
		zu = e.get("up", Vector3(0, 0, 1))
	else:
		var h := Geom.heading(float(e.yaw))
		yf = Vector3(h.x, h.y, 0)
	var xr := yf.cross(zu).normalized()
	zu = xr.cross(yf).normalized()   # square to the pipe on a sloped run
	var basis := Basis(_gd(xr), _gd(zu), -_gd(yf))
	return Transform3D(basis, Geom.g([e.pos.x, e.pos.y, e.pos.z]))

static func _gd(v: Vector3) -> Vector3:
	return Vector3(v.x, v.z, -v.y)

## A part-frame vector from Godot's local axes.
static func _pv(v: Vector3) -> Vector3:
	return Vector3(v.x, -v.z, v.y)

func ctx_for(kks: String, e: Dictionary) -> Dictionary:
	var c: Dictionary = ctx_extra.get(kks, {}).duplicate()
	if used.has(kks):
		c["used"] = used[kks]
	for k in ["out", "floor_dz", "pipe_od"]:
		if e.has(k):
			c[k] = e[k]
	return c

## Makes one piece of equipment: its node (named by its code), its moving pieces, its plate, its collision; its static
## pieces go to the cells. Returns the node.
func equipment(parent: Node3D, kks: String, top: bool) -> Node3D:
	var e: Dictionary = b.equipment[kks]
	if not Kit.has_part(e.part):
		b._err("unsupported", kks, "the parts kit has no part '%s'" % e.part)
		return null
	if e.has("parent") and Kit.kit_json().parts.get(e.part, {}).get("group", "") == "instruments":
		_child_out(kks, e)
	var res := Kit.make(e.part, e.params, ctx_for(kks, e), seg_scale)
	res_of[kks] = res
	var xf := xform(e)
	var node := StaticBody3D.new()
	node.name = kks
	node.transform = xf
	parent.add_child(node)
	node.set_meta("kks", kks)
	node.set_meta("part", e.part)
	node.add_to_group("equipment", true)
	var box := AABB()
	var first := true
	for k in res.layers:
		var bb: AABB = res.layers[k].mesh.get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	if box.size.length() > 2.0 * CELL:
		# a large part (an HRSG, a cooling tower) stands in many cells: its pieces go to the cell they lie in
		var arrays := {}
		for k in res.layers:
			var L: Dictionary = res.layers[k]
			arrays[k] = {"mat": L.mat, "cls": L.cls, "size": L.size, "arrays": _turned(L.mesh.surface_get_arrays(0), xf.basis)}
		for piece in split_cells(arrays, xf.origin):
			var layers := Kit._meshes(piece.layers, Vector3.ZERO)
			for k in layers:
				_cell(layers[k], k, Transform3D(Basis(), piece.origin))
	else:
		for k in res.layers:
			_cell(res.layers[k], k, xf)
	tris_total += res.tris
	instances += 1
	# moving pieces: nodes of their own (kit/README.md "Moving parts")
	for mv in res.moving:
		var path: PackedStringArray = mv.name.split("/")
		var host: Node3D = node
		for i in range(path.size() - 1):
			host = host.get_node(NodePath(path[i]))
		var pivot_parent := Vector3.ZERO
		if host != node:
			pivot_parent = _node_pivot(host, node)
		var n := Node3D.new()
		n.name = path[-1]
		n.position = mv.pivot - pivot_parent
		n.set_meta("anim_axis", mv.axis)
		n.set_meta("anim_kind", mv.kind)
		n.set_meta("anim_travel", mv.travel)
		host.add_child(n)
		if path[-1] == "on":
			n.visible = false
		for k in mv.layers:
			var L: Dictionary = mv.layers[k]
			var mi := MeshInstance3D.new()
			mi.name = "mesh" if mv.layers.size() == 1 else ("mesh_" + L.mat)
			mi.mesh = L.mesh
			mi.material_override = b._mat(L.mat)
			Lightmap.mark(mi, false)   # it moves: the sky's light (builder/lightmap.gd mark)
			if L.cls == "detail":
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.add_to_group("detail", true)
				mi.set_meta("detail_size", L.size)
				mi.set_meta("box_half", 0.0)
			n.add_child(mi)
			var bb: AABB = L.mesh.get_aabb()
			bb.position += mv.pivot
			box = bb if first else box.merge(bb)
			first = false
	node.set_meta("aabb", box)
	# the tag plate; an instrument carries its own small tag with its code (as in the field) when the content names
	# no plate point for it
	var plate: String = e.get("plate", "none")
	if plate == "none" and Kit.kit_json().parts.get(e.part, {}).get("group", "") == "instruments" and not res.plates.is_empty():
		plate = res.plates.keys()[0]
	if plate != "none" and res.plates.has(plate):
		_plate(node, xf, res.plates[plate], kks)
	# collision: the parts' solids (small parts on pipes and machines are not solid)
	if top or box.size.length() > 1.0:
		add_solids(node, res.solids, Transform3D.IDENTITY)
	# the floating label (as before the kit): the code and the name over the part
	var lab := Label3D.new()
	lab.name = "label"
	lab.text = "%s\n%s" % [kks, e.name]
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.pixel_size = 0.004 if top else 0.0015
	lab.font_size = 40
	lab.outline_size = 8
	lab.visibility_range_end = 30.0 if top else 6.0
	lab.position = Vector3(box.get_center().x, box.end.y + (0.6 if top else 0.15), box.get_center().z) if not first else Vector3(0, 1, 0)
	node.add_child(lab)
	return node

## The kit's solids (part frame) as collision shapes under `node`, placed by `xf` (the part's frame in the node's).
func add_solids(node: Node3D, solids: Array, xf: Transform3D) -> void:
	for s in solids:
		var cs := CollisionShape3D.new()
		if s.kind == "obox":
			var bs := BoxShape3D.new()
			bs.size = s.size
			cs.shape = bs
			var B: Basis = s.basis
			# the shape's own axes are the basis' (in Godot's terms), its size along them
			cs.transform = Transform3D(Basis(Kit._gv(B.x), Kit._gv(B.y), Kit._gv(B.z)), Kit._gv(s.c))
		elif s.kind == "box":
			var lo: Vector3 = Kit._gv(s.lo)
			var hi: Vector3 = Kit._gv(s.hi)
			var bs := BoxShape3D.new()
			bs.size = (hi - lo).abs().max(Vector3(0.05, 0.05, 0.05))
			cs.shape = bs
			cs.position = (lo + hi) * 0.5
		else:
			var c2 := CylinderShape3D.new()
			c2.radius = s.r
			c2.height = maxf(s.a.distance_to(s.b), 0.05)
			cs.shape = c2
			cs.transform = b._along(Kit._gv(s.a), Kit._gv(s.b))
		cs.transform = xf * cs.transform
		node.add_child(cs)

## A structure the parts kit draws (the site's and the camp's, PLANT3D.md §18.6: planting, vehicles, gates, canopies,
## furniture): a body named by its id holding its solids, its static pieces to the cells like equipment's. A planting
## along a `route` is one plant every `spacing` metres along it (the species' usual spacing for 0), each with a
## variant of its shape and a heading of its own (a row is not one plant copied), and the row's drip line.
func structure(parent: Node3D, s: Dictionary) -> Node3D:
	var pr: Dictionary = b.params_of(s.part, s.get("params", {}))
	var at: Vector3 = b._v3(s.get("at", [0, 0, 0]))
	var yaw := float(s.get("yaw", 0))
	var body := StaticBody3D.new()
	body.name = s.id
	body.set_meta("structure", s.part)
	parent.add_child(body)
	var places: Array = []   # [plant position, yaw, params]
	if s.part == "planting":
		places = planting_places(s, pr)
		var route: Array = pr.route
		for i in range(route.size() - 1):
			var a := at + Geom.turn(b._v3(route[i]), yaw)
			var c := at + Geom.turn(b._v3(route[i + 1]), yaw)
			var L := a.distance_to(c)
			if L < 0.05:
				continue   # one plant: no drip line along a row
			# in DRIP_UNIT pieces of one mesh along it (instanced, held once), each in its own cell (a detail piece's
			# range is measured to its cell), the remainder its own
			var d := (c - a) / L
			var xf_dir := Basis(Vector3.UP, atan2(d.y, d.x))   # the unit's x along the row (Godot: plant y is -z)
			var n := int(floor(L / DRIP_UNIT + 1e-6))
			for j in n + 1:
				var len := minf(DRIP_UNIT, L - j * DRIP_UNIT)
				if len < 0.05:
					break
				var p0 := a + d * (j * DRIP_UNIT)
				for k in _drip_layers(len):
					_cell(_drip_layers(len)[k], k, Transform3D(xf_dir, Geom.g([p0.x, p0.y, p0.z])))
	elif s.part == "kerb":
		places = kerb_places(s, pr)
	else:
		places.append([at, yaw, pr])
	for pl in places:
		var res := Kit.make(s.part, pl[2], {}, seg_scale)
		var xf := xform({"pos": pl[0], "yaw": pl[1]})
		for k in res.layers:
			_cell(res.layers[k], k, xf)
		tris_total += res.tris
		instances += 1
		add_solids(body, res.solids, Transform3D(xf.basis, xf.origin))
	return body

## A row's drip line in pieces this long (one mesh, instanced along every row).
const DRIP_UNIT := 4.0
var _drip := {}
## The drip line's meshes for a piece `len` long along x (cached by length).
func _drip_layers(len: float) -> Dictionary:
	var key := snappedf(len, 0.01)
	if not _drip.has(key):
		var mb = MB.new()
		P_SITE.drip_line(mb, Vector3.ZERO, Vector3(key, 0, 0))
		_drip[key] = Kit._meshes(mb.finish(), Vector3.ZERO)
	return _drip[key]

## How many shapes a species has (a plant's `variant`): enough that a row is not one plant copied, few enough that the
## scenes hold each once (a variant is a mesh of its own).
const VARIANTS := 4

## A kerb along its route as KERB_UNIT pieces (one stripe of each colour), the remainder of each straight piece its own:
## the same few meshes instanced along every road, not one mesh per kerb.
const KERB_UNIT := 2.0
func kerb_places(s: Dictionary, pr: Dictionary) -> Array:
	var at: Vector3 = b._v3(s.get("at", [0, 0, 0]))
	var yaw := float(s.get("yaw", 0))
	var out: Array = []
	var route: Array = pr.route
	for i in range(route.size() - 1):
		var a := at + Geom.turn(b._v3(route[i]), yaw)
		var c := at + Geom.turn(b._v3(route[i + 1]), yaw)
		var L := a.distance_to(c)
		if L < 0.05:
			continue
		var d := (c - a) / L
		var heading := rad_to_deg(atan2(d.x, d.y))
		var n := int(floor(L / KERB_UNIT + 1e-6))
		for k in n + 1:
			var len := minf(KERB_UNIT, L - k * KERB_UNIT)
			if len < 0.05:
				break
			var p := pr.duplicate()
			p["route"] = [[0, 0, 0], [0, snappedf(len, 0.01), 0]]
			out.append([a + d * (k * KERB_UNIT), heading, p])
	return out

## Where a row's plants stand: along the route (relative to the structure's `at`, turned by its `yaw`) from its first
## point, one every spacing metres, the last one at most half a spacing from its end; [position, yaw, params].
func planting_places(s: Dictionary, pr: Dictionary) -> Array:
	var at: Vector3 = b._v3(s.get("at", [0, 0, 0]))
	var yaw := float(s.get("yaw", 0))
	var sp := float(pr.get("spacing", 0.0))
	if sp <= 0.0:
		sp = float(P_SITE.SPECIES.get(String(pr.species), P_SITE.SPECIES.date_palm).spacing)
	var pts: Array = []
	for q in pr.route:
		pts.append(at + Geom.turn(b._v3(q), yaw))
	var out: Array = []
	var carry := 0.0
	var k := 0
	var seed := hash(s.id)
	for i in range(pts.size() - 1):
		var a: Vector3 = pts[i]
		var c: Vector3 = pts[i + 1]
		var L := a.distance_to(c)
		var t := carry
		if L < 1e-6 and i > 0:
			continue
		while t <= L + 1e-6:
			var p := pr.duplicate()
			p.erase("route")
			p.erase("spacing")
			p["variant"] = (seed + k) % VARIANTS
			out.append([a.lerp(c, t / maxf(L, 1e-6)), float((seed / 7 + k * 137) % 360), p])
			k += 1
			t += sp
		carry = t - L
	return out

func _node_pivot(n: Node3D, root: Node3D) -> Vector3:
	var p := Vector3.ZERO
	var c: Node = n
	while c != root and c is Node3D:
		p += (c as Node3D).position
		c = c.get_parent()
	return p

## A child part's instrument faces away from its parent's centre line (the parent's `axis`).
func _child_out(_kks: String, e: Dictionary) -> void:
	var pr: Dictionary = res_of.get(e.parent, {})
	if pr.is_empty() or e.has("out"):
		return
	var a := _pv(pr.axis[0])
	var bb := _pv(pr.axis[1])
	var at: Vector3 = e.at
	var t := clampf((at - a).dot(bb - a) / maxf((bb - a).length_squared(), 1e-9), 0.0, 1.0)
	var o := at - a.lerp(bb, t)
	if o.length() < 0.05:
		o = Vector3(0, 0, 1)
	o = o.normalized()
	# from the parent's frame to the child's (turned by its own yaw)
	e["out"] = Geom.turn(o, -float(e.get("own_yaw", 0.0)))
	e["floor_dz"] = -float(at.z)

func _plate(node: Node3D, _xf: Transform3D, pl: Dictionary, kks: String) -> void:
	var kind: String = pl.kind
	var s: Vector3 = PLATE[kind]
	var n: Vector3 = pl.normal
	var up := Vector3(0, 1, 0)
	if absf(n.dot(up)) > 0.9:
		up = Vector3(0, 0, -1)
	var x := up.cross(n).normalized()
	var y := n.cross(x).normalized()
	var at: Vector3 = pl.at + n * (s.y * 0.5 + 0.004)
	var pxf := Transform3D(Basis(x, y, n), at)
	var world: Transform3D = node.transform * pxf
	var pm: Dictionary = _plate_mesh(kind)
	_cell(pm, pm.mesh.resource_name, world)
	var lab := Label3D.new()
	lab.name = "plate"
	lab.text = kks
	var ch: float = PLATE_CHAR[kind]
	lab.font_size = 48
	lab.pixel_size = ch / 34.0
	lab.modulate = Color(0.02, 0.02, 0.02)
	lab.outline_size = 0
	lab.double_sided = false
	lab.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	lab.transform = Transform3D(Basis(x, y, n), at + n * (s.y * 0.5 + 0.002))
	lab.add_to_group("legible", true)
	lab.set_meta("legible_size", ch)
	lab.visibility_range_end = ch * 640.0 / 8.0
	lab.visibility_range_end_margin = lab.visibility_range_end * 0.1
	lab.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	node.add_child(lab)

var _plates := {}
## A tag plate (white, a black border) in its own frame: x across, y up, z out of its face. Built in part axes
## (x, y = -z, z = y), one mesh: both materials resolve to `plain`.
func _plate_mesh(kind: String) -> Dictionary:
	if not _plates.has(kind):
		var s: Vector3 = PLATE[kind]
		var m := MB.new()
		m.use("plate", "identify")
		m.box(Vector3.ZERO, Vector3(s.x, s.y, s.z))
		m.use("plate_border", "identify")
		var t := s.z * 0.06
		for z: float in [-1.0, 1.0]:
			m.box(Vector3(0, -(s.y * 0.5 + 0.0005), z * (s.z * 0.5 - t * 0.5)), Vector3(s.x, 0.001, t))
		for x: float in [-1.0, 1.0]:
			m.box(Vector3(x * (s.x * 0.5 - t * 0.5), -(s.y * 0.5 + 0.0005), 0), Vector3(t, 0.001, s.z))
		_plates[kind] = Kit._meshes(m.finish(), Vector3.ZERO).values()[0]
	return _plates[kind]

# ------------------------------------------------------------------ safety signs

const SIGN_BACK := 0.13      # metres out from the wall's line: its face (walls are 0.25 thick on it), and a gap
const SIGN_THICK := 0.02     # the board
const SIGN_SYMBOLS := ["M003"]

## The sign's layout for text `text_w` wide in a font of `size` (its em, as Label3D's pixel_size × font_size): {w, h, lo (the board's bottom
## below the text's centre line), disc (the symbol's centre above it), r (its radius), face (the board's face out
## from the wall's line)}. As ISO 3864-1 lays a sign out: the symbol above its supplementary text, on one white
## board. The symbol is three lines of text across, so it is made out at least as far away as the text is read.
static func sign_layout(text_w: float, size: float) -> Dictionary:
	var m := 0.4 * size
	var r := 1.5 * size
	var w := maxf(text_w, 2.0 * r) + 2.0 * m
	var lo := size * 0.5 + m
	return {"w": w, "h": lo + size * 0.5 + m + 2.0 * r + m, "lo": lo, "disc": size * 0.5 + m + r, "r": r,
		"face": SIGN_BACK + SIGN_THICK}

## The sign's board with its symbol, in its own frame (x across, y up, z out of the wall, metres from the point on
## the wall's line), drawn by us (no artwork: CC0 by construction). Built in part axes (x, y = -z, z = y), one mesh:
## all of it is `sign_board` (retroreflective sheeting, its colours in the vertices: kit/materials.gd), so in its cell
## it is one draw call, merged with the other signs' boards there.
## M003 ("wear ear protection", ISO 7010): a blue disc, and on it in white a head with ear defenders: the head and
## its neck, the shoulders, two ear cups clear of the head and the headband over it, clear of the head's top.
static func sign_mesh(symbol: String, text_w: float, size: float) -> MB:
	assert(symbol in SIGN_SYMBOLS)
	var L := sign_layout(text_w, size)
	var m := MB.new()
	var f: float = L.face
	m.use("sign_board", "identify")
	m.box(Vector3(0, -(SIGN_BACK + SIGN_THICK * 0.5), -L.lo + L.h * 0.5), Vector3(L.w, SIGN_THICK, L.h))
	var out := Vector3(0, -1, 0)
	var R: float = L.r
	var cy: float = L.disc
	# a point of the symbol (in its radii, x across, y up) at depth d in front of the board, in part axes
	var at := func(x: float, y: float, d: float) -> Vector3: return Vector3(x * R, -(f + d), cy + y * R)
	var ellipse := func(cx: float, cy2: float, rx: float, ry: float, d: float) -> Array:
		var pts := []
		for i in 32:
			var t := TAU * i / 32.0
			pts.append(at.call(cx + rx * cos(t), cy2 + ry * sin(t), d))
		return pts
	m.use("sign_board", "identify")
	m.colour = Mat.PAINT_SIGN_BLUE   # the board's material, the blue in the vertices: one layer, one draw call
	m.disk(at.call(0, 0, 0.005), out, R, 48)
	m.use("sign_board", "identify")
	var d := 0.01
	# the shoulders: inside the disc's 0.86 below a gentle rise to the neck (convex: one fan)
	var sh := []
	var xe := sqrt(0.86 * 0.86 - 0.62 * 0.62)
	var a0 := atan2(-0.62, -xe)
	var a1 := atan2(-0.62, xe)
	for i in 17:
		var t := lerpf(a0, a1, i / 16.0)
		sh.append(at.call(0.86 * cos(t), 0.86 * sin(t), d))
	for i in range(1, 12):
		var x := lerpf(xe, -xe, i / 12.0)
		sh.append(at.call(x, -0.62 + 0.10 * cos(PI * 0.5 * x / xe), d))
	m.poly(sh, out)
	m.poly([at.call(-0.12, -0.6, d), at.call(0.12, -0.6, d), at.call(0.12, -0.2, d), at.call(-0.12, -0.2, d)], out)
	m.poly(ellipse.call(0.0, 0.02, 0.25, 0.34, d), out)                      # the head
	for sx: float in [-1.0, 1.0]:
		m.poly(ellipse.call(sx * 0.39, 0.0, 0.10, 0.17, d), out)            # an ear cup
	for i in 16:                                                             # the headband
		var t0 := PI * i / 16.0
		var t1 := PI * (i + 1) / 16.0
		m.poly([at.call(0.43 * cos(t0), 0.43 * sin(t0), d), at.call(0.50 * cos(t0), 0.50 * sin(t0), d),
			at.call(0.50 * cos(t1), 0.50 * sin(t1), d), at.call(0.43 * cos(t1), 0.43 * sin(t1), d)], out)
	return m

var _signs := {}
## A safety sign's board and symbol at `xf` (the sign's frame on the wall's line), into the cells.
func sign_board(xf: Transform3D, symbol: String, text_w: float, size: float) -> void:
	var key := "sign|%s|%.3f|%.3f" % [symbol, text_w, size]
	if not _signs.has(key):
		_signs[key] = Kit._meshes(sign_mesh(symbol, text_w, size).finish(), Vector3.ZERO).values()
	# each material's layer (the white and the symbol's colour) merged with its cell's layer of that material; a group
	# of signs' boards alone casts no shadow (flat on its wall: the shadow pass would draw it for nothing)
	for L in _signs[key]:
		cells[_cell(L, L.mesh.resource_name, xf)]["sign"] = true

# ------------------------------------------------------------------ the cells

func _cell(L: Dictionary, key: String, xf: Transform3D) -> String:
	var cls: String = L.cls
	var size := SMALL_CELL if cls == "detail" else CELL
	var c := Vector2i(int(floor(xf.origin.x / size)), int(floor(xf.origin.z / size)))
	var k := "%d|%s|%d|%d" % [L.mesh.get_instance_id(), key, c.x, c.y]
	if not cells.has(k):
		cells[k] = {"mesh": L.mesh, "mat": L.mat, "cls": cls, "size": L.size, "xf": []}
	cells[k].xf.append(xf)
	return k

## The cells of an area under its node "kit": in each cell, the meshes that stand there once are merged per material
## and size bucket into one mesh (with LODs made again for it), those that stand there more than once are instanced
## (MultiMesh). Either way one draw call per (mesh, cell) or per (material, bucket, cell).
func flush(root: Node3D) -> int:
	var kit := Node3D.new()
	kit.name = "kit"
	root.add_child(kit)
	var n := 0
	var merge := {}   # "layer|cell" -> [entries]
	for k in cells:
		var c: Dictionary = cells[k]
		# planting is instanced, never merged: a row's plants share a few meshes (their variants), which the scene then
		# holds once, not once per cell (merged, the site's palms and tamarisks were most of its scenes' bytes)
		if c.xf.size() == 1 and not c.mat in UNBAKED:
			var parts: PackedStringArray = k.split("|")
			var mk := "|".join(parts.slice(1))
			if not merge.has(mk):
				merge[mk] = []
			merge[mk].append(c)
		else:
			_quiet = c.get("sign", false)
			_emit(kit, c.mesh, c.mat, c.cls, c.size, c.xf, n)
			n += 1
	for mk in merge:
		var group: Array = merge[mk]
		_quiet = group.all(func(c): return c.get("sign", false))
		var cls: String = "identify" if group.any(func(c): return c.cls == "identify") else group[0].cls
		if cls == "detail":
			# detail pieces are small (bolts, fins): the sky's light, never given lightmap texels
			if group.size() == 1:
				_emit(kit, group[0].mesh, group[0].mat, group[0].cls, group[0].size, group[0].xf, n)
				n += 1
				continue
		# one mesh for them all, around the first one's origin
		var o: Vector3 = group[0].xf[0].origin
		var st := SurfaceTool.new()
		for c in group:
			var t: Transform3D = c.xf[0]
			st.append_from(c.mesh, 0, Transform3D(t.basis, t.origin - o))
		var arr := st.commit_to_arrays()
		var size := INF
		for c in group:
			size = minf(size, c.size)
		if cls == "form" and not unbaked and not group[0].mat in UNBAKED:
			# a static mesh standing once in its cell: the bake lights it (builder/lightmap.gd). Identify pieces
			# (tag plates, bands, arrows) are not: a texel of a third of a metre would grey a white plate behind
			# its code; they take the sky's light like the instanced pieces
			var lit := Lightmap.unwrap(arr, Lightmap.TEXEL * b.texel_scale, cls != "identify")
			if lit != null:
				_emit_static(kit, lit, group[0].mat, cls, o, n)
				n += 1
				continue
		var im := ImporterMesh.new()
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr)
		if cls != "identify":   # identify pieces keep every triangle (§10)
			im.generate_lods(25.0, 60.0, [])
		_emit(kit, im.get_mesh(), group[0].mat, cls, size, [Transform3D(Basis(), o)], n)
		n += 1
	_quiet = false
	var groups := merge.size()
	var widest := 0.0
	for c in kit.get_children():
		if c.is_in_group("detail"):
			widest = maxf(widest, float(c.get_meta("box_half")))
	print("build: area %s: widest detail cell %.1f m (half diagonal)" % [root.name, widest])
	print("build: area %s: %d draw meshes (%d cells' merged groups)" % [root.name, n, groups])
	cells.clear()
	cells_made += n
	return n

var _quiet := false   # what flush emits now is signs' boards alone: no shadow

## A static mesh with lightmap UV2, standing once (group "kit_static"): a MeshInstance3D, which LightmapGI bakes.
func _emit_static(kit: Node3D, mesh: Mesh, mat: String, cls: String, o: Vector3, n: int) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "%s_%s_%d" % [mat, cls, n]
	mi.mesh = mesh
	mi.position = o
	mi.material_override = b._mat(mat)
	mi.set_meta("box", Transform3D(Basis(), o) * mesh.get_aabb())
	mi.add_to_group("kit_static", true)
	Lightmap.mark(mi, true)
	if _quiet:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	kit.add_child(mi)

func _emit(kit: Node3D, mesh: Mesh, mat: String, cls: String, size: float, xfs: Array, n: int) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	var buf := PackedFloat32Array()
	var box := AABB()
	var mb: AABB = mesh.get_aabb()
	for i in xfs.size():
		var t: Transform3D = xfs[i]
		var bs := t.basis
		buf.append_array([bs.x.x, bs.y.x, bs.z.x, t.origin.x, bs.x.y, bs.y.y, bs.z.y, t.origin.y, bs.x.z, bs.y.z, bs.z.z, t.origin.z])
		box = (t * mb) if i == 0 else box.merge(t * mb)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "%s_%s_%d" % [mat, cls, n]
	mmi.multimesh = mm
	mmi.material_override = b._mat(mat)
	mmi.set_meta("xforms", buf)
	mmi.set_meta("count", xfs.size())
	mmi.set_meta("box", box)
	mmi.add_to_group("kit_cells", true)
	Lightmap.mark(mmi, false)
	if _quiet:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if cls == "detail":
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.add_to_group("detail", true)
		mmi.set_meta("detail_size", size)
		mmi.set_meta("box_half", box.size.length() * 0.5)
	kit.add_child(mmi)

# ------------------------------------------------------------------ pipes

## The pipe's route (plant coordinates), its pieces, valves and instruments on it, its supports.
func pipe(parent: Node3D, p: Dictionary) -> void:
	var route: Array = [b._end_point(p.from)]
	for q in p.get("points", []):
		route.append(b._v3(q))
	route.append(b._end_point(p.to))
	for q in route:
		if q == Vector3.INF:
			b._err("bad_ref", p.kks, "a pipe end names a nozzle the kit doesn't have")
			return
	var od: float = (float(p.od_mm) if p.has("od_mm") else b._od(int(p.dn))) / 1000.0
	var ins: float = float(p.get("insulation_mm", 0)) / 1000.0
	var buried := {}
	for r in p.get("buried", []):
		for s in range(int(r[0]), int(r[1]) + 1):
			buried[s] = true
	# the collision (as before the kit): a cylinder per straight segment above ground
	var body := StaticBody3D.new()
	body.name = p.kks
	body.set_meta("kks", p.kks)
	body.set_meta("medium", p.medium)
	body.add_to_group("pipes", true)
	parent.add_child(body)
	for i in range(route.size() - 1):
		if buried.has(i):
			continue
		var a := Geom.g([route[i].x, route[i].y, route[i].z])
		var c := Geom.g([route[i + 1].x, route[i + 1].y, route[i + 1].z])
		if a.distance_to(c) < 0.005:
			continue
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = od * 0.5 + ins
		sh.height = a.distance_to(c)
		cs.shape = sh
		cs.transform = b._along(a, c)
		body.add_child(cs)
	# valves and instruments on the pipe at their fraction of its length; bare pipe round them when insulated
	var total := 0.0
	for i in range(route.size() - 1):
		total += route[i].distance_to(route[i + 1])
	var gaps: Array = []
	for v in p.get("valves", []) + p.get("parts", []):
		var want := float(v.at) * total
		var acc := 0.0
		for i in range(route.size() - 1):
			var l: float = route[i].distance_to(route[i + 1])
			if acc + l >= want or i == route.size() - 2:
				var q: Vector3 = route[i].lerp(route[i + 1], clampf((want - acc) / maxf(l, 1e-6), 0, 1))
				var d: Vector3 = (route[i + 1] - route[i]).normalized()
				var up := Vector3(0, 0, 1)
				if absf(d.z) > 0.9:   # a vertical pipe: the part's up lies across it, towards the north
					up = Vector3(0, 1, 0)
				var pr := Kit.params_of(v.part, v.get("params", {}))
				var e := {"pos": q, "yaw": 0.0, "fwd": d, "up": up, "part": v.part, "params": pr, "area": "",
					"name": v.get("name", ""), "child": true, "plate": v.get("plate", "none"), "pipe_od": od + 2.0 * ins}
				if v.has("side"):
					var right := d.cross(up).normalized()
					var sd: Vector3 = {"top": up, "bottom": -up, "right": right, "left": -right}.get(v.side, up)
					e["pos"] = q + sd * (od * 0.5 + ins)
					# the instrument's own frame is the pipe's: out is the side, in that frame (x right, y along, z up)
					e["out"] = Vector3(sd.dot(right), sd.dot(d), sd.dot(up))
					gaps.append([want - 0.12, want + 0.12])
				else:
					var F := P_VAL.ftf(v.part, od) if v.part.begins_with("valve") else od * 1.5
					gaps.append([want - F * 0.5 - 0.15, want + F * 0.5 + 0.15])
				b.equipment[v.kks] = e
				equipment(parent, v.kks, false)
				break
			acc += l
	# flanges where the pipe meets a nozzle
	var flanges: Array = []
	if p.from.has("nozzle"):
		flanges.append([route[0], (route[1] - route[0]).normalized()])
	if p.to.has("nozzle"):
		flanges.append([route[-1], (route[-2] - route[-1]).normalized()])
	var sup := _supports(p, route, od * 0.5 + ins, buried)
	var m := MB.new()
	m.seg_scale = seg_scale
	var origin: Vector3 = route[0]
	var group: String = b.plant.media[p.medium].get("group", "")
	P_PIPE.pipe(m, route, {"od": od, "ins": ins, "band": "medium_" + p.medium, "paint": Mat.pipe_paint(group), "arrows": float(p.get("arrows", 0)),
		"buried": buried, "gaps": gaps, "flanges": flanges, "supports": sup,
		"bend": {"3d": 3.0, "5d": 5.0}.get(p.get("bend", ""), 1.5)}, origin)
	_stencils(parent, p, route, od, ins, buried, gaps)
	# a pipe runs through many cells: its triangles go to the cell they lie in (0041's grouping, culling and LOD per
	# cell, a detail range measured from its own cell)
	var o := Geom.g([origin.x, origin.y, origin.z])
	for piece in split_cells(m.finish(), o):
		var layers := Kit._meshes(piece.layers, Vector3.ZERO)
		var xf := Transform3D(Basis(), piece.origin)
		for k in layers:
			_cell(layers[k], k, xf)
			tris_total += layers[k].tris[0]

## The straight pieces of a pipe that carry colour bands, as kit/parts_pipes.gd pipe() makes them (the runs between
## the bends' tangents, split at the bare stretches round valves and instruments when insulated): {a, d, len, k, bands
## (centres along the piece), bw, arrow}. The stencilled names are placed from these (between bands, clear of arrows).
static func band_pieces(route: Array, od: float, ins: float, p: Dictionary, buried: Dictionary, gaps: Array) -> Array:
	var out: Array = []
	var pc: Dictionary = P_PIPE.pieces(route, od * float({"3d": 3.0, "5d": 5.0}.get(p.get("bend", ""), 1.5)))
	var every: float = float(p.get("arrows", 0))
	var band_every := every if every > 0.0 else 12.0
	var bw := clampf(od * 0.6, 0.12, 0.5)
	var arrow := clampf(od * 1.4, 0.3, 1.2) + 0.05 if every > 0.0 else 0.0
	for run in pc.runs:
		if buried.has(run.seg):
			continue
		var a: Vector3 = run.a
		var len: float = a.distance_to(run.b)
		if len < 1e-3:
			continue
		var d: Vector3 = (run.b - a) / len
		var cuts: Array = [[0.0, len]]
		if ins > 0.0:
			cuts = []
			var t := 0.0
			var gs: Array = []
			for g in gaps:
				var g0: float = clampf(float(g[0]) - run.s0, 0.0, len)
				var g1: float = clampf(float(g[1]) - run.s0, 0.0, len)
				if g1 > g0 + 1e-3:
					gs.append([g0, g1])
			gs.sort_custom(func(x, y): return x[0] < y[0])
			for g in gs:
				if g[0] > t:
					cuts.append([t, g[0]])
				t = maxf(t, g[1])
			if t < len:
				cuts.append([t, len])
		for c in cuts:
			var l2: float = c[1] - c[0]
			if l2 < bw * 4.0:
				continue
			var k := maxi(1, int(round(l2 / band_every)))
			var bands: Array = []
			for i in k:
				bands.append(l2 * (i + 0.5) / k)
			out.append({"a": a + d * c[0], "d": d, "len": l2, "k": k, "bands": bands, "bw": bw, "arrow": arrow,
				"s0": float(run.s0) + float(c[0])})
	return out

## The service name stencilled in black on a pipe's sides (plant.json's medium `name`), as plants label their lines
## beside the flow arrows: on each straight horizontal run long enough to carry it, between the colour bands, clear
## of the bends and of the valves and instruments (`gaps`), on both sides at the pipe's middle. The same label as a
## safety sign's text (no outline, black, one-sided: no pipeline of its own), drawn within STENCIL_RANGE.
const STENCIL_RANGE := 30.0
const STENCIL_MIN_R := 0.1
## Where a pipe's name goes: [point (plant coordinates, on the axis), direction] for each place on a level piece of
## the pipe between its colour bands (or a quarter of the way along a piece with one band), its `w` metres clear of
## the bands, their arrows, the piece's ends (the bends) and the valves and instruments (`gaps`).
static func stencil_places(route: Array, od: float, ins: float, p: Dictionary, buried: Dictionary, gaps: Array, w: float) -> Array:
	var out: Array = []
	for pc in band_pieces(route, od, ins, p, buried, gaps):
		var d: Vector3 = pc.d
		var L: float = pc.len
		if absf(d.z) > 0.02:
			continue                       # level pieces only (a label stands level)
		var places: Array = []
		for j in range(1, pc.k):
			places.append(L * j / pc.k)
		if pc.k == 1:
			places = [L * 0.25]
		for t in places:
			if t - w * 0.5 < 0.3 or t + w * 0.5 > L - 0.3:
				continue
			var hits_band := false
			for cb in pc.bands:
				if t + w * 0.5 + 0.15 > cb - pc.bw * 0.5 and t - w * 0.5 - 0.15 < cb + pc.bw * 0.5 + 0.05 + pc.arrow:
					hits_band = true
			if hits_band:
				continue
			var sm: float = pc.s0 + t      # clear of the valves and instruments on a bare pipe too
			if gaps.any(func(gp): return gp[0] < sm + w * 0.5 + 0.2 and gp[1] > sm - w * 0.5 - 0.2):
				continue
			out.append([pc.a + d * t, d])
	return out

func _stencils(parent: Node3D, p: Dictionary, route: Array, od: float, ins: float, buried: Dictionary, gaps: Array) -> int:
	var text := String(b.plant.media[p.medium].get("name", ""))
	var rr := od * 0.5 + ins
	if text == "" or rr < STENCIL_MIN_R:
		return 0
	var size := clampf(rr * 0.55, 0.08, 0.3)
	var w := ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x * size / 64.0
	var n := 0
	for pl in stencil_places(route, od, ins, p, buried, gaps, w):
		var mid: Vector3 = pl[0]
		var d: Vector3 = pl[1]
		var side := Vector3(-d.y, d.x, 0.0)
		for sgn in [1.0, -1.0]:
			var nrm: Vector3 = side * sgn
			var l := Label3D.new()
			l.name = "stencil"
			l.text = text
			l.font_size = 64
			l.pixel_size = size / 64.0
			l.double_sided = false
			l.outline_size = 0
			l.modulate = Color(0.02, 0.02, 0.02)
			l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			l.visibility_range_end = STENCIL_RANGE
			var z_ax := Geom.g([nrm.x, nrm.y, nrm.z]) - Geom.g([0, 0, 0])
			var y_ax := Vector3.UP
			var x_ax := y_ax.cross(z_ax).normalized()
			l.transform = Transform3D(Basis(x_ax, y_ax, z_ax), Geom.g([mid.x + nrm.x * (rr + 0.012), mid.y + nrm.y * (rr + 0.012), mid.z]))
			l.set_meta("stencil", p.medium)
			parent.add_child(l, true)   # readable names (stencil, stencil2, …)
			n += 1
	return n

## Mesh arrays turned by a basis (positions, normals, tangents).
static func _turned(arr: Array, bs: Basis) -> Array:
	var out := arr.duplicate()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX].duplicate()
	for i in v.size():
		v[i] = bs * v[i]
	out[Mesh.ARRAY_VERTEX] = v
	if arr[Mesh.ARRAY_NORMAL] != null:
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL].duplicate()
		for i in n.size():
			n[i] = (bs * n[i]).normalized()
		out[Mesh.ARRAY_NORMAL] = n
	if arr[Mesh.ARRAY_TANGENT] != null:
		var t: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT].duplicate()
		for i in range(0, t.size(), 4):
			var q := (bs * Vector3(t[i], t[i + 1], t[i + 2])).normalized()
			t[i] = q.x; t[i + 1] = q.y; t[i + 2] = q.z
		out[Mesh.ARRAY_TANGENT] = t
	return out

## Mesh layers (finished arrays, around origin o in Godot's axes) cut by 12 m cell (6 m for detail) of each
## triangle's centre: [{origin, layers}], each piece's vertices around its cell's corner.
static func split_cells(layers: Dictionary, o: Vector3) -> Array:
	var by_cell := {}
	for k in layers:
		var L: Dictionary = layers[k]
		var arr: Array = L.arrays
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var size := SMALL_CELL if L.cls == "detail" else CELL
		var tris := {}
		for t in range(0, idx.size(), 3):
			var c := (v[idx[t]] + v[idx[t + 1]] + v[idx[t + 2]]) / 3.0 + o
			var cell := Vector2i(int(floor(c.x / size)), int(floor(c.z / size)))
			if not tris.has(cell):
				tris[cell] = PackedInt32Array()
			tris[cell].append_array([idx[t], idx[t + 1], idx[t + 2]])
		for cell in tris:
			var corner := Vector3(cell.x * size, o.y, cell.y * size)
			var remap := {}
			var out := []
			out.resize(Mesh.ARRAY_MAX)
			var nv := PackedVector3Array()
			var ni := PackedInt32Array()
			var chans := {}
			for ch in [Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_COLOR]:
				if arr[ch] != null:
					chans[ch] = []
			for i in tris[cell]:
				if not remap.has(i):
					remap[i] = nv.size()
					nv.append(v[i] + o - corner)
					for ch in chans:
						if ch == Mesh.ARRAY_TANGENT:
							for q in 4:
								chans[ch].append(arr[ch][i * 4 + q])
						else:
							chans[ch].append(arr[ch][i])
				ni.append(remap[i])
			out[Mesh.ARRAY_VERTEX] = nv
			out[Mesh.ARRAY_INDEX] = ni
			for ch in chans:
				match ch:
					Mesh.ARRAY_NORMAL: out[ch] = PackedVector3Array(chans[ch])
					Mesh.ARRAY_TANGENT: out[ch] = PackedFloat32Array(chans[ch])
					Mesh.ARRAY_TEX_UV: out[ch] = PackedVector2Array(chans[ch])
					Mesh.ARRAY_COLOR: out[ch] = PackedColorArray(chans[ch])
			var key := "%d|%d" % [cell.x, cell.y] if L.cls != "detail" else "d%d|%d" % [cell.x, cell.y]
			if not by_cell.has(key):
				by_cell[key] = {"origin": corner, "layers": {}}
			by_cell[key].layers[k] = {"mat": L.mat, "cls": L.cls, "size": L.size, "arrays": out, "tris": ni.size() / 3}
	return by_cell.values()

## The top of a support post's base plate over the surface it stands on (parts_pipes.gd `_support`, `_bridge`): FOOT,
## or FOOT_STEP higher for each level the plates it overlaps already take (two pipes' supports side by side: their
## plates overlapped in one plane and fought in the depth buffer, tests/test_ground.gd); the lowest level free. 4 cm: a
## raised plate stays 2 cm clear of a hall's floor too (plant_builder.gd HALL_FLOOR_T), which hides a plate at FOOT.
## `half`: the plate's half width (its plates are square, along the plant's axes).
const FOOT := 0.02
const FOOT_STEP := 0.04
var feet: Array = []   # [plan point, half width, surface z, plate top]
func _foot(p: Vector2, half: float, z: float) -> float:
	var taken: Array = []
	for f in feet:
		var q: Vector2 = f[0]
		if absf(f[2] - z) < 0.01 and absf(q.x - p.x) < half + f[1] and absf(q.y - p.y) < half + f[1]:
			taken.append(f[3])
	var top := FOOT
	while taken.any(func(t): return absf(t - top) < 0.001):
		top += FOOT_STEP
	feet.append([p, half, z, top])
	return top

## The half width of a support post's base plate (parts_pipes.gd `_support`), 0 where it has none (a post shorter
## than 5 cm: the shoe sits on the surface).
static func _plate_half(post: float) -> float:
	if post <= 0.05:
		return 0.0
	return (0.1 if post < 2.0 else (0.2 if post < 8.0 else 0.3)) * 2.5 * 0.5

## Supports at the span table's spacing along every horizontal run above ground, on the highest walkable surface,
## rack tier or the ground below (within MAX_POST), or hung from a roof or deck above (within 6 m).
func _supports(p: Dictionary, route: Array, r: float, buried: Dictionary) -> Array:
	var out: Array = []
	var sp := P_PIPE.span(float(p.get("dn", 100)))
	var n_made := 0
	for i in range(route.size() - 1):
		if buried.has(i):
			continue
		var a: Vector3 = route[i]
		var c: Vector3 = route[i + 1]
		var d := c - a
		var len := d.length()
		if len < sp * 0.5 or absf(d.z) / maxf(len, 1e-6) > 0.3:
			continue
		var k := int(ceil(len / sp))
		for j in k:
			var q := a + d * ((j + 0.5) / k)
			if q.z + r < 0.0 and b.ground_at(Vector2(q.x, q.y)):
				continue   # in the soil (a run the content leaves unburied under the ground): nothing to draw
			var base := _below(q, r)
			if base > -INF:
				var dn := d.normalized()
				if _in_walkway(q, r, base):
					# a post would stand in walking space (a deck, a landing, a stair): a bridge over it instead,
					# its legs where the walkway ends on both sides
					var br := _bridge(q, r, dn)
					if br.is_empty():
						unsupported.append("%s at %s (over a walkway)" % [p.kks, str(q.snapped(Vector3(0.1, 0.1, 0.1)))])
					else:
						for l in br.legs:
							if q.z - r - 0.15 - l.z > 0.05:   # (parts_pipes.gd _bridge: a leg's plate, 0.45 m square)
								l["foot"] = _foot(Vector2(l.at.x, l.at.y), 0.225, l.z)
						out.append(br)
						n_made += 1
					continue
				var sup := {"at": q, "z_to": base, "kind": "guide" if n_made % 3 == 2 else "shoe", "dir": dn}
				var half := _plate_half(q.z - r - 0.1 - base)
				if half > 0.0:
					sup["foot"] = _foot(Vector2(q.x, q.y), half, base)
				out.append(sup)
				n_made += 1
				continue
			var above := _above(q, r)
			if above < INF:
				out.append({"at": q, "z_to": above, "kind": "hanger", "dir": d.normalized()})
				n_made += 1
			else:
				unsupported.append("%s at %s" % [p.kks, str(q.snapped(Vector3(0.1, 0.1, 0.1)))])
	supports += n_made
	return out

## Would a post from the pipe at q down to `base` stand in walking space: on a walkway or a landing (a deck narrower
## than WIDE_DECK; on a wide deck, a roof or a floor, posts stand as pipe sleepers do) more than a short leg high, or
## through a stair?
func _in_walkway(q: Vector3, r: float, base: float) -> bool:
	var p2 := Vector2(q.x, q.y)
	var h := q.z - r - base
	for sf in b.surfaces:
		if absf(sf.z - base) <= 0.05 and sf.kind in ["platform", "floor", "grating"] and h > 1.0 and Geom.in_region(p2, sf.outline, sf.holes):
			var bb := Rect2(sf.outline[0], Vector2.ZERO)
			for v in sf.outline:
				bb = bb.expand(v)
			if minf(bb.size.x, bb.size.y) < WIDE_DECK:
				return true
	for st in b.stairs:
		if Geom.in_poly(p2, st.lay.rect) and st.top.z + 2.1 > base and st.foot.z < q.z:
			return true
	return false

## A pipe bridge across a walkway: two legs beside it (perpendicular to the pipe, where neither leg stands in walking
## space), a beam under the pipe between them. {} when there is no room within 8 m either side.
func _bridge(q: Vector3, r: float, dn: Vector3) -> Dictionary:
	var side := dn.cross(Vector3(0, 0, 1)).normalized()
	var legs: Array = []
	for s: float in [-1.0, 1.0]:
		var t := 0.5
		var found := false
		while t <= 8.0:
			var p := q + side * (t * s)
			var base := _below(p, r)
			if base > -INF and not _in_walkway(p, r, base):
				legs.append({"at": p, "z": base})
				found = true
				break
			t += 0.25
		if not found:
			return {}
	return {"at": q, "kind": "bridge", "dir": dn, "legs": legs, "z_to": minf(legs[0].z, legs[1].z)}

func _below(q: Vector3, r: float) -> float:
	var best := -INF
	var p2 := Vector2(q.x, q.y)
	for sf in b.surfaces:
		if sf.z < q.z - r - 0.05 and sf.z > q.z - MAX_POST and Geom.in_region(p2, sf.outline, sf.holes):
			best = maxf(best, sf.z)
	for t in b.rack_tiers:
		if t.z < q.z - r - 0.05 and t.z > q.z - MAX_POST and Geom.in_poly(p2, t.outline):
			best = maxf(best, t.z)
	if q.z - r > 0.05 and q.z < MAX_POST and b.ground_at(p2):
		best = maxf(best, 0.0)
	return best

func _above(q: Vector3, r: float) -> float:
	var best := INF
	var p2 := Vector2(q.x, q.y)
	for sf in b.surfaces:
		if sf.z - sf.thick > q.z + r + 0.05 and sf.z < q.z + 6.0 and Geom.in_region(p2, sf.outline, sf.holes):
			best = minf(best, sf.z - sf.thick)
	for bd in b.buildings:
		if bd.height > q.z + r and bd.height < q.z + 6.0 and Geom.in_poly(p2, bd.outline):
			best = minf(best, bd.height)
	return best
