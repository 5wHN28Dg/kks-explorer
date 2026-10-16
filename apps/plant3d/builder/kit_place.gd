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

func _init(builder) -> void:
	b = builder

# ------------------------------------------------------------------ before the areas: what parts need to know

## The nozzles pipes end on, the shaft lines, and what each part stands under or over.
func prepare() -> void:
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
		var L: Dictionary = res.layers[k]
		_cell(L, k, xf)
		var bb: AABB = L.mesh.get_aabb()
		box = bb if first else box.merge(bb)
		first = false
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
		for s in res.solids:
			var cs := CollisionShape3D.new()
			if s.kind == "box":
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
			node.add_child(cs)
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
	lab.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
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

# ------------------------------------------------------------------ the cells

func _cell(L: Dictionary, key: String, xf: Transform3D) -> void:
	var cls: String = L.cls
	var size := SMALL_CELL if cls == "detail" else CELL
	var c := Vector2i(int(floor(xf.origin.x / size)), int(floor(xf.origin.z / size)))
	var k := "%d|%s|%d|%d" % [L.mesh.get_instance_id(), key, c.x, c.y]
	if not cells.has(k):
		cells[k] = {"mesh": L.mesh, "mat": L.mat, "cls": cls, "size": L.size, "xf": []}
	cells[k].xf.append(xf)

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
		if c.xf.size() == 1:
			var parts: PackedStringArray = k.split("|")
			var mk := "|".join(parts.slice(1))
			if not merge.has(mk):
				merge[mk] = []
			merge[mk].append(c)
		else:
			_emit(kit, c.mesh, c.mat, c.cls, c.size, c.xf, n)
			n += 1
	for mk in merge:
		var group: Array = merge[mk]
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
		var im := ImporterMesh.new()
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr)
		if group[0].cls != "identify":   # identify pieces keep every triangle (§10)
			im.generate_lods(25.0, 60.0, [])
		var mesh := im.get_mesh()
		var size := INF
		for c in group:
			size = minf(size, c.size)
		_emit(kit, mesh, group[0].mat, "identify" if group.any(func(c): return c.cls == "identify") else group[0].cls, size, [Transform3D(Basis(), o)], n)
		n += 1
	var groups := merge.size()
	print("build: area %s: %d draw meshes (%d cells' merged groups)" % [root.name, n, groups])
	cells.clear()
	cells_made += n
	return n

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
	P_PIPE.pipe(m, route, {"od": od, "ins": ins, "band": "medium_" + p.medium, "arrows": float(p.get("arrows", 0)),
		"buried": buried, "gaps": gaps, "flanges": flanges, "supports": sup,
		"bend": {"3d": 3.0, "5d": 5.0}.get(p.get("bend", ""), 1.5)}, origin)
	var layers := Kit._meshes(m.finish(), Vector3.ZERO)
	var xf := Transform3D(Basis(), Geom.g([origin.x, origin.y, origin.z]))
	for k in layers:
		_cell(layers[k], k, xf)
		tris_total += layers[k].tris[0]

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
						out.append(br)
						n_made += 1
					continue
				out.append({"at": q, "z_to": base, "kind": "guide" if n_made % 3 == 2 else "shoe", "dir": dn})
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
