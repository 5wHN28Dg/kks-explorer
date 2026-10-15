## The engine bench (decision 0041): a pipe rack and pump bay of about 1.5 M triangles at full detail, built by script
## from parametric parts (the way the plant will be built from its description), 40 PBR materials (5 CC0 texture sets
## in tinted variants), one sun with shadows, a walking camera on a fixed loop, and a frame-time log.
##
## Settings come from the command line after `--` (desktop) or from preset.txt in the app's external files folder
## (Android: run_phone.sh pushes it), one `name=value` per line, the same names:
##   seconds=600            how long to walk (after the first 5 s, which are not measured)
##   variant=cells          nodes (one node per part) | merged (one mesh per material) | cells (instanced per 12 m cell)
##   preset=lean+vis+tex1k  a base and its levers, each switchable on its own:
##     bases:  full (native resolution, 4 shadow cascades to 80 m) | scaled (70 % + FSR) | lean (60 % + FSR, 2048
##             shadow atlas, 40 m shadows, mesh LOD threshold 4 px) | lean2 (lean, 2 cascades) | lean_noshadow
##     levers: vis    small parts that carry no information far away (bolts, motor fins) are not drawn beyond the
##                    distance where their smallest feature is under 1 px on the Note 9's screen, with a fade (R9a)
##             tex1k  textures at 1024 px (the tier's texture size: the same files imported with a size limit)
##             texraw the earlier bench's import (2048 px, lossless, no mipmaps): to compare with the old numbers
##             lod    LOD bias 0.5: each part switches to its simpler LOD at half the distance
##             half   (with full) 3D drawn at half the screen's width and height: a HiDPI laptop panel at its logical
##                    resolution
##   prebuilt=1             load built/plant.scn (what a shipped app does) instead of building the plant by script
##   look=1                 capture the 10 "look" viewpoints as PNGs instead of walking
##   save=res://built/plant.scn   (desktop) build the plant, save it as a scene and quit
##   out=PATH               where result.txt and the look PNGs go (default: the external files folder on Android,
##                          the user data folder elsewhere)
extends Node3D

const ANDROID_FILES := "/storage/emulated/0/Android/data/kks.plant3d.bench/files"
const CELL := 12.0        # instancing cell (m)
const SMALL_CELL := 6.0   # cell for parts with a visibility range: a smaller box keeps the range close to the rule
## The Note 9's screen: 1080 px over the camera's 70 degree vertical field of view.
const PX_PER_RAD := 540.0 / 0.7002075382   # = 540 / tan(35 deg), about 771
## Parts not drawn beyond a distance (R9a): only parts whose information the larger part they sit on carries already
## (a flange shows the joint, a motor body the motor). Handwheels and bonnets show a valve's type and state and are
## never cut; they get simpler with distance through LOD only. Value = the part's smallest feature in metres.
const FEATURE := {"bolt": 0.024, "fins": 0.04}

var mats: Array[StandardMaterial3D] = []
var meshes := {}
var times := PackedFloat32Array()
var gpu := PackedFloat32Array()
var cpu := PackedFloat32Array()
var calls := PackedInt32Array()
var t_run := 0.0
var seconds := 600.0
var variant := "cells"
var preset := "full"
var levers: PackedStringArray = []
var base := "full"
var prebuilt := false
var look := false
var save_to := ""
var out_dir := ""
var cam: Camera3D
var path: Array[Vector3] = []
var tris := 0
var nodes := 0
var first_frame_ms := -1   # since the engine started (Time.get_ticks_msec counts from engine start)
var ready_ms := 0
var root: Node3D
var ranged := 0            # instances given a visibility range
var log_lines: PackedStringArray = []

