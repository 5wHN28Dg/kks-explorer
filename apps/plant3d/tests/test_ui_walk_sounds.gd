## The people cues and the ambience (docs/plant3d/FIRST-TRAIN.md §6, ui/sound_player.gd), in the built plant: the
## walker's footsteps once a stride by the floor underfoot (the ground's concrete, HRSG 1's stair, its grating roof),
## none in flight; a sliding door plays its run as it starts, a roller door its loop while it moves; outdoors the wind
## and the distant plant play, inside a hall they fade out; the distant plant's level follows how much runs; the
## output's cap is a limiter on the master bus. (A small WAV stands in for the generator's files.)
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const SoundPlayer = preload("res://ui/sound_player.gd")
const Autopilot = preload("res://app/autopilot.gd")
const Routes = preload("res://app/routes.gd")
const Plant = preload("res://app/plant.gd")
const Parts = preload("res://tests/test_ui_parts.gd")


static func walk(tree: SceneTree, ui, route: Array, frames := 1800) -> String:
	var auto := Autopilot.new()
	ui.main.add_child(auto)
	var st := {"done": false, "stuck": ""}
	auto.finished.connect(func(): st.done = true)
	auto.stuck.connect(func(i, at): st.stuck = "stuck at step %d at %s" % [i, str(at)])
	auto.start(ui.player, route)
	for i in frames:
		await tree.physics_frame
		if st.done or st.stuck != "":
			break
	auto.stop()
	auto.queue_free()
	return st.stuck if st.stuck != "" else ("" if st.done else "the walk did not end")


static func place(tree: SceneTree, ui, at: Vector3) -> void:
	ui.player.set_mode(ui.player.Mode.FLY)
	ui.player.global_position = at
	ui.player.set_mode(ui.player.Mode.WALK)
	for i in 10:
		await tree.physics_frame


