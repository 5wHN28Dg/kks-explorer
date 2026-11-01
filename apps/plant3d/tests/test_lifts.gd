## HRSG 1's service lift in the app (docs/PLANT3D.md §20.2, §20.6, §20.7): the trainee calls the cab at grade from the
## call station's card, opens the gate, steps in (their `board` sent by app/lift.gd), shuts the gate, sends the cab to
## the roof from the panel's landing buttons and rides it up, the walker carried by the cab's floor all the way; opens
## the gate at the top and steps out (the `alight`). The gates are solid only while shut, the cab's front only away
## from an open landing gate; a gate's open is refused where the cab is not; the panel's buttons are offered only
## within reach. The walking directions take the lift to the roof and to the landing at +16.7 m (one ride, not two
## through the landing between), and no way they choose is slower than the stairs' by the staff's speeds. A saved run
## continued in the cab at the roof puts the walker back in it; the autopilot walks down through the gates with a stop at
## +16.7 m, pressing each control once; a gate shutting on the walker in its gateway puts them out on the landing.
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const Autopilot = preload("res://app/autopilot.gd")
const SimClock = preload("res://ui/sim_clock.gd")

const LIFT := "hrsg1_lift"
const KKS := "10SNB10"
const SPEED_STEP := 0.061         # m: the cab's travel in one step (0.6 m/s)

var p: Array = []
var tree: SceneTree


static func gd(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, z, -y)


func run(t: SceneTree) -> Array:
	tree = t
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null:
		main.free()
		return ["the interaction layer did not start"]
	await tree.process_frame
	if ui.lifts == null or ui.lifts.lifts.size() != 1:
		main.free()
		return ["the lift is not drawn: %s" % str(ui.lifts.lifts.size() if ui.lifts != null else null)]
	# nothing done while still (PLANT3D §20.8): paused, the cab standing, no frame draws it again
	for i in 3:
		await tree.physics_frame
	var d0: int = ui.lifts.draws
	for i in 30:
		await tree.physics_frame
	if ui.lifts.draws != d0:
		p.append("the lift's view drew %d times in 30 frames with nothing moving" % (ui.lifts.draws - d0))
	# running, the cab standing: once a step, not every frame
	var s0: int = ui.clock.engine.step_no
	d0 = ui.lifts.draws
	await _run(ui, 1.0)
	if ui.lifts.draws - d0 > ui.clock.engine.step_no - s0 + 1:
		p.append("the lift's view drew %d times in %d steps with the cab standing" % [ui.lifts.draws - d0, ui.clock.engine.step_no - s0])
	await _ride(ui)
	await _walked_down(ui)
	await _gateway(ui)
	_directions(ui)
	_speeds(ui)
	main.free()
	return p


func _stand(ui, at: Vector3) -> void:
	ui.player.global_position = at
	ui.player.velocity = Vector3.ZERO
	ui.player.halt()
	for i in 4:
		await tree.physics_frame
	ui.card.refresh()


func _press(ui, code: String, do: String, label: String) -> bool:
	ui.open_card(code)
	var row: Array = App.op_row(ui.card, code, do)
	if row.is_empty():
		p.append("%s's card has no %s" % [code, do])
		return false
	var b: Button = row[1]
	if b.text != label:
		p.append("%s %s is labelled %s, not %s" % [code, do, b.text, label])
	if b.disabled:
		p.append("%s %s is not offered where the trainee stands: %s" % [code, do, App.texts(ui.card)])
		return false
	b.pressed.emit()
	return true


## Lets the plant run at normal speed for `seconds` of game time (physics frames: the cab and the walker move).
func _run(ui, seconds: float, until := Callable()) -> bool:
	ui.clock.set_speed(SimClock.Speed.NORMAL)
	var n := int(seconds * 60.0)
	for i in n:
		await tree.physics_frame
		if until.is_valid() and until.call():
			ui.clock.set_speed(SimClock.Speed.PAUSED)
			return true
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	return not until.is_valid()


