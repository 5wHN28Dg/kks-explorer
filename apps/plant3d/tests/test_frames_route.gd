## The frame-time walk's route (app/routes.gd `frames`, measured on the phones) walked once headless, so a phone run
## doesn't measure a walker stuck at a door or a pipe: out of the control room, through the turbine hall's two doors,
## up and down HRSG 1's stair tower and back. Fails when the walker is stuck for 5 s or falls below the ground.
extends RefCounted

const Plant = preload("res://app/plant.gd")
const Player = preload("res://app/player.gd")
const Autopilot = preload("res://app/autopilot.gd")
const Routes = preload("res://app/routes.gd")

func run(tree: SceneTree) -> Array:
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
	var route := Routes.frames(plant)
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
			problems.append("fell below the ground at %s (step %d)" % [str(player.global_position), auto.i])
			break
	if st.stuck != "":
		problems.append(st.stuck)
	elif not st.done:
		problems.append("the route did not end (at step %d)" % auto.i)
	print("  walked %d physics frames (%.0f s of walking)" % [frames, frames / 60.0])
	world.free()
	return problems