func run(tree: SceneTree) -> Array:
	var p: Array = []
	# the output's cap: one limiter, at the cap, however often it is asked for
	SoundPlayer.cap_output()
	var lim := SoundPlayer.cap_output()
	var bus := AudioServer.get_bus_index("Master")
	var n := 0
	for i in AudioServer.get_bus_effect_count(bus):
		n += 1 if AudioServer.get_bus_effect(bus, i) is AudioEffectHardLimiter else 0
	if n != 1 or lim.ceiling_db > SoundPlayer.OUTPUT_CAP_DB or not AudioServer.is_bus_effect_enabled(bus, 0):
		p.append("the master bus has %d limiters, ceiling %.1f dB" % [n, lim.ceiling_db])
	if SoundPlayer.distant_gain(0.0) != 0.0 or SoundPlayer.distant_gain(0.25) != 1.0 \
			or not SoundPlayer.distant_gain(0.05) > SoundPlayer.distant_gain(0.01):
		p.append("the distant plant's level does not follow how much runs")
	var dir := OS.get_user_data_dir().path_join("test_walk_sounds")
	DirAccess.make_dir_recursive_absolute(dir)
	var idx := {"format": "walkdown-plant-sound-files", "version": 1, "sounds": {}}
	for id in ["step_concrete", "step_grating", "step_stair", "door_slide"]:
		Parts.wav(dir.path_join(id + ".once.wav"), 0.2)
		idx.sounds[id] = {"loop": false, "layers": [{"layer": "once", "file": id + ".once.wav", "pitch": true}]}
	for id in ["door_roller", "wind", "plant_distant"]:
		Parts.wav(dir.path_join(id + ".noise.wav"), 0.5)
		idx.sounds[id] = {"loop": true, "layers": [{"layer": "noise", "file": id + ".noise.wav", "pitch": true}]}
	FileAccess.open(dir.path_join("index.json"), FileAccess.WRITE).store_string(JSON.stringify(idx))
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null:
		main.free()
		return p + ["the interaction layer did not start"]
	var s = ui.sounds
	s.load_index(dir)
	# the content build marks the floors: a grating deck, a concrete deck, a stair
	var marks := {"hrsg1_roof": "grating", "cw_pit_cover": "grating", "st_floor_12": "concrete", "hrsg1_stair": "stair"}
	for id in marks:
		var body: Node = main.plant.find_child(id, true, false)
		if body == null or SoundPlayer.surface_of(body) != marks[id]:
			p.append("%s does not sound as %s (%s)" % [id, marks[id], "missing" if body == null else SoundPlayer.surface_of(body)])
	# outdoors on the ground: concrete steps, about one a stride; the wind blows
	await place(tree, ui, Plant.g(86, 34.5, 0.05))
	s.played.clear()
	var r: String = await walk(tree, ui, [{"to": Plant.g(86, 34.5, 0), "floor": 0.0}, {"to": Plant.g(93.5, 44.5, 0), "floor": 0.0}])
	var metres := Vector2(93.5 - 86, 44.5 - 34.5).length()
	var c: int = s.played.get("step_concrete", 0)
	if r != "" or c < int(metres / SoundPlayer.STRIDE) - 2 or c > int(metres / SoundPlayer.STRIDE) + 2 or s.played.size() != 1:
		p.append("walking %.1f m on the ground: %s %s" % [metres, str(s.played), r])
	if s.outdoors < 0.99 or s._ambience.get("wind", []).is_empty():
		p.append("outdoors the wind does not blow (outdoors %.2f)" % s.outdoors)
	# up the first flights of HRSG 1's stair tower: steel stair steps
	s.played.clear()
	var path: Array = main.plant.stair_path("hrsg1_stair")
	r = await walk(tree, ui, path.slice(0, 3).map(func(q): return {"to": q, "floor": q.y}))     # to its first flight's foot
	s.played.clear()
	r += await walk(tree, ui, path.slice(2, 4).map(func(q): return {"to": q, "floor": q.y}))    # and up it
	if r != "" or s.played.get("step_stair", 0) < 4 or s.played.get("step_concrete", 0) > 1:
		p.append("climbing the stair (%s): %s %s" % [str(path.slice(0, 4)), str(s.played), r])
	# along HRSG 1's grating roof at +30
	await place(tree, ui, Plant.g(110, 56, 30.05))
	s.played.clear()
	r = await walk(tree, ui, [{"to": Plant.g(110, 56, 30), "floor": 30.0}, {"to": Plant.g(122, 56, 30), "floor": 30.0}])
	if r != "" or s.played.get("step_grating", 0) < 12 or s.played.has("step_concrete"):
		p.append("walking the grating roof: %s %s" % [str(s.played), r])
	# flying: no steps
	s.played.clear()
	ui.player.set_mode(ui.player.Mode.FLY)
	for i in 60:
		ui.player.global_position += Vector3(0.1, 0, 0)
		await tree.physics_frame
	if not s.played.is_empty():
		p.append("footsteps in flight: %s" % str(s.played))
	# inside the GT hall: the ambience fades out
	await place(tree, ui, Plant.g(10, 70, 0.05))
	for i in 90:
		await tree.process_frame
	if s.outdoors > 0.01 or not s._ambience.get("wind", []).is_empty():
		p.append("inside the GT hall the wind still blows (outdoors %.2f)" % s.outdoors)
	# the doors: the personnel door runs once as it opens; the roller door's loop plays while it moves
	var doors := {}
	for dn in tree.get_nodes_in_group("doors"):
		doors[String(dn.name)] = dn
	await place(tree, ui, Plant.g(30, 76, 0.05))
	s.played.clear()
	doors["gt1_door_n"].press()
	for i in 10:
		await tree.physics_frame
	if s.played.get("door_slide", 0) != 1:
		p.append("the personnel door did not play its run once: %s" % str(s.played))
	await place(tree, ui, Plant.g(40, 53, 0.05))
	doors["gt1_door_s"].press()
	for i in 10:
		await tree.physics_frame
	if s.played.get("door_roller", 0) != 1 or not s._doors.has(doors["gt1_door_s"]):
		p.append("the roller door's loop does not play while it moves: %s" % str(s.played))
	await place(tree, ui, Plant.g(10, 70, 0.05))      # away from it: it opens fully, waits and closes
	for i in 900:
		await tree.physics_frame
		if not doors["gt1_door_s"].moving:
			break
	if s._doors.has(doors["gt1_door_s"]):
		p.append("the roller door's loop plays on after it stopped")
	main.free()
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
	return p
