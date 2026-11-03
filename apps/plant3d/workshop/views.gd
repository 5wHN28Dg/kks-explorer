## The Workshop's views (docs/plant3d/WORKSHOP.md §3 "See inside", §7): every component drawn with `ws_lit` (the
## plant's weathered material with the cut planes, the heat and pressure colour and the selection's glow), the cut
## faces with `ws_cap` (ws_lit's next pass on solid components while a cut is on), the X-ray with `ws_xray` (the
## assembly ghost's shader, in another colour), and the flow paths with `ws_flow`. Generic: the kind's views come from
## its data file (`views`: xray_all, cutaway with its planes and keep), its flow paths from the generator.
##
## Planes are in the Workshop's world, where the machine stands at the origin in its own frame (Godot's axes): the
## cutaway's from the data (a normal in the part frame and an offset as a fraction of the part's box from its centre),
## the section's from the trainee (an axis, a turn about it and a position across the box).
extends RefCounted

const BenchModel = preload("res://sim/bench_model.gd")
const LIT := preload("res://workshop/ws_lit.gdshader")
const CAP := preload("res://workshop/ws_cap.gdshader")
const XRAY := preload("res://workshop/ws_xray.gdshader")
const FLOW := preload("res://workshop/ws_flow.gdshader")
const XRAY_COLOUR := Color(0.95, 0.85, 0.35)     # the X-ray's colour (the ghost's is blue)
const FLOW_QUADS := 48                           # particles per path at full density
const FLOW_PTS := 8
const SECTION_AXES := [Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)]   # across, along, up (Godot's axes)
const RAMP_MIX := 0.65                           # how much of a component's colour the heat or pressure colour takes
## Glass the trainee looks through (a component the generator marks `glass`: a display's window): drawn with ws_xray
## in a glass colour, faint, so what is behind it reads (the plant draws it opaque; no new pipeline: the X-ray's shader)
const GLASS_COLOUR := Color(0.55, 0.68, 0.74)

var ws                          # workshop/workshop.gd
var xray := false
var cut := false
var section := false
var section_axis := 0           # SECTION_AXES' index
var section_turn := 0.0         # degrees about the up axis (about x for the up axis)
var section_at := 0.5           # 0-1 across the box along the plane's normal
var flow_on := true
var density := 1.0              # the flow's density on this tier (R9a: the phone draws a third, never fewer)
var _lit := {}                  # plant material name -> ws_lit material (no cap)
var _capped := {}               # plant material name -> ws_lit material whose next pass is the cap while a cut is on
var _caps := {}                 # plant material name -> its ws_cap material
var _xray_mat: ShaderMaterial
var _glass: ShaderMaterial      # the see-through glass (GLASS_COLOUR)
var _keep := {}                 # component id -> true: the cutaway passes it by
var _meshes := {}               # component id -> [GeometryInstance3D] (its own, not its children's)
var _flows := {}                # path id -> {mmi, mat, pts, total, phase}
var _ramped := {}               # component id -> true: has a heat or pressure colour now
var _xrayed := {}               # component id -> true: drawn with the X-ray now
var _warm := false              # the machine's first frame: the cap pass drawn unseen (nothing cut)


## The machine was instanced: its materials to the Workshop's variants, its flow paths' particles made.
func machine_shown(machine: Node3D, comps: Dictionary) -> void:
	_meshes.clear()
	_flows.clear()
	_ramped.clear()
	_xrayed.clear()
	_keep.clear()
	xray = false
	cut = false
	section = false
	var views: Dictionary = ws.words.get("views", {})
	for id in views.get("cutaway", {}).get("keep", []):
		_keep[id] = true
	for id in comps:
		var n: Node3D = comps[id]
		var thin: bool = n.get_meta("thin", false)
		var glass: bool = n.get_meta("glass", false)
		var own := []
		for c in n.get_children():
			if (c is MeshInstance3D or c is MultiMeshInstance3D) and c.has_meta("mat"):
				own.append(c)
			elif c.has_meta("items"):            # a fastener group: its MultiMeshes, solid
				for mm in c.get_children():
					if mm is MultiMeshInstance3D and mm.has_meta("mat"):
						mm.material_override = mat_for(mm.get_meta("mat"), false)
		for c in own:
			c.material_override = glass_mat() if glass else mat_for(c.get_meta("mat"), thin)
			c.set_instance_shader_parameter("ws_keep", 1.0 if _keep.has(id) else 0.0)
		_meshes[id] = own
	var flows: Dictionary = machine.get_meta("flows", {})
	for fid in flows:
		_make_flow(machine, fid, flows[fid])
	_planes()