func _ride(ui) -> void:
	var e = ui.clock.engine
	var L: Dictionary = ui.lifts.lifts[0]
	var front0 := gd(102.42, 48.0, 0.0)
	# from the control room the cab's panel buttons are not offered
	ui.go_control_room(false)
	ui.open_card(KKS + "GH010")
	var to_top: Button = App.find_button(ui.card, "To +30.0 m")
	if to_top == null:
		p.append("the cab's panel has no landing buttons: %s" % App.texts(ui.card))
		return
	if not to_top.disabled:
		p.append("the cab's panel is offered from the control room")
	# at the gate at grade: a gate's open at the top is refused (the cab is not there)
	await _stand(ui, front0)
	if (L["gates"][0]["shape"] as CollisionShape3D).disabled:
		p.append("the shut gate at grade is not solid")
	ui.do_op(ui.info.ops_of[KKS + "AB003"].filter(func(o): return o["do"] == "open")[0], null)
	ui.clock.run_steps(1)
	if not e.events.any(func(ev): return ev[1] == "op" and ev[2] == KKS + "AB003" and ev[4] == "refused"):
		p.append("the top gate's open was not refused with the cab at grade")
	# call the cab here, open the gate
	if not _press(ui, KKS + "GH001", "start", "Call the cab here"):
		return
	ui.clock.run_steps(2)
	if not _press(ui, KKS + "AB001", "open", "Open the gate"):
		return
	await _run(ui, 4.0, func(): return e.truth(LIFT + "_open0"))
	await tree.physics_frame
	if not e.truth(LIFT + "_open0"):
		p.append("the gate at grade did not open")
		return
	if not (L["gates"][0]["shape"] as CollisionShape3D).disabled:
		p.append("the open gate at grade is still solid")
	if not (L["front"] as CollisionShape3D).disabled:
		p.append("the cab's front is solid at an open gate")
	# step in: the board is sent from the walker's feet (app/lift.gd), the slot is the rider (free mode)
	var body: Node3D = L["body"]
	await _stand(ui, body.global_position + Vector3.UP * 0.05)
	await _run(ui, 2.0, func(): return ui.lifts.walker_aboard == 0)
	if not e.riders[0].has(0):
		p.append("the walker in the cab did not board: riders %s, events %s" % [str(e.riders[0]), str(e.events.slice(-5))])
		return
	if e.v(LIFT + "_load_kg") != 75.0:
		p.append("the load cell does not read one person: %s" % e.v(LIFT + "_load_kg"))
	# shut the gate (from inside: within reach) and send the cab to the roof
	if not _press(ui, KKS + "AB001", "close", "Close the gate"):
		return
	await _run(ui, 3.0, func(): return e.truth(LIFT + "_shut0"))
	await tree.physics_frame
	if (L["front"] as CollisionShape3D).disabled or (L["gates"][0]["shape"] as CollisionShape3D).disabled:
		p.append("the cab's front or the gate at grade is not solid once the gate is shut")
	ui.open_card(KKS + "GH010")
	to_top = App.find_button(ui.card, "To +30.0 m")
	if to_top == null or to_top.disabled:
		p.append("the cab's panel is not offered inside the cab")
		return
	to_top.pressed.emit()
	# the ride: the walker stays on the cab's floor all the way up
	var worst := [0.0]              # (a lambda captures by value: the worst kept in an array)
	# paused mid-ride (between landings): nothing drawn again while the clock stands; the walker on the floor from the
	# start
	await _run(ui, 15.0, func():
		worst[0] = maxf(worst[0], absf(ui.player.global_position.y - body.global_position.y))
		return e.v(LIFT + "_z") > 3.0)
	if e.v(LIFT + "_z") <= 0.5 or e.truth(LIFT + "_at1") or e.truth(LIFT + "_at2"):
		p.append("the cab is not between landings for the paused check: z %.2f" % e.v(LIFT + "_z"))
	for i in 3:
		await tree.physics_frame
	var dr: int = ui.lifts.draws
	for i in 30:
		await tree.physics_frame
	if ui.lifts.draws != dr:
		p.append("paused mid-ride, the lift's view drew %d times in 30 frames" % (ui.lifts.draws - dr))
	var rode := await _run(ui, 70.0, func():
		worst[0] = maxf(worst[0], absf(ui.player.global_position.y - body.global_position.y))
		return e.truth(LIFT + "_at2"))
	if not rode:
		p.append("the cab did not reach the roof: z %.2f" % e.v(LIFT + "_z"))
		return
	if worst[0] > 0.25:
		p.append("the walker was %.2f m off the cab's floor on the ride" % worst[0])
	if ui.player.global_position.y < 29.8:
		p.append("the walker did not ride up: at %.2f m" % ui.player.global_position.y)
	await tree.physics_frame
	if absf(ui.lifts.cab_height(0) - 30.0) > SPEED_STEP:     # (drawn between the last two steps: within one)
		p.append("the cab is drawn at %.2f m at the roof" % ui.lifts.cab_height(0))
	# a run saved in the cab at the roof and continued (the app killed mid-ride): the walker is put back in the cab up
	# here, not on the roof of the cab the fresh run had at grade, and stays aboard
	var saved: Dictionary = ui.autosave.payload()
	ui.autosave.restore(saved)
	# the cab is where the run has it before the walker is put down (not where the fresh run drew it, at grade)
	if absf((L["body"] as Node3D).global_position.y - ui.clock.engine.v(LIFT + "_z")) > 0.01:
		p.append("continued, the walker is put down before the cab is moved to the run's height: cab at %.2f m, the run's %.2f m" % [(L["body"] as Node3D).global_position.y, ui.clock.engine.v(LIFT + "_z")])
	for i in 30:
		await tree.physics_frame
	if ui.player.global_position.y < 29.8 or not ui.lifts.feet_inside(L, ui.player.global_position) or not e.riders[0].has(0):
		e = ui.clock.engine
		p.append("continued in the cab at the roof, the walker is at %s (cab at %.2f m, riders %s)" % [str(ui.player.global_position), ui.lifts.cab_height(0), str(ui.clock.engine.riders[0])])
	e = ui.clock.engine
	body = L["body"]
	# the panel rides with the cab: within reach up here
	if not ui.near(KKS + "GH010"):
		p.append("the cab's panel did not ride up with the cab")
	# open the gate at the top and step out: the alight
	if not _press(ui, KKS + "AB003", "open", "Open the gate"):
		return
	await _run(ui, 4.0, func(): return e.truth(LIFT + "_open2"))
	await _stand(ui, gd(102.42, 48.0, 30.05))
	await _run(ui, 2.0, func(): return ui.lifts.walker_aboard == -1)
	if not e.riders[0].is_empty():
		p.append("the walker out on the roof landing did not alight: riders %s" % str(e.riders[0]))
	if ui.player.global_position.y < 29.8:
		p.append("the walker fell stepping out: at %.2f m" % ui.player.global_position.y)