func _ready() -> void:
	var settings := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		settings[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if OS.get_name() == "Android":
		var f := FileAccess.open(ANDROID_FILES + "/preset.txt", FileAccess.READ)
		if f:
			for line in f.get_as_text().split("\n"):
				var kv := line.strip_edges().split("=", true, 1)
				if kv.size() == 2: settings[kv[0]] = kv[1]
	seconds = float(settings.get("seconds", "600"))
	variant = settings.get("variant", "cells")
	preset = settings.get("preset", "full")
	prebuilt = settings.get("prebuilt", "0") == "1"
	look = settings.get("look", "0") == "1"
	save_to = settings.get("save", "")
	out_dir = settings.get("out", ANDROID_FILES if OS.get_name() == "Android" else OS.get_user_data_dir())
	var parts := preset.split("+")
	base = parts[0]
	levers = parts.slice(1)
	for l in levers:
		if not l in ["vis", "tex1k", "texraw", "lod", "half"]: _say("unknown lever " + l)
	_apply_preset()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_environment()
	var t0 := Time.get_ticks_msec()
	if prebuilt:
		root = (load("res://built/plant.scn") as PackedScene).instantiate()
		add_child(root)
		_say("loaded the pre-built plant in %d ms" % (Time.get_ticks_msec() - t0))
	else:
		root = Node3D.new()
		root.name = "Plant"
		add_child(root)
		_build()
		_say("built the plant in %d ms" % (Time.get_ticks_msec() - t0))
		if save_to != "":
			for c in root.get_children(): c.owner = root
			var ps := PackedScene.new()
			ps.pack(root)
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_to.get_base_dir()))
			_say("saved %s: error %d" % [save_to, ResourceSaver.save(ps, save_to)])
			# The materials as resources too: the export's shader baker compiles the shaders of the materials it
			# finds in the project, and these (made by script at run time) would otherwise be compiled on the phone.
			# The texture tier changes no shader, so one set covers every tier.
			_materials()
			var md := save_to.get_base_dir().path_join("mats")
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(md))
			var err := 0
			for i in mats.size(): err += ResourceSaver.save(mats[i], md.path_join("m%02d.tres" % i))
			_say("saved %d materials to %s: errors %d" % [mats.size(), md, err])
			set_process(false)
			get_tree().quit()
			return
	var t1 := Time.get_ticks_msec()
	_materials()
	_dress()
	_say("materials and ranges in %d ms" % (Time.get_ticks_msec() - t1))
	cam = Camera3D.new()
	cam.fov = 70
	cam.far = 400
	add_child(cam)
	path = [Vector3(-5, 1.7, -4), Vector3(65, 1.7, -4), Vector3(65, 1.7, 14), Vector3(30, 7.7, 14),
			Vector3(-5, 7.7, 14), Vector3(-5, 1.7, 4), Vector3(-5, 1.7, -4)]
	ready_ms = Time.get_ticks_msec()
	_say("%s preset=%s renderer=%s tris=%d nodes=%d ranged=%d device=%s screen=%s" % [variant, preset,
		RenderingServer.get_current_rendering_method(), tris, nodes, ranged, RenderingServer.get_video_adapter_name(),
		str(get_viewport().get_visible_rect().size)])
	if look: _look()

func _say(s: String) -> void:
	print("bench: ", s)
	log_lines.append(s)

func _write_out() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var f := FileAccess.open(out_dir.path_join("result.txt"), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(log_lines) + "\n")
	else:
		print("bench: could not write ", out_dir.path_join("result.txt"), ": ", FileAccess.get_open_error())

func _apply_preset() -> void:
	var vp := get_viewport()
	if base != "full":
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		vp.scaling_3d_scale = 0.7 if base == "scaled" else 0.6
	elif "half" in levers:   # a HiDPI laptop panel drawn at its logical resolution (1440x900 on 2880x1800)
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = 0.5
	if base.begins_with("lean"):   # lean, lean2, lean_noshadow
		RenderingServer.directional_shadow_atlas_set_size(2048, true)
		vp.mesh_lod_threshold = 4.0

# ------------------------------------------------------------------ materials: 5 CC0 sets x 8 tints = 40

