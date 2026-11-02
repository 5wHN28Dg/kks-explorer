## The staff's bus in the app (docs/PLANT3D.md §21.7, milestone S4c; app/vehicles.gd, builder/fleet.gd):
## - the build drew the camp's first parked bus as the staff's vehicle (a piece of its own, two draw calls), with a
##   road for each of its drive ways on the asphalt, and at the shift's start (05:00) it stands parked at the depot;
## - on its run it moves along its road on the right of it, smoothly between two steps, a square over it on the map;
## - a trainee who plays crew A's CW field operator goes to the camp's stop from the Crew panel and gets on the bus
##   ("Get on the bus"): the walker rides in it at a seat, off the floor, and is put down at the control building's
##   stop when the engine puts them off; and once its run is over the bus is parked at the depot again.
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const SimClock = preload("res://ui/sim_clock.gd")
const Vehicles = preload("res://app/vehicles.gd")
const Fleet = preload("res://builder/fleet.gd")


func run(tree: SceneTree) -> Array:
	var p: Array = []
	p += _fleet_rules()
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null or not ui.model.scenarios.has("shift_cold"):
		main.free()
		return p + ["the app or its scenario with the crews (shift_cold) did not start"]
	var mv: Array = main.plant.manifest.get("vehicles", [])
	if mv.size() != 1 or mv[0]["id"] != "bus_1" or mv[0]["structure"] != "camp_bus_1":
		main.free()
		return p + ["the built plant's vehicles are not the camp's first bus as bus_1: %s" % str(mv).left(300)]
	for k in ["bus_depot|camp_stop", "camp_stop|gate_stop", "gate_stop|cr_stop"]:
		if not mv[0]["roads"].has(k) or mv[0]["roads"][k].size() < 2:
			p.append("no road for the drive way %s" % k)
	_on_asphalt(main, mv[0], p)
	ui.start_shift("shift_cold")
	await tree.process_frame
	var vv = ui.vehicles
	if vv == null or vv.vehicles.size() != 1:
		main.free()
		return p + ["the app draws no staff vehicle"]
	var V: Dictionary = vv.vehicles[0]
	var body: Node3D = V["body"]
	if not body is AnimatableBody3D:
		p.append("the bus is not a body that moves")
	var surfaces := 0
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		surfaces += (mi as MeshInstance3D).mesh.get_surface_count()
	if surfaces == 0 or surfaces > 2:
		p.append("the bus draws with %d draw calls (at most 2, PLANT3D §21.10)" % surfaces)
	var sq: MeshInstance3D = V["square"]
	if sq.layers != 1 << (Vehicles.MAP_LAYER - 1):
		p.append("the bus's square is not on the map's layer")
	if not (V["xf"] as Transform3D).is_equal_approx(V["parked"]):
		p.append("the bus is not parked at the depot at 05:00: %s, drawn %s, parked %s" % [str(ui.clock.engine.st_veh[V["vi"]]).left(200),
				str((V["xf"] as Transform3D).origin), str((V["parked"] as Transform3D).origin)])
	var e = ui.clock.engine
	# the trainee: crew A's CW field operator, coming on at 06:00, rides the 05:40 bus in
	var b := App.find_button(ui.crew, "Play Field CW, crew A…")
	if b == null:
		var msg := "the shift's start offers no crew A CW field operator: %s" % App.texts(ui.crew).left(300)
		main.free()
		return p + [msg]
	b.pressed.emit()
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	var me: int = e.trainee()
	var vi: int = V["vi"]
	var moved_seen := false
	var aboard_at := -1
	var lane_off := 0
	for i in 1200:
		if e.sp_aboard[me] != -1:
			aboard_at = e.step_no
			break
		_play(ui, e, me)
		ui.clock.run_steps(5)
		vv._physics_process(0.0)
		if not e.st_veh[vi]["leg"].is_empty():
			var a: Vector3 = vv.drawn_at(vi)
			ui.clock.acc = ui.clock.STEP * 0.5        # half a step on: drawn between the two
			vv._physics_process(0.0)
			var h: Vector3 = vv.drawn_at(vi)
			ui.clock.acc = 0.0
			if h.distance_to(a) > 1e-3:
				moved_seen = true
			var leg: Array = e.st_veh[vi]["leg"]
			if leg[0] != V["home"] and leg[1] != V["home"]:
				var d := _off_road(V, e, leg, h)
				if absf(d - Vehicles.LANE) > 0.35:
					lane_off += 1
		if i % 8 == 0:
			await tree.process_frame       # (the panels' old rows are freed at a frame's end)
	if not moved_seen:
		p.append("the bus was never drawn moving between two steps on its run")
	if lane_off > 0:
		p.append("the bus was drawn off its lane %d times (not %.1f m right of its road's middle)" % [lane_off, Vehicles.LANE])
	if aboard_at == -1:
		var cur = e.sp_cur[me]
		var msg := "the trainee never got on the bus (now %s, the task %s)" % [ui.clock_text(), str(cur["task"]) if cur else "none"]
		main.free()
		return p + [msg]
	vv._physics_process(0.0)
	if vv.walker_aboard != vi or ui.player.is_physics_processing() or ui.player.collision_layer != 0:
		p.append("aboard, the walker is not carried in the bus (aboard %d, physics %s)" % [vv.walker_aboard, ui.player.is_physics_processing()])
	if ui.player.global_position.distance_to(vv.drawn_at(vi)) > 6.5:
		p.append("aboard, the walker is %.1f m from the bus" % ui.player.global_position.distance_to(vv.drawn_at(vi)))
	var off := false
	for i in 600:
		ui.clock.run_steps(5)
		vv._physics_process(0.0)
		ui._place_tick()
		if e.sp_aboard[me] == -1:
			off = true
			break
	if not off:
		p.append("the trainee was never put off the bus")
	else:
		vv._physics_process(0.0)
		var at: int = e.sp_pos[me]
		if at == -1 or e._sm.places[at]["id"] != "cr_stop":
			p.append("the trainee got off at %s, not the control building's stop" % (e._sm.places[at]["id"] if at != -1 else "nowhere"))
		if vv.walker_aboard != -1 or not ui.player.is_physics_processing() or ui.player.collision_layer == 0:
			p.append("off the bus, the walker is not walking again")
		if at != -1 and ui.player.global_position.distance_to(ui.people._at[at]) > 2.0:
			p.append("off the bus, the walker is %.1f m from the stop" % ui.player.global_position.distance_to(ui.people._at[at]))
	# its run over, the bus parked at the depot again
	var home := false
	for i in 400:
		ui.clock.run_steps(10)
		if e.st_veh[vi]["at"] == V["home"] and e.st_veh[vi]["leg"].is_empty():
			home = true
			break
	vv._physics_process(0.0)
	if not home or not (V["xf"] as Transform3D).is_equal_approx(V["parked"]):
		p.append("after its run the bus is not parked at the depot (home %s, %s, now %s)" % [str(home), str(e.st_veh[vi]).left(200), ui.clock_text()])
	main.free()
	return p


