## The walking tests (decision 0054 §10): the built plant loaded as the app loads it, a walker with the app's own
## controls driven by app/autopilot.gd. It fails if the walker is stuck for 5 s, falls below the floor it should be
## on, or doesn't end where the route ends. Physics runs with the headless (dummy) renderer.
##   climb, pit      the scripted routes of app/routes.gd: HRSG 1's nine-flight stair tower, its roof and the stack's
##                   ladder to +40 and back; the turbine hall's condenser pit stair and back
##   every stair     up its own path from its foot to its top, and down again, walking, running and at the slow pace
##   every ladder    up from its foot and down from its top, the same three ways
##   every route     the walking directions (app/walk_route.gd, PLANT3D.md §8): from the control room, the path finder
##                   reaches every stop of every tour and the equipment of every procedure step with "go": "walk", and
##                   the walker follows its routes in the order a trainee meets them, stop after stop, and the
##                   path finder's ways up and down every stair and ladder
extends RefCounted

const Plant = preload("res://app/plant.gd")
const Player = preload("res://app/player.gd")
const Autopilot = preload("res://app/autopilot.gd")
const Routes = preload("res://app/routes.gd")
const WalkRoute = preload("res://app/walk_route.gd")
const SceneIndex = preload("res://ui/scene_index.gd")

const REACH := 6.0                 # ui/plant_ui.gd: within this a trainee works the equipment's local controls
const PROCEDURES := "res://built/content/procedures"

func run(tree: SceneTree) -> Array:
	var problems: Array = await walk(tree, "climb")
	problems.append_array(await walk(tree, "pit"))
	problems.append_array(await stairs_and_ladders(tree))
	problems.append_array(await routes(tree))
	return problems

## A world with the built plant and a walker in it: [world, plant, player], or [the error].
func _world(tree: SceneTree) -> Array:
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
	return [world, plant, player]

func _place(tree: SceneTree, player, at: Vector3) -> void:
	player.set_mode(Player.Mode.WALK)
	player.velocity = Vector3.ZERO
	player.global_position = at + Vector3.UP * 0.05
	for i in 10:
		await tree.physics_frame

## Walks `route` (autopilot steps) from where the walker stands; the problems. Walking towards a point at a height,
## the feet are never more than `floor_margin` below it or below the point before it; the walk ends within 0.5 m of the
## last point in plan and `end_h` in height.
func _follow(tree: SceneTree, world: Node, player, route: Array, what: String, floor_margin := 0.2, end_h := 0.1) -> Array:
	var problems: Array = []
	var auto := Autopilot.new()
	world.add_child(auto)
	var st := {"stuck": "", "done": false}
	auto.stuck.connect(func(i, at): st.stuck = "%s: stuck at step %d (%s) at %s" % [what, i, str(route[i]), str(at)])
	auto.finished.connect(func(): st.done = true)
	auto.start(player, route)
	var frames := 0
	var max_frames := 60 * 60 * 12   # 12 minutes of walking at most
	while not st.done and st.stuck == "" and frames < max_frames:
		await tree.physics_frame
		frames += 1
		var p: Vector3 = player.global_position
		if p.y < -12.0:
			problems.append("%s: fell out of the plant at %s (step %d)" % [what, str(p), auto.i])
			break
		if auto.i < route.size() and route[auto.i].has("floor") and player.mode == Player.Mode.WALK:
			var prev: Dictionary = route[auto.i - 1] if auto.i > 0 else {}
			var fl: float = minf(route[auto.i].floor, prev.get("floor", route[auto.i].floor))
			if p.y < fl - floor_margin:
				problems.append("%s: fell through the floor at +%.1f: at %s (step %d)" % [what, fl, str(p), auto.i])
				break
	auto.stop()
	auto.free()
	if st.stuck != "":
		problems.append(st.stuck)
	if frames >= max_frames:
		problems.append("%s: did not end in 12 minutes (at step %d, %s)" % [what, auto.i, str(player.global_position)])
	var last: Dictionary = route[-1]
	if st.done and last.has("to"):
		var end: Vector3 = last.to
		if Vector2(player.global_position.x - end.x, player.global_position.z - end.z).length() > 0.5:
			problems.append("%s: ended at %s, not at %s" % [what, str(player.global_position), str(end)])
		elif absf(player.global_position.y - end.y) > end_h:
			problems.append("%s: ended at height %.2f, not at %.2f" % [what, player.global_position.y, end.y])
	return problems