func _materials() -> void:
	var dir := "res://tex1k/" if "tex1k" in levers else ("res://texraw/" if "texraw" in levers else "res://tex/")
	var sets := ["PaintedMetal009", "Metal032", "MetalPlates006", "Concrete034", "Grate001"]
	var tints := [Color(1, 1, 1), Color(0.75, 0.2, 0.15), Color(0.2, 0.45, 0.25), Color(0.25, 0.35, 0.7),
				  Color(0.9, 0.75, 0.2), Color(0.6, 0.6, 0.62), Color(0.35, 0.35, 0.38), Color(0.85, 0.85, 0.8)]
	var tex := func(name: String) -> Texture2D:
		var p: String = dir + name
		return load(p) if ResourceLoader.exists(p) else null
	for s in sets:
		var color: Texture2D = tex.call(s + "_2K-JPG_Color.jpg")
		var normal: Texture2D = tex.call(s + "_2K-JPG_NormalGL.jpg")
		var rough: Texture2D = tex.call(s + "_2K-JPG_Roughness.jpg")
		var metal: Texture2D = tex.call(s + "_2K-JPG_Metalness.jpg")
		var ao: Texture2D = tex.call(s + "_2K-JPG_AmbientOcclusion.jpg")
		for t in tints:
			var m := StandardMaterial3D.new()
			m.albedo_texture = color
			m.albedo_color = t
			if normal:
				m.normal_enabled = true
				m.normal_texture = normal
			m.roughness_texture = rough
			m.roughness = 1.0
			if metal:
				m.metallic_texture = metal
				m.metallic = 1.0
			if ao:
				m.ao_enabled = true
				m.ao_texture = ao
			m.uv1_scale = Vector3(2, 2, 2)
			mats.append(m)

func _environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true            # Forward+ only; ignored by the Mobile renderer
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.directional_shadow_max_distance = 40 if base.begins_with("lean") else 80
	sun.shadow_enabled = base != "lean_noshadow"
	if base == "lean2": sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(sun)

## The levers that work on the built plant: materials by index, visibility ranges, LOD bias. The same for a plant
## built now and one loaded from built/plant.scn (which carries no materials, only each instance's part and material).
func _dress() -> void:
	for n in root.get_children():
		var gi := n as GeometryInstance3D
		if gi == null: continue
		gi.material_override = mats[int(gi.get_meta("mat"))]
		if prebuilt:   # count what was loaded (a built plant counted itself)
			nodes += 1
			var mmi := gi as MultiMeshInstance3D
			if mmi: tris += mmi.multimesh.instance_count * _tri_count(mmi.multimesh.mesh)
			elif gi is MeshInstance3D: tris += _tri_count((gi as MeshInstance3D).mesh)
		if "lod" in levers: gi.lod_bias = 0.5
		var part: String = gi.get_meta("part", "")
		if "vis" in levers and FEATURE.has(part):
			_range(gi, FEATURE[part])

## Not drawn beyond the distance where the part's smallest feature is under 1 px on the Note 9's screen. Godot
## measures the range to the centre of the instance's box (here a whole cell of instances: servers/rendering/
## renderer_scene_cull.cpp, _visibility_range_check), so the box's half diagonal is added: no instance in it is
## faded before its own distance. The fade (SELF) runs from end - margin to end + margin.
func _range(gi: GeometryInstance3D, feature: float) -> void:
	var d := feature * PX_PER_RAD   # 1 px
	var box: AABB = gi.get_meta("box")
	var half_diag := box.size.length() / 2.0
	var margin := d * 0.2
	gi.visibility_range_end = d + half_diag + margin
	gi.visibility_range_end_margin = margin
	gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	ranged += 1

# ------------------------------------------------------------------ parametric parts (with generated LODs)

func _lod(m: PrimitiveMesh) -> Mesh:
	## a primitive as an ArrayMesh with LODs generated the way imported models get them
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, m.get_mesh_arrays())
	im.generate_lods(25.0, 60.0, [])
	return im.get_mesh()

func _part(key: String, make: Callable) -> Mesh:
	if not meshes.has(key):
		var mesh := _lod(make.call())
		mesh.set_meta("part", key.rstrip("0123456789."))
		meshes[key] = mesh
	return meshes[key]

