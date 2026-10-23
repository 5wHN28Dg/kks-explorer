## Repairs and a motor valve's handwheel (docs/PLANT3D.md §7.8, FIRST-TRAIN §4 "As built"):
## - the instructor applies a fault and repairs it from the panel; the repaired fault can be applied again;
## - a fault is repaired by the trainee at its equipment under its work's permit (§15.5): the card shows it while it is
##   applied, and offers it only within reach with the permit accepted (its isolation in place); the work's done then
##   repairs nothing; a run saved with that repair waiting is accepted;
## - a CW discharge valve whose actuator has lost its supply is opened by its handwheel at the valve, slowly, and stopped
##   where it is; refused while the supply is there;
## - the debrief lists the repairs and the handwheel's operations; a run saved with a repair waiting is accepted.
extends RefCounted

const App = preload("res://tests/ui_app.gd")
const RunSave = preload("res://ui/run_save.gd")

const PUMP_A := "30PAC10AP001"
const VALVE_A := "30PAC10AA101"
const WORK_A := "wo_cw_a_motor"


## A permit action pressed on the form, then a step: the failures.
static func _do(ui, pm, action: String) -> Array:
	pm.refresh()
	var b: Button = pm.body.find_child("do_" + action, true, false)
	if b == null or b.disabled:
		return ["the permit form offers no %s: %s" % [action, App.texts(pm.body).left(300)]]
	b.pressed.emit()
	ui.clock.run_steps(1)
	pm.refresh()
	return []


static func _row(panel, text: String) -> HBoxContainer:
	for r in panel.body.get_children():
		if r is HBoxContainer and App.texts(r).contains(text):
			return r
	return null


static func _button(row: Node) -> Button:
	for c in row.get_children():
		if c is Button:
			return c
	return null