func walk(tree: SceneTree, which: String) -> Array:
	var w := _world(tree)
	if w.size() == 1:
		return w
	var world: Node3D = w[0]
	var player = w[2]
	var route: Array = Routes.climb(w[1]) if which == "climb" else Routes.pit(w[1])
	player.global_position = route[0].to + Vector3.UP * 0.05
	for i in 30:
		await tree.physics_frame
	var seen := {"top": false, "fell": null}
	var ladder_top := Plant.g(156, 63, 40)
	var watch := func():
		var p: Vector3 = player.global_position
		if p.distance_to(ladder_top) < 0.6 and absf(p.y - 40.0) < 0.2:
			seen.top = true
		if seen.fell == null and p.y < (-0.2 if which == "climb" else -6.2):
			seen.fell = p
	tree.physics_frame.connect(watch)
	var problems := await _follow(tree, world, player, route, which)
	tree.physics_frame.disconnect(watch)
	if seen.fell != null:
		problems.append("%s: fell below the ground at %s" % [which, str(seen.fell)])
	if which == "climb" and not seen.top:
		problems.append("never stood on the stack platform at +40 next to the ladder")
	print("  %s: lowest point %.2f m" % [which, player.lowest_y])
	world.free()
	return problems

## Every stair up and down its own path, every ladder up and down.
func stairs_and_ladders(tree: SceneTree) -> Array:
	var w := _world(tree)
	if w.size() == 1:
		return w
	var world: Node3D = w[0]
	var plant = w[1]
	var player = w[2]
	var problems: Array = []
	var t0 := Time.get_ticks_msec()
	if plant.manifest.stairs.size() < 7 or plant.manifest.ladders.is_empty():
		problems.append("the first train has %d stairs and %d ladders, not 7 and 1" % [plant.manifest.stairs.size(), plant.manifest.ladders.size()])
	# at a walk, running, and at the slow pace (the walker's speed is the trainee's: app/player.gd speed_for)
	for g in [{"what": "walking", "run": false, "pace": Player.WALK_SPEED}, {"what": "running", "run": true, "pace": Player.WALK_SPEED},
			{"what": "at the slow pace", "run": false, "pace": Player.PACES.slow}]:
		player.run = g.run
		player.pace = g.pace
		for s in plant.manifest.stairs:
			var up: Array = plant.stair_path(s.id).map(func(p): return {"to": p, "floor": p.y})
			var down := up.duplicate()
			down.reverse()
			await _place(tree, player, up[0].to)
			# the walker stops within reach of a point in plan: at a flight's end that is on its slope, which starts a going
			# before the first riser (builder/plant_builder.gd), up to half a metre from the point's height
			problems.append_array(await _follow(tree, world, player, up, "stair %s up %s" % [s.id, g.what], 0.2, 0.5))
			problems.append_array(await _follow(tree, world, player, down, "stair %s down %s" % [s.id, g.what], 0.2, 0.5))
		for l in plant.manifest.ladders:
			var foot: Vector3 = plant.v3(l.foot)
			var ex: Vector3 = plant.v3(l.exit)
			await _place(tree, player, foot)
			problems.append_array(await _follow(tree, world, player, [{"ladder": l.id, "dir": "up"}], "ladder %s up %s" % [l.id, g.what]))
			if absf(player.global_position.y - ex.y) > 0.2:
				problems.append("ladder %s up %s: ended at height %.2f, not at its top %.2f" % [l.id, g.what, player.global_position.y, ex.y])
			problems.append_array(await _follow(tree, world, player, [{"ladder": l.id, "dir": "down"}], "ladder %s down %s" % [l.id, g.what]))
			if absf(player.global_position.y - foot.y) > 0.2:
				problems.append("ladder %s down %s: ended at height %.2f, not at its foot %.2f" % [l.id, g.what, player.global_position.y, foot.y])
	player.run = false
	player.pace = Player.WALK_SPEED
	print("  %d stairs and %d ladders walked both ways at three gaits in %d ms" % [plant.manifest.stairs.size(), plant.manifest.ladders.size(), Time.get_ticks_msec() - t0])
	world.free()
	return problems

## The tours' stops and the procedures' walking steps, in their order: [procedure id, step id, code].
static func targets() -> Array:
	var out: Array = []
	var files := Array(DirAccess.get_files_at(PROCEDURES))
	files.sort()
	for f in files:
		if not f.ends_with(".json"):
			continue
		var p: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PROCEDURES.path_join(f)))
		for s in p.steps:
			if p.kind == "tour" or s.get("go", "") == "walk":
				for c in s.get("at", []):
					out.append([p.id, s.id, c])
	return out