func _cyl(r: float, h: float, seg: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r; c.bottom_radius = r; c.height = h; c.radial_segments = seg; c.rings = 1
	return c

func _box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new(); b.size = Vector3(x, y, z); return b

func _torus(r: float, t: float, rings: int, sides: int) -> TorusMesh:
	var to := TorusMesh.new(); to.inner_radius = r - t; to.outer_radius = r + t; to.rings = rings; to.ring_segments = sides
	return to

var batch := {}   # variant "merged": material -> SurfaceTool of everything static with it
var cells := {}   # variant "cells": (mesh, material, cell) -> transforms, drawn as one MultiMesh each

## mat = set * 8 + tint (5 texture sets x 8 tints)
func _put(mesh: Mesh, mat: int, xf: Transform3D) -> void:
	tris += _tri_count(mesh)
	var part: String = mesh.get_meta("part")
	if variant == "cells":
		var size := SMALL_CELL if FEATURE.has(part) else CELL
		var cell := Vector2i(int(floor(xf.origin.x / size)), int(floor(xf.origin.z / size)))
		var key := [mesh.get_instance_id(), mat, cell]
		if not cells.has(key): cells[key] = [mesh, mat, []]
		cells[key][2].append(xf)
		return
	if variant == "merged":
		if not batch.has(mat):
			var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES); batch[mat] = st
		batch[mat].append_from(mesh, 0, xf)
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = xf
	_tag(mi, part, mat)
	mi.set_meta("box", xf * mesh.get_aabb())
	root.add_child(mi)
	nodes += 1

func _tag(gi: GeometryInstance3D, part: String, mat: int) -> void:
	gi.set_meta("part", part)
	gi.set_meta("mat", mat)

var tri_cache := {}
func _tri_count(mesh: Mesh) -> int:
	# reading a mesh's arrays back is slow on a GPU (it took 8 s for the plant's 10,000 parts): once per mesh
	var id := mesh.get_instance_id()
	if not tri_cache.has(id):
		var a := mesh.surface_get_arrays(0)
		var idx = a[Mesh.ARRAY_INDEX]
		tri_cache[id] = (idx.size() if idx != null else a[Mesh.ARRAY_VERTEX].size()) / 3
	return tri_cache[id]

# ------------------------------------------------------------------ the scene