## Down again with the autopilot, as a trainee walks it: through the open gates into the cab and out (no teleporting),
## a stop at the tower's landing at +16.7 m (off, the gate shut behind, on again), then down to grade, the walker
## carried down by the cab's floor; every control pressed once (the cab remembers its calls and sends).
func _walked_down(ui) -> void:
	var e = ui.clock.engine
	var n0: int = e.inputs.size()
	var auto := Autopilot.new()
	auto.ui = ui
	ui.main.add_child(auto)
	var stuck := [0]
	auto.stuck.connect(func(_i, _at): stuck[0] += 1)
	auto.start(ui.player, [{"lift": KKS, "from": 2, "dest": 1}, {"lift": KKS, "from": 1, "dest": 0}])
	var lowest := [INF]
	var done := await _run(ui, 240.0, func():
		lowest[0] = minf(lowest[0], ui.player.global_position.y - ui.lifts.cab_height(0))
		return not auto.running)
	auto.stop()
	auto.queue_free()
	if not done or stuck[0] > 0:
		p.append("the walk down by the lift did not finish (stuck %d, at %s, step %d phase %d)" % [stuck[0], str(ui.player.global_position), auto.i, auto._phase])
		return
	if ui.player.global_position.y > 0.3 or not e.riders[0].is_empty():
		p.append("the walk down did not end off the cab at grade: at %s, riders %s" % [str(ui.player.global_position), str(e.riders[0])])
	var stops: int = e.events.slice(n0).filter(func(ev): return ev[1] == "alight" and ev[4] == "done").size()
	if stops != 2:
		p.append("the walk down got off %d times, not twice (at +16.7 m and at grade)" % stops)
	var presses := {}
	for ins in e.inputs.slice(n0):
		if ins[1] == "op":
			var key := "%s %s %s" % [ins[2], ins[3], str(ins[4])]
			presses[key] = presses.get(key, 0) + 1
	for key in presses:
		if presses[key] > 1:
			p.append("the autopilot pressed %s %d times: %s" % [key, presses[key], str(e.events.slice(n0).filter(func(ev): return ev[1] == "op" and String(ev[2]).begins_with(KKS)))])