## From the control room the path finder reaches every target; the walker follows each procedure's and tour's routes
## from the control room, target after target.
func routes(tree: SceneTree) -> Array:
	var w := _world(tree)
	if w.size() == 1:
		return w
	var world: Node3D = w[0]
	var plant = w[1]
	var player = w[2]
	var problems: Array = []
	var nav := WalkRoute.new()
	world.add_child(nav)
	var err := nav.setup(plant)
	if err != "":
		world.free()
		return [err]
	var index := SceneIndex.new()
	index.scan(plant)
	for i in 600:
		if nav.ready_to_find():
			break
		await tree.physics_frame
	if not nav.ready_to_find():
		world.free()
		return ["the navigation map never became ready"]
	var start: Vector3 = plant.start()[0]
	var tg := targets()
	if tg.size() < 48:
		problems.append("only %d walking targets in the procedures and tours" % tg.size())
	# 1. the path finder: from the control room to each, a route that ends within reach of the equipment
	var codes := {}
	for t in tg:
		var code: String = t[2]
		if codes.has(code):
			continue
		if not index.has(code):
			problems.append("%s/%s: %s is not drawn in the plant" % [t[0], t[1], code])
			continue
		var to: Vector3 = nav.point_for(index.box(code))
		var gap := index.distance(code, to + Vector3.UP * 1.0)
		if gap > REACH:
			problems.append("%s/%s: the nearest walkable point to %s is %.1f m from it" % [t[0], t[1], code, gap])
		var rt: Dictionary = nav.find(start, to)
		if not rt.reached:
			problems.append("%s/%s: no way on foot from the control room to %s (the route ends at %s, %s is at %s)" % [t[0], t[1], code,
				str(rt.points[-1]) if rt.points.size() > 0 else "-", code, str(to)])
		codes[code] = to
	# the ladder is on the routes that need it: the way to its top climbs it
	for l in plant.manifest.ladders:
		var rt: Dictionary = nav.find(start, plant.v3(l.exit))
		if not rt.reached or not nav.steps(rt).any(func(s): return s.get("ladder", "") == l.id and s.dir == "up"):
			problems.append("the path finder's way to the top of %s does not climb it: %s" % [l.id, str(nav.steps(rt))])
	print("  path finder: %d codes, %d searches, %.2f ms a search on average, %.2f ms the longest" % [codes.size(),
		nav.stats.finds, nav.stats.find_us_sum / 1000.0 / maxi(nav.stats.finds, 1), nav.stats.find_us_max / 1000.0])
	if not problems.is_empty():
		world.free()
		return problems
	# 2. the walker on those routes, procedure by procedure from the control room, target after target. It runs (Shift,
	# as a trainee crossing the plant does): 6.7 km at a walk would take the test four minutes of the build's ten; the
	# stairs and the ladder are walked at a walk above
	player.run = true
	var t0 := Time.get_ticks_msec()
	var walked := 0.0
	var proc := ""
	for t in tg:
		if t[0] != proc:
			proc = t[0]
			await _place(tree, player, start)
		var rt: Dictionary = nav.find(player.global_position, codes[t[2]])
		if not rt.reached:
			problems.append("%s/%s: no way on foot from %s to %s" % [t[0], t[1], str(player.global_position), t[2]])
			break
		var steps: Array = nav.steps(rt)
		if steps.is_empty():
			continue
		walked += rt.length
		var pb := await _follow(tree, world, player, steps, "%s/%s to %s" % [t[0], t[1], t[2]], 0.5, 0.5)
		if not pb.is_empty():
			problems.append_array(pb)
			break
		var d := index.distance(t[2], player.global_position + Vector3.UP * 1.0)
		if d > REACH:
			problems.append("%s/%s: the walker ended %.1f m from %s" % [t[0], t[1], d, t[2]])
	# and every stair and ladder by the path finder's own ways: from the control room to the floor in front of its
	# foot, up it to the floor in front of its top, and down again, each way through its link
	await _place(tree, player, start)
	for l in nav.links.values():
		if not problems.is_empty():
			break
		var ends: Array = [l.path[0], l.path[-1]]
		for leg in [[null, ends[0], ""], [ends[0], ends[1], "up"], [ends[1], ends[0], "down"]]:
			var rt: Dictionary = nav.find(player.global_position, leg[1])
			var what := "%s %s %s" % [l.kind, l.id, leg[2] if leg[2] != "" else "(the way to its foot)"]
			if not rt.reached:
				problems.append("%s: no way on foot" % what)
				break
			if leg[2] != "" and not Array(rt.marks).has("%s %s" % [l.kind, l.id]):
				problems.append("%s: the path finder's way does not take it" % what)
				break
			walked += rt.length
			var pb := await _follow(tree, world, player, nav.steps(rt), what, 0.5, 0.5)
			if not pb.is_empty():
				problems.append_array(pb)
				break
	print("  walked %.0f m along the routes to %d targets and up and down %d stairs and ladders in %d ms" % [walked,
		tg.size(), nav.links.size(), Time.get_ticks_msec() - t0])
	world.free()
	return problems
