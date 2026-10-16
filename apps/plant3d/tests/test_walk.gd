## The walking tests (decision 0054 §10): `climb` and `pit` (app/routes.gd). the built plant loaded as the app loads it, a walker with the app's own
## controls driven along a scripted route (app/routes.gd `climb`): up HRSG 1's nine-flight stair tower to +30, across
## the roof, up the stack's ladder to +40, then back down the ladder and the stair to the ground. It fails if the
## walker is stuck for 5 s, falls below the floor it should be on, or doesn't end where the route ends. Physics runs
## with the headless (dummy) renderer.
extends RefCounted

const Plant = preload("res://app/plant.gd")
const Player = preload("res://app/player.gd")
const Autopilot = preload("res://app/autopilot.gd")
const Routes = preload("res://app/routes.gd")

func run(tree: SceneTree) -> Array:
	var problems: Array = await walk(tree, "climb")
	problems.append_array(await walk(tree, "pit"))
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
	var route: Array = Routes.climb(plant) if which == "climb" else Routes.pit(plant)
	var start: Vector3 = route[0].to
	player.global_position = start + Vector3.UP * 0.05
	var auto := Autopilot.new()
	world.add_child(auto)
	var st := {"stuck": "", "done": false}
	auto.stuck.connect(func(i, at): st.stuck = "stuck at step %d (%s) at %s" % [i, str(route[i]), str(at)])
	auto.finished.connect(func(): st.done = true)
	# the floors the walker must never be below: the ground on the way, +30 on the HRSG roof, +40 at the top
	var top_reached := false
	var on_roof_low := INF
	var ladder_top := Plant.g(156, 63, 40)
	for i in 30:
		await tree.physics_frame
	auto.start(player, route)
	var frames := 0
	var max_frames := 60 * 60 * 12   # 12 minutes of walking at most
	while not st.done and st.stuck == "" and frames < max_frames:
		await tree.physics_frame
		frames += 1
		var p: Vector3 = player.global_position
		if p.y < (-0.2 if which == "climb" else -6.2):
			problems.append("fell below the ground at %s (step %d)" % [str(p), auto.i])
			break
		# walking to a point at a height (the roof at +30, the stack platform at +40): never below it
		if auto.i < route.size() and route[auto.i].has("floor") and player.mode == Player.Mode.WALK:
			var prev: Dictionary = route[auto.i - 1] if auto.i > 0 else {}
			var fl: float = minf(route[auto.i].floor, prev.get("floor", route[auto.i].floor))
			if p.y < fl - 0.2:
				problems.append("fell through the floor at +%.1f: at %s (step %d)" % [fl, str(p), auto.i])
				break
		if p.distance_to(ladder_top) < 0.6 and absf(p.y - 40.0) < 0.2:
			top_reached = true
	if st.stuck != "":
		problems.append(st.stuck)
	if frames >= max_frames:
		problems.append("the route did not end in 12 minutes (at step %d, %s)" % [auto.i, str(player.global_position)])
	if which == "climb" and not top_reached:
		problems.append("never stood on the stack platform at +40 next to the ladder")
	var end: Vector3 = route[-1].to
	if st.done and Vector2(player.global_position.x - end.x, player.global_position.z - end.z).length() > 0.5:
		problems.append("ended at %s, not at %s" % [str(player.global_position), str(end)])
	if st.done and absf(player.global_position.y - end.y) > 0.1:
		problems.append("ended at height %.2f, not at %.2f" % [player.global_position.y, end.y])
	print("  %s: walked %d physics frames (%.0f s), lowest point %.2f m" % [which, frames, frames / 60.0, player.lowest_y])
	world.free()
	return problems