## Plays the trainee's step from the Crew panel: to a place, to the stop, onto the bus; a choice.
static func _play(ui, e, me: int) -> void:
	var cur = e.sp_cur[me]
	if cur == null:
		return
	var s: Dictionary = e._sm.tasks[cur["task"]]["steps"][cur["step"]]
	if s.has("ride") or s.has("go") or s.has("meet"):
		ui.crew._sig = ""
		ui.crew.refresh()
		for t in ["Get on the bus", "Take me to the stop", "Take me there"]:
			var b := App.find_button(ui.crew, t)
			if b != null:
				b.pressed.emit()
				ui._place_tick()
				return
	elif s.has("choose"):
		e.pick(0)


## How far h is from the middle line of the road the leg drives (in plan).
static func _off_road(V: Dictionary, e, leg: Array, h: Vector3) -> float:
	var sm = e._sm
	var k: String = sm.places[leg[0]]["id"] + "|" + sm.places[leg[1]]["id"]
	if not V["roads"].has(k):
		k = sm.places[leg[1]]["id"] + "|" + sm.places[leg[0]]["id"]
	var line: PackedVector3Array = V["roads"].get(k, PackedVector3Array())
	var best := INF
	for i in range(1, line.size()):
		var q := Geometry3D.get_closest_point_to_segment(Vector3(h.x, 0, h.z), Vector3(line[i - 1].x, 0, line[i - 1].z),
				Vector3(line[i].x, 0, line[i].z))
		best = minf(best, q.distance_to(Vector3(h.x, 0, h.z)))
	return best


