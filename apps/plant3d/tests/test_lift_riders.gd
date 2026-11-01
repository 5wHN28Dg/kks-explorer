## The staff on HRSG 1's lift in the app (docs/PLANT3D.md §20.7, §20.12, milestone LIFTS L3): the first train's day
## shift run until an NPC waits for the cab at grade; from there frame by frame at normal speed: they walk from the
## landing into the cab without a jump (within two seconds at their spot, on its floor, facing the gate), they are on
## the map at the lift while aboard, they stay in the cab while it travels; and from the step they get off (their
## ride's "off" event) they walk out without a jump, their step-out done within three seconds.
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const SimClock = preload("res://ui/sim_clock.gd")

const LIMIT := 36000            # steps of the shift (an hour of model time) for a ride to come
const JUMP := 0.1               # m in one frame at most (6 m/s at 60 frames a second: no teleport)

var p: Array = []


func _drawn(pv, pi: int):
	for k in pv.avatars.people.size():
		if k < pv.drawn.size() and pv.drawn[k] == pi:
			return pv.avatars.people[k]
	return null


func run(tree: SceneTree) -> Array:
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null or not ui.model.scenarios.has("shift_cold") or ui.people == null:
		main.free()
		return ["the app or its scenario with the crews (shift_cold) did not start"]
	for i in 4:
		await tree.physics_frame
	ui.start_shift("shift_cold")
	await tree.process_frame
	ui.take_role("")
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	var pv = ui.people
	var e = ui.clock.engine
	var L: Dictionary = ui.lifts.lifts[0]
	# paused, to the step where someone begins to wait for the cab at grade; then frame by frame at normal speed
	var who := ""
	var n := 0
	while n < LIMIT and who == "":
		var n0: int = e.events.size()
		ui.clock.run_steps(1)
		n += 1
		for ev in e.events.slice(n0):
			if ev[1] == "ride" and ev[6] == "wait" and ev[4] == "p_lift0":
				who = ev[2]
	if who == "":
		main.free()
		return ["nobody waited for the lift at grade in the first %d steps of the day shift" % LIMIT]
	var pi: int = e._sm.person_ix[who]
	ui.clock.set_speed(SimClock.Speed.NORMAL)
	var was := Vector3.INF
	var worst_in := 0.0
	var boarded := -1.0
	var t := 0.0
	var in_cab_ok := false
	var faced := false
	var on_map := false
	var off_t := -1.0
	var worst_out := 0.0
	var out_done := false
	var travelled := false
	var left_cab := false
	var checked := false
	for i in 60 * 600:
		await tree.process_frame
		t += 1.0 / 60.0
		var d = _drawn(pv, pi)
		var at: Vector3 = d.at if d != null else Vector3.INF
		var aboard: bool = e.riders[0].has(who)
		if at != Vector3.INF and was != Vector3.INF:
			if off_t < 0.0:
				worst_in = maxf(worst_in, at.distance_to(was))
			else:
				worst_out = maxf(worst_out, at.distance_to(was))
		was = at
		if aboard and boarded < 0.0:
			boarded = t
		if aboard and boarded >= 0.0 and t - boarded > 2.0 and not checked and d != null:
			checked = true
			var spot: Vector3 = ui.lifts.rider_spot(0, e.riders[0].find(who))
			in_cab_ok = ui.lifts.feet_inside(L, at + Vector3.UP * 0.05) and at.distance_to(spot) < 0.15
			faced = absf(angle_difference(float(d.yaw), ui.lifts.gate_yaw(0))) < 0.3
			pv.update()
			var mm: MultiMesh = pv.dots.multimesh
			for k in mm.instance_count:
				var o: Vector3 = mm.get_instance_transform(k).origin
				if Vector2(o.x - spot.x, o.z - spot.z).length() < 0.3:
					on_map = true
		if aboard and e.v("hrsg1_lift_moving") >= 0.5 and at != Vector3.INF:
			travelled = true
			if not ui.lifts.feet_inside(L, at + Vector3.UP * 0.05):
				left_cab = true
		if off_t < 0.0 and boarded >= 0.0:
			for ev in e.events.slice(maxi(0, e.events.size() - 40)):
				if ev[1] == "ride" and ev[2] == who and ev[6] == "off":
					off_t = t
		if off_t >= 0.0 and t - off_t > 3.0:
			out_done = pv._roff[pi] == Vector3.ZERO and pv._rode[pi] == 0
			break
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	if boarded < 0.0:
		p.append("%s never boarded" % who)
	else:
		if worst_in > JUMP:
			p.append("%s jumped %.2f m in a frame stepping into the cab or riding" % [who, worst_in])
		if not in_cab_ok:
			p.append("%s is not at their spot in the cab two seconds after boarding" % who)
		if not faced:
			p.append("%s in the cab does not face the gate" % who)
		if not on_map:
			p.append("%s aboard is not on the map at the lift" % who)
		if not travelled or left_cab:
			p.append("%s was not drawn in the travelling cab (travelled %s, out of it %s)" % [who, str(travelled), str(left_cab)])
	if off_t < 0.0:
		p.append("%s never got off" % who)
	else:
		if worst_out > JUMP:
			p.append("%s jumped %.2f m in a frame stepping out of the cab" % [who, worst_out])
		if not out_done:
			p.append("%s is still stepping out three seconds after getting off" % who)
	main.free()
	return p
