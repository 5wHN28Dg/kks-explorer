## Pictures of the people for checking by eye (not part of the build): every look, and every clip on one look.
##   tools/plant3d/bench/offscreen.sh godot --path apps/plant3d --script res://builder/people/shots.gd -- --out=DIR
## (after build.sh, which makes built/people/). Writes DIR/looks.png, DIR/clips.png and DIR/posed.png.
extends SceneTree

func _init() -> void:
	var out := "user://people_shots"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	var info = JSON.parse_string(FileAccess.get_file_as_string("res://built/people/people.json"))
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.68, 0.74)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.55)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var floor_ := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor_.mesh = pm
	root.add_child(floor_)
	var cam := Camera3D.new()
	cam.fov = 40
	root.add_child(cam)
	var scene: PackedScene = load(info.avatar)
	# 1. the looks, idle, front and three-quarter
	var made := []
	var i := 0
	for id in info.looks:
		for turn in [0.0, 2.4]:
			var av: Node3D = scene.instantiate()
			root.add_child(av)
			av.position = Vector3(i * 0.75 - 5.6, 0, 0)
			av.rotation.y = turn
			var body: MeshInstance3D = av.get_node("Skeleton3D/Body")
			body.mesh = load(info.looks[id].lod0)
			var ap: AnimationPlayer = av.get_node("Anim")
			ap.play("idle")
			ap.advance(0.3)
			made.append(av)
			i += 1
	cam.look_at_from_position(Vector3(0, 1.3, 9.5), Vector3(0, 0.9, 0))
	await _save(out.path_join("looks.png"))
	for n in made:
		n.free()
	made.clear()
	# 2. every clip on the operator's look, a third of the way through
	i = 0
	for c in info.clips:
		var av: Node3D = scene.instantiate()
		root.add_child(av)
		av.position = Vector3((i % 8) * 1.4 - 4.9, 0, -(i / 8) * 2.4)
		av.rotation.y = 0.6
		var ap: AnimationPlayer = av.get_node("Anim")
		ap.play(c)
		ap.advance(ap.current_animation_length * 0.33)
		var l := Label3D.new()
		l.text = c
		l.pixel_size = 0.004
		l.position = Vector3(0, 2.05, 0)
		av.add_child(l)
		made.append(av)
		i += 1
	cam.look_at_from_position(Vector3(0, 3.2, 10.0), Vector3(0, 0.6, -2.4))
	await _save(out.path_join("clips.png"))
	for n in made:
		n.free()
	made.clear()
	# 3. the posed band's meshes of one look, and LOD 1
	i = 0
	for p in info.looks.operator.posed:
		var mi := MeshInstance3D.new()
		mi.mesh = load(info.looks.operator.posed[p])
		mi.position = Vector3(i * 1.1 - 3.0, 0, 0)
		mi.rotation.y = 0.6
		root.add_child(mi)
		made.append(mi)
		i += 1
	var av2: Node3D = scene.instantiate()
	root.add_child(av2)
	av2.position = Vector3(i * 1.1 - 3.0, 0, 0)
	(av2.get_node("Skeleton3D/Body") as MeshInstance3D).mesh = load(info.looks.operator.lod1)
	(av2.get_node("Anim") as AnimationPlayer).play("walk")
	(av2.get_node("Anim") as AnimationPlayer).advance(0.2)
	# the road variant: the hat carried, walking and standing at the phone (the office look)
	for k in 2:
		var av3: Node3D = scene.instantiate()
		root.add_child(av3)
		av3.position = Vector3((i + 1 + k) * 1.1 - 3.0, 0, 0)
		av3.rotation.y = 0.9
		(av3.get_node("Skeleton3D/Body") as MeshInstance3D).mesh = load(info.looks.office.lod0_road)
		var ap3: AnimationPlayer = av3.get_node("Anim")
		ap3.play("walk_road" if k == 0 else "idle_road")
		ap3.advance(0.3)
	cam.look_at_from_position(Vector3(1.5, 1.3, 8.5), Vector3(1.5, 0.9, 0))
	await _save(out.path_join("posed.png"))
	quit()


func _save(path: String) -> void:
	for k in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("people: ", path)
