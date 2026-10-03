## The engine bench (decision 0041): a pipe rack and pump bay of about 2 M triangles at full detail, built by script
## from parametric parts (the way the plant will be built from its description), 40 PBR materials (5 CC0 texture sets
## in tinted variants), one sun with shadows, a walking camera on a fixed loop, and a frame-time log.
## Command line (desktop): -- --seconds=60 --variant=nodes|merged
extends Node3D

const TEX := "res://tex/"
var mats: Array[StandardMaterial3D] = []
var meshes := {}
var times: PackedFloat32Array = PackedFloat32Array()
var gpu: PackedFloat32Array = PackedFloat32Array()
var cpu: PackedFloat32Array = PackedFloat32Array()
var calls: PackedInt32Array = PackedInt32Array()
var t_run := 0.0
var seconds := 600.0
var variant := "nodes"
var preset := "full"   # full | scaled | lean | lean2 (2 shadow cascades) | lean_noshadow: the phone tier's levers (decision 0041)
var cam: Camera3D
var path: Array[Vector3] = []
var tris := 0
var nodes := 0
var started_ms := 0
var first_frame_ms := -1
var save_to := ""        # desktop: -- --save=res://built/plant.scn writes the built plant as a scene
var prebuilt := false    # load res://built/plant.scn instead of building (what a shipped app would do)
var root: Node3D         # the plant's geometry (everything _build makes)

func _ready() -> void:
	started_ms = Time.get_ticks_msec()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seconds="): seconds = float(a.split("=")[1])
		if a.begins_with("--variant="): variant = a.split("=")[1]
		if a.begins_with("--preset="): preset = a.split("=")[1]
		if a.begins_with("--save="): save_to = a.split("=")[1]
		if a == "--prebuilt": prebuilt = true
	var f := FileAccess.open("/storage/emulated/0/Android/data/kks.plant3d.bench/files/preset.txt", FileAccess.READ)  # Android: adb push
	if f:
		for line in f.get_as_text().split("\n"):
			if line.begins_with("preset="): preset = line.split("=")[1].strip_edges()
			if line.begins_with("seconds="): seconds = float(line.split("=")[1])
			if line.begins_with("variant="): variant = line.split("=")[1].strip_edges()
			if line.strip_edges() == "prebuilt=1": prebuilt = true
	_apply_preset()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	_environment()
	var t0 := Time.get_ticks_msec()
	if prebuilt:
		root = (load("res://built/plant.scn") as PackedScene).instantiate()
		add_child(root)
		print("bench: loaded the pre-built plant in ", Time.get_ticks_msec() - t0, " ms")
	else:
		root = Node3D.new()
		root.name = "Plant"
		add_child(root)
		_materials()
		_build()
		print("bench: built the plant in ", Time.get_ticks_msec() - t0, " ms")
		if save_to != "":
			for c in root.get_children(): c.owner = root
			var ps := PackedScene.new()
			ps.pack(root)
			DirAccess.make_dir_recursive_absolute(save_to.get_base_dir())
			print("bench: saved ", save_to, ": ", ResourceSaver.save(ps, save_to))
			get_tree().quit()
	cam = Camera3D.new()
	cam.fov = 70
	cam.far = 400
	add_child(cam)
	path = [Vector3(-5, 1.7, -4), Vector3(65, 1.7, -4), Vector3(65, 1.7, 14), Vector3(30, 7.7, 14),
			Vector3(-5, 7.7, 14), Vector3(-5, 1.7, 4), Vector3(-5, 1.7, -4)]
	print("bench: ", variant, " preset=", preset, " renderer=", RenderingServer.get_current_rendering_method(), " tris=", tris, " nodes=", nodes,
		" device=", RenderingServer.get_video_adapter_name())

func _apply_preset() -> void:
	var vp := get_viewport()
	if preset != "full":
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		vp.scaling_3d_scale = 0.7 if preset == "scaled" else 0.6
	if preset.begins_with("lean"):   # lean, lean2, lean_vis, lean_noshadow
		RenderingServer.directional_shadow_atlas_set_size(2048, true)
		vp.mesh_lod_threshold = 4.0

# ------------------------------------------------------------------ materials: 5 CC0 sets x 8 tints = 40

func _tex(name: String) -> Texture2D:
	var p := TEX + name
	return load(p) if ResourceLoader.exists(p) else null

