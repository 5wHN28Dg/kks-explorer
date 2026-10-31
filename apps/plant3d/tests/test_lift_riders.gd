## The staff on HRSG 1's lift in the app (docs/PLANT3D.md §20.7, milestone LIFTS L3): the first train's day shift run
## until an NPC rides the cab while it travels; they are drawn in the cab (on its floor, within its walls, at their
## spot in boarding order, facing the gate), kept there by the keeping apart (not moved out of the cab), on the map at
## the lift; and once they step out at the landing, drawn walking from the cab to the landing's place within a couple
## of seconds, never further than a step's walk at a time.
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const SimClock = preload("res://ui/sim_clock.gd")

const LIMIT := 36000            # steps of the shift (an hour of model time) for a ride to come
const DT := 1.0 / 60.0


func run(tree: SceneTree) -> Array:
	var p: Array = []
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
	var who := ""
	var n := 0
	while n < LIMIT:
		ui.clock.run_steps(1)
		n += 1
		if e.riders[0].size() > 0 and typeof(e.riders[0][0]) == TYPE_STRING and e.v("hrsg1_lift_moving") >= 0.5:
			who = e.riders[0][0]
			break
	if who == "":
		main.free()
		return ["nobody rode the lift in the first %d steps of the day shift" % LIMIT]
	var pi: int = e._sm.person_ix[who]
	# a few frames: the cab and the people drawn where the engine says
	for i in 30:
		await tree.physics_frame
		pv.drive(DT)
	var k := pv.drawn.find(pi)
	if k == -1:
		p.append("%s in the cab is not drawn" % who)
	else:
		var at: Vector3 = pv.avatars.people[k].at
		if not ui.lifts.feet_inside(L, at + Vector3.UP * 0.05):
			p.append("%s is drawn at %s, not in the cab (at %.2f m)" % [who, str(at), ui.lifts.cab_height(0)])
		var spot: Vector3 = ui.lifts.rider_spot(0, 0)
		if at.distance_to(spot) > 0.3:
			p.append("the first rider is drawn %.2f m from the first spot" % at.distance_to(spot))
		var yaw: float = pv.avatars.people[k].yaw
		if absf(angle_difference(yaw, ui.lifts.gate_yaw(0))) > 0.5:
			p.append("%s in the cab does not face the gate (%.2f, the gate %.2f)" % [who, yaw, ui.lifts.gate_yaw(0)])
	pv.update()
	if pv.shown < 1:
		p.append("nobody on the map")
	# off at a landing: drawn walking out to the landing's place, no frame's move longer than a brisk walk's
	ui.clock.set_speed(SimClock.Speed.NORMAL)
	var was := Vector3.INF
	var worst := 0.0
	var after := -1
	for i in 12000:
		await tree.process_frame
		if after == -1 and not e.riders[0].has(who):
			after = i
		if after != -1 and i > after + 150:
			break
		k = pv.drawn.find(pi)
		if k == -1:
			was = Vector3.INF
			continue
		var at2: Vector3 = pv.avatars.people[k].at
		if was != Vector3.INF and after != -1:
			worst = maxf(worst, at2.distance_to(was))
		was = at2
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	if after == -1:
		p.append("%s never got off" % who)
	elif worst > 0.1:
		p.append("%s jumped %.2f m in a frame stepping out of the cab" % [who, worst])
	main.free()
	return p