func run(tree: SceneTree) -> Array:
	var p: Array = []
	var main := App.start(tree)
	var ui = main.ui
	if ui == null or ui.clock == null:
		main.free()
		return ["the interaction layer did not start"]
	await tree.process_frame
	var e = ui.clock.engine
	# 1. the instructor's panel: apply, repair, apply again
	ui.set_instructor(true)
	ui.toggle_trainer()
	var fault_text := "CW pump B motor overload"
	var row := _row(ui.trainer, fault_text)
	if row == null or _button(row).text != "Apply":
		p.append("the instructor's panel has no Apply for %s" % fault_text)
	else:
		_button(row).pressed.emit()
		ui.clock.run_steps(1)
		ui.trainer.refresh()
		row = _row(ui.trainer, fault_text)
		if e.v("cw_b_fault") != 1.0 or _button(row).text != "Repair":
			p.append("after the fault the panel offers %s (fault %s)" % [_button(row).text, e.v("cw_b_fault")])
		_button(row).pressed.emit()
		ui.clock.run_steps(1)
		ui.trainer.refresh()
		row = _row(ui.trainer, fault_text)
		if e.v("cw_b_fault") != 0.0 or not e.events.any(func(ev): return ev[1] == "repair" and ev[2] == "cw_b_motor"):
			p.append("the panel's Repair did not repair the motor (fault %s)" % e.v("cw_b_fault"))
		if _button(row).text != "Apply again" or _button(row).disabled:
			p.append("a repaired fault can't be applied again: %s" % _button(row).text)
	ui.toggle_trainer()
	# 2. at the equipment, under a permit to work (§15.5, the user's decision of 2026-10-23): CW pump A's motor fails;
	# its card shows the repair (none before) but offers it only under the work's permit, accepted, within reach
	ui.go_control_room()
	ui.open_card(PUMP_A)
	if ui.card._repairs.is_empty() or (ui.card._repairs[0][1] as Control).visible:
		p.append("the pump's card offers a repair while nothing is wrong with it")
	ui.fault("cw_a_motor")
	ui.clock.run_steps(1)
	ui.player.global_position = ui.index.center(PUMP_A) + Vector3(0, 0, 3)
	ui.open_card(PUMP_A)
	var rp: Array = ui.card._repairs[0] if not ui.card._repairs.is_empty() else []
	if rp.is_empty() or not (rp[1] as Control).visible or not (rp[2] as Button).disabled \
			or not (rp[3] as Label).text.contains("Under its permit to work only"):
		p.append("beside the pump its repair is offered without a permit: %s" % App.texts(ui.card).left(300))
	# the permit: requested, approved, both points locked at the equipment, issued; still not offered until accepted
	var pm = ui.permits
	ui.open_permits(WORK_A)
	for a in ["request", "approve"]:
		p.append_array(_do(ui, pm, a))
	for k in 2:
		var code: String = [PUMP_A, VALVE_A][k]
		ui.player.global_position = ui.index.center(code) + Vector3(0, 0, 3)
		pm.refresh()
		var lb: Button = pm.body.find_child("lock_%d" % k, true, false)
		if lb == null or lb.disabled:
			p.append("beside %s the permit form offers no lock" % code)
			continue
		lb.pressed.emit()
		if not await App.lock_checked(tree, pm) or not pm.check.is_empty():
			p.append("beside %s the lock was not sent after its check" % code)
		ui.clock.run_steps(1)
		pm.refresh()
	p.append_array(_do(ui, pm, "issue"))
	ui.player.global_position = ui.index.center(PUMP_A) + Vector3(0, 0, 3)
	ui.card.refresh()
	if rp.is_empty() or not (rp[2] as Button).disabled:
		p.append("the repair is offered with the permit only issued")
	p.append_array(_do(ui, pm, "accept"))
	ui.card.refresh()
	if not rp.is_empty():
		if (rp[2] as Button).disabled:
			p.append("with the permit accepted, beside the pump, its repair is not offered: %s" % (rp[3] as Label).text)
		(rp[2] as Button).pressed.emit()
		if not (rp[2] as Button).disabled:
			p.append("the card's Repair can be pressed again before the step takes it (a second input)")
		if not e.queue.has(["repair", "cw_a_motor", WORK_A, null]):
			p.append("the card sent no repair under the permit: %s" % str(e.queue))
		# a run saved with the repair waiting is accepted (a queued repair is an input of the run), and put back
		var saved: Dictionary = ui.autosave.payload()
		var why: String = ui.autosave.check(saved)
		if why != "":
			p.append("a run saved with a repair under a permit waiting was refused: %s" % why)
		var dec: Dictionary = RunSave.decode(RunSave.encode(saved))
		if not dec.get("ok", false) or ui.autosave.check(dec["payload"]) != "":
			p.append("the saved run with the repair waiting did not come back")
		ui.clock.run_steps(1)
		ui.card.refresh()
		if e.v("cw_a_fault") != 0.0 or (rp[1] as Control).visible:
			p.append("the repair at the locked-out pump did not repair it, or is still offered (fault %s)" % e.v("cw_a_fault"))
	# the work done finds it repaired (no second repair); handed back, the locks off, closed
	p.append_array(_do(ui, pm, "done"))
	p.append_array(_do(ui, pm, "return"))
	for k in 2:
		ui.player.global_position = ui.index.center([PUMP_A, VALVE_A][k]) + Vector3(0, 0, 3)
		pm.refresh()
		var ub: Button = pm.body.find_child("unlock_%d" % k, true, false)
		if ub == null or ub.disabled:
			p.append("the permit form offers no unlock of point %d" % k)
			continue
		ub.pressed.emit()
		ui.clock.run_steps(1)
		pm.refresh()
	p.append_array(_do(ui, pm, "close"))
	ui.close_permits()
	if e.events.filter(func(ev): return ev[1] == "repair" and ev.size() == 3 and ev[2] == "cw_a_motor").size() != 1:
		p.append("CW pump A's motor was repaired other than once: %s" % str(e.events.filter(func(ev): return ev[1] == "repair")))
	if e.pstate[e.m.work_ix[WORK_A]] != 9:
		p.append("CW pump A's permit did not close (%d)" % e.pstate[e.m.work_ix[WORK_A]])
	# 3. the handwheel: refused while the actuator has its supply; with the supply lost, it opens the valve slowly
	ui.player.global_position = ui.index.center("30PAC10AA101") + Vector3(0, 0, 3)
	ui.open_card("30PAC10AA101")
	var hrow := App.op_row(ui.card, "30PAC10AA101", "hand_open")
	if hrow.is_empty() or (hrow[1] as Button).text != "Open by handwheel":
		p.append("the valve's card has no Open by handwheel")
		main.free()
		return p
	(hrow[1] as Button).pressed.emit()
	ui.clock.run_steps(1)
	var txt: String = ui.op_result(hrow[0]).get("text", "")
	if not txt.contains("The actuator has its supply"):
		p.append("the handwheel with the supply there came back: %s" % txt)
	ui.fault("cw_valve_power")
	ui.clock.run_steps(1)
	(hrow[1] as Button).pressed.emit()
	ui.clock.run_steps(600)            # a minute of turning: a fifth of the travel (the motor would take a minute for it all)
	var pos: float = e.v("cw_a_v_pos")
	if pos < 0.18 or pos > 0.22:
		p.append("a minute at the handwheel opened the valve to %.3f (want about 0.2)" % pos)
	var srow := App.op_row(ui.card, "30PAC10AA101", "hand_stop")
	(srow[1] as Button).pressed.emit()
	ui.clock.run_steps(100)
	if absf(e.v("cw_a_v_pos") - pos) > 0.01 or ui.op_result(srow[0]).get("state", "") != "done":
		p.append("Stop turning did not hold the valve where it was (%.3f, then %.3f)" % [pos, e.v("cw_a_v_pos")])
	# 4. the debrief lists the repairs and the handwheel
	var Debrief = load("res://ui/debrief.gd")
	var d: Dictionary = Debrief.collect(e, ui.info, null)
	var texts: Array = d.entries.map(func(x): return x.text)
	for want in ["Repaired: CW pump B motor overload", "Repaired: CW pump A motor overload", "Open by handwheel",
			"Stop turning"]:
		if not texts.any(func(t): return String(t).contains(want)):
			p.append("the debrief does not list %s" % want)
	if d.summary.repairs != 2:
		p.append("the debrief counts %d repairs, not 2" % d.summary.repairs)
	main.free()
	return p
