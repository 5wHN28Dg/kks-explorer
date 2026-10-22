## The frame-time walks' routes (app/routes.gd `frames` and `camp`, measured on the phones) walked once headless, so a
## phone run doesn't measure a walker stuck at a door or a pipe: out of the control room, through the turbine hall's
## two doors, up and down HRSG 1's stair tower and back; and to the camp, into block 1's room 101 and the mess hall,
## their interiors loaded by the app's own loader (app/interiors.gd) as the walker comes near. Fails when the walker is
## stuck for 5 s or falls below the ground, or an interior on the way was not there when the walker went in.
extends RefCounted

const Plant = preload("res://app/plant.gd")
const Player = preload("res://app/player.gd")
const Autopilot = preload("res://app/autopilot.gd")
const Routes = preload("res://app/routes.gd")
const Interiors = preload("res://app/interiors.gd")

func run(tree: SceneTree) -> Array:
	var problems: Array = await walk(tree, "frames")
	problems.append_array(await walk(tree, "camp"))
	return problems

func walk(tree: SceneTree, which: String) -> Array:
	var problems: Array = []
	var world := Node3D.new()
	tree.root.add_child(world)
	var plant := Plant.new()
	world.add_child(plant)
	var err := plant.load_plant()
	if err != "":
		world.free()
		return [err]
	var player := Player.new()
	world.add_child(player)
	var st0: Array = plant.start()
	player.global_position = st0[0] + Vector3.UP * 0.05
	var interiors := Interiors.new()
	world.add_child(interiors)
	interiors.setup(plant, player)
	var route: Array = Routes.frames(plant) if which == "frames" else Routes.camp(plant)
	var inside_seen := {}
	var auto := Autopilot.new()
	world.add_child(auto)
	var st := {"stuck": "", "done": false}
	auto.stuck.connect(func(i, at): st.stuck = "stuck at step %d (%s) at %s" % [i, str(route[i]), str(at)])
	auto.finished.connect(func(): st.done = true)
	for i in 30:
		await tree.physics_frame
	auto.start(player, route)
	var frames := 0
	while not st.done and st.stuck == "" and frames < 60 * 60 * 20:
		await tree.physics_frame
		frames += 1
		if player.global_position.y < -0.2:
			problems.append("%s: fell below the ground at %s (step %d)" % [which, str(player.global_position), auto.i])
			break
		# inside an interior's building, its interior is there (loaded on the way, as in the app)
		for id in interiors.items:
			var r: Rect2 = interiors.items[id].rect
			if r.grow(-0.5).has_point(Vector2(player.global_position.x, -player.global_position.z)):
				inside_seen[id] = true
				if not interiors.loaded(id):
					problems.append("%s: walked into %s before its interior was loaded (step %d)" % [which, id, auto.i])
					st.stuck = "interior"
	if which == "camp" and (not inside_seen.has("block1_in") or not inside_seen.has("mess_in")):
		problems.append("camp: the walk went into %s, not block 1 and the mess hall" % str(inside_seen.keys()))
	if st.stuck != "" and st.stuck != "interior":
		problems.append("%s: %s" % [which, st.stuck])
	elif not st.done and st.stuck == "":
		problems.append("%s: the route did not end (at step %d)" % [which, auto.i])
	print("  %s: walked %d physics frames (%.0f s of walking)" % [which, frames, frames / 60.0])
	world.free()
	return problems