func _build() -> void:
	# ground
	_put(_part("ground", func(): return _box(140, 0.2, 50)), 3 * 8 + 5, Transform3D(Basis(), Vector3(60, -0.1, 12)))
	# pipe rack: 3 tiers, columns every 6 m along 120 m
	var col := _part("col", func(): return _box(0.3, 9, 0.3))
	var beam := _part("beam", func(): return _box(0.25, 0.3, 6))
	var lbeam := _part("lbeam", func(): return _box(6, 0.3, 0.25))
	for i in range(21):
		var x := i * 6.0
		for z in [0.0, 6.0]:
			_put(col, 4, Transform3D(Basis(), Vector3(x, 4.5, z)))
		for y in [3.0, 6.0, 9.0]:
			_put(beam, 4, Transform3D(Basis(), Vector3(x, y, 3)))
			if i < 20:
				for z in [0.0, 6.0]:
					_put(lbeam, 4, Transform3D(Basis(), Vector3(x + 3, y, z)))
	# pipes on the rack: 3 tiers x 8 pipes, insulated (cladding) or painted by system; flanges every 6 m
	var tints := [1, 2, 3, 5, 6, 7, 1, 2]
	for tier in range(3):
		for k in range(8):
			var r := 0.08 + 0.03 * (k % 4)
			var y := 3.15 + tier * 3.0 + r
			var z := 0.5 + k * 0.7
			var clad := (k % 3 == 0)
			var pipe := _part("pipe%.2f" % r, func(): return _cyl(r, 6.0, 32))
			var flange := _part("flange%.2f" % r, func(): return _cyl(r * 1.8, 0.05, 48))
			var bolt := _part("bolt", func(): return _cyl(0.012, 0.12, 12))
			for i in range(20):
				var x := i * 6.0 + 3.0
				_put(pipe, (2 * 8 + 5) if clad else tints[k], Transform3D(Basis(Vector3(0, 0, 1), PI / 2), Vector3(x, y, z)))
				_put(flange, 8 + 5, Transform3D(Basis(Vector3(0, 0, 1), PI / 2), Vector3(x + 3, y, z)))
				for b in range(8):
					var ang := b * TAU / 8
					_put(bolt, 8 + 6, Transform3D(Basis(Vector3(0, 0, 1), PI / 2), Vector3(x + 3, y + cos(ang) * r * 1.5, z + sin(ang) * r * 1.5)))
	# pump bay: 4 rows x 13 pumps with motor, casing, baseplate, suction/discharge valves with handwheels
	var motor := _part("motor", func(): return _cyl(0.35, 1.0, 48))
	var fins := _part("fins", func(): return _torus(0.37, 0.02, 64, 8))
	var casing := _part("casing", func(): return _torus(0.32, 0.18, 48, 24))
	var base_p := _part("base", func(): return _box(2.4, 0.15, 0.9))
	var vbody := _part("vbody", func(): return _cyl(0.14, 0.5, 32))
	var bonnet := _part("bonnet", func(): return _cyl(0.06, 0.6, 24))
	var wheel := _part("wheel", func(): return _torus(0.18, 0.015, 64, 12))
	var grate := _part("grate", func(): return _box(6, 0.05, 3))
	for row in range(4):
		for p in range(13):
			var o := Vector3(5 + p * 9.0, 0, 11 + row * 6.0)
			_put(base_p, 6, Transform3D(Basis(), o + Vector3(0, 0.08, 0)))
			_put(motor, 3, Transform3D(Basis(Vector3(0, 0, 1), PI / 2), o + Vector3(-0.5, 0.55, 0)))
			for f in range(8):
				_put(fins, 3, Transform3D(Basis(Vector3(0, 0, 1), PI / 2), o + Vector3(-0.9 + f * 0.1, 0.55, 0)))
			_put(casing, 2, Transform3D(Basis(Vector3(1, 0, 0), PI / 2), o + Vector3(0.7, 0.55, 0)))
			for v in range(4):
				var vo := o + Vector3(1.4 + v * 0.8, 0.9, 0)
				_put(vbody, 8 + 6, Transform3D(Basis(), vo))
				_put(bonnet, 8 + 6, Transform3D(Basis(), vo + Vector3(0, 0.5, 0)))
				_put(wheel, 1, Transform3D(Basis(), vo + Vector3(0, 0.82, 0)))
			_put(grate, 4 * 8 + 6, Transform3D(Basis(), o + Vector3(1.5, 6.0, 0)))
	if variant == "cells":
		for key in cells:
			var e = cells[key]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = e[0]
			mm.instance_count = e[2].size()
			for i in range(e[2].size()): mm.set_instance_transform(i, e[2][i])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			_tag(mmi, e[0].get_meta("part"), e[1])
			# the cell's box, computed here (the renderer's copy is not readable everywhere): what its range is
			# measured from
			var box: AABB = e[2][0] * e[0].get_aabb()
			for xf in e[2]: box = box.merge(xf * e[0].get_aabb())
			mmi.set_meta("box", box)
			root.add_child(mmi)
			nodes += 1
	if variant == "merged":
		for mat in batch:
			var mi := MeshInstance3D.new()
			mi.mesh = batch[mat].commit()
			_tag(mi, "merged", mat)
			root.add_child(mi)
			nodes += 1

# ------------------------------------------------------------------ the look viewpoints

## The 10 viewpoints compared across tiers (wiki 3D-plant, "Look"): near and far views of what a trainee must
## recognise (valves with their handwheels and bonnets, pumps and motors, flanges, the rack's pipes by colour).
const VIEWS := [
	["01-valves-2m", Vector3(7.0, 1.7, 8.6), Vector3(7.6, 1.0, 11.0)],
	["02-motor-fins-2m", Vector3(3.2, 1.3, 9.2), Vector3(4.5, 0.55, 11.0)],
	["03-flange-bolts-2m", Vector3(6.0, 2.2, -1.6), Vector3(6.0, 3.3, 1.2)],
	["04-handwheels-10m", Vector3(10.0, 1.7, 3.0), Vector3(14.0, 1.0, 17.0)],
	["05-rack-side-15m", Vector3(12.0, 1.7, -12.0), Vector3(12.0, 5.0, 3.0)],
	["06-pump-row-along", Vector3(-8.0, 1.7, 14.0), Vector3(40.0, 0.8, 11.0)],
	["07-rack-along", Vector3(-5.0, 1.7, 3.0), Vector3(60.0, 5.0, 3.0)],
	["08-platform", Vector3(30.0, 7.7, 14.0), Vector3(50.0, 6.0, 20.0)],
	["09-bay-from-above", Vector3(-10.0, 12.0, 5.0), Vector3(40.0, 0.0, 20.0)],
	["10-whole-plant", Vector3(130.0, 3.0, -15.0), Vector3(40.0, 3.0, 15.0)],
]