func _materials() -> void:
	var sets := ["PaintedMetal009", "Metal032", "MetalPlates006", "Concrete034", "Grate001"]
	var tints := [Color(1, 1, 1), Color(0.75, 0.2, 0.15), Color(0.2, 0.45, 0.25), Color(0.25, 0.35, 0.7),
				  Color(0.9, 0.75, 0.2), Color(0.6, 0.6, 0.62), Color(0.35, 0.35, 0.38), Color(0.85, 0.85, 0.8)]
	for s in sets:
		for t in tints:
			var m := StandardMaterial3D.new()
			m.albedo_texture = _tex(s + "_2K-JPG_Color.jpg")
			m.albedo_color = t
			var n := _tex(s + "_2K-JPG_NormalGL.jpg")
			if n:
				m.normal_enabled = true
				m.normal_texture = n
			m.roughness_texture = _tex(s + "_2K-JPG_Roughness.jpg")
			m.roughness = 1.0
			var mt := _tex(s + "_2K-JPG_Metalness.jpg")
			if mt:
				m.metallic_texture = mt
				m.metallic = 1.0
			var ao := _tex(s + "_2K-JPG_AmbientOcclusion.jpg")
			if ao:
				m.ao_enabled = true
				m.ao_texture = ao
			m.uv1_scale = Vector3(2, 2, 2)
			mats.append(m)

func _mat(set_i: int, tint: int) -> StandardMaterial3D: return mats[set_i * 8 + tint]

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
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40 if preset.begins_with("lean") else 80
	sun.shadow_enabled = preset != "lean_noshadow"
	if preset == "lean2": sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS   # 2 cascades, not 4
	add_child(sun)

# ------------------------------------------------------------------ parametric parts (with generated LODs)

func _lod(m: PrimitiveMesh) -> Mesh:
	## a primitive as an ArrayMesh with LODs generated the way imported models get them
	var im := ImporterMesh.new()
	var arrays := m.get_mesh_arrays()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	im.generate_lods(25.0, 60.0, [])
	return im.get_mesh()

var far := {}   # mesh id -> metres beyond which the part isn't drawn (presets lean_vis): small parts carry no information far away

func _part(key: String, make: Callable) -> Mesh:
	if not meshes.has(key):
		meshes[key] = _lod(make.call())
		var d := {"bolt": 15.0, "fins": 25.0, "wheel": 60.0, "bonnet": 60.0}
		if d.has(key): far[meshes[key].get_instance_id()] = d[key]
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

var cells := {}   # variant "cells": (mesh, material, 12 m cell) -> transforms, drawn as one MultiMesh each

func _put(mesh: Mesh, mat: Material, xf: Transform3D) -> void:
	tris += _tri_count(mesh)
	if variant == "cells":
		var cell := Vector2i(int(floor(xf.origin.x / 12.0)), int(floor(xf.origin.z / 12.0)))
		var key := [mesh.get_instance_id(), mat.get_instance_id(), cell]
		if not cells.has(key): cells[key] = [mesh, mat, []]
		cells[key][2].append(xf)
		return
	if variant == "merged":
		var key := mat.get_instance_id()
		if not batch.has(key):
			var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES); batch[key] = [st, mat]
		batch[key][0].append_from(mesh, 0, xf)
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = xf
	root.add_child(mi)
	nodes += 1

func _tri_count(mesh: Mesh) -> int:
	var a := mesh.surface_get_arrays(0)
	var idx = a[Mesh.ARRAY_INDEX]
	return (idx.size() if idx != null else a[Mesh.ARRAY_VERTEX].size()) / 3

# ------------------------------------------------------------------ the scene

