## Walking directions in the app (docs/PLANT3D.md §8 `"go": "walk"`, app/walk_route.gd): a procedure step to walk to
## shows the way on foot from the trainee to its equipment (chevrons on the floor, the walk's length at the arrow);
## walking along it redraws the way from where the trainee is without searching again, leaving it finds a new way
## from there, flying hides it, and a step that doesn't say "walk" or the end of the procedure takes it away. The
## gamepad's X takes the trainee back to the control room, as H does.
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const Player = preload("res://app/player.gd")
const Controls = preload("res://app/controls.gd")


func _wait(tree: SceneTree, seconds: float) -> void:
	for i in int(seconds * 60):
		await tree.physics_frame


func run(tree: SceneTree) -> Array:
	var p: Array = []
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null or ui.route == null:
		main.free()
		return ["the interaction layer or its walking directions did not start"]
	var r = ui.route
	# 0. the chevrons' pipeline queued early by a hidden chevron, never drawn: drawn (alpha 0, the first way) it held a
	# frame for its pipeline (113-121 ms on the Note 9, 1.3-1.5 s after the first walkable frame)
	var shown_early := false
	for i in int((r.WARM_UP_S + 1.0) * 60):
		if r.warmed:
			break
		shown_early = shown_early or r._mi.visible
		await tree.physics_frame
	if not r.warmed or r._mesh.get_surface_count() == 0:
		p.append("the chevrons' pipeline is queued by a hidden chevron after the start")
	if shown_early or r._mi.visible or r.shown():
		p.append("the chevron that queues the pipeline is never drawn")
	for i in 300:
		if r.ready_to_find():
			break
		await tree.physics_frame
	if not r.ready_to_find():
		main.free()
		return ["the navigation map was not ready 5 s after the start: %s" % r.error]
	ui.go_control_room()
	var player = ui.player
	# 1. a step to walk to: the way from the control room to the instrument air compressor
	ui.start_procedure("cold_start", "ia")
	if not ui.walking or not r.active():
		p.append("the step \"ia\" (go: walk) shows no way on foot")
	await _wait(tree, 0.5)
	if not r.shown() or not r.route.get("reached", false):
		p.append("no way on foot drawn to 00QFA10AN001 half a second after the step began (walker %s in mode %d, %d points)" % [
			str(player.global_position), player.mode, r.route.get("points", []).size()])
		main.free()
		return p
	if r.left < 80.0 or r.left > 400.0:
		p.append("the walk from the control room to 00QFA10AN001 is %.0f m (expected 80 to 400)" % r.left)
	if r.chevrons < 20:
		p.append("the way is shown with no chevrons")
	var pts: PackedVector3Array = r.route.points
	if pts[0].distance_to(player.global_position) > 1.5:
		p.append("the way does not start at the trainee: %s, the trainee at %s" % [str(pts[0]), str(player.global_position)])
	var target_gap: float = ui.index.distance("00QFA10AN001", pts[pts.size() - 1] + Vector3.UP)
	if target_gap > ui.REACH:
		p.append("the way ends %.1f m from the compressor, out of reach of its local controls" % target_gap)
	# 2. walking along it: redrawn from the trainee onwards, no new search
	var finds: int = r.stats.finds
	var draws: int = r.stats.draws
	var left0: float = r.left
	var along := 0.0
	var k := 1
	while k < pts.size() - 1 and along < 25.0:
		along += pts[k - 1].distance_to(pts[k])
		k += 1
	player.global_position = pts[k - 1] + Vector3.UP * 0.05
	await _wait(tree, 0.5)
	if r.stats.finds != finds or r.stats.draws != draws:
		p.append("walking along the way searched for a new one or rebuilt the chevrons")
	if absf((left0 - r.left) - along) > 3.0:
		p.append("after %.0f m along the way, %.0f m are left of %.0f" % [along, r.left, left0])
	if r._drawn_from < along - 3.0:
		p.append("the chevrons were not shown from where the trainee is (%.0f m along, drawn from %.0f)" % [along, r._drawn_from])
	# 2b. off the mesh (half way up a stair tower the way doesn't take): no searching from a floor below, the way stays
	var on_stair: Vector3 = main.plant.stair_path("hrsg1_stair")[10]
	var keep: Vector3 = player.global_position
	finds = r.stats.finds
	player.global_position = on_stair + Vector3.UP * 0.05
	await _wait(tree, 1.5)
	if r.stats.finds != finds or not r.shown():
		p.append("off the mesh on a stair the way was searched again (%d searches) or hidden" % (r.stats.finds - finds))
	player.global_position = keep + Vector3.UP * 0.05
	await _wait(tree, 0.5)
	finds = r.stats.finds
	# 2c. a floor 4 m above or below the way is off it (a way along the ground, the trainee on a deck over it)
	var saved: Dictionary = r.route
	r.route = {"points": PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 0, 0)])}
	var below: Array = r._progress(Vector3(5, -4, 0))
	var beside: Array = r._progress(Vector3(5, 0.3, 0))
	r.route = saved
	if below[2] <= r.OFF_ROUTE or beside[2] > 0.5:
		p.append("4 m below the way counts %.1f m off it, 0.3 m above it %.1f m" % [below[2], beside[2]])
	# 3. off the way: a new one from where the trainee is
	var off: Vector3 = NavigationServer3D.map_get_closest_point(r.map, player.global_position + Vector3(0, 0, 12))
	if off.distance_to(player.global_position) < 5.0:
		off = NavigationServer3D.map_get_closest_point(r.map, player.global_position + Vector3(0, 0, -12))
	player.global_position = off + Vector3.UP * 0.05
	await _wait(tree, 1.5)
	if r.stats.finds <= finds or not r.shown():
		p.append("leaving the way by %.0f m found no new one" % off.distance_to(pts[k - 1]))
	elif r.route.points[0].distance_to(player.global_position) > 1.5:
		p.append("the new way does not start at the trainee")
	# 4. flying: no way on foot; landing: back
	player.set_mode(Player.Mode.FLY)
	await _wait(tree, 0.5)
	if r.shown():
		p.append("the way on foot stays on screen in flight")
	player.set_mode(Player.Mode.WALK)
	await _wait(tree, 1.5)
	if not r.shown():
		p.append("the way did not come back after landing")
	print("  walking directions: loaded in %.2f ms, %d searches (longest %.2f ms), %d chevron builds (longest %.2f ms), %d moves" % [
		r.stats.setup_us / 1000.0, r.stats.finds, r.stats.find_us_max / 1000.0, r.stats.draws, r.stats.draw_us_max / 1000.0, r.stats.moves])
	# 5. a step that says "fly": no way on foot
	ui.start_procedure("cold_start", "basin")
	await _wait(tree, 0.5)
	if ui.walking or r.active() or r.shown():
		p.append("a step with go: fly still shows a way on foot")
	# 6. back to a walking step, then the procedure stopped: gone
	ui.start_procedure("cold_start", "cw_a_valve")
	await _wait(tree, 0.5)
	if not r.shown():
		p.append("the step \"cw_a_valve\" (go: walk) shows no way to the valve")
	ui.stop_procedure()
	if r.active() or r.shown():
		p.append("the way on foot stays after the procedure stopped")
	# 7. the gamepad's X: back to the control room, as H
	var xs := InputMap.action_get_events("home").filter(func(e): return e is InputEventJoypadButton and e.button_index == JOY_BUTTON_X)
	if xs.is_empty():
		p.append("the gamepad's X is not bound to home")
	var seen := {}
	for a in Controls.BUTTONS:
		for b in Controls.BUTTONS[a]:
			if seen.has(b):
				p.append("gamepad button %d does both %s and %s" % [b, seen[b], a])
			seen[b] = a
	for a in ["ui_accept", "ui_select", "ui_cancel"]:
		for e in InputMap.action_get_events(a):
			if e is InputEventJoypadButton and e.button_index == JOY_BUTTON_X:
				p.append("the gamepad's X is also Godot's %s" % a)
	player.global_position = off + Vector3.UP * 0.05
	if ui.in_control_room():
		p.append("the test's trainee is still in the control room")
	# through Godot's input, as a gamepad sends it
	var ev := InputEventJoypadButton.new()
	ev.button_index = JOY_BUTTON_X
	ev.pressed = true
	Input.parse_input_event(ev)
	await tree.process_frame
	await tree.process_frame
	var up := ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	if not ui.in_control_room():
		p.append("the gamepad's X did not take the trainee back to the control room")
	main.free()
	return p
