## HRSG 1's service lift in the app (docs/PLANT3D.md §20.2, §20.6, §20.7): the trainee calls the cab at grade from the
## call station's card, opens the gate, steps in (their `board` sent by app/lift.gd), shuts the gate, sends the cab to
## the roof from the panel's landing buttons and rides it up, the walker carried by the cab's floor all the way; opens
## the gate at the top and steps out (the `alight`). The gates are solid only while shut, the cab's front only away
## from an open landing gate; a gate's open is refused where the cab is not; the panel's buttons are offered only
## within reach. The walking directions take the lift to the roof (quicker than the stairs by the staff's speeds) and
## the stairs to the tower's +10 m landing (quicker than riding to +16.7 m and walking down).
extends RefCounted

const App = preload("res://tests/ui_app.gd")
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
	await _ride(ui)
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
	var front0 := gd(102.52, 48.0, 0.0)
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
	# the panel rides with the cab: within reach up here
	if not ui.near(KKS + "GH010"):
		p.append("the cab's panel did not ride up with the cab")
	# open the gate at the top and step out: the alight
	if not _press(ui, KKS + "AB003", "open", "Open the gate"):
		return
	await _run(ui, 4.0, func(): return e.truth(LIFT + "_open2"))
	await _stand(ui, gd(102.52, 48.0, 30.05))
	await _run(ui, 2.0, func(): return ui.lifts.walker_aboard == -1)
	if not e.riders[0].is_empty():
		p.append("the walker out on the roof landing did not alight: riders %s" % str(e.riders[0]))
	if ui.player.global_position.y < 29.8:
		p.append("the walker fell stepping out: at %.2f m" % ui.player.global_position.y)


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
	if not steps.any(func(s): return s.has("lift") and s["from"] == 0 and s["to"] == 2):
		p.append("the way to the roof has no ride for the autopilot: %s" % str(steps))
	var low: Dictionary = r.find(from, gd(101.4, 48.0, 10.0))
	if not low.reached or " ".join(low.marks).contains("lift "):
		p.append("the way to the tower's +10 m landing takes the lift (or fails): %s" % str(low.marks))


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
