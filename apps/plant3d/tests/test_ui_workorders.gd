## Work orders in the app (docs/plant3d/REALISM.md §7.1, §2.20; milestone WM1), in the aged plant in free mode:
## - a finding matched to its work by the code and the kind found (the first work written for it without an open
##   order);
## - the form's actions only those the person played may make (the engine's authority), named by the roles that may;
## - the card's "Work orders" at closed cooling water pump A's motor (works and past orders) and none at a code with
##   neither; its view lists the content's history and reports a finding: the bearings' vibration notified (WO-0001);
## - the list: the open order with the backlog's planned hours; its form plans it (urgent) and schedules it (today),
##   then cancels it: the run's history in the list and in the code's view;
## - transmitter 2's calibration: its permit taken to accepted (the order in progress by itself), the completion's
##   pickers and comment refused while the permit is not done (in words), then completed after the done with the
##   chosen codes; the debrief's line compares them with the job's own.
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const SimClock = preload("res://ui/sim_clock.gd")
const Wo = preload("res://ui/wo_panel.gd")

const MOTOR := "00PGC10AP001"         # closed cooling water pump A's motor
const NOTHING := "30MAG10AC001"       # the condenser: no work and no past order
const CAL := "wo_cond_p2_cal"         # condenser pressure transmitter 2's calibration


func run(tree: SceneTree) -> Array:
	var p: Array = _matching()
	p += _who_may()
	p += await _panel(tree)
	return p


## An engine's works and orders for work_for (by code and kind).
class Eng extends RefCounted:
	var m := Mod.new()
	var wo := {}
	class Mod extends RefCounted:
		var works: Array = []
		var work_ix := {}


func _matching() -> Array:
	var p: Array = []
	var e := Eng.new()
	e.m.works = [{"id": "a", "kks": "X", "finds": ["noise"]}, {"id": "b", "kks": "X", "finds": ["vibration", "noise"]},
		{"id": "c", "kks": "Y", "finds": ["vibration"]}]
	for i in e.m.works.size():
		e.m.work_ix[e.m.works[i]["id"]] = i
	for c in [["X", "vibration", {}, "b"], ["X", "noise", {}, "a"], ["X", "noise", {"a": 1}, "b"],
			["X", "noise", {"a": 3, "b": 4}, "a"], ["X", "noise", {"a": 6}, "a"], ["Y", "noise", {}, ""]]:
		e.wo = c[2]
		var w: Dictionary = Wo.work_for(e, c[0], c[1])
		if w.get("id", "") != c[3]:
			p.append("a finding of %s on %s with %s went to %s, wanted %s" % [c[1], c[0], str(c[2]), w.get("id", ""), c[3]])
	return p


## The form offers only what the person played may do (the engine's authority): a fake staff with a supervisor
## (plan_work, close_work) and an I&C technician (accept, instrument); free mode (nobody played) may do everything.
class Staffed extends RefCounted:
	var _sm := Sm.new()
	class Sm extends RefCounted:
		var person_ix := {"sup": 0, "ic": 1}
		var people := [{"id": "sup", "role": "maint_sup"}, {"id": "ic", "role": "ic_tech"}]
		var auth := {"maint_sup": {"plan_work": true, "close_work": true}, "ic_tech": {"accept": true}}
		var roles := {"maint_sup": {"title": "Maintenance supervisor", "discipline": "mechanical"},
			"ic_tech": {"title": "I&C technician", "discipline": "instrument"}}


func _who_may() -> Array:
	var p: Array = []
	var e := Staffed.new()
	var cal := {"id": "cal", "discipline": "instrument"}
	var pump := {"id": "pump", "discipline": "mechanical"}
	for c in [["sup", "plan", cal, true], ["sup", "close", cal, true], ["sup", "complete", cal, false],
			["ic", "plan", cal, false], ["ic", "cancel", cal, false], ["ic", "complete", cal, true],
			["ic", "complete", pump, false], ["ic", "notify", pump, true], [null, "plan", cal, true]]:
		if Wo.may(e, c[0], c[1], c[2]) != c[3]:
			p.append("%s may %s %s: %s, wanted %s" % [c[0], c[1], c[2]["id"], not c[3], c[3]])
	for c in [["plan", cal, "maintenance supervisor"], ["complete", cal, "i&c technician"],
			["complete", pump, "nobody in this plant"], ["notify", pump, "anyone"]]:
		if Wo.role_words(e, c[0], c[1]) != c[2]:
			p.append("who may %s %s: %s, wanted %s" % [c[0], c[1]["id"], Wo.role_words(e, c[0], c[1]), c[2]])
	return p