## The Workshop's variant of a plant material (by its name): ws_lit, with the cap as its next pass for a solid
## component while a cut is on.
func mat_for(name: String, thin: bool) -> Material:
	var cache: Dictionary = _lit if thin else _capped
	if cache.has(name):
		return cache[name]
	var src: Material = ws._mat(name)
	var m := ShaderMaterial.new()
	m.shader = LIT
	if src is ShaderMaterial:
		for u in (src as ShaderMaterial).shader.get_shader_uniform_list():
			var v = (src as ShaderMaterial).get_shader_parameter(u.name)
			if v != null:
				m.set_shader_parameter(u.name, v)
	cache[name] = m
	if not thin:
		var cap := ShaderMaterial.new()
		cap.shader = CAP
		if src is ShaderMaterial:
			for k in ["tint", "use_vertex_colour", "use_albedo", "albedo_tex"]:
				var v = (src as ShaderMaterial).get_shader_parameter(k)
				if v != null:
					cap.set_shader_parameter(k, v)
		_caps[name] = cap
	_planes()
	return m


## The see-through glass.
func glass_mat() -> Material:
	if _glass == null:
		_glass = ShaderMaterial.new()
		_glass.shader = XRAY
		_glass.set_shader_parameter("colour", GLASS_COLOUR)
		_glass.set_shader_parameter("alpha", 0.05)
		_glass.set_shader_parameter("edge", 0.12)
	return _glass

## Every ws_lit and ws_cap material, for the planes' uniforms.
func _all_mats() -> Array:
	return _lit.values() + _capped.values() + _caps.values()


func set_xray(on: bool) -> void:
	xray = on
	_apply_xray()


## The X-ray takes the selected component (and its subassembly) when one is selected, else the kind's `xray_all`.
func _apply_xray() -> void:
	var want := {}
	if xray:
		if ws.selected != "" and _meshes.has(ws.selected):
			for id in _meshes:
				if id == ws.selected or ws._ancestor_of(ws.selected, id):
					want[id] = true
		else:
			for id in ws.words.get("views", {}).get("xray_all", []):
				want[id] = true
	if _xray_mat == null:
		_xray_mat = ShaderMaterial.new()
		_xray_mat.shader = XRAY
		_xray_mat.set_shader_parameter("colour", XRAY_COLOUR)
		_xray_mat.set_shader_parameter("alpha", 0.12)
		_xray_mat.set_shader_parameter("edge", 0.5)
	for id in _meshes:
		var on := want.has(id)
		if on == _xrayed.has(id):
			continue
		var thin: bool = ws.comps[id].get_meta("thin", false)
		var glass: bool = ws.comps[id].get_meta("glass", false)
		for c in _meshes[id]:
			c.material_override = _xray_mat if on else (glass_mat() if glass else mat_for(c.get_meta("mat"), thin))
		if on:
			_xrayed[id] = true
		else:
			_xrayed.erase(id)



func is_xrayed(id: String) -> bool:
	return _xrayed.has(id)


func selection_changed() -> void:
	if xray:
		_apply_xray()


func set_cut(on: bool) -> void:
	cut = on
	_planes()


func set_section(on: bool) -> void:
	section = on
	_planes()


func set_section_axis(k: int) -> void:
	section_axis = posmod(k, SECTION_AXES.size())
	_planes()


func set_section_turn(deg: float) -> void:
	section_turn = deg
	_planes()


func set_section_at(x: float) -> void:
	section_at = clampf(x, 0.0, 1.0)
	_planes()


## The machine's first frame: the cap pass drawn with nothing cut (hidden behind the front faces), so its pipelines
## are compiled with the machine's (§7.1); off again after that frame.
func warm(on: bool) -> void:
	_warm = on
	_planes()


func has_cutaway() -> bool:
	return not ws.words.get("views", {}).get("cutaway", {}).get("planes", []).is_empty()


## A plane's [normal, distance] from a normal in the part frame and an offset as a fraction of the box from its centre.
static func plane_of(normal_part: Vector3, offset: float, box: AABB) -> Array:
	var n := Vector3(normal_part.x, normal_part.z, -normal_part.y).normalized()   # the kit's part frame to Godot's
	var d := n.dot(box.get_center()) + offset * absf(n.x) * box.size.x + offset * absf(n.y) * box.size.y \
		+ offset * absf(n.z) * box.size.z
	return [n, d]


## The section plane's [normal, distance] now.
func section_plane() -> Array:
	var box: AABB = ws.machine.get_meta("box", AABB()) if ws.machine != null else AABB()
	var ax: Vector3 = SECTION_AXES[section_axis]
	var n := (Basis(Vector3(1, 0, 0), deg_to_rad(section_turn)) if section_axis == 2 \
		else Basis(Vector3.UP, deg_to_rad(section_turn))) * ax
	# the plane's position across the box along its normal: from the box's lowest corner along n to its highest
	var lo := INF
	var hi := -INF
	for i in 8:
		var p := box.get_endpoint(i)
		lo = minf(lo, n.dot(p))
		hi = maxf(hi, n.dot(p))
	return [n, lerpf(lo, hi, section_at)]


