## Repairs and a motor valve's handwheel (docs/PLANT3D.md §7.8, FIRST-TRAIN §4 "As built"):
## - the instructor applies a fault and repairs it from the panel; the repaired fault can be applied again;
## - a fault is repaired by the trainee at its equipment (the card offers it within reach only, while it is applied);
## - a CW discharge valve whose actuator has lost its supply is opened by its handwheel at the valve, slowly, and stopped
##   where it is; refused while the supply is there;
## - the debrief lists the repairs and the handwheel's operations; a run saved with a repair waiting is accepted.
extends RefCounted

const App = preload("res://tests/ui_app.gd")


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
	# 2. at the equipment: CW pump A's motor fails; its card offers the repair within reach only
	ui.fault("cw_a_motor")
	ui.clock.run_steps(1)
	ui.go_control_room()
	ui.open_card("30PAC10AP001")
	var rp: Array = ui.card._repairs[0] if not ui.card._repairs.is_empty() else []
	if rp.is_empty() or not (rp[1] as Control).visible or not (rp[2] as Button).disabled \
			or not (rp[3] as Label).text.contains("At the equipment only"):
		p.append("the pump's card in the control room does not show its repair as at the equipment only")
	else:
		ui.player.global_position = ui.index.center("30PAC10AP001") + Vector3(0, 0, 3)
		ui.card.refresh()
		if not ui.near("30PAC10AP001") or (rp[2] as Button).disabled:
			p.append("beside the pump (%.1f m) its repair is not offered" % ui.distance_to("30PAC10AP001"))
		(rp[2] as Button).pressed.emit()
		# a run saved with the repair waiting is accepted (a queued repair is an input of the run)
		var why: String = ui.autosave.check(ui.autosave.payload())
		if why != "":
			p.append("a run saved with a repair waiting was refused: %s" % why)
		ui.clock.run_steps(1)
		ui.card.refresh()
		if e.v("cw_a_fault") != 0.0 or (rp[1] as Control).visible:
			p.append("the repair at the pump did not repair it, or is still offered (fault %s)" % e.v("cw_a_fault"))
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