static func _press(n: Node, name: String) -> bool:
	var b = n.find_child(name, true, false)
	if b == null or not b is Button:
		return false
	(b as Button).pressed.emit()
	return true


static func _fresh(wp) -> void:
	wp._sig = ""
	wp.refresh()


func _panel(tree: SceneTree) -> Array:
	var p: Array = []
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null or not ui.model.scenarios.has("shift_aged"):
		main.free()
		return ["the app or its aged scenario (shift_aged) did not start"]
	ui.player.set_physics_process(false)
	var sc: Dictionary = ui.model.scenarios["shift_aged"].duplicate(true)
	sc["id"] = "test_workorders"
	sc["start"] = {"day": 1, "time": "06:30"}
	ui.model.scenarios["test_workorders"] = sc
	ui.start_shift("test_workorders")
	await tree.process_frame
	ui.clock.set_speed(SimClock.Speed.PAUSED)
	var e = ui.clock.engine
	var wp = ui.work_orders
	if ui.me() != null or e.m.wo_doc == null:
		main.free()
		return ["the run should be in free mode with workorders.json (me %s)" % str(ui.me())]
	# the card offers it where works or past orders are, and not elsewhere
	if wp.has_orders(NOTHING):
		p.append("%s has no works and no past orders: its card should not offer Work orders" % NOTHING)
	ui.open_card(NOTHING)
	await tree.process_frame
	if ui.card.body.find_child("work_orders", true, false) != null:
		p.append("%s's card offers Work orders" % NOTHING)
	ui.open_card(MOTOR)
	await tree.process_frame
	if not _press(ui.card.body, "work_orders"):
		main.free()
		return p + ["no Work orders on %s's card: %s" % [MOTOR, App.texts(ui.card).left(400)]]
	if not wp.is_open() or ui.card.visible or wp.code != MOTOR:
		p.append("the work order panel did not open in the card's place at the motor")
	var past := 0
	for h in e.m.wo_doc["history"]:
		if h["kks"] == MOTOR:
			past += 1
	var txt: String = App.texts(wp)
	if past == 0 or txt.count("days before the run") != past:
		p.append("the motor's view should list its %d past orders: %s" % [past, txt.left(500)])
	# report the bearings' vibration: notified, matched to the bearings' work
	if not _press(wp.body, "report_vibration"):
		main.free()
		return p + ["no Report a finding: vibration at the motor: %s" % txt.left(500)]
	ui.clock.run_steps(2)
	await tree.process_frame
	if int(e.wo.get("wo_ccw_a_brg", 0)) != 1 or Wo.record_of(e, "wo_ccw_a_brg")[0] != "WO-0001":
		p.append("the vibration should have notified the bearings' work as WO-0001: %s" % str(e.wo))
	if not wp.last_text.contains("notified"):
		p.append("the result in words: %s" % wp.last_text)
	_fresh(wp)
	var again = wp.body.find_child("report_vibration", true, false)
	if again == null or not (again as Button).text.contains("already notified"):
		p.append("a second vibration report should say it is already notified")
	# the list, the form: planned urgent, scheduled today, then cancelled
	_press(wp.body, "to_list")
	_fresh(wp)
	txt = App.texts(wp)
	if not txt.contains("Backlog: 1 open order, 8 planned crew hours") or wp.body.find_child("open_wo_ccw_a_brg", true, false) == null:
		p.append("the list should show the one open order and its 8 hours: %s" % txt.left(400))
	_press(wp.body, "open_wo_ccw_a_brg")
	_fresh(wp)
	if not _press(wp.body, "plan_2"):
		p.append("no Urgent in the notified order's form: %s" % App.texts(wp).left(400))
	ui.clock.run_steps(2)
	_fresh(wp)
	if not _press(wp.body, "schedule_0"):
		p.append("no Today in the planned order's form: %s" % App.texts(wp).left(400))
	ui.clock.run_steps(2)
	var rec: Array = Wo.record_of(e, "wo_ccw_a_brg")
	if int(e.wo["wo_ccw_a_brg"]) != 3 or int(rec[4]) != 2 or int(rec[5]) != int(e.clock() / Wo.DAY):
		p.append("the order should be scheduled for today, urgent: %s" % str(rec))
	_fresh(wp)
	if not App.texts(wp).contains("Priority: Urgent"):
		p.append("the form should say its priority")
	_press(wp.body, "cancel")
	ui.clock.run_steps(2)
	await tree.process_frame
	if int(e.wo["wo_ccw_a_brg"]) != 7 or e.wo_history.size() != 1:
		p.append("the order should be cancelled into the run's history: %s, %s" % [str(e.wo), str(e.wo_history)])
	_press(wp.body, "to_list")
	_fresh(wp)
	if not App.texts(wp).contains("WO-0001  Closed cooling water pump A: replace the motor bearings: cancelled"):
		p.append("the list's closed orders: %s" % App.texts(wp).left(600))
	wp.open_for_code(MOTOR)
	_fresh(wp)
	if not App.texts(wp).contains("WO-0001"):
		p.append("the motor's history should hold the run's cancelled order")
	# transmitter 2's calibration: in progress by itself at the accept, completed after the done
	ui.inputs.work_order(CAL, "notify", null, ["reading"])
	ui.clock.run_steps(1)
	for a in ["request", "approve"]:
		ui.inputs.permit(CAL, a, null)
		ui.clock.run_steps(1)
	ui.inputs.lock(CAL, 0, null)
	ui.clock.run_steps(1)
	for a in ["issue", "accept"]:
		ui.inputs.permit(CAL, a, null)
		ui.clock.run_steps(1)
	if int(e.wo[CAL]) != 4:
		main.free()
		return p + ["the calibration's order should be in progress after the accept: %s, permit %d" % [str(e.wo[CAL]),
				int(e.pstate[e.m.work_ix[CAL]])]]
	wp.open(CAL)
	_fresh(wp)
	var picks := {"pick_modes": "reading", "pick_causes": "out_of_adjust", "pick_actions": "replace"}
	for k in picks:
		var ob = wp.body.find_child(k, true, false)
		if ob == null:
			p.append("no %s in the completion" % k)
			continue
		var items: Array = e.m.wo_doc[k.substr(5)]
		var idx := -1
		for i in items.size():
			if items[i]["id"] == picks[k]:
				idx = i + 1
		(ob as OptionButton).select(idx)
		(ob as OptionButton).item_selected.emit(idx)
	var ce = wp.body.find_child("comment", true, false)
	if ce != null:
		(ce as LineEdit).text = "Zero and span reset"
		(ce as LineEdit).text_changed.emit("Zero and span reset")
	_press(wp.body, "complete")
	ui.clock.run_steps(2)
	await tree.process_frame
	if int(e.wo[CAL]) != 4 or not wp.last_text.contains("permit is not done"):
		p.append("completing before the done should be refused in words: %s" % wp.last_text)
	ui.inputs.permit(CAL, "done", null)
	ui.clock.run_steps(1)
	_fresh(wp)
	_press(wp.body, "complete")
	ui.clock.run_steps(2)
	rec = Wo.record_of(e, CAL)
	if int(e.wo[CAL]) != 5 or Array(rec[7]) != ["reading", "out_of_adjust", "replace"] or rec[8] != "Zero and span reset":
		p.append("the calibration should be complete with the chosen codes: %s" % str(rec))
	var lines: PackedStringArray = Wo.debrief_lines(e, null)
	var joined := "\n".join(lines)
	if not joined.contains("Work orders: 2 raised, 0 closed") or not joined.contains("the job's own coding: Abnormal instrument reading, Out of adjustment, Adjust"):
		p.append("the debrief's work order lines: %s" % joined)
	main.free()
	return p