func _planes() -> void:
	if ws == null or ws.machine == null:
		return
	var box: AABB = ws.machine.get_meta("box", AABB())
	var pl: Array = ws.words.get("views", {}).get("cutaway", {}).get("planes", [])
	var p0 := Vector4(0, 1, 0, 1e9)
	var p1 := Vector4(0, 1, 0, -1e9)
	if pl.size() >= 1:
		var a := plane_of(_v3(pl[0].normal), float(pl[0].offset), box)
		p0 = Vector4(a[0].x, a[0].y, a[0].z, a[1])
	if pl.size() >= 2:
		var b := plane_of(_v3(pl[1].normal), float(pl[1].offset), box)
		p1 = Vector4(b[0].x, b[0].y, b[0].z, b[1])
	var sp := section_plane()
	var p2 := Vector4(sp[0].x, sp[0].y, sp[0].z, sp[1])
	var cut_on := 1.0 if cut and pl.size() >= 1 else 0.0
	var sec_on := 1.0 if section else 0.0
	for m in _all_mats():
		m.set_shader_parameter("ws_plane0", p0)
		m.set_shader_parameter("ws_plane1", p1)
		m.set_shader_parameter("ws_plane2", p2)
		m.set_shader_parameter("ws_cut_on", cut_on)
		m.set_shader_parameter("ws_sec_on", sec_on)
	var capping := cut_on > 0.5 or sec_on > 0.5 or _warm
	for name in _capped:
		var m: ShaderMaterial = _capped[name]
		var want: Material = _caps[name] if capping else null
		if m.next_pass != want:
			m.next_pass = want


static func _v3(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


# ------------------------------------------------------------------ heat and pressure colours, the selection

## A component's heat or pressure colour (a = how much: 0 none).
func set_ramp(id: String, c: Color, a: float) -> void:
	if not _meshes.has(id):
		return
	if a <= 0.0 and not _ramped.has(id):
		return
	for g in _meshes[id]:
		g.set_instance_shader_parameter("ws_ramp", Color(c.r, c.g, c.b, a * RAMP_MIX))
	if a > 0.0:
		_ramped[id] = true
	else:
		_ramped.erase(id)


## The selection's glow on a component or fastener group (its own meshes).
func set_sel(n: Node, on: bool) -> void:
	for c in n.get_children():
		if c is GeometryInstance3D and c.has_meta("mat"):
			c.set_instance_shader_parameter("ws_sel", 1.0 if on else 0.0)


## A legend's colour at x (sim/bench_model.gd's).
static func legend_colour(lg: Dictionary, x: float) -> Color:
	return BenchModel.legend_colour(lg, x)


# ------------------------------------------------------------------ flow paths (ws_flow)

func _make_flow(machine: Node3D, fid: String, pts_in: Array) -> void:
	var pts := PackedVector3Array()
	for p in pts_in:
		if pts.size() < FLOW_PTS:
			pts.append(p)
	if pts.size() < 2:
		return
	var cum := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + pts[i].distance_to(pts[i - 1]))
	while pts.size() < FLOW_PTS:
		pts.append(pts[pts.size() - 1])
		cum.append(cum[cum.size() - 1])
	var mat := ShaderMaterial.new()
	mat.shader = FLOW
	mat.set_shader_parameter("pts", pts)
	mat.set_shader_parameter("cum", cum)
	mat.set_shader_parameter("npts", mini(pts_in.size(), FLOW_PTS))
	mat.set_shader_parameter("count", float(FLOW_QUADS))
	mat.set_shader_parameter("density", 0.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = FLOW_QUADS
	for i in FLOW_QUADS:
		mm.set_instance_transform(i, Transform3D.IDENTITY)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "flow_" + fid
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = machine.get_meta("box", AABB()).grow(0.05)
	machine.add_child(mmi)
	_flows[fid] = {"mmi": mmi, "mat": mat, "total": cum[cum.size() - 1], "phase": 0.0}


func flow_ids() -> Array:
	return _flows.keys()


## A flow path drawn from the bench's value (flow -1..1: its sign is the direction), advanced by `dt` seconds of
## bench time at `speed` m/s at full flow; `c` its colour.
func set_flow(fid: String, flow: float, speed: float, dt: float, c: Color) -> void:
	if not _flows.has(fid):
		return
	var f: Dictionary = _flows[fid]
	var k := clampf(flow, -1.0, 1.0)
	f.phase = fmod(f.phase + k * speed * dt, maxf(f.total, 1e-6))
	var mat: ShaderMaterial = f.mat
	mat.set_shader_parameter("phase", f.phase)
	var a := absf(k)
	mat.set_shader_parameter("density", (clampf(a * 4.0, 0.0, 1.0) * density) if flow_on else 0.0)
	mat.set_shader_parameter("strength", clampf(0.35 + a, 0.0, 1.0))
	mat.set_shader_parameter("colour", c)


## The machine's first frame: every flow's quads drawn (unseen: density 1, strength 0) so ws_flow's pipelines compile.
func warm_flows(on: bool) -> void:
	for fid in _flows:
		var mat: ShaderMaterial = _flows[fid].mat
		mat.set_shader_parameter("density", 1.0 if on else 0.0)
		mat.set_shader_parameter("strength", 0.0)