## A gate shutting on the walker in its gateway puts them on the side their riding says: not aboard, out on the landing.
func _gateway(ui) -> void:
	var e = ui.clock.engine
	var L: Dictionary = ui.lifts.lifts[0]
	if not e.truth(LIFT + "_at0"):
		p.append("the cab is not at grade for the gateway check")
		return
	ui.do_op(ui.info.ops_of[KKS + "AB001"].filter(func(o): return o["do"] == "open")[0], null)
	await _run(ui, 4.0, func(): return e.truth(LIFT + "_open0"))
	var g: Node3D = L["gates"][0]["node"]
	ui.lifts.set_physics_process(false)          # (no board from standing there: they are not aboard)
	await _stand(ui, g.global_transform * Vector3(0.05, 0.05, 0.0))
	ui.do_op(ui.info.ops_of[KKS + "AB001"].filter(func(o): return o["do"] == "close")[0], null)
	ui.lifts.set_physics_process(true)
	await _run(ui, 4.0, func(): return e.truth(LIFT + "_shut0"))
	for i in 3:
		await tree.physics_frame
	var l: Vector3 = g.global_transform.affine_inverse() * ui.player.global_position
	if l.x > -0.3:
		p.append("the gate shut on the walker in its gateway, who was left at %.2f m from its plane" % l.x)


func _directions(ui) -> void:
	var r = ui.route
	if not r.ready_to_find():
		p.append("the navigation map is not ready")
		return
	var from := gd(93.5, 44.5, 0.0)
	var up: Dictionary = r.find(from, gd(101.4, 52.5, 30.0))
	if not up.reached or not " ".join(up.marks).contains("lift " + KKS + " 0 2"):
		p.append("the way to the roof does not take the lift: %s" % str(up.marks))
	var steps: Array = r.steps(up)
	if not steps.any(func(s): return s.has("lift") and s["from"] == 0 and s["dest"] == 2):
		p.append("the way to the roof has no ride for the autopilot: %s" % str(steps))
	var mid: Dictionary = r.find(from, gd(102.4, 48.0, 50.0 / 3.0))
	if not mid.reached or not " ".join(mid.marks).contains("lift " + KKS + " 0 1"):
		p.append("the way to the tower's landing at +16.7 m does not take the lift there: %s" % str(mid.marks))
	# no chevrons up the ride's height (the route's mesh: none above the grade's front and under the roof's)
	r.route = up
	r._build()
	var v: PackedVector3Array = r._mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] if r._mesh.get_surface_count() > 0 else PackedVector3Array()
	var front := gd(102.42, 48.0, 0.0)
	var in_shaft := 0
	for q in v:
		if Vector2(q.x - front.x, q.z - front.z).length() < 0.4 and q.y > 2.0 and q.y < 28.0:
			in_shaft += 1
	if in_shaft > 0:
		p.append("the directions draw %d chevron vertices up the lift's height" % in_shaft)
	r.route = {}
	# whichever way it takes, it is the quicker by the staff's speeds: never slower than the stairs' way
	for to in [gd(101.4, 52.5, 30.0), gd(102.4, 48.0, 50.0 / 3.0), gd(110.0, 61.0, 32.0)]:
		var f: Dictionary = r.find(from, to)
		var st: Dictionary = r._find(from, to, 1)
		if st.reached and r.time_of(f) > r.time_of(st) + 1e-6:
			p.append("the way to %s takes %.0f s by the staff's speeds, the stairs' %.0f s" % [str(to), r.time_of(f), r.time_of(st)])


## The walking directions time a ride as the staff do: their speeds are staff.json's (walk_route.gd keeps them).
func _speeds(ui) -> void:
	var f := FileAccess.get_file_as_string("res://built/content/staff.json")
	var d = JSON.parse_string(f)
	if typeof(d) != TYPE_DICTIONARY:
		p.append("no staff.json in the built content")
		return
	for k in d["speeds"]:
		if absf(float(ui.route.speeds.get(k, -1.0)) - float(d["speeds"][k])) > 1e-9:
			p.append("the directions' %s speed %s is not staff.json's %s" % [k, str(ui.route.speeds.get(k)), str(d["speeds"][k])])
