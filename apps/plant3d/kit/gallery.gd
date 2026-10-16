## Pictures of the parts kit's parts, to look at (not a test): each part with its defaults (or the first train's
## parameters) on gravel under the sun, from the front right and above, at a distance that fits it in the view.
## Needs a rendering device (tools/plant3d/bench/offscreen.sh):
##   godot --path apps/plant3d --script res://kit/gallery.gd -- --out=DIR [--parts=a,b] [--tier=full|lean+vis]
##     [--near=1]   (a second picture from 2 m: what a trainee sees standing beside it)
extends SceneTree

const Kit = preload("res://kit/kit.gd")
const Mat = preload("res://kit/materials.gd")

var args := {}
var mats := {}

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	_run.call_deferred()

func _mat(name: String) -> Material:
	if not mats.has(name):
		var specs := Mat.specs()
		var spec: Dictionary = specs.get(name, {})
		if name.begins_with("medium_"):
			spec = {"set": "", "tint": Color(0.1, 0.5, 0.2), "rough": 0.5, "metal": 0.0}
		if spec.is_empty():
			spec = specs.paint_grey
		mats[name] = Mat.make(name, spec, Mat.TIER_SIZE.get(args.get("tier", "full"), 1024))
	return mats[name]

func _params(part: String) -> Dictionary:
	var p := {}
	var dir := ProjectSettings.globalize_path("res://").path_join("../../data/plant3d/areas").simplify_path()
	for f in DirAccess.get_files_at(dir):
		var a = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(f)))
		if not a is Dictionary:
			continue
		var items: Array = []
		for e in a.get("equipment", []):
			items.append(e)
			items.append_array(e.get("parts", []))
		for q in a.get("pipes", []):
			items.append_array(q.get("valves", []))
			items.append_array(q.get("parts", []))
		for e in items:
			if e.part == part and p.is_empty():
				p = e.get("params", {})
	var full := Kit.params_of(part, p)
	var spec: Dictionary = Kit.kit_json().parts[part].params
	for k in spec:
		if not full.has(k):
			match spec[k].type:
				"pair": full[k] = [0, 100]
				"path": full[k] = [[0, 0, 5], [20, 0, 5]]
				"enum": full[k] = spec[k].values[0]
	return full

func _run() -> void:
	var out: String = args.get("out", OS.get_user_data_dir().path_join("gallery"))
	DirAccess.make_dir_recursive_absolute(out)
	var tier: String = args.get("tier", "full")
	var vp := root
	vp.scaling_3d_scale = 0.6 if tier == "lean+vis" else 1.0
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if tier == "lean+vis" else Viewport.SCALING_3D_MODE_BILINEAR
	var env := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = tier == "full"
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	ground.mesh = pm
	var gm: ShaderMaterial = _mat("gravel").duplicate()   # the weathered shader (kit/materials.gd)
	gm.set_shader_parameter("uv_scale", Vector2(400, 400) / 3.0)
	ground.material_override = gm
	root.add_child(ground)
	var cam := Camera3D.new()
	cam.fov = 70
	cam.far = 1500
	root.add_child(cam)
	cam.make_current()
	var parts: Array = []
	if args.has("parts"):
		parts = String(args.parts).split(",")
	else:
		for p in Kit.kit_json().parts:
			if Kit.has_part(p):
				parts.append(p)
	for part in parts:
		var ctx := {"pipe_od": 0.3} if part in ["valve_safety", "flow_element"] else {}
		var res := Kit.make(part, _params(part), ctx)
		var holder := Node3D.new()
		root.add_child(holder)
		var box := AABB()
		var first := true
		for k in res.layers:
			var L: Dictionary = res.layers[k]
			var mi := MeshInstance3D.new()
			mi.mesh = L.mesh
			mi.material_override = _mat(L.mat)
			holder.add_child(mi)
			box = L.mesh.get_aabb() if first else box.merge(L.mesh.get_aabb())
			first = false
		for mv in res.moving:
			if mv.name.ends_with("/on"):
				continue
			for k in mv.layers:
				var L: Dictionary = mv.layers[k]
				var mi := MeshInstance3D.new()
				mi.mesh = L.mesh
				mi.position = mv.pivot
				mi.material_override = _mat(L.mat)
				holder.add_child(mi)
				var bb: AABB = L.mesh.get_aabb()
				bb.position += mv.pivot
				box = bb if first else box.merge(bb)
				first = false
		var c := box.get_center()
		var r := box.size.length() * 0.5
		var dist := r / sin(deg_to_rad(cam.fov * 0.5 * 0.85))
		var dir := Vector3(0.9, 0.55, -1.0).normalized()   # from the front right (the part's +y is Godot's -z)
		cam.position = c + dir * maxf(dist, 0.6)
		cam.look_at(c, Vector3.UP)
		cam.near = maxf(0.02, dist * 0.01)
		for i in 20:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join("%s.png" % part))
		if args.has("near") and r > 1.5:
			cam.position = c + dir * 1.0 + Vector3(0, 0, 0) + (Vector3(dir.x, 0, dir.z).normalized() * (r * 0.6 + 2.0))
			cam.position.y = 1.7
			cam.look_at(Vector3(c.x, minf(c.y, 1.5), c.z), Vector3.UP)
			for i in 10:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out.path_join("%s_near.png" % part))
		holder.queue_free()
		print("gallery: %s %d triangles" % [part, res.tris])
	quit()
