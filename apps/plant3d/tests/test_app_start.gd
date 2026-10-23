## The app as it starts (app/main.tscn), headless: every script under app/ compiles, the start loads the built plant,
## puts the walker at the plant's start in the control building, and makes the HUD, the map and the settings; the
## map opens, holds the walker's controls while open, and closes after a jump; a tap on the map lands on a free floor.
extends RefCounted

const Lighting = preload("res://app/lighting.gd")
const Quality = preload("res://app/quality.gd")

func run(tree: SceneTree) -> Array:
	var p: Array = []
	for f in DirAccess.get_files_at("res://app"):
		if f.ends_with(".gd"):
			var s: GDScript = load("res://app/" + f)
			if s == null or not s.can_instantiate():
				p.append("app/%s does not compile" % f)
	if not p.is_empty():
		return p
	var main: Node = (load("res://app/main.tscn") as PackedScene).instantiate()
	tree.root.add_child(main)
	for i in 20:
		await tree.process_frame
	if main.player == null:
		main.free()
		return ["the app did not load the plant"]
	if main.area_at(main.player.global_position) != "Control building":
		p.append("the walker starts in %s, not the control building" % main.area_at(main.player.global_position))
	if main.tier == "":
		p.append("no quality tier was chosen")
	# (RenderingServer has no getter for the filter: the start records what it set)
	var want_filter := "bicubic" if Lighting.lightmap_bicubic(Quality.is_phone(), RenderingServer.get_video_adapter_name()) else "bilinear"
	if main.lightmap_filter != want_filter:
		p.append("the start sets the lightmap's filter for this device (app/lighting.gd lightmap_bicubic)")
	# before the plant loads: the filter is part of every lit pipeline
	var i_filter: int = Array(main.lines).find_custom(func(s): return s.begins_with("lightmap filter:"))
	var i_plant: int = Array(main.lines).find_custom(func(s): return s.begins_with("loaded the plant"))
	if i_filter < 0 or i_plant < 0 or i_filter > i_plant:
		p.append("the lightmap's filter is set before the plant loads (lines %d and %d)" % [i_filter, i_plant])
	main.toggle_map()
	if not main.map.active or main.player.input_enabled:
		p.append("the map opens and holds the walker's controls")
	# a tap above the control building: inside it on the ground, not on its roof
	main.map.cam.global_position = Vector3(-20, 100, 0)
	main.map.cam.look_at(Vector3(-20, 0, 0.01), Vector3.UP)
	var got := {"at": null}
	main.map.jumped.connect(func(at): got.at = at)
	await tree.physics_frame
	main.map._jump(main.map.cam.unproject_position(Vector3(-20, 0, 0)))
	if got.at == null or absf(got.at.y) > 0.1:
		p.append("a tap on the control building lands at %s, not on its ground floor" % str(got.at))
	# the jump closes the map and puts the walker there
	if main.map.active or not main.player.input_enabled:
		p.append("after a jump the map closes and gives the controls back")
	elif got.at != null and main.player.global_position.distance_to(got.at) > 0.2:
		p.append("the walker was not put where the map was tapped")
	main.free()
	return p
