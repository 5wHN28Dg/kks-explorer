## Pictures of the Workshop's kinds (docs/plant3d/WORKSHOP.md §10), to look at (not a test): each built Workshop scene
## (built/workshop/<part>.scn, after build.sh) in the Workshop's own light, assembled, half and fully taken apart
## (workshop/explode.gd), from the front right and above. K3 adds cut away and running. Needs a rendering device
## (tools/plant3d/bench/offscreen.sh):
##   godot --path apps/plant3d --script res://kit/gallery_workshop.gd -- --out=DIR [--parts=a,b]
extends SceneTree

const Explode = preload("res://workshop/explode.gd")
const WS = preload("res://workshop/workshop.gd")

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var out: String = args.get("out", OS.get_user_data_dir().path_join("gallery_workshop"))
	DirAccess.make_dir_recursive_absolute(out)
	var parts: Array = String(args.get("parts", "")).split(",", false) if args.has("parts") else WS.kinds()
	root.size = Vector2i(1600, 900)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.30, 0.32, 0.34)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.80, 0.84)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(35), 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	root.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.005
	root.add_child(cam)
	cam.current = true
	for part in parts:
		var path := "res://built/workshop/%s.scn" % part
		if not ResourceLoader.exists(path):
			print("gallery_workshop: no ", path)
			continue
		var m: Node3D = (load(path) as PackedScene).instantiate()
		root.add_child(m)
		_resolve(m)
		var spec := Explode.spec_of(m)
		var homes := {}
		_homes(m, homes)
		var box: AABB = m.get_meta("box")
		for s in [0.0, 0.5, 1.0]:
			var off := Explode.offsets(spec, s)
			for id in homes:
				var n: Node3D = homes[id][0]
				n.transform = Transform3D(homes[id][1].basis, homes[id][1].origin + off.get(id, Vector3.ZERO))
			var grown := box.grow(box.size.length() * 0.6 * s)
			var r := grown.size.length() * 0.5
			var dir := Vector3(0.8, 0.55, 1.0).normalized()
			cam.global_position = grown.get_center() + dir * (r / tan(deg_to_rad(20.0)) * 1.1)
			cam.look_at(grown.get_center(), Vector3.UP)
			for i in 6:
				await process_frame
			await RenderingServer.frame_post_draw
			var file := out.path_join("%s_%s.png" % [part, ["assembled", "half", "exploded"][int(s * 2)]])
			root.get_texture().get_image().save_png(file)
			print("gallery_workshop: ", file)
		m.queue_free()
		await process_frame
	quit()

func _resolve(n: Node) -> void:
	if (n is MeshInstance3D or n is MultiMeshInstance3D) and n.has_meta("mat"):
		var p := "res://built/materials/%s.tres" % n.get_meta("mat")
		if ResourceLoader.exists(p):
			n.material_override = load(p)
	if n.has_meta("items"):
		var items: Array = n.get_meta("items")
		for c in n.get_children():
			if c is MultiMeshInstance3D:
				c.multimesh.instance_count = items.size()
				for i in items.size():
					c.multimesh.set_instance_transform(i, items[i])
	for c in n.get_children():
		_resolve(c)

func _homes(n: Node, out: Dictionary) -> void:
	for c in n.get_children():
		if c.has_meta("explode"):
			out[c.get_meta("id")] = [c, c.transform]
		_homes(c, out)