## Every point of the roads (and the middle of each stretch) is on the asphalt.
static func _on_asphalt(main, mv: Dictionary, p: Array) -> void:
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	for k in mv["roads"]:
		var line: Array = mv["roads"][k]
		for i in line.size():
			var pts: Array = [line[i]]
			if i > 0:
				pts.append([(line[i][0] + line[i - 1][0]) * 0.5, (line[i][1] + line[i - 1][1]) * 0.5])
			for q in pts:
				var from := Vector3(float(q[0]), 0.5, -float(q[1]))     # (under the parked bus's roof)
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 40.0))
				if hit.is_empty() or absf(hit.position.y) > 0.6:
					p.append("the road %s leaves the ground at %s" % [k, str(q)])
					return


## builder/fleet.gd on a small site: a vehicle takes the parked one of its kind nearest its home (the first on a tie),
## and its road keeps to the asphalt's middle, from the parked place.
static func _fleet_rules() -> Array:
	var p: Array = []
	var staff := {"places": [{"id": "depot", "at": [0, 0, 0]}, {"id": "stop", "at": [40, 24, 0]}],
			"ways": [["depot", "stop", 60, "drive"]],
			"vehicles": [{"id": "bus_a", "kind": "bus", "home": "depot"}, {"id": "bus_b", "kind": "bus", "home": "depot"}]}
	var st: Array = [
		{"s": {"id": "car", "part": "vehicle", "at": [1, 0, 0], "params": {"kind": "suv"}}, "area": "x"},
		{"s": {"id": "far", "part": "vehicle", "at": [9, 0, 0], "params": {"kind": "bus"}}, "area": "x"},
		{"s": {"id": "near1", "part": "vehicle", "at": [0, 3, 0], "params": {"kind": "bus"}}, "area": "x"},
		{"s": {"id": "near2", "part": "vehicle", "at": [0, -3, 0], "params": {"kind": "bus"}}, "area": "x"}]
	var claimed: Dictionary = Fleet.claim(staff, st)
	if claimed != {"near1": "bus_a", "near2": "bus_b"}:
		p.append("fleet: the buses took %s (each the nearest bus, the first on a tie)" % str(claimed))
	# an L of asphalt: 8 m wide east from the depot along y 0, then north along x 40 to y 30
	var surfaces: Array = [{"kind": "road", "surface": "asphalt", "outline": PackedVector2Array([Vector2(-6, -4), Vector2(44, -4),
			Vector2(44, 4), Vector2(-6, 4)])}, {"kind": "road", "surface": "asphalt", "outline": PackedVector2Array([Vector2(36, -4),
			Vector2(44, -4), Vector2(44, 30), Vector2(36, 30)])}, {"kind": "road", "surface": "pavers",
			"outline": PackedVector2Array([Vector2(0, 4), Vector2(36, 4), Vector2(36, 30), Vector2(0, 30)])}]
	var m: Array = Fleet.manifest(staff, st, claimed, surfaces)
	if m.size() != 2 or m[0]["structure"] != "near1":
		return p + ["fleet: the manifest's vehicles %s" % str(m).left(200)]
	var line: Array = m[0]["roads"]["depot|stop"]
	if line[0] != [0.0, 3.0]:
		p.append("fleet: the road from home begins at %s, not where the bus is parked" % str(line[0]))
	for i in range(1, line.size()):
		for t in [0.25, 0.5, 0.75, 1.0]:
			var q := Vector2(line[i - 1][0], line[i - 1][1]).lerp(Vector2(line[i][0], line[i][1]), t)
			var on := Rect2(-6, -4, 50, 8).has_point(q) or Rect2(36, -4, 8, 34).has_point(q)
			if not on:
				p.append("fleet: the road leaves the asphalt at %s (over the pavers: a corner cut)" % str(q))
				return p
	# along the road's middle: every point but the parked one on the east road's middle line (y 0) or the north one's (x 40)
	for i in range(1, line.size()):
		if absf(float(line[i][1])) > 0.6 and absf(float(line[i][0]) - 40.0) > 0.6:
			p.append("fleet: the road's point %s is off the road's middle" % str(line[i]))
	var end := Vector2(line[-1][0], line[-1][1])
	if end.distance_to(Vector2(40, 24)) > 1.5:
		p.append("fleet: the road ends at %s, not on the road by the stop" % str(end))
	return p