func _build() -> void:
	# ground
	_put(_part("ground", func(): return _box(140, 0.2, 50)), _mat(3, 5), Transform3D(Basis(), Vector3(60, -0.1, 12)))
	# pipe rack: 3 tiers, columns every 6 m along 60 m
	var col := _part("col", func(): return _box(0.3, 9, 0.3))
	var beam := _part("beam", func(): return _box(0.25, 0.3, 6))
	var lbeam := _part("lbeam", func(): return _box(6, 0.3, 0.25))
	for i in range(21):
		var x := i * 6.0
		for z in [0.0, 6.0]:
			_put(col, _mat(0, 4), Transform3D(Basis(), Vector3(x, 4.5, z)))
		for y in [3.0, 6.0, 9.0]:
			_put(beam, _mat(0, 4), Transform3D(Basis(), Vector3(x, y, 3)))
			if i < 20:
				for z in [0.0, 6.0]:
					_put(lbeam, _mat(0, 4), Transform3D(Basis(), Vector3(x + 3, y, z)))
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
				_put(pipe, _mat(2 if clad else 0, 5 if clad else tints[k]), Transform3D(Basis(Vector3(0, 0, 1), PI / 2), Vector3(x, y, z)))
				_put(flange, _mat(1, 5), Transform3D(Basis(Vector3(0, 0, 1), PI / 2), Vector3(x + 3, y, z)))
				for b in range(8):
					var ang := b * TAU / 8
					_put(bolt, _mat(1, 6), Transform3D(Basis(Vector3(0, 0, 1), PI / 2), Vector3(x + 3, y + cos(ang) * r * 1.5, z + sin(ang) * r * 1.5)))
	# pump bay: 2 rows x 6 pumps with motor, casing, baseplate, suction/discharge valves with handwheels
	var motor := _part("motor", func(): return _cyl(0.35, 1.0, 48))
	var fins := _part("fins", func(): return _torus(0.37, 0.02, 64, 8))
	var casing := _part("casing", func(): return _torus(0.32, 0.18, 48, 24))
	var base := _part("base", func(): return _box(2.4, 0.15, 0.9))
	var vbody := _part("vbody", func(): return _cyl(0.14, 0.5, 32))
	var bonnet := _part("bonnet", func(): return _cyl(0.06, 0.6, 24))
	var wheel := _part("wheel", func(): return _torus(0.18, 0.015, 64, 12))
	var grate := _part("grate", func(): return _box(6, 0.05, 3))
	for row in range(4):
		for p in range(13):
			var o := Vector3(5 + p * 9.0, 0, 11 + row * 6.0)
			_put(base, _mat(0, 6), Transform3D(Basis(), o + Vector3(0, 0.08, 0)))
			_put(motor, _mat(0, 3), Transform3D(Basis(Vector3(0, 0, 1), PI / 2), o + Vector3(-0.5, 0.55, 0)))
			for f in range(8):
				_put(fins, _mat(0, 3), Transform3D(Basis(Vector3(0, 0, 1), PI / 2), o + Vector3(-0.9 + f * 0.1, 0.55, 0)))
			_put(casing, _mat(0, 2), Transform3D(Basis(Vector3(1, 0, 0), PI / 2), o + Vector3(0.7, 0.55, 0)))
			for v in range(4):
				var vo := o + Vector3(1.4 + v * 0.8, 0.9, 0)
				_put(vbody, _mat(1, 6), Transform3D(Basis(), vo))
				_put(bonnet, _mat(1, 6), Transform3D(Basis(), vo + Vector3(0, 0.5, 0)))
				_put(wheel, _mat(0, 1), Transform3D(Basis(), vo + Vector3(0, 0.82, 0)))
			_put(grate, _mat(4, 6), Transform3D(Basis(), o + Vector3(1.5, 6.0, 0)))
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
			mmi.material_override = e[1]
			if preset.ends_with("_vis") and far.has(e[0].get_instance_id()):
				mmi.visibility_range_end = far[e[0].get_instance_id()]
			root.add_child(mmi)
			nodes += 1
	if variant == "merged":
		for key in batch:
			var mi := MeshInstance3D.new()
			mi.mesh = batch[key][0].commit()
			mi.material_override = batch[key][1]
			root.add_child(mi)
			nodes += 1

# ------------------------------------------------------------------ the walk and the log

func _process(delta: float) -> void:
	if first_frame_ms < 0:
		first_frame_ms = Time.get_ticks_msec() - started_ms
		print("bench: first frame after ", first_frame_ms, " ms")
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

func _finish() -> void:
	var s := times.duplicate(); s.sort()
	var n := s.size()
	var over33 := 0; var over100 := 0
	for d in times:
		if d > 33.4: over33 += 1
		if d > 100.0: over100 += 1
	var mem := OS.get_static_memory_usage()
	print("bench: RESULT preset=" + preset + " variant=%s frames=%d median=%.1fms p95=%.1fms p99=%.1fms max=%.1fms fps_p95=%.1f over33=%.1f%% over100=%d static_mem=%dMB vram=%dMB first_frame=%dms" % [
		variant, n, s[n / 2], s[int(n * 0.95)], s[int(n * 0.99)], s[n - 1], 1000.0 / s[int(n * 0.95)],
		100.0 * over33 / n, over100, mem / 1048576, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576, first_frame_ms])
	var g := gpu.duplicate(); g.sort(); var c := cpu.duplicate(); c.sort(); var dc := calls.duplicate(); dc.sort()
	print("bench: SPLIT preset=%s variant=%s gpu_median=%.1fms gpu_p95=%.1fms cpu_median=%.1fms cpu_p95=%.1fms drawcalls_median=%d drawcalls_p95=%d" % [
		preset, variant, g[n / 2], g[int(n * 0.95)], c[n / 2], c[int(n * 0.95)], dc[n / 2], dc[int(n * 0.95)]])
	get_tree().quit()