func _look() -> void:
	set_process(false)
	var tag := "%s_%s" % [preset, RenderingServer.get_current_rendering_method()]
	DirAccess.make_dir_recursive_absolute(out_dir.path_join("look"))
	for v in VIEWS:
		cam.position = v[1]
		cam.look_at(v[2], Vector3.UP)
		for i in range(90): await get_tree().process_frame   # LOD, fades and background shader compiles settle
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var p := out_dir.path_join("look/%s_%s.png" % [tag, v[0]])
		_say("look %s: error %d" % [p, img.save_png(p)])
	_write_out()
	get_tree().quit()

# ------------------------------------------------------------------ the walk and the log

func _process(delta: float) -> void:
	if first_frame_ms < 0:
		first_frame_ms = Time.get_ticks_msec()
		_say("first frame %d ms after the engine started (%d ms after the scene was ready)" % [first_frame_ms, first_frame_ms - ready_ms])
	t_run += delta
	var loop := 60.0
	var u := fmod(t_run, loop) / loop * (path.size() - 1)
	var i := int(u)
	var p := path[i].lerp(path[i + 1], u - i)
	var q := path[i + 1] + (path[min(i + 2, path.size() - 1)] - path[i + 1]) * 0.3
	cam.position = p
	if p.distance_to(q) > 0.01: cam.look_at(q + Vector3(0, -0.2, 0), Vector3.UP)
	if t_run > 5.0:
		times.append(delta * 1000.0)
		var vp := get_viewport().get_viewport_rid()
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp))
		calls.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	if t_run > seconds + 5.0: _finish()

## Peak and current resident memory of this process (kB), from /proc (Linux and Android): VmHWM is the peak RSS, an
## upper bound of the PSS the rule names.
func _proc_mem() -> Dictionary:
	var r := {}
	var f := FileAccess.open("/proc/self/status", FileAccess.READ)
	if f == null: return r
	while not f.eof_reached():   # /proc files report no length: read line by line
		var line := f.get_line()
		for k in ["VmHWM", "VmRSS"]:
			if line.begins_with(k + ":"): r[k] = int(line.split(":")[1].strip_edges().split(" ")[0])
	return r

func _finish() -> void:
	set_process(false)
	var n := times.size()
	if n == 0:
		_say("RESULT no frames")
		_write_out()
		get_tree().quit()
		return
	var s := times.duplicate(); s.sort()
	var over33 := 0; var over100 := 0
	for d in times:
		if d > 33.4: over33 += 1
		if d > 100.0: over100 += 1
	var pm := _proc_mem()
	_say("RESULT preset=%s variant=%s frames=%d median=%.1fms p95=%.1fms p99=%.1fms max=%.1fms fps_p95=%.1f over33=%.1f%% over100=%d peak_rss=%dMB rss=%dMB static_mem=%dMB vram=%dMB first_frame=%dms" % [
		preset, variant, n, s[n / 2], s[int(n * 0.95)], s[int(n * 0.99)], s[n - 1], 1000.0 / s[int(n * 0.95)],
		100.0 * over33 / n, over100, pm.get("VmHWM", -1024) / 1024, pm.get("VmRSS", -1024) / 1024,
		OS.get_static_memory_usage() / 1048576, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576,
		first_frame_ms])
	var g := gpu.duplicate(); g.sort(); var c := cpu.duplicate(); c.sort(); var dc := calls.duplicate(); dc.sort()
	_say("SPLIT preset=%s variant=%s gpu_median=%.1fms gpu_p95=%.1fms cpu_median=%.1fms cpu_p95=%.1fms drawcalls_median=%d drawcalls_p95=%d" % [
		preset, variant, g[n / 2], g[int(n * 0.95)], c[n / 2], c[int(n * 0.95)], dc[n / 2], dc[int(n * 0.95)]])
	# mean frame time per minute: shows a thermal drop over the run
	var per := PackedStringArray()
	var acc := 0.0; var k := 0; var minute := 0.0
	for d in times:
		acc += d; k += 1; minute += d
		if minute >= 60000.0:
			per.append("%.1f" % (acc / k)); acc = 0.0; k = 0; minute = 0.0
	_say("PER_MINUTE mean_ms=" + ",".join(per))
	_write_out()
	get_tree().quit()
